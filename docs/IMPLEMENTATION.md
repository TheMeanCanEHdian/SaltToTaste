# Implementation Tracker

Living status of the approved rewrite plan (kept locally, not in the
repo). Statuses: `pending` / `in-progress` / `done` / `changed(reason)`.

Last updated: 2026-07-16

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

## P3 — Auth — **done** (review record below, 2026-07-16)

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

### P3 code review record (2026-07-16)

Run at last — P3 was the only phase whose review had never happened, which is
how the security-sensitive surface ended up the least examined. 7 lenses ->
7 claims -> 6 survived, 1 killed by the panel. Evidence-gated adjudication (see
`.claude/REVIEW-PROCESS.md`): 6 findings carried reproductions and took the
verify path; the 1 argued claim escalated and all 3 refuters killed it.

**Three lenses found NOTHING, which is the good news and worth recording:**
`pat-scope` (the role INTERSECT scope invariant holds — every one of the 24
route files is guarded, a `read` PAT cannot mutate, a member cannot reach an
admin action), `secrets-and-logging` (no token, password, recovery code or FDC
key reaches a log line, an error envelope or a URL), and `recover-and-setup`
(single-use is enforced in fact, the expiry is server-side, setup cannot be
re-run to mint a second admin). The critics confirmed no false positives among
the survivors and that sessions/PATs have no IDOR.

**Killed by the panel:** "no rehash-on-login path". Correct on mechanism, but
the Argon2id parameters are compile-time constants with no writer that could
produce a weaker hash, so the input is unreachable. 3/3 refuted.

**Survivors — all open, none fixed yet (several need a policy decision):**

| sev | finding |
|---|---|
| MED | **Admin password reset does not revoke the target's PATs**, while its own doc says it "signs the user out everywhere". Reproduced end to end: an attacker PAT returns 200, then 403 during the `must_change_password` freeze, then **200 again** once the victim completes the forced change. `recoverAdmin` already revokes tokens on the neighbouring path for exactly this reason. |
| MED | **`TRUST_PROXY=true` trusts `X-Forwarded-For` from any peer**, with no check that the socket peer is the proxy — so login rate limiting is bypassable in the README's own documented deployment. |
| MED | **"Remember me" is a no-op on web**: the cookie carries no `Max-Age`/`Expires`, so the 90-day sliding session dies when the browser closes. |
| MED | **The recovery code is a ~40-bit admin-granting secret stored as unsalted SHA-256** (8 chars over a 31-symbol alphabet = 31^8), which its own docstring's guarantee does not survive. |
| LOW | **Login CSRF**: `/auth/login` accepts any Content-Type, so a cross-site form can sign a victim into the attacker's account. |
| LOW | **No test pins the real `middleware()` chain** — a reorder that strips CSP/X-Frame-Options from the app shell keeps all 296 tests green. The cause is mechanical: `middleware()` hard-binds process globals, so it cannot be imported by a test without a real `initServer()`. |
| MED | **Availability was never a lens** (found by a critic): no lens asked whether an unauthenticated attacker can stop the server serving. |
| LOW | The deliberate login/recovery rate-limit split is defeated by a **key-namespace collision** (`recover|<ip>` vs `<ip>|<username>` in one flat map, username unvalidated) — a rider on the XFF finding, closed by the same fix. |

**Five are now fixed** (`769920d`, `79b2476`) — the three policy calls after the
user made them (revoke PATs on reset; peer-check `X-Forwarded-For` via the new
`TRUSTED_PROXIES`; lengthen the recovery code to ~59 bits), plus the two that
needed no decision (`Max-Age` on the remember-me cookie; `application/json`
required on request bodies). Each is mutation-checked, and the XFF work also
closed the older shared-bucket entry and the key-collision rider.

**The first fix was wrong, and the second review caught it** (`d95a9d6`). The
peer check shipped inert: the binary binds `anyIPv6`, so an IPv4 peer arrives
as `::ffff:172.17.0.2` and never matched the `172.17.0.0/16` the code's own
comment offers as the example. It compounded — `isSecureRequest` shares that
check, so the cookie lost `Secure` while the new `Max-Age` made it persist 90
days: strictly worse than shipping nothing. The test asserted
`isTrustedProxy("127.0.0.1")`, a string the author invented, and passed
throughout.

