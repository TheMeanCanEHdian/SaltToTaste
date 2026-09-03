// Upgrading a POPULATED database — the one code path every real deployment
// takes, and the one the rest of the suite never exercises: every other
// migration test starts from an empty file, so migration 007's `json_each`
// backfill and migration 008's Dart-side FTS reindex have never run over rows.
//
// The harness is a generic prefix loop: for each start version V in
// 1..migrations.length it builds a raw SQLite database carrying exactly the
// schema that shipped at version V, seeds it with real ATK corpus data written
// against that old shape, then hands the file to `SaltDatabase.open` (which
// migrates) and asserts nothing was lost and every data transform landed.
//
// The loop is driven by `migrations.length`, so a future migration 009 gets a
// populated-upgrade run for free. The one thing that must be maintained by hand
// is [_capabilityByVersion] — what each version's schema can hold — and the
// first test in this file fails loudly when it falls behind.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:salt_server/src/auth/password_hasher.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_server/src/services/serves_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// What each schema version can hold, keyed by the `PRAGMA user_version` at
/// which it first exists. The seeder consults this so it only ever writes
/// columns and tables that existed at the version it is impersonating.
///
/// **Append an entry whenever a migration lands** — the first test below
/// fails loudly if `migrations.length` outgrows this map, because a silent
/// skip would mean the new migration never gets a populated-upgrade run.
const Map<int, String> _capabilityByVersion = {
  1:
      'sources, recipes, recipe_ingredients, tags, recipe_tags, settings, '
      'import_jobs, recipe_fts (narrow: top-level text only)',
  2: 'users, sessions, api_tokens',
  3: 'tag_styles',
  4: 'user_favorites, user_notes',
  5:
      'fdc_search_cache, fdc_food_cache, ingredient_matches, '
      'recipe_nutrition, nutrition_jobs',
  6: 'import_jobs.legacy / .imported / .updated',
  7: 'recipes.variation_count (backfilled by 007)',
  8:
      'recipe_fts widened to subsection + technique text (reindexed in Dart '
      'by SaltDatabase._migrate, keyed on the fts.widened_v8 settings marker)',
};

/// Mirror of the private `SaltDatabase._ftsWideningVersion`: a database whose
/// start version is below this gets its FTS rows re-derived in Dart on open.
/// Kept as a literal on purpose — the point of the assertions below is to pin
/// the production value, so reading it from production would prove nothing.
const int _ftsWideningVersion = 8;

/// The migration that added `recipes.variation_count` and backfilled it. From
/// this start version on, the seed already carries the column, so the
/// post-upgrade check is preservation rather than backfill (see below).
const int _variationCountVersion = 7;

const String _sourceSlug = 'atk-tv-2023';

/// The corpus's own `source.yaml` identity, verbatim.
const String _sourceName =
    "The Complete America's Test Kitchen TV Show Cookbook 2001–2023";
const Map<String, Object?> _sourceMeta = {'isbn': '9781954210110'};

/// Value of the seeded [SaltDatabase.ftsWidenedSetting] row for a healthy v8.
const String _ftsWidenedValue = '2026-07-16T02:11:15.000Z';

/// Value of the seeded [servesBackfillSetting] row — the completion timestamp
/// the backfill records. Compared byte-exact after the upgrade: corrupt this
/// marker and the once-per-database backfill re-runs over a live library.
final String _servesBackfillValue = DateTime.utc(
  2026,
  3,
  4,
  5,
  6,
  7,
).toIso8601String();

/// Corpus recipes chosen to cover all three shapes migration 007 must handle,
/// plus the technique text migration 008 also widens the index to. Their
/// subsection/variation/technique content is verified from the real files in
/// the first corpus-backed test — nothing here is assumed from the filename.

/// Subsections that are all `kind: variation`, carry their own ingredient
/// lines (invisible to a pre-008 narrow FTS row), and a non-empty `tags` list
/// so the `tag_styles` seed can point at a tag that really exists.
const String _withVariations = '0859-marbled-blueberry-bundt-cake.yaml';

/// 1 subsection, `kind: component` — the "has subsections, zero variations"
/// case, which the backfill must count as 0 rather than as 1.
const String _subsectionsNoVariations = '0093-cuban-style-picadillo.yaml';

/// No subsections at all — the backfill's zero case. Also the recipe the
/// recorded real FDC payloads in `test/fixtures/fdc/` were captured against,
/// so the seeded nutrition rows can be real engine output (see
/// [_captureNutritionRows]) instead of invented values.
const String _noSubsections = '0857-rich-chocolate-bundt-cake.yaml';

/// Non-empty `techniques` — the other half of what migration 008 widens the
/// FTS row to (step captions fold into `directions`, heading/description into
/// `background`). 221 of the 1,198 corpus recipes carry techniques.
const String _withTechniques = '0292-new-england-lobster-roll.yaml';

/// Words of five or more letters, lowercased — the candidate pool the
/// tracer terms are drawn from.
Iterable<String> _words(String text) =>
    RegExp('[a-z]{5,}').allMatches(text.toLowerCase()).map((m) => m.group(0)!);

