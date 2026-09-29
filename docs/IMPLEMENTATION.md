# Implementation Tracker

Living status of the approved rewrite plan (kept locally, not in the
repo). Statuses: `pending` / `in-progress` / `done` / `changed(reason)`.

Last updated: 2026-07-26

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

**Both call sites are now pinned** (`#44`): the chain build moved to
`lib/src/app_pipeline.dart` as `buildAppMiddleware(handler, {config, database,
authRuntime, nutritionProvider})`, and `_initAuthRuntime` became the public
`initAuthRuntime({config, database, warn, announceSetupCode})` — both take their
collaborators as parameters instead of reading process globals, so a test drives
the real code. `middleware_test.dart` now assembles the production chain over a
socket (a reorder putting `securityHeaders` inside `spaFallback` turns the
deep-link CSP test red), and `trusted_proxy_test.dart` drives `initAuthRuntime`
with a captured sink (deleting the `configWarnings(...).forEach(warn)` wiring
turns the boot-warning test red). Both mutation-checked. `routes/_middleware.dart`
is now a thin delegator holding only the fixed dart_frog entry point. The
rate-limit key collision is closed with the XFF peer check.

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

**Second pass, 2026-07-17 — the review tool fixed, then re-run.** Once the
preflight gate closed the worktree bug (`#46`), the workflow ran clean and
reached the questions the void run had not:

- **FIXED — MED: a member can stall the whole server with a handful of
  ~500-byte search queries.** `GET /recipes?q=` ranks with FTS5 `bm25`, which is
  superlinear in OR'd terms, run synchronously in the one serving isolate.
  Measured on the corpus (and reproduced independently): 20 terms → 19 ms, 80 →
  210 ms, 320 → 2.7 s — doubling terms ~quadruples time; dropping the `bm25`
  ORDER BY takes an 80-term query from 210 ms to 0.5 ms, so ranking is the whole
  lever. Uncapped, 3 looping connections drove `/healthz` from 4 ms to ~480 ms
  (effective denial). Fixed by a `maxSearchTerms = 24` cap in the shared DSL
  parser (`dsl_parser.dart`), enforced as a parse error → 422. Verified on a
  live server: the 73-term attack now 422s in 7 ms; a real query is untouched;
  the worst capped query is ~30 ms and 3 connections hold `/healthz` at ~89 ms
  (degraded, not denied). Mutation-checked.
- **Critic swept four more modes, all bounded** — sync image reads are
  admin-gated to write, the recipe list caps `limit` at 100, the login username
  regex is anchored, and the parser did not blow the stack on adversarial input.
  Zero new findings.

**Residual — search rate limit added (`#47`), root cause still open.** The cap
killed the *quadratic*; a member sending capped ~30 ms queries on many
connections still added latency for everyone (linear, not quadratic). A per-user
request-RATE limiter (`RequestRateLimiter` in `rate_limiter.dart` — sliding
window, distinct from the login lockout limiter) now gates `GET /recipes?q=`:
`SEARCH_RATE_LIMIT` searches/min per user (default 60; `0` disables), returning
`429 rate_limited` with a `Retry-After` past that. Keyed on the authenticated
user id (search is auth-only), so it bounds any single caller's isolate share;
plain listing (no `q`) is never limited. Wired via a `provider<RequestRateLimiter>`
through the `#44` `buildAppMiddleware`. Unit- and integration-tested over a real
socket, both mutation-checked (limiter off-by-one; handler gate removed). This
caps the single-abuser case but does NOT remove the single-isolate limit — many
distinct users, or the true cure of moving the DB off the serving isolate,
remain out of scope.

**The two untested vectors are now driven and both benign (`#48`, first half).**
`availability_vectors_test.dart` drives real half-open sockets and the real
drain against the production chain — the thing #42's critic could only reason
about:

