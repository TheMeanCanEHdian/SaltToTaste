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

  // 009 — cross-recipe reuse of human match decisions (review R1). The
  // matcher's normalized item text is stored per match row so a decision made
  // on "unsalted butter" in one recipe can be found from any other. Existing
  // rows are keyed in Dart at boot (services/item_key_backfill.dart, marker
  // backfill.item_key): the key derives from the recipe's parsed lines, which
  // SQL cannot reach.
  [
    'ALTER TABLE ingredient_matches ADD COLUMN item_key TEXT',
    'CREATE INDEX idx_matches_item_key ON ingredient_matches(item_key)',
  ],

  // 010 — a human food decision gets a row of its own, keyed by the
  // ingredient (design review D3, 2026-09-07). Before this a decision lived
  // only on the line it was made on and every other line BORROWED it, so
  // deleting that recipe or editing that line's amount silently reverted
  // every borrower at its next compute. `item` is the parsed text the key
  // was derived from, so a matcher change can re-derive the key at boot
  // (services/decision_rekey.dart). Not seeded: the table fills as
  // decisions are made. Human-only — the engine never writes it.
  [
    '''
CREATE TABLE ingredient_decisions (
  item_key TEXT PRIMARY KEY CHECK(item_key <> ''),
  item TEXT NOT NULL,
  fdc_id INTEGER,
  description TEXT,
  data_type TEXT,
  decided_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  decided_at TEXT NOT NULL DEFAULT (datetime('now'))
) WITHOUT ROWID
''',
  ],

  // 011 — an engine match held out of the totals for a reason other than a
  // weak name score (sweep accuracy batch, 2026-09-26): a record that
  // publishes no energy and no macros would count as 0 kcal, a discarded
  // medium set to review, a line that names a second ingredient. The code
  // (`no_nutrients` | `discarded_medium` | `second_food`) is what the review
  // sheet explains; it only holds an `auto` row — a person's decision on the
  // row always counts. NULL on every existing row: the next compute sets it.
  ['ALTER TABLE ingredient_matches ADD COLUMN hold TEXT'],

  // 012 — a recipe's match-row LAYOUT (Run 051 C1, D2): `seq` counts the
  // layouts that changed where its rows stand or the lines they stand on
  // (SaltDatabase.relayoutIngredientMatches), so a writer that read the
  // rows before an await writes only while no layout came between — the
  // content hash cannot tell, a save and its revert hash the same (ABA).
  // `lines` holds the texts (a JSON array) of the lines the rows were last
  // laid out on, the old side the next pairing reads. Its own table: a
  // recipe may have rows and no recipe_nutrition row (a person's write
  // before any compute). No row = never laid out (seq 0, texts unknown).
  [
    '''
CREATE TABLE recipe_layout (
  recipe_id TEXT PRIMARY KEY REFERENCES recipes(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  lines TEXT NOT NULL
) WITHOUT ROWID
''',
  ],

  // 013 — Run 052 (O1/S2, Opus critic 1): the freshness stamp records the
  // layout it was computed on, and the layout sequence is GLOBAL.
  // `recipe_nutrition.layout_seq` is the `recipe_layout.seq` the stamped
  // totals were computed on: a recipe is fresh only while its hash AND its
  // layout are still those (a save, a person's write laying the rows out
  // for it and a revert hash the same, but bump the layout). Existing stamps
  // take their recipe's current seq (0: never laid out). `layout_counter`
  // is the one counter every layout draws its next seq from, so a recipe
  // deleted and re-created under the same id (its recipe_layout row
  // cascades away) never repeats a seq a writer read before the delete.
  [
    'ALTER TABLE recipe_nutrition ADD COLUMN layout_seq INTEGER',
    '''
UPDATE recipe_nutrition SET layout_seq = COALESCE((SELECT seq FROM
  recipe_layout l WHERE l.recipe_id = recipe_nutrition.recipe_id), 0)
''',
    '''
CREATE TABLE layout_counter (
  id INTEGER PRIMARY KEY CHECK (id = 0),
  seq INTEGER NOT NULL
)
''',
    '''
INSERT INTO layout_counter (id, seq)
  SELECT 0, COALESCE(MAX(seq), 0) FROM recipe_layout
''',
  ],

  // 014 — Run 057 (RULE A, v27): "derived" is a fact ON THE ROW. A decided
  // row's `derived_seq` names what its derived fields (hold, grams unless
  // typed, their source) were computed for: '<layout seq>:<ingredients
  // hash>' — the recipe's layout and inputs, the two halves its freshness
  // stamp names, as one value ([derivedKeyOf]). A successful derivation
  // writes it; one that cannot run leaves it (or the PUT stores null), so
  // a decided row no derivation has reached for the stamped inputs is
  // UNDERIVED and the recipe is not fresh, whoever wrote the stamp
  // ([SaltDatabase.underivedSql]). Backfilled at boot, not here: whether a
  // stamp is current needs the Dart-side hash — the marker below asks the
  // boot pass once (`backfillDerivedSeq`: a fresh recipe's decided rows
  // take its current key, a stale one's stay null).
  [
    'ALTER TABLE ingredient_matches ADD COLUMN derived_seq TEXT',
    '''
INSERT OR REPLACE INTO settings (key, value)
  VALUES ('nutrition.derived_seq_backfill', 'pending')
''',
  ],

  // 015 — v27 closer (RULE A, the verifier's D1): the per-RECIPE totals
  // the per-serving label was divided from, unrounded (JSON: nutrient key
  // -> total), so a serving-basis change is arithmetic over what is stored
  // ([rebaseNutrition]) — never a re-read of the rows against the caches,
  // which dropped a food no cache held and turned the recipe stale. Null
  // on a row written before it (the per-serving amounts times the stored
  // basis stand in until the next compute writes it).
  ['ALTER TABLE recipe_nutrition ADD COLUMN totals TEXT'],

  // 016 — Run 058 (v28). RULE A: `retry_count` counts the computes in a
  // row that met a FOOD failure ([FailureScope.food]: FDC failing one
  // food's detail, not a 404) on a decided row — the row is left underived
  // and the sweep moves on; at `foodUnavailableAfter` the row is held
  // `food_unavailable` for a person. Every other write of the row resets
  // it to 0. RULE C: `fdc_search_cache_foods` indexes which cached search
  // answers list which food (`knownFood`'s fallback was an unindexed scan
  // of every answer per typed row per GET, Run 058 O5/S10), kept by
  // TRIGGERS on every write of `fdc_search_cache` — whoever writes it —
  // and backfilled once here from the answers already cached (SQL's own
  // JSON reader: no boot pass needed).
  [
    '''
ALTER TABLE ingredient_matches ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0
''',
    '''
CREATE TABLE fdc_search_cache_foods (
  fdc_id INTEGER NOT NULL,
  query TEXT NOT NULL,
  PRIMARY KEY (fdc_id, query)
) WITHOUT ROWID
''',
    '''
CREATE INDEX fdc_search_cache_foods_query ON fdc_search_cache_foods (query)
''',
    '''
CREATE TRIGGER fdc_search_cache_foods_insert
AFTER INSERT ON fdc_search_cache BEGIN
  DELETE FROM fdc_search_cache_foods WHERE query = NEW.query;
  $_indexAnswer
END
''',
    '''
CREATE TRIGGER fdc_search_cache_foods_update
AFTER UPDATE OF response ON fdc_search_cache BEGIN
  DELETE FROM fdc_search_cache_foods WHERE query = NEW.query;
  $_indexAnswer
END
''',
    '''
CREATE TRIGGER fdc_search_cache_foods_delete
AFTER DELETE ON fdc_search_cache BEGIN
  DELETE FROM fdc_search_cache_foods WHERE query = OLD.query;
END
''',
    r'''
INSERT OR IGNORE INTO fdc_search_cache_foods (fdc_id, query)
  SELECT json_extract(j.value, '$.fdc_id'), c.query
  FROM fdc_search_cache c, json_each(CASE WHEN json_valid(c.response)
    THEN c.response ELSE '[]' END) j
  WHERE j.type = 'object' AND json_extract(j.value, '$.fdc_id') IS NOT NULL
''',
  ],

  // 017 — Run 059 (v29, RULE A). `computing`: how many writers have a pass
  // IN PROGRESS — an OWNED count, each compute pass, person's write and
  // apply-to-all target adding one before its first row write and taking
  // its own one away with its totals (one transaction), so no writer
  // clears another's; read as stale by every freshness reader
  // (`underivedSql`): a pass that never reaches its totals (a restart, an
  // OOM, an await never answered) leaves the recipe stale (Run 059 Opus
  // critic 1 — its marks stayed committed and the recipe read fresh on
  // totals that never counted the row). The boot clears the stamp of every
  // recipe still counted (`interrupted:`, stale) and resets the count; the
  // next compute repairs them. The partial index serves `unholdOn`: a
  // cache gaining a food re-opens the rows held for having none (`food_gone`,
  // `food_unavailable` on that food) — one indexed UPDATE per cache write.
  [
    'ALTER TABLE recipe_nutrition ADD COLUMN computing INT NOT NULL DEFAULT 0',
    '''
CREATE INDEX ingredient_matches_no_record ON ingredient_matches (fdc_id)
  WHERE hold IN ('food_gone', 'food_unavailable')
''',
  ],

  // 018 — matcher v41, the composite row (plan.md Q5 a / Q7 phase 1; the
  // approved mockup docs/mockups/v40-composite-rows.html). One line, one
  // row, still. A SUB-RECIPE row names its child by `recipes.id` (stable
  // across slug renames; no FK, so deleting a library recipe is never
  // blocked — the stamp arm turns its parents stale instead), the share
  // of the child's batch it counts, and the child's `computed_at` it was
  // derived from (`child_stamp`, read by `underivedSql`). A TWO-PART row
  // keeps the record bought on the row and lists the records it COUNTS in
  // `parts` (rendered bacon: cooked + the fat kept in the pan). NULL on
  // every existing row = not composite; nothing to backfill — the matcher
  // bump stales every stamp and the next sweep writes the new rows.
  [
    'ALTER TABLE ingredient_matches ADD COLUMN child_recipe_id TEXT',
    '''
ALTER TABLE ingredient_matches ADD COLUMN child_share REAL
  CHECK (child_share IS NULL OR child_share > 0)
''',
    'ALTER TABLE ingredient_matches ADD COLUMN child_stamp TEXT',
    '''
ALTER TABLE ingredient_matches ADD COLUMN parts TEXT
  CHECK (parts IS NULL OR (json_valid(parts) AND json_type(parts) = 'array'
    AND child_recipe_id IS NULL))
''',
  ],
];

/// Lists the foods a cached search answer (`NEW.response`: a JSON array of
/// `FdcCandidate.toJson`) holds in `fdc_search_cache_foods` (migration 016).
const String _indexAnswer = r'''
INSERT OR IGNORE INTO fdc_search_cache_foods (fdc_id, query)
  SELECT json_extract(j.value, '$.fdc_id'), NEW.query
  FROM json_each(CASE WHEN json_valid(NEW.response)
    THEN NEW.response ELSE '[]' END) j
  WHERE j.type = 'object' AND json_extract(j.value, '$.fdc_id') IS NOT NULL;
''';