/// The text a **pre-008** FTS row could see for [recipe] — exactly the fields
/// `_rebuildFts` indexed before the widening (`git show 11f9dc7~1`): title,
/// category, tags, TOP-LEVEL ingredients and steps, notes, background and
/// prep notes. No subsection text and **no technique text**; both are what
/// 008 adds. Used to propose candidate tracer terms; the term is then
/// confirmed empirically against the seeded FTS table so the real
/// tokenizer/stemmer has the last word.
Set<String> _topLevelWords(Recipe recipe) => {
  ..._words(recipe.title),
  ..._words(recipe.category ?? ''),
  for (final tag in recipe.tags) ..._words(tag),
  for (final group in recipe.ingredients)
    for (final line in group.items) ..._words(line.raw),
  for (final step in recipe.steps) ..._words(step.text),
  ..._words(recipe.notes ?? ''),
  ..._words(recipe.background ?? ''),
  ..._words(recipe.prepNotes ?? ''),
};

/// Words reachable only through [recipe]'s subsections — exactly the text
/// migration 008 adds to the index.
Set<String> _subsectionWords(Recipe recipe) => {
  for (final sub in recipe.subsections) ...[
    ..._words(sub.title ?? ''),
    ..._words(sub.body ?? ''),
    for (final group in sub.ingredients ?? const <IngredientGroup>[])
      for (final line in group.items) ..._words(line.raw),
    for (final step in sub.steps ?? const <RecipeStep>[]) ..._words(step.text),
  ],
};

/// Words in [recipe]'s technique STEP CAPTIONS — one of the two technique
/// paths migration 008 opens: `_rebuildFts` folds these into `directions`.
Set<String> _techniqueCaptionWords(Recipe recipe) => {
  for (final technique in recipe.techniques)
    for (final step in technique.steps) ..._words(step.caption),
};

/// Words in [recipe]'s technique HEADINGS and DESCRIPTIONS — the other
/// technique path: `_rebuildFts` folds these into `background`.
Set<String> _techniqueProseWords(Recipe recipe) => {
  for (final technique in recipe.techniques) ...[
    ..._words(technique.heading ?? ''),
    ..._words(technique.description ?? ''),
  ],
};

/// All technique text — the half of the 008 widening that no subsection
/// carries.
Set<String> _techniqueWords(Recipe recipe) => {
  ..._techniqueCaptionWords(recipe),
  ..._techniqueProseWords(recipe),
};

/// Number of `variation` subsections in [recipe], derived from the real
/// document exactly the way migration 007's SQL and `upsertRecipe` both
/// define it. Never hardcoded on either side of an assertion.
int _variationCount(Recipe recipe) =>
    recipe.subsections.where((sub) => sub.kind == 'variation').length;

/// Applies `migrations[0 .. version-1]` statement by statement and stamps
/// `PRAGMA user_version`, reproducing the schema as it shipped at [version].
void _applyPrefix(Database raw, int version) {
  for (var index = 0; index < version; index += 1) {
    for (final statement in migrations[index]) {
      raw.execute(statement);
    }
  }
  raw.execute('PRAGMA user_version = $version');
}

/// The nutrition tables migration 005 adds, each with the column that gives a
/// deterministic read order, so captured rows and post-upgrade rows line up.
/// Migrations 006–008 never touch them, so a row captured at head is exactly
/// the row a v5 deployment holds.
const Map<String, String> _nutritionTables = {
  'fdc_search_cache': 'query',
  'fdc_food_cache': 'fdc_id',
  'ingredient_matches': 'position',
  'recipe_nutrition': 'recipe_id',
};