**Reviewing that fix (`d95a9d6`) found six more, all verified, and three were
the same defect as the original**: a load-bearing security guard with no test.
Deleting the `::ffff:` prefix loop (a hostile `2001:db8::ffff:172.17.0.2`
becomes the trusted proxy), deleting the peer check, or replacing
`isSecureRequest` with `=> false` each left **320/320 green**. The only
assertion on `Secure` in the whole repo was a NEGATIVE one, which a
permanently-broken implementation satisfies. Now fixed and mutation-proven at
335 tests: `secure_cookie_http_test.dart` drives the real login route over a
real socket and pins both routes to a `Secure` cookie; `trusted_proxy_test.dart`
pins each unmapping guard against an address chosen so only that guard stands
between it and a false match. `_asIpv4` also now canonicalises IPv4 from the
BYTES — dart:io echoes the input back, so `010.0.0.5` never matched
`10.0.0.5`, correct config failing closed in silence.

**Boot now reports config that looks set up and is not** (`configWarnings`,
extracted from `_initAuthRuntime` so it is testable at all): an entry that can
never match (`fd00::/8` — an IPv6 CIDR is unsupported — or a Compose service
name) was previously silent, because the only warning was gated on the list
being EMPTY. This also closes the recorded mirror case, `TRUSTED_PROXIES` set
with `TRUST_PROXY` unset. Verified on the rebuilt binary, which named the two
bad entries and left the good one alone.

**One LOW remains**: nothing pins the real `middleware()` order (blocked on a
small refactor — it hard-binds process globals, so a test cannot import it; the
`configWarnings` extraction is the same shape of fix and a template for it).
The rate-limit key collision is closed with the XFF peer check.

**Availability — first pass, 2026-07-17 (task #42), PARTIAL.** The workflow run
was VOID: its finder worktrees were provisioned at `9497e68` (the deleted
Python tree), so most agents had no `apps/` to test — the recurring
worktree-provisioning bug, not a code result. The top leads were instead
measured BY HAND against a rebuilt server:

- **REFUTED — Argon2 does not stall the event loop.** 100 concurrent bogus
  logins (each pays the full 19 MiB / t=2 hash via `dummyVerify`), and
  `/healthz` stayed 2-50 ms throughout. The argon2 binding runs off-isolate;
  the `await` is real. A whole class of "cheap login floods the CPU" finding is
  dead.
- **REFUTED — no unbounded body buffering.** `readJsonBody` rejects on
  `Content-Length` before reading and aborts the stream past 2 MiB, so a 200 MB
  POST to `/auth/login` returns 422 with RSS *falling* afterward (the +137 MB
  in a first measurement was Argon2 residue from a preceding burst — a
  confounded probe caught by re-measuring on a fresh server).
- **FIXED — MED: a member could mint personal access tokens without bound.**
  Session logins are always full-scope so `requireFullScope` does not gate on
  role; a token row is permanent (revocation is an UPDATE, never a DELETE); and
  the create path re-read the user's whole list. Reproduced live (200 rows, no
  rejection). Now capped at 20 live tokens/user, and the create does a
  single-row read. `maxActiveTokensPerUser` in `token_handlers.dart`,
  mutation-checked.

**Still UNTESTED** (the void run never reached them, and hand-measuring stopped
at the top leads): FTS/DSL superlinearity on a crafted `q=` (member-reachable),
and the critic's exotic vectors — slowloris, SIGTERM drain completion,
disk-fill during YAML export/backups, uncancellable jobs blocking the next, and
recursion on attacker-shaped input (nested quotes, deep YAML). A re-run needs
the worktree provisioning fixed first, or hand-measurement continued.

**One LOW residual on the token fix:** the active cap bounds *usable* tokens,
but a mint+revoke loop still adds permanent rows (revoked rows are never
deleted) and `GET /tokens` is unpaginated. Slow (two requests per row) and
lower-severity than the capped abuse; a retention policy for revoked rows is a
data decision left for the user rather than invented here.

