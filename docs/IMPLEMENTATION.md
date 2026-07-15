# Implementation Tracker

Living status of the approved rewrite plan (local file:
`/Users/drivard/.claude/plans/background-a-long-warm-robin.md`). Statuses:
`pending` / `in-progress` / `done` / `changed(reason)`.

Last updated: 2026-07-14

## P0 — Workspace + salt_shared — **done**

| Item | Status | Notes |
|---|---|---|
| Pub workspace root (`pubspec.yaml`, `analysis_options.yaml`) | done | Dart 3.12 native workspaces; strict lints |
| Branch `feat/dart-rewrite` | done | |
| `salt_shared` package + schema-v2 models (dart_mappable, snake_case) | done | `lib/src/model/recipe.dart`; codegen green |
| YAML emitter (block style, literal blocks, PyYAML-safe quoting) | done | `lib/src/yaml/yaml_emitter.dart` |
| Quantity/fraction utils + servings parser (corpus-vocabulary driven) | done | 100% of 200 distinct corpus servings values parse |
| Search DSL parser (scoped terms, and/or, calories ops) | done | tolerant parser w/ error recovery; no parentheses (matches old DSL) |
| Recipe YAML codec (decode/normalize/v1→v2 upgrade, canonical encode) | done | quantity/isbn/extracted_at string-coercion; subsection key omission preserved |
| Corpus golden test: 1,198 files decode + round-trip model-equal | done | verified: 1198/1198 decode, 1198/1198 round-trip, 0 unparseable servings; 89/89 tests, analyze clean |
| CLAUDE.md + this tracker | done | |
| Phase code review (high effort, adversarial verify) | done | see review record below |

Known limitations (documented by module authors): quantity parser rejects
range strings (`1–2`) by design; DSL has no parentheses grouping; smart quotes
not treated as phrase delimiters; `MAKES ... CUPS` yields use the leading
number (serving basis is editable later).

### P0 code review record (2026-07-14)

8 finder angles → 27 deduped candidates → adversarial panel (3 refuters per
finding, ≥2 kills) → 23 survivors, 5 killed. All survivors fixed and covered
by regression tests (suite grew 89 → 107 tests), except three deferred items:

**Fixed (correctness):** emitter now quotes PyYAML date/sexagesimal forms
(`'2026-06-30'`, `'1:30'`); C1 controls + U+2028/9 escaped double-quoted;
non-finite doubles emit `.inf`/`.nan`; codec reads `schema_version` tolerantly
(`'1'`/`1.0`/unrecognizable→warn+v1); `SERVES 4-6`/`4–6` ranges; DOZEN
multiplies before rounding (`1½ DOZEN` = 18); `ABOUT/YIELDS n SERVINGS` and
`n TO m SERVINGS` parse via token scan.

**Fixed (design/cleanup):** encode now derived from generated `toMap()` +
canonical transform — model fields can never be silently dropped (tripwire
test added); redundant scalar coercion removed (dart_mappable String-coercion
behavior pinned by regression test); fraction char class shared between
quantity and servings parsers; corpus path/scanners consolidated into
`test/corpus.dart` with a decode-once cache; And/Or nodes share a sealed
junction base; contradictory coverage assertions resolved; `formatQuantity`
regexes hoisted; emitter public-API branches now tested.

**Killed by panel (spot-checkable):** subsection key-order fidelity (encode is
canonical-v2 by contract, source files never rewritten); versioned migration
chain (no v3 on roadmap; YAGNI); structured warning objects (two producers,
job-log contract only); generalized numeric filter node (calories-only is the
documented old-DSL parity); serves/times optionality asymmetry (deliberate
per-plan shapes).

**Deferred to user/P4:** search semantics changes vs old app — scope binds one
term (old: whole block) and adjacent same-scope terms AND (old: OR) — product
decisions pending; `calories:` queries must default to calories-ascending
ordering in the P4 compiler (old-app contract not expressible in the AST).

## P1 — Server core + import — **done**