/// Every nutrition row the REAL engine writes for [recipe] when it runs
/// against the RECORDED REAL USDA payloads in `test/fixtures/fdc/` — the same
/// fixtures `nutrition_engine_test.dart` computes its label from.
///
/// Nutrition values have no corpus counterpart (they come from the FDC API),
/// so they are captured from production code over recorded real responses
/// rather than invented: what gets seeded below is byte-for-byte what a real
/// deployment holds before the upgrade, down to FDC's own `data_type`
/// spelling.
Future<Map<String, List<Map<String, Object?>>>> _captureNutritionRows(
  Recipe recipe,
) async {
  final dir = Directory.systemTemp.createTempSync('salt_migr_nutrition');
  final path = '${dir.path}/salt.db';
  try {
    final db = SaltDatabase.open(path)
      ..upsertSource(
        slug: _sourceSlug,
        name: _sourceName,
        type: 'epub',
        meta: _sourceMeta,
      )
      ..upsertRecipe(
        recipe,
        sourceSlug: _sourceSlug,
        contentHash: contentHashOf(recipe),
      );
    await matchAndCompute(db, FixtureProvider(), recipe);
    db.dispose();

    final raw = sqlite3.open(path);
    final captured = {
      for (final entry in _nutritionTables.entries)
        entry.key: [
          for (final row in raw.select(
            // Both names are literals from [_nutritionTables], never input.
            'SELECT * FROM ${entry.key} ORDER BY ${entry.value}',
          ))
            {for (final column in row.keys) column: row[column] as Object?},
        ],
    };
    raw.dispose();
    return captured;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Writes [rows] back into [table] verbatim, column for column.
void _replay(Database raw, String table, List<Map<String, Object?>> rows) {
  for (final row in rows) {
    final columns = row.keys.toList();
    raw.execute(
      // `table` is a literal from [_nutritionTables]; the column names come
      // from the schema itself. Neither is external input.
      'INSERT INTO $table (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      [for (final column in columns) row[column]],
    );
  }
}

/// Everything the seeder wrote, so the post-upgrade assertions compare against
/// the exact bytes that went in rather than against a recomputed guess.
class _Seed {
  _Seed({
    required this.docs,
    required this.hashes,
    required this.ingredientCounts,
    required this.tagNames,
    required this.styledTag,
    required this.sessionTokenHash,
    required this.patTokenHash,
    required this.passwordHash,
    required this.noteBody,
  });

  final Map<String, String> docs;
  final Map<String, String> hashes;
  final Map<String, int> ingredientCounts;
  final Map<String, List<String>> tagNames;
  final String styledTag;
  final String sessionTokenHash;
  final String patTokenHash;
  final String passwordHash;
  final String noteBody;
}

/// Writes the pre-008 **narrow** FTS row for [recipe] — top-level text only,
/// a verbatim reproduction of `_rebuildFts` as it stood before migration 008
/// (`git show 11f9dc7~1:apps/server/lib/src/db/salt_database.dart`). Seeding
/// the widened content here would make the reindex assertion vacuous.
void _seedNarrowFts(Database raw, Recipe recipe, int rowid) {
  final tags = [for (final tag in recipe.tags) tag.toLowerCase().trim()].join(
    ' ',
  );
  final ingredients = [
    for (final group in recipe.ingredients)
      for (final line in group.items) line.raw,
  ].join('\n');
  final directions = [for (final step in recipe.steps) step.text].join('\n');
  raw.execute(
    'INSERT INTO recipe_fts '
    '(rowid, recipe_id, title, category, tags, ingredients, directions, '
    'notes, background, prep_notes) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
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
    ],
  );
}

/// Seeds a raw connection sitting at [version] with real corpus recipes plus
/// every side table that exists at that version.
_Seed _seed(
  Database raw,
  int version,
  List<Recipe> recipes, {
  required String passwordHash,
  required String sessionToken,
  required String patToken,
  required Map<String, List<Map<String, Object?>>> nutritionRows,
}) {
  raw.execute(
    'INSERT INTO sources (slug, name, type, meta) VALUES (?, ?, ?, ?)',
    [_sourceSlug, _sourceName, 'epub', jsonEncode(_sourceMeta)],
  );

  final docs = <String, String>{};
  final hashes = <String, String>{};
  final ingredientCounts = <String, int>{};
  final tagNames = <String, List<String>>{};
  final hasVariationCount = version >= _variationCountVersion;

  for (final recipe in recipes) {
    // Exactly what upsertRecipe persists: the mapped document as JSON, and
    // the SHA-256 of the canonical v2 YAML.
    final doc = jsonEncode(recipe.toMap());
    final hash = contentHashOf(recipe);
    docs[recipe.id] = doc;
    hashes[recipe.id] = hash;

    final columns = [
      'id',
      'slug',
      'source_slug',
      'title',
      'category',
      'servings_text',
      'serves_min',
      'serves_max',
      'prep_min',
      'cook_min',
      'total_min',
      'hero_image',
      if (hasVariationCount) 'variation_count',
      'doc',
      'content_hash',
    ];
    final values = <Object?>[
      recipe.id,
      recipe.slug,
      _sourceSlug,
      recipe.title,
      recipe.category,
      recipe.servings,
      recipe.serves?.min,
      recipe.serves?.max,
      recipe.times.prep,
      recipe.times.cook,
      recipe.times.total,
      recipe.images.hero,
      // A deployment already past 007 carries the correct count; the upgrade
      // must leave it alone rather than re-running the backfill.
      if (hasVariationCount) _variationCount(recipe),
      doc,
      hash,
    ];
    raw.execute(
      'INSERT INTO recipes (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      values,
    );

    var position = 0;
    for (final group in recipe.ingredients) {
      for (final line in group.items) {
        raw.execute(
          'INSERT INTO recipe_ingredients '
          '(recipe_id, position, group_name, raw, item, prep, amounts) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            recipe.id,
            position,
            group.group,
            line.raw,
            line.item,
            line.prep,
            jsonEncode([for (final amount in line.amounts) amount.toMap()]),
          ],
        );
        position += 1;
      }
    }
    ingredientCounts[recipe.id] = position;

    final names = <String>[];
    for (final tag in recipe.tags) {
      final name = tag.toLowerCase().trim();
      if (name.isEmpty || names.contains(name)) {
        continue;
      }
      names.add(name);
      raw.execute('INSERT OR IGNORE INTO tags (name) VALUES (?)', [name]);
      final tagId =
          raw.select('SELECT id FROM tags WHERE name = ?', [
                name,
              ]).first['id']
              as int;
      raw.execute(
        'INSERT OR IGNORE INTO recipe_tags (recipe_id, tag_id) VALUES (?, ?)',
        [recipe.id, tagId],
      );
    }
    names.sort();
    tagNames[recipe.id] = names;

    final rowid =
        raw.select('SELECT rowid FROM recipes WHERE id = ?', [
              recipe.id,
            ]).first['rowid']
            as int;
    _seedNarrowFts(raw, recipe, rowid);
  }

  // A real settings row (the serves backfill's once-per-database guard). The
  // key comes from production so renaming the constant cannot leave this test
  // seeding something nothing reads.
  raw.execute('INSERT INTO settings (key, value) VALUES (?, ?)', [
    servesBackfillSetting,
    _servesBackfillValue,
  ]);
  // A deployment that reached v8 the normal way completed its FTS reindex
  // and holds the marker. Seeding it is what makes the at-head case below a
  // real "healthy database" and not the stuck one (v8, narrow rows, no
  // marker) that the self-heal test seeds on purpose.
  if (version >= _ftsWideningVersion) {
    raw.execute('INSERT INTO settings (key, value) VALUES (?, ?)', [
      SaltDatabase.ftsWidenedSetting,
      _ftsWidenedValue,
    ]);
  }

  // import_jobs exists from 001; 006 adds three counters.
  final jobColumns = [
    'status',
    'source_path',
    'total',
    'done',
    'skipped',
    'failed',
    'log',
    if (version >= 6) ...['legacy', 'imported', 'updated'],
  ];
  final jobValues = <Object?>[
    'done',
    corpusRoot,
    recipes.length,
    recipes.length,
    0,
    0,
    jsonEncode(['imported ${recipes.length} recipes']),
    if (version >= 6) ...[0, recipes.length, 0],
  ];
  raw.execute(
    'INSERT INTO import_jobs (${jobColumns.join(', ')}) '
    'VALUES (${List.filled(jobColumns.length, '?').join(', ')})',
    jobValues,
  );

  final noteBody = recipes.first.notes ?? recipes.first.title;
  if (version >= 2) {
    raw
      ..execute(
        'INSERT INTO users (username, password_hash, role, '
        'must_change_password, disabled) VALUES (?, ?, ?, ?, ?)',
        ['admin', passwordHash, 'admin', 1, 0],
      )
      ..execute(
        'INSERT INTO sessions (token_hash, user_id, expires_at, remember, '
        'user_agent) VALUES (?, ?, ?, ?, ?)',
        [
          hashToken(sessionToken),
          1,
          DateTime.utc(2030).toIso8601String(),
          1,
          'salt-migration-test',
        ],
      )
      ..execute(
        'INSERT INTO api_tokens (user_id, name, prefix, token_hash, scope) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          1,
          'kitchen tablet',
          patToken.substring(patMarker.length, patMarker.length + 12),
          hashToken(patToken),
          'read',
        ],
      );
  }
  final styledTag = tagNames.values
      .firstWhere(
        (names) => names.isNotEmpty,
        orElse: () => throw StateError(
          'none of the seeded corpus recipes carries a tag, so tag_styles '
          'cannot be seeded against real data — pick a tagged recipe',
        ),
      )
      .first;
  if (version >= 3) {
    // Style a tag that really exists on a seeded recipe.
    raw.execute(
      'INSERT INTO tag_styles (tag_name, icon, color, bg_color) '
      'VALUES (?, ?, ?, ?)',
      [styledTag, 'cake-slice', '#960000', '#f4e4e4'],
    );
  }
  if (version >= 4) {
    raw
      ..execute(
        'INSERT INTO user_favorites (user_id, recipe_id) VALUES (?, ?)',
        [1, recipes.first.id],
      )
      ..execute(
        'INSERT INTO user_notes (user_id, recipe_id, body) VALUES (?, ?, ?)',
        [1, recipes.first.id, noteBody],
      );
  }
  if (version >= 5) {
    // Real engine output over recorded real FDC payloads, replayed verbatim
    // (see [_captureNutritionRows]) — the rows a v5+ deployment really holds.
    for (final table in _nutritionTables.keys) {
      _replay(raw, table, nutritionRows[table]!);
    }
    // Job bookkeeping, not nutrition data: one completed run over one recipe.
    raw.execute(
      'INSERT INTO nutrition_jobs (status, total, done, failed, log) '
      'VALUES (?, ?, ?, ?, ?)',
      ['done', 1, 1, 0, jsonEncode(<String>[])],
    );
  }

  return _Seed(
    docs: docs,
    hashes: hashes,
    ingredientCounts: ingredientCounts,
    tagNames: tagNames,
    styledTag: styledTag,
    sessionTokenHash: hashToken(sessionToken),
    patTokenHash: hashToken(patToken),
    passwordHash: passwordHash,
    noteBody: noteBody,
  );
}