**One LOW remains from P3**: nothing pins the real `middleware()` order (blocked
on the same process-globals refactor as the boot-warning call site — `#44`).

## P4 — Search + tags — **done** (core in `ffb833a`, 2026-07-15; the tag-style editor shipped against the approved `docs/mockups/p4-tags.html`)

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

## P6 — Nutrition (USDA FDC) — **done** (2026-07-15)

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

Flutter UI (mockup approved 2026-07-15; browser-verified same day on the
dev instance against the real computed Bundt data):
- `NutritionRepository` + `NutritionCubit` (keyed by slug next to the
  detail cubit; compute uses a 5-min receive timeout).
- `NutritionPanel`: classic black-on-white FDA label (deliberately
  theme-independent — the regulation label IS the design), match
  transparency badge (green complete / amber review), empty states
  (admin Compute button vs member notice), stale banner with Recompute.
  Wide: right rail under the hero. Narrow: after the content with the
  badge ABOVE the label (approved mobile layout).
- Review sheet dialog: per-line provenance (matched food, data-type
  chip, grams + source: weight ✓ direct / household portion / density
  est. / piece est. / set by hand), confidence pills, admin actions
  Confirm / Change… (ranked candidate picker) / Set grams… (hidden for
  rows with no matched food — the server 422s those) / Skip / Include
  again, and the per-serving basis stepper (live rescale verified:
  12→13 recomputed 466→430 kcal instantly).
- Settings → Nutrition (replaces the "soon" placeholder): write-only FDC
  key (masked pill + Replace flow, never re-read), bulk "Compute all
  missing" with 2s job polling, progress bar, failure log toggle, and
  the serving-basis explainer.
- Recipe tiles: dark card badge "466 kcal" beside the servings badge
  once computed — text-only searches carry it too (server LEFT JOIN
  fix).

P6 UI review (3-angle: correctness / mockup fidelity / robustness,
2026-07-15): 30 findings, all triaged; 20 fixed, the rest recorded below.
Fixed highlights:
- `copyWith(matches: null)` was a no-op (null means "keep"), so a
  recompute could never invalidate the cached review-sheet rows —
  actions could target lines the server had re-matched. Now an explicit
  `clearMatches` flag.
- An override whose follow-up label refresh failed threw away the
  server-persisted match list; now the fresh rows are emitted before the
  label GET, and its failure says "Saved, but refreshing failed".
- One transient poll failure permanently killed bulk-job progress
  tracking (and the job id with it); polling now rides out blips and the
  active job id survives settings-tab switches (module-level, re-attach
  on mount). The 409 "already running" message actually reaches the
  user now (`conflict` added to the apiGuard passthrough codes).
- Review sheet: a failed load showed an infinite spinner — now an error
  with Retry; per-open `TextEditingController` leak fixed; phones get
  the spec'd full-height bottom sheet; header gained the summary line
  ("13 lines · 12 matched · 1 skipped · computed …"); Foundation
  data-type chips highlight green.
- Label: Recompute hidden from members; badge is the mockup's bordered
  pill (alert triangle, chevron, full-width on mobile); the green state
  now also requires zero unreviewed low-confidence matches (new
  `low_confidence` field in the nutrition GET); FDA details ("Includes
  Xg Added Sugars", italic *Trans* only, bold Amount-per-serving, black
  rules); empty state matches the mockup copy without double-heading
  the narrow layout.
- `compute()` now carries a CancelToken cancelled on cubit close (was
  holding a browser connection up to 5 min after navigating away).
Deliberate deviations (recorded, not bugs): the review sheet keeps the
stacked row anatomy at all widths (the mockup's desktop 5-column grid
presents the same data; revisit if it grates), grams edit stays a
dialog, no free-text FDC search in the re-pick list (needs a new
endpoint — P7 candidate along with bulk Pause), no sheet footer
buttons (totals recompute on every action, Close is the header X).


## P7 — Settings + import UI + Docker — **done** (2026-07-15)

Server half (built, 254 tests green):
- SPA deep-link fallback middleware: non-API extension-less GET 404s serve
  `public/index.html` (API/`/healthz`/`/images` and asset misses keep
  their JSON 404); sits outside the error handler, inside the logger.
