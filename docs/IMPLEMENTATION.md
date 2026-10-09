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

### The review-UI build (the checkpoint-8 mockup, 2026-09-28)

The approved mockup `docs/mockups/c1-review-ui.html` (artifact
DZk4sNM5XLCtt4Ft1vB6hN; the user's 2026-09-28 rulings 5-9 with my
recommendations) built as six units, matcherVersion unchanged at 13. U1:
a zero-gram row below the gate hides the food ("Counts as zero (no
amount)"; the engine's guess sits in a collapsed admin-only disclosure and
the fix sheet offers no confirm-as-is). U2: "Finishes recipes" is the
queue's default order (`sort=finishes`), every group carrying how many
recipes one decision on it completes (`finishes`, `finishes_recipes`,
`last_open`; the body's `finishable` / `open_recipes`), and the apply
receipt carries `applied.completed` / `completed_recipes` so the strip can
say "N recipes are now complete, as promised" or name the shortfall (a
pick of another food may finish MORE than promised - accepted). Measured
on snapshot 11: the finishes order completes 46 recipes in its first 10
groups against 12 worst-first (85 against 17 in the first 25); the
mockup's 53 / 96 reproduce exactly on snapshot 8. U3: grams on confirm -
the matches body carries `line_amount`, `kcal_per_100g` and a cache-only
`portions` list (each with the grams the line's amount weighs on it, never
a fetch); the sheet prefills the amount when the line's unit names exactly
one USDA portion and offers the others as tap-to-fill chips. U4: the
review card on a held medium or an in-shell row defaults to "Skip, poured
away" / "Enter edible grams", Confirm only where an eaten "plus" part
exists. U5: a flagged-approximation row's basis ends with " · approximation
(counted as <record>)". U6: `basis_kind` - a serving basis of 1 is
`per_batch` ("per loaf", from the MAKES yield) unless the yield's head noun
is a single portion (omelet, cocktail, sandwich, egg, drink - the only such
nouns among the corpus's MAKES-1 yields). A no-grams group keeps the pane
on the same ingredient. Closing the build's own review: the seven mutants
its verifier could not kill are pinned (the queue's promise to the strip on
a real snapshot-11 group; the in-shell row never offering Confirm; the
route's receipt over HTTP; the yield head noun, the first-clause split and
the 4-kcal carbohydrate factor on synthesized inputs stated as exceptions),
the totals' duplicated 4/9/4 now calls `kcalPer100g`, and the Lines view
also defaults to the finishes order (finishes-1 lines first, then worst) -
the mockup's open question 5 as recommended (ruled by the user 2026-09-30:
keep it — on the v15 replay the first 50 lines finish 50 recipes against 12
worst-first); a
consumer that relied on worst-first lines passes `sort=worst`. Wire changes
in API.md.

### The v14 engine batch: Run 045's union, checkpoint 8's fixes and the rulings (matcher v14)

Zero live requests. From Run 045 (both fleets): the sub-recipe rule now
gates EVERY write path (the fresh match, the orphan re-attach and the
prior-decision reuse — an edited marked line no longer keeps its stale
eggs at 408 g), a marked bare count whose pick sits below the gate is held
in check rather than confirmed as a 0 g sub-recipe, 0091's cheesecloth
bundle is not eaten (the v13 pin was wrong), the skimmer rule needs the
liquid left behind (water that evaporates or a served broth no longer
holds its salt), 0306's crushed saltines read their own count (48 g on
"Crackers, saltine", not 192 g of bread crumbs), the "-es"-after-z
docstring matches the code, a pick or un-skip landing on an unsearchable
line in a brining recipe no longer crashes (an empty head reaches
`_names`), and the docs stop calling brine sugar held. From checkpoint 8:
the engine may rewrite its OWN rule rows (`engineRuleNotes` /
`isEngineRuleRow`: a confirmed row with no food and one of the engine's
four notes — sub-recipe, seasoning, equipment, water — is the engine's,
not a person's), which unblocked everything that follows; the unread SR
portions (an amount-1 bare noun such as "shell" or "leaf", the "medium"
of several, a bare "stick", a "(750-ml)" volume, a "5-pound" weight in
the item, the chile as FDC's "pepper") lift 0478's taco shells to 103.2 g
and 23 no_grams lines; the poured-away detectors cover the 13 rows the
rulings could not see (soda rinsed off a velveted meat, a later "Drain
chickpeas", a court-bouillon, a milk-salt dip, a drained pickle, a poach
before a brine, a dunk sugar) and one the brief did not name (0063's
drained broth, garlic and bay); a fresh herb on its dried record counts
ONE THIRD of the fresh volume, the written "or 1 teaspoon dried" amount
when offered, and leaf counts 0 g, with the basis "· approximate (dried
herb record for a fresh herb)"; held media rows store only the eaten part
(51 rows now carry no grams, 7 an eaten "plus" part — none the whole
poured-away line) and a Confirm on such a row writes 0 g "poured away"
unless grams are typed; 0711 counts its 3 tablespoons of reserved oil,
"1 recipe … pie dough" lines are references, and 0249's fresh half ham
moves off the cured rump (`freshOverCured`). The rulings: 0731's "1
recipe Easy-Peel Hard-Cooked Eggs" counts the subsection's six eggs (300
g) — the only single-food subsection in the corpus; 0407's wiped-off
degorging salt is held; a marinade's food stays counted; a store-bought
alternative stays 0 g. The cached-rewrite batch took 22 of checkpoint 8's
first 30 keys (thick-cut bacon, whole-grain mustard off Buckwheat, Thai
chiles, elbow macaroni, no-boil lasagna noodles, 80% chuck off bison,
Shaoxing off dessert wine, filet mignon and chateaubriand off pork chops
and Denver cut, kale, baby back ribs off beef, sea salt off wheat flakes,
white baking chips off potato chips …) — 72 counted rows changed food,
each judged against its head noun; the other 8 keys (baguette, broccoli
rabe, instant/minute tapioca, St. Louis spareribs, whole farro, bone-in
turkey breast, pomegranate seeds) sit on their right record BELOW the gate
in every cached answer and need one search each (not spent — approval
pending), so the batch's own gate of 744 complete was not met. The
verifier's replay caught one wrong-mass crossing: the chile-as-pepper
rule sized New Mexican, guajillo and chipotle chiles by 168570's 0.5 g
"pepper" (a bird chile; a pod is ~7 g by the corpus's own parens), three
recipes completing on 1–5 g of chiles — a sub-gram pepper portion now
weighs only a chile the line calls small (arbol, Thai, japonés), the rest
wait for a dried-chile piece table. Cache-only replay on snapshot 12 (the
v13 live replay): counted 12,755 → 12,860 (94.5%), check 654 → 563, no
grams 169 → 155, no match 37, complete 660 → 712 (+56, −4 by the rulings:
shrimp salad, eggplant Parmesan, hummus, calamari); holds discarded_medium
41 → 58, cured_for_fresh 1 → 0. matcherVersion 14. Known limits: the 4
no-boil lasagna lines are on the right food with no per-noodle weight;
0286's whole peppercorns are still counted (head "pepper" does not match
"peppercorns"); Shaoxing sits exactly at the 0.50 gate; "thai chile"
resolves through the cached "jarred hot cherry peppers" answer; 0711's
plus-line substitution lives in the compute path only (a later pick
re-derives from "1 recipe" and stores no grams).

### Review fixes for the UI build and the v14 engine (Runs 046 and 047; matcher v15)