- **Slowloris — REFUTED as an event-loop DoS.** 300 half-open connections
  (partial headers, never terminated) held open → `/healthz` still answered in
  ~7 ms (vs a ~40 ms cold baseline). `connectionsInfo` counts them **`idle`, not
  `active`**: the async single-isolate server parks half-open sockets cheaply, so
  they never touch the serving isolate. The only residual is FD/connection
  accumulation, which (a) is fronted by the deployment's TLS reverse proxy and
  (b) is now bounded at the origin too: `CONNECTION_IDLE_TIMEOUT_SECONDS`
  (default 75, below Dart's 120 s; `0` disables) sets `HttpServer.idleTimeout`,
  and it was **measured** to reap a socket stalled mid-headers. Test asserts the
  idle-not-active structural property + the reap.
- **SIGTERM-drain — CONFIRMED, and made testable.** The drain loop was extracted
  from `main.dart` into `drainConnections` (`lib/src/shutdown.dart`, the `#44`
  pattern) so a test drives the real code. Verified: an in-flight request
  **completes** (status 200, real body) rather than being killed, the drain
  **blocks** until it finishes (a no-op drain that returns instantly is
  mutation-checked red), an idle/half-open socket does **not** extend the drain
  (reaped by the initial `close()`), and a request outlasting the bound is
  **force-closed** near the bound, not after the full handler (also
  mutation-checked). New config parse unit-tested.

**The single-isolate DB root cure — a SURGICAL search isolate (`#48`, second
half).** The residual after `#47` was that every synchronous `sqlite3` FFI call
runs on the one serving isolate, so a ranked `bm25` search blocks the event loop
while it runs. The cure moves *only the FTS ranked search* — the measured lever,
the only attacker-reachable heavy query — onto dedicated background isolate(s),
each owning its own read-only WAL connection. Everything else (admin-only writes,
imports which already run in `Isolate.run`, cheap by-id reads) stays synchronous.

- **Shape.** A `SearchService` interface (`lib/src/search/search_service.dart`)
  with two impls: `InlineSearchService` (synchronous, the pre-#48 behavior, kept
  for tests and `SEARCH_WORKER_ISOLATES=0`) and `IsolateSearchService` (a pool of
  workers, round-robined). Each worker opens `SaltDatabase.openReadOnly` (a WAL
  reader, `PRAGMA query_only`) and runs the unchanged `searchCards`. `RecipeCard`
  and `CompiledSearch` cross the isolate boundary by copy (verified). The handler
  (`listRecipes`/`_resolve`) went async and takes the service; parse+compile stay
  on the serving isolate (cheap, capped by `#47`). Wired through a
  `provider<SearchService>` and `buildAppMiddleware`, sized by
  `SEARCH_WORKER_ISOLATES` (default 1). Workers spawn AFTER the writer migrates
  and are disposed BEFORE it closes (readers before the checkpoint).
- **Correctness.** `search_service_test.dart` proves the off-isolate path is
  behavior-preserving on the whole real corpus — same rows, order, totals, and
  favorite flags as inline across text/scoped/OR/AND/calorie/paged/no-hit
  queries — including favorites written on the writer and read through a worker's
  separate WAL connection. Plus: concurrent-burst parity, SQLite-error
  propagation (not a hang), and a disposed-service guard. The parity suite is
  mutation-checked (a worker that drops `favoritesOnly` reddens it). A crashed
  worker respawns lazily (`onExit`); a stuck one is bounded by a per-request
  timeout. Real-process smoke: boots "Search running on N background isolate(s)",
  serves, and drains+disposes cleanly on SIGTERM.
- **The high-effort review found the cure was INERT in production, now fixed
  (`#48` review, 2 survivors of 7).** The 6-lens evidence-gated panel caught a
  **HIGH** the smoke test missed: the dart_frog entrypoint builds the handler
  chain (reading the `searchService` getter → the `InlineSearchService` fallback,
  since `_searchService` is still null) BEFORE the custom `run()` calls
  `initSearchService()`, and `buildAppMiddleware` captured that value — so every
  request ran search *inline on the serving isolate*, the pool spawned-but-unused,
  while the reassuring log line still fired. The smoke test booted and drained but
  never issued a `?q=` search, so it proved nothing about the request path. Fix:
  the `SearchService` provider now takes a *thunk* (`() => searchService`) and
  resolves it **per request**, so the post-build swap is honoured (reproduced
  before + after; mutation-checked end-to-end HTTP test in
  `search_isolate_wiring_test.dart`). The panel also confirmed a **MED** isolate
  leak — `ensureSpawned` had no in-flight guard, so two concurrent requests after
  a worker death double-spawned and orphaned a reader (now shares one respawn) —
  and a completeness-critic **MED**: a wedged (not crashed) worker was never
  evicted, poisoning the single default worker (a timed-out request now evicts +
  respawns it). Both resilience paths, previously untested (the review's LOW), are
  now mutation-checked. 4 findings were killed by the refutation panel.
- **Why surgical, not the full cure — the reasons, recorded.** The mainstream
  best practice ("don't run a synchronous DB on the serving isolate") is honored
  where it is *measured to matter*, which is the correct scope, not a compromise.
  The alternatives were weighed and rejected:
  - *Full async DB isolate* (all ~60 methods async through one DB isolate):
    complete but a rewrite of the entire data path with high risk, and — to be
    real best practice — it would mean adopting a library (`drift`/`sqlite_async`)
    over the deliberately hand-written raw-SQL layer, discarding an architecture
    decision in `CLAUDE.md`. Poor ROI: writes are admin-only and imports already
    run off-isolate, so there is no measured problem there.
  - *Multi-isolate serving* (N serving isolates, `shared` socket): spreads CPU
    but each isolate gets its own copy of the in-memory guards — the login-lockout
    and search rate limiters, session/setup state — so a per-user limit enforced
    per-isolate becomes N× looser and login lockout is bypassable by hitting
    different isolates. A security regression; rejected.
  - *Accept the residual*: defensible (acute risk capped, search auth-only, small
    admin-created user base), but the user chose the surgical cure.

**The token-row residual is closed (`#45`).** The active cap bounds *usable*
tokens, but a mint+revoke loop still grew the table with permanent revoked rows.
The user chose a retention window: daily housekeeping (and every boot) now
deletes revoked rows older than `API_TOKEN_RETENTION_DAYS` (default 90; `0`
keeps them forever) via `deleteRevokedApiTokensBefore`. That bounds the table —
and with it the unpaginated `GET /tokens` list, whose size is now
active (≤ 20) + revoked-within-window — so no separate pagination change was
needed. DB prune + config parse are unit-tested, the comparison mutation-checked.

**The P3 `middleware()`-order residual is closed** (`#44`): the chain moved to a
parameterised `buildAppMiddleware` in `lib/`, the test now drives the real
production chain over a socket, and the reorder that strips the shell's CSP is
mutation-checked red. Same refactor made the boot-warning call site testable.

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

## Admin pages (post-P8 backlog) — **done** (2026-07-17)

Two admin-only pages beyond parity, both mockup-first:

- **Recipe review** (profile-dropdown, admin only): a recipe DATA-QUALITY
  report — NOT a security audit; the backlog's "audit" name was a misnomer.
  Six checks in an extensible registry (no instructions; unparsed ingredients =
  a quantity+unit line with no parsed amount; incomplete nutrition; no nutrition
  data (separate category); extraction warnings; no servings) run over the whole
  library. The server owns the check ids + labels + descriptions and ships them
  in the DTO, so the app documents itself. `GET /api/v1/admin/recipe_review`;
  422 on an unknown issue filter; whole-library counts, paginated item list.
- **Logs viewer** (Settings → Server → Logs, admin only): a persistent,
  file-backed store — one JSON line per record under `<dataDir>/logs/`, rotating
  to a single `.1` at `LOG_MAX_BYTES` (default 4 MiB). Chosen over the initial
  in-memory ring buffer (the user wanted comprehensive logs from a real store)
  and over a DB table (avoids mid-transaction write contention); it's the same
  stream stdout gets, persisted where the endpoint can read it. Secrets redacted
  on ingest (defence-in-depth — the setup + recovery codes go straight to
  stdout, never through the logger). `GET /api/v1/admin/logs` (+ `/export` text
  download). The request logger now skips `/healthz` + the viewer's own poll
  (self-referential flood) and stamps the proxy-aware client IP on the http line.

### Admin-pages code review record (2026-07-17)

Evidence-gated review (base `5cde892`, 4 lenses + 3 critics): the correctness,
security and test-quality lenses found nothing; the two availability findings
(one issue) and three critic gaps all traced to the #48 anti-pattern — heavy
synchronous work on the single serving isolate — plus two robustness holes. All
admin-only / post-auth. Fixed in `fc49517` + `596f7a3`:

| area | issue | fix (measured) |
|---|---|---|
| Logs poll | `query()` re-parsed both full files every 3s Live poll | tail bound (512 KiB): **86ms → 11ms** |
| Logs filter | a full-history search would reintroduce the block | off-isolate `queryFull` (`Isolate.run`): **86ms → 0.1ms** main-isolate; client sends `scan=full` only when a filter is active |
| Recipe review | whole-library decode re-run per page/filter | memoized behind a DB fingerprint (recipe+nutrition counts, `max(updated_at)`) |
| Log write | `add()` synced per record + no failure guard | dir created once; write wrapped (best-effort — never throws into the root zone) |
| Cubit | `filter()` left the new chip over the old items on error | reverts to the pre-filter state |

**Deferred:** the `/export` download still does a full *synchronous* read (a rare
one-off; off-isolating it cleanly needs format-in-isolate or a large copy-back).
See `.claude/DEFERRED.md`.

## Post-P8 continued (2026-07-18 → 2026-07-26)

Work past the parity cutover and the two admin pages, in five threads. All on
`feat/dart-rewrite`; each finish point reviewed (standing order — see the
Decision log), then deployed for the user to test.

### Editor: subsections & techniques (2026-07-18)

- **Variations & components** editable in the structured editor (`4f0a1a5`,
  mockup-first): prose-only variations with promote-to-full affordances, and
  full components with their own nested ingredient/step editors. Forui kind
  select; bordered-block corner rendering fixed (`1867e41`).
- **Techniques** — illustrated asides with captioned, photographed steps
  (`07f644d`): per-step photo upload / from-URL, source-rooted image URLs,
  rendered in the detail view (`6770e8e`). Review + a11y follow-ups (`580da04`,
  `54ff2ad`, `2402c36`, `d05adc4`, `edcde3c`).

### Nutrition matching quality (2026-07-23 → 2026-07-26)

The P6 matcher/grams matured against live FDC + the 1,198-recipe corpus, driven
by adversarial probing. Ranker (`matcher.dart`):

- FNDDS layer added via POST search + transient-error retry (`0885488`); query
  cleaned, all-words required, base-form changes penalized (`5581d87`).
- A ladder of query-gated, individually-measured penalties: reconstitutable
  concentrates — broth cubes / bouillon (`97b8e62`); meat analogs + prepared
  dishes (`c820cca`); added meat qualifiers turkey/deli (`8673605`); and the
  breakfast-sausage fix — split the meat-qualifier dock out to −0.12 so the
  wrong MEAT beats a raw/cooked tiebreak, plus "biscuit" as a dish marker
  (`c1ad124`).
- Low-confidence (<0.5) auto matches held OUT of the label totals until a human
  confirms (`5bf4fee`).

Grams (`grams.dart`):

- Weight printed in a raw parenthetical is used (`c0ba59e`); counted whole items
  resolve from FDC portions + a curated piece table (`d614c2e`).
- Rustic/country/crusty bread piece fallback (≈50 g/slice, 454 g/loaf), and
  fixed a TRAILING parenthetical total being over-scaled by the count — "5
  slices bread (9 ounces)" read as 5× (`858c30f`).
- Ground-spice / dried-herb densities, back-derived from FDC's own 1-tsp gram
  weight so a volume estimate reproduces FDC (`f504427`).

### Nutrition-match review queue (2026-07-24 → 2026-07-26)

A cross-recipe, line-level admin review, distinct from the recipe-level report:
a "Nutrition matches" tab on the Recipe Review page (master-detail, worst-first)
listing every flagged ingredient match across the library in one queue. Buckets
`no_match` / `no_grams` / `check` (<0.5 name conf) / `skipped`; a
confirmed/overridden line counts as resolved (keeps confirmed water out of the
queue). Server `GET /api/v1/admin/nutrition_review` (`d7192f9`); Flutter tab
reusing a fix panel extracted from the review sheet (`75a08bb`). Alongside it:
the per-recipe label got a collapsible facts panel (`4d49c14`) and the match-fix
modal was rebuilt with manual USDA search + verifiable amounts (`e6b25be`).

### UI / brand polish pass (2026-07-18 → 2026-07-22)

A broad Forui/brand sweep, mostly cosmetic: all action buttons → `FButton`, icon
affordances → `FButton.icon` xs (`9ebcfb1`, `e95359d`); vector brand-logo widgets
replacing raster PNGs (`b3dd14e`); sign-in / recover redesigned with the maroon
brand band (`27c9225`); a shared `SaltBadge` status pill + dismissible filter
chips (`64e18ff`, `afb4ead`); scoped search clauses rendered as dismissible chips
(`830547a`); recipe-list row layout + clearable filters (`fa0ee6d`). App routing
decisions (`48099cc`, `7a46b47`): pushes reflect the URL, the in-app web Back
button is dropped for the browser's, the splash gates above the router, and
editor-exit is guarded on browser Back.

### Editor drag-and-drop fixes (2026-07-26)

The editor's reorderable lists had a run of drag visual bugs, each fixed in turn
(`e56a0ce` → `08151ae`; see the Decision log for the scope trap and the
flicker): a grey `ErrorWidget` from the drag overlay rebuilding an item outside
its `InheritedWidget` scope; border-overflow from Flutter's default grey lift; a
white margin strip painted under lifted cards; and a one-frame flip back to the
pre-drag order on drop. Final state: ingredient rows lift opaque-white; bordered
cards (steps, variations, components) lift opaque-white **inset off their bottom
margin**; every scoped list re-provides its scope inside the `proxyDecorator`;
and an optimistic local list reorders synchronously so the drop frame already
shows the new order.

### Nutrition: decisions get a home, keys go singular (2026-09-02 → 2026-09-07)

A run of nutrition work, each commit dual-fleet reviewed (RUNLOG Runs 032–036):

- **Bulk scopes** (`7f6afc2`, `bbd4710`): `POST /nutrition/bulk` takes
  `missing` (default) / `stale` / `all`; `GET /nutrition/bulk/counts`. Staleness
  is DERIVED by hashing every computed recipe (~110–190 ms for 1,198) — the
  stored `status` column never holds `stale` and timestamps cannot be trusted
  (see the staleness-traps note in the decision log).
- **Cross-recipe reuse, R1** (`88101b1`, `753662d`, `7219e67`, `7cf9be9`):
  migration 009 adds `ingredient_matches.item_key` (backfilled at boot under
  the `backfill.item_key` marker); a new line inherits a decided sibling's food
  as `auto` at confidence 1 (an engine write, so a later decision on the line
  wins); `apply_to_all` on the match PUT lands a decision on every other
  undecided line of the item and answers `applied {recipes, lines, failed}`;
  the app offers it after a decision (approved mockup `r1-apply-to-all.html`).
- **Matcher** (`1e95f39`, `2f31130`): pepper is a spice and brand liqueurs are
  liqueur (a query-rewrite table keyed by normalized items — every key is
  pinned reachable); an amount-less salt/pepper line is confirmed as zero
  ("Seasoning to taste"); a weak match with no amount is `check`, not
  `no_grams`; the sheet explains a zeroed line.
- **Search-cache visibility** (`c8519df`, `6bd06d3`, `9646dbc`): every matches
  line carries `candidates_query` and `candidates_cached_at`; the admin search
  answers `query`/`cached`/`cached_at`; `fresh=true` bypasses and replaces the
  cache row — but a live answer with NO hits never evicts a stored one that had
  some (an empty row is a cache hit and the cache never expires).
- **Survey 2026-09-04** (9 read-only agents over the corpus + a DB copy): the
  library has never been swept (8 of 1,198 computed), decisions were keyed by
  position and lost on edit (reproduced), and a class of confident wrong-mass
  rows never reaches review (scallions as onions, frying oil, bone-in gross
  weights). Full backlog in memory; the user chose the order.
- **Design review D3 (2026-09-07)**: an "ingredient dictionary" proposal was
  attacked by 7 lenses and REJECTED for a smaller design — the one built here:
  - **Migration 010 `ingredient_decisions`**: a human food decision (a pick, or
    a confirm of a food — never a grams-only edit, never a skip) gets a row of
    its own keyed by the ingredient, written at the match PUT and consulted
    first by the compute. It outlives the recipe and the line it was made on
    (before, every other line BORROWED it from that row). Human-only, not
    seeded (test data only at the time); `item` keeps the parsed text so a
    matcher change re-keys the row at boot (`services/decision_rekey.dart`,
    marker `decisions.matcher_version`).
  - **Decisions follow their lines**: `matchAndCompute` re-attaches a decided
    row to the position whose line carries its text (a per-text LIST — 80
    corpus recipes repeat a line — nth line keeps the nth row); an amount edit
    on a decided line keeps the food and status and re-derives the grams (a
    hand-typed weight for the old amount is dropped); a skip stays a skip.
  - **`matcherVersion`** (`matcher.dart`) is part of `ingredientsHashOf`, so a
    bump makes every computed recipe `stale` and the stale sweep re-resolves
    engine rows (decisions kept). A bump spends FDC only on keys whose
    rewritten query text changed — pinned: a fully cached recompute makes 0
    provider calls. The CI-visible hash literal must be updated with each bump.
  - **Keys are singular, the query is not**: `itemKeyFor` (decision/reuse
    key: "onion"/"onions" are one ingredient — 66 pairs, 2,036 corpus lines)
    vs `normalizeItem` (the FDC query, the line's own words — so no cached
    answer is invalidated and ranking is unchanged). Accents fold
    (jalapeño → jalapeno, 65 lines); canned "crushed/diced tomatoes" keep their
    form word (51 canned lines had merged with 9 fresh under "tomatoes"). The
    item-key backfill re-runs whenever its marker is not the current version.
  - Measured on the corpus before building: 1,840 query forms → 1,778 keys;
    62 keys merge >1 form, all genuine plural pairs, 0 false merges.

### Ranker: the head noun, composites and brands (2026-09-08)

Driven by a DIAGNOSTIC SWEEP rather than the full library: 69 corpus recipes
chosen by greedy cover over the survey's 18 categories (≥8 each) plus 30 random
controls, computed against live FDC in 8.5 min (~600 requests). Every category
behaved as the survey predicted; the random control found two classes nobody
had listed — a modifier word outranking the ingredient ('dry sherry' →
"Lentils, dry" 0.53 COUNTED; 'ground cumin' → "Flaxseed, ground") and
prepared-dish/branded records outranking the raw food ('whole chicken' →
"School Lunch, chicken nuggets" 0.88 COUNTED; 'ice cream' → "Ice cream
sandwich"; 'bacon' → "Bacon bits"). Both produce confident WRONG foods that the
review queue never shows. The run, its caches and every artefact below live in
`.claude/diag/2026-09-08/` (gitignored; the API key removed).

Design review D4 (RUNLOG) attacked a written proposal with seven lenses that
could each implement a rule and recompute the 878 cached lines for free (a
provider that throws on any network call proves the recompute spent nothing).
Verdict: adopt with changes — R2 (a description-category dock) and IDF
weighting were rejected on measurement; the judge's own ablation grid showed
only the COMBINATION passes.

Shipped (`matcherVersion` 3):
- **Head-noun dock −0.30** (`headNounOf`): the word that names the food —
  after cutting a trailing " for …" clause and an "or … recipe …"
  cross-reference (never a plain "or"), dropping form/prep/stop words and
  count nouns in BOTH numbers, stepping back over identity tails (anchovy
  paste → anchovy), stemmed with the key stemmer on both sides (an -ies head
  also matches its -ie spelling), stepping back over a modified form to the
  food it modifies ('egg yolk' → egg; a lone 'yolks' names nothing) and with
  chile → pepper. A negated head ("Chili hot dog, no bun", "… no sugar
  added") is not carried. Docked uniformly even when no candidate carries it: that is
  what un-counts the lentils. Never excludes a candidate.
- **Composite dock −0.40** (was −0.25 for dishes/analogs): the nine marker
  families measured to change a chosen food, both numbers (sandwich, cake,
  roll, bun, nugget, mock, dressing, topping, candy) + 'school lunch' / 'with
  meat'; 'sandwich' never docks a cookie (FDC files Oreos as "Cookie, …
  sandwich" — recorded). Not 'bits' (Canadian bacon), not pie/cookie (the
  graham-cracker crust pin).
- **Brand dock −0.40** (a wrong food's worth; at −0.25 a McFlurry still
  counted for 'oreo cookies'): a token with three capitals in a row that the
  query does not name ('McFLURRY', "McDONALD'S" — a lowercase "Mc" defeated
  the all-caps rule), never "USDA's" programme note or NFS/NS. Safe only WITH
  the head-noun dock (alone it handed SWANSON's beef broth to a mushroom soup).
- **Rewrites** (all targets recorded from live FDC): ground cumin/coriander/
  fennel → their seeds, cinnamon (+stick) → ground cinnamon, whole cloves →
  ground cloves, frozen phyllo → phyllo, bay leaves → bay leaf, parsley leaves
  → parsley, vegetable oil for frying → vegetable oil, bacon → pork cured bacon
  unprepared, shrimp family → shrimp raw, (dry) sherry → wine dessert dry,
  (mild) lager → beer, dijon mustard → mustard prepared, 17 pasta shapes →
  pasta dry enriched. Curry paste has no FDC record and stays unmatched.
- **Normalizer**: "juice from 1 lemon" / "zest from 2 limes" → "lemon juice" /
  "lime zest" (the fruit leads, the count goes; 120 corpus lines).
- **`candidates_name_ingredient`** on every matches line: false when the
  answer holds no record naming the food (37 of 878 diagnostic lines); the fix
  panel then says "Nothing in the search names this ingredient — search by
  hand below" instead of offering the top junk record.

Measured on the diagnostic set (cache-only recompute, 0 provider calls): 70
lines changed; 26 of the 31 confidently wrong foods fixed or out of `counted`
(21 now on the right food and counting); 0 correct lines regressed; counted
601 → 622, check 136 → 118. The 5 that remain wrong (white sandwich bread,
frozen peas, clam juice, rice vermicelli, cremini, celery root) are variety
or normalizer items for a later round, as is the count-noun coverage cap
(right foods parked at 0.44–0.55 — the next design round, as a head-noun
WEIGHT). The recorded answers became test fixtures (46 queries, 52 foods).

Review fixes (Run 038 in the evidence repo's RUNLOG, both fleets on
`8ac8936`, same day): the head noun keeps a cut's own 'ribs' ('rib' is a
count noun only after 'celery' — 72 corpus lines count celery by the rib, 25
name a cut), skips a preposition and its object ('ham with skin'; 'thai with
salt preserved radish', which is how the normalizer spells "salted"), drops
measurement units left by "or ¼ teaspoon dried" and FDC's own form words on
the rewrite targets ('shrimp raw' → shrimp, 'wine dessert dry' → wine, 'pasta
dry enriched' → pasta, 'cumin seeds' → cumin) — so every rewrite target has an
identifying head instead of a null or a form word. A marker the query itself
names in any number ('buns' names bun, and bun ⇄ roll because FDC files buns
under "Roll, …") is the food, so FDC's own hamburger-bun records count again.
`candidates_name_ingredient` judges the WHOLE cached answer, not the eight the
sheet shows ("Peppers, hot chile, sun-dried" is 11th of 16 for 'thai chiles').
The fix panel now says a weak match is "held out of the totals until you
confirm it" — it was telling the admin the line "is counting now" while the
engine held it out. Pinned by name: an explicit rewrite table (a deleted entry
fails), the brand rules, the recorded bun answer, the 'with meat' phrase, the
negated head, and a corpus recipe's Thai-chile line read through the matches
body over the seeded answer; 14 mutants bite. Re-measured on the diagnostic
set: bucket counts unchanged (622 / 118 / 80 / 4 / 54), two weak check-bucket
lines re-ordered among wrong foods, 0 regressions. Deferred: 'fresh
fettuccine' counted at dry-pasta density (LOW), the normalizer's "trimmed to
bottom 6 inches" tail.

### Nutrition queue: grouped by ingredient (Batch B, 2026-09-09)

The admin queue's unit of work in the food buckets is now the INGREDIENT: a
wrong food is fixed once, library-wide, so 202 flagged lines on the
diagnostic copy read as 131 rows, 102 of them a single line drawn exactly as
before. Mockup-first: `docs/mockups/b1-grouped-queue.html` (a four-angle
design panel, three comparative judges, one synthesis, then a correct→verify
loop against the recomputed diagnostic copy — the judges had mistaken the
pre-fix sweep for the live data) was approved with all six recommendations.

- **`GET /api/v1/admin/nutrition_review?group=item`** — a mode on the existing
  endpoint (any other value is a 422). A group item is the LINE item flattened
  (recipe/position/raw/bucket/match = the group's example line, so the app's
  `slug#position` key, `select()`, the fix pane and `queueShouldAdvance` are
  unchanged) plus `item_key`, `item` (the example line's parsed ingredient,
  decoded per recipe and memoised within the request — the label the app
  prints through `itemLabel`, falling back to the key), `lines`, `recipes`,
  `decided` (an `ingredient_decisions` row exists) and `grams:{min,max,
  missing}`. One constant SQL text (`_reviewFlaggedCte` + a window function
  for the example: lowest confidence, then a member WITH grams, then title,
  then position); a NULL/'' key is a group of one keyed by its own row;
  group bucket = worst member; sort MIN(confidence), lines DESC, recipes DESC,
  key; paging counts groups. `groups` is reported at the top level and per
  bucket in BOTH modes; `total`/`count` stay line counts so the chips never
  change unit. The line view gained an `item_key` tie-break so an
  ingredient's lines sit together.
- **`others` is food-agnostic** (the one change the grouped queue could not
  ship without): undecided siblings already on this line's food as a
  low-confidence GUESS count, and `apply_to_all` rewrites them as `auto` at
  confidence 1 — which is what lifts a same-food group out of `check` after a
  Confirm as-is. A sibling already on the food at confidence 1 carries the
  decision (propagated or inherited) and is neither counted nor rewritten —
  without that exclusion every later confirm re-offered the rows the last
  apply had just written. `others_lines` joins `others` (recipes).
- **App**: `NutritionReviewCubit` keeps a per-bucket grouped flag for the
  session (default `bucket != 'no_grams' && bucket != 'skipped'`; Skipped
  never groups and hides the segment); the header reads "N ingredients, M
  lines" in grouped view; `hasMore` compares against groups there. The group
  row = today's row with the meta slot swapped for the label + a maroon-
  tinted reach pill ("5 lines · 5 recipes"), an "e.g." prefix on the raw
  line, a `decided` badge, and an amount slot ("amounts 14–63 g, one per
  line" / "no amount on any of the 6 lines — Confirm as-is is unavailable" /
  "264 g on both lines" / "… · 3 of 5 lines have no amount"). The strip
  says "N other lines of <item>, in M recipes, are still waiting on this
  decision" + "Apply to N lines" when the decision KEPT the line's food
  (a confirm, or re-picking the same food — judged app-side from the row
  before the PUT), today's wording when it changed.
- Contract goldens: `nutrition_review_grouped` added; `nutrition_review`
  and both matches goldens regenerated. Deliberately not built (user
  decisions): no group-scoped Skip, no inline member list (the Lines toggle
  is the member view), chips never count ingredients.

Review fixes (Run 039, both fleets on `c7d811e`): the reach stops at the
flagged threshold — a same-food sibling counts (and is rewritten) only while
it is a guess below `lowConfidence`; a counted 0.92 line is not "waiting" on
anything, and at corpus scale the old rule would have rewritten 302 flour
lines inside one PUT. A decided row (overridden without an amount, skipped)
is a group of one, never part of an ingredient's reach, so the pill is exact
in the food buckets. The strip has ONE sentence ("N other lines of X, in M
recipes, are still waiting on this decision") — the old "with a different
match" became false once the count was food-agnostic — and `keptFood` is
gone. A failed toggle restores the per-bucket memory and leaves the paging
cursor alone; the "Confirm as-is is unavailable" warning follows the EXAMPLE
line's grams, which is what gates the button. Five pins were missing (the
example rule's confidence/title/position clauses, the key tie-break in the
ORDER BY, the stale-line guard on `item`, grouped paging, the Skipped
guard); eleven mutants now die. The title tie-break is pinned on the corpus's
two "Chicken Francese" recipes, which share a title and differ only in
position.

### Library sweep, checkpoint audits and the efficiency batch (2026-09-26)

The first library-wide `missing` sweep ran on a scratch copy of the data
against live FDC (1,190 recipes, job 13, ~3 windows of the 900/hour
budget). Per the user's standing instruction the hourly budget pauses became
checkpoints: a key-stripped snapshot, a quick report, then an Opus 5.5 audit
workflow (accuracy of the food, accuracy of the mass, efficiency, the
normalizer and keys, a synthesizer ranking adjustments by impact × cost).

Checkpoint 1 (250 recipes, 2,969 lines): 76.7% of lines counted; 3.7 FDC
requests per recipe with ~27% of the window spent on the `requireAllWords`
fallback pass and ~20% of searches on junk queries (quantities leaked into
keys, equipment, "A or B"); 93 counted lines carried a wrong food (11 whole
turkeys as "Bologna, turkey", +48,058 kcal; beef broth as condensed soup in
14 recipes; romaine as the organ "Heart"); 42 bone-in/whole-bird lines at
gross weight; 20 brine-salt and 3 frying-oil lines counted in full;
scallions at 110 g; 106 check lines held the right food (the count-noun
cap). Checkpoint 2 (585 recipes): 2.7 requests per recipe, fallback share
34% (the "or" and digit-leak shapes doubled), and a class bigger than any
in checkpoint 1 — two Foundation records publish no energy (extra-virgin
olive oil keeps its fat only under NLEA nutrient 298; whole-grain spaghetti
has no macros) so 144 counted lines added 0 kcal (~53,600 kcal missing);
frying oil was undercounted by the "for frying" rule (19 counted oil lines
≥ 400 g, 26.6 kg).

The efficiency batch (cache-safe, built from checkpoint 1's plan):
- **FDC request counters** on the provider (strict search, loose/fallback
  search, food fetch, food 404, retry), logged at each rate-limit wait and
  at the end of a bulk job — the accounting the audits had to infer.
- **Quantity leaks out of the keys** (`normalizeItem`): a leading "N [N]
  unit" left by the `plus` stopword, a mid-item "N unit", " or N unit";
  "N percent" kept. `matcherVersion` 4 (the boot re-key covers every row).
- **Equipment is a confirmed zero, never searched**: cheesecloth, skewers,
  twine, parchment, toothpicks, wood chips/chunks, charcoal, disposable
  aluminum pans ("pan" alone stays food-neutral).
- **Sibling cache lookup**: a line whose own words were never searched
  reads the answer stored under its key's words before FDC is asked.
- **Lazy food detail**: the food is built from the search hit's nutrients
  when they are macro-complete; `/food/{id}` is fetched only when the grams
  need FDC portions; no stand-in is written to `fdc_food_cache`. A decision
  (pick, confirm, apply-to-all) on such a line spends no request; a target
  that needs portions fetches once and a failure counts in `applied.failed`.
- **"A or B" split**, narrow form: the left alternative is searched when it
  is itself a known query or rewrite key, never an adjective.

Measured on the checkpoint-1 snapshot before shipping: only the 361
regex-matched library lines change key or query; 56/56 sibling pairs rank
the same top food; grams and gram_source identical for all 2,969 lines under
the lazy path; 64 lines / 54 phrases split, every left side a noun food.
Projected saving at checkpoint 1: ~540 of ~2,170 remaining requests. The
accuracy batch (whole-bird and species rewrites, the energy fallback, the
dish-record cut, the count-noun cap, grams from cached portions, discarded
media and edible yields) follows, replayed cache-only with a `stale` sweep.

Review fixes (Run 040, both fleets on `13030d0`): the " or N unit" cut
dropped the whole alternate food ("masa harina or 3 tablespoons cornstarch"
→ "masa harina"; Sonnet HIGH) — it now drops only the amount and the
or-split decides what is searched; the fruit move ran before the amount cut,
so "plus 1 tablespoon juice from 2 to 3 lemons" became "lemon" (now "lemon
juice"); the or-split treated an EMPTY cached answer as a known query
("pancetta or bacon" lost its 25 candidates); a decision on a lazily matched
superseded (detail-404) food was reverted by the next compute because the
prior-decision and edited-orphan paths still fetched (now cache-first via
knownFood, one 404 remembered); knownFood scanned the whole search cache
before reading the line's own answer (164 ms → 1 ms at 13k rows); retries
rode an already-spent budget grant (each attempt now acquires one, so the
tally equals the grants); the bulk job's closing tally is the job's delta,
not the process total; a rewrite-keyed line no longer falls back to the raw
sibling phrase; the "563 of 563 equal" comment was false — a search hit is
the detail rounded (54 of 70 fixture foods differ, all under 1%), which the
lazy path accepts and a test now documents. Fourteen missing pins added
(sibling precedence and own-query ranking, every equipment word, the cut
connectors and unit words, the detail's portions in gramsFor, cache-first,
the apply-to-all portion fetch and its `failed`, the pick path, macro
completeness, the or-split branches, the 404 stand-in write, the tally log).
`matcherVersion` 5. The library-wide sweep itself finished the same evening:
1,190 recipes in 3 h 04 min, 0 failures, 13,615 lines — counted 76.4%, check
11.9%, no grams 11.1%, no match 0.6%; 142 recipes complete; 1,802 searches
and 961 foods cached (archive `.claude/diag/2026-09-26/`).

### The accuracy batch (2026-09-26 → 27, matcherVersion 6)

Built from checkpoints 1–3 of the library sweep (the whole library replayed
cache-only on the efficiency batch: counted 76.4% → 77.5%, 154 recipes
complete) by an Opus 5.5 builder/verifier loop in two passes, each validated
by replaying the cached answers and foods over a copy of the 13,615-line
snapshot with a provider that throws on any network call.

- **Energy-less records (A1)**: the Atwater fallback reads fat from nutrient
  204, then 298 (FDC files extra-virgin olive oil's fat only under 298 —
  240 counted lines added 0 kcal); a food with no energy and a missing
  macro is held out of the totals with `hold: no_nutrients`; 'spaghetti'
  joins the dry-pasta rewrite.
- **A `hold` reason on match rows** (`no_nutrients`, `discarded_medium`,
  `second_food`, `dried_for_fresh`): the engine's reason for keeping an
  `auto` row whose name score passes out of the totals. `matchBucketFor`
  treats a held row as `check`; the matches body and the review sheet's
  WhyLine say why. Documented in API.md.
- **Whole birds and species (A2)**: rewrites for turkey, whole chicken,
  chicken, standing rib roast, sirloin tips; a species-mismatch dock (−0.30
  when the query names an animal the record does not).
- **Dish and product records (A3, N3, N10)**: `_carriesHead` cuts the
  description at the first " with " / " on " (34 lines on snap1: beef broth
  → "Soup, vegetable with beef broth" no more); markers toddler / babyfood /
  tots / puffs / julep; identity tails heart(s), meat; "N percent" → "N%";
  ~30 rewrites (sandwich bread, buns, sweet potatoes, frozen peas, clam
  juice, tomato sauce, orange juice, pork butt, cottage cheese, masa harina,
  cream of coconut, gelatin, fresh peas, butter beans, celeriac, mustard
  seed …). Targets whose answer is not recorded sit in
  `_pendingLiveVerification` until one live search confirms them.
- **The count-noun cap (A4)**: count nouns (leaf, wedge, sprig, clove,
  fillet, rib after celery …) leave the query tokens when another token
  remains — 217 right lines move check → counted on the library (lemon,
  basil, thyme, anchovy, lime …); kosher salt → 'salt table' (108 lines).
  `allowDriedForFresh` (user answer #5, default false): a fresh-herb line
  the engine put on a dried or ground spice record is held
  `dried_for_fresh` (55 lines) rather than counted at the fresh amount.
- **Grams from what is cached (A5)**: volume portions from SR/FNDDS records
  after the density table (798 no-grams lines resolve), unicode fractions in
  parenthetical weights, scallions and green onions at 15 g a piece (87
  lines were 110 g), package nouns (sleeve, box, bag, loaf), piece keys
  matched on whole tokens (pineapple ≠ apple, garlic head ≠ clove), amount
  ranges keep the upper bound unless `rangeWeightsMidpoint` (user answer
  #7) is on.
- **Variety dock (A6, user answer #6, on)**: −0.03 for red / baby / brown /
  roma / beech the query does not name — 251 onion lines leave "Onions,
  red", 94 carrot lines leave "baby", 19 cremini leave "beech".
- **Macro fallback (A7)**: a fallback candidate is accepted only when its
  extra words are form words (the token-subset rule); `RankedCandidate.
  docked` records the head-noun, wrong-food, species and brand docks.
- **Discarded media (A8, user answer #2)**: oil / shortening / lard of
  400 g or more, or any "for (deep-)frying" line, brine salt of 3 tbsp or
  more dissolved in a brine, soaks → `gram_source: discarded` at 0 g under
  the zero policy (29 frying lines / 41 kg / 368,000 kcal; 35 brine-salt
  lines / 2.6 M mg sodium); brine sugar, salt baths and cheese-making milk
  are held for review with their grams. Rubs and cures are kept.
- **Edible yield (A9, user answer #4, on)**: FDC's own "excluding refuse
  (yield from …)" portion scales a bone-in / whole-bird / shell-on weight
  (pork rib chops ×0.57); boneless and meat-only records are docked when
  the line says bone-in or skin-on (12 lines). Records without a refuse
  portion keep the printed weight — 17 cuts need one live fetch each.
- **Or-split guard (A10)**: the left alternative is searched only when its
  answer names it AND its top confidence is at least the whole phrase's
  (the vermouth lines are back on white wine); vermouth → the dessert-wine
  target.
- **Second-food lines (A11, N5, user answer #10)**: "zest plus juice",
  "eggs plus yolks" and the like are held `second_food` under their own key
  (`lemon zest plus juice`) so a decision on the zest never reaches them;
  same-food "plus" amounts are summed (120 lines); leaked jar / can / #N
  amounts leave the keys.
- **Canned legumes (N1, user answer #9)**: a can or jar in the amount sends
  the query to the canned record; the drained weight is a switch (default
  drained). **Cook-state dock (N2)**, **lone-adjective items (N4)**,
  **participles after a cut (N8)**, **the 0.52–0.54 review band (N9, off)**.

Simulated on the whole library (a rewrite target answered by the union of
its sources' cached answers): counted 10,548 → 11,789, check 1,527 → 1,336,
no grams 1,463 → 413; the real numbers come from the replay on the scratch
copy, which spends one live search per pending target.

Measured on the real replay (75 live requests): counted 10,548 → 11,896
(87%), check 1,527 → 1,276, no grams 1,463 → 366, recipes complete 154 →
334, recipes over 1,500 kcal a serving 62 → 44, over 4,000 mg sodium 57 →
15; of 916 food changes 854 improved, 57 neutral, 5 regressed.

Review fixes (Run 041, both fleets on `d60bcd1`, matcherVersion 7): the
apply-to-all reach and `others` now include a held sibling, and a decision
(pick, confirm, skip, un-skip) clears the hold; a discarded or unmeasured
0 g row counts whatever its confidence (bucket rule, totals and queue SQL
agree); `lineItemOf` walks comma segments until one names a food; a "plus"
line is one food only when both parts name the same food (brown sugar plus
granulated sugar is `second_food`); "(3½- to 4-pound)" is a range; the
edible yield fetches the detail it needs once and a stand-in never claims a
factor; a re-pick on a discarded medium keeps 0 g; the eaten part of a
"plus" line is counted; the count-noun cap keeps "half" and never leaves only
a dish marker ("curry leaves"); the volume-portion fallback prefers the
portion whose words match the item, else the median; a parenthetical
restatement is not summed twice; second-food keys come from the normalized
parts. From checkpoint 4: "bone-in (skin-on) chicken pieces" → the whole
chicken record, "instant or rapid-rise yeast" → instant yeast (+21 complete
recipes), Cornish hens → the raw record with FNDDS "cooked" as a cook-state
token, "imported"/"australian" as variety words, cherry tomatoes, packed
qualifiers, "oven bag", pink curing salt, a pinch or dash as the food's
teaspoon portion ÷ 16 and a sprig at 0 g (switch), no detail fetch for an
engine pick below the gate. Sixteen pins added, three of them on synthesized
frying/soaking lines the corpus lacks (a stated exception, the user's call).
Cache-only replay: counted 11,896 → 11,999, check 1,276 → 1,154, no grams
366 → 237, with 149 lines waiting on unrecorded answers.
Real replay on the scratch copy (27 live requests, 24 s), counted with the
queue's own bucket SQL: counted 11,929 → 12,133 (89%; snap6 re-bucketed
under the v7 rule), check 1,243 → 1,164, no grams 366 → 242, no match 76;
recipes complete 334 → 414;
over 1,500 kcal a serving 44 → 39; over 4,000 mg sodium 15 → 14. The
review's critics found three gaps outside every lens: a reached or
inherited decision re-holding `second_food` siblings (closed by M1's
`decided` flag), an amount edit on a confirmed discarded frying-oil line
re-deriving the full oil through the orphan re-attach path (fixed after the
batch: that path now takes `engineOutcome` with `decided: true`; pinned on
0116 typed over to 3 cups), and `_macroComplete` without the NLEA-298 fat
fallback (not shipped: no record among 33,708 cached candidates publishes
energy, carbohydrate and protein with fat only as 298).

### Checkpoint-5 batch (matcher v8)

Checkpoint 5 (five Opus 5.5 auditors over snapshot 7 vs 6) found two real
regressions in v7 (the comma walk built a key the coconut rewrite never
saw, so a macaroon line counted 720 g of coconut water; pink curing salt
counted inside a discarded brine), that 12 of 15 detail fetches bought
nothing (Foundation and FNDDS records publish no refuse or drained
portions), that the 0.45–0.50 band holds 395 lines whose score is capped
whenever one query word has no FDC counterpart (47% right, 27% wrong, so
the gate stays at 0.5), and that a group decision RELEASED `second_food`
siblings at first-part grams (about 4,846 g of juice, yolk and white over
108 lines would vanish on the first click). The batch, built by a fixer
with three verify/refix rounds and measured cache-only on a copy of
snapshot 7: holds are split into FOOD holds (cleared by a decision that
reaches the line) and LINE holds (`second_food`, `discarded_medium`, never
cleared by key; the reach SQL skips them and `applied` counts only rows
whose bucket changed); the coconut rewrite, the same-sentence brine rule
and prep-only comma segments dropped from keys; coverage-only synonyms
(chile → pepper, zest → peel), "Spices," qualifiers and a no-credit word
set with a head guard (+52 complete, 0 wrong band lines counted);
second-food resolution behind two switches on by default — a zest of at
most a tablespoon plus the same fruit's juice counts the juice on the
fruit's juice record, eggs plus yolks or whites count the parts' summed
piece weights on the whole-egg record (100 of 125 held lines released, 25
stay held); volume grams from a cached SR sibling for portion-less
Foundation records; rewrites to cached targets (pancetta → bacon is a
flagged approximation); normalizer leaks (a leading or/and, pinch, very,
torn, tightly) and the pinch basis; yield and drained-can fetches only for
SR Legacy records, the whole-bird "yield from 1 lb ready-to-cook" read on
171447 for whole-bird lines (switch), Cornish hens sized by the record's
bird portion; connector tokens dropped from ranker scoring (switch,
measured apart: 69 lean-only picks flip to lean-and-fat); ranker tidy-ups
(imported docked only against a domestic record of the same cut, the white
dock only on egg records, the volume fallback prefers the line's own unit
then a default form, `cured_for_fresh` as its own hold). Removed as
unobservable on the recorded answers: cremini → crimini, the chili/chily
synonyms, the hungarian/spanish qualifiers, the basmati/jasmine rule.
Cache-only replay on snapshot 7 (queue SQL): counted 12,133 → 12,514,
check 1,164 → 840, no grams 242 → 210, no match 76 → 51, recipes complete
414 → 540; three recipes and 24 lean-and-fat lines wait on unrecorded
answers (about 16 live requests).

Review fixes (Run 042, both fleets on `f72094f`, matcherVersion 9). The
one root both fleets found four ways: the apply-to-all offer (`others`,
`others_lines`, the reach SQL) counted siblings the citrus and egg rules
had already resolved, which the writer skipped — "Apply to 43 lines" then
applied 0. One Dart-side reach (`decisionReach`) now feeds the offer and
the writer, leaves out rule-resolved and line-held lines, and counts a row
as applied only when its bucket changed or it took the decided food; a
line-held row is a group of one in the queue and never `decided`. Un-skip
of a person's row is never re-held `second_food`, and un-skip of an
engine row the rule covers moves it to the rule record like a fresh
compute. "Juice from 3 or 4 limes" keys `lime zest plus juice` (the fruit
taken from the raw line when the item has none). A no-credit word leaves
the denominator only on a record that carries the head (Tofu no longer
overtakes "Apple, raw" on the McIntosh line), the chile → pepper credit
applies only to hot-pepper records ("Thai red chiles" → the hot chile),
and mcintosh/english/littleneck are credited only on plain records. One
whole-bird regex with the part-word exclusion on both branches, pinned on
0452 (1,104 g, not 1,814). Identity participles (sweetened, smoked, dried,
salted, cooked, canned, pickled, …) stay with their food in a comma list.
"¼ teaspoon ground cloves or allspice" counts cloves. Among same-unit
portions a chopped/minced/grated line reads the matching portion first
(¼ cup grated onion 40 g, the same per mL as 2 tablespoons). A failed
yield, drained-can, sibling or rule-record fetch now fails the compute
like the search path (the sweep retries; the line is never stored counted
at gross weight with the hash current — 12 bone-in pork lines were). Egg
part keys are food-first (`egg plus white`, `egg plus yolk`, `egg yolk
plus white`). API.md documents the PUT override's rule-grams special case
and the fetch-failure rule. The fixture provider throws `UnrecordedAnswer`
for any answer not recorded (a miss is never a silent 404); 7 foods and
39 searches were recorded from the snapshot cache. Boot now re-keys
DECISIONS BEFORE ROWS in one shared step (`rekeyAfterMatcherChange`): a
decision's old-key row is the only reliable example once a line's
prep-kept reading changes too (Key Lime Pie's v8 pick, pinned). Cache-only
replay on snapshot 7: counted 12,514 → 12,509, check 840 → 843, no grams
210 → 212, complete 540 → 536 — the four lost are recipes whose required
detail fetch now fails instead of storing gross weight; 27 recipes wait
on 11 food details and 1 search the live replay will make.

### Checkpoint-6 batch under the user's rulings (matcher v10)

Checkpoint 6 (five Opus 5.5 auditors over snapshot 8 vs 7) found 3
regressions in 712 changed rows (two lines that lost their grams on a
better record, one tuna light → white), 318 upward gate crossings all
right or acceptable, and one new hole: a confirm on a line with no grams
left the queue while the recipe stayed partial. The user then ruled on
every open question (2026-09-27): variations and "(recipe follows)"
sub-recipes stay OUT of the main totals (revisited later); everything
else went with the recommendations. The batch, built by a fixer with
three verify/refix rounds plus a fourth pass for three pin-vacuity
leftovers: a `confirmed` row with a food and no grams is `no_grams` in
Dart, SQL and the totals alike; the two lost-grams regressions
(blueberries via the frozen sibling's cup, hamburger rolls via the
record's roll portion); raw country-style ribs (rewrite to the raw record
with its 0.65 yield — the general cook-state dock moved no line); cached
band rewrites (gorgonzola, arborio, 90 percent lean sirloin, andouille,
kielbasa; asiago → Parmesan and allspice berries → ground allspice as
FLAGGED approximations); a cooking-water medium — salt or baking soda in
water that boils and is later drained is held for review, and "dissolve …
in N … submerge" is brine at any volume; shellfish bought in the shell are
held (`in_shell`, 18 lines); every counted gross-weight meat or bird on a
record without a refuse portion carries an "approximate" basis and the
whole-bird basis names the ready-to-cook yield; a nutrient sibling for the
energy-less Foundation napa record; the second-food tail (mixed-number
ranges, zest strips with a juice volume, a bare zest keyed by its fruit);
the "skinless" credit only on records carrying the head with "lomi" and
"<head> salad" as dish markers; a 0.5 − 1e-9 gate floor; the lime zest →
"lime peel raw" rewrite (one approved live search, pending); and a
`basis_kind` flag ("per_batch" when the serving basis is exactly 1 — the
fixer's first cut, basis ≤ 2 with no serves count, mislabelled 29 two-yield
recipes and was refixed) shown as a small "per batch" label. Cache-only replay on snapshot 8:
counted 12,513 → 12,540, check 841 → 819, no grams 210 → 206, no match
51 → 50, complete 540 → 553 (23 gained; 9 dropped on purpose because a
line is now held for review, plus the carbonara pasta-water salt); 5
recipes wait on the lime search. Three guards the corpus cannot exercise
(the dissolve verb's own-sentence scope, the water-before-the-salt bound)
are pinned on synthesized lines, stated as an exception in the test.

Review fixes (Run 043, both fleets on `b405a52`, matcherVersion 11). An
un-skip re-derives the row's holds and keeps every LINE hold (in_shell,
second_food, discarded_medium) — toggling an inherited-decision shellfish
line off and on had counted its shell weight; only a person's own confirm
or pick clears in_shell. An amount-less bought-in-shell line ("1 dozen
mussels", "24 oysters") is held on a fresh match too, never counted at
0 g. A shell-on shrimp line the recipe peels is still bought in the shell
and stays held (0429, weighed with its shells — the fixer's first cut had
counted it at gross weight and the last verify round reverted that to the
ruling); "debearded" went (every such line also says scrubbed); the rule
holds 18 lines. A dissolve is brine only when the salt's own mention
follows the verb, the "in <amount>" follows in the same sentence, and the
step says "submerge" (a dough's yeast water and a sugar dissolved beside a
stirred-in salt are pinned as synthesized negatives). A held medium's
eaten "plus" part is shown as the row's grams and is what a confirm
counts (0300 Classic Macaroni and Cheese: 6 g of the 24 g line). With
several salt lines, a bare "salt" in a drained pot belongs to the one line
no step names with its amount (0358, 0461 now held). Every media rule
reads only the recipe's own steps — a variation's pot never touches a main
line. The "approximate" basis comes from the line and the cached search
hit, never from whether the detail was fetched, and an in-shell line
reads it too. An exact ranker tie breaks toward the plainer record: the
lean-and-fat sibling over "lean only", the unheated or unbaked record over
a cooked one (kielbasa 3 lines, pie dough 12, shrimp 5; 14 cached answers
change top pick, every one a tie). Lime zest is a FLAGGED approximation
on "Lemon peel, raw" (the live search settled that FDC has no lime peel
record; the answer is recorded). The napa nutrient sibling is pinned and
named in a hand-entered row's basis. The staleness hash now covers the
recipe title and its own step texts, since the media rules read them: a
drain added or removed makes the recipe stale (every recipe goes stale
once at this bump). The changelog no longer claims a bare "peel" is
handled. Live replay on the scratch copy (0 requests — every recipe
recomputed from cache after the hash change): counted 12,544 → 12,542,
check 816 → 818, complete 553 → 552 (0358 lost to the cooking-water
hold; 0461's pasta-water salt held too). Checkpoint 7 (five Opus 5.5
auditors) confirmed those numbers and found that the fixer's cache-only
replay had run on an intermediate build (the first paragraph's 17 lines
/ 553 figures were from it). Its two counted wrong-food regressions since
v9: the "skinless" credit lifts both skinless-halibut lines onto FNDDS
"Fish, halibut", a cooked record at 175 kcal/100 g (0273 complete about
190 kcal a serving over) — needs one live search for the raw record.

### Checkpoint-7 zero-request batch (matcher v12)

Only the checkpoint-7 items that need neither a ruling nor a live answer.
`_singular` strips "-es" only after s, x, z, ch, sh or o and otherwise the
"s" alone ("whites" → "white", not "whit"; "tomatoes" still → "tomato"):
26 egg-white lines leave the check bucket at 0.95 and 14 recipes complete
on them alone; four wrong foods the stem let through got guards (FDC's
"Spices," and "Beverages," class segments cover nothing and take no
ready-to-drink dock unless the query names the class; a puree base form;
a tapenade composite; the "Alaska Native" phrase). Zero-request rewrites,
each ranking its record first on a recorded answer: medium-large,
colossal and shell-on jumbo shrimp → the raw shrimp answer; skin-on
salmon fillets → the raw salmon record (10 lines off a kippered record);
pepperoncini → "Peppers, hot, pickled"; chen pi → orange peel (flagged
approximation); juice oranges → navel oranges. The normalizer cuts a
dangling trailing "and"/"or" ("lime zest and"), and lineItemOf reads on
past a lone size or firmness segment ("2 medium, firm, ripe tomatoes":
four no-match lines now count). "N dozen" is a count of N × 12 (0105's
mussels 15 g → 180 g, still held); a `_varietyHosts` record that files the
head after a different food noun ("Mushroom, oyster") is docked when
another record files the head first, so 1184's oysters rank "Oysters,
raw". The three halibut keys rewrite to a query for the raw record that
stays PENDING (no recorded answer; the user decides the live search).
matcherVersion 12; decisions re-key before rows. Cache-only replay on
snapshot 10: counted 12,542 → 12,594, check 818 → 773, no grams
206 → 208, no match 49 → 40, complete 552 → 573 (20 gained, 0 lost); the
next live sweep would ask about five answers (the halibut search, "ripe
avocado", "ripe bananas", the prune and oyster details).
(Live replay of v12: only two of those were asked — the halibut search,
which put all three halibut lines on the raw record at 0.98, and the
prune detail; the avocado and banana lines resolved from cache; the
oysters line stayed on the mushroom record because the dock described in
the v12 commit message had never been written — see Run 044.)

### Review fixes and the 2026-09-28 rulings (matcher v13)

Run 044 (both fleets on `0697d8d`) found that the "host-record dock for
oyster mushrooms" in the v12 commit message did not exist: the fixer had
reported it, the workflow's verifier had signed it off, and the commit was
written from the report. It exists now (`_varietyHosts`: a record that
files the head only after a different food noun is docked when another
record in the answer files the head first; "oysters" ranks "Oysters, raw"),
and every batch is now committed only after the orchestrator greps the
tree for each named symbol and runs its pin and a mutant; the verifier
confirms mechanisms by symbol grep and diff, never from the report. Also
from the fleets: the stem strips "-es" after x too ("cake mixes"; a "-zes"
word loses only its "s") and the connector cut drops a trailing "or";
"center-cut skin-on salmon fillets" takes the salmon rewrite; the prune
detail is recorded; the "dozen" branch applies to the amount the leading
number belongs to; a below-gate pick that moved to an uncached twin keeps
the grams path; "⅔ cup crushed saltines" reads the line's own count; API.md
names chen pi (dried peel on a raw-peel record, about 3× short per gram —
a ruling item) and pepperoncini. From the Opus critic: "(recipe follows)"
and "(this page)" reference lines are never counted on a food — of the
119 such lines, 116 had been matched to a food and 11 counted with grams,
up to 2,082 g of frosting — except a bare COUNT of the food itself (four
hard-cooked-egg lines count their eggs; taco shells stay at 0 g because
their record's "shell" portion is written in a form the grams code does
not yet read — checkpoint 8). The user's rulings of 2026-09-28:
poured-away media the rules could not see (a poaching liquid's soy, salt
rinsed off in a colander, salt or acid in a cheese milk, a pot emptied
with a skimmer, the written pot share of a divided salt line) are held
(18 lines in 12 recipes; the eaten part is stored as grams only on the
"plus" lines — checkpoint 8 found the other held rows still carry the
whole poured-away amount, a fix for the next batch); sugar and aromatics
dissolved in a dissolve-and-submerge brine go to zero like the salt (a
dunk that leaves liquid on the food stays held); fresh herbs with no fresh
FDC record count on "Spices, X, dried" as a flagged approximation and a
line offering the dried form is never held (the 57 dried-for-fresh holds
are gone; cured-for-fresh meat stays held). matcherVersion 13. Cache-only
replay on snapshot 11 (the v12 live replay): counted 12,596 → 12,755
(93.7%), check 772 → 654, no grams 207 → 169, no match 40 → 37, complete
573 → 660; the next live sweep needs two approved details (oysters, white
chocolate).

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
- 2026-07-24 — **The added-species matcher nudge is deliberately SMALL** (user
  chose "small turkey/deli nudge" from the options): turkey/chicken are
  legitimate meats, just not the default for a generic query, so the dock only
  needs to break a tie — over-docking would sink a legitimate turkey/chicken
  match below the review gate. It later proved too small in one case (see the
  breakfast-sausage entry below), which split it into its own −0.12 bucket
  rather than raising the shared off-form penalty.
- 2026-07-26 — **breakfast sausage matched a turkey link / a breakfast
  biscuit.** FDC's "breakfast sausage" results carry no pork option; the best
  available is a beef Foundation entry (nutrition close to the pork default,
  unlike lean turkey). The −0.06 species nudge was overwhelmed by the raw/cooked
  form swing (the turkey link was "raw", +0.02; the beef "pre-cooked", −0.06),
  so the meat qualifiers were split into `_offMeatTokens` at −0.12 (wrong meat >
  wrong cook-state), and "biscuit" added to the dish markers (a "…breakfast
  biscuit" is a sandwich). Live-verified no regression: turkey bacon / chicken
  sausage / deli ham still match (query names the qualifier).
- 2026-07-26 — **A trailing parenthetical weight is the line TOTAL, not
  per-unit.** `_parenWeightGrams` treated every printed weight as per counted
  unit and scaled by the count, so "5 slices bread (9 ounces)" (9 oz = the
  total) read as 5× (~1276 g vs 255 g). `_parenWeight` now marks a weight
  per-unit only when it is adjectival — nothing but the count precedes it
  ("4 (5-ounce) breasts") or it says "each" — and leaves a trailing total
  unscaled. Only changes counts >1; found while resolving rustic-bread grams.
- 2026-07-26 — **Ground spices resolve via the density table, not the FDC
  portion.** FDC *does* carry tsp/tbsp portions for "Spices, X", but their
  `measureUnit` is "undetermined" and the unit sits in an amount-less
  description ("tsp"), which `_portionGramsPerUnit` can't use — so a volume
  spice line fell through to nothing. Filled the density table (the designed
  fallback) with 26 spice/dried-herb densities back-derived from FDC's own 1-tsp
  gram weight, rather than reworking the shared portion matcher (riskier; some
  foods list two tsp portions, e.g. oregano leaves 1.0 g vs ground 1.8 g). Keys
  beat existing shorter entries by length (`ground ginger` over fresh `ginger`),
  and herbs with a fresh form are gated to "dried …".
- 2026-07-26 — **The editor reorder drop-flicker is a Bloc-vs-reorderable timing
  bug, fixed with an optimistic local list.** A `ReorderableListView` never
  reorders its own children — on drop it zeroes the drag-gap offsets in the same
  frame, snapping items back to the ORIGINAL order — while the real reorder
  arrives one microtask later over Bloc's async broadcast stream, so the drop
  frame paints the old order for a frame. `_OptimisticReorderableList` mirrors
  the list locally and reorders it synchronously in `onReorderItem` before
  notifying the cubit. Not reproducible in a widget test (`tester.pump` drains
  the very microtask that causes it), so the on-device flicker is verified by
  eye; the test asserts the synchronous local path instead.
- 2026-07-26 — **A ReorderableListView drag proxy rebuilds the item OUTSIDE its
  ancestor scopes.** The editor's ingredient/step rows read a per-list
  `InheritedWidget` scope via a `.of(context)!`; in the drag overlay that scope
  is absent, the `!` throws, and a release-build `ErrorWidget` paints a blank
  grey box stretched to the overlay — read as a styling bug, and two symptom-only
  fixes shipped before the thrown-error root cause was found. Each scoped list's
  `proxyDecorator` now re-provides its scope around the lifted child. Bordered
  cards carry a bottom margin, so their opaque lift is laid behind the card and
  inset by that margin (an opaque fill over the whole item painted the margin as
  a padding strip).
- 2026-07-28 — **The 2026-07-27 whole-branch review's defect and refactor
  batches landed** (the full findings document with severities and evidence
  lives locally in `.claude/reviews/2026-07-27-whole-branch-review.md`).
  Fixed: FTS now indexes subsection/technique content (migration 008 +
  Dart-side reindex at open); the nutrition match override passes `raw:` so
  printed-weight grams survive a re-pick; editor saves preserve meaningful
  duplicate step numbers (valid-run rule, app + server); the guided review
  flow advances by list-shrink alone and failed overrides surface their
  error on both admin surfaces instead of silently advancing; the triage
  bucketing rule is now ONE shared function (salt_shared `matchBucketFor`,
  SQL parity-pinned) with decided corners (overridden+no-grams stays
  flagged; un-skip returns to `auto`, not confirmed); path params are
  percent-decoded (multi-word tags stylable); `serves` derives at decode
  time for all schema versions and unrelated edits preserve a hand-set
  value (plus a `serves_mismatch` review check); hand-added YAML lines
  without an `amounts` key parse their `raw`; `kind_needs_review` left the
  canonical format; `images.credit` is pinned as free-text and rendered;
  imports take the documented before-import backup; recipe PUT gained an
  optional `base_hash` 409 precondition (editor echoes it; browser
  beforeunload guard added); scan/import validate documents at ingest;
  backup retention is per-trigger with a `BACKUP_RETENTION` knob; FDC and
  image-fetch failures are 422s with real messages; log timestamps are
  UTC-with-Z and every surface renders viewer-local times; favorites
  paging is count-derived (no skipped cards); corpus-free tests were
  hoisted out of whole-file corpus gates (CI now runs the SSRF, validation,
  containment, and PDF-spanning pins); simplifications: `Paged<T>` deleted,
  slugify derives from `vulgarFractionAscii`, dead `formatQuantity`
  removed, `invalidateReviewCount` wired, one shared tag-colour rule and
  error-envelope decoder. Ranged parenthetical weights resolving to the
  upper bound was ruled INTENDED (won't fix). Suites: 196/491/210 green
  with corpus (baseline 192/473/201).
- 2026-09-07 — Ingredient decisions (user): build the human-only
  `ingredient_decisions` table (design review D3's third design), NOT the
  full dictionary; no seed (only test data existed); the review queue will
  group by ingredient by default for the food buckets with a lines view behind
  a toggle for amount problems, a group opening the EXISTING fix panel on its
  example line with apply-to-all spreading (mockup first); fix canned
  "tomatoes" and fold plural keys BEFORE the first library sweep. The first
  sweep runs on a database COPY with the real key to baseline the buckets.
- 2026-09-07 — Evidence-gated reviews stay at Find effort `high` (user);
  Run 036 measured `xhigh` as not a superset for either model. Every review
  runs a Sonnet fleet then an Opus fleet and the RUNLOG records the nature of
  each fleet's catches; the user reviews the accumulated log later.
- 2026-09-08 — Ranker (user, after design review D4): ship the head-noun dock,
  the composite/brand docks and the verified rewrites; drop R2 and IDF; put the
  "juice from N lemon" rule in the normalizer; add the no-match flag to the
  matches body and the fix panel; keep the judge's switched harness only as a
  saved diff (ship unconditional code); record a cookie answer to pin the
  sandwich guard; a second recorded mini-sweep for the still-wrong lines. The
  count-noun coverage cap is the NEXT design round, not this one. Subagents
  run on Opus 5 from 2026-09-08 (session-limit reasons), except the Sonnet
  fleet of the dual-fleet reviews.
- 2026-09-09 — Grouped queue (user, on the approved mockup): six calls —
  (1) widen `others`/`apply_to_all` to be food-agnostic (refined during the
  build: a sibling already on the food at confidence 1 is excluded); (2) row
  label = the example line's parsed item via `itemLabel`, key as fallback;
  (3) no group-scoped Skip; (4) no inline members this pass; (5) toggle
  remembered per bucket for the session; (6) chips always count lines.