- Security headers on every response (`nosniff`,
  `Referrer-Policy: same-origin`) + CSP/`X-Frame-Options: DENY` on HTML.
- SIGTERM/SIGINT graceful shutdown: drain (8s bound, then force), stop
  the backup timer, close SQLite (WAL checkpoints away — clean next
  boot). `isSecureRequest` (X-Forwarded-Proto behind TRUST_PROXY) already
  existed from P3.
- Import jobs API: `IMPORT_DIR` allowlist root (default
  `DATA_DIR/import`, auto-created), `GET /api/v1/import/candidates`
  (v1/legacy detection, depth ≤ 1), `POST /api/v1/import {path}` with
  canonical containment (traversal/symlink escapes 422; folder names
  with spaces — the real corpus — allowed), job runs in `Isolate.run`
  with its own DB connection + throttled per-file progress,
  `GET /api/v1/import/jobs/{id}`, orphaned `running` jobs failed at
  boot. Migration 006 extends the 001 `import_jobs` table (legacy /
  imported / updated columns). Permission matrix extended.
- Tests: real corpus files as the v1 root and the legacy app's shipped
  sample as the v0 root inside a temp import dir — candidates,
  containment negatives (incl. symlink escape), end-to-end job to done,
  idempotent re-run, legacy auto-detect + v2 mapping, failed-job
  visibility, boot reconciliation; SPA fallback + header tests in the
  middleware suite.
- `Dockerfile` (repo root): 3 stages (cirruslabs Flutter 3.44.0 web build →
  dart 3.12.2 dart_frog AOT via workspace resolve minus apps/app →
  bookworm-slim with libsqlite3-0/ca-certificates/tzdata, non-root
  `salt`, VOLUME /data, compiled `/app/healthcheck` probe — no curl in
  the image); `.dockerignore`. Three real-world fixes found by the
  container walkthrough: bookworm ships only `libsqlite3.so.0`
  (unversioned symlink added, arch-agnostic); dart_frog wires its
  static handler only when `public/` exists at BUILD time (`mkdir -p
  public` in the server stage); the Flutter engine defaults to Google
  CDNs for CanvasKit/Roboto, which the same-origin CSP rightly blocks —
  web builds now use `--no-web-resources-cdn` (fully offline app,
  matching the hard-local-copy goal; CLAUDE.md dev command updated).

Container walkthrough (real image, corpus mounted `:ro`): first-boot
setup code → admin created → `import/candidates` detects the 1,198-file
ATK root → `POST /import` runs to `done` (1,198 imported, 0 warnings) →
idempotent re-run → traversal `../etc` rejected → deep-link
`/r/rich-chocolate-bundt-cake` refresh boots the app under the CSP →
`docker stop` drains and logs "Shutdown complete" → volume holds only
`salt.db` (no `-wal`/`-shm`) → restart persists 1,198. Image 243 MB.

P7 server review (3-angle: correctness/concurrency, security,
robustness/ops; 2026-07-15): 262 tests green. Fixes applied:
- **Drain was a no-op** — `HttpServer.close(force:false)` completes when
  the listen socket closes, NOT when active requests finish, so `exit(0)`
  killed in-flight handlers (a committed save the client never learns
  about). Now polls `connectionsInfo().active` to a 5s bound before
  force-close.
- **Existence oracle** — `resolveImportPath` accepted absolute paths and
  resolved them on disk before the containment check, so distinct error
  strings for `/etc/passwd` vs `/etc/nonexistent` leaked host-path
  existence. Added a purely lexical `_lexicallyInside` gate BEFORE any
  filesystem access.
- **Dotted recipe slugs** — the SPA fallback's "dotted last segment = a
  missing asset" rule broke deep links to hand-edited slugs like
  `st.-louis-…`; `/r/` paths are now exempt.
- **Unreadable dirs bricked candidates** — a root-owned 700 child in a
  `:ro` mount threw `PathAccessException` → 500 for the whole listing;
  per-child and top-level `listSync` are now try/skip.
- **`.yml` count mismatch** — candidates counted `.yml` files the v1
  importer ignores (silent 0-import); v1 counts `.yaml` only now.
