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

## P4 — Search + tags — **pending**
FTS5 + DSL→FTS compiler, search UI, tag styles (Lucide) + editor.
Requirement from P0 review: `calories:` queries default to calories-ascending
result ordering (old-app contract). Search semantics decided by user
(2026-07-14): scope binds one term (quoted phrases for multi-word); adjacent
terms always AND (explicit `or` for unions) — modern convention, deviates
from old app; document in search help UI.

## P5 — Editing + export + reconciliation + backups — **pending**
CRUD, atomic auto-export, library reconciliation scan (file wins clean edit /
DB wins conflict + `.conflict` file), image upload + SSRF-guarded URL download,
rolling backups, legacy v0 importer, editor UI (mockup first), favorites/notes.

## P6 — Nutrition (USDA FDC) — **pending**
Provider + caches + matcher + gram resolver + aggregation, match overrides,
rate-limited bulk job, FDA label + review sheet (mockup first), `calories:` live.
Needs per-deployment api.data.gov key from user at phase start.

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
