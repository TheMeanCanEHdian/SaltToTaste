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
  tokenize='porter unicode61 remove_diacritics 2'
)
''',
  ],
];