- **SPA read race** — the fallback (outside the error handler) read
  `index.html` unguarded; a mid-redeploy `rm`/`cp` window threw an
  unenveloped 500. Wrapped in try/catch → falls through to the 404.
- **Ops**: job log capped at 500 warnings (+ "N more" note) so the
  polling UI can't re-download an MB-scale array; Dockerfile restructured
  (pubspecs+lockfile before sources for cache; `--enforce-lockfile`;
  `dart_frog_cli` pinned to 1.2.14; `HEALTHCHECK --start-period=120s
  --retries=5` for big first-boot scans); `.dockerignore` adds
  `.claude`/`.DS_Store`.
- Tests added: HTTP-level import success paths (candidates shape, 202 +
  job poll to done, 409 single-flight race, 422 non-string/outside path,
  404 unknown/non-numeric job id) and SPA fallback with a query string +
  dotted slug.

Import wizard mockup approved 2026-07-15 (`docs/mockups/p7-import.html`)
and built as Settings → Import (`import_tab.dart` + `import_repository.dart`,
replacing the "Import — soon" placeholder):
- Detected source-folder rows (kind chips: Recipe Extraction teal /
  Legacy v0 amber), per-row Import button, one import at a time (others
  disable while a job runs), Refresh, empty state with the server's real
  import path, and the explainer. Terminal summary + expandable warning
  log (capped at 60 lines inline, plus a "N more" pointer). Job polling +
  cross-tab re-attach mirror the Nutrition tab's bulk-compute idiom.
- Mobile (< 720px): the Import button drops full-width under the name so
  long folder names aren't squeezed (approved section-4 layout).