int _count(Database raw, String sql, [List<Object?> params = const []]) =>
    raw.select('SELECT COUNT(*) AS n FROM $sql', params).first['n'] as int;

/// Column names of [table] as the connection currently sees them.
List<String> _columnNames(Database raw, String table) => [
  // `table` is a literal from this file, never external input; PRAGMA does
  // not accept bound parameters.
  for (final row in raw.select('PRAGMA table_info($table)'))
    row['name'] as String,
];

void main() {
  // ---- Corpus-free: these must run in CI, which has no ATK corpus. ----

  test('the version -> capability table covers every shipped migration', () {
    expect(
      _capabilityByVersion.keys.toList()..sort(),
      [for (var v = 1; v <= migrations.length; v += 1) v],
      reason:
          'migrations.length is ${migrations.length} but _capabilityByVersion '
          'describes versions ${_capabilityByVersion.keys.toList()..sort()}. '
          'Add the new migration here (and teach _seed what it can hold) so '
          'the populated-upgrade loop covers it instead of silently skipping.',
    );
  });

  test('every migration prefix applies cleanly and then upgrades to head', () {
    for (var version = 1; version <= migrations.length; version += 1) {
      final dir = Directory.systemTemp.createTempSync('salt_migr_empty');
      final path = '${dir.path}/salt.db';
      try {
        final raw = sqlite3.open(path);
        _applyPrefix(raw, version);
        expect(
          raw.select('PRAGMA user_version').first.columnAt(0),
          version,
          reason: 'prefix of $version migrations should stamp version $version',
        );
        raw.dispose();

        SaltDatabase.open(path).dispose();

        final after = sqlite3.open(path);
        expect(
          after.select('PRAGMA user_version').first.columnAt(0),
          migrations.length,
          reason: 'opening a v$version database must migrate to head',
        );
        after.dispose();
      } finally {
        dir.deleteSync(recursive: true);
      }
    }
  });

  test('a fresh database is marked FTS-widened at its first open', () {
    // No rows to reindex, so the marker is written at once and every later
    // boot skips the pass. The MARKER is the key, not the start version: a
    // reindex keyed on "started below v8" ran exactly once, after the loop
    // had already committed version 8, so a single undecodable row made it
    // throw once and never run again.
    final dir = Directory.systemTemp.createTempSync('salt_migr_fresh');
    try {
      final db = SaltDatabase.open('${dir.path}/salt.db');
      expect(db.getSetting(SaltDatabase.ftsWidenedSetting), isNotNull);
      db.dispose();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // ---- Corpus-backed: the populated upgrade. ----

  group('populated upgrade from every shipped version', () {
    late Recipe withVariations;
    late Recipe subsectionsOnly;
    late Recipe plain;
    late Recipe withTechniques;
    late List<Recipe> recipes;
    late String passwordHash;
    late String sessionToken;
    late String patToken;
    late Map<String, List<Map<String, Object?>>> nutritionRows;

    setUpAll(() async {
      withVariations = loadCorpusRecipe(_withVariations);
      subsectionsOnly = loadCorpusRecipe(_subsectionsNoVariations);
      plain = loadCorpusRecipe(_noSubsections);
      withTechniques = loadCorpusRecipe(_withTechniques);
      recipes = [withVariations, subsectionsOnly, plain, withTechniques];
      // Real nutrition rows for the one seeded recipe the recorded FDC
      // fixtures were captured against.
      nutritionRows = await _captureNutritionRows(plain);
      // Real production credential material, so the rows that survive the
      // upgrade are the shapes production actually stores.
      passwordHash = await PasswordHasher(
        random: Random(20260728),
      ).hash('correct horse battery staple');
      sessionToken = generateOpaqueToken();
      patToken = generatePat().token;
    });

    test('the chosen corpus recipes cover the 007 shapes and 008 text', () {
      expect(
        _variationCount(withVariations),
        greaterThan(0),
        reason: '$_withVariations must carry variations',
      );
      expect(
        subsectionsOnly.subsections,
        isNotEmpty,
        reason: '$_subsectionsNoVariations must carry subsections',
      );
      expect(
        _variationCount(subsectionsOnly),
        0,
        reason: '$_subsectionsNoVariations must carry none of kind variation',
      );
      expect(
        plain.subsections,
        isEmpty,
        reason: '$_noSubsections must carry no subsections',
      );
      expect(
        _subsectionWords(withVariations).difference(
          _topLevelWords(withVariations),
        ),
        isNotEmpty,
        reason: 'the 008 assertion needs subsection-only vocabulary',
      );
      expect(
        withTechniques.techniques,
        isNotEmpty,
        reason:
            '$_withTechniques must carry techniques — the other half of the '
            '008 widening, which no other seeded recipe exercises',
      );
      final elsewhere = {
        for (final recipe in recipes) ...[
          ..._topLevelWords(recipe),
          ..._subsectionWords(recipe),
        ],
      };
      expect(
        _techniqueWords(withTechniques).difference(elsewhere),
        isNotEmpty,
        reason:
            'the 008 technique assertions need vocabulary reachable ONLY '
            'through technique text, so the subsection half of the widening '
            'cannot satisfy them',
      );
      expect(
        _techniqueCaptionWords(withTechniques)
            .difference(_techniqueProseWords(withTechniques))
            .difference(elsewhere),
        isNotEmpty,
        reason: 'the captions -> directions fold needs its own tracer pool',
      );
      expect(
        _techniqueProseWords(withTechniques)
            .difference(_techniqueCaptionWords(withTechniques))
            .difference(elsewhere),
        isNotEmpty,
        reason:
            'the heading/description -> background fold needs its own tracer '
            'pool',
      );
      expect(
        withVariations.tags,
        isNotEmpty,
        reason: 'tag_styles must be seeded against a tag that really exists',
      );
    });

    test('the seeded nutrition rows are real engine output over real FDC '
        'payloads', () {
      final matches = nutritionRows['ingredient_matches']!;
      final foods = {
        for (final row in nutritionRows['fdc_food_cache']!)
          row['fdc_id']! as int:
              jsonDecode(row['response']! as String) as Map<String, dynamic>,
      };
      final matched = [
        for (final row in matches)
          if (row['fdc_id'] != null) row,
      ];
      expect(
        matched,
        isNotEmpty,
        reason:
            'the recorded fixtures must still match ${plain.slug}, otherwise '
            'the seeded nutrition rows are empty ballast',
      );
      for (final row in matched) {
        final food = foods[row['fdc_id']! as int];
        expect(
          food,
          isNotNull,
          reason: 'every matched fdc_id must be in the captured food cache',
        );
        expect(
          row['data_type'],
          food!['data_type'],
          reason:
              "the stored data_type must be FDC's own spelling, straight "
              'from the recorded payload — never a made-up variant',
        );
      }
      expect(
        nutritionRows['recipe_nutrition'],
        hasLength(1),
        reason: 'the engine computes one totals row for the recipe',
      );
      expect(
        nutritionRows['recipe_nutrition']!.single['ingredients_hash'],
        ingredientsHashOf(plain),
        reason: 'the totals row must be keyed to the real corpus recipe',
      );
    });

    for (
      var startVersion = 1;
      startVersion <= migrations.length;
      startVersion += 1
    ) {
      final atHead = startVersion == migrations.length;
      final expectReindex = startVersion < _ftsWideningVersion;

      test('v$startVersion populated -> v${migrations.length}'
          '${atHead ? ' (no-op)' : ''}', () {
        final dir = Directory.systemTemp.createTempSync('salt_migr_pop');
        final path = '${dir.path}/salt.db';
        late _Seed seed;
        late String subsectionTerm;
        late String techniqueCaptionTerm;
        late String techniqueProseTerm;
        try {
          // --- build a real deployment sitting at startVersion ---
          final raw = sqlite3.open(path)..execute('PRAGMA foreign_keys = ON');
          _applyPrefix(raw, startVersion);
          seed = _seed(
            raw,
            startVersion,
            recipes,
            passwordHash: passwordHash,
            sessionToken: sessionToken,
            patToken: patToken,
            nutritionRows: nutritionRows,
          );

          /// Picks a term the seeded narrow index genuinely cannot find, out
          /// of [pool] — confirmed by running the real FTS matcher, so
          /// stemming and the other seeded recipes are accounted for rather
          /// than guessed at.
          String tracer(Set<String> pool, String what) {
            final candidates = pool.toList()..sort();
            return candidates.firstWhere(
              (word) =>
                  _count(raw, 'recipe_fts WHERE recipe_fts MATCH ?', [
                    word,
                  ]) ==
                  0,
              orElse: () => throw StateError(
                'no $what term is invisible to the narrow index; candidates '
                'were $candidates',
              ),
            );
          }

          // Everything the seeded corpus already says outside the text 008
          // adds — subtracted from every tracer pool, so each tracer can only
          // come back through the one code path it is named for.
          final seededElsewhere = {
            for (final recipe in recipes) ...[
              ..._topLevelWords(recipe),
              ..._subsectionWords(recipe),
            ],
          };
          subsectionTerm = tracer(
            _subsectionWords(withVariations).difference({
              for (final recipe in recipes) ..._topLevelWords(recipe),
            }),
            'subsection-only',
          );
          // The two technique paths get a tracer each: _rebuildFts folds step
          // captions into `directions` and heading/description into
          // `background`. Delete either fold and the matching tracer stops
          // coming back.
          techniqueCaptionTerm = tracer(
            _techniqueCaptionWords(withTechniques)
                .difference(_techniqueProseWords(withTechniques))
                .difference(seededElsewhere),
            'technique-caption-only',
          );
          techniqueProseTerm = tracer(
            _techniqueProseWords(withTechniques)
                .difference(_techniqueCaptionWords(withTechniques))
                .difference(seededElsewhere),
            'technique-heading/description-only',
          );

          // The seeded file really is the OLD shape: without this, a v1 case
          // could be silently seeding a v8 schema and every "the migration
          // did its work" assertion below would be vacuous.
          expect(
            _columnNames(raw, 'recipes'),
            startVersion >= 7
                ? contains('variation_count')
                : isNot(contains('variation_count')),
            reason: 'recipes.variation_count arrives with migration 007',
          );
          expect(
            _columnNames(raw, 'import_jobs'),
            startVersion >= 6
                ? contains('imported')
                : isNot(contains('imported')),
            reason: 'import_jobs.imported arrives with migration 006',
          );
          for (final table in [
            'users',
            'tag_styles',
            'user_notes',
            'recipe_nutrition',
          ]) {
            final since = {
              'users': 2,
              'tag_styles': 3,
              'user_notes': 4,
              'recipe_nutrition': 5,
            }[table]!;
            expect(
              _count(raw, "sqlite_master WHERE type = 'table' AND name = ?", [
                table,
              ]),
              startVersion >= since ? 1 : 0,
              reason:
                  '$table exists from v$since '
                  '(${_capabilityByVersion[since]})',
            );
          }
          raw.dispose();

          // --- the upgrade under test ---
          final db = SaltDatabase.open(path);
          List<String> idsFor(String term) => [
            for (final card
                in db
                    .searchCards(
                      compileSearch(parseSearchQuery(term).root!),
                      page: 1,
                      limit: 50,
                    )
                    .items)
              card.id,
          ];
          // Every path the 008 widening opens, one tracer each.
          for (final (term, recipe, where) in [
            (subsectionTerm, withVariations, 'inside a subsection of'),
            (
              techniqueCaptionTerm,
              withTechniques,
              'inside a technique step caption of',
            ),
            (
              techniqueProseTerm,
              withTechniques,
              'inside a technique heading/description of',
            ),
          ]) {
            if (expectReindex) {
              expect(
                idsFor(term),
                contains(recipe.id),
                reason:
                    '"$term" appears only $where ${recipe.slug}; after '
                    'upgrading from v$startVersion across the 008 widening '
                    'the Dart reindex must have made it findable through the '
                    'real search path',
              );
            } else {
              expect(
                idsFor(term),
                isNot(contains(recipe.id)),
                reason:
                    'a database at v${migrations.length} that HOLDS the '
                    'completion marker must not be reindexed — the narrow '
                    'tracer rows prove _migrate honoured it. (A v8 database '
                    'WITHOUT the marker is the stuck case and IS reindexed; '
                    'see the self-heal test.)',
              );
            }
          }
          // The pre-existing narrow content still resolves either way.
          final titleWord = _words(withVariations.title).first;
          expect(
            idsFor(titleWord),
            contains(withVariations.id),
            reason: 'the upgrade must not drop existing FTS rows',
          );
          expect(db.recipeCount(), recipes.length);
          db.dispose();

          // --- inspect the migrated file directly ---
          final after = sqlite3.open(path);
          expect(
            after.select('PRAGMA user_version').first.columnAt(0),
            migrations.length,
          );

          for (final recipe in recipes) {
            final rows = after.select(
              'SELECT doc, content_hash, slug, title, variation_count '
              'FROM recipes WHERE id = ?',
              [recipe.id],
            );
            expect(rows, hasLength(1), reason: '${recipe.id} must survive');
            final row = rows.first;
            expect(
              row['doc'],
              seed.docs[recipe.id],
              reason: 'the stored document must be byte-identical',
            );
            expect(row['content_hash'], seed.hashes[recipe.id]);
            expect(row['slug'], recipe.slug);
            // For startVersion < 7 this is genuinely independent: the SQL
            // backfill computed the column and Dart computed the expectation.
            // For startVersion >= 7 it is only a PRESERVATION check — _seed
            // wrote _variationCount(recipe) into the column itself, so the
            // two sides are the same expression and all this pins is that the
            // upgrade did not clobber the value. Do not read the v7/v8 rows
            // as backfill coverage.
            expect(
              row['variation_count'],
              _variationCount(recipe),
              reason: startVersion >= _variationCountVersion
                  ? 'the upgrade must preserve the stored variation_count for '
                        '${recipe.slug} (it predates this start version)'
                  : 'migration 007 must count only kind == variation for '
                        '${recipe.slug} '
                        '(${recipe.subsections.length} subsections)',
            );
            expect(
              _count(after, 'recipe_ingredients WHERE recipe_id = ?', [
                recipe.id,
              ]),
              seed.ingredientCounts[recipe.id],
            );
            final tags = after.select(
              'SELECT t.name AS name FROM recipe_tags rt '
              'JOIN tags t ON t.id = rt.tag_id '
              'WHERE rt.recipe_id = ? ORDER BY t.name',
              [recipe.id],
            );
            expect(
              [for (final tag in tags) tag['name']],
              seed.tagNames[recipe.id],
            );
          }

          expect(
            after.select('SELECT value FROM settings WHERE key = ?', [
              servesBackfillSetting,
            ]).single['value'],
            _servesBackfillValue,
            reason:
                'the serves-backfill marker must come back byte-identical — '
                'corrupt it and the once-per-database backfill re-runs over a '
                'live library',
          );
          final job = after.select('SELECT * FROM import_jobs').first;
          expect(job['done'], recipes.length);
          expect(job['total'], recipes.length);
          expect(
            job['imported'],
            startVersion >= 6 ? recipes.length : 0,
            reason: startVersion >= 6
                ? 'seeded counters must survive'
                : 'migration 006 adds the column with DEFAULT 0',
          );

          if (startVersion >= 2) {
            final user = after.select('SELECT * FROM users').single;
            expect(user['username'], 'admin');
            expect(user['password_hash'], seed.passwordHash);
            expect(user['role'], 'admin');
            expect(user['must_change_password'], 1);
            expect(
              after.select(
                'SELECT user_id FROM sessions WHERE token_hash = ?',
                [
                  seed.sessionTokenHash,
                ],
              ).single['user_id'],
              user['id'],
            );
            expect(
              after.select(
                'SELECT scope FROM api_tokens WHERE token_hash = ?',
                [seed.patTokenHash],
              ).single['scope'],
              'read',
            );
          }
          if (startVersion >= 3) {
            final style = after.select('SELECT * FROM tag_styles').single;
            expect(style['tag_name'], seed.styledTag);
            expect(style['color'], '#960000');
          }
          if (startVersion >= 4) {
            expect(
              after
                  .select('SELECT recipe_id FROM user_favorites')
                  .single['recipe_id'],
              recipes.first.id,
            );
            expect(
              after.select('SELECT body FROM user_notes').single['body'],
              seed.noteBody,
            );
          }
          if (startVersion >= 5) {
            // Every nutrition row, every column, byte-identical to the real
            // engine output that was seeded.
            for (final entry in _nutritionTables.entries) {
              final expected = nutritionRows[entry.key]!;
              final rows = after.select(
                'SELECT * FROM ${entry.key} ORDER BY ${entry.value}',
              );
              expect(
                rows,
                hasLength(expected.length),
                reason: '${entry.key} must survive the upgrade intact',
              );
              for (final (index, row) in rows.indexed) {
                expect(
                  {
                    for (final column in row.keys)
                      column: row[column] as Object?,
                  },
                  expected[index],
                  reason: '${entry.key} row $index must come back unchanged',
                );
              }
            }
            expect(
              after
                  .select('SELECT status FROM nutrition_jobs')
                  .single['status'],
              'done',
            );
          }
          after.dispose();
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    }

    /// Every text column of the FTS row for [recipeId], joined — where a
    /// subsection word lands (title, ingredients, directions, background)
    /// depends on the fold, and this test cares only that it landed.
    String ftsText(Database raw, String recipeId) {
      final rowid =
          raw.select('SELECT rowid FROM recipes WHERE id = ?', [
                recipeId,
              ]).first['rowid']
              as int;
      final row = raw.select('SELECT * FROM recipe_fts WHERE rowid = ?', [
        rowid,
      ]).first;
      return [
        for (final column in row.keys)
          if (row[column] is String) row[column] as String,
      ].join(' ');
    }

    /// A word that lives only in a subsection of [withVariations] and that
    /// the seeded NARROW row provably lacks — the sanity check inside makes
    /// the choice empirical rather than assumed.
    String narrowMissingTerm(Database raw) {
      final narrow = ftsText(raw, withVariations.id);
      final candidates = _subsectionWords(
        withVariations,
      ).difference(_topLevelWords(withVariations));
      return candidates.firstWhere(
        (word) => !narrow.contains(word),
        orElse: () => fail('no subsection-only word is absent from the seed'),
      );
    }

    test(
      'a v${migrations.length} database with narrow rows and NO marker is '
      'healed at the next open',
      () {
        // The stuck deployment: it reached v8 on a boot whose reindex threw,
        // so the version committed and the rows stayed narrow. Keying on the
        // marker heals it. A reindex inside the 008 transaction never could —
        // at version 8 there is nothing left to roll back.
        final dir = Directory.systemTemp.createTempSync('salt_migr_stuck');
        final path = '${dir.path}/salt.db';
        try {
          final raw = sqlite3.open(path)..execute('PRAGMA foreign_keys = ON');
          _applyPrefix(raw, migrations.length);
          _seed(
            raw,
            migrations.length,
            recipes,
            passwordHash: passwordHash,
            sessionToken: sessionToken,
            patToken: patToken,
            nutritionRows: nutritionRows,
          );
          raw.execute('DELETE FROM settings WHERE key = ?', [
            SaltDatabase.ftsWidenedSetting,
          ]);
          final term = narrowMissingTerm(raw);
          raw.dispose();

          SaltDatabase.open(path).dispose();

          final after = sqlite3.open(path);
          expect(
            after.select('SELECT value FROM settings WHERE key = ?', [
              SaltDatabase.ftsWidenedSetting,
            ]),
            isNotEmpty,
            reason: 'healed: the completion marker is written',
          );
          expect(
            ftsText(after, withVariations.id),
            contains(term),
            reason:
                '"$term" lives only in a subsection; a healed row carries it',
          );
          after.dispose();
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'an undecodable stored doc is skipped and named, and the pass retries '
      'until it is fixed',
      () {
        // Crafted negative input — the one class the corpus cannot supply.
        // What a real deployment hits when a model change makes an OLD doc
        // stop decoding on the upgrade boot.
        final dir = Directory.systemTemp.createTempSync('salt_migr_baddoc');
        final path = '${dir.path}/salt.db';
        final records = <LogRecord>[];
        final subscription = Logger.root.onRecord.listen(records.add);
        addTearDown(subscription.cancel);
        try {
          final raw = sqlite3.open(path)..execute('PRAGMA foreign_keys = ON');
          _applyPrefix(raw, _ftsWideningVersion - 1);
          final seed = _seed(
            raw,
            _ftsWideningVersion - 1,
            recipes,
            passwordHash: passwordHash,
            sessionToken: sessionToken,
            patToken: patToken,
            nutritionRows: nutritionRows,
          );
          final term = narrowMissingTerm(raw);
          raw
            ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
              'not json',
              plain.id,
            ])
            ..dispose();

          Iterable<LogRecord> namingTheVictim() => records.where(
            (record) =>
                record.level >= Level.WARNING &&
                record.message.contains(plain.id),
          );

          // Boot 1: succeeds, skips the bad row, names it, does NOT mark.
          var db = SaltDatabase.open(path);
          expect(
            db.getSetting(SaltDatabase.ftsWidenedSetting),
            isNull,
            reason: 'one skipped row must leave the pass unmarked',
          );
          expect(namingTheVictim(), isNotEmpty, reason: 'the log names it');
          db.dispose();
          final check = sqlite3.open(path);
          expect(
            ftsText(check, withVariations.id),
            contains(term),
            reason: 'the rows that DID decode are widened and committed',
          );
          check.dispose();

          // Boot 2: retries and names it again — every boot, until fixed.
          final named = namingTheVictim().length;
          db = SaltDatabase.open(path);
          expect(db.getSetting(SaltDatabase.ftsWidenedSetting), isNull);
          expect(namingTheVictim().length, greaterThan(named));
          db.dispose();

          // Fix the row (restore the exact seeded document) and boot 3.
          sqlite3.open(path)
            ..execute('UPDATE recipes SET doc = ? WHERE id = ?', [
              seed.docs[plain.id],
              plain.id,
            ])
            ..dispose();
          db = SaltDatabase.open(path);
          expect(
            db.getSetting(SaltDatabase.ftsWidenedSetting),
            isNotNull,
            reason: 'with every row decodable the pass completes and marks',
          );
          db.dispose();
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  }, skip: skipIfNoCorpus);
}