| Item | Status | Notes |
|---|---|---|
| Dart Frog scaffold (apps/server, workspace member) | done | |
| Logging + request-id + error-envelope middleware (first) | done | order: requestId → requestLogger → errorHandler → providers (deviation from plan's "errorHandler outermost": dart_frog's one-directional context means the envelope couldn't carry the request id otherwise; rationale in routes/_middleware.dart) |
| ServerConfig from env (DATA_DIR, LOG_LEVEL, TRUST_PROXY) | done | trustProxy stored, consumed in P3 (cookies) |
| SQLite DAL + migration 001 incl. FTS5 | done | migrations as Dart constants (not .sql files — asset-loading in compiled exe); prepared statements only |
| Import service + `dart run salt_server:import` CLI | done | canonical-v2 export written to library/, sha256 content hash, idempotent |
| Recipes list/detail/yaml endpoints + image serving | done | handler-refactor pattern (testable cores in lib/src/handlers); traversal guards |
| DTOs (RecipeCard, Paged, ApiError) in salt_shared | done | |
| End-to-end gate | done | verified by hand: 1198/1198 imported in 5.5s, 0 warnings; re-import 1198 skipped; list total=1198; detail by id+slug; yaml attachment; image 200 image/jpeg; 3 traversal probes rejected; error envelopes carry request_id |
| Phase code review (high effort, adversarial verify) | done | see review record below |

Known quirks: `dart_frog dev` crashes without a TTY (its hot-reload key
listener sets stdin echo mode) — use `dart_frog build` + `dart
build/bin/server.dart`, or run dev from a real terminal. `.data/` is
git-ignored dev state. Editing migration 001 is allowed only because P1 has
not shipped; once released, append a new migration instead (delete `.data`
to rebuild a dev DB after a 001 change).

### P1 code review record (2026-07-14)

8 finder angles → 25 deduped candidates → adversarial panel (3 refuters per
finding, ≥2 kills) → 21 survivors fixed, 4 killed. Full suite green
(salt_shared 107 + server 46) and re-verified end-to-end.

**Security fixed:** arbitrary file write via unvalidated `recipe.id`
(now `isSafeRecipeId`, rejected at import — verified a `../../` id is blocked
and writes nothing); `Content-Disposition` header injection (same id
validation); symlink-following on import image copy (source path now resolved
+ contained); unbounded reads (8 MB YAML cap on import, 25 MB image cap on
serve).

**Correctness fixed:** import side effects now run before the success count
and a hash-unchanged recipe still re-materializes a missing export/image
(verified: deleting a library file + image and re-importing restores both);
slug-collision suffix now written into the stored doc so card and detail
agree; config + logging initialize eagerly at startup so a bad `LOG_LEVEL`
fails fast (verified: server prints a fatal message and refuses to serve)
instead of silent 500s; image URL/served-name unified in one
`image_paths` module (flattens subdirs, URL-safe names, no basename
collisions); 404 rewrap keyed on status code, not dart_frog's fallback body.

**Efficiency fixed:** FTS rows keyed by rowid (was a full virtual-table scan
per upsert — the O(N²)); cached prepared statements; `synchronous=NORMAL`;
single IN-clause tags query for the card list (was N+1); image
`Last-Modified` + `304` revalidation (verified).

**Altitude/cleanup fixed:** `background`/`prep_notes` added to the FTS table
in migration 001 (FTS5 can't add columns later — verified body-prose words
like "bloomed" are now searchable, closing a P4 general-search parity gap);
list endpoint returns the shared `Paged<RecipeCard>` DTO; error codes
centralized in `ApiErrorCodes` (salt_shared); `MethodNotAllowedException` +
`requireGet` collapse five route guards and add the RFC `Allow` header
(verified); `yamlToPlain` promoted to a shared util; tests consolidated on
`test/support/corpus.dart` with `SALT_CORPUS_DIR` override.

**Killed by panel:** nosniff-missing (Dart's HttpServer sets it globally);
upsert-reads-outside-transaction race (correctly a P5 concern when the second
connection lands); slugify drift (no client consumer exists yet);
package:path duplication (not worth the dependency).

**Recorded deviation:** the plan's `recipes` table lists scalar
`background`/`prep_notes`/`notes` columns; migration 001 omits them
deliberately — nothing sorts or filters on them, the full values live in the
`doc` JSON, and search uses the FTS columns. Add scalar columns only if a
future query needs them.

## P2 — Flutter read-only app — **done**
Mockups (grid/card/detail, desktop+mobile) → approval → theme/router/grid/detail.

### P2 code review record (2026-07-15)

Lighter review (per usage constraints): 3 finder angles (Flutter correctness,
API-contract fidelity, cleanup/conventions) → ~15 candidates deduped to 12
distinct → triaged inline (no full refuter panel; findings were robustness/UX
with clear reasoning). All fixed:

- **Repository robustness**: decode/shape casts and `response.data!` ran
  outside the error handler, so a malformed 200 body threw uncaught and hung
  the spinner. Now every failure — Dio transport AND decode/shape — maps to a
  single `RepositoryException`; error messages are client-owned (no raw server
  strings), and the "unreachable" copy no longer fires for non-envelope error
  bodies.
- **Pagination**: `loadMore` now stops on a short/empty page (a stale `total`
  can't loop forever) and surfaces a retry footer instead of silently
  stalling when pinned at the bottom.
- **Navigation**: tiles use `context.push` (real back stack); the detail nav
  bar has a back control that pops or falls back to home (fixes mobile
  system-back exiting the app).
- **Prod base-URL footgun**: `apiBaseUrl` now defaults to empty (same-origin,
  production-safe); dev passes `--dart-define=SALT_API_BASE=http://localhost:8080`.
  Verified in-browser with the define.
- **YAML download**: awaited, error-handled (SnackBar), absolute URL via
  `Uri.base.resolve` so it works same-origin in production.
- **Dev CORS**: now answers preflight `OPTIONS` (204) and advertises
  methods/headers, so P3's authenticated requests won't be blocked in the
  split-port dev setup. Verified: `OPTIONS` → 204 with CORS headers.
- **Cleanup**: shared `PhotoFallback` widget; stray color literals folded into
  `SaltColors`; shared `Breakpoints` constants; slug URL-encoding in API paths.

Verified in-browser after fixes: grid loads real photos (fallback only for
hero-less recipes), detail renders with hero + prose + ingredients + steps,
mobile stacks, back button present. `flutter analyze` clean; tests pass.

Approved design (2026-07-15), reference `docs/mockups/p2-read-only.html`:
- **Cards**: full-bleed photo tile with title + tag chips overlaid on a
  bottom dark gradient; a servings badge top-left. Maroon `#960000` identity.
- **Detail header**: two-column on wide screens — title/tags/times-strip/
  description on the left, hero photo on the right; stacks (hero on top) on
  mobile. (Changed from the mockup's full-width-hero-on-top.)
- Ingredients two-column, numbered step cards, download-YAML + favorite
  actions. Real look is Forui components themed to this palette.

## P3 — Auth — **done** (phase code review pending)

Flutter half (2026-07-15): shared Dio (cookie credentials on web via
conditional import, X-Requested-With on every request, 401 interceptor →
signed-out); AuthRepository (me/setup/login/logout/change_password, users,
sessions, tokens); AuthCubit state machine (unknown/setup-required/signed-out/
password-change-required/signed-in) driving go_router redirects
(refreshListenable); screens per approved mockup: login (error + lockout
banners, remember-me), first-run setup, forced password change, settings
shell (sidebar/chips; Account + sessions, Users w/ temp-password reveal,
API tokens w/ one-time reveal), role-aware avatar menu. `/healthz` gained
`setup_required`; `/` serves `public/index.html` when a web build is bundled
(production-shaped same-origin serving; `apps/server/public/` gitignored).
Dev note: cross-origin dev (dart-define SALT_API_BASE) hits a Flutter-web
limitation — image fetches don't send cookies, so photos 401 → placeholder;
preferred dev loop is same-origin: `flutter build web` → copy to
`apps/server/public/` → run the server. Verified in-browser end-to-end on a
fresh instance: setup screen (auto-detected) → admin created → authenticated
grid with photos → settings (Account/sessions, Users, tokens tabs render) →
sign out (notice) → sign in. All 130+ server tests and app tests green.

Server (2026-07-15): migration 002 (users/sessions/api_tokens, hashes only at
rest); Argon2id (OWASP m=19456,t=2,p=1; PHC format; RFC 9106 vector pinned;
timing-equal dummy verify); auth middleware (cookie+bearer, role∩scope,
CSRF, forced-password-change); rate-limited login (5 fails → 1→15 min);
first-boot setup code on stdout; endpoints auth/{setup,login,logout,me,
change_password}, users CRUD + reset_password, sessions, tokens; all prior
endpoints now require auth (images Cache-Control now `private`). 130 server
tests green. End-to-end verified by hand on a fresh instance: setup-code
flow, cookie+bearer, CSRF 403, member forbidden from /users, temp-password
login → password_change_required → change → access, PAT read scope, lockout
429 (even with the correct password). docs/API.md updated. Workflow note:
both endpoint agents stalled at their final step; agent C's work was complete
on disk, agent D's half (users/sessions/tokens routes + tests + API.md) was
written by hand afterward.
Setup flow, sessions (cookie+bearer), CSRF, rate limiting + lockout, roles
(admin full / member read+personal), PATs scoped read|full, users CRUD, login UI.

Approved design (2026-07-15), reference `docs/mockups/p3-auth.html`
(artifact: claude.ai/code/artifact/931e1635-48a0-4876-a257-2e3ddabb6990):
login card w/ lockout state; first-run setup via one-time code from server
logs; settings shell (left tabs: You = Account/Users*/API tokens, Server
(admin) = Tags/Import/Backups/Nutrition); token one-time reveal; role-based
avatar menu. User decisions: sessions 7d unchecked / 90d sliding when
remembered; new users get an autogenerated temp password (shown once) with
forced change at first sign-in.

## P4 — Search + tags — **core done** (commit `ffb833a`, 2026-07-15; tag-style editor UI pending mockup approval)

Server: `fts_compiler.dart` compiles the parsed DSL AST to FTS5 MATCH —
user terms only ever become quoted string literals (injection-proof by
construction); scope→column map; calories constraints collected separately
(AND-only, 422 under `or`); `searchCards` orders by bm25;
`GET /api/v1/recipes?q=` runs it (parse errors → 422); `GET /api/v1/tags`
(counts + styles), `PUT /api/v1/tags/{name}/style` (admin/full/CSRF;
validated Lucide name + `#RRGGBB`); migration 003 `tag_styles`. Gate
`search_corpus_test.dart` seeds all 1,198 corpus recipes and checks
grep-derived counts (`tag:dessert` = 214 exact; stemming-aware bounds for
word searches). App: nav `_SearchField` → `/search?q=`, SearchPage on the
shared RecipeGrid ("N RESULTS · QUERY" eyebrow), syntax-help dialog
documenting the decided semantics, tappable detail-page tag chips.
Verified in-browser: `tag:dessert` → "214 RESULTS" grid. Remaining for P4
close-out: styled TagChip rendering + Settings → Tags editor — mockup
published for approval (2026-07-15):
`docs/mockups/p4-tags.html` (artifact
claude.ai/code/artifact/36b39bb6-c210-4987-97cb-1b1b1a6e3010 — icon +
text/bg colors, presets, live preview, real dessert tag).
Phase review: ran 2026-07-15 together with the P5 review (dedicated
finder over the `ffb833a` diff); findings recorded below with P5's.

Tag-style editor UI shipped 2026-07-15 (mockup approved same day):
styled `TagChip` everywhere (Lucide icon + text/bg colors from
`GET /api/v1/tags`, loaded app-wide on sign-in via `TagStylesCubit`,
default rose chip until styles arrive or when a tag has none);
Settings → Tags tab per the approved design — filter/sort, live chip
previews, inline editor (searchable icon grid over the full generated
Lucide catalog `lucide_catalog.g.dart` [1,991 icons, regenerated by
`apps/app/tool/gen_lucide_catalog.py`], 8 preset pairs, hex fields with
validation, page/photo-tile preview, save/clear). Package decision:
`lucide_icons_flutter` (the package lucide.dev points Flutter users at) +
`file_picker` for editor photo uploads. Browser-verified: styled `dessert`
(cake-slice + raspberry) in the editor → chips restyled on grid tiles,
search results, and the detail page. **P4 complete.**

## P5 — Editing + export + reconciliation + backups — **done** (2026-07-15)

Editor/library mockup `docs/mockups/p5-editor.html` (artifact
claude.ai/code/artifact/10b4f9c8-e983-46c3-86d0-19871b275d07) approved
2026-07-15; Flutter half shipped the same day:
- **Editor** (`/new`, `/r/:slug/edit`; admin-only route guard + hidden
  affordances): raw-first ingredient rows with debounced
  `parseIngredientLine` and parsed/check/no-amount/manual chips,
  expandable structured panel (amounts table with measure/quantity/unit/
  approx/primary, item/prep, re-parse + hand-edit lock), drag-reorder for
  rows/headers/steps, group headers, bulk **Paste a list…** dialog with
  live parse preview (`Header:` lines become groups), step cards with
  optional labels, photo upload (`file_picker`) + from-URL + credit
  (photos enabled after first save — a new recipe has no id yet), danger
  zone delete with confirm, dirty tracking (title-bar dot, save bar,
  discard-changes confirm on Cancel/back), save → detail navigation.
  Merge-semantics payload: the editor sends exactly the editable keys, so
  times/subsections/techniques survive untouched.
- **Favorites & notes**: heart toggle on detail (optimistic, SnackBar on
  failure), private My-notes card (view/edit, "only you" badge), heart
  badges on grid tiles (tap = unfavorite, optimistic), `/favorites` page,
  avatar-menu entries (Add recipe [admin], My favorites).
- **Settings → Library** (admin): rescan with report rendering (in-sync /
  updated/added/re-exported/skipped/conflict lines), backups table
  (create with include-photos option, download via browser, delete with
  confirm).
Browser-verified end-to-end on the real library: create via paste dialog
→ YAML appeared at `library/my-recipes/recipes/<id>.yaml`; edit (tag add)
→ export rewritten with `- celebration`, tag appeared in Settings → Tags;
favorite + note round-trips; favorites page; rescan clean over 1,198
files; manual backup; delete → row + YAML gone with an automatic
`before-delete` backup. Two real bugs found by the walkthrough and fixed:
unkeyed BlocProviders on parameterized routes (navigating detail→detail
kept showing the old recipe under the new URL — detail + editor now keyed
by slug, matching SearchPage), and the tag input dropping half-typed text
(now commits on blur, not just Enter). UI review record below.

### P4/P5 UI code review record (2026-07-15)

Three finder angles over the Flutter diff (state-management correctness /
API contract / UX-robustness+quality): 27 raw findings, 17 unique after
cross-angle dedup — the angles independently converged on the top two.
**All fixed except one documented deferral**:

- **Typing loss (HIGH, found by all three angles)**: ingredient raw text
  was committed to state only on a 350ms debounce, so a fast Save (or the
  leave-check) could silently drop the last keystrokes, and any other
  row's state emit could clobber a focused field via `didUpdateWidget`.
  Fixed structurally: raw text now commits to the cubit synchronously on
  every keystroke (only the *parse* is debounced), and `_BoundField` never
  syncs state into a focused field.
- **Note wipe (HIGH, all three angles)**: toggling Favorite emitted a
  detail copy whose `copyWith` cleared the private note by default — the
  note vanished from view and could be permanently overwritten. `copyWith`
  now preserves the note unless explicitly cleared.
- **Curated-data protection**: typing in a loaded line whose structured
  fields differ from parser output (human-curated corpus lines) no longer
  silently replaces them — such lines load locked (`manual` chip);
  re-parse is explicit.
- **Async hygiene**: `isClosed` guards after every await in Editor/Detail/
  List/TagStyles cubits (leaving a page mid-request threw StateError);
  list cubit now merges pages/reverts against the *latest* state instead
  of pre-await snapshots (interleaved unfavorite + pagination could
  resurrect cards or skip a page); favorite toggle has an in-flight guard.
- **Save/upload race**: Save is blocked (and disabled) during photo
  uploads, and the PUT only includes the `images` block when the credit
  actually changed — hero/gallery are owned by the image endpoints, so
  merge semantics can no longer unlink a just-uploaded photo.
- **Contract/UX**: per-request timeouts for backup (10 min) / rescan
  (5 min) / uploads (5 min) instead of the global 20s; browser/system back
  now gets the discard confirm (PopScope, best-effort on web); a failed
  note save keeps the editor open; first added amount defaults to primary;
  tag input keeps focus on Enter; confirm dialogs focus their safe action;
  favorites page has its own empty-state wording; group/step label width
  caps actually apply; the three copies of the Dio→RepositoryException
  mapping collapsed into one shared `apiGuard`; status ok/warn/err colors
  centralized in `SaltColors`.
- **Deferred**: every keystroke rebuilds the editor page (scaffold-level
  `context.watch`) — measured as imperceptible at this form size on
  desktop web; revisit if the editor grows column layouts or the form gets
  hundreds of rows.

Post-fix verification: analyzers clean, 357 tests green, web rebuilt, and
a live regression pass against the running server (raw-line edit → save →
YAML export; corpus file copied over the export → rescan → file won and
was normalized back to canonical v2).

Server (all tested against real corpus data; 216 server tests green):
- **Ingredient parser** (`salt_shared`): Dart port of the Recipe
  Extraction `ingredient_parser.py` + leading-quantity recovery, validated
  line-by-line against all 16,510 corpus ingredient lines — 99.79%
  primary-amount agreement, 99.1–99.4% item/prep; 98.6% of disagreements
  are self-flagged by the `parsed/check/none` confidence signal. Corpus
  agreement test enforces dated floors.
- **CRUD**: `POST/PUT/DELETE /api/v1/recipes` (admin ∩ full + CSRF).
  Create generates `manual-<date>-<slug>` ids under library source
  `my-recipes`; PUT has merge semantics (present keys replace, null
  clears, absent untouched) with stable slugs; server renumbers steps,
  derives `serves`, normalizes tags; caps guard against balloon documents.
  Every save exports canonical YAML atomically.
- **Reconciliation**: save-time conflicts keep the hand edit as
  `<id>.conflict-<ts>.yaml` (DB wins); `scanLibrary` (boot +
  `POST /api/v1/library/rescan`): clean hand edit wins + file normalized
  to canonical, malformed skipped with reason (DB stays), missing exports
  re-materialized, hand-dropped new files imported, conflict copies
  surfaced; report persisted (`GET /api/v1/library`).
- **Backups**: streamed tar.gz (library YAML + `VACUUM INTO` snapshot) via
  `package:archive`; images excluded by default (`include_images` for full
  copies); triggers: manual endpoint, before every recipe delete, daily
  timer (+boot catch-up); retention 14; strict name pattern doubles as
  path containment for download/delete.
- **Favorites & notes** (migration 004): per-user, DB-only;
  `PUT/DELETE .../favorite`, `GET/PUT/DELETE .../note`;
  `?favorites=true` filter; cards/detail carry the caller's flag+note.
  Read-scope PATs may write personal data (documented P3 exception).
- **Images**: `POST .../images` raw-body upload (magic-byte JPEG/PNG/WebP,
  25 MB cap enforced while streaming, server-generated names) and
  `POST .../images/from_url` (SSRF guards: scheme, public-address DNS
  validation incl. IPv4-mapped IPv6, per-hop redirect re-validation,
  content-type + magic bytes, size/time caps).
- **Legacy v0 importer**: `--legacy` (auto-detected `_recipes/` layout)
  maps the old Flask format to schema v2 (description→background,
  prep/cook/ready→times, flat ingredients→parser-structured lines,
  image/imagecredit, source URL; Edamam calories dropped loudly); tested
  against the real sample recipe in `saltToTaste/sample/`; idempotent.

### P4 + P5 code review record (2026-07-15)

Three finder angles over the P5 diff (security / correctness /
API-contracts+tests, 20 raw findings) plus a dedicated finder over the P4
commit `ffb833a` (11 findings — P4's own review had been skipped);
triaged inline, 3 cross-angle duplicates. **All confirmed findings fixed**,
221 server tests green after fixes:

- **Security**: backup *download* now requires full scope (the archive
  holds the DB snapshot — credential hashes/private notes — which no other
  endpoint returns; a leaked read PAT could have exfiltrated it);
  `readJsonBody` now enforces a 2 MB cap *while reading* (no JSON body
  could previously balloon memory before field-length checks); FTS terms
  with control characters (NUL crashed FTS5 into an opaque 500) are 422s;
  `q` capped at 512 chars (CPU DoS); SSRF fetch re-validates the socket's
  actual remote address after connect (narrows the DNS-rebinding TOCTOU to
  one side-effect-free GET; remaining sliver documented).
- **Correctness**: legacy-import ids now derive from the unique *file name*
  (duplicate titles silently overwrote each other — verified empirically by
  the reviewer) and `extracted_at` from the source file's mtime (a
  wall-clock date made every later-day re-run an "update" that clobbered
  in-app edits); the scan refuses duplicate ids across source dirs (copies
  fought over the DB row on every scan, churning forever); all three
  import/scan paths resolve slug collisions *before* encoding (DB doc,
  content hash, and exported YAML could disagree); conflict copies and
  backups uniquify same-second names (a preserved hand edit could still be
  overwritten); backup listing/pruning orders by real creation time (name
  sort misordered same-second `-N` archives, pruning newer before older);
  conflict-copy classification uses the exact generated shape (an id
  containing ".conflict-" was permanently misclassified);
  `attachRecipeImage` validates the merged document (40-image gallery cap
  was bypassable upload-by-upload, then bricking every later PUT) and both
  image routes validate `role` before writing bytes (no orphan files).
- **P4 search**: separator-only terms ("mac & cheese"'s `&`) are dropped as
  noise instead of AND-ing the whole query to zero results; bm25 ordering
  gained a title tiebreaker (equal scores are the norm for tag queries;
  OFFSET pagination needs a stable order); `PUT /tags/{name}/style` 404s
  for tags no recipe carries; detail-page chips escape quotes/backslashes
  when building `tag:` queries; resubmitting the same query on /search now
  refreshes in place (was a visible no-op); four committed `.DS_Store`
  files untracked + gitignored.
- **Tests strengthened** (reviewer-confirmed gaps): favorites filter now
  proven to *narrow* (second unfavorited recipe; per-user independence;
  `favorites=true&q=` covers the search-path SQL); 404/422/405-with-Allow
  negative paths for every new endpoint; backup test restores `salt.db`
  from the archive and queries it (was only checking the entry name);
  compiler tests pin the decided scope-binds-one-term semantic, noise-term
  dropping, control-char 422, and the handler-level parse-error → 422
  mapping.
- **Deferred with rationale**: `tag:` scope matches at token level via the
  space-joined FTS column, so a *multi-word* tag phrase could match across
  two adjacent tags — latent (corpus has only single-word `dessert`);
  proper fix is relational `tag:` compilation, scheduled with the tag
  editor. DNS-rebinding beyond the post-connect check: accepted risk for a
  self-hosted admin-only endpoint, documented in code.
- **Ingredient-parser follow-up** (from the contracts angle): the three
  drifted unit vocabularies became one `_unitVocabulary` table everything
  derives from; `fluid ounce`/`fl oz` parse as a real volume unit;
  unit-like-but-unknown tokens flag `check` instead of silently parsing as
  count; exact same-measure parentheticals (`1 cup (240 ml) milk`) become
  secondary amounts. Corpus floors re-verified (99.76% primary agreement;
  the only lines whose parse changed are seven champagne-cocktail
  fluid-ounce lines the Python extractor itself had misparsed — the Dart
  parser now reads them correctly). 121 salt_shared tests green.

## P6 — Nutrition (USDA FDC) — **server half done** (2026-07-15; label UI pending mockup approval)

Nutrition mockup published for approval (2026-07-15):
`docs/mockups/p6-nutrition.html` (artifact
claude.ai/code/artifact/961cb020-f089-4d3d-8411-6b1db96f5cd0): classic FDA
label in the detail right rail with match-transparency badge + empty/stale
states, the per-ingredient review sheet (confirm / re-pick / set grams /
skip with gram-source provenance), Settings → Nutrition (write-only key,
bulk compute progress), and the `calories:` search strip.

Server (user's real api.data.gov key; 235 server tests green):
- Migration 005: `fdc_search_cache`/`fdc_food_cache` (the vocabulary
  repeats — a recipe re-compute is request-free), `ingredient_matches`,
  `recipe_nutrition` (calories denormalized + indexed for search),
  `nutrition_jobs`.
- `UsdaFdcProvider`: key read live from settings (write-only API,
  masked reads, sent as the `X-Api-Key` HEADER so it can never hit a log),
  token bucket 900 req/hr with FIFO waits, 429 backoff, timeouts.
- Matcher: normalization (stop-words, parentheticals, water/ice matched
  locally for free, FDC-vocabulary synonyms: unsalted→"without salt",
  confectioners→powdered, bittersweet/semisweet→dark), token-overlap
  ranking with Foundation/SR-Legacy bonuses and modified-form penalties
  (egg *white*, *decaf*, *drink mix*, *syrup* lose to the plain form
  unless asked for).
- Gram resolver in confidence order: printed weight direct (incl. the
  secondary of ATK's dual amounts — flour 8¾ oz → 248.06 g exactly),
  volume → the food's own portions → ~55-staple density table, count →
  piece weights; ranges take midpoints.
- Real-FDC quirks discovered by testing with the live API and handled:
  search returns superseded records whose detail endpoint 404s (the
  search payload's own nutrient list stands in — portions lost only);
  some records omit whole macros (Foundation butter has no energy or
  saturated fat!) — macro-complete candidates are preferred and missing
  energy derives via Atwater 4/9/4.
- Aggregation → the legacy app's ~30-nutrient panel with current FDA
  Daily Values; per-serving basis defaults to parsed serves-min, editable
  (instant recompute). Status complete/partial + read-time staleness via
  an ingredients hash. Overrides (confirm/re-pick/set-grams/skip) persist
  through re-matching.
- Endpoints: settings/fdc_key, nutrition GET/PUT, compute, matches
  GET/PUT, bulk job + progress (failures logged per recipe, never
  silent). `calories:` filter + ascending ordering LIVE in search.
- Tests against RECORDED REAL FDC responses
  (`test/fixtures/fdc/`, regenerated by `tool/record_fdc_fixtures.dart`
  with `SALT_FDC_KEY`): the P6 gates — Bundt flour/sugar matched by
  printed weights; review flow (12/13 → skip garnish → complete);
  overrides survive; cache eliminates repeat searches; serving-basis
  rescale; `calories:` filter/order incl. combined text query.
- Live acceptance on the dev instance with the real key: key stored via
  the API (masked round-trip), Bundt computed in 21 s cold — 466 kcal,
  sat fat 10.3 g (51% DV), cholesterol 127 mg (42% DV) — garnish skipped
  via the API → complete; `calories:<500` returns exactly the Bundt,
  `calories:<400` honestly empty.

P6 server review (3-angle, 2026-07-15): 19 findings, 13 unique, all
fixed (244 tests green):
- **HIGH — staleness laundering** (empirically confirmed): a serving-basis
  PUT or match override after an ingredient edit recomputed against the
  edited recipe and stamped its fresh hash, silently clearing `stale`
  with wrong totals (orphaned match rows could even yield "13/12
  matched"). Now only `matchAndCompute` stamps the current hash
  (`freshMatch`); plain recomputes keep the stored hash, filter match
  rows to live positions, and clamp `matched_count`. HTTP regression
  test: edit → basis change stays `stale` → compute clears it.
- Match rows whose stored `raw` no longer equals the line's text are
  treated as unreviewed by the matches GET and reset by overrides — a
  pre-edit decision (or its hand-set grams) never silently applies to
  new text.
- `GET …/matches` candidates are now cache-only: a member read can never
  spend the FDC budget or block on the rate limiter.
- Token bucket: interactive provider caps rate-limit waits at ~30s
  (`422` with an explanation) while the bulk provider waits unbounded —
  two `UsdaFdcProvider` instances sharing one bucket; the response body
  read got its own timeout; "FIFO" doc claim softened (poll-based, only
  approximately ordered).
- Bulk job: yields the event loop between recipes (fully-cached streaks
  starved interactive requests); jobs left `running` by a crash are
  marked `failed` at boot (they polled as running forever).
- `searchCards` always LEFT JOINs `recipe_nutrition`, so text-only
  search results carry `calories_per_serving` for the tile badge.
- Grams-only override on a line with no matched food → `422` (was a
  silent nothing-contributes no-op).
- Portion matching via free-text description now requires a parseable
  leading amount ("0.25 cup" scales; bare "cup, sifted" is rejected —
  gramWeight-per-unknown-amount quadrupled some estimates).
- Serving-basis PUT: permission checks before existence (joins the 403
  matrix), `NutritionProviderException` → 422, `serves: 0` basis guard.
- Tests: serving-basis PUT added to the permission matrix;
  `FixtureProvider` moved to `test/support/fdc_fixtures.dart`;
  success-path HTTP tests (compute → label → basis → review → stale
  lifecycle) over recorded real FDC data; TokenBucket wait-cap unit
  tests.

## P7 — Settings + import UI + Docker — **pending**
Settings tabs, import wizard, multi-stage Dockerfile (Flutter web → dart_frog
AOT compiled in-image → slim runtime + libsqlite3, `VOLUME /data`, non-root
user, HEALTHCHECK, multi-arch amd64+arm64), security headers. Server must ship:
SPA deep-link fallback (non-API GET → index.html), env-var config (PORT,
DATA_DIR, LOG_LEVEL, TRUST_PROXY, TZ), X-Forwarded-Proto trust for Secure
cookies behind reverse proxy, SIGTERM graceful shutdown (drain + clean SQLite
close). Document: /data must be local fs (no NFS/SMB); domain-root serving
assumed (sub-path deferred).

## P8 — Parity audit + cutover — **pending**
Checklist vs old app, delete Python tree, promote Dockerfile, README, Forui
upgrade pass.

## Decision log (deviations & clarifications)

- 2026-07-14 — Backend must be deployable as a Docker container (user):
  already covered by P7 single-container design; noted ARM multi-arch as a
  P7 consideration.
- 2026-07-14 — Search semantics (user decision): keep modern conventions over
  old-app parity — scope prefixes bind a single term/phrase, adjacent terms
  AND everywhere; the P4 search-help UI must document both, since old-app
  queries return different results.
- 2026-07-14 — Container hardening specifics added after user question: SPA
  deep-link fallback route, X-Forwarded-Proto trust for Secure cookies,
  non-root user, SIGTERM graceful shutdown, HEALTHCHECK, env-var runtime
  config, local-fs-only /data caveat, domain-root serving assumption
  (sub-path support deferred).
- 2026-07-15 — Backups exclude image files by default (plan said "tar.gz of
  `library/`"): images are 461 MB of the 472 MB library, are never touched
  by destructive operations, and self-heal on re-import — including them in
  the automatic before-delete/daily backups would cost ~0.5 GB×14 retention
  for no recovery value. `POST /api/v1/backups {include_images: true}`
  still produces the full archive. `package:archive` chosen for pure-Dart
  tar.gz (no `tar` binary in the slim Docker runtime; no real alternative
  package, so no user package-decision was needed).
- 2026-07-15 — PAT scope semantics refined per the P3-documented model:
  `read` PATs may write **personal** data (favorites, private notes) —
  they affect only the token's owner — while every shared-state mutation
  keeps requiring `full`. Recorded in docs/API.md.
- 2026-07-15 — Recipe `PUT` uses merge semantics (present keys replace,
  explicit null clears, absent keys untouched) rather than full-document
  replacement: single-field script updates can't accidentally wipe data;
  the editor always sends full documents so UI behavior is identical.
- 2026-07-15 — Legacy v0 `calories` values are dropped on import (with a
  per-file warning + extraction warning) rather than seeded into the DB:
  P6 recomputes nutrition from FDC with per-ingredient provenance, and old
  Edamam numbers would be indistinguishable from computed ones.