- Browser-verified end to end against a real import dir (ATK corpus
  files + the legacy app's sample): candidates detected, import → live
  progress → terminal summary, the warning log renders, idempotent
  re-run skips, desktop + mobile.

**Font regression fixed (found during the Import walkthrough):**
`--no-web-resources-cdn` (added for the offline container) leaves
CanvasKit unable to resolve generic CSS font families, so every
`fontFamily: 'monospace'` and the FDA label's `'Helvetica'` rendered as
INVISIBLE text (the import log and mono paths were blank). Bundled
RobotoMono (Apache-2.0, from the Flutter cache) and repointed all
`monospace` usages (import_tab, nutrition_tab, secret_reveal,
search_page) to it; the FDA label drops `'Helvetica'` for the bundled
Open Sans. This was a latent regression across P4/P6 UI, not new to P7 —
it only surfaced because the offline build changed CanvasKit's font
fallback.

## P8 — Parity audit + cutover — **done** (2026-07-15)

- **Parity audit** (`docs/PARITY.md`): every user-facing feature of the
  legacy Flask app inventoried and verified against the v2 codebase by an
  independent multi-agent pass (parallel verifiers over feature groups +
  a completeness critic reading the whole old app). Result: full
  functional parity — all 19 features covered/improved, plus search
  (fully present, added to the matrix). Only intentional differences (no
  anonymous/no-auth mode, always-on backups with fixed retention 14,
  Edamam→FDC, API-key→PATs, Font Awesome→Lucide) and one minor known gap
  ("Save and add another" bulk-entry button — not carried over).
- **Cutover**: legacy `saltToTaste/` Python tree removed (git-recoverable;
  its one v0 recipe preserved as
  `apps/server/test/fixtures/legacy-v0/`, the two legacy-importer tests
  repointed there). Legacy `Dockerfile`/`saltToTaste.py`/`requirements.txt`
  deleted; the P7 `docker/Dockerfile` promoted to the repo root (built
  with `docker build .`). CLAUDE.md + tracker updated. All suites green
  after removal (server 262, salt_shared 121, app 2).
- **README** rewritten for v2 (quickstart, config, import, dev).
- **Forui upgrade pass**: 0.24.0 is still the latest published release;
  the exact pin is retained deliberately (pre-1.0, breaking changes can
  land in minor versions). No upgrade needed.

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
- 2026-07-16 — **`parseServings` split in two** (plan had one parser): a
  yield is not a serving count, but `MAKES ENOUGH FOR ONE 9-INCH PIE` was
  reading as `serves: 1`. `parseServings` now returns null for a bare yield
  and `parseYieldCount` reads the count separately; only `parseServings`
  reaches `Recipe.serves`. 173 of the 1,198 corpus recipes are yield-only,
  pinned by the corpus `servings coverage` gate.
- 2026-07-16 — **One-shot `serves` backfill on boot** (not in the plan; no
  migration hook exists — `PRAGMA user_version` migrations are SQL-only).
  `serves_backfill.dart` runs from `initServer()`, guarded by a `settings`
  marker, and skips any row whose hash shows a hand edit. **Ran against the
  live library on 2026-07-16: 173 of 1,198 recipes corrected**, YAML
  re-exported. This rewrote real user data, so it is recorded here rather
  than only in the code.
- 2026-07-16 — **Per-recipe nutrition compute is a background job**
  (`202 {job_id}` + poll), replacing the synchronous response: a cold
  compute takes ~20s, and the client would cancel on navigation while the
  server kept working — the user saw "couldn't reach server" on a compute
  that in fact succeeded. Single-flight per recipe. `computing_job_id` is
  sent only to admins: the poll endpoint is admin-only, so a member handed
  the id would 403 on every poll and see a false error.
- 2026-07-16 — **Serving basis falls back to the yield count** before 1
  (`servingBasis ?? stored ?? serves.min ?? parseYieldCount(...).min ?? 1`):
  post-split, a yield-only recipe has no `serves`, and dividing by 1 would
  report a 16-cookie batch as one serving. A yield still never populates
  `serves`; this is only a starting divisor, and the admin can override it.
- 2026-07-16 — **Admin lockout recovery** (user request): `salt_server:recover`
  prints a single-use 15-minute code, redeemed unauthenticated at `/recover`.
  Local access is the authorization, as with the first-boot setup code. The
  endpoint is rate-limited per IP and logs every failure (it is
  unauthenticated, grants admin, and a code check is only a SHA-256), and
  recovery revokes the account's API tokens as well as its sessions — a PAT
  would otherwise outlive the reset. The CLI is compiled into the Docker
  image as `/app/recover`; without that the feature was unusable in the
  deployment it was documented for.
- 2026-07-16 — **PDF export replaces the recipe page's YAML download** (user
  request); YAML moves to an admin-only View YAML dialog. All PDF prose sets
  `overflow: TextOverflow.span` — the only thing in the `pdf` package that
  can split across a page break — and the numbered step badge rides inline as
  a `WidgetSpan` because a `Row` can never span. Fractions the bundled fonts
  cannot draw (⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅐ ⅑ ⅒) are spelled out; an uncovered rune renders
  as a crossed-out box, and the package only warns behind an `assert`, so a
  release build would corrupt an amount silently.
- 2026-07-16 — **Grids reconcile favorites from a repository stream** rather
  than reloading on return: the tile heart became an indicator (user
  request), which removed the in-place unfavorite, and a favorites grid left
  alive under the detail page went stale. `setFavorite` is the only place a
  favorite changes, so it broadcasts; reloading instead would lose scroll and
  paging on a 1,198-recipe library.
- 2026-07-16 — **Tag input rebuilt on Forui's `FAutocomplete`**, approved
  mockup `docs/mockups/p9-tag-input.html`. Chips moved ABOVE the field: the
  approved P5 design had chips and cursor sharing one bordered box, and
  `FAutocomplete` renders its own bordered field, so the old shape would nest a
  border in a border. Forui's default filter is `startsWith`; overridden to
  substring to keep the old field's behaviour. Enter takes the matching tag
  rather than the raw text — the vocabulary is shared across 1,198 recipes, so
  `des` beside `dessert` is the failure worth designing against; creating a
  near-miss needs the explicit `Create "x"` row. `FMultiSelect` was rejected:
  it is a closed-set picker and tags must be creatable.