Run 046 (both fleets on the review-UI commit; the first with the Sonnet
fleet on Sonnet 5.5 — 22 claims, no empty lens) and Run 047 (both fleets
on v14) were fixed in one batch. The UI: the amount-first Confirm and the
field's Enter now write the STAGED pick (they had confirmed the food the
person just rejected at the typed grams — the worst defect of either run,
Opus alone); an untouched prefill is not sent after a pick of another food
and the old record's portion chips hide; "finishes" now promises only what
a confirm can count — a Check example or line with no grams, or a No match
line, never counts its recipe (snapshot 11: finishable 326 → 281, line
promises 372 → 303; the finishes order's payoff held at 46 / 85 while
worst-first fell to 11 / 15); the receipt reconciles by id, an unpromised
completed recipe is a bonus and a missing one "was not completed by this
apply"; a bare count is a line amount ("8" for the scallops — a quarter of
the no-grams lines with a count had read "no amount"), and a one-word unit
("dash") stays a unit; `kcal_per_100g` follows the nutrient sibling the
totals use (napa 4 → 16); a bare confirm on a below-gate zero row is a 422
`zero_row`; the approximation suffix follows the record whoever chose it
but never a skipped row (invariant 7 as first written was too strong);
`basis_kind` reads per_serving for "SERVES 1" and per_batch for "MAKES 1
TO 16 EGGS" (a singular head noun only, a trailing parenthetical dropped);
a stale page-two reply no longer overwrites a later sort switch (request
tickets); the pane stays on any line left waiting on an amount; a skipped
zero row keeps its guess hidden; the single-portion prefill appears when
the portions first arrive; the label's fold controller is built in
initState. The engine (v15): a repeated line takes the nth row of its OWN
text from a list of all rows by text — a kept engine rule row is re-derived
in place and never pops a later twin line's decision (0405's second "Salt
and pepper" override had been copied onto the first by any recompute; 21
library recipes repeat a rule line), which also fixed a pre-existing case
where an auto first copy took the second copy's skip; the orphan re-attach
path carries the discarded_medium hold and a Confirm writes 0 g whenever
the engine's own detector holds the line (a confirmed 0 g salt, edited,
had come back with no hold and the next Confirm counted the whole line);
ONE weighed line (`weighedLine`: the sub-recipe's eaten plus part) and ONE
sub-recipe gate (`subRecipeRowFor`) now serve compute, pick, confirm,
un-skip, apply_to_all, the candidates and the matches body (0711's re-pick
had stored one onion's weight as oil; apply_to_all had bypassed the rule);
un-skipping a 0 g held medium restores the engine's row instead of counting
it as resolved; the second-"or" guard keeps the animal/adjective exemption
("chicken or beef or vegetable broth" had matched raw chicken at 1.0); the
staleness hash covers the referenced subsection; flake and coarse sea salt
take the kosher density (0.72; table salt had been 2–3× heavy); a sub-gram
"pepper" portion weighs only a small DRIED chile (arbol, bird, "small …
dried" — a fresh Thai chile had read 0.5 g); a bare count with a printed
paren volume is weighed at that volume (the chard's "4–6 leaves (about 2
cups)" 240 → 72 g); no herb suffix on typed grams or 0 g sprigs; API.md
corrected (the taco shells count 103.2 g, `freshOverCured`, the chile
guard, the poured-away wording). Cache-only replay on snapshot 12 is
unchanged in every bucket (counted 12,860 / check 563 / no grams 155 / no
match 37 / complete 712); eight rows re-massed, none re-matched, one recipe
−8 kcal. Deploy note: the 26 v14 rewrites resolve through search answers
cached in the scratch copy — the live database must carry those
`fdc_search_cache` rows before a live recompute, or it will spend requests
or keep the old matches.

### Review fixes for v15 (Run 048; matcher v16)

Run 048 (both fleets on the v15 commit) found that v15's twin-line pairing
was worse than v14's: pairing rows by their stored text meant editing the
FIRST copy of a repeated line dropped the person's decision on the SECOND
copy, which never moved (Opus, HIGH); a line inserted above two decided
twins lost one decision and duplicated the other (both fleets); and the new
"demotion" of a decided row was the engine's only unguarded write, so a
provider failure or a person's write during the compute's wait erased a
decision (both critics). The pairing is rebuilt (`pairRowsToLines`): rows
are aligned to lines by the longest common subsequence of their text, so
every line nothing moved keeps its row and a shifted run keeps its rows;
only the leftovers are re-paired (same position first, then nth order of
the same text). The whole layout is computed in memory and written in ONE
transaction before any wait (`relayoutIngredientMatches`: drop the rows
whose line was deleted, park movers at negative positions, place them) —
a person's row is moved, never rewritten, and the engine has no unguarded
write left. Held media keep a person's resolution through an amount edit,
a re-confirm and an un-skip (0 g poured away or their typed grams, never
grams-less), the review sheet never prefills a poured-away amount, and the
app treats a held line as held whatever its status. The pin batch's
"unobservable" reverts and deletions were undone where they protected real
lines: the pick and apply-to-all weigh the eaten plus part again; the SR
portion noun must lead its description ("cup, sliced" is no slice); "Do
not drain" is not a drain; the in-item ounces and "(1-liter)" readers are
back; a paren volume that says "each" is per item; only flake/flaky/coarse
sea salt takes the kosher density (fine sea salt stays table salt). In the
app, portions arriving while another food is staged no longer prefill the
rejected food's grams, a superseded failed reload no longer rewinds the
order or paints the error screen, and a mixed number ("1 1/2") is never
read as a unit. matcherVersion 16: every v16 rule change is invisible on
the ATK corpus — the cache-only replay on snapshot 12 is byte-identical to
v15 (12,860 / 563 / 155 / 37 / 712, zero provider calls) — but they change
what the engine writes for other libraries' lines, so recipes go stale.
Eight surviving mutants are argued equivalent in comments at their sites.
The user ruled on 2026-09-30 that the Lines view keeps the finishes order,
and approved any further live requests the analyzer work needs.

### The live-request batch, built dry (matcher v17)

The user approved the requests the analyzer needs (2026-09-30). A planner
measured every candidate on the v16 replay and kept only requests that
move lines: 13 searches — the eight stalled rewrite keys that sit on
their right record below the gate (baguette → "french bread", broccoli
rabe → "broccoli raab", instant/minute tapioca → "tapioca pearl dry", St.
Louis and full-rack spareribs → "pork spareribs raw", pomegranate seeds →
"pomegranate raw"), milk chocolate → "milk chocolate candy" (off the
chocolate-MILK drink), and seven new ones (swordfish, tuna, nonfat dry
milk, pumpkin purée, Nutella, water chestnuts, dried buttermilk) — plus
eight SR sibling details for portion-less Foundation records (pecans,
garlic, cabbage, carrots, celery, spinach, iceberg, napa). It dropped the
Thai chile repoint and the fresh-ham detail (they move no line), farro
(no volume sibling exists), the chocolate details (weight lines need
none) and the four no-match details (36 of 37 no-match rows have empty
cached answers). Zero-request additions reuse cached answers: the whole
bone-in turkey breasts, the boneless country-style spareribs, granulated
garlic on garlic powder, and a "liquid" dock scoped to a record whose own
form is liquid (the unsweetened chocolate moves to the solid squares; the
canned "solids and liquids" wording is untouched). A bare count of an
item whose record NAMES it in a numbered portion over 250 g now takes it
("1 baguette (about 22 in. long)" 324 g, where it had counted a 64 g
slice); an unnamed heavy portion stays capped. The proof is a dry run:
the cache-only replay of snapshot 12 asks the provider for exactly the 21
planned calls and nothing else (a first build had missed seven searches
because the plan was cut when handed on — a process lesson recorded).
matcherVersion 17; the live spend follows, the answers are recorded into
the fixtures from the resulting snapshot, and the pins move off pending.

### The live spend, checkpoint 9, the pairing design panel (matcher v18)

The v17 live run spent 25 requests (the 13 planned searches and 12
details: the 8 SR siblings and four follow-ons) and delivered the plan's
upper bound exactly: counted 12,860 → 12,957, check 563 → 512, no grams
155 → 109, complete 712 → 761; all 112 changed rows were planned lines, no
person's row moved, and a cache-only replay of the live snapshot
reproduces it row for row (the answers are recorded as fixtures, c7bad9d).
Checkpoint 9 found one miss: the density table matched keys as bare
substrings before a record's own volume portion, so "milk", "buttermilk"
and "water" weighed dry milk, buttermilk powder and water chestnuts as
liquids — three of the 25 details were fetched for portions the engine
never read, and 27 counted lines library-wide were mis-sized.

The row-to-line pairing had failed review in v14, v15 and v16, so it went
to a design panel instead of a fourth point fix. An oracle agent wrote an
identity-tracking fuzz (random edits over real corpus line lists — insert,
delete, amount edit, text edit, edit-to-equal, swap, cross-group move —
with a person's skips and picks carried by hidden identities, a write in
the stale window between a save and the next compute, and FoodData Central
failing mid-compute), proven on v16: 1,781 violations in 1,180 of 2,000
fresh seeds. Three designers in isolated worktrees (a weighted alignment, a
line diff, edit-time line identity carried from the editor) each reached
zero violations on 24,000 fresh edits. The judge chose the line diff:
`pairRowsToLines` is an order-preserving alignment scored, in strict
priority, by same text, then a pair at all (the fewest edits: a changed
line is one substitution, never a delete plus an insert), then a person's
decision kept, then a row at its own position; leftover rows then pair by
text and by ingredient key. `layoutMatchRows` writes that layout in one
transaction before any wait, at the top of the compute AND of a person's
match PUT (closing the stale window); a compute stops writing once the
recipe has been saved over (`contentHashOf` checked on every write); the
review sheet pairs in memory and writes nothing. Server only — no wire or
app change; the engine has no unguarded write left. Also in v18 (the rest
of Run 049 and checkpoint 9's fix 1): the density guard (short keys as
whole words or plurals, "with(out) salt" stripped, "ice cream" at 0.558,
dry milk / milk powder / buttermilk powder / water chestnut / ricotta /
cream cheese / oil-packed fall through to the record's own portion — 31
rows re-massed, all right, no bucket moved); the flake/coarse sea-salt
density only when that salt is the line's own food, the same decision for
its "plus" part and a held medium's eaten part, and the common spellings;
the per-item "each" volume paren when the parser kept it; a re-attach clears
a stale medium hold; an un-skip restores a person's typed grams as their
row; the approximation label and the held-medium filter read the weighed
line; the queue's failure tickets restore the order and grouping the screen
shows; the finishes paragraph rewritten. matcherVersion 18. Known limits
(marked in code): apply-to-all into another recipe during that recipe's
save, and a PUT whose own waits span a save, predate this batch.

### Run 050's fixes: the multi-edit oracle and the exact pairing (matcher v19)

Run 050 (both fleets on v18) showed the panel's pairing held on every
single edit and broke on a save that combines edits: its "fewest edits"
level credited a substitution across ingredients above keeping a person's
decision, so a move plus a delete or an amount edit in one save lost a
pick or swapped typed grams between two same-ingredient lines. The oracle
had generated single edits only. So the oracle came first: each fuzz save
now applies one to three edits, its explanation enumerator computes the
fewest-op scripts over insert / delete / substitute / move with a
cross-ingredient substitution costing a delete plus an insert (a flat cost
would have endorsed half the swap), and on v18 the shipped oracle finds
103 violations in 90 of 1,000 seeds (the "83" first written here was an
intermediate oracle's count — Run 051), every one on a multi-edit save. The pairing then went through
a heuristic search (candidate alignments and a local climb over the
engine's own layout cost) that reached zero but left thirteen of its pieces
unkillable and two seeds broken — and was replaced by the principled form:
`pairRowsToLines` is now an exact depth-first branch-and-bound that
minimises `_layoutCost` (the script's cost, then its edits, then the
decisions it drops, then the rows off their positions — the oracle's own
ranking), each line taking an unused row of its exact text or its
ingredient or none, with an admissible bound and a 10,000-expansion budget
that falls back to the best layout found from the plain alignment. It is
smaller than the heuristic search it replaced (that intermediate never
shipped; against the committed v18 the pairing section grew from 133 to 295
lines and engine.dart by 222 — Run 051 corrected the "−220" first written
here), every cost term
and the bound, budget and fallback die under a named seed or scenario,
and the oracle finds zero violations on more than 11,000 fresh multi-edit
seeds including the two residual ones. A 60-line list shuffled whole with
a quarter rewritten pairs in 76 ms (1.35 s before); an unedited library
pairs in one alignment and writes nothing. Also in v19: the compute's
version gate compares the ingredient-lines hash (a tags-only save no
longer blocks a compute) and a tripped compute stamps its totals stale;
the match PUT reads its body before loading the recipe, lays out the
STORED recipe, re-reads it after its own waits, and accepts the line's
text (`raw`) — a moved line answers 409 `line_moved` and writes nothing;
the sheet, the fix panel and the queue send it and refresh on 409; the
review GET's apply-to-all offer reads the paired rows; a skipped line
whose amount was edited re-derives its grams (typed or derived) so an
un-skip never counts the old weight; un-skip keeps a person's food and
typed grams on a sub-recipe line; a re-attach keeps typed grams on any
discarded medium. Grams: the density compound guard is general ("cream of
tartar", "cream of coconut", "mustard/cumin/coriander/cardamom seeds",
almond and apple butter fall through to the record's own portion), a named
nut takes its record's cup over the generic "nuts" density, a powder never
takes a "prepared with" record's drink cup, "small" is read only from the
item's own words, quantity words may precede a flake salt, and a shredded
or grated line takes the record's shredded/grated cup. Replay on snapshot
13: 58 rows re-massed (all judged right), one recipe complete → partial
(malted milk powder with no honest portion left): counted 12,956 / check
512 / no grams 110 / no match 37 / complete 760.

### Run 051's fixes: guards fed from the right place, the layout sequence, the gap mode (matcher v20)

Run 051 (both fleets on v19, 2026-09-30) found that v19's guards were sound
and fed from the wrong place: the apply-to-all RETRY after a 409 re-read the
line's text from whatever row now sat at the offer's position, so the raw
guard passed and the food was written — and broadcast library-wide — onto
another ingredient (HIGH, both fleets); the review queue sent a fallback row's
text; the sheet's fix panel was keyed by position. The gate compared hashes
for EQUALITY, which a save-and-revert (ABA) around a compute's or a PUT's
awaits defeats. And v19's skipped-orphan re-derive had re-implemented half
of the compute's outcome without the discard policy, so an un-skip counted a
frying oil's poured-away 672 g (Opus only; a regression from v18). v20, built
2026-10-01 after a usage-limit kill and a relaunch: (A) the app — an offer
carries the text of the line it was raised on and every send uses it; every
reload relocates the offer by that text or withdraws it and says why; the
queue sends the line's own text (no fallback row); the panel drops its
staged pick when the row's text changes; the app matches `ApiErrorCodes`,
never string literals. (B) one function, `editedDecisionRow`, decides what a
decided row becomes when its line is edited to the same ingredient — used by
the compute's orphan branches AND the PUT: it runs the compute's real outcome
(the discard policy, with grams), keeps typed grams when the amount is
unchanged or the line is a medium by that outcome, re-derives otherwise, and
keeps the status; a skip or a pick stands ahead of the sub-recipe rule; a
never-computed recipe written by a PUT is stamped `''` (stale) instead of
fresh; a compute whose gate tripped re-runs on the stored recipe (the
single-flight job no longer swallows a request); a recipe deleted during a
compute stops cleanly and during a PUT answers 404; the serving basis is read
from the stored recipe at stamp time. (C) migration 012 adds `recipe_layout`
(a per-recipe sequence bumped inside every relayout's transaction, and the
texts of the lines the rows were laid out on); the compute's writes, the
PUT's post-await write and each apply-to-all target write check the sequence
INSIDE their own transaction — equality of hashes is no longer the question.
(D) the oracle's op model: a cross-ingredient substitution is a delete plus
an insert (two ops), in the oracle and in `_layoutCost` alike — the "edits"
term became redundant and went; the LIS cost replaced a per-leaf n·m table
(400 lines: 730 ms → 95 ms, so the budget is not scaled); a last tie-break
on drift; a row's ingredient key is its stored key OR its own text's key
under the current matcher; a "gaps" oracle mode (two saves with the rows
left incomplete between them: a person's stale-window write, a save at the
compute's first provider call, a failed compute) found 224 violations per
1,000 seeds on the batch's pre-fix tree (Run 052 noted that figure was
measured on an unshipped intermediate, not on the committed v19) — the
pairing now reads a row-less position as a line of unknown text (→ 120)
and, with the laid-out texts from `recipe_layout`, 0 in 1,000
(22 seeds added to the regression list; the mode runs 60 seeds by default);
`pairingExpansions` pins the budget's magnitude. (E) grams: the sub-gram
dried-chile guard reads 'small' from the item's own words; the density table
yields to the record's own volume portion when the key is not the item's
head noun ("vanilla extract", "cayenne pepper", "cocoa powder": 272 counted
rows re-weighed on snapshot 13, every one judged by the record's portions,
cocoa 7.69 → 5.40 g per tablespoon; a variant that also moved Parmesan and
panko was measured and rejected); the apply-to-all writes an undecided row
the layout paired by ingredient key, so the offer equals the receipt; the
reach into other recipes is documented as an upper bound. Pins and mutants
for every term named by the two pin-vacuity lenses. Replay on snapshot 13:
calls 0, buckets unchanged (12,956 / 512 / 110 / 37, complete 760), the 272
rows above. matcherVersion 20. The verifier's one defect (the DB's own
stale-sequence refusal had no direct pin) was closed by hand before the
commit.

### Checkpoint 9's zero-request items: right picks, wrong-food rewrites, portions and aliases (matcher v21)

Checkpoint 9 had ranked, after the density guard, three zero-request fixes:
the right records already cached but ranked below the gate or under the
wrong query (#2), the wrong foods still counted (#3) and the unread
portions and aliases (#4). A read-only planner (2026-10-01) turned them
into an exact plan: for every line the rule, the cached target record and
the expected grams, dry-run through the real engine on a snapshot-13 copy
with zero calls, every moved row attributed. It also found that six of the
checkpoint's "right picks" were wrong (quick oats on the cooked record,
pickling cucumbers on dill pickles, fingerlings on potato bread, Calasparra
on rice crackers, white American cheese on a cheese sandwich, firm tart
apples on a candied apple) and left them alone. v21 builds the plan: 82
`_queryRewrites` entries to cached queries; a new mechanism, `_rankAs`
(51 entries) — a line reads a CACHED answer re-ranked under the record's
own words, consulted first in `lineSearchFor`, because 31 right records led
no cached answer under any query's own words (crab lump, collards, gai lan,
raw snapper, the raw dry legumes, raw pork tenderloin); a one-word item key
is always a rank-as entry and never a rewrite key, since a rewrite key is
also a `leftAlternative` food noun (the planner's 'thai' sent "Thai or
Italian basil leaves" to 225 g of hot peppers before it was moved);
'filtered water' water-like and 'banana leaf' a non-food; grams: jelly
densities scoped to the exact compound (apple / currant / jalapeño jelly
from 169642's 21 g tablespoon — a bare 'jelly' key reached "apricot
preserves or hot pepper jelly"), piece aliases (green pepper, fuji, yolk),
approximate densities (Aleppo on paprika, pecorino 0.42, ghee on oil) and
the other stand-ins the user approved as flagged approximations (dried
pinto / unspecified / small white beans on navy raw, spicy greens on
arugula, All-Bran on bran flakes, seven-grain on whole-wheat hot cereal,
fingerling on red potato, tapioca starch on the tapioca-pearl cup), pints
and quarts in a parenthesised volume, and the whole-item cap exemption for a
bare 'fruit' portion or the item's own noun up to 350 g (a mango 672 g,
chicken legs 1,060 g; the 625 g roast still capped). The build's verifier
caught two things the plan had carried faithfully: the pins asserted only
the record and the grams, so the 94 rows that move by confidence alone
pinned nothing (the table now carries each row's bucket and gate class, and
every rule's own-query answer is recorded from the snapshot so a dropped
rule fails by assertion, not by the unrecorded-fixture guard — 170 answers
added, each deep-equal to the snapshot); and "1 cup lightly salted
popcorn" counted at 193 g, the record's "1 cup, unpopped, yields" portion
— a portion whose description says yields, unpopped or makes now never
sizes a line unless the line itself says unpopped, dry or uncooked (14 g).
Replay on snapshot 13: calls 0; 198 rows moved on top of v20's 272 (the
plan's 197 + tapioca), 0 regressions among the 41 counted-to-counted
corrections (dried legumes to raw records, fresh Chinese noodles off the
fried record, pork tenderloin to the raw SR record, mixed berries off the
snack bar, coleslaw mix to cabbage, a banana leaf to 0 g): counted 12,956 →
13,099, check 512 → 375, no grams 110 → 104, no match 37, complete 760 →
839, partial 438 → 359; 0 recipes complete → partial; 0 person rows
touched. matcherVersion 21. Left for the live step, under the user's
standing approval of needed requests: 7 details + 3 searches the plan
named (+12 counted / +7 complete) — built dry first, as v17 was.

### The checkpoint 9 rulings and Run 052's fixes, each as the whole class (matcher v22)

Run 052 (both fleets on v20, 2026-10-01; no HIGH, six MED each) found that
v20 had fixed one SITE of each class rather than the class: the row writes
had left hash equality but the freshness stamp had not (a save, a person's
PUT that drops a deleted line's row, and a revert left a recipe fresh and
complete with a line that had no row); the offer's provenance had moved
one hop (the response's row at the position) instead of to the `raw` the
person sent; the compute re-run lived in one of two job loops; the
apply-to-all's acceptance had widened without narrowing its write (a
decided twin the layout carried onto the reached position was overwritten,
a sibling a save only shifted was skipped and the receipt could not say
why); `sameAmount` read the parser's first amount, so an edit of a line's
eaten "plus" part kept the old typed grams; and the key union let a pick
follow a line rewritten to another ingredient when the editor's parse gave
a generic key. v22 (2026-10-01) closes each at every site: migration 013
adds `recipe_nutrition.layout_seq` and a global `layout_counter`; a stamp
names the layout it was computed on and `nutritionIsFresh` — the one
predicate behind the body, the bulk stale scope and the job re-run —
requires the hash AND the layout to match, and a layout with a row-less
line never stamps fresh; the guarded upsert can no longer replace a decided
row on a raw difference, the compute's orphan row goes through
`replaceIngredientMatchIfUnchanged`, and the apply-to-all finds each target
by row identity (`sameMatchRow`, shared with the PUT) after the layout and
writes only an undecided row, its receipt now counting every offered line
as written, decided meanwhile, gone, moved or failed (the app parses and
shows all of it); the offer is built from the sent `raw` and the row that
reads it, and the app's `rowReading` is the one way it names the line a
person acted on; `computeUntilFresh` (three passes) serves both job loops;
the stored key is the key, the own-text key only when the stored key is
absent or shares its head noun (51 corpus lines parse differently, 15
without the head noun); `sameAmount` compares the weighed line's amounts
including the plus part; a decision an amount edit carried is shown with
its status, the new line's cache-only grams and `carried_from`, labelled in
the app; a deleted target counts as gone; the sequence survives a delete
and re-create. The user's checkpoint 9 rulings (decision log 2026-10-01)
land as three new discard kinds with their own hold codes, listed once
(`mediumHolds`) and used at every server and app site: `starter_discard`
(0799's two flour lines), `coating` (eleven dredging lines in ten fried
recipes — 0116, 0148, 0233, 0255, 0279, 0304, 0525, 0527, 1084, 1133 — with
a null `coatingFraction` hook for a future user-set share; a batter stays
counted; Chicken Kiev, which bakes, and the sautéed dredges await the
user's word), `partial_pour_away` (0129's braise and its sister Indoor
Pulled Chicken, the kept amount in the GET's `hold_note`; Enchiladas
Verdes awaits the user's word), and a rinsed dry cure at 0 g discarded
(0090; 0091, a rub only partly rinsed and a barbecue rub stay as they
were). Also: "1 sugar cube" off the beef-steak record onto granulated
sugar (no cube portion, so no grams); one density path per record for the
head-noun rule. Replay on snapshot 13: calls 0; 26 rows differ from v21,
every one a named hold, the cure, the sugar cube or the coffee row; eight recipes go from complete to review (seven fried ones — 1133,
0304, 0116, 0148, 0527, 0525, 0233 — and the starter 0799; Run 053
corrected this sentence's first wording), as the rulings intend: counted
13,077, check 396, no grams 105, no match 37, complete 831, partial 367.
The oracle: 0 violations in 1,000 plain and 1,000 gap seeds.
matcherVersion 22.

### Run 053's fixes: proxies replaced by signals, the backfill matched to the first write, the stamp from one read (matcher v23)

Run 053 (both fleets on v21+v22, 2026-10-01; no HIGH) found three kinds
of slip: a rule keyed on a proxy instead of the signal (R2's "fries" read
the oil's mass, ≥ 400 g, so Easier Fried Chicken at 381 g and Pan-Fried
Pork Chops escaped the hold while Francese, with less oil, was held;
`_asPrepared` read the literal word 'unpopped' for "measured unpopped"; the
grated-cheese density came from a table while ATK prints its own pair —
"1 ounce … grated (½ cup)" — the verbatim form on 32 corpus lines, 5 of
them Pecorino; the "twenty" first written here was Run 053's count of the
Pecorino-only pairs by a narrower regex); a backfill that did not
behave like the first real write (migration 013 stamped pre-012 recipes at
layout 0 while the first layout bumped the counter with nothing moved, so
an unedited recipe read stale after its first PUT or apply-to-all turn —
masked in the v22 deploy only by the matcher bump); and a stamp taken from
one read with the totals from another (a plain recompute built totals from
a stale `Recipe` object and stamped a newer compute's fresh hash). v23
(2026-10-01): a first layout that moves nothing writes its texts without
bumping the sequence; a plain recompute computes on the STORED recipe at
stamp time; R2 and the frying-oil rule read the same signal — a dredged
food fried by the directions, deep, shallow or pan — so the five recipes
newly recognised as fried (0042, 0114, 0149, 0198, 0288) hold their dredge
AND discard their oil (a smaller first part a step names — 0114's egg-wash
tablespoon — stays eaten; 0116's tablespoon and a sauté's four stay
counted; 400 g or "for frying" remains the fallback with no dredge); grated
Parmesan and Pecorino Romano weigh at the corpus's printed 0.24 g/mL — ATK
prints the ounce-to-cup pair for both; a bare "Romano" line is NOT covered
and still weighs at the generic cheese 0.47 with no flag (Runs 054 and 055
corrected this sentence twice: the first wording claimed Romano, the second
claimed a flagged stand-in) — 24 counted rows, a ¼ cup 24.8 → 14.2 g, and
shredded at its printed 0.36; a
"plus" part that prints its own weight uses it; a pick that kept an
eaten-in-part hold keeps it through an amount edit on the compute path as
on the PUT; the divided lines (1133's teaspoon of flour, Indoor Pulled
Chicken's teaspoon of liquid smoke, the shrimp's cornstarch toss) carry
their eaten part in the hold note and count it on a confirm, as the
existing plus-part design does for any held medium; `_asPrepared` applies
only to a line naming the prepared form; the apply-to-all's reach excludes
line-held targets by re-running the detector, its receipt files a decided
twin as decided and a changed ingredient as gone, and both job loops log
and count a recipe still stale after the three-pass cap; the app keeps an
apply-to-all receipt whose line a concurrent save removed, unanchored with
a note; the one-word-key test asserts over every rewrite key. Pins and
mutants for every mechanism the two pin-vacuity lenses named, including
the stamp-time re-check the v22 verifier had called equivalent. Replay on
snapshot 13: calls 0; 39 rows differ from v22 (24 grated cheese, 5 dredges,
5 frying oils, 3 divided parts, the shredded row, the plus part), two more
fried recipes to review (0042, 0114): counted 13,072, check 401, no grams
105, no match 37, complete 829, partial 369; 0 person rows touched. The
oracle: 0 violations in 1,000 plain and 1,000 gap seeds. matcherVersion
23. Left pending: the singular "portobello mushroom cap" needs one FDC
detail (the live step); 0042's eaten two tablespoons of oil (~28 g) and
0288's quarter cup of pan-fry oil are the user's call alongside the open
sautéed/baked question.

### Run 054's fixes: the oil signal on both sides, a real backfill, the detector memoised, linear regexes (matcher v24)

Run 054 (both fleets on v23, 2026-10-02; no HIGH) found five shapes: a
class fixed on one side of a conjunction (the frying-oil signal was wired
only for recipes that also had a dredge, so Crispy Tempeh's cup of oil,
heated to 375° and poured off, still counted 224 g and the Tostadas' ¾ cup
168 g; and v23 had narrowed `_fries` so "for deep frying" passed the oil
rule but no longer the dredge rule); a special case standing in for a
backfill (v23's first layout "staying at seq 0" re-opened the delete-and-
re-create ABA the global counter existed to close, and recorded an edited
line list under the stamp's sequence so a pick plus a revert read fresh
with a reverted line's food in the totals); the right computation in the
wrong place (the hold detector ran per matched row per GET line — the
matches GET on the busiest recipe 1.1 s, the library 4× slower, every PUT
and apply response too); derived state stored on a person's decision (a
pick's engine hold stayed frozen across a steps edit that stopped the
frying; a pick alone on a divided line counted its eaten part at once so
the hold it kept did nothing); and — from Sonnet's critic — an unbounded
regex over member-supplied text: the new divided-line reader and its v22
sibling backtracked quadratically on a period-free run of "1 1 1 …",
reachable by any member through the matches GET on an internet-facing
server (the 2 MB request cap would have meant hours). v24 (2026-10-02): the
oil rule reads the oil's OWN sentence — heated to a frying temperature, or
discarded / poured off — with or without a dredge, and "pour off all but 2
tablespoons" is a partial pour-away with the kept part counted (Crispy
Tempeh 224 → 28 g, Tostadas 168 → 0 g; the fritters' shallow oil stays
counted and is noted for the user); `_fries` matches frying verbs only
(not stir-fry, bacon, oven fries, a thermometer) and "for (deep) frying"
serves both rules; the no-bump branch is deleted and a Dart-side boot
backfill seeds a real layout row — counter sequence plus the recipe's
current line texts — for every stamped recipe (1,198 on the snapshot; no
stamp at 0, none off its layout; idempotent), so every layout bumps and a
stamp always names a layout whose texts are known; a plain recompute keeps
the stored hash only while the stored recipe still hashes to it; a target
deleted during the apply's await files as gone; one hold-state memo per
request plus a process-wide cache keyed by content hash (the busiest GET
0.8 s → 30 ms warm, ~0.4 s cold; the library 64 s → 12 s, under v22's 16 s;
pinned by detector-run and decode counts, never a clock); every regex over
step or line text made linear — the amount run bounded, the whitespace
collapsed once at the parser's and the gram resolver's entry, scanned
sentences capped at 1,000 characters, 186 regex sites audited on twelve
hostile shapes (worst 0.36 ms; the old `_parsedUnit` lead was 4.1 s) and
the parser's own normalisation pinned by hand; a decided row's hold is
re-derived on every compute through the guarded write; a pick on a divided
line counts the eaten part and resolves the hold ("eaten part counted after
your pick"), a pick on a non-divided held line keeps the hold with no
grams; the app shows a hold's reason in every bucket; `_asPrepared` reads
the measured head (popped popcorn with a "kernels" paren gets the popped
portion); the plus-part restatement only for the plus part's own food; a
divided line's eaten part read only from a step naming its ingredient; the
app's Dismiss no longer drops a pending offer, the queue advances past a
gone line, an anchored receipt on a different twin is shown. Replay on
snapshot 13: calls 0; exactly two rows differ from v23 (the two oils);
buckets unchanged — counted 13,072, check 401, no grams 105, no match 37,
complete 829, partial 369; 0 person rows touched. The oracle: 0 violations
in 1,000 plain and 1,000 gap seeds. matcherVersion 24. Left to the user:
the fritters' shallow oil (0674/0675), whether "air-fry" is a frying verb,
and the plus-part cheese sentence in API.md (true for a typed line; no
corpus line reaches it — kept).

### Run 055's fixes as three design rules (matcher v25)

Run 055 (both fleets on v24, 2026-10-02; no HIGH) found the SAME classes
as Run 054 in new places — a fix applied to one field of a class (the hold
on a decided row re-derived, its grams not; a pick rule covering three
holds of four), "linear" proven per regex while the detectors stayed
quadratic per mention (a salt line on forty legal steps: 39 s), and an oil
rule keyed on the noun "oil" rather than on the line that owns the
sentence (a typed "brush with the oil and bake at 375 degrees" zeroed a
quarter cup of olive oil; a second oil line was zeroed and given the kept
part). So v25 (2026-10-02) was briefed as three design rules, each one
mechanism proven at every site by diff. RULE A — a decided row stores only
the decision: `derivedFor(recipe, line, decision)` returns every derived
field (hold, grams unless typed, gram source, note) from the CURRENT
recipe, and the compute, the PUT and the GET all read it; the compute
writes only those fields through the guarded write and never a status, a
food or typed grams; a confirm means "this food, the engine's current
weight" and counts a known eaten part on both paths (0129's liquid smoke
4.73 g, no longer undone by the next compute); a pick resolves a hold by
one rule per kind (divided → the eaten part counted and said; wholly
poured away → 0 g and said; other eaten-in-part → the hold kept, no
grams). RULE B — a sentence belongs to a line, not a noun: `_oilOwnersOf`
binds a frying, discard or pour-off sentence to the oil line whose own
amount or distinguishing kind word it names, the oil noun phrase following
directly (only "of", "the" and the recipe's own kind words between — the
verifier's "2 tablespoons butter to the oil" and "lime juice into the oil"
bind nothing; the owner closed that last gap by hand and the window mutant
dies); frying heat is the oil heated to a temperature, never an oven's
"bake/roast at"; with two or more quarter-cup candidates and no binding
word each is HELD under a new `ambiguous_medium` reason with the sentence
as its note, never zeroed; `_fryVerb` excludes the unhyphened and negated
forms (stir fry, air fry, dry fry, don't fry). RULE C — a detector costs
O(text) per recipe, measured end to end: a per-recipe `_StepIndex` (steps
windowed, sentences split once, sentence ends indexed for binary search,
each pattern's matches located once, per-line mentions memoised) that every
detector reads; the per-mention rescans in `_sentenceAt`'s five callers,
`_drainedMention`'s later-steps scan, the oil lines' step re-split and
`normalizeItem`'s digit-run rescan are gone; the 1,000-character cap is a
scan window that logs the step it truncates instead of silently disabling
a rule; the matches GET memoises its reach per key and its text reads per
raw (160 identical legal lines: 16 s → 0.2 s). Measured: a salt line on
forty legal 10,000-character steps 38 s → 44 ms; a 10,000-character
period-free step 3 s → 1 ms; the library's matches GETs 13.6 s → 11.8 s.
Also: `_asPrepared` parses the measured head (a leading count-paren
dropped, a qualifying paren read as a modifier); a plus part's cheese form
read from its own words; one shared whitespace normaliser for the parser
and the editor's hand-curated check (a stored quantity-less line with a
double space no longer reads as hand-edited); the dead Skipped-arm label
deleted; the apply strip's "Not now" wired; corpus-free pins un-gated so
CI runs them; the time pins carry count pins beside them. Replay on
snapshot 13: calls 0; one row differs from v24 — a person's pick of
"Bread, Italian" for ten slices of country bread had its grams frozen at
null before the rustic-bread rule existed and now reads 500 g under RULE A
(the decision itself untouched); counted 13,073, check 401, no grams 104,
no match 37, complete 830, partial 368. The oracle: 0 violations in 1,000
plain and 1,000 gap seeds. matcherVersion 25. Left to the user: whether
"shimmering/smoking" counts as frying heat (it would zero 81 counted
quarter-cup oil lines — not adopted), the fritters' shallow oil, air-fry.

### Run 056's fixes: the three rules at the granularity the review measured (matcher v26)

Run 056 (both fleets on v25, 2026-10-02; no HIGH) found each v25 design
rule met at the granularity its proof had measured rather than the one the
invariant stated. RULE C's step index made every sentence O(1) to reach,
but the per-line loops around it still walked the recipe's text — a legal
400-line dredge recipe cost about two minutes per member matches GET
(`_eatenOutsideMedium` parsing every written mention per line and
rescanning the lines for each), 400 salt lines about 25 s (`_ownMentionsOf`
iterating every mention per line), and `layoutOf` decoded the whole layout
JSON on every row write. RULE A's decided branch wrote the re-derived
fields at the row's PRE-layout position, so a decided row that a save moved
kept stale grams while the recipe was stamped fresh (Sonnet alone), and its
failure arms each stored a different partial state: a confirm during an FDC
outage stored with null grams and no hold, the compute throwing for a row
whose detail it fetched but never used, the PUT no longer answering the 422
API.md promised, a decided food FDC could no longer resolve clearing a
confirm's grams (0857's flour, 248 g from its own written weight). RULE B
had been scoped to the one noun it was written for: shortening or lard
heated to a frying temperature no longer counted as frying fat (a v25
regression, Opus alone), an amount two oil lines shared bound both (both
zeroed, never held), a frying oil written by weight was never a candidate,
and the oven exclusion read only the words between the noun and the
temperature. So v26 (2026-10-02) restates each rule where Run 056 measured
it. RULE A: the decided and orphan branches derive and write at the row's
CURRENT position (S1's 0129 confirm: 4.73 g stale → 14.2 g `portion`,
fresh); a derivation that cannot run — the provider failing, or a food in
no cache that FDC answers null for, through the existing superseded-food
path — is ONE outcome on every path: the decision is stored, the derived
fields stay as the last successful derivation left them, the recipe is left
stale so the next sweep retries, the compute never throws for one row (the
totals' own fetch given the same outcome), and a food is read only where a
path needs it (typed grams or a skip on the line's own amount read none);
an amount-less line derives no weight on a pick, a resolved medium is
always `discarded`, and "eaten part counted" is said only when a part was
(0318's "Kosher salt": "poured away after your pick"). RULE B: one `_Fat`
mechanism per frying head (oil, shortening, lard), each signal reading its
own noun; a binding key two candidates share binds neither and lines are
counted by position (two identical raws are two candidates); a candidate is
any line the mass rule could zero — a quarter cup by volume or 400 g by
written weight (0690's 24 ounces: the aioli held); frying heat is positive
evidence from the whole sentence (the fat as the object of heat/bring/warm
… to/until/registers a 300–399 °F or 160–200 °C temperature in every
spelling — "350°F", "350 °F", "350F", "180°C") with any oven, bake, roast,
broil, grill, air-fryer, smoker, slow-cooker, pizza-stone, toaster or
convection word anywhere in the sentence ruling it out; every corpus oil,
dredge and fries row byte-identical, the 67 corpus oil-with-temperature
sentences still frying. RULE C at the loop level: mentions grouped by
owning line once per recipe (`_sharesOf`/`_firstOwn`), written parts
parsed once per head and the amount-writers map built once
(`_amountWritersOf`), per-head memos for the dredge, cure, brine and
dissolve readers (the last a site the digests had not named: >120 s →
144 ms), the oil owners' unbound sentences attached once and the kept oil
memoised per line, `layoutSeqOf` reading only the sequence on a row write,
`laterOf` keyed by step and offset (0572's soda keeps `cookingWater` with a
prepended step), the window notice logged once per recipe and content;
every memo family counted through `stepIndexCounts` and pinned by COUNT at
the editor's caps (400 lines × 120 steps × 10,000 characters) on the
compute, the matches GET, the PUT and the apply-to-all, so deleting any of
the eighteen steps-only memos fails a count, not a clock; every clock-only
pin in the suite now carries a count pin with a generous backstop (the v24
pins had timed an already-warm index). Measured at the caps, before →
after: a salt-written recipe's compute 21.5 s → 0.69 s and its member GET
24.5 s → 0.51 s; the dredge-written compute 114 s → 0.65 s; the dissolve
shape 274 s → 0.62 s; every path at or under about one second. The
verifier's first pass then found RULE B's new whole-sentence heat check
itself running unfiltered on every sentence naming the fat — a cap-sized
frying recipe's member GET 0.74 s → 1.2 s, a regression — closed by a
cheap prefilter (a sentence with no digit run that could be a temperature
is never frying heat) with its own count pin; what remains on that shape
is 30–75 ms over v25 on paths of 0.1–0.8 s, the constant cost of building
the loop-level index for a recipe whose loops never fired before, accepted
against the 159 s → 0.6 s it bounds. Also: a plus part's cheese
form read after its comma ("plus 2 cups, shredded": 128 → 184 g); a popcorn
paren of one word qualifies the head and a longer one is a note ("(unpopped
kernels discarded)" no longer restores the kernel cup); one
`normalizeLineFields` normaliser over the whole stored line for the editor's
hand-curated check (a quantity's double space no longer locks a line; a
pre-v24 paren the old parser read differently still does, by design — the
re-parse button); the app's hold copy per kind says which decisions finish
it and that a pick keeps an eaten-in-part hold, and the ambiguous hold
asks its own question ("Two lines could be the frying medium — which?").
Replay on snapshot 13: calls 0; zero rows differ from v25; counted 13,073,
check 401, no grams 104, no match 37, complete 830, partial 368; every
hold note identical. The oracle: 0 violations in 1,000 plain and 1,000 gap
seeds. matcherVersion 26. Noted for the user: a superseded food that no
cache holds leaves its recipe stale for good, one retry request per sweep;
a pick during an outage records the person's food library-wide, as a
successful pick does.

### Run 057's fixes: the state as a row fact, the evidence as one reading, the index paid by its amortiser (matcher v27)

Run 057 (both fleets on v26, 2026-10-02; no HIGH) found the opposite of
Run 056's lesson: v26 had stated RULE A's "derivation unavailable" outcome
for ONE function, and five other writers and readers of the same state
kept their old semantics — an in-flight compute re-stamped a recipe fresh
over a PUT's underived decision (the sweep never retried it); the old
`computeUntilFresh` loop, built for a concurrent save, re-ran such a
recipe three passes per sweep (six requests per row, a StateError masking
the provider's reason, the bad-key stop lost); the apply-to-all wrote its
earlier targets then threw (old totals under a fresh stamp); FDC's 404
null arm left `recomputeTotals`' flag false (a typed decision dropped
under a fresh stamp); the serving-basis route's catch could no longer fire
(a divisor change dropped a food and turned a fresh stamp stale). RULE B
had regressed v25 (an exclusion word anywhere in the sentence with no
boundary — "drain on a baking sheet" — vetoed a real fry; the closed lead
list missed "to between 350 and 375"); candidacy read parsed amounts
while the mass rule read resolved grams; every medium rule was gated on
volume, so "8 ounces vegetable oil" bypassed them all. RULE C still had
one quadratic site (`_dissolvedWithBrineSalt`, 100 s per member GET at the
caps) and the new whole-recipe naming inversion was paid by every ONE-LINE
reader (a cold GET over a 20-recipe reach 2 s → 14 s). So v27 (2026-10-02)
restates each rule as the fact every reader reads. RULE A: "derived" is a
fact on the row — migration 014 adds `derived_seq` (the layout sequence
and ingredients hash the row's derived fields were computed for), a
one-shot boot backfill marks the decided rows of every current recipe and
leaves a stale one's null, and ONE SQL predicate (`underivedSql`) behind
`nutritionIsFresh`, the stale scope and the recipe page says a recipe is
fresh only when its stamp is current AND no decided row is underived — the
compute's own snapshot (`derivedAll`) is deleted, so no writer can stamp
over a row it never saw. A food FDC answers 404 for that no cache holds
becomes a `food_gone` hold the person revisits in the queue (a pick or
skip finishes it; the row counts as derived), never a forever-stale
recipe; an outage leaves the row underived and costs the sweep ONE request
per underived row per pass (0148's thirteen decided rows: 13 requests in
one pass, not 42 in three), and both job loops stop on a provider-class
failure with FDC's own message. `recomputeTotals` is cache-only and
synchronous (its provider parameter deleted; the compute prefetches the
one nutrient sibling the totals read); migration 015 stores the unrounded
per-recipe totals, so the serving-basis route (`rebaseNutrition`) is pure
arithmetic over them — it reads and touches no row, no food, no
`derived_seq` and no stamp (the closer's fix after the verifier re-ran
Opus's critic: the first cut still recomputed from rows and caches) — and
its dead catch is gone; an un-skip whose derivation cannot run keeps no
grams of an edited-away amount; the apply-to-all weighs each target inside
the same outcome (a target it
cannot weigh is not written and is counted under a new receipt key,
`unavailable`, never `failed`); the unavailable arm keeps line holds only;
the test fixture's `UnrecordedAnswer` is an Error again, not a provider
exception, so a missing fixture fails loudly (its first run exposed one
test that had passed only because a fixture miss read as an outage). The
pairing oracle gained an outage mode (ORACLE_OUTAGE=1) and an UNDERIVED
invariant on every save. RULE B: one heat reading in `_Fat.heatsToFry` —
the lead is read in the 72 characters before the temperature's digits; the
sentence fries when "<fat> temperature" precedes it, or the fat's noun
precedes a lead (to, until, reaches, registers, reads, is, at, a
temperature of, between … and, NNN–NNN, NNN to NNN, each with
about/around/approximately/roughly) opened by a heat or fry verb in the
lead's own verb phrase; an appliance or method word excludes only the
temperature it GOVERNS (its own clause, bounded by ; , — ( ) or a heat
verb — "baking sheet/powder/soda/dish/pan", "roasted peppers" never
exclude); every spelling reads (° º ˚, deg, degree, F, Fahrenheit, C,
Celsius 160–200); pinned on the 67 corpus sentences AND every typed
positive Run 057 listed, every v26 negative still false. One quantity reading,
`_mediumMl` (the written volume, else the written or paren weight at the
ingredient's table density; a fat without an entry at oil's 0.92), under
both the candidacy `_couldZero(line)` (a "for (pan-/deep-)frying" label
with any amount, or a quarter cup) and the mass rule `_massZeroes` (the
label, or 400 g of the line's own amount read with no food) — the owner
accepted the two predicates over one reading in place of the brief's
single function, since every line the mass rule zeroes is a candidate by
containment (the next review is asked to pin that) — and the same
`_mediumMl` makes every medium threshold both-family (the dredge's quarter
cup, the brine salt's 44 mL, the four-cup soak): "8 ounces vegetable oil"
fries like "1 cup", "20 ounces flour" is held like "4 cups", "1 (48-ounce)
bottle vegetable oil" is zeroed and never held. A method word followed by
a vessel noun (sheet, dish, pan, rack, tray) never governs a temperature
and the words-after scan stops at a heat verb — "heat 1 inch of oil in a
roasting pan to 350 degrees" fries; a "broiler pan" or "grill pan" still
does not (pre-existing, left for the next round). Grams: a popcorn paren or comma
part is a qualifier when every word is in the qualifier vocabulary
(unpopped, popped, air-popped, kernel(s), raw, dry, plain, yellow, white)
— "(unpopped kernels)" keeps the kernel cup, "(unpopped kernels
discarded)" is a note. RULE C: the naming inversion (`namingAll`) is built
only when a SECOND distinct word head is asked, so a one-line reader — the
reach's `heldMediumLine`, a single-line PUT — pays O(its head) (the
20-recipe reach GET 7.1 s → 1.8 s, its apply-to-all 13.9 s → 3.0 s); one
inverted name → sentence index (`_occurrences`, Aho–Corasick, O(text +
patterns + pairs)) serves `_dissolvedWithBrineSalt` (the pair loop gone:
the 200 × 199 shape 70 s → 0.39 s) and the plus-part scan (a shape with
real plus parts 1.6 s → 0.85 s); every record-keyed memo carries a "Key:"
comment enumerating its coordinates, and a `memoOffForTest` oracle plus a
drop-one-coordinate mutant per memo pins them. The first verifier measured
the oil-shape PUTs 25 % slower than v26; the closer isolated it to RULE B's
new heat reading (7.3 µs per frying sentence against 3.4 at v26 — the
heat-verb alternation, the lead regex and the clause read to the sentence
end) and to the plus index built eagerly for a one-line read with the
recipe hashed twice per PUT; with a word scan and a set lookup, one
lookbehind at the digits, the clause read only up to the temperature, the
plus index built on the second distinct line and the hash reused only
while the stored recipe still equals the one hashed (a racing-save pin
caught the first version of that reuse), every oil-shape path now runs
below v26 (the PUT pick 387 → 257 ms, the shortening compute 626 → 518). Replay on snapshot 13:
calls 0; zero rows differ from v26; counted 13,073, check 401, no grams
104, no match 37, complete 830, partial 368; every hold note identical.
The oracle: 0 violations in 1,000 plain seeds and 300 outage seeds; the
gap mode found ONE pre-existing violation (seed 41487: a copied Pecorino
line inserted, a salt line deleted and a cross-group move in one save —
fails identically on v26; a pairing defect briefed separately, not a v27
regression). matcherVersion 27.

### Run 058's fixes: every input named, one action table, boundaries at marks, readers that declare their reach (matcher v28)

Run 058 (both fleets on v27, 2026-10-02; no HIGH) found each v27 rule
right but stopped one entity short. The `food_gone` shortcut was keyed on
the recipe's inputs while the derivation also read the caches, so once a
cache held the food again the GET showed the line counted, the row and
totals said gone, and the recipe read fresh with nothing to heal it. A
persistent per-food provider error on one decided row stopped every stale
sweep at that recipe (a liveness regression: recipes after it were never
computed). The new hold had reached the buckets but not the action table —
the sheet and queue still offered Confirm, the queue's `finishes` SQL
promised it, and a confirm wrote the gone food as the ingredient's
library-wide decision. The 404-versus-outage distinction covered a row's
own food but not its nutrient sibling (a retired sibling never converged),
and an engine-line throw after a decided row was derived left the recipe
fresh with totals computed before that derivation. RULE B's clause began
at the lead's own heat verb, which cut the governing appliance out ("heat
grill until lid thermometer registers 350" fried), and the heat reading
rescanned the clause once per temperature (quadratic per sentence, hidden
behind a count pin that counted checks, not their size). The second-head
gate did not cover an oil line in a dredge-fry recipe, and v27's typed-row
read doubled the whole-search-cache scan per typed row on the member GET.
Both fleets also characterised the pre-existing gap-oracle violation (seed
41487): the pairing's 10,000-expansion budget exhausted by eleven
identical-text rows in a three-edit save, a decision moved between twins
and never lost. So v28 (2026-10-02) states each rule with its consumers
enumerated by grep before any code. RULE A: "derived for" names every
input — a `food_gone` or `food_unavailable` row is re-read from the caches
on every compute (no request) and re-derived the moment a cache holds its
food; the nutrient sibling is resolved where the food is, on every path
(a 404'd sibling is the row's own `food_gone`, an outage leaves it
underived, and the totals never meet a missing sibling — a plain
recompute resolves before it reads); a provider failure has two classes
set by the provider (`FailureScope.global` — a rejected key, a spent
budget, a failed search — stops the job with its reason; `.food` — a
detail failing for one id — is that row's state: underived with a
`retry_count`, held `food_unavailable` for the person after three
computes, and the sweep moves on, so no recipe ever blocks the ones after
it; three consecutive food failures on distinct ids within one pass
escalate to global, so a detail-wide outage stops the pass with the
provider's reason instead of counting against every row — per pass only,
so a library-wide outage can still hold a recipe's one or two uncached
decisions after three sweeps, noted); a pass that throws clears the keys it marked before rethrowing;
`markDerivedIfUnchanged` is one guarded single-row UPDATE. One action
table (`holdActions` in salt_shared) says for every hold family which
decisions finish it, which buttons are offered, which the PUT accepts and
whether the decision may go library-wide — read by the server's PUT gates
(a confirm on `food_gone` is a 422 before any request and never reaches
`putDecision`), by the queue's `finishes` SQL, and by the app's sheet,
queue and copy, with a parity pin on each side; the nutrition body names
why it is stale (`stale_reason`: inputs changed, or a decision waiting on
USDA). Migration 016 adds `retry_count` and an `fdc_search_cache_foods`
index kept by triggers, so the search-cache lookup is indexed (a member
GET of 400 typed rows 3.3 s → under 0.1 s); the matches GET resolves each
row's food once; one FDC request per food per pass (100 napa rows with a
missing sibling: 401 requests and 3.2 s → 1 request and 50 ms). RULE B: a
frying temperature's clause starts at the last clause mark, never at a
heat verb (a mark followed directly by a heat participle opens no clause —
"in the smoker, holding it at 300" stays an oven's heat); the governing
words are located once per sentence and each temperature answered by
forward pointers, with a `heatClauseChars` pin bounding the characters
scanned (the quadratic shapes 2.5 s → 0.37 s, below v26); vessel compounds
(Dutch and French ovens, oven-safe and -proof in every spelling, broiler
and grill pans and -safe vessels) never exclude; the fry range stays
300–399 °F — exactly six corpus sentences name a fat at 400–450 °F, and
widening would have held 0672's eaten quarter cup of coconut oil as an
ambiguous medium; a food-free density table serves the threshold readers
only (bread crumbs 0.45, starch 0.54, shortening and lard 0.87 from the
FDC records — putting the keys in the shared table would have moved ten
replay rows). RULE C: the naming inversion is gated by
measured cost, not by a proxy — the first cut declared a one-line reader
and built the inversion on a second declared line, which the verifier
found still built 22 inversions on the oil-reach GET (the viewed recipe
shares ten keys with each reached recipe); the closer deleted the proxy
and `_naming` now scans one head at a time, counting the step characters
each scan reads (`namingPaid`), and builds the inversion only when the
scans already paid would have paid for it (30 × the step characters, the
constants measured), so the reach builds none, the GET exactly two (its
own recipe and the reach's copy of it), the apply-to-all none (the
21-recipe oil reach GET 6.3 s → 1.5 s, its apply-to-all 6.4 s → 1.5 s; the
oil GET stays 4–6 % over a garlic-line GET because each reached recipe is
asked about eight foods, accepted); `_wordsOf` confirms each word where
it stands instead of rescanning the sentence per head; the pairing lays out a run of identical-text rows in its
own order and swaps twins back onto their own lines afterwards, so seed
41487's save pairs in 4,916 expansions (39,789 before) and the gap oracle
runs 1,000 seeds clean — twins separated by other lines can still exhaust
the budget (once in 2,000 twin-heavy saves; grouping them would change the
cost model and is left for a decision). Replay on snapshot 13: calls 0;
zero rows differ from v27; counted 13,073, check 401, no grams 104, no
match 37, complete 830, partial 368. The oracle: 0 violations in 1,000
plain, 1,000 gap and 300 outage seeds. matcherVersion 28.

### Run 059's fixes: a hold re-read before it is enforced, every line kind, the job's units, a boundary moved not removed, a cost that is the cost (matcher v29)

Run 059 (both fleets on v28, 2026-10-03; no HIGH) found each v28 rule
right where it was applied and wrong one step over. The `food_unavailable`
shortcut read only `fdc_food_cache` and the PUT's gate read the stored
hold, while the GET derived from every cache — so a recovered row stayed
held forever with the GET showing it counted and a confirm refused with a
false "USDA has no record". The engine's own lines had no food-failure
handling: a failure on an undecided line threw the pass, dropped the
recipe's counts and was never held, so a detail outage never escalated
(the sweep ground all 1,198 recipes at four requests and 18 s each and
ended "done", where v27 stopped after one), while three broken records in
one recipe tripped the per-pass escalation into a permanent stop. RULE B's
mark-only clause had removed the heat-verb boundary without replacing it,
so an earlier oven in the same clause governed the fat's own temperature
("Heat the oven to 200 degrees and heat the oil to 350" zeroed nothing).
The amortiser charged characters while the regex charged pattern-dependent
work (a crafted step 10–20× under-counted); consecutive twins with one
edit still exhausted the pairing budget; a PUT made one sequential request
per uncached food with no stop on a global failure. The critics added a
pass that dies mid-await keeping its marks (fresh with uncounted totals)
and `{skipped: true, grams}` carrying typed grams past the no-record gate.
So v29 (2026-10-03) states each rule with its unit and its consumers. RULE
A: a hold is re-read before it is enforced — one cache-only derivation
(`cacheOnly` → `derivedFor` → `knownFood`, the detail cache then the search
index) is the only reader for the compute's shortcut, the PUT's gate and
the GET, and a cache write that regains a food re-opens the rows held on
it (`unholdOn`, migration 017's partial index) so the next sweep re-reads
them; an engine line whose candidate, prior decision or sibling fails gets
its own row, counted by the same closure as a decided row and held
`food_unavailable` after three failures while the pass goes on; the
escalation is counted across the job (`_JobWatch`: consecutive food
failures on distinct ids, reset by any answered detail; a food that
failed once is not asked again in that job) under three rulings the two
close rounds settled — every food failure is always counted on its row,
including the one that tips an outage; the run must span two recipes, so
three broken records in one recipe are that recipe's held rows and never
an outage; and within one pass, three consecutive distinct failures
suspend that recipe's remaining details (its failed rows counted, the
rest left underived) so a detail outage costs at most four requests per
sweep whatever the recipe size, where v28 spent one per recipe over the
whole library; a pass is visible as in progress until its totals are
written (migration 017's `computing`, an owned count each writer takes
before its first row write and releases with its own totals in one
transaction — a pass that throws or dies leaves the recipe stale, the
boot clears the stamp of every recipe still counted as computing and the
banner says a compute is in progress or was interrupted); the
PUT gate reads every verb in the body (`skipped` with anything else is a
422 "one decision per request"); a PUT resolves only its own line's food
and sibling (at most two requests, stopping on the first global failure —
400 underived rows: one request and 54 ms where v28 made four hundred);
the held write keeps its retry count and only an `all`-scope sweep re-asks
a held row, once; every hold family's membership lives on its `holdActions`
entry (`HoldKind`) and the hand-copied lists are gone. RULE B: a
temperature's clause starts at the latest of a clause mark, an "and/then"
opener or the fat's own mention, and never at the evidence verb (a mark
or opener whose phrase opens on a non-fry heat verb — "holding it", "heat
it" — is no cut, which keeps "in the smoker, holding it at 300" the
smoker's); the participle exception is deleted (the fat's mention inside
the participle phrase is the boundary that keeps the oven out); the
hyphenated vessels never exclude; the heat reading is built once per
sentence per index (`_HeatReading`, every pass lazy and counted — the
heat shapes 35–45 % below v27); the failure classification is a table
pinned arm by arm (a malformed, empty or wrong-shaped 200 on a detail is a
food failure — the detail is parsed defensively, where v28 threw a type
error — a search failure of any kind global, a connect error or timeout
global — argued: nothing in it names a food). RULE C: the per-head scan is an
exact-cost lookup over a per-step word index (`_Words`, every word's start
and key in one pass), the head confirmed at the word, `namingPaid`
counting words visited and the inversion built at twelve lookups per word
measured on those units — the `\b<lead>` regex pass, whose cost per
character varied seventy-fold with the text, is gone (the crafted-step
read 430 → 78 ms); the first verifier measured the PUT paths 8–15 % over
v28 and the closer profiled it to a one-time JIT compile on the first
call plus a twin table copied when there were no twins and the word
index built in growable lists — both fixed, and under the production AOT
build every PUT path is at v28 within noise, the cold oil reach 2 % over
(the exact-cost index, stated); the pairing treats a run of identical-text rows as one
item (the search branches per run, the bound reads a run's untaken rows
as one block, a surplus settled once by a DP — fewest decisions lost, then
fewest rows moved, ties from the end): 400 twins with one edit 10,000 →
~800 expansions and 1–4 s → 20–44 ms. Replay on snapshot 13: calls 0;
zero rows differ from v28; counted 13,073, check 401, no grams 104, no
match 37, complete 830, partial 368. The oracle: 0 violations in 1,000
plain, 1,000 gap, 300 outage and 2,000 twin-fuzz seeds. The owner's
gate on the final tree: every named symbol grepped present or deleted,
the server suite with the corpus (1,954) and the nutrition suite without
it (717) green, and two mutants anchored on code and restored from a
snapshot copy — the two-recipe span rule weakened to one recipe
(`_run.values.toSet().length > 0`) fails the O11 one-recipe pin, and the
freshness predicate without its `computing > 0` term fails the
interrupted-pass pin. matcherVersion 29.
Deferred, stated: twins separated by other lines (one budget hit in 30,000
two-text saves); the queue's SQL reads the stored row and catches up at
the next stale sweep; a held engine row (no food on it) is re-asked only
by an `all` sweep; a skip carried by an amount edit can be held
`food_unavailable` on its old text.

### The accuracy track, part 1: the rulings already made, built (matcher v30)

After Run 060 (the exit review of the engine loop, 2026-10-03) the owner
chose to stop the engine loop at v29 and spend the effort on accuracy, which
is gated on the open rulings. While mapping those rulings it turned out
that nothing from checkpoint 9's Q6 and Q7 had ever shipped: v22 built the
four hold rulings only, and the bone-in group that was marked "build now"
was never built. So v30 (2026-10-03) builds exactly what was already ruled
and needed no new answer. Q7's bone-in parts: 18 rank-as items read their
raw record under the meats-and-birds ruling (gross weight, labelled
approximate, unless the record publishes a refuse yield — the Boston butt
reads USDA's 0.76), three of them flagged approximations (flap meat on top
sirloin; turkey drumsticks-and-thighs and leg quarters on the thigh record),
and "rib slabs" buys bone; the fresh ham waits for its detail in the live
step. Q6's two chile figures printed BY WEIGHT in the corpus — a dried New
Mexican and a dried guajillo pod at 7.1 g (ATK's "3 medium New Mexican pods
(about ¾ ounce)", "4 large dried guajillo chiles … (about 1 ounce)") —
join the piece table keyed on the dried item, flagged approximate with the
source in the label (a new `_approximatePieces` label map; `_pieceLookup`
returns its key); the volume-printed and proposed figures wait for the
rulings the owner gave the same evening (part 2). The live step's rules are
built dry: every entry commented with the detail it waits on, and an
enable experiment asked exactly ten details and no search (the plan's pear
item is already landed, its weight-in-text item is a mechanism and is
dropped, item 10 is a detail not a search). Replay on snapshot 13: calls 0;
24 rows differ from v29 — the 20 bone-in rows check → counted and the 4
chile rows no grams → counted, every other row byte-identical; counted
13,073 → 13,097, check 401 → 381, no grams 104 → 100; complete 830 → 847
(fish-and-chips, which the planner counted, is now blocked by the v22
coating hold on its flour). Six older pins the ruling superseded moved to
other real corpus lines (0249, 0002, 0651) or were strengthened from "no
grams" to the printed 7.1 g pod. The owner's gate: every fixture addition
byte-equal to a snapshot cache row, the re-pins read and judged, two
code-anchored mutants (the guajillo figure 7.1 → 7.0; the rib-slab refuse
term removed) killed and restored, the fresh-copy replay identical to the
fixer's, the server suite with the corpus 1,958 green. matcherVersion 30.

### The accuracy track, part 2: the checkpoint 10 rulings, built (matcher v31)

The owner's rulings of 2026-10-03 (the decision log's entry of that date)
are built as v31 (2026-10-03, afternoon), from the planners' tables and four read-only
preparation reports (the lasagna figures sourced from manufacturers' box
specifications, the chorizo record check, the forty misc mappings read one
by one, the dredge-reach survey). Q6: every approved piece figure, each
flagged approximate with its source in the basis text — ginger 8 g an inch
of a "(N-inch) piece", a dried chipotle 4.6 g, orange and lemon zest strips
0.8 g an inch, the six whole spices per piece (reference figures), star
anise lines on the anise-seed record, a no-boil lasagna sheet 17 g
(Barilla's 9 oz box of at least 15 sheets; the label's 3 sheets = 51 g
agrees), a curly-edged noodle 25 g (Ronzoni's label), a lemongrass stalk
10 g, a bunch of scallions 7 × FDC's 15 g; dried jujubes and the per-inch
mild chile stay at no grams as ruled. Q7: the eight small groups exactly as
the planner wrote them (72 rank-as items, 49 flagged approximations),
anchovy paste at 6.7 g a teaspoon, the misc group's 35 kept mappings with
the prep report's modifications (a Cubanelle pepper 99 g by ATK's "3 to 4
ounces each", instant espresso at its siblings' 0.43 density) and its two
companions (the one-word fat head in the frying-medium test, so the
confit's 1,230 g of duck fat is discarded; a cornichon 3.2 g by ATK's "6
cornichons (about 2 tablespoons)"); Spanish chorizo stays on the cached
record until the live step fetches the real dry-cured one (the cached
2706179 is fresh Mexican chorizo); the light sour cream and brioche
rules are built dry for the live step. The dredge rule's one unambiguous
gap: the bread a held breading processes into its crumbs is held with its
flour (0114, 0233); the sautéed and baked classes wait for the owner's
ruling on the survey. The held-media rulings, each the narrowest reading
pinned on its recipe with the corpus's non-trips listed: 0488's poach
("remove ¼ cup liquid … discard the remaining liquid") holds its broth,
oil, onion, garlic and cumin as a part-kept medium; 0042's two tablespoons
of dressing oil count (the fat's amounts written after its last discard);
0288's pan-fry oil and the two fritters' oil are held ambiguous (a frying
verb with no heat, discard or pour-off sentence and no line of the fat
zeroed by the mass rule — the guard that keeps 0672's eaten coconut oil
counted). A flagged piece figure under 10 g prints one decimal ("3.2 g
each", "4.6 g each", "7.1 g each"). Replay on snapshot 13: calls 0; 191
rows differ from v30, every one traced to a ruling, none a person's row;
counted 13,097 → 13,260, check 381 → 269, no grams 100 → 54, no match 37 →
32; complete 847 → 939 (95 recipes complete, 3 go to review by the rulings:
0488 and the two fritter recipes). Twenty-two existing pins the rulings
superseded moved to the ruled value or to another real corpus line; the
contract goldens changed on their black-vinegar line only (now balsamic
with its portions). Four close rounds in all: the verifier's two unpinned
guards (the per-inch record gate; where the eaten parts start after the
pour-away step) pinned on corpus lines with stated-exception edits. The
owner's gate: every one of the 73 fixture additions byte-equal to a snapshot
cache row, the re-pins read and judged, two code-anchored mutants (the
lasagna figure 17 → 16; the fat companion dropped) killed and restored, the
fresh-copy replay identical to the verifier's, the server suite with the
corpus and the shared suite green. The live step after v31: 12 food details
and one search (`scratchpad/fix31/live_step.md` archived under
`.claude/diag/2026-10-01/fix31/`). matcherVersion 31.

### The accuracy track, part 3: the live step, spent and enabled (matcher v32)

The live step was spent on 2026-10-03 by the owner on a scratch copy of
snapshot 13 with the deployment's key attached read-only for the run and
deleted after: 14 requests, every one named in advance by the dry rules
v30 and v31 had built — 12 food details (the chicken leg quarters, the
oil-packed tuna, tamarinds, the whole egg, cranberry juice cocktail,
dehydrated onions, the fresh ham, khorasan wheat, canned pimento, the
portobello, light sour cream, brioche) and two searches for the Spanish
chorizo. The searches showed that FoodData Central has no dry-cured
Spanish chorizo record at all (its SR chorizo is the fresh Mexican link at
296 kcal), so the five Spanish-chorizo lines count on "Salami, Italian,
pork" (174603, 425 kcal; sodium about half high against a Spanish label)
as a flagged approximation at no further cost — the preparation report's
recommendation. v32 (2026-10-03) then enabled each dry rule only after
its stated check against the real record: nine checks passed (the
tamarind and egg volume siblings publish a cup portion, the juice, onions
and pimento a cup or tablespoon, the tuna its can, the leg quarters and
the fresh ham no refuse yield — so the gross weight, labelled approximate,
under the meats ruling); the portobello stays dry (its record publishes a
serving, no per-cap portion); the brioche enables through a `brioche bun`
piece figure of 77 g read from the record's own "1 piece" portion and
flagged approximate because the piece is read as one bun. Replay on the
fetched copy: calls 0; 20 rows differ from v31, every one attributed to an
enabled item, none a person's row; counted 13,260 → 13,275, check 269 →
258, no grams 54 → 50; complete 939 → 949. Fixtures: the 12 details and 4
searches added as byte-equal copies of the fetched copy's rows; the
superseded pins (the fresh ham "waits for its detail", the leg quarters
below the gate, the tamarind lines at no grams) re-pinned; the contract
goldens changed on the ham entry only. Four verifier rounds (two close
rounds; the last pass with observations only). The owner's gate: the
fixtures checked against the fetched copy, the re-pins read, two
code-anchored mutants (the tamarind sibling removed; the chorizo flag
removed) killed and restored, the replay re-run on a fresh copy, the
suites green; the owner added the brioche flag the verifier observed was
missing. The fetched copy, key-stripped, is snapshot 14 — the replay
reference from here on (`.claude/diag/2026-10-01/snap14.db`). The
portobello singular (2003598) remains the one live-step item not enabled.
matcherVersion 32.

### The accuracy track, part 4: the dredge-reach ruling (matcher v33)

The owner ruled on the dredge survey (2026-10-03, evening): a reachable
coating line is held whenever the directions leave an excess of the coat
behind, in every cooking class, and counted whenever the coat is wholly
eaten; a blanket coating fraction stays ruled out. v33 (2026-10-03) builds
it as the narrowest text signal the survey's deciding sentences support:
a step sentence in which a removal verb (shake, remove, pat) reaches the
word "excess" followed by the coat, a conjunction, punctuation or the end
("dredge in the flour, shaking off the excess", "using a pastry brush,
remove excess cornstarch", "thoroughly pat off the excess cornstarch
mixture"), never a liquid's excess and never in a step that names a dough
(rustic dinner rolls and pita are dusted and shaken off and are not
dredges). A coat set out in a shallow dish is not a signal on its own: that
reading would have held katsu, chicken parmesan, the salmon cakes, the crab
cakes and chicken marsala against the survey. The frying ruling of
checkpoint 9 stands as a sufficient condition, so no held dredge is
un-held; the bread a newly held breading processes into its crumbs, and a
crumb or panko line the steps call by another name, are held with the
flour of the same coat; a divided "plus" line whose first part is set out
in a pie plate for the dredge keeps its eaten part counted. The engine's
reading reproduces the survey's judgment on all 47 coating recipes (32
leave an excess, 15 do not). The review screen's wording for the hold no
longer says "fried": a dredge whose excess is discarded, and how much the
food keeps is not written. Replay on snapshot 14: calls 0; 25 rows differ
from v32 — 18 flour or cornstarch lines in the sautéed, baked and shallow
classes, 5 bread lines and 2 crumb lines of the same coats — every one an
auto row with no hold that is now held `coating`, no person's row, no held
row un-held; counted 13,275 → 13,250, check 258 → 283; complete 949 → 932
(17 recipes to review: the two piccatas, chicken francese, saltimbocca,
meunière, skillet chicken and rice, better chicken marsala, parmesan-
crusted cutlets, pan-seared salmon steaks, maple-glazed pork tenderloin,
Kiev, nut-crusted chicken, crunchy baked pork chops, crunchy oven-fried
fish, lighter chicken parmesan, oven-fried onion rings, stuffed chicken
cutlets). Follow-up questions recorded for the owner, not decided: the
four fried dredges the survey reads as leaving no excess but the frying
ruling holds (0288, 0149, 0525, 0042); the coat components outside the head
set that stay counted (0117's almonds, 0150's Melba toast, 0315's saltines
and potato chips, 0419's Parmesan). Two verifier rounds (one close round
added the crumb-by-another-name arm). The owner's gate: the re-pins read,
two code-anchored mutants (the excess condition dropped from the dredge
gate; the "pat" verb dropped from the signal) killed and restored, the
fresh-copy replay identical to the verifier's, the three analyzers and the
suites green. matcherVersion 33.

### The accuracy track, part 5: the coat's other layers (matcher v34)

v33 left two questions for the owner, who ruled on both (2026-10-03,
night: "the narrow version for both lists"). The four fried dredges the
survey reads as leaving no excess sentence (crab cakes, easier fried
chicken, orange chicken, almond-crusted chicken) stay held by the frying
ruling — no change. The coat layers outside the flour and crumb head set
are held only narrowly, and v34 (2026-10-04) builds that: a line whose head
is a nut, cheese, cracker, chip, cornflake or Melba toast, sized above the
quarter-cup guard and the first of its head in the recipe, is held
`coating` when the steps name it in the sentence that sets the coat out in
its shallow dish or mixes it with the crumbs, and the recipe either holds a
dredge already (the v33 gate as it stands) or leaves an excess of the coat
(the Melba toast of oven-fried chicken, whose coat has no flour line).
Cheese in a filling or a sauce, nuts in a strudel, chips on the side and
a crust no step leaves an excess of stay counted, each pinned as a
non-trip; a row with no food gets no hold (the cornflakes stay no match).
The rule reached eight rows, not the six the brief enumerated: the
Parmesan stirred into the already held crumbs of eggplant parmesan and
lighter chicken parmesan is a layer mixed evenly through a held coat, left
in the dish in the same share, and the two verifier rounds and the owner
agreed the enumeration was short, not the rule wide. Replay on snapshot
14: calls 0; 8 rows differ from v33 — the almonds of two recipes, the
saltines and potato chips of the onion rings, three Parmesan lines and the
Melba toast — every one an unheld auto row now held `coating`, no person's
row, no held row un-held, no no-match row touched; counted 13,250 →
13,242, check 283 → 291; complete 932 → 931 (oven-fried chicken alone
enters the review queue; the others were already there). The review
screen's wording now reads "part of a coating whose excess is discarded"
so a nut or cheese layer reads true. Two verifier rounds found the
enumeration question only; the third verifier's agent wrote its report
and stalled on its return (the app analyzer took fifteen minutes on this
machine), so the owner's gate stood in for its verdict: the two search
fixtures byte-equal to snapshot rows, the re-pins read, two code-anchored
mutants (the held-dredge-or-excess condition dropped; the almond head
dropped) killed and restored, the fresh-copy replay identical to that
verifier's, the analyzers and the suites green. matcherVersion 34.

### The accuracy track, part 6: the portobello caps (matcher v35)

The one live-step item v32 could not enable — the portobello cap, whose
Foundation record publishes a serving marker and no per-piece weight — went
to the owner, who chose to spend two more requests for FoodData Central's
own figure (2026-10-04). The search "mushrooms portabella raw" returned the
SR Legacy record 169255 "Mushrooms, portabella, raw", and its detail
publishes "1 piece whole" 84 g and "cup diced" 86 g. v35 (2026-10-04) points
both count lines at it — the stew's "1 large portobello mushroom cap",
which had sat on a pork leg steak at low confidence, and the stir-fry's
"6 to 8 portobello mushrooms", which had sat on crimini with no grams —
through rank-as items reading that answer, and sizes them by an 84 g piece
figure read from the record (the engine's whole-item reader skips a
"piece" portion with no unit, so the figure is a table entry), flagged
approximate because a whole mushroom's weight is read for a stemmed cap.
"Large" is not a size word, so the cap reads 84 g; the bare range reads its
midpoint, 7 × 84 = 588 g. The ragu's weight line stays on the Foundation
record, pinned. Replay on the fetched copy (snapshot 15): calls 0; exactly 2
rows differ from v34, both engine rows, no person row; counted 13,242 →
13,244, check 291 → 290, no grams 50 → 49; complete 931 → 932 (the stir-fry;
the stew still waits on four parsnips with no weight). Fixtures: the search
and the detail copied byte for byte from the fetched copy. Live requests on
the accuracy track: 16. One verifier round, no defects; the owner's gate:
the fixtures checked, the re-pins read, one code-anchored mutant (84 → 80)
killed and restored, the fresh-copy replay identical to the verifier's, the
suite green. The fetched copy, key-stripped, is snapshot 15 — the replay
reference from here on. matcherVersion 35.

### Before the first run: an engine line keeps what it had (v36, matcher version unchanged)

Of the exit review's deferred findings, one was reachable on an ordinary
admin sweep and the owner chose to fix it before the first real run
(2026-10-04): v29's engine-line failure handling built a fresh unmatched
row whenever an undecided line's food failed and the line had no
already-unavailable row, and wrote it over the line's current engine row —
so one transient failure on an `all` or stale sweep destroyed a previously
correct auto match (0857 complete 13/13 at 464.8 kcal → one 500 on the
butter's detail → "unmatched / FoodData Central could not serve this
food", 12/13 at 363 kcal, until a later sweep). v36 completes RULE A's
"every line kind" with "keep what was there": an engine line that already
has an auto row with a food is treated on a food failure exactly like a
decided row — the row kept with its food, description, grams and status,
left underived with its retry count incremented, the recipe stale
(`stale_reason` underived), the pass continuing; held `food_unavailable`
after three failures with the food kept so a reviewer sees what it was;
re-read from the caches only on a stale sweep and asked of FDC once per
`all` sweep like any held row; a kept row whose food is not cached is left
out of the totals the way a decided row is (the first cut set the
`unavailable:` stamp and ran three passes in one sweep, counting the row
three times — caught by the v29 O4-shape pin and fixed). The unmatched
note row is written only when the line has no row with a food (v29's
behaviour there, pinned). The freshness predicate's engine half now also
reads an auto or unmatched row with a retry count and no hold as underived.
The job watch, the per-pass suspension and the GLOBAL classes are untouched
and their suites green; the oracle's outage mode clean. The matcher version
stays 35: failure-path handling only, and a cache-only replay of snapshot
15 moves no row. Pins on 0857 end to end (fail once → kept and stale;
recover → one request, 464.8 kcal; fail three times → held with the food;
the `all` re-ask recovers), the no-prior-row case, and a job-driven shape;
v28's A12 re-pinned (its last assertion had pinned the overwrite itself).
Three verifier rounds (two close rounds). The owner's gate: the re-pin
read, one code-anchored mutant (the kept-row arm made unreachable) killed
and restored, the fresh-copy replay with zero rows differing, the suites
and the outage oracle green.

### The queue sweep, part 1: every zero-request group the owner approved (matcher v37)

With the engine loop closed and the first run live, the owner's third
decision (2026-10-04) was to work the review queue's engine side rather
than leave 393 lines for a person: a read-only planning pass over the 131
lines below the confidence gate, the 49 matched lines with no weight and
the 32 lines with no match produced an approval table (every proposal a
named record or a sourced figure; a sample audit of the ten largest
proposals found no wrong food), and the owner approved it with my
recommendations on the six judgment calls. v37 (2026-10-04) builds every
zero-request group: right records that cached answers already named
(pears, a whole side of salmon by ATK's printed "about 3½ pounds", raisins,
cheddar, orange juice, raw cashews …), density keys from weights ATK prints
in the corpus (pearl onions, lentils, strawberries, grape tomatoes, cooked
chicken, shredded apple), ATK's own equivalences (a yeast envelope, "about
8 fillets", a trimmed weight, a sugar cube from the recipe's own yield),
FDC's own portions for olives, jalapeños and a baguette by the inch, two
parse fixes; flagged stand-ins on precedents the owner had set (mirin on
the sweet-wine record, gochujang and chipotle in adobo on sriracha,
doenjang on miso, galangal on ginger, culantro on cilantro, alcaparrado on
green olives, five-spice on pumpkin pie spice, garam masala on curry
powder, Sichuan and pink peppercorns on black pepper, white fish on cod,
mixed herbs on parsley, roasted red pepper at the pimento density, gyoza
wrappers at the wonton figure, crème fraîche on heavy cream at a 1.01
density, nonpareils at sugar's density); the owner's answers (canning salt
counted on table salt, a sea scallop 34 g flagged); food-only fixes on
lines already accounted as zero; and a class rule for zero-nutrient
flavourings (an explicit list — liquid smoke, red and green food
colouring, a pickling crisp, bitters, a vanilla bean — each counting 0 g
on no food with the basis "flavouring, no nutrients", reaching exactly its
14 library lines). The request groups (30 requests: bulgur, pectin, barley
malt, canned sour cherries, a per-cookie portion, nine same-food records
for portions, nori, frisée, cremini, ya cai, and three speculative
searches) are built dry for the live step. Deviations from the planners,
each pinned: the pear's rank words tie an FNDDS record ahead of the SR one
and were replaced; the cheddar line lands on the record the library's
other eight cheddar lines use; the francese olive oil reads the
extra-virgin answer; a density figure applies only where the record has
no volume figure of its own; the fragment rule is narrowed to parenthesised
or continuation lines; two held second-food chipotle lines gain the
sriracha food while staying held. Replay on snapshot 15: calls 0; 113 rows
differ from v36, every one attributed to the planners' row table or the
flavourings list, none a person's row, no hold changed; counted 13,244 →
13,343, check 290 → 232, no grams 49 → 23, no match 32 → 17; complete 932 →
1,004 (72 recipes complete, none back). Fixtures: 17 details and 20
searches copied byte for byte from snapshot 15. Sixteen older pins moved
to other real lines (the Sichuan peppercorns they used now lift). Two
verifier rounds (one close round). The owner's gate: the fixtures checked,
the re-pins read, two code-anchored mutants (a flavouring dropped from the
class; the lentil density changed) killed and restored, the fresh-copy
replay identical to the verifier's, the suite green; three engine comments
that pointed at a scratch file repointed at API.md. matcherVersion 37.

### The queue sweep, part 2: the request groups, enabled (matcher v38)

The owner spent v37's live step on 2026-10-04: 26 requests on a scratch
copy of snapshot 15 (21 details and 5 searches; one detail skipped because
its rule could not rank the record first, one already cached), the key
attached read-only for the run and deleted after, the result snapshot 16.
Two searches found no food at all — FoodData Central has no freekeh and no
candied ginger (the 25 candidates for "candied ginger" are teas, pickled
root, ginger ale and candy bars) — so those lines stay a person's, as the
plan said they would; the farro search found only pearled farro with a
serving marker, so the whole-farro line stays as it was. v38 (2026-10-04)
enabled twelve groups whose stated check passed on the real portions —
bulgur (cup 140 g), diastatic malt (cup 162 g), roasted pepitas, Oreos (a
12 g cookie read from FDC's "3 cookie" 36 g), turnip (one whole 120 g),
romaine (the inner leaf 6 g; the outer is 28 g — the owner's call if a
recipe means whole outer leaves), frisée on the endive record, cremini (a
20 g whole mushroom, flagged), ya cai on salted mustard cabbage (flagged),
and three volume siblings (radicchio, cauliflower, canned chickpeas) — and
left nine dry with the portions FDC actually published (pectin by the
package only, fennel bulb only, Morello cherries with no reader for the
jar weight, xanthan by the ounce, parsnips by the cup of slices, no large
kiwi, malted milk powder by the heaping teaspoon only, no nori sheet,
cashews by the ounce). Replay on snapshot 16: calls 0; 36 rows differ from
v37, every one attributed to an enabled item (eighteen cremini rows change
food only), no person's row, no hold changed; counted 13,343 → 13,361,
check 232 → 223, no grams 23 → 17, no match 17 → 14; complete 1,004 →
1,016. Fixtures: 22 details and 13 searches byte-equal to snapshot 16.
Two verifier rounds (one close round). The owner's gate: the fixtures
checked, the re-pins read, two code-anchored mutants (the Oreo figure; the
frisée item removed) killed and restored, the fresh-copy replay identical
to the verifier's, the suite green; a misplaced colon in API.md that v37
had introduced put right. The accuracy track's live requests: 42 in all.
matcherVersion 38.

### Edible yields, part 1: the bone-in class yields, skin, shell, size and two prep losses (matcher v39)

The blind accuracy audit (2026-10-05; `.claude/diag/2026-10-05/audit1/`)
graded 230 blind lines and recomputed 25 recipes by hand: the engine's
food choice was wrong on one of 200 counted lines, and the mass ran high where
a line's weight is what was bought rather than what is eaten — bone-in
cuts at gross weight alone were 83 % of the sample's calorie error. The
owner ruled on the planners' nine items the same day ("go with your
recommendations"; the decision-log entry below), and v39 (2026-10-05)
builds everything that needs no request. Y1, the bone-in class yields,
REVISES checkpoint 6's #11 and #5: a line that buys refuse, weighed from
a printed weight, on a record that publishes no refuse portion of its
own, reads its class figure — every one an FDC portion (pork bone-in
chops 0.662 from 168242's own refuse; ribs 0.653 from country-style ribs;
bone-in pork roasts and hams 0.758 from the Boston butt; beef standing rib
0.758 on the same figure; chicken and turkey parts 0.608 from the whole
chicken's ready-to-cook yield; a whole turkey 0.608 as an interim; bony
beef, lamb and veal 0.657, the median; oxtails 0.564 from the record's
own "1 oz yields 16 g"); the either-bone steaks and ham hocks stay gross;
a record's own refuse portion and the whole chicken's ready-to-cook yield
keep precedence. Y2 un-holds five shellfish lines whose grams need no
shell yield (a dozen mussels and two dozen oysters at FNDDS's 15 g of
meat; shell-on shrimp the prep note says are eaten whole; two live
lobsters at the record's own 200 g) and keeps thirteen held. Y3 moves a
bone-in, skin-on thigh or leg quarter whose recipe discards the skin to
the cached meat-only record at the bone yield × FDC's meat share (0.795,
0.770), on a narrow signal (the line's "skin removed", or a step that
removes or discards the skin with no sentence reserving, laying back,
stretching or trimming it); the breast and whole-bird shares are built
dry for the live step. D1 reads canned coconut milk on the SR canned
record (197 kcal) instead of the FNDDS drink (31 kcal), unflagged. C1 and
C3 read "small" and "large" on a counted onion, carrot or round tomato
from the SR records' own size portions, and a plum tomato at 62 g. A3 and
T1 are the two prep losses with a printed figure: a peeled banana at
FDC's 115 g "Peeled" portion and drained canned tomatoes at × 0.54 (ATK's
own "3 cups juice" from two 28-ounce cans), each only when the grams come
from a printed weight and the word sits in the line's tail after its
first top-level comma. The first verifier round found the batch's one
real defect before it shipped: the skin share was keyed on the meat-only
record, and a routine Confirm of a moved row wrote that record for the
item key — so Chicken Provençal's thighs, confirmed, would have put the
share on Chicken Teriyaki's skin-eaten thighs across the library. Closed
at the root: the share is read only where the line's own recipe trips the
signal, the move applies to every auto row on the skin-on record (the
engine's pick or a carried decision) and never to a person's own row, and
a decision written from a moved row records the skin-on record bought.
Replay on snapshot 16: calls 0; 271 rows differ from v38, every one
attributed (Y1 96, Y3 13, Y2 5, D1 9, C1 114, C3 4, A3 2, T1 28), no
person's row, no status change, the only hold changes Y2's five; counted
13,361 → 13,366, check 223 → 218, no grams 17, no match 14; complete
1,016 → 1,019. Recipes moving by more than 10 % a serving: Y1 100 of 103,
Y3 12, Y2 4, D1 9, the rest none — the plan's counts. Two figures differ
from the plan's and are kept: the two coconut-milk volume lines read the
`milk` density (182.76 g, 121.84 g) as the library's three canned lines
already do, not 170173's cup; C1 reaches 114 rows, not 102, because the
rule sizes an onion of any colour (eleven small red onions) and reads "1
small carrot, chopped medium" by its head. Fixtures: 12 details and 9
searches, each equal to its snapshot-16 row; the two contract goldens
regenerated (a 3½-pound chicken 1,587.6 → 966.0 g; a bone-in ham 3,628.7
→ 2,750.2 g). Re-pins: v7–v11, v17, v21, v30, v32, the sweep audit
398/299, the seasoning hash. The owner's gate: every named mechanism
grepped, the fixtures compared to the snapshot rows, every re-pinned
bound read (none widened), two code-anchored mutants (the poultry figure;
the "small" term of the size read) killed and restored, a fresh-copy
replay byte-identical to the verifier's, the analyzer and the full suite
green. matcherVersion 39.

### Edible yields, part 2: the live step, spent and enabled (matcher v40)

The owner spent the plan's live step on 2026-10-05: 13 requests (3
searches, 10 details) on a scratch copy of snapshot 16, the key attached
read-only for each stage and deleted after it, the result snapshot 17
(`.claude/diag/2026-10-05/snap17.db`; the log `live39_record.log`). The
plan's own conditions decided every item from what FDC answered. Enabled
as v40 (2026-10-05): a whole bird or pieces on 171447 whose recipe
discards the skin moves, by v39's move semantics, to SR 171052 "Chicken,
broilers or fryers, meat only, raw" — the search's first record, whose
own portion gives 197 g of meat a ready-to-cook pound against 171447's
276 g of meat and skin — a whole bird read by the existing ready-to-cook
reader, unflagged where the whole skin goes and flagged where the
recipe keeps part of it (Grilled Lemon Chicken's "leaving skin on wings",
which the plan said the flag must name — a second closer round added it),
pieces at the same per-pound figure flagged (the whole bird's part mix
assumed); and the six clam lines bought by weight rank as SR
174214, whose detail publishes "lb (with shell), yield after shell
removed" 68 g, read by a reader for that one portion shape, so they count
at 0.15 of the weight bought and the `in_shell` hold lifts. Not enabled,
each recorded in API.md with FDC's answer: the breast share (the skinless
breast record publishes no half-breast portion; its "piece" is 272 g
against a 145 g half), the whole-turkey yield (no raw meat-and-skin back
or neck record exists and the meat-only ones publish no share, so the
three parts' 0.626 is a partial sum and the interim 0.608 stays), the
mussels (no with-shell portion; five lines stay held), the canned beans
(the chickpea pair names no can size, so the same-can condition is
undetermined and the other pairs were not fetched — the owner's open
question). The verifier's first round found that v39's skin signal, inert
for a whole bird until now, tripped Classic Chicken Noodle Soup's bird on
a step that discards the skin "from the breast pieces" only; the closer
narrowed the shared predicate at its root — a skin-off sentence that
names a part trips only a line whose item names that part — which moves
no v39 row and changes only that recipe, and pinned the pieces arm's trip
gate. Replay on snapshot 17: calls 0; 11 rows differ from v39, every one
attributed (E1 5, E2 6), no person's row, no status change, the only hold
changes the six clam un-holds; counted 13,366 → 13,372, check 218 → 212,
no grams 17, no match 14; complete 1,019 → 1,022 (cataplana, New England
clam chowder and paella on the grill finish). Fixtures: 3 details and 1
search, each equal to its snapshot-17 row. Re-pins: v7, v10, v11, v16, the
v39 meat suite's two clam rows, the sweep audit 401/301, the seasoning
hash. The accuracy track's planned live requests now total 55 (API.md's
record); the v38 server sweep's 14 requests, spent before its caches were
seeded and equal to snapshot 16's answers, bring the requests actually
sent to 69. matcherVersion 40. The composite-row batch the approved mockup
calls v40 ships as matcher v41.

### The composite row: sub-recipe routing phase 1, the rendered-bacon row, the partial-label rule (matcher v41)

The owner approved the composite-row mockup on 2026-10-05 ("go with the
recommendations" on its five open questions) and, after a read-only
design pass — four planners, a synthesis, a completeness critic whose
three HIGH findings and twelve others were folded into a second and third
draft, each rechecked — ruled on the design's ten questions as recommended
(the decision-log entry). v41 (2026-10-05) builds it in two commits. The
SERVER commit: migration 018 adds four nullable columns to the matches
table (the child recipe, its share, the child's stamp, the parts JSON) —
still one row per line, nothing in YAML. A reference line ("1 recipe X",
"(this page)", "(recipes follow)") resolves, first hit wins: no amount →
a marinade (held `discarded_recipe`, poured away) → one own section (the
0 g rule row until phase 2) → the first library title the prep note names
(flagged as a default when it names two or more) → the exact library title
(unless the parent is made FOR it — Herb Sauce's steaks) → other recipes'
sections listed, never routed → held `choose_recipe`. A routed row counts
the child's stored totals at the line's share (a written "½ recipe", "N
recipe", or the amount over the child's MAKES measure), its grams live,
accounted only while the child is complete; a child's recompute, rebase or
delete turns its parents stale and the sweep recomputes them parents last.
Rule B1 reads a bacon row whose recipe fries the bacon out and pours the
fat down to N tablespoons as cooked bacon at FDC's protein retention
(0.403) plus the kept fat as bacon grease, one row, flagged. R3: every
reference line not routed leaves the label partial and the matched count,
out of the queue. A recipe pick never enters the item-key decisions; it
travels only by an explicit apply-to-all, whose targets become the
person's own rows. The three recipe holds are line holds. The verifier's
rounds found: a share-less recipe pick stored as a counted 0 g row (now a
422 asking for the share) and two pin gaps; the fixers' own deviations,
kept: a food pick WITH typed grams on a reference line stays accepted as
shipped since Run 051 (only the bare pick is refused), and the appended
pour-off step renders the sample's pancetta row in the rules golden.
Replay on snapshot 17 through the new harness (rp41: the engine's own
sweep order, parents last; staleAfter 0; 1,198 fresh): calls 0; exactly 64
rows differ from v40 — 13 routed (the four double-crust pies on All-Butter,
flagged; peach tarte tatin unflagged; the three graham-crust pies; the
three tart-dough parents; the chocolate cream pie; the nachos' guacamole),
35 held `choose_recipe`, 3 marinades, 13 bacon rows — every one
attributed, no person's row; counted 13,372 → 13,334, check 212 → 215,
no grams 17, no match 14, choose_recipe 35; complete 1,022 → 935 (the 87
exactly the design's list; 51 of them with nothing to review until phase
2); R1 +25,702 kcal per batch (Blueberry Pie 189 → 571 kcal a serving),
R2 −891 (Wilted Spinach Salad 360 → 302). Two deviations from the approved
plan, each a ruling: 13 routes not 16 (the un-noted single-crust pies name
a section) and 87 recipes partial not "about 60" (the plan read stale
stored labels). Fixtures: 10 details and 23 searches, each equal to its
snapshot-17 row; the contract goldens regenerated and five new corpus-free
goldens through the real routes. The owner's gate: the replay reproduced
row for row, the two reserved mutants (the default = the first named
title; the kept-fat minimum) killed, analyzers clean, salt_shared 214 and
the server 2,088 green; deployed locally — migration 018 on the live
database after a key-stripped backup, the stale sweep at zero requests,
the live buckets equal to the replay. matcherVersion 41.
The APP commit, per the approved mockup (now
`docs/mockups/v41-composite-rows.html`, renamed to the matcher version that
ships it): the review sheet's row grows a routed branch (the Recipe chip,
the share and the "from the recipe" basis, the flag on its own line, Change
and "Open the recipe's matches" — members see the link only), a held
branch (the "choose recipe" badge, Choose a recipe or Skip), a two-part
branch (one row, two records with their grams, "kept in the pan", Change
as the undo) and a "not counted" badge for the rule rows R3 leaves; a
recipe fix panel with the five candidate groups in resolution order,
sections listed but not pickable, the library search, a share field
offering only the child's yield units and one following primary button;
the label's "Includes N recipe" and Partial lines, shown to members too;
the queue's fifth chip "Choose recipe" with its slots and line-hold notes;
the apply strip's recipe footer. Every string is the copy sheet's, four
disclosed where the sheet was silent. Five verifier rounds: the first
three closed string and pin gaps, the fourth pinned four rules a mutant
had shown unpinned (one named mutant equivalent — a redundant argument on
a shared table lookup), the fifth the apply footer the mockup draws but
the copy sheet omitted. flutter analyze clean, the app suite green;
theme_test untouched, no package added. Two notes left for the owner: a
"served with" reference row carries only the "not counted" badge, its
words appearing in the label's Partial line; and the queue's headers now
read in lower case throughout, as the mockup draws them.

The blind re-calibration after v39–v41 (the audit's 25 recipes; the
hand figures reused, being independent of the engine;
`.claude/diag/2026-10-05/recal_v41.md`): mean absolute error 11.3 % →
5.8 %, median 4.4 % → 4.0 %, the engine-high bias +3.4 % → +0.8 %; Blueberry
Pie +0.2 % (the dough routed), the buffalo wings −18.2 % against a hand
figure that counts the dressing the engine holds for a recipe choice, the
known person's lines unchanged. At line level, counted lines within 15 %
of the auditors' grams rose from 161 to 171 of 197 (within 25 %: 166 →
180) and the engine's gram total over the auditors' fell from 1.20 to
1.01; every bone-in line is inside 25 % but the beef back ribs (1.19×, as
the plan said). Two ceilings stand: a whole bird that keeps its wing skin
now reads 13 % under (the meat-only yield removes all skin; flagged), and
the SR meat-only thigh share runs about 17 % under the auditors' estimate
on two recipes. The remaining outliers are a person's lines, small herb
and aromatic amounts, and produce yields for a later batch.

### Canned beans by their drained share; the not-routed row note (matcher v42)

The owner's rulings on the questions left open after v41 (2026-10-06; the
decision-log entry). Canned beans: 22 lines counted a can's printed weight
on Foundation "drained and rinsed" records, so the can's liquid was counted
as beans — about 7,400 kcal across the library. The owner chose to fetch
FDC's remaining can pairs (five details on a scratch copy of snapshot 17,
the result snapshot 18) rather than apply the chickpea share to every bean,
and the pairs differ by up to six points: chickpeas 0.565, kidney 0.610,
pinto 0.627 (each drained ÷ total can from the two records' own portions);
black, cannellini and navy beans, with no cached pair, take the three
pairs' median 0.610, flagged as such; the rinsed kidney record publishes a
cup only, so rinsing adds no factor. A line that keeps the liquid
("undrained", "do not drain", "liquid reserved") keeps the can whole;
"1 can drained, 1 can undrained" takes the share on half the cans. Replay
on snapshot 19 (snapshot 18 plus the four chicken details of the skin step,
below): calls 0; exactly 19 rows differ from v41, every one a bean row
(three keep the liquid), no status, hold or bucket change; 19 recipes move,
10 by more than 10 % a serving (ultracreamy hummus −22 %, pasta e fagioli
−22 %). The review sheet: a reference row the engine does not route now
carries a one-line note under its "not counted" badge with the label's own
reason (its section has no totals yet; served with this recipe, not made
from it; no amount on the line; no share the yield can read). The queue
header keeps the lower-cased bucket inside its sentence, as the mockup drew
it. One verifier round, no defect; the owner's gate: the replay reproduced,
two mutants (the half-can rule; the served-with note) killed, analyzers and
suites green. matcherVersion 42.

The skin live step (the owner's option (b), four details, the result
snapshot 19) settled one question and reframed another: the SR "thigh with
skin" portions are boneless (the thigh pair reads 193 g with skin and 149 g
without, within 2 g of the leg record's "bone and skin removed" 147 g), so
v39's bone-then-skin stacking does not double-count the bone; the SR skin
shares agree at 21–23 % skin (0.772 thigh pair, 0.795 the leg record's
thigh, 0.770 leg) against the Foundation nutrient balance's 15–17 %. FDC
publishes no bone figure for a thigh and no wing-skin figure (the wing's
skin share by nutrient balance falls anywhere between 0.21 and 0.36, two to
four points of Grilled Lemon Chicken's 13 %). The remaining under-read on
thigh and leg lines, and on the whole bird, therefore sits in the
whole-bird bone share applied to meatier parts, which FDC does not publish
for parts; the USDA yield handbook the owner approved as a source is the
route, in phase 2's design pass. Which thigh share ships is the owner's open
choice.

The phase-2 dry run (the owner's option (a); read-only, zero requests;
`.claude/diag/2026-10-06/prep42/`): 403 sections with ingredients in 241
recipes, 2,895 lines, all stored with the `variation` tag (the 32
`component` sections carry no lines); the referenced sections are 140 with
936 lines. Against snapshot 19's caches, 2,541 section lines have a cached
answer and 146 do not — 132 distinct missing searches (16 of them
normaliser defects to fix by rule, 116 genuine), no missing detail in the
first wave, up to 113 details in a second; for the referenced sections
alone, 42 searches and up to 33 details. 259 sections would be complete at
zero requests; of the 51 recipes partial with nothing to review, 27 finish
at zero requests, 15 more need 13 genuine requests, 9 never finish through
sections (six with no amount on the reference, one served with, two whose
section has no lines). An independent checker re-derived every count.

- **2026-10-06 — after v41, the owner's answers one at a time:** (Q2) every
  not-routed reference row gets a one-line note under its badge with the
  label's reason, option (a). (Q3) the queue header keeps the lower-cased
  bucket in its sentence, option (a). (Q4) phase 2 starts with a zero-request
  dry run, then a design pass with the real request count, option (a) — done
  the same day (the v42 section). (Q5) spend requests for the wing skin and
  an SR thigh refuse figure before changing the shares, option (b) — spent
  the same day (four details; snapshot 19): the SR portions proved boneless
  and no bone or wing-skin figure exists, so the choice of thigh share (keep
  0.795; the thigh pair's 0.772; the Foundation-derived 0.84) was put back to
  the owner, who kept 0.795 ("go with your recommendation"): a published FDC
  portion stays until the part bone share is sourced from the USDA yield
  handbook in phase 2's design pass; the wing flag stands.

### The handbook yields: parts, prep losses and named cuts from USDA Agriculture Handbook 102 (matcher v43)

The question the re-calibration left open — why bone-in thighs read 17 %
under independent hand estimates — was a bone share, not a skin share: the
engine applied the whole bird's edible share (0.608) to every part. FDC
publishes no part yields, so the owner's approved source, USDA Agriculture
Handbook 102 (Food Yields Summarized by Different Stages of Preparation,
revised 1975), was fetched as a 139-page scan, rendered page by page with a
small CoreGraphics program and transcribed into two extracts with an
item-number index (`.claude/diag/2026-10-06/ah102_poultry.md`,
`ah102_produce_meat.md`). A design pass (five planners, a synthesis, a
critic with eighteen findings folded in, a recheck) produced the package
the owner ruled on the same day: two batches, the yields first (B1), and
Y1–Y13 as recommended, with Y12 reversing the morning's "keep 0.795" once
the handbook's own thigh figure was in hand. v43 (2026-10-06) builds the
yields. Poultry: a bone-in chicken or turkey part weighed from a printed
weight reads the handbook's raw boning figure for the part the line names,
the record deciding meat or meat and skin in one step (breast 74 / 65,
thigh 70 / 59, drumstick 63 / 55, wing 50 / 31; a leg and mixed pieces
derived from those by the carcass shares and flagged derived, since no
leg-quarter row exists; turkey thigh 82, leg 75, leg quarter 71, wing 61,
fryer-roaster class flagged); a whole turkey reads the handbook's "12 lb
and over" dressing step times its carcass yield (0.652) in place of the
chicken interim; skin-discarded breasts move to the Foundation skinless
record at 65; a skin-discarded thigh reads 59 from the printed weight and
the SR skin stack is retired. Kept: whole chickens at FDC's own 0.608 and
0.434 (inside the handbook's ranges) and the bone-in turkey breast at
0.608, deferred because the handbook's breast is a breast without the back
ATK's carries. Produce: a weight printed in the line's head with the prep
word in its tail reads the paring yield (potatoes 81, apples 78 or cored
90, sweet potatoes 80, pears 78, carrots 82, onions 90, leeks 44, savoy by
head cabbage 93, cauliflower 92, butternut 84, zucchini 93, summer squash
95, strawberries 94), never a count read, a trailing prepared weight,
"unpeeled", "peels reserved", or a line that also uses the part the word
would discard (the verifier's catch on a pasta whose leeks are used whole);
scallion part words on a piece read (white 37, green 59 derived). Meats
where the handbook names the cut: spareribs 0.58, standing rib 0.82, fore
shank 0.61, lamb rack 0.73 (flagged as measured unfrenched), lamb foreshank
0.70, cured spiral ham 0.70, fresh ham shank half 0.78 derived; FDC's own
refuse portions stay; bacon keeps 0.403. Replay on snapshot 19: calls 0;
198 rows differ from v42 (poultry 74, produce 103,
scallions 6, meats 15), grams and basis only except five breast rows that
change record; no bucket, status, hold or person row moves. The 25-recipe
re-calibration: mean error 5.80 → 6.13 %, median 4.00, the signed mean
+0.80 → −0.32 % — the design's predicted figures: the engine now sits a
little below the hand estimates where it sat above them, and Chicken
Provençal's thighs read 1.02× the auditors where they read 0.83×. Three
verifier rounds (a fifth breast line vetoed by its own "reserved cooked
chicken"; a savoy citation; three printed ranges; then the leek line), the
owner's gate (replay reproduced, two mutants killed, analyzers and suites
green). matcherVersion 43.

### Sections as children: a titled subsection is a recipe of its own (matcher v44)

Phase 2 of sub-recipe routing. v41 routed a reference line to a LIBRARY
recipe; the 51 recipes left partial with nothing to review all referenced a
section of their own document ("1 tablespoon tabil (recipe follows)") or of
another's ("1 recipe Basic Single-Crust Pie Dough (this page)"). The owner's
rulings S1–S15 (2026-10-06, as recommended) make such a section a recipe of
its own when a main reference line needs it — only the referenced ones (140
on snapshot 19, 936 lines), never the dry run's 403. Storage (migration 019,
user_version 18 → 19): the three nutrition tables are rebuilt so `recipe_id`
may hold a section key `<host id>#<exact title>` and a VIRTUAL generated
`host_id` carries the FK to `recipes` with its cascade (accepted by this
Mac's SQLite 3.54.0; Debian bookworm's 3.40.1 is unverified and the trigger
fallback unbuilt — the migration test runs on the deploy image before the
first deploy). The key is storage only: on the wire a section is always its
host's slug plus a `section` title. One resolver (`nutritionRecipeOf`)
serves every nutrition path — a key loads its host and the section as a
recipe with the section's own lines, yield and steps — and every per-recipe
gate (layout, the write race, the held-medium cache) binds the HOST's
content hash. The bulk order is [child section keys, recipes that read
none, parents]; a stale key appends its parents; a sweep collects keys no
main line needs any more (never a person's decided row); a host saved with
a section retitled or removed drops that key's rows, stamp and layout, and
a parent's pick of it then holds `choose_recipe` missing, naming the old
title (S15, one-way). Engine: the own-section and other-host branches build
the key and share the library tail — the share read on the SECTION's yield
(Tabil ⅛ of ½ cup; the gluten-free blend 16 of 42 oz), a section with no
ingredient lines the 0 g rule row `no_ingredients`, a section holding a
reference `nested_recipe`; another host's section routes only when exactly
one host carries the title (N8). Rule PO lists, for a "(recipes follow)"
line held generic or marinade, the recipe's own sections no other reference
routes to — listed for a person, never routed (the glazed ham's two
glazes); A9 reads an unmarked line naming an own titled section as a
reference (kibbeh's harissa), S11 its bare count of one as one recipe; S10
refuses a marinade pick without a typed eaten share. The 16 normaliser
defects the dry run exposed became rules at zero requests ("for <purpose>"
salt, "back pepper", "warm tap water", a lone "boneless", the leaked "fluid
ounce(s)", a section line naming the parent's reserved part — two new rule
notes —, "green thai"), S7 counts a bare orange count beside its zest, and
23 reads land on cached answers. API: `child` and `candidates` gain
`section`, `host_title`, `state` and `pickable` (a section candidate carries
its totals; `other_section` lists only stored children); `?section=` on the
nutrition GET, the matches GET and the PUT; the PUT body's `section`; nine
422 texts from the approved copy delta; a section's totals per batch (basis
1); a section pick is line-local; the queue joins the host, lists a section
line as "{host} · {section}", and credits a section group to the parents it
would finish, the banner reading the same CTE (279 groups, Σ finishes 72 =
finishable 72). Replay (rp43, cache-only on snapshot 19; `scratchpad/v43/`):
the only calls are option A's 12 searches and 4 read details, to be spent by
the owner; 63 main rows differ from v43 (57 rule rows routed to a section,
3 A9 routes, 3 salt rows), no person's row; buckets 13,336 / 214 / 17 / 13
/ 35; complete 935 → 976, partial 263 → 222; the 51 → 12 (3 wait on option
A, 9 never); +76,418.6 kcal per batch; sections 121 complete / 19 partial
(13 waiting on option A). The app (the approved copy delta
`docs/mockups/v44-sections-copy.html`, a delta to the v41 mockup): section
candidates pickable by (slug, section) — two own sections share one slug —
with their state in the right column ("no totals yet" / "no ingredients
listed" / "made from another recipe"); the routed row's " · a section of
{host title}" suffix for another host's section; "Open the recipe's
matches" opening the section's own sheet (the basis row hidden there: the
basis PUT takes no section); the label's "{title} (a section of {host
title})" and the `no_ingredients` partial line and row note; the retitle
note naming the old title and its host; the queue row "{host} · {section}"
and a section-aware queue key; the marinade share gate. Fixtures: 30
searches and 14 details copied from snapshot 19. Pins: the three server
files (storage, sections, api) and the app's `nutrition_sections_test`;
verifier rounds server 3 (two closers), app 4 (three closers: every defect
a missing pin over correct code). The delta's §5 example draws the section
before its host, against its own rule; the app follows the rule and the
golden. Server a18da27, app (this commit). Not swept live until option A is
spent on a scratch copy (snapshot 20) and its answers seeded.

## Decision log (deviations & clarifications)

- **2026-10-09 — matcher v65 (batch M66): coat parts and dips — the
  gated nut or cheese layer joins the coat, the dip sized by the coated
  food, a dip line's part used elsewhere, the shared-head split, dips
  alone open a budget, the alcohol and batter basis texts (prep49 §2 M66;
  Q5, Q7, Q8; built under the standing authorization; the owner's Q7
  ruling applied without a deploy gate; reach labelled pre-Q18).** A nut
  or cheese layer that a step mixes into a crumb coat now joins the coat's
  budget (gated on the crumb word in the same sentence, so a Parmesan
  crust with a flour binder stays held); an egg dip is sized by the
  coated food's own breading figure rather than the smaller of that and
  the counted carbohydrate; the printed part of a dip line a later step
  uses elsewhere counts whole; a shared head is split by its own modifier
  word; a recipe with dips but no counted coat still opens a budget; the
  three fried-batter alcohol rows name USDA's missing frying row and the
  fifteen batter rows say which breading figure is applied. Disclosed and
  pinned: three recipes turn complete because the released layer was
  their only uncounted line (the design said none would); four figures
  land 0.01 off the design's rounded fractions; "orange zest" is read by
  its last word as well as its head. 33 rows (18 in grams or hold, 15 in
  basis text), +536 kcal, three holds released and one added.

- **2026-10-09 — the owner's rulings on the prep49 design's three open
  questions (the other twelve decided under the standing authorization as
  recommended; `.claude/diag/2026-10-09/prep49/design_v2.md`).** Q2, the
  home-corned briskets: option (c) for both — they stay on the fresh
  0-inch flat and a flag states that the steps cure and rinse the brisket
  and the cure's sodium is not counted (CP9's rinsed cure 0 g and the
  brine co-solute ruling kept literal); M68 becomes the whole brisket at
  its printed trim plus two flags. Q7, the one-way door on person
  decisions: accepted without a count-before-deploy gate — no one is
  using the app and will not for some time, so changes are not limited by
  an established user base; a Confirm on a reached coat, dip or dough row
  reads the engine's share, and the pins state the new meaning. Q11,
  manufacturer labels through FDC Branded records: accepted as a standing
  rule — a label supplies grams for a size or volume the corpus line
  prints (the 8-inch wrapper, a per-piece candy, a per-volume pectin
  serving), never composition and never an unprinted size; the reads are
  one-off requests in the live step and the engine's search never
  includes Branded on its own.

- **2026-10-09 — matcher v64 (batch M65): landings on records the cache
  already held — jarred Morello cherries, corn husks, kombu, gel food dye,
  ricotta salata on feta (prep49 §2 M65; Q14; built under the standing
  authorization).** A volume line whose tail reads "from N (W-ounce) jars"
  now weighs its volume rather than the jars' printed weight, which lets
  the long-commented Morello landing ship (the cobbler's cherries 680 →
  1,344 g on the drained sour-cherry record, +564 kcal, the recipe
  complete); corn husks join the non-food class (tamales complete); kombu
  reads the dried-seaweed record, still strained to 0 g; gel food dye is a
  zero-nutrient flavouring; ricotta salata, which FDC does not hold, reads
  feta flagged with feta's sodium and fat (two recipes complete, +526
  kcal). Six rows, +1,090 kcal; four recipes partial → complete; no person
  row. Noted for a later batch: a can count written as a word with no
  paren ("from one 28-ounce can") still counts the whole can.

- **2026-10-09 — matcher v63 (batch M64): corpus prints — kosher salt at
  half table salt's weight, the set-aside pear half, "remove the bay
  leaf", the pour-off window, the fried-shallot oil yield (prep49 §2 M64;
  built under the standing authorization; the step readers' reach
  labelled pre-Q18).** Kosher salt's density was a round kitchen figure;
  the corpus prints "1 tablespoon kosher salt or 1½ teaspoons table salt"
  and the SR table-salt portion gives 6.0 g a teaspoon, so kosher salt now
  weighs half of table salt by volume (90 rows, 0 kcal, about 59 g of
  sodium less across the library; flake and coarse sea salt keep the old
  figure under their own names). A step that sets aside a pear half "for
  other use" counts the rest; "remove the bay leaf" zeroes the leaf (bay
  only — the same verb on peppers or garlic would zero eaten food); a
  pour-off now binds to the last oil-naming sentence before it, not only
  the step before; a section whose yield prints its oil in and out ("2
  cups" in, "about 1¾ cups" out) keeps the printed difference as eaten,
  flagged approximate; a "remove solids … and discard" sentence is read
  as a strain. Disclosed and pinned: a routed parent's spice-rub salt moves
  with its section (one row beyond the design's count, 0 kcal); the
  shallot parent lands 0.01 g off the design (the stored section total is
  one decimal); the strain reaches the lemongrass only (galangal is not a
  strained head — left as a gap). The verifier's three closer rounds were
  text and two synthesized edge cases (a printed yield beside an
  oil-absorbing food would have counted the oil twice). 127 rows, +243
  kcal of row energy, no status, hold or person-row move.

- **2026-10-09 — re-calibration on v62 and blind audit 4 (snapshot 25) —
  the prep48 series' exit measurement.** Audit 3's 25 hand-counted recipes
  re-measured on the v62 library: median error 8.7 → 6.9 %, mean 10.7 →
  7.6 %, the engine's bias +4.9 → +1.1 %, 18 of 25 within ±10 %
  (`.claude/diag/2026-10-08/recalibration_audit3_v62.tsv`). Audit 4
  (`.claude/diag/2026-10-09/audit4/report.md`; 232 lines — the eight
  batches' 130 moved rows plus 102 controls, two blind auditors per chunk,
  adjudicated; 25 fresh batch-heavy recipes hand-counted): the counted
  food is right on every counted line; the meat-record, strained-liquid,
  reserved-oil and pita/crab/sirloin rules audit with no mass error; the
  errors concentrate in the batter and dip shares (batters 50 % high at one
  breading ratio; the read wet share undersizes dips on nut and panko coats)
  and in the held coats, every one of which the auditors would count
  (17 of 17, ≈ 1,210 kcal in the sample); the largest kcal pattern is a
  right-grams wrong-state record (the brisket priced at 0-inch trim where
  the auditors want ⅛ inch, a home-cured corned beef priced fresh, a vegan
  mayonnaise on a light product). Calibration on the 25 hardest recipes:
  median 11.1 %, bias +5.8 % (fried doughs +19.9 %: the doughnut uptake
  charged on the whole dough where two thirds is cut). These findings feed
  the next design round; no rule changed in this entry.

- **2026-10-09 — matcher v62 (batch M63): the 8-inch pita by FDC's
  per-area portion, the crab cake's own oil, the sirloin stand-in flag,
  the rack's retired hit read (prep48 §2 M63; Q3, Q6, Q11, Q16; the live
  step L's records; built under the standing authorization).** The SR pita
  record names only 4-inch and 6½-inch pitas, but the FNDDS pita the rows
  sit on carries a "1 surface inch" portion of 2 g, so a line printing an
  8-inch pita now weighs the record's own portion times the printed
  diameter's area (100.53 g each, flagged "derived", the baguette
  precedent) — the owner's ruling over the design's demand for a portion
  naming 8 inches, which predates the read; the unnamed "large" 85 g is a
  stated alternative (four rows, +1,676 kcal). The crab-cake record lists
  its crumbs as a binder, so no coat figure follows and the stand-in
  suffix stays; its own frying oil (5 g per 65 g of crab) is read as a
  crab arm (one row, +41 kcal). FDC has no lean-and-fat petite sirloin
  roast, so the three rows keep the lean-only record with an explicit
  stand-in flag. The rack of lamb keeps its Australian record, byte-equal,
  and the search-hit workaround is retired now that its detail is cached;
  the domestic rib is rejected as an unfrenched cut of different
  composition. The plan's two late text defects (a test-count touch, a
  wording) were fixed by hand; the fixer keyed the per-area map to the
  record's id rather than a description prefix, so a person's pick of
  another pita record keeps its own weighing. Eight rows, +1,717 kcal per
  batch, no status, hold or bucket move. This closes the prep48 series
  (M56–M63); re-calibration and audit 4 follow.

- **2026-10-08 — matcher v61 (batch M62): egg dips sized by the read wet
  share, held-coat dips held, no crumb rule (prep48 §2 M62; Q9; the live
  step L's breading record; built under the standing authorization; reach
  labelled pre-Q18).** The FNDDS "breading or batter" record (flour 125 g,
  crumbs 25, egg 15, water 120) confirmed the coat budget's carbohydrate
  constant and gave the dip's size: 1.17 g of wet dip per gram of coat
  carbohydrate. Egg and buttermilk dip lines whose sentence says the excess
  drips off are now sized by that share on the recipe's own coat budget
  (28 rows, −1,414 kcal), the coat parts' split unchanged — the owner's
  ruling in place of the design's "dips join the coat's one fraction",
  which was measured too (45 rows, −1,488) and lands farther on four of
  five calibration recipes. No crumb rule: the record's crumb share drives
  crumb lines further down, against the audit, and the pork-crumb stand-in
  overrides chicken's own read coats; the eight low crumb coats stay a
  stated gap. The dips of a held coat take the coat's hold (nine rows, −647
  kcal counted; the design's tenth is beyond the line rule's reach); a
  person's Confirm on one counts 0 g, a pick keeps the hold, typed grams
  stand. Two no-coat recipes gain the left-in-bowl flag only. The verifier
  found the compute re-planning the coat budget once per person-confirmed
  dip (16 s at the editor caps) and the GET once per confirmed no-coat dip;
  the closer gave every M52 kind one compute-scoped plan keyed on exactly
  the rows the plan reads, invalidated by any cache write, proved exact by a
  seven-mode whole-corpus oracle. Forty-four rows, −2,060 kcal per batch, no
  status move, nine new coating holds.

- **2026-10-08 — matcher v60 (batch M61): fried doughs, fritters, rolls
  and falafel take an uptake (prep48 §2 M61; Q12; the live step L's
  records; built under the standing authorization; reach labelled
  pre-Q18).** A frying oil whose recipe fries a named product (pakoras,
  lumpia, falafel, doughnuts, struffoli, a bare batter or dough) now
  carries the oil that product absorbs, read from the USDA record for its
  class on the raw mix before the oil (the dipping sauce and the glaze
  excluded). Figures decided by the owner from the planner's verified
  arithmetic: the pakora, egg roll and plain fritter records by the
  design's formula (the latter two flagged stand-ins for lumpia and
  struffoli); the yeast doughnut derived by a protein balance on its own SR
  doughnut record, because both FNDDS doughnut records list no oil input
  and the design's fallback would give nothing; the falafel derived by a
  carbohydrate balance on the SR home-prepared record, because the FNDDS
  falafel lists a whole cup of frying oil as an input (a 60 % reading that
  is the medium, not an uptake). Beyond the design, disclosed and pinned: a
  roll takes its figure only when the mix counts a pork, beef or chicken
  row (the meatless record was never read); a dough reads the yeast
  figure only with a yeast row, else the fritter; the verifier found M61
  opened the shipped matches GET's quadratic re-planning to a new shape
  (636 s at the editor caps), so the GET now plans once per request on
  both its paths and the skin sentences are read once per recipe, with
  cost pins. Five rows, +5,107 kcal per batch, no status move.

- **2026-10-08 — matcher v59 (batch M60): the bone-in turkey breast, a peel
  written in the steps, bacon that drips (prep48 Y + P7a + P7b; Q14 a,
  Q15 a; built under the standing authorization; P7a and P7b reach
  labelled pre-Q18).** ATK's bone-in turkey breast reads a figure derived
  from USDA AH-102 (the breast's meat and skin, 87 % of its 33 of 43 parts
  of the breast-plus-rib retail cut, 66.8 %) in place of the chicken class
  figure (eight rows, +2,319 kcal); a produce line whose tail prints no
  prep word reads the record's peeled figure when a step pares it (three
  rows, −351 kcal); bacon laid over or wrapped around a food and then
  baked, roasted, grilled or broiled keeps no fat (two rows, −1,275 kcal;
  the oven-fried bacon waits for its missing steps, Q18). Deviations from
  the design, disclosed and pinned: a line saying "unpeeled" never takes
  the step read (the shipped "never unpeeled" promise); the drip rule is
  recipe-wide, as bacon's kept-fat signal is; the paring and bacon readers
  were rebuilt as one-pass token scans with per-recipe memos after the
  verifier measured the first build at seven seconds a line at the editor
  caps; a synthetic whole-bird line on the breast record now reads AH-102's
  whole turkey rather than the deleted class figure. One figure lands
  0.01 off the design's (rounded replay grams). The design's Q14 miscounted
  the recipes that cut the back away (five of eight; the corpus says six),
  corrected in API.md. Thirteen rows, +693 kcal per batch, no status move.

- **2026-10-08 — matcher v58 (batch M59): the frying oil the steps keep or
  rinse off, and a battered vegetable's uptake (prep48 C + F1 + D; Q13 b;
  built under the standing authorization; reach labelled pre-Q18).** A
  frying oil's "reserve N tablespoons frying oil" is a kept part only when
  a later sentence heats the reserved oil (two recipes); the ¼ cup
  fish-and-chips tosses with its fries and then drains and rinses is not
  eaten (CP9's rinsed-cure precedent, 0 g); the fried cauliflower's read
  uptake scales to the carbohydrate its ingredient group holds against the
  FNDDS recipe's batter (c_b 0.40 from the six read breadings), flagged
  "derived". Deviations from the design, disclosed and pinned: F1 sits
  where the engine reads a frying oil's eaten part, not in the fat's
  one-sentence pour-off reader (the kept part is the line's "plus ¼ cup",
  not a sentence); F1 matches no food — the step stands in for the tossed
  one (0255's rinse names none); its basis names a kept pour-off beside the
  uptake and never the rinsed part; D reads a batter left in the bowl (M58
  W) at its whole line grams on every path (the plan writes those rows
  `discarded`, so the stored row read nothing after the first compute — a
  non-idempotent compute the verifier found; no corpus row reaches it). Two
  figures land 0.01 g off the design's (rounded replay grams, as for v57).
  Four rows, −578 kcal per batch, no status move.

- **2026-10-08 — matcher v57 (batch M58): a batter left in the bowl joins
  the coat budget (prep48 W + S; Q8, Q10; built under the standing
  authorization; reach labelled pre-Q18).** The M50 Q21 lines reached
  through the dip word "batter" are now parts of M52's coat budget at one
  fraction per mixture, battered shrimp on its own FNDDS fried-shrimp figure;
  glaze and confection coats stay whole (negimaki's flag states its printed
  split). Kept additions, disclosed and pinned: a person's Confirm of a
  batter line keeps the plan's grams and is written `discarded` (the shipped
  Confirm rule for coats); a batter part below the confidence gate is left
  out of the carbohydrate sum (no corpus row reaches it). Three pins land
  0.01 g off the design's figures because the planner worked from rounded
  replay grams. Twenty-six rows (17 moving grams), −1,376 kcal per batch,
  no status move.
- **2026-10-08 — matcher v56 (batch M57): a strain of "the liquid" whose
  solids nothing uses (prep48 S1; Q19 NO; built under the standing
  authorization; reach labelled pre-Q18).** The one strained-solids case
  M50's readers missed: "strain the (braising/cooking/poaching) liquid"
  counts as the strain only when no later sentence uses the solids. Kept
  deviations, disclosed and re-measured: the arm is its own regular
  expression (a shipped name collision; the guard and the never-null scan
  need it); a 'solids' widening is an equivalent mutant by construction
  (the guard includes the strain sentence), re-spelled and killed. Four
  rows, −591 kcal per batch, two recipes' kcal per serving; the short ribs
  land at +14.3 % against the calibrator (the prunes stay counted by the
  recipe's own words).
- **2026-10-08 — matcher v55 (batch M56): meat records at the right animal,
  cut and fat level (prep48 Q1–Q7; built under the standing
  authorization).** Kept deviations, each disclosed and re-measured: (1)
  the rack of lamb's record 174414 has no cached detail and the engine would
  have fetched it (one request, the recipe blocked), so a narrow
  `ah102MeatsOnHit` reads the AH-102 row from the search hit for that key
  alone (the broad form broke a v11 pin and three goldens); the rack counts
  on the hit's nutrients until its detail is read at the live step; (2) the
  verifier found two DOMESTIC lamb rib records cached (SR 174377 at 342
  kcal/100 g, 1/8" choice; 174321 1/4"), contradicting the design's premise
  that none was — they sit only in unrelated answers, so M56 stands on the
  Australian 174414 as decided and the live step gains a named search and
  detail to let M63 decide the rack's record (+44 % on that row if domestic);
  (3) R1e's rank words tie Foundation 2646168 with the tenderloin 2646169
  at 1.0 and FDC's order breaks the tie (pinned; the known FDC-order
  ceiling); (4) the verifier's round-4 finding was two comments claiming
  facts the cache contradicts — fixed by hand as worded. The library moves
  −3,992 kcal per batch on 26 rows, grams unchanged, no status move.
- **2026-10-08 — Q18 SKIPPED for this session (the owner: the focus is the
  matcher, not corpus completeness).** The extraction left 269 of the 403
  subsections that carry ingredient lines (in 160 host recipes) and 26
  whole recipes without their direction paragraph, although the EPUB prints
  it (the pupusas' Curtido: "Toss slaw, then drain" is in the book, not in
  the YAML). This is a corpus-completeness gap, not a matcher defect: no
  step-reading rule can fire inside such a section, so its lines count on
  the ingredient data alone. The batches proceed unchanged, each
  step-reading commit labelled "pre-Q18"; future audit samples mark lines
  in step-less sections "no steps in the corpus" so they are not scored as
  engine errors. Reopen when the corpus is re-extracted (the guards of
  design_v2 §1 Q18 apply then).
- **2026-10-08 — the prep48 design pass on audit 3's patterns
  (`.claude/diag/2026-10-08/prep48/design_v2.md`; five planners, a critic
  with 16 findings all folded) — the owner questions DECIDED under the
  standing authorization, every one as recommended except Q18, which is the
  owner's:** Q1 strip steaks and the top loin roast on Foundation 2727572
  (a); Q2 brisket on the raw flat 168743, pomegranate|0 flagged as a
  stand-in for its printed ¼-inch cap, the trim-depth item deferred; Q3 the
  rack of lamb on 174414, listed as a gap; Q4 thighs stay Foundation; Q5
  the boneless center-cut pork loin on Foundation 2646168 (a); Q6 one
  search for a lean-and-fat top sirloin; Q7 "fat caps removed" → 171751,
  contingent on Q1 (a); Q8 batters budgeted by carbohydrate, battered
  shrimp on 2706364; Q9 read FNDDS "Breading or batter" first, then the egg
  dips, the held-coat dips (H — a one-way door, taken: a dip of a held coat
  is held) and the crumb figure together; Q10 glaze and confection coats
  stay whole; Q11 read the crab-cake record; Q12 the fried-dough uptake
  with 14 named requests and every conditional request named and approved
  before it is spent; Q13 no C2 oil on the browned-then-baked rolls, the
  cauliflower scaling on O5 only and flagged derived, the shell-on shrimp
  keeps the squid figure; Q14 the bone-in turkey breast at 66.77 %, derived
  from AH-102 items 2591 and 2593 (the breast's 33 of the breast-plus-rib
  43 parts × 87 %), the back not counted; Q15 bacon draped over or wrapped
  round a baked or grilled food takes B1's cooked part with no kept fat;
  Q16 the 8-inch pita only on a printed 8-inch weight (one record read);
  Q17 leave the unsourced prep losses; Q19 NO 'prune' in the strained
  heads (the corpus says they melt into the sauce); Q20 the 51 below-gate
  rows (36 recipes partial on one each) are a later item. **Q18 — DEFERRED
  TO THE OWNER:** re-extracting the direction paragraphs of 269 subsections
  (160 hosts, 152 person rows) in the Recipe Extraction project, with the
  critic's guards (a dry-run diff proving every ingredient line byte-equal;
  a pin that the person rows survive; its own attributed replay); until
  then every step-reading batch is labelled "pre-Q18". Build order: M56
  meat records → M57 strained liquid → M58 batters → M59 reserved and
  rinsed oil and the cauliflower → M60 turkey breast, step peel, bacon drip
  (all zero requests, −5,844 kcal in all) → the live step L (23 named
  requests) → M61 fried doughs → M62 dips and crumbs → M63 pita, crab cake,
  sirloin. Not a defect, closed: the EVOO energy fallback; held two-part
  bacon rows do enter totals.
- **2026-10-08 — BLIND AUDIT 3 on the deployed v54 library (snapshot 23;
  `.claude/diag/2026-10-08/audit3/report.md`; 272 lines drawn from the
  prep47 batches' reaches plus controls, two blind auditors per line and an
  adjudicator per chunk; 25 NEW recipes recomputed by hand).** Counted food
  WRONG 1 of 212 (a beef top loin roast on the pork top-loin record); once
  the bacon stratum is set aside (a sampling artefact: the blind sheet showed
  the two-part rows' raw record, not the cooked bacon and grease the engine
  counts — re-costed on the parts, 7 of 10 within 1 %), state WRONG 1.5 %,
  should-have-counted 4 %, mass LOW 5.7 % and HIGH 11.1 %; the alcohol
  (40/40), shellfish (7/7), density and portion lines carry no mass fault;
  discards right on 38 of 40. Ranked patterns by kcal: P9 wrong cut or fat
  level on four meat records (−2,084: pork for beef; "lean only" for a
  trimmed strip steak and a blade roast; the frenched lamb record); P1 the
  M50 Q21 lines flagged "excess left in the bowl" counted whole — 13 of 16
  HIGH at 1.9× (+1,355); P3 deep-fry oil at 0 on fritters and wrapped rolls
  (−1,226); P4 four uptake percentages off; P2 all eight bread and panko
  crumb coats LOW at 0.44× (the USDA breading ratio against the auditors'
  pressed layers — a USDA-vs-judgment gap); the turkey-breast yield 0.61
  8 % low on four lines (inside tolerance, −1,173); P7 printed weights with
  a printed prep loss. Calibration on the 25 new, batch-heavy recipes:
  median |diff| 8.7 % (51 kcal a serving), the engine +4.9 % high (14 high,
  11 low), driven by meat fat-level records, strained solids the hand count
  excluded, and the whole-counted wet coats. Not a defect: the EVOO record
  748608 carries no energy nutrient but the engine's fallback counts 9 × its
  fat (843 kcal/100 g) on all 251 rows. NEXT: the prep48 design pass on
  these patterns (five planners, a critic), then batches on snapshot 23
  against the v54 rows.
- **2026-10-08 — RE-CALIBRATION after the prep47 series (audit 2's 25
  hand-computed recipes against the v54 replay on snapshot 22;
  `.claude/diag/2026-10-07/recalibration_v54.tsv`).** Median absolute error
  per serving 6.3 % (v46) → 2.7 % (v54) over the 25; like for like (without
  R12 and R15, whose hand figures are of a different dish) 6.3 % → 2.2 %,
  mean 13.9 % → 4.9 %, signed mean −3.7 % → +1.0 %. The design forecast
  2.7 % / 9.6 % / 0.0 %; measured 2.7 % / 9.8 % / −0.3 % on the 25. The
  largest closures: the plum pie −72.7 % → +1.3 %, lemon meringue −44.9 →
  −1.0, the crispy Thai eggplant −45.9 → −3.9, panna cotta −16.5 → +1.8,
  the beer-can chicken +13.1 → +0.1, salade lyonnaise +22.1 → −9.3. Left
  as ruled: R03 +14.1 % (the optional salsa counted by the ruled practice
  for optional lines with an amount), R06 +26.1 % (the satay marinade the
  hand count took at a share; the engine counts it whole, flag only), R15
  +51.2 % (the rice the hand count left out of "Red Beans and Rice"), R12
  (the hand figure is the plate, the engine's the sauce). Eleven of the 25
  are within 2 %.
- **2026-10-08 — matcher v54 (the Q25 alcohol batch): ethanol energy
  reduced by USDA retention factors read from the line's cooking shape
  (design_q25_v2.md; the owner's decisions Q-a..Q-h of 2026-10-07; built
  under the standing authorization).** Energy-only: no record, grams,
  status, bucket, hold, child or part moves. OWNER CONFIRMATION at the gate
  (design §0; closer 1's ruling, the verifier's round 1): the fixer stopped
  with 4 of 255 rows off the amended table, and five rows are amended from
  the corpus text by the brief's own rules — shrimp-scampi|5 85 (Q-f's exact
  shape, left off the Q-f list), modern-beef-burgundy|9 17.92 (the split
  weighted volume by volume), broiled-chicken-with-gravy|11 40 (the stock is
  strained into a bowl before the roux), strawberry-rhubarb-pie|5 35 (the
  55-minute bake at the range's low end), summer-peach-cake|1 the 29.0 %
  split — net −17.8 kcal per batch; beef-wellington|14 and the
  tenderloin stuffing stay at the table's 85 (a roast taken to rare never
  simmers; the layer-into-bake precedents are dishes baked bubbling or set;
  roundings err toward more kept). The final table is archived as
  prep47/q25_factors_v54_final.tsv. The library loses 14,584 kcal per batch
  on main rows (sections −1,094; parents −1,042) across 201 recipes, kcal
  per serving only; the largest −132 a serving (daube provençale). Noted:
  mahogany-chicken|2 (held) reads 56 minutes where design P35 said 55, the
  same 35 %; one equivalent mutant stated (a clause no corpus row reaches).
  Closes the prep47 series: M53, M48, M47, M50, M49, M51, M55, M52, Q25.
  NEXT: re-calibration against audit 2's hand figures, then a second blind
  audit, then the deferred widenings (the pour-off window, marbella's oil
  binder, D5's spelling, the kombu record).
- **2026-10-08 — matcher v53 (batch M52): coats and frying-oil uptake on
  the READ FNDDS figures (prep47 Q2 (a), Q3 (a), Q24 (b); built under the
  standing authorization).** RE-RULES CP9 Q2 and the 2026-10-03 (1) held
  dredges, and amends the discarded-media zero for frying oil. Every k and u
  is the figure of p3_read_figures.md (the inputFoods read at M53/M55 with
  a protein-conservation raw basis); the SR analytical shapes stay derived
  and are flagged so. OWNER CONFIRMATION at the gate (closer 1's ruling,
  the verifier's round 1 D2): the brief's Q24 gate said "exactly four oils
  plus two cascade rows" but the data gives FIVE oils and ONE cascade row —
  best-chicken-parmesan|19 meets the trigger as worded (coated cutlets
  browned in ⅓ cup oil) exactly as chicken-katsu does, and
  easy-salmon-cakes|0's panko is not a shipped dredge (and would land at
  the same grams held); the trigger is the rule, the design's list was a
  search result. Other kept deviations, each disclosed: budgeted coat rows
  are written `gram_source: discarded` so the recompute finds the plan's
  rows (grams unaffected); easier-fried-chicken|8 reads C2 by the last-cook
  rule (45.60 g, not P3's C1 82.0); fish-and-chips|1 lands a different oil
  record on a fresh DB than in the snapshot (the uptake the same). The
  library gains +18,400.6 kcal per batch on 70 rows; 16 recipes complete
  (1,006 → 1,022); the coating holds fall 51 → 20. Unpinned because no
  corpus row reaches them: the wing coat k 5.66 and eight record fields no
  flag prints. DEPLOY FINDING: the live DB still carried snapshot 20's
  caches (never seeded with snapshots 21 and 22) — the M47 sibling reads and
  every v53 coat figure need those details, so the live caches are seeded
  from snapshot 22 (INSERT OR IGNORE, the key untouched) before the v53
  sweep; the v49–v52 sweeps ran at 0 requests on search-hit nutrients where
  a detail was missing, which the bucket comparison cannot see — the v53
  sweep's full recompute settles every row on the detail figures.
- **2026-10-08 — matcher v52 (batch M51): references with no amount, server
  + app (prep47 Q8, Q8b, Q9, Q22, Q15 (iii); built under the standing
  authorization; both copy deltas approved 2026-10-07).** RE-RULES prep41
  A3 (a) and CP3 for these lines: a served-with reference is accounted (0 g,
  the label says "Served with {name} — not counted."), a whole-batch
  reference routes at share 1.0 flagged, a prose variation routes to its
  base flagged. Kept deviations, each disclosed and re-measured: (1) D7's
  title rule is served by the shipped resolver order's own served-with
  answer, not a marker arm (no corpus line could test one); (2) the
  served-with `name` is the first alternative, as the mockup prints it;
  (3) the group headings of a recipe with a reference fold into its hash
  (SW reads CONDIMENTS) — no library hash moves today; (4) RA1 needed no
  code (v49's rank-as; WB makes the coulis a child, so its line is read).
  The verifier's round 4 found two LOW documentation defects — the
  matcherVersion doc entry inverted the amount scope of PV and D7 (PV
  applies to lines WITH an amount; D7 with or without), and API.md labelled
  Foundation 2512381 "SR" — fixed by the owner by hand as worded, comment
  and docs only. The library gains +7,113 kcal per batch on 5 main rows and
  11 new section rows (sections 140 → 143); 9 recipes complete (997 →
  1,006); the partial-with-nothing-to-review count is 0. Noted: a PV
  answer can move only when a host's section is added or renamed (the
  shipped resolver-index class); a person's typed share of 1 on an
  amount-less routed line carries the WB flag.
- **2026-10-07 — matcher v51 (batch M49): the bacon package and fat poured
  off to a stated amount (prep47 Q4 (b), Q19 (a); built under the standing
  authorization).** RE-RULES Y11 (2026-10-06 "bacon keeps 0.403") — the
  cooked yield is USDA AH-102 item 1981's 0.33 (18–43) — and v40's "the
  wider bacon lines a person's", amended by the slice weight only (28 g,
  FDC 168277's slice; thick-cut 35.44 g, the median of the corpus's three
  prints, flagged; Canadian 28.5 g). Kept deviations and owner items, each
  disclosed and re-measured: (1) a kept amount is weighed as the library
  weighs a line of that amount (1 tsp oil 4.53 g, 1 tbsp 14.00 g), so two
  pins land 4.53 / 23.07 against the brief's volume-scaled 4.7 / 23.3
  (≈ 2 kcal); (2) the pour-off cap reaches 4 browning oils, not P1's 7:
  skillet-jambalaya|2 is right uncut (its other 3 tsp go in after the pour-
  off); crispy-skinned-chicken-breasts|2 sits outside the design's window
  (oil in at step 2, pour-off at step 4; widening would take −168 kcal —
  LEFT, a later widening if wanted); chicken-marbella|12's "Heat oil"
  binds neither of its two oil lines (a group-aware binder could cut it,
  −41 kcal — LEFT: uncut errs toward counting eaten oil); (3) a non-whole
  piece weight of 10 g or more prints its figure in the basis (2 rows,
  basis only). The library moves −2,328.5 kcal per batch on 35 rows, no
  status, hold or bucket move; M50's four cured-pork rows byte-equal.
- **2026-10-07 — matcher v50 (batch M50): discards and partial use (prep47
  Q16, Q17, Q18, Q20, Q21, Q7's flag; built under the standing
  authorization).** AMENDS the 2026-09-28 "poured-away media HELD" ruling:
  strained solids and removed whole aromatics are 0 g, flagged (CP9 Q4's
  partial pour-away stays HELD). Kept deviations, each disclosed and
  re-measured: (1) cuban-style-black-beans-and-rice|4 and |5 are
  PARTITIONED (178.50 g, 1 of 4 halves; 75.00 g, 1 of 2) rather than the
  design's "at 0" — the corpus text under the Q18 count-partition ruling,
  the verifier concurring; (2) sprig lines are not skipped: a 0 g sprig row
  in a strained pot or a discard moves from `unmeasured` to `discarded`
  with the M50 basis (≈ 40 rows, 0 kcal); (3) Q21's flag follows P1's
  "excess egg/batter/glaze" spelling — 18 lines in 9 recipes; the same
  breading shape without the noun ("allowing excess to drip off", about 15
  to 18 recipes) stays counted unflagged — a later widening if wanted, 0
  kcal; Q7 flags 4 recipes (beef-satay prints no removal sentence); (4) the
  Q18 basis is the design's flag text; (5) the gnocchi figure reads the
  potato detail's carbohydrate (551.32 g; a cold line would read 550.43);
  (6) french-omelets|2 not built (the design dropped it). The library moves
  −14,714 kcal per batch on 333 rows (203 zeroed, 117 flag or basis only),
  5 recipes complete → partial for holds a person must answer, 6 new
  holds. Noted for later: nikujaga|1 kombu leaves the check queue at 0 g on
  a wrong below-gate record; a person-decided 0 g row on an M50 line reads
  the shipped "poured away" text. Environment: the ATK corpus checkout
  carries another session's uncommitted removal of the dessert tags (HEAD
  has 214 dessert tag blocks, the working copy none) — 28 tag tests fail on
  the live corpus on any tree; the gate ran the suite on a clean archive of
  the corpus repo's HEAD; not M50's and not touched.
- **2026-10-07 — the owner approved the two-part-row role copy delta
  (`docs/mockups/v49-two-part-rows-copy.html`, "i approve M51"):** the
  headers and part suffixes ship verbatim — bacon unchanged; zest and juice
  "matched to two records, the zest and the juice:" with " · the zest" /
  " · the juice"; a can drained and a can kept with its liquid "matched to
  two records, drained and with its liquid:" with " · drained" / " · with
  its liquid"; any other pair the plain header. Keyed on the part's `role`
  from the wire. Rides with M51's app half (one app commit for both deltas).
- **2026-10-07 — matcher v49 (batch M47): records and published figures
  (prep47 Q5, Q6, Q11–Q15, Q23, Q26; built under the standing
  authorization).** Kept deviations, each disclosed and re-measured: (1)
  'jarred hot cherry peppers' reads its record by RANK-AS, not the brief's
  rewrite — as a rewrite key the phrase broke the rewrite-target stability
  invariant for the four Thai-chile rewrites that read that cached answer,
  so those four became rank-as reads with the same landing (byte-identical
  rows); a person's "Search live" on a Thai chile row now re-asks the
  pickled answer, as 'thai' and 'green thai' already did; (2) the Q23 veto
  reaches 8 rows (5 curry paste, 3 Old Bay), not the 3 section rows the
  brief named — P6's measured reach; (3) the tapioca density rides the
  shipped precedence (a key outside `_recordFirstDensities` outranks the
  record's own cup) — the fixer's report named a third set that the final
  tree does not have, caught by the pre-commit symbol grep; (4) the kiwi "large" flag uses P6's wording (the brief
  gave none); (5) the `in_shell` hold has no corpus vehicle after v49 —
  tests and the rules contract sample use a STATED synthesized "1 pound
  oysters, scrubbed"; (6) the APP changed in a "server only" batch: the
  two-record copy "matched to two records, cooked and drained:" is now the
  bacon's only (role `kept_fat`); a zest-and-juice or half-drained can row
  reads "matched to two records:" — an interim guard against a mislabel,
  not new copy; role-specific wording is a later mockup; (7) the owner's
  ruling on the open item: pasta-e-fagioli|14 sat below the gate at 0.0125
  after its sibling lifted the hold, so 'pasta such as ditalini' reads its
  own cached answer under "pasta dry enriched" (SR 169736, the right food,
  no flag): +841.41 kcal, 17/18; the batch lands 61 rows, +926.9 kcal. Noted for later: palak-dal|9 "15 curry
  leaves" on "Beef curry" (0.465, check) is outside Q23; two `withParts`
  guards (typed grams, held rows) have no real path and stay unpinned.
- **2026-10-07 — the owner approved the M51 references copy delta
  (`docs/mockups/v51-references-copy.html`, "i approve the M51 copy"):**
  the three new strings ship verbatim — the label's non-partial line
  "Served with {name} — not counted."; the whole-batch row flag
  "approximate (no amount on the line — the whole batch counted)"; the
  prose-variation row flag "approximation (counted as {base title}; the
  variation's changes are not read)". M51 builds the server and app halves
  in one run and ships them as two commits (the v44 precedent).
- **2026-10-07 — matcher v48 (batch M48): every printed weight range reads
  its midpoint (prep47 Q1 = (c), re-ruling checkpoint 9 Q5 "upper bound in
  parentheses, midpoint bare" and B2's 2026-07-28 "won't fix, upper bound
  intended"; built under the standing authorization).** Kept deviations
  from the brief, each disclosed by its author and re-measured by the
  verifier: (1) a spaced mixed number inside a parenthesis is folded
  ("(3 ½- to 4-pound)" → 3½; without it the regex read "½- to 4" and
  Pressure-Cooker Pot Roast landed at 2.25 lb — the only such line in the
  library, so the replay still moves exactly the forecast 200 rows); (2)
  the reversed-bounds guard lives in the one range reader, so a bare
  reversed amount, count or volume keeps the larger too (0 corpus rows;
  pinned on stated synthesized inputs); (3) the paren weight's bound token
  accepts an ASCII mixed number ("(3 1/2- to 4-pound)", as the editor
  prints it) — verify round 2's one defect, 0 corpus reach, closed with a
  pin; (4) **matcherVersion is 47, not 48**: the brief said "the v47
  commit's + 1" and the v47 commit kept 46 — from here the stamp trails the
  commit name by one, stated in API.md and the matcher doc entry (re-pinning
  the seasoning and chraime hashes for a cosmetic 48 was not worth a cycle).
  Known and left: "(1-1/2-pound)" (a HYPHENATED ASCII mixed number) reads
  1.0 lb — the reversed pair "1"–"1/2" keeps the larger — because the
  spelling is ambiguous with a range; no corpus line prints it. Deploy:
  the version bump stales every recipe; the zero-request sweep recomputes
  the library (185 recipes change kcal per serving, median −6.5 %).
- **2026-10-07 — M55, the live step for M52's figures, and the coat/oil
  figures RE-STATED on read FNDDS recipes (design_v2 line 404, critic F8;
  under the standing authorization for new live matches).** The M53
  `inputFoods` list COOKED meat for the chicken, beef and pork recipes (raw
  only for cod and shrimp), so P3's "raw food, coat, fat" could not be read
  off directly; the raw basis is now protein conservation between each
  recipe's named cooked ingredient and the raw record (USDA's own retention
  convention), and the coat's carbohydrate per gram (0.40) is read off the
  six recipes whose other inputs are cooked (0.397–0.401). M55 spent 20
  requests on a scratch copy of snapshot 21 (5 searches, one an HTTP 400 for
  a slash FDC rejects; 7 details with raw JSON — the baked breast and legs,
  the baked cod, the fried haddock, the fried cauliflower, the two skin-on
  fried records; the potato-chips raw answer, a bare SR pass-through) →
  **snapshot 22** (`.claude/diag/2026-10-07/snap22.db`, user_version 20,
  1,111 foods / 1,898 searches, key- and session-free; raw answers in
  `live55_raw/`); the running live total 117 → 137. The table is
  `.claude/diag/2026-10-07/prep47/p3_read_figures.md`: the chicken coats
  land on P3 to 0.02 (breast 5.73, thigh 6.10, wing 5.66 g carbohydrate per
  100 g raw), the beef coat rises (8.19 → 8.79), the fish and shrimp coats
  fall (17.55/23.7 → 15.38: P3 solved a 40 % batter as 77 % flour), the
  baked coats fall a little (chicken 3.63 → 3.18, legs 3.25 → 3.10, fish
  8.58 → 7.41; pork 6.42 → 6.61); the fragile oil figures move most: thigh
  9.5 → 7.11 %, beef 18.1 → 9.89 %, shrimp 23.6 → 15.38 %, cod 17.7 →
  15.38 %, the battered cauliflower 16.1 → 30.32 % (FNDDS's recipe is half
  batter by weight); skin-on parts stay 0 on a read fat balance (2705996
  adds 7 g oil per 100 g yet carries 17.2 g fat against 18.2–20.9 g in the
  raw skin-on legs the engine counts; 2705949's inputs are fast-food
  composites, no longer a basis). The SR analytical records (squid, fries,
  chips, plantains, tostadas) have no recipe and stay derived, flagged so.
  M52's brief (`scratchpad/batch17/v53_m52_brief.md`, archived) builds on
  the read figures only, with STEP ZERO = the M51 tree byte-identical on
  snapshot 22 (the one existing row on a new id, the broiled salmon's
  potato chips, kept its cached detail). Also written today for M51's app
  half: `docs/mockups/v51-references-copy.html` (the served-with label line,
  the whole-batch and prose-variation flags) — awaiting the owner's
  approval; the server half does not wait.
- **2026-10-07 — alcohol after cooking (prep47 Q25; the planner pass's
  design `.claude/diag/2026-10-07/prep47/design_q25_v2.md`; decided under
  the standing authorization):** an alcohol line's ethanol energy is
  reduced by USDA's Table of Nutrient Retention Factors, Release 6 (2007),
  food group 14, read from the line's own cooking shape in its recipe's
  steps — 85 % stirred into a hot liquid (code 5002), 75 % flamed (5003),
  40 / 35 / 25 / 20 / 10 / 5 % stirred in and simmered or baked 15 / 30 / 60 /
  90 / 120 / 150+ minutes (5004–5009); the non-ethanol energy (protein, fat
  and carbohydrate by Atwater) is kept; grams, records and statuses never
  move. The design's own questions: under 15 minutes reads 85 (no
  extrapolation below the table's first row); a cooking-time range reads its
  low end (a time, not the weight-midpoint ruling); the 70 % "stored
  overnight" row is unused (no line's printed minimum hold is overnight);
  covered braises and slow cookers read the open-pot rows (the table does
  not distinguish); vanilla extract stays out; the flag and basis strings as
  designed; the 45 % "not stirred, baked 25 min" row is dropped (no line
  reaches it; a pour-over reads 85); marinades, drained liquids and beer
  cans stay with the mass rulings. One decision AGAINST the design's
  recommendation: an alcohol stirred into a hot dish off the heat reads row
  5002's 85 %, not 100 % — the row's verbatim text is "stirred into hot
  liquid", and a published figure beats the safe side (seven lines, 66.5
  kcal in all). The transcription is
  `prep47/usda_retn06_alcohol.md`; the 16 alcohol records' raw answers
  (nutrient 221) came from the live step M54 (16 requests).

- **2026-10-07 — matcher v47, the sections-batch review fixes (the union of
  the dual-fleet review Runs 061 and 062; decided under the standing
  authorization; deviations kept):** (1) a person's section pick now keeps
  the section alive — the child set every reader shares is the engine's
  routes plus every decided pick whose host still carries the title; (2) a
  duplicate subsection title is refused on create, update, import and
  rescan alike (the brief had asked for a documented limitation on imported
  YAML; the validator is the import's and the scan's gate, and review B13
  forbids ingesting what the editor then refuses — kept); (3) a section's
  line that names its own host is a 0 g rule row with the new wire reason
  `self`, which the app shows as the raw code on a section's own sheet (7
  corpus lines, all in sections nobody routes to; the copy waits for a
  mockup); (4) bulk totals and counts count recipes only and the counts
  gain a `sections` figure — a scope whose only work is sections counts 0
  and the Settings button stays disabled for it (no label depends on such a
  section); (5) two recipes whose reference targets a prose section
  (lemon-meringue-pie, fresh-plum-ginger-pie) read stale once after this
  deploys, because their hash now folds the prose section — a zero-request
  sweep restores them; (6) client/server version skew across a deploy (an
  old browser tab picking a section with the pre-v44 payload) stays a
  documented gap: deploy both halves together and reload open admin tabs; a
  version handshake is a later design. No landing moves: the replay is
  byte-identical to v46.

- **2026-10-07 — standing authorization (the owner): "you can continue to go
  with your recommendations regarding the matcher unless there is a problem
  that you determine would really benefit from my decision … I am okay with
  you doing new live matches as needed."** From here, matcher design
  questions are decided on the recommendation and logged here as decided
  under this authorization, with the evidence; the owner is told in the
  report and can veto. Live FDC requests stay named in advance, spent on a
  scratch copy of the current snapshot, counted, with the raw answers kept
  where the cache would trim them. First use: the prep47 design's 27
  questions (`.claude/diag/2026-10-07/prep47/design_v2.md` §1) are all
  decided as recommended — Q1 ranges at the midpoint everywhere (re-rules
  checkpoint 9 Q5), Q2 USDA coat budgets per shape (re-rules checkpoint 9
  Q2), Q3 per-food frying-oil uptake, Q4 bacon at AH-102 item 1981's 0.33 on
  a 28 g slice (re-rules Y11), Q5 tapioca by ATK's print, Q6 zest plus juice
  as two parts, Q7 marinades flagged only, Q8/Q8b served-with references
  accounted at 0 g, Q9 prose variations routed to their base, Q10 partial
  pour-away kept held, Q11 shell-on shrimp and mussels at AH-102's shares,
  Q12 kiwi at FNDDS's fruit, Q13 raw leek and rhubarb records, Q14/Q14b
  canned-bean liquid, Q15 four record fixes, Q16 strained solids 0 g, Q17
  strained cured pork by the skim test, Q18 removed aromatics 0 g, Q19 fat
  poured off capped, Q20 kept parts counted, Q21 bowl leftovers counted
  whole, Q22 plated no-amount references at one batch, Q23 curry paste and
  Old Bay uncounted, Q24 shallow-fry oils with uptake, Q25 an alcohol
  retention planner pass authorised, Q26 halloumi flagged on Monterey. Build
  order as the design's §2: the v47 review fixes, the 9-detail live step
  (snapshot 21), then ranges, records, discards, bacon, references, coats.

- **2026-10-07 — option A's six failed answers (the owner: "go with your
  recommendations" on the six-row table):** stand-ins, each as recommended —
  mascarpone (no FDC record; three lines) counts as heavy cream 2346386,
  flagged; potato starch as cornstarch 169698, flagged; brown rice flour as
  white rice flour 790214 (the plan's own fallback), flagged — the gluten-free
  flour blend then completes and its two parents count it; nutritional yeast
  keeps FNDDS "Yeast" 2710005, now flagged; frozen cranberries read the raw
  cranberry record 171722 and frozen pineapple chunks the raw pineapple
  2346398, both unflagged (the same food, frozen). Built as matcher v46; the
  held library sweep follows it, then the re-calibration, then the
  evidence-gated dual-fleet review of the sections batch (a18da27 onward;
  the last fleet review was Run 060 on v29) and a second blind nutrition
  audit on a fresh, stratified sample (the first predates sub-recipe
  routing). Image thumbnails stay deferred by the earlier decision.

- **2026-10-06 — matcher v44, the server half built (deviations from
  `prep43/design_v2.md` §2, each disclosed by a fixer or verifier and kept):**
  (1) a child section not yet swept ROUTES with no stamp (the v41 F6 shape:
  the row reads its recipe stale and the stale sweep appends the parent)
  instead of the design's `section` rule row, which would have left the
  parent fresh at 0 g for good once the section computed (no child id for the
  readers' query, no stamp to read as underived); the wire reason `section`
  is therefore unreachable and a section with no ingredient lines answers
  `no_ingredients`. (2) The replay's `sectionsStale` is 13, not the design's
  0: the thirteen sections whose lines ask option A's unanswered queries keep
  a retry row, which RULE A reads as underived — the same rule every recipe
  obeys; it holds only until the owner spends option A (every parent is
  fresh, `staleAfter` 0). (3) A section key's stored totals are per batch
  (serving basis 1): the first build inherited the host's serves (verify
  round 2's V1), restored to P3 §3.4 at the one compute function. (4) The
  queue's credit under-promises: a recipe with an incomplete routed child is
  never credited by its own group (verify round 1's D2 — the gluten-free
  pizza while its flour blend waits on option A); 279 groups, the sum of
  `finishes` 72 = `finishable` 72. (5) Two app TEST files are re-pinned in
  the server commit because S14 (a) removed the three non-child sections from
  the shared golden the app tests read (the "a section stages nothing" pin
  moves to the app commit's section goldens); a third app pin, the C1 widget
  test's ham and chicken-pieces figures, was red since v43's golden move —
  that gate ran the server and salt_shared suites but not the app suite.
  Gate rule from here: a server commit that regenerates a shared golden runs
  the app suite too. (6) The server is NOT deployed to the local :8080 until
  the app commit: the shipped app gates a pick on `slug == null`, and a v44
  section candidate carries its host's slug, so an old app would store
  another host's whole recipe as the child. (7) The FK on the generated
  `host_id` is accepted by this Mac's SQLite 3.54.0; Debian bookworm's 3.40.1
  (the Dockerfile) is unverified and the trigger fallback unbuilt — the
  migration test runs on the deploy image before the first deploy. (8) Two
  new rule notes ("Reserved from the main recipe — no amount on the line,
  counts as zero" / "… counted in the main recipe's spice rub") are row text
  not on the S13 copy sheet; they go on the app mockup delta. The v44
  section of this document lands with the app commit, as v41's did.

- **2026-10-06 — the phase-2 package, part 2 (the owner: "go with your
  recommendations" on S1–S15 of `prep43/design_v2.md`):** a section becomes a
  recipe keyed `<host id>#<title>` in the same tables (migration 019; a
  retitle is a new key, the parent's pick then held with the old title
  named); only REFERENCED sections compute (140), with the live step's option
  A (at most 22 requests, named in advance, under the 2026-09-30 standing
  approval), the mascarpone search and the conditional brown-rice-flour
  search; the 23 zero-request reads and stand-in extensions and the 16
  normaliser-defect rules adopted; the citrus rule extended to a counted
  fruit; a "(recipes follow)" line lists the own sections no other reference
  routes to; a section pick is line-local; the marinade sections become
  pickable but a pick needs a typed eaten share; a bare count of one on an
  unmarked reference reads one recipe; section rows enter the review queue
  keyed to the host, their finishes credited to the parents routed to them;
  the nine new strings as designed, approved on a mockup delta before the app
  commit (`docs/mockups/v44-sections-copy.html`, approved the same day:
  "approved"); other hosts' sections outside the child set are not listed.
  Build order: v43 (the yields) first, then v44 (server commit, mockup delta,
  app commit, the live step).

- **2026-10-06 — the phase-2 package, part 1 (the owner: "go with your
  recommendation" on B1, then "go with your recommendations" on Y1–Y13 of
  `.claude/diag/2026-10-06/prep43/design_v2.md`):** two batches, the USDA
  Agriculture Handbook 102 yields first as matcher v43 (server only, zero
  requests), then sections as children as v44. The yields: chicken parts with
  the skin kept read the part's own raw yield (breast 74, thigh 70, drumstick
  63, wing 50 — items 584–586, 590) instead of the whole bird's 0.608; a leg
  and mixed pieces read figures derived from those by item 583's carcass
  shares (66.7, 69.8), flagged as derived with the leg-quarter caveat (the
  handbook has no leg-quarter row); breasts whose skin is discarded move to
  the Foundation skinless breast record at item 584's meat 65 in one step;
  whole chickens keep FDC's own 0.608 / 0.434; whole turkeys read 0.652 (the
  "12 lb and over" neck-and-giblets step 78/85 × the fryer-roaster carcass
  yield 71, item 2592), turkey parts their own rows (thigh 82, leg 75, leg
  quarter 71, skinned thigh 77, wings 43); the bone-in turkey breast stays at
  0.608 (item 2593's "Breast" is a breast without the back ATK's carries);
  produce prep losses on a printed weight (potatoes 81, apples 78 or cored 90,
  sweet potatoes 80, pears 78, carrots 82, onions 90, leeks 44, savoy 93,
  cauliflower 92, butternut 84, zucchini 93, summer squash 95, strawberries
  94), scallion parts on a piece read (white 37, green 59); bone-in beef, pork
  and lamb where the handbook names the cut (spareribs 0.58, standing rib
  0.82, fore shank 0.61, lamb rack 0.73 flagged as unfrenched, lamb foreshank
  0.70, cured spiral ham 0.70, fresh ham shank half 0.78 derived) with FDC's
  own refuse portions kept where they exist; bacon keeps 0.403. REVERSED, with
  the handbook's numbers in hand (the same morning's "keep 0.795" was made
  conditional on sourcing a part bone share): a skin-discarded thigh or leg
  reads the handbook's one-step meat figure (thigh 59, item 586; leg 57.1
  derived) from the printed weight, and the SR skin share is retired for
  chicken parts — Chicken Provençal's thighs 658 → 803 g against the blind
  auditors' 790. A person's pick of a meat-only record reads the meat figure
  (composition over the skin trip), pinned both ways.

- **2026-10-06 — canned beans (the owner: option (b)):** the drained share is
  read per bean from FDC's own can pairs, fetched in a five-request live step
  the same day (kidney 174285/175195: 266 of 436 g = 0.610; pinto
  174286/175201: 277 of 442 g = 0.627; the rinsed kidney record 175243 gives a
  cup figure only, so rinsing adds no factor) beside the chickpea pair already
  in hand (253 of 448 g = 0.565) — the result snapshot 18. The 22 canned-bean
  lines counted by the can's printed weight on a drained record take their
  bean's share, flagged; black, cannellini and navy beans, which have no cached
  pair, take the three pairs' median (0.610) flagged as such; a line that keeps
  the liquid ("undrained", "do not drain", "liquid reserved", "1 can drained, 1
  can undrained") keeps the can whole for that part. Not chosen: the chickpea
  share for every bean (a), or leaving the liquid counted (c).

- **2026-10-05 — the composite-row design (matcher v41; the owner: "go with your
  recommendations" on the ten items of `.claude/diag/2026-10-05/prep41/design_v3.md`
  §1.1):** a recipe pick never enters the item-key decisions and travels only by
  the explicit apply-to-all, its targets written as the person's own rows (a
  re-imported parent falls back to its engine default); `choose_recipe`,
  `nested_recipe` and `discarded_recipe` are LINE holds (groups of one); a
  reference row that stays a 0 g rule row until phase 2 drops out of the matched
  count and the label names it, out of the queue; the copy the mockup leaves open
  as the design writes it (parent kind pie/tart/quiche else recipe; no why-line
  on exact-title routes); the three reference marinades keep Q7's poured-away
  meaning under their own hold code `discarded_recipe` (Skip, Confirm, Choose a
  recipe — typed grams need a food) rather than the literal `discarded_medium`;
  a Confirm keeps the flags that state a fact (the bacon rendering, "child is
  partial") and clears only the default-dough flag; the three un-noted
  single-crust lines are HELD `choose_recipe`, not routed on Foolproof All-Butter
  as plan.md §2 counted (the book's own links name a section) — R1 therefore
  routes 13 lines, not 16; buffalo-wings' blue cheese dressing is held
  `choose_recipe` (missing) instead of plan.md's silent rule row; the three
  unmarked own-section references (a cilantro sauce, a tapenade, harissa) wait
  for phase 2; a food pick is accepted on a reference line whose printed
  alternative carries an amount, weighed on that alternative and keyed on the
  row's own item key (three lines), refused where it carries none. Also
  recorded: R3 (an unrouted reference makes the label partial) moves 87 complete
  recipes to partial on the v40 replay, not plan.md's "about 60", which read
  snapshot 16's stale stored labels; 51 of them have nothing to review until
  phase 2.

- **2026-10-05 — the edible-yields live step, spent (13 requests on a scratch
  copy of snapshot 16, the key attached read-only and deleted after; the
  result snapshot 17):** the plan's conditions decided every item. The
  search for a meat-only broiler ranks SR 171052 first, whose own
  ready-to-cook yield is 197 g a pound (171447's meat-and-skin figure is
  276 g), so the whole-bird and pieces skin lines can move to it; the SR clam
  record publishes "lb (with shell), yield after shell removed" 68 g, so the
  six clam lines bought by weight can count. Not enabled, by FDC's own
  answers: the skinless breast record publishes no half-breast portion
  comparable to the skin-on half (its "piece" is 272 g against a 145 g half
  breast), so the breast lines stay at the bone yield; the turkey leg and
  wing publish ready-to-cook shares (105 g, 33 g; the cached breast 146 g)
  but FDC has no raw meat-and-skin back or neck record and the meat-only
  ones publish no share, so no bird yield can be summed (the three parts
  alone are 0.626) and the interim 0.608 stays; the mussel record publishes
  no with-shell portion, so the five mussel lines stay held; the chickpea
  pair (253 g "can drained"; 448 g "can (total can contents)") names no can
  size, so the plan's same-can condition is undetermined, the other bean
  pairs were not fetched and no bean line changes — an open question for
  the owner (0.565 drained ÷ whole if the same-can reading is accepted on
  manufacturers' drained weights). Version naming: the enable batch is
  matcher v40; the composite-row batch the mockup calls v40 ships as
  matcher v41.

- **2026-10-05 — the v40 composite-row mockup (the owner: "go with the
  recommendations"):** all five open questions as recommended. The
  `choose_recipe` hold gets its own queue chip (its fix is a recipe, not a
  USDA food); a person's Confirm on a defaulted dough clears the
  approximation flag; no "count as rendered" action in v40 for the wider
  bacon lines (oven-fried bacon, quiche Lorraine, carbonara — typed grams
  correct them); section candidates are listed but not pickable until phase
  2; the label's "Includes N recipe" line is shown to members too. The
  mockup (`docs/mockups/v41-composite-rows.html`) is the specification for
  the v40 build.

- **2026-10-05 — the edible-yields plan (the owner: "go with your
  recommendation on the edible yields batch", then "go with your
  recommendations" on the plan's nine items):** the blind accuracy audit
  (`.claude/diag/2026-10-05/audit1/`) found the engine's food choice right
  and its mass high where a line's weight is what was bought rather than
  what is eaten; bone-in cuts at gross weight were 83 % of the sample's
  calorie error. Two earlier rulings are REVERSED by this one: checkpoint 6's
  #11 and #5 (meats and birds at gross weight, approximate; turkeys gross)
  become class edible yields from FDC's own refuse portions, flagged; and the
  2026-09-27 #9 ruling (no sub-recipe routing) becomes phase-1 routing of
  "1 recipe X" references to library recipes in v40 (variations still never
  routed). The nine items: Q1 the per-class yield table in full, keyed on
  the matched record (pork bone-in chops 0.662, pork ribs 0.653, pork
  bone-in roasts and hams 0.758, beef bone-in rib roast 0.758, chicken and
  turkey parts 0.608, whole turkey 0.608 interim, bony beef/lamb/veal
  0.657, oxtails 0.564; either-bone steaks and ham hocks stay gross); Q2 no
  refuse-sibling map; Q3 five shellfish lines un-held (per-piece mussel and
  oyster meat, shell-on shrimp eaten whole, two live lobsters at FDC's
  one-lobster portion), thirteen stay held; Q4 skin removed in the
  directions → the cached skinless thigh and leg records at the SR meat
  share (0.795, 0.770) stacked on the bone yield, the breast and whole-bird
  cases after a three-request live step; Q5 rendered bacon and pancetta as a
  two-part row in v40 (cooked at 0.403 plus the kept fat as bacon grease),
  the wider bacon lines a person's; Q6 only the two ATK-printed prep losses
  (a peeled banana 115 g; drained canned tomatoes × 0.54), a cited USDA
  yield table acceptable later; Q7 sub-recipe routing phase 1 with a mockup
  first; Q8 canned coconut milk on the SR record, unflagged; Q9 the SR
  records' own size portions for small and large onions, carrots and
  tomatoes, the plum tomato at 62 g, unsized onions later. Build order: v39
  part 1 at zero requests, then a live step of nine to eighteen requests,
  then v40.

- **2026-10-04 — the review queue (the owner: "option two — make as many things
  accurately auto mapped as possible", then "go with your recommendations" on the
  approval table):** the engine-side queue lines are swept by the engine where a
  cached answer names the right food or a sourced figure exists; the held lines
  stay a person's call. Approved: 24 right-record lines; 53 flagged stand-ins
  and figures on existing precedents; the six asks (canning salt counted on
  table salt; a sea scallop 34 g flagged; nonpareils at sugar's density flagged;
  crème fraîche on heavy cream flagged; ya cai on salted mustard cabbage
  flagged; farro searched before a label); all 30 requests; a class rule
  counting 14 zero-nutrient flavourings as 0 g. Left for a person: 49 lines
  (foods FDC lacks, discarded infusions) and two corpus typos to edit by hand.

- **2026-10-04 — the portobello cap (the owner, "go with option 1"):** spend two live
  requests for FDC's own per-cap figure rather than a reference figure or no
  grams. Spent the same day (the SR raw portabella record and its detail: 84 g a
  piece); built as v35. Also 2026-10-04 (the owner): there is NO production host
  and never has been — every run so far was local development on this machine;
  the first real run uses the swept snapshot as its database, locally, with the
  one exit-review finding an ordinary sweep reaches (an engine line's good match
  overwritten by one transient failure) fixed first; the other exit-review
  findings stay deferred.

- **2026-10-03 (night) — v33's two follow-ups (the owner: "the narrow version for
  both lists"):** (1) the four fried dredges the survey reads with no excess
  sentence (0288, 0149, 0525, 0042's panko) STAY HELD by the frying ruling — no
  change. (2) A coat layer outside the head set (nuts, cheese, crackers, chips,
  Melba toast) is held only when the same recipe already holds a dredge (or its
  directions leave an excess of the coat) AND the coating step names the layer
  in the coat's dish or with its crumbs; cheese in a filling or a sauce, nuts in
  a filling, chips on the side and a crust with no excess stay counted; a row
  with no food gets no hold. Built as v34 (eight rows: the brief's six plus the
  Parmesan stirred into the held crumbs of 0407 and 0416, judged within the rule).

- **2026-10-03 (evening) — the dredge-reach ruling (the owner, on the survey's
  option 1):** a reachable coating line (flour, starch, crumbs or panko at a
  quarter cup or more, plus the bread or crumbs of the same coat) is HELD
  whenever the directions leave an excess of the coat, in every cooking class
  (sautéed and baked included); a coat wholly eaten (a toss, a binder, a
  pressed-on crust with no excess sentence, a batter) is counted; no blanket
  coating fraction. The checkpoint 9 frying ruling stands as a sufficient
  condition (no held dredge is un-held). Left for the owner: the four fried
  dredges the survey reads as leaving no excess; the coat components outside
  the head set (nuts, cheese, Melba toast, saltines, chips). Built as v33.

- **2026-10-03 — after Run 060 (the exit review): the engine loop STOPS at v29;
  the effort moves to accuracy.** Run 060's engine findings are deferred (none is
  reached by the corpus or a healthy sweep). The same evening the owner ruled the
  open accuracy questions ("go with your recommendations, including the sourced
  lasagna figures"): Q6 (a) a corpus-printed VOLUME counts as a printed weight
  (ginger 8 g/inch, chipotle 4.6 g/pod, orange zest strip 0.8 g/inch, flagged);
  (b) ginger 8 g not 6; (c) counted whole spices get per-piece reference figures
  flagged approximate; (d) star anise on anise seed, flagged; (e) ancho stays on
  FDC's 17 g; lemon zest strips 0.8 g/inch; lasagna figures SOURCED from
  manufacturers' box specs (17 g a no-boil sheet, 25 g a curly noodle); a
  scallion bunch 7 × 15 g; lemongrass 10 g a stalk (reference); dried jujubes
  and the per-inch mild chile stay at no grams. Q7: the bone-in group built now
  (v30); the eight small groups and the anchovy-paste figure approved; Spanish
  chorizo only on the real dry-cured record (one live request — the cached
  record is fresh Mexican chorizo); the misc group after a full read (35 keep,
  5 small modifications, 0 reject). R2: dredges stay held, no blanket fraction.
  The dredge REACH (sautéed, baked) is NOT ruled: a zero-request survey per
  class first, then the owner rules per class. R4: 0488's poaching set is held
  as a part-kept medium like 0129. 0042's two eaten tablespoons of oil count;
  0288's quarter cup of pan-fry oil and 0674/0675's fritter oil are held
  ambiguous. Air-fry stays a non-frying verb; shimmering/smoking stays
  non-evidence. The live step is spent by the owner on a scratch copy under the
  2026-09-30 standing approval, every request counted. Constraint recorded: the
  owner cannot weigh ingredients — figures come from manufacturer specs, FDC
  portions or the corpus, or the line stays at no grams.

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
- 2026-10-01 — Checkpoint 9 rulings (user: "go with your recommendations"):
  the v21 stand-ins are approved as flagged approximations (dried pinto /
  unspecified / small white beans on navy raw, spicy greens on arugula,
  All-Bran on bran flakes, seven-grain on whole-wheat hot cereal, fingerling
  on red potato raw, ghee at oil density, Aleppo at paprika density,
  pecorino at the grated-hard-cheese 0.42, tapioca starch on the tapioca
  pearl cup). Q1 the sourdough starter's flour lines (0799) are HELD as a
  poured-away medium; Q2 dredging flour and crumbs (the 8 lines counted at
  checkpoint 9; 11 held when built, 16 after Run 053) are HELD until
  a coating fraction is set; Q3 a rinsed dry cure (0090) is 0 g discarded —
  the brine / degorging ruling extended; Q4 the soy braise (0129) is HELD
  under poured-away media; Q5 range amounts stay as they are (upper bound in
  parentheses, midpoint bare); Q6 piece figures FDC lacks (ginger per inch,
  counted whole spices, chile pods, zest strips, lasagna noodles, lemongrass)
  use a weight ATK prints in the corpus where one exists and otherwise a
  user-set figure flagged approximate (a figure table drafted from the
  corpus's printed weights awaits approval); Q7 the 151-line stand-in list
  is approved group by group once each group's target record is listed
  (bone-in parts are already covered by the meats-and-birds ruling); Q8
  water chestnuts keep the raw record.
