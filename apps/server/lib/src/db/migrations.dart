/// Ordered schema migrations applied via `PRAGMA user_version`.
///
/// Each entry is one migration: a list of single SQL statements executed in
/// order inside one transaction. `PRAGMA user_version` equals the number of
/// migrations already applied, so migration N (0-based index) brings the
/// database to version N + 1. Never edit a shipped migration — append a new
/// one instead.
const List<List<String>> migrations = [
  // 001 — initial P1 schema.
  [
    '''
CREATE TABLE sources (
  slug TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  meta TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
)
''',
    '''
CREATE TABLE recipes (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  source_slug TEXT NOT NULL REFERENCES sources(slug),
  title TEXT NOT NULL,
  category TEXT,
  servings_text TEXT,
  serves_min INTEGER,
  serves_max INTEGER,
  prep_min INTEGER,
  cook_min INTEGER,
  total_min INTEGER,
  hero_image TEXT,
  doc TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
)
''',
    'CREATE INDEX idx_recipes_title ON recipes(title COLLATE NOCASE)',
    'CREATE INDEX idx_recipes_category ON recipes(category)',
    '''
CREATE TABLE recipe_ingredients (
  recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  group_name TEXT,
  raw TEXT NOT NULL,
  item TEXT,
  prep TEXT,
  amounts TEXT NOT NULL,
  PRIMARY KEY (recipe_id, position)
) WITHOUT ROWID
''',
    '''
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
)
''',
    '''
CREATE TABLE recipe_tags (
  recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tags(id),
  PRIMARY KEY (recipe_id, tag_id)
)
''',
    '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''',
    '''
CREATE TABLE import_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  status TEXT NOT NULL,
  source_path TEXT NOT NULL,
  total INTEGER NOT NULL DEFAULT 0,
  done INTEGER NOT NULL DEFAULT 0,
  skipped INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  log TEXT NOT NULL DEFAULT '[]',
  started_at TEXT,
  finished_at TEXT
)
''',
    '''
CREATE VIRTUAL TABLE recipe_fts USING fts5(
  recipe_id UNINDEXED,
  title,
  category,
  tags,
  ingredients,
  directions,
  notes,
  background,
  prep_notes,
  tokenize='porter unicode61 remove_diacritics 2'
)
''',
  ],
  // 002 — P3 auth: users, sessions, API tokens. Token/session secrets are
  // stored only as SHA-256 hashes; timestamps written by the DAL are UTC
  // ISO-8601 TEXT.
  [
    '''
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin','member')),
  must_change_password INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_active_at TEXT
)
''',
    '''
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL,
  last_seen_at TEXT,
  remember INTEGER NOT NULL DEFAULT 0,
  user_agent TEXT
)
''',
    'CREATE INDEX idx_sessions_user_id ON sessions(user_id)',
    '''
CREATE TABLE api_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  prefix TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  scope TEXT NOT NULL CHECK(scope IN ('read','full')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT
)
''',
    'CREATE INDEX idx_api_tokens_user_id ON api_tokens(user_id)',
  ],
  // 003 — P4 search & tags: per-tag chip styling (Lucide icon + colors),
  // editable by admins in Settings.
  [
    '''
CREATE TABLE tag_styles (
  tag_name TEXT PRIMARY KEY,
  icon TEXT,
  color TEXT,
  bg_color TEXT
)
''',
  ],
  // 004 — P5 editing: per-user favorites and personal notes. Both are
  // database-only personal data — never exported to the YAML library.
  [
    '''
CREATE TABLE user_favorites (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, recipe_id)
)
''',
    'CREATE INDEX idx_user_favorites_recipe ON user_favorites(recipe_id)',
    '''
CREATE TABLE user_notes (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, recipe_id)
)
''',
  ],
  // 005 — P6 nutrition (USDA FoodData Central). FDC responses are cached
  // (the ingredient vocabulary repeats heavily), per-line matches are
  // persisted and user-overridable, and computed per-serving totals are
  // denormalized (calories) for the `calories:` search filter/ordering.
  [
    '''
CREATE TABLE fdc_search_cache (
  query TEXT PRIMARY KEY,
  response TEXT NOT NULL,
  fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
)
''',
    '''
CREATE TABLE fdc_food_cache (
  fdc_id INTEGER PRIMARY KEY,
  response TEXT NOT NULL,
  fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
)
''',
    '''
CREATE TABLE ingredient_matches (
  recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  raw TEXT NOT NULL,
  fdc_id INTEGER,
  description TEXT,
  data_type TEXT,
  confidence REAL NOT NULL DEFAULT 0,
  grams REAL,
  gram_source TEXT,
  status TEXT NOT NULL
    CHECK(status IN ('auto','confirmed','overridden','skipped','unmatched')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (recipe_id, position)
) WITHOUT ROWID
''',
    '''
CREATE TABLE recipe_nutrition (
  recipe_id TEXT PRIMARY KEY REFERENCES recipes(id) ON DELETE CASCADE,
  serving_basis INTEGER,
  calories_per_serving REAL,
  nutrients TEXT NOT NULL,
  total_grams REAL,
  matched_count INTEGER NOT NULL,
  total_count INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('complete','partial','stale')),
  ingredients_hash TEXT NOT NULL,
  computed_at TEXT NOT NULL DEFAULT (datetime('now'))
)
''',
    // ignore: no_adjacent_strings_in_list
    'CREATE INDEX idx_recipe_nutrition_calories ON '
        'recipe_nutrition(calories_per_serving)',
    '''
CREATE TABLE nutrition_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  status TEXT NOT NULL,
  total INTEGER NOT NULL DEFAULT 0,
  done INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  log TEXT NOT NULL DEFAULT '[]',
  started_at TEXT,
  finished_at TEXT
)
''',
  ],

  // 006 — import jobs go live (P7). The table itself shipped in 001;
  // the API adds format detection and finer summary counters.
  [
    'ALTER TABLE import_jobs ADD COLUMN legacy INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE import_jobs ADD COLUMN imported INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE import_jobs ADD COLUMN updated INTEGER NOT NULL DEFAULT 0',
  ],

  // 007 — how many VARIATIONS a recipe carries, so a card can say so without
  // decoding its doc.
  //
  // A count, not a boolean: it costs the same to store and lets a later
  // `has:variants` search or a "3 variations" label land without a second
  // migration.
  //
  // `variation` only. `Subsection.kind` is tri-valued — variation / component /
  // unknown — and a component is a sub-recipe (a pie dough for the pie), not a
  // variant of the recipe. Counting subsections wholesale would badge those
  // wrongly. Measured over the 1,198-recipe corpus: 383 recipes carry
  // subsections, 680 subsections in all, of which 648 are variations and 32
  // components.
  //
  // The backfill reads `doc`, which is JSON (`jsonEncode(recipe.toMap())` in
  // upsertRecipe) rather than the YAML export, so json_each can do it in SQL
  // with no Dart pass and no re-import. Verified against the dev library: 374
  // recipes get a non-zero count, 648 variations in total — the same figures
  // the corpus itself reports.
  [
    'ALTER TABLE recipes ADD COLUMN variation_count INTEGER NOT NULL DEFAULT 0',
    r'''
UPDATE recipes SET variation_count = (
  SELECT COUNT(*)
  FROM json_each(json_extract(recipes.doc, '$.subsections'))
  WHERE json_extract(json_each.value, '$.kind') = 'variation'
)
WHERE json_extract(doc, '$.subsections') IS NOT NULL
''',
  ],

  // 008 — the FTS row widens to subsection content (ingredients, steps,
  // titles, body) and technique captions/headings, so search stops missing
  // a third of the library's text (review B1: `chanterelle` found nothing
  // because the only mention sat in a "Sautéed Wild Mushrooms" component).
  //
  // The FTS text is derived from nested arrays of the doc JSON — beyond
  // what a maintainable SQL backfill can express — so the rebuild happens
  // in Dart: SaltDatabase._migrate() re-derives every FTS row via
  // _rebuildFts when it crosses this version. The statement below only
  // marks the schema version; the paired Dart pass is what reindexes.
  ['SELECT 1'],
];