- 2026-07-16 — **Enter resolves against the WHOLE tag vocabulary, not the
  popover's filtered list.** The popover hides a tag the recipe already has
  (offering it is noise), and `_onSubmit` reused that same filtered list to
  decide what Enter meant — so once `dessert` was on the recipe it became
  invisible to the matcher, and typing `des` + Enter minted `des` beside it:
  the exact junk near-duplicate the widget exists to prevent, through its
  primary path. Display and resolution are now separate (`_suggestions` vs
  `_matches`). Resolving to a tag already present is a harmless no-op —
  `EditorCubit.addTag` ignores duplicates. Found by the review's completeness
  critic; none of the eight finder lenses covered it.
- 2026-07-16 — **The `Create "x"` row is built from what the user TYPED**, not
  from the live field text. Forui previews a highlighted row by writing its
  value into the field, and hands `contentBuilder` that live text as the query
  — so arrowing onto `dessert` to look at it made the query `dessert`, tripped
  the exact-match guard, and deleted `Create "des"` from under the keyboard.
  The escape hatch was mouse-only. `_typed` is recorded from the managed
  control's `onChange`, gated on the FIELD having focus, which is what
  separates a keystroke from a preview.

- 2026-07-16 — **A tag is committed only by an explicit act** (user's call).
  Enter, or pressing a popover row (including `Create "x"`). Blur commits
  nothing. The field previously added whatever was typed when focus left it,
  reasoning that clicking Save should not silently drop a half-typed tag — but
  that made blur the last surviving route to the junk near-duplicate the widget
  exists to prevent: Enter resolves `des` to `dessert` while blur took `des`
  literally, so the same keystrokes meant different things depending on how you
  left the field. Text left behind now stays visible in the field and unsaved,
  which trades an invisible write for a visible no-op.

- 2026-07-16 — **The tag input waits for its vocabulary via an async `filter`,
  and carries no sentinel.** Both come from reading forui's source rather than
  guessing at its contract, and both were live defects:
  (1) `FAutocomplete` re-runs `filter` ONLY when the field text changes
  (autocomplete.dart:1250 returns early otherwise), so a `setState` landing the
  tags could not refresh an open popover — type before the fetch lands and the
  popover offered `Create "des"` and nothing else, permanently. Returning a
  `Future` from `filter` hands the waiting to forui: `Content` parks a pending
  future behind a FutureBuilder and calls `contentBuilder` only once it
  resolves, so no row can be offered against a vocabulary we do not know yet.
  A `Create` row shown then is a lie — it claims no such tag exists when the
  truth is that the tags have not arrived.
  (2) An item's `value` is not a private channel: merely arrowing onto a row
  writes it into the visible field (autocomplete.dart:1531-1535). The
  `Create` row's `\x00create:` sentinel was therefore displayed verbatim and
  committed as a literal tag name on blur. The row now carries the plain typed
  text; adding it IS creating it, since the row only appears when nothing
  matches exactly.
- 2026-07-16 — **The PDF release-hang is fixed per-site, by rule. The
  `_boundedBlock` container ceiling was REVERTED** (it replaces an earlier
  entry here that recommended it — that recommendation was wrong). A height
  ceiling does not clip in the `pdf` package, it DROPS: `Flex` adds each
  child's height and `break`s once the total exceeds the constraint *without
  incrementing its index* (flex.dart:280-286), so the child is never painted
  while its height is still reserved. The 420pt ceiling silently deleted every
  tag chip from the header, and the byte-length test that "proved" it worked
  was measuring coordinate shift, not drawn content. Silently dropping a user's
  content is worse than the hang it fixed.
  The rule that replaced it, applied to all ~20 text sites rather than to
  whichever instance was reported: a text that is a DIRECT MultiPage child gets
  `overflow: TextOverflow.span` (only 9 pdf types can span at all; `Text extends
  RichText`, which spans only with that flag); a text NESTED in a Row/Wrap
  cannot span at any depth, so it gets a measured `maxLines`. Where the content
  is countable rather than textual, the overflow is STATED, not dropped — the
  header prints at most 12 tag chips plus a `+N more`.
  Verification is by counting `TJ` operators in an uncompressed content stream
  (one per word), which observes what was actually painted; byte length does
  not.
  **That rule is necessary but NOT sufficient, and on its own it made things
  worse** (found by the adversarial review of the fix; two independent lenses,
  no dissent across six refuters). A non-spanning CONTAINER's height is the SUM
  of its children's caps, and capping the children lowered the header's sum
  *into* the hang band (699.8pt, 720pt] instead of over it: input that threw a
  clean PdfException at `0d655dd` began hanging the tab instead. A sweep of 216
  header combinations measured 10 hangs and 73 throws. Enumerating the leaves
  cannot see this — each field alone saturates safely; only combinations reach
  the band.
  So the caps are now chosen to keep ONE invariant: **the saturated header must
  fit a page**, which makes the band unreachable rather than merely unlikely.
  Caps are set from measurement against both the corpus and the API's limits
  (title 10 lines — a legal 250-char title needs 9; category 3 — a legal
  120-char one needs 3; yield 14 — a legal 200-char one needs 12; chips one
  line each, text ellipsized at the API's own 60-char tag cap). The same sweep
  now measures 343/343 clean. The invariant lives in a test that sweeps
  combinations, because that is the only thing that can hold it.
- 2026-07-16 — **PDF steps hang-indent, via `Partitions`** (user-approved
  design, chosen from two rendered candidates). The number sits in its own
  column and the text hangs-indented beside it, spanning as many pages as it
  needs. It took three attempts, and the two failures are the lesson:
  1. **Row + `maxLines: 40`.** A Row cannot span (flex.dart:
     `canSpan => direction == Axis.vertical`), so it must fit one page. A LINE
     cap does bound height honestly — but `maxLines` truncates INVISIBLY (pdf's
     `TextOverflow` has no ellipsis member), silently eating ~44% of an
     API-legal 10,000-char step, which `0d655dd` had printed in full.
  2. **Row gated on `text.length > 3000`.** Strictly worse, and it shipped: a
     CHAR COUNT CANNOT BOUND A HEIGHT. Measured inside that gate, so routed to
     the Row: `'MMM ' * 700` (2,799 chars) and a **1,397-char checklist of 44
     short newline-separated lines** both landed in the (699.8pt, 720pt] band —
     reintroducing the exact release-build hang the work existed to prevent,
     reachable by typing an ordinary multi-line step into the editor's own
     multiline field. Found by the review's completeness critics; no finder lens
     covered it.
  3. **`Partitions` for everything.** It spans (`canSpan => children.any(...)`,
     partitions.dart:116), so nothing truncates — but a spanning widget is
     ALWAYS SPLIT and never moved whole (multi_page.dart:376-393), so a SHORT
     step at a page boundary had its badge placed on the old page and its text
     on the next. The number was orphaned. Caught by the user on a real export
     (Basic Double-Crust Pie Dough, step 3) — no test saw it.
  4. **Both, chosen per step.** MultiPage MOVES a non-spanning widget whole to
     the next page when it does not fit (multi_page.dart:379), which is exactly
     what a numbered step wants. So a step takes the non-spanning Row when it
     PROVABLY fits a page, and Partitions only when it cannot. The gate is
     `stepLineBound` — a real bound, not a guess: within a hard-break-free run,
     greedy wrapping leaves every line at least half full unless a word is wider
     than half the column, so the run needs at most `2 * totalWidth /
     columnWidth` lines; a too-wide word returns null and takes the safe branch.
     Measured over all 5,881 corpus steps: the worst bounds at under 35 lines
     against a 43-line page, so no real step ever spans, and the adversarial
     shapes (44 hard breaks, wide glyphs, 10,000 chars) all route to spanning.
  The generalisable rule, learned twice in one day: **bound a height with a
  height (or with a line count), never with a character count** — and the same
  error is why the header's `_maxTitleLines`/`_maxCategoryLines`/`_maxChipChars`
  comments are wrong about what they guarantee (open, see the deferred list).

- 2026-07-16 — **Process**: the user made auto-review a standing order after
  three prompts in one day. Reviews now run at every finish point, before
  deploying for them to test. Evidence for why: a batch of four "small" UI
  items shipped with two HIGH defects (a transition that never ran; a PDF
  release-hang), and the fixes for those findings — committed in `0d655dd`
  without their own review — themselves carried 12 defects. Fixing a review's
  findings does not review the fixes.
