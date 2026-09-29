# SaltToTaste API (v1)

Base path: `/api/v1`. All responses are JSON unless noted. Updated in the
same commit as any endpoint change (see CLAUDE.md).

**Status:** P6 — every endpoint except `GET /healthz` requires
authentication. Recipes are editable; the library reconciles with hand
edits; backups run automatically; nutrition computes from USDA FoodData
Central.

## Authentication, roles & scopes

Two interchangeable credentials, checked by the same middleware:

- **Session token** — from `POST /auth/login` (or `/auth/setup`). Delivered
  both as an `stt_session` cookie (`HttpOnly; SameSite=Lax; Path=/`, plus
  `Secure` behind a TLS proxy with `TRUST_PROXY=true` **and** `TRUSTED_PROXIES`
  naming that proxy; `Max-Age` only when `remember` was requested) and in the
  response
  body for non-browser clients (`Authorization: Bearer <token>`). Expiry:
  7 days, or 90 days sliding when `remember` was set.
- **Personal access token (PAT)** — `stt_pat_…`, minted per user in
  Settings, long-lived until revoked, sent as `Authorization: Bearer`.
  Intended credential for native apps and scripts.

Roles: **admin** (full access) and **member** (read + personal features).
PATs carry a scope — `read` (browse + personal data) or `full` (everything
the owner's role allows). Effective permission = role ∩ scope: every
endpoint that mutates **shared/server state** (accounts, sessions, tokens,
recipes, tags, library, backups) requires `full` scope and returns
`403 forbidden` to a `read` PAT. **Personal data is the documented
exception:** favorites and personal notes are writable with a `read` PAT —
they affect only the token's owner. Session logins always act as `full`.

CSRF: cookie-authenticated **mutating** requests must send
`X-Requested-With: SaltToTaste`. Bearer requests are exempt — **any**
bearer, a PAT and equally a session token presented as one, because what
the rule keys on is whether the *browser* attached the credential by itself.
An absent, `Basic`, or malformed `Authorization` is treated as ambient and
stays guarded. Identical rule to the side-effectful GETs below; one
implementation serves both.

<a name="cross-site-gets"></a>
**Side-effectful GETs carry the same protection.** The session cookie is
`SameSite=Lax`, which a browser *does* send on a cross-site top-level
navigation, so a GET that spends something is drivable from an attacker's
page even though it is not a mutation. Six reads therefore refuse a
cookie-authenticated request unless it proves it is not cross-site — either
`X-Requested-With: SaltToTaste`, **or** a `Sec-Fetch-Site` the browser
itself stamped `same-origin` or `none` (which is what lets a download
opened by a top-level navigation through). Neither present — including a
client that sends no `Sec-Fetch-*` at all — is `403 csrf`.

**Anything sent as `Authorization: Bearer` is exempt** on all six — a PAT
*and* a session token presented as a bearer (the form the login response
hands to non-browser clients). What these guards key on is whether the
browser attached the credential *ambiently*, which only the cookie is; a
`curl`/script client therefore needs neither header. An absent, `Basic`, or
malformed `Authorization` is treated as ambient and stays guarded —
"malformed" as the *authenticator* judges it, since one parser decides both:
`Bearer` with an empty or whitespace-only token grants no exemption, and it
does not authenticate either.

| Route | What it spends |
|---|---|
| `GET /api/v1/admin/logs` | `scan=full` spawns an isolate over the whole history |
| `GET /api/v1/admin/logs/export` | synchronous whole-history parse, no row cap |
| `GET /api/v1/nutrition/search` | up to 2 calls of the shared FDC request budget |
| `GET /api/v1/backups/{name}` | streams the entire database snapshot off disk |
| `GET /api/v1/import/candidates` | synchronous walk of the import dir and every child |

Login rate limiting: per IP+username; 5 consecutive failures lock the pair
for 1 minute, doubling per further failure up to 15 minutes (`429 locked`).

Accounts created by an admin (and password resets) issue a one-time
temporary password with `must_change_password`: until the user calls
`/auth/change_password`, every other endpoint returns
`403 password_change_required`.

### Auth endpoints

| Endpoint | Notes |
|---|---|
| `POST /api/v1/auth/setup` | `{setup_code, username, password}` — first boot only (zero users); code from server stdout; creates the admin |
| `POST /api/v1/auth/recover` | `{recovery_code, username, new_password}` — no auth; code from `salt_server:recover` on the server host; resets/creates that account as an enabled admin and revokes its sessions + API tokens; rate-limited per IP (`429 locked`) |
| `POST /api/v1/auth/login` | `{username, password, remember?}` → `{token, user}` + cookie; failures are uniform `422 validation` (unknown username / wrong password), except a **disabled** account whose password is correct gets a specific "account disabled" `422` — revealed only after a correct password, so it stays enumeration-safe |
| `POST /api/v1/auth/logout` | ends the current session (cookie/session bearer only) |
| `GET /api/v1/auth/me` | `{user: {id, username, role, must_change_password, scope, via}}` |
| `POST /api/v1/auth/change_password` | `{current_password?, new_password}` → `{ok, revoked_tokens}` — current required unless a change was forced. Signs out everywhere: the caller's other sessions AND **every** one of their PATs, with the count returned as `revoked_tokens`. No opt-out, deliberately: a session alone can mint a full-scope PAT and a PAT never expires, so a change that spared them would evict the honest sessions and leave a token minted from a stolen cookie alive forever. The cost is accepted — the user's own scripts stop too, exactly as with an admin reset |

### Account management

| Endpoint | Role | Notes |
|---|---|---|
| `GET /api/v1/users` | admin | all accounts |
| `POST /api/v1/users` | admin | `{username, role}` → `{user, temp_password}` (shown once); duplicate → `409 conflict` |
| `PATCH /api/v1/users/{id}` | admin | `{role? \| disabled?}`; never your own account |
| `DELETE /api/v1/users/{id}` | admin | permanently deletes the account (never your own → `422`); its sessions, PATs, favorites, and notes cascade; recipes are not user-owned and survive. Irreversible — disable to deactivate reversibly |
| `POST /api/v1/users/{id}/reset_password` | admin | new `temp_password` (once), forces change, and signs out everywhere — every session AND every PAT, with the count returned as `revoked_tokens`. Not your own account (use change password). Revoking the PATs is deliberate: a PAT is its own credential, so a reset that only dropped sessions left an attacker's token frozen rather than gone, and it returned to full service the moment the user completed the forced change |
| `GET /api/v1/sessions` | any | own sessions; `current` flags this one |
| `DELETE /api/v1/sessions/{id}` | any | sign out one session (own only) |
| `GET /api/v1/tokens` | any | own PATs (prefix only); a revoked token carries `deletes_at` (`revoked_at + API_TOKEN_RETENTION_DAYS`, null when retention is 0) so the UI can count down to its prune |
| `POST /api/v1/tokens` | any | `{name, scope}` → `{token, item}` — full value only in this response. Capped at 20 live tokens per user (`422` past the cap); revoke one to free a slot |
| `DELETE /api/v1/tokens/{id}` | any | revoke (own only). The revoked row is deleted after `API_TOKEN_RETENTION_DAYS` (default 90) by daily housekeeping |

## Conventions

- Every response carries an `X-Request-Id` header (16 hex chars, server
  generated). Errors echo it in the body so users can quote it in reports
  and admins can grep the server logs.
- **Error envelope** (every non-2xx):

  ```json
  { "error": { "code": "<stable code>", "message": "<human message>", "request_id": "<id>" } }
  ```

- **Error code catalog:**

  | Code | HTTP | Meaning |
  |---|---|---|
  | `validation` | 422 | A parameter or body value is invalid; message names it |
  | `not_found` | 404 | Resource (or route) does not exist |
  | `method_not_allowed` | 405 | Route exists; HTTP method not supported |
  | `unauthorized` | 401 | Missing/expired/revoked credential — sign in |
  | `forbidden` | 403 | Authenticated but not permitted (role or scope) |
  | `csrf` | 403 | Cookie-authed request that cannot prove it is not cross-site: a mutation missing `X-Requested-With: SaltToTaste`, or a [side-effectful GET](#cross-site-gets) missing both that header and a same-origin `Sec-Fetch-Site` |
  | `password_change_required` | 403 | Must change password before anything else |
  | `conflict` | 409 | Conflicts with existing state (e.g. duplicate username) |
  | `locked` | 429 | Login lockout; message says when to retry |
  | `rate_limited` | 429 | Too many text searches; retry after the `Retry-After` header |
  | `internal` | 500 | Unhandled server error (details only in server logs) |

- Timestamps are UTC ISO-8601 strings with a `Z` suffix. Keys are
  `snake_case`.

## Endpoints

### `GET /healthz`

Liveness probe (outside `/api/v1`, no auth ever). →
`200 {"status": "ok", "setup_required": bool}` — `setup_required` is true
while the instance has zero users, telling a fresh client to run the
first-boot `/auth/setup` flow (it reveals only whether the instance is
claimed).

### `GET /api/v1/recipes`

Paged recipe cards — ordered by title, or by relevance (bm25) when `q` runs
a search.

Query parameters:

| Param | Default | Constraints |
|---|---|---|
| `page` | 1 | integer ≥ 1 |
| `limit` | 24 | integer 1..100 |
| `q` | — | search-DSL query (below), max 512 chars; parse errors → `422 validation`; rate-limited per user (see below) |
| `favorites` | — | `true` restricts the listing (and any `q` search) to the caller's favorites |

A `q` search is rate-limited per user — `SEARCH_RATE_LIMIT` requests per minute
(default 60; `0` disables), returning `429 rate_limited` with a `Retry-After`
header past that, so it caps any single caller's share of the search worker
pool. The ranked search runs on background isolate(s) (`SEARCH_WORKER_ISOLATES`),
off the serving isolate. Plain listing (no `q`) is not limited.

**Search DSL:** words next to each other all must match (`and` implied);
`or` broadens; `"quoted phrases"` match exactly; scopes `title:`, `tag:`,
`ingredient:`, `direction:`, `note:` bind the single word or quoted phrase
after them; unscoped terms search everything (including the "why this
works" background prose). `calories:<400` (also `<=`, `>`, `>=`, `=`)
filters by computed calories per serving, forces calorie-ascending order,
and may only be combined with `and`; recipes without computed nutrition
never match. User terms are compiled into FTS5 as quoted literals;
MATCH syntax cannot be injected.

→ `200`:

```json
{
  "items": [ { /* RecipeCard */ } ],
  "total": 1198,
  "page": 1,
  "limit": 24
}
```

`RecipeCard`: `id`, `slug`, `title`, `category`, `hero_image`
(`/images/<source-slug>/<file>` or null), `tags` (string list),
`servings_text`, `total_minutes`, `calories_per_serving` (null until
computed), `favorite` (the **caller's** favorite flag), `variation_count`
(how many `variation` subsections the recipe carries — the card badge).

### `POST /api/v1/recipes` (admin, full scope)

Create a recipe. Body: `{"recipe": { /* schema-v2 fields */ }}` with the
editable keys `title` (required), `servings`, `category`, `tags`, `times`,
`background`, `prep_notes`, `ingredients`, `steps`, `subsections`,
`techniques`, `images`, `notes`, plus `source.name`/`source.url`.
Server-owned fields are generated: id `manual-<yyyymmdd>-<slug>`, slug from
the title (uniqued), `schema_version`, `serves` (parsed from `servings`);
steps are renumbered sequentially; tags are lowercased and de-duplicated.
The canonical YAML is exported to `library/my-recipes/recipes/<id>.yaml`.

→ `201` with the detail body (below). Invalid shapes/values → `422` with a
field-naming message.

### `GET /api/v1/recipes/{idOrSlug}`

Full recipe document by canonical id (`atk-tv-2023-0857-rich-chocolate-bundt-cake`)
or slug (`rich-chocolate-bundt-cake`).

→ `200`:

```json
{
  "recipe": { /* full schema-v2 recipe document, snake_case */ },
  "source_slug": "the-complete-americas-test-kitchen-tv-show-cookbook-2001-2023",
  "hero_image_url": "/images/<source-slug>/<file>.jpg",
  "base_hash": "<stored content hash — echo it on PUT to detect conflicts>",
  "favorite": false,
  "note": null
}
```

`favorite`/`note` are the **caller's** personal data (never another
user's). → `404 not_found` when neither id nor slug matches.

### `PUT /api/v1/recipes/{idOrSlug}` (admin, full scope)

Update. Same body shape as create with **merge semantics**: an editable key
*present* in the submission replaces the stored value (an explicit `null`
clears an optional field); an *absent* key is left untouched — so a script
can safely update a single field. An optional top-level `base_hash`
(sibling of `recipe`) makes the save conditional: when it no longer matches
the stored content hash — another save landed since the client loaded — the
request is a `409 conflict` and nothing is written. The web editor always
echoes the hash it loaded; a request without `base_hash` keeps plain
last-write-wins. The slug is stable across renames (links
keep working); id, source identity, and extraction provenance are
preserved. Saving re-exports the canonical YAML; if the on-disk file had an
unsynced hand edit, that edit is preserved next to it as
`<id>.conflict-<timestamp>.yaml` (the save wins). → `200` detail body
(carrying the fresh `base_hash`).

### `DELETE /api/v1/recipes/{idOrSlug}` (admin, full scope)

Takes a backup first, then removes the database row and the library YAML
(image files and conflict copies are left in place). → `204`.

### `PUT | DELETE /api/v1/recipes/{idOrSlug}/favorite`

Mark/unmark the recipe as one of the **caller's** favorites (idempotent;
any role, `read` PAT allowed). → `200 {"favorite": bool}`.

### `GET | PUT | DELETE /api/v1/recipes/{idOrSlug}/note`

The caller's private note on the recipe (any role, `read` PAT allowed;
never stored in YAML). `PUT {"note": "<text ≤ 20000 chars>"}` sets it (an
empty string deletes). → `200 {"note": string | null}`.

### `POST /api/v1/recipes/{idOrSlug}/images?role=hero|gallery` (admin, full scope)

Upload a photo as the **raw request body**. Content is validated by magic
bytes (JPEG/PNG/WebP; 25 MB cap enforced while reading) — the server
generates the stored filename. `role=hero` (default) replaces the hero
image; `role=gallery` appends. → `201` detail body.

### `POST /api/v1/recipes/{idOrSlug}/images/from_url` (admin, full scope)

`{"url": "https://…", "role": "hero" | "gallery"}` — downloads a photo into
the library. SSRF-guarded: http/https only, every resolved address must be
public, redirects are re-validated per hop, response must be a real image
(content-type **and** magic bytes), size/time capped. When the recipe has no
photo credit yet, `images.credit` (free-text attribution, shown under the
hero) defaults to the download URL; an existing credit is never touched.
→ `201` detail body.

### `POST /api/v1/recipes/{idOrSlug}/images/store` (admin, full scope)

Upload a photo as the **raw request body** and get back its stored reference
WITHOUT attaching it to the recipe — the store-only twin of the upload above.
Same magic-byte/25 MB validation; the recipe document is untouched (the client
places the reference into a `techniques[].steps[].image` and persists it with
the recipe's own `PUT`). → `201 {"reference": "images/<file>"}`.

### `POST /api/v1/recipes/{idOrSlug}/images/store_from_url` (admin, full scope)

`{"url": "https://…"}` — the store-only twin of `from_url` (same SSRF guard and
image validation): downloads a photo into the library and returns its reference
without attaching it. → `201 {"reference": "images/<file>"}`.

> The reference is the bare canonical `images/<file>` (as stored in YAML); root
> it under the recipe's source slug to display — `/images/<source>/<file>`,
> which the reconciliation scan / detail response do for you elsewhere.
>
> **Known limitation:** a stored image only becomes referenced if a later
> recipe `PUT` points a step at it. There is no garbage collection of
> unreferenced image files, so a store call that is never followed by a
> referencing save (the editor is discarded, the photo is replaced or removed,
> or the step is deleted before saving) leaves the file on disk. Reachable only
> by full-scope admins and bounded by the 25 MB cap; pruning is a future item.

### `GET /api/v1/library` (admin)

`{"last_scan": {…} | null}` — the report of the most recent reconciliation
scan (also runs at every server start). Report fields: `started_at`,
`elapsed_ms`, `files_seen`, `updated_from_disk`, `added`, `re_exported`,
`skipped` (`[{file, reason}]`), `conflict_files`.

### `GET /api/v1/admin/recipe_review?issue=&page=&limit=` (admin)

The recipe data-quality report — which recipes are missing or have incomplete
data, grouped by issue: `{total, categories: [{id, label, count}], items:
[{id, slug, title, source, issues: [{check, label, detail}]}], page, limit}`.
`total` is the whole-library count of recipes with any issue (stable across
filters); each `categories[i].count` is per-issue. `issue` narrows `items` (and
their pagination) to one category — an unknown id is a 422. Current checks:
`no_instructions`, `unparsed_ingredients` (a line starting with a quantity + a
measurement unit that parsed no amount — dimensions and equipment are not
flagged), `incomplete_nutrition` (nutrition `partial`), `no_nutrition`
(never computed), `extraction_warnings`, `no_servings`. The set is an open
registry, so categories can be added without an API shape change.

### `GET /api/v1/admin/nutrition_review?group=&sort=&bucket=&page=&limit=` (admin)

The cross-recipe queue of ingredient-match lines that still need a look, in
the `sort` order (below): `{total, groups, buckets: [{id, label, count,
groups}], items:
[{recipe: {id, slug, title}, position, raw, bucket, finishes, match: {fdc_id,
description, data_type, confidence, grams, gram_source, status, hold} |
null}], page, limit}` (`hold` as in the per-recipe matches body below).
A line item's `finishes` is 1 when the line is its recipe's LAST open line
(the only one in `no_match` / `check` / `no_grams`, whatever the filter) —
any decision on it, a confirm taking its amount included, completes the
recipe — else 0 (always 0 on a `skipped` line). A group item overrides it
with the group's count (below).
Triage buckets: `no_match` (no food matched), `check` (an automatic match
below 50% name confidence — compared with a 1e-9 tolerance, so a score that
lands exactly on 0.5 counts whatever its float rounding — probably the wrong
food, whether or not it has
an amount — or one the engine holds for a `hold` reason at any score; an
engine 0 g, `gram_source` `discarded` or `unmeasured` at `grams: 0`, is
`counted` whatever its score or hold, since no decision on its food can
change a total — except `hold: unnamed_food`: "2 tablespoons juice" with its
amount left in the item names no food and its 0 g drops a real amount, so it
stays in `check`),
`no_grams` (a plausible match that resolves no grams, so it
contributes nothing), and `skipped` (browsable via the filter, excluded
from `total`). A `confirmed` line with no food is resolved and never appears
(confirmed water is a deliberate no-match); a `confirmed` or `overridden`
line with a food is resolved ONLY once it has grams — with no grams it stays
in `no_grams`, because the food still contributes nothing (an unfinished
fix; a confirm on a line whose record gives no amount leaves it in the queue
and its recipe `partial`). The rule is
shared verbatim with the per-recipe review sheet (salt_shared
`matchBucketFor`), so the two admin surfaces always agree. `total` and the `buckets`
counts are whole-library (stable across filters); `bucket` narrows `items` (and
their pagination) to one bucket — an unknown id is a 422. Fix a line with the
existing `PUT /api/v1/recipes/{id}/nutrition/matches/{position}` (candidates for
its fix panel come from that recipe's `…/nutrition/matches`).

`group=item` changes the UNIT of `items` to one row per ingredient — a wrong
food is an ingredient-level problem, and the decision it takes reaches the whole
library. Absent or empty means lines (the response above, unchanged); any other
value is a 422. A group item is a line item FLATTENED — `recipe`, `position`,
`raw`, `bucket`, `match`, all describing the group's EXAMPLE line — plus
`item_key` (the ingredient key the group is joined on, and the key
`ingredient_decisions` lands on; empty for a row the key backfill has not
reached, which is always a group of one), `item` (the example line's parsed
ingredient VERBATIM; null when the line has none, and null too when the
line's text changed since its compute — the same drift `…/nutrition/matches`
reports as unmatched; the app labels a group by `item_key` instead when the
key names a second food, `… plus …`, since the item names only its first
food), `lines` and `recipes` (its reach), `decided` (an
ingredient decision already exists for the key) and `grams: {min, max,
missing}` over the members' amounts, and `finishes`: how many recipes one
decision on the group completes when it is applied to the group — a recipe
counts when EVERY flagged line it has (in any bucket, whatever the filter)
sits in this group and each of them already has grams or is the group's
example (a confirm on the example takes its grams in the same step); a group
of one (a line hold, a decided line) counts its own recipe when that line is
the recipe's last open one. A pick of a different food recomputes every
reached line's grams from its own amounts, so it can finish more than the
count says (accepted: the count may undercount, never promises a confirm
more). `finishes_recipes: [{id, title}]` names those recipes, by title, and
`last_open` counts every recipe whose flagged lines all sit in the group,
grams or not — a No grams group holds the last open line of `last_open`
recipes, each needing its own amount. The grouped body also carries the
whole-library payoff at the top level, whatever the filter: `finishable`,
the recipes ONE group decision completes (every group's `finishes`, summed —
a recipe sits in at most one group's count), and `open_recipes`, the
recipes with at least one flagged line ("328 of the 658 partial recipes are
one group decision away from complete"); the line mode has neither. Members
are the lines that pass the
current filter, so every count is counted inside it; a group's `bucket` is its
WORST member's (`no_match` > `check` > `no_grams` > `skipped`) and the example
is its lowest-confidence line — among ties one that has grams, then the recipe
title, then the position — so `match.confidence` is the group's minimum.
`sort` orders the groups: `finishes` (the default, absent or empty) by
`finishes`, then `lines`, then worst confidence, then `recipes` and the key —
the groups whose decision completes the most recipes first; `worst` by worst
confidence first, then `lines`, `recipes`, then the key. Any other value is a
422, in either mode. In the line mode `sort` orders the lines: `finishes`
(the default) puts the lines with `finishes` 1 first, then worst (lowest
name-confidence) first; `worst` is worst first. Either order breaks ties on
the ingredient key, the recipe title, then the position. Grouped,
`page`/`limit` count GROUPS and a group is never split across a page.
Only UNDECIDED lines (`auto` / `unmatched`) join an ingredient's group: a line
someone already decided is a group of one — an amount problem for that line,
never part of an ingredient's reach, since `apply_to_all` cannot touch it —
and it still reports its own `item_key`. So is a line a LINE hold holds
(`second_food`, `discarded_medium`, `in_shell`): no decision on its key
clears it, so each rinsed or cooking-water salt is a group of one, never one "table salt · N lines" group, and
such a group's `decided` is always false.

`groups` — at the top level and on every `buckets[]` entry — is reported in
BOTH modes: the number of distinct ingredient groups among the flagged lines,
and among each bucket's lines (a key whose lines sit in two buckets counts once
at the top level). `total` and `buckets[].count` stay LINE counts in both
modes, so the filter chips never change unit.

### `GET /api/v1/admin/logs?level=&logger=&q=&limit=` (admin, full scope)

**Full scope on a read**, like the backup download and for the same reason:
the log is secret material no other endpoint returns (client IPs, recovery
lines, backup names, every request path), so a leaked `read` PAT gets
`403 forbidden`. Also a [side-effectful GET](#cross-site-gets): a cookie
session without `X-Requested-With` or a same-origin `Sec-Fetch-Site` gets
`403 csrf`.

Recorded on the `auth` logger at `WARNING` naming the actor
(`Server log read by <user> (id <n>)`) — the access line names nobody, and
this endpoint returns client IPs, recovery lines and persisted stack traces.
**Throttled to one record per actor per 10 minutes**: the viewer polls this
route every 3 seconds with Live on, so a record per read would write ~1,200
lines an hour into the very store being read and rotate the history away.
No filter text is echoed, so nothing a caller chooses reaches the record.

Recent server log records from the persistent log store (newest first):
`{items: [{time, level, logger, message, request_id}], loggers}`.
`level` shows that severity bucket (`DEBUG` `INFO` `WARN` `ERROR`) and above;
`logger` filters to one source; `q` is a message/request-id substring; `limit`
caps the count (default 200, max 1000). `scan=full` reads the whole history
**off the serving isolate** (for an explicit filter/search whose matches may be
older than the recent window); omitted, it reads only a recent tail synchronously
(cheap — the Live poll of an unfiltered view uses this). Records are appended
(one JSON line
each) to `<dataDir>/logs/server.jsonl`, which **survives restarts** and rotates
to a single `.1` backup once it passes `LOG_MAX_BYTES` (default 4 MiB; `0`
disables the store) — so the viewer shows history from before the current
process. `loggers` lists the distinct loggers present in the store, for the
filter. This is the same stream the process prints to stdout (`docker logs`),
persisted where the endpoint can read it. Secrets are redacted on the way in
(the first-boot setup code and recovery code are the only secrets ever logged;
both are masked), so the endpoint cannot hand out a live code. The `http`
logger's `message` carries the client IP (`… -> 200 (5ms) from <ip> rid=…`),
resolved against the trusted-proxy config (rightmost `X-Forwarded-For` from a
trusted hop, else the socket peer). The liveness probe (`/healthz`) and the log
viewer's own reads (`/api/v1/admin/logs`) are **not** request-logged — they
poll frequently and would otherwise flood the log.

The `auth` logger carries the security-relevant events the `http` access line
cannot name, each with its actor and its target: sign-in success/failure/
lockout and refusal of a disabled account, logout, password change (and a
rejected one), first-boot setup, user create/role change/enable/disable/delete,
admin password reset, PAT mint/revoke, session revoke, **backup
create/download/delete**, **server-log read/export**, and **FDC key
set/clear**. Usernames and ids only —
never a password, token, hash, or code — and an attempted username that cannot
name an account (`login` does not validate that field) is recorded as
`<invalid>` rather than written through, so a peer cannot pump the store or
smuggle a `rid=` into a record. Filter `logger=auth` for the whole account
story.

**`LOG_LEVEL` does not apply to `auth`.** That logger's level is pinned, so
its records are written at every supported setting — including `WARN` and
`ERROR`, which would otherwise discard the entire trail (sign-ins, PAT mints,
backup downloads) while keeping only the failures, on a routine verbosity
choice. Every other logger (`http`, `search`, `import`, …) still follows
`LOG_LEVEL` as documented.

An `ERROR` record for an unhandled exception carries the exception type, its
message and its stack in `message`, on lines below the summary (they are
redacted like any other text, and are still never in the response envelope).
`request_id` is the server-generated id carried with the record as data — the
store never parses one out of message text at all, so neither a request path
containing `rid=…` nor a message that merely ends in one can set it.
Retention is a fixed byte budget, so an unbounded record is how an
unauthenticated peer would rotate the history away — three caps bound it, each
cut with a marker stating how much was dropped: a request path over 256
characters (longer than anything this app can serve), the emitter's own text
over 1 KiB, and the finished record (text plus exception plus stack) over
8 KiB. The text has its own budget so that a long attacker-chosen path can
never push the exception type and stack frames out of an `ERROR` record.

### `GET /api/v1/admin/logs/export?level=&logger=&q=` (admin, full scope)

Same posture as the viewer above: **full scope** (`403 forbidden` to a
`read` PAT) and a [side-effectful GET](#cross-site-gets) (`403 csrf` to a
cookie session that proves neither header). The app opens this by top-level
navigation, which is why the `Sec-Fetch-Site` proof exists at all.

Every export is recorded on the `auth` logger at `WARNING` naming the actor
(`Server log exported by <user> (id <n>)`) — the whole persisted log leaving
the box is the same class of act as a backup download. Not throttled (a
one-shot user action, unlike the viewer's poll) and no filter text is
echoed.

The full matching log as a downloadable **text** file (`Content-Disposition:
attachment; filename="salttotaste-logs-<utc-timestamp>.log"`). Same `level` /
`logger` / `q` filters as the viewer, but **no row cap** — every matching record
is emitted **oldest-first**, each starting a header line
(`<time> <LEVEL> <logger> [rid=<id>] <message>`). An `ERROR` record's exception
and stack sit on **two-space-indented continuation lines** under that header,
so a crash spans several lines but only its first line carries the metadata —
`rid=` is on the header, never stranded on the last stack frame. Records are
already redacted in the store. The web app opens
this via `launchUrl`, so the browser saves the file rather than navigating.

### `POST /api/v1/library/rescan` (admin, full scope)

Reconcile the YAML library with the database now: a cleanly hand-edited
file **wins** (imported, then normalized back to canonical form), a
malformed file is skipped with a reason (the database version stays), a
missing export is re-materialized, and a hand-dropped new file is imported.
→ `200 {"last_scan": {…}}`.

### `GET | POST /api/v1/backups` (admin; POST full scope)

`GET` → `{"items": [{"name", "size_bytes", "created_at"}]}`, newest first.
`POST {"include_images"?: bool}` → `201 {"backup": {…}}` — creates a
`.tar.gz` holding the YAML library plus a compacted SQLite snapshot
(`salt.db`). Images (97% of the bytes, untouched by destructive operations)
are excluded unless `include_images` is true. Backups also run
automatically before every recipe delete, before every import, and daily.
Retention keeps the newest `BACKUP_RETENTION` (default 14) **per trigger**
— scheduled, manual, before-delete, and before-import each have their own
pool, so a bulk-delete session's burst of before-delete archives can never
evict the scheduled history.

A `POST` is recorded on the `auth` logger at `WARNING` with the acting admin
and the archive name (`Backup created: <name> by <user> (id <n>)`), the same
level as its download and delete siblings so the three read as one story
under `logger=auth`. An archive is only exfiltrable once it exists, and the
access line names neither actor nor object.

### `GET | DELETE /api/v1/backups/{name}` (admin, full scope)

`GET` streams the archive (`application/gzip`, attachment). `DELETE` →
`204`. Names must match the strict backup pattern; an unknown one is
`404 not_found` (after the permission checks, never before). The download
requires full scope even though it is a read: the archive contains the
database snapshot (credential hashes, private notes) — material no other
endpoint returns. `GET` is also a [side-effectful GET](#cross-site-gets) —
it streams the whole snapshot off disk and the app opens it by top-level
navigation — so a cookie session proving neither header gets `403 csrf`.

Both arms are recorded on the `auth` logger with the acting admin and the
archive name (`Backup downloaded: <name> (<bytes>) by <user> (id <n>)`,
`Backup deleted: …`), at `WARNING`: taking the snapshot off the box is the
highest-value exfiltration this API permits and deleting it is the most
useful way to erase evidence, and the access line names neither actor nor
object.

### `GET /api/v1/recipes/{idOrSlug}/yaml`

The canonical schema-v2 YAML document.

→ `200`, `Content-Type: application/yaml; charset=utf-8`,
`Content-Disposition: attachment; filename="<id>.yaml"`.

### `GET /images/{sourceSlug}/{file}`

Recipe images from the library. **Requires authentication** (any role).
Segments are strictly validated (no path traversal; extension whitelist
`.jpg` `.jpeg` `.png` `.webp`).

→ `200` with correct `Content-Type` and `Cache-Control: private,
max-age=86400` (`private` because the response is authenticated — a shared
proxy cache must not serve it). Supports `Last-Modified` /
`If-Modified-Since` revalidation (`304`). Malformed segments are
`422 validation`; an unknown extension, missing file, or escaping path is
`404 not_found`.

### `GET /api/v1/tags`

Every tag with its recipe count and optional chip style:
`{"items": [{"name", "count", "icon", "color", "bg_color"}]}`.

### `PUT /api/v1/tags/{name}/style` (admin)

`{icon?, color?, bg_color?}` — sets the tag's chip style (Lucide icon name,
`#RRGGBB` colors); null clears a field. `404 not_found` when no recipe
carries the tag.

### `GET | PUT /api/v1/settings/fdc_key` (admin; PUT full scope)

The per-deployment USDA FoodData Central API key (free at
api.data.gov/signup). **Write-only**: `GET` → `{configured, masked}` (last
four characters only); `PUT {api_key}` stores/replaces it (empty string
clears). The key is sent to FDC as a header and never logged.

A `PUT` is recorded on the `auth` logger as `FDC API key set|cleared by
<user> (id <n>)` — who changed the deployment credential and whether they
removed it (which silently breaks every nutrition lookup). No part of the
key reaches the record, not even the masked tail the `GET` returns.

### `GET /api/v1/recipes/{idOrSlug}/nutrition`

The computed per-serving label. → `200 {"status": "none"}` before the
first compute, else:

```json
{
  "status": "complete | partial | stale",
  "serving_basis": 12,
  "basis_kind": "per_serving | per_batch",
  "calories_per_serving": 466.2,
  "per_serving": { "<key>": {"label", "amount", "unit", "dv_percent"?} },
  "total_grams": 1730.5,
  "matched_count": 12,
  "total_count": 13,
  "low_confidence": 0,
  "computed_at": "…",
  "computing_job_id": 7
}
```

`basis_kind` says what `serving_basis` divides by: `per_batch` when the basis
is 1 — the whole batch: "MAKES 1 LOAF", no servings at all, or an admin's
1 — unless the recipe's yield (its servings text up to the first comma or
semicolon: "MAKES ABOUT 2 CUPS, ENOUGH FOR 4 SANDWICHES" is cups) is ONE
single portion: its count is 1 (or "one"; "MAKES 1 TO 16 EGGS" starts at
one) and its head noun, the yield's last word, is on the ruling's list —
omelet, cocktail, sandwich, egg or drink, singular or plural ("MAKES 1
OMELET", "MAKES 1 COCKTAIL", "MAKES 1 TO 16 EGGS"; never "MAKES 12
SANDWICHES", a batch, or "MAKES 32 SANDWICH COOKIES", cookies) — the only
such nouns among the corpus's MAKES-1 yields; the rest
are loaves, quarts, pies, tarts, crusts, a square and a quarter cup of
dressing), whose one is a real serving (the user's ruling, 2026-09-28) —
else `per_serving`. A larger basis
divides the batch by a serves count or by a MAKES yield count, where one
"serving" is one of the yield ("MAKES TWO 9-INCH PIZZAS": one pizza), not the
batch. The app marks a per-batch label "per batch" beside its per-serving
header, over a line naming the recipe's MAKES yield when it has one ("The
recipe says "MAKES 1 LOAF", so one serving is the whole loaf.").

`low_confidence` counts the lines in the `check` bucket: auto-matched lines
below 0.5 confidence, or held for a `hold` reason (see the matches body),
that no one has reviewed yet (confirm/override/skip clears one) — never an
engine 0 g (`discarded` / `unmeasured` at `grams: 0`) unless it is held
`unnamed_food`.

`computing_job_id` appears **only for admins, and only while a compute is in
flight** — it is the handle for re-attaching a reopened page to a running job
(see the compute endpoint below). It is omitted for members on purpose: the
job endpoint it points at is admin-only, so a member handed the id would
poll, get a 403 on every attempt, and surface a false error on a page they
cannot compute from anyway. It is also absent from the `{"status": "none"}`
body unless a first compute is currently running.

`stale` means the ingredients — or the recipe's own steps or its title,
which the discarded-media rules read (a drain added or removed changes what
counts) — changed since the compute; matcher v11 made every computed recipe
stale once for that. The ~30-nutrient
key set and FDA Daily Values match the legacy app's panel.

### `PUT /api/v1/recipes/{idOrSlug}/nutrition` (admin, full scope)

`{serving_basis}` (1–1000) — change the per-serving divisor and recompute
instantly from stored matches (no FDC calls). The default is the first of:
the stored basis, the parsed `serves` minimum, the parsed **yield** count
(so `MAKES ABOUT 16 LARGE COOKIES` divides by 16, not by the whole batch),
then 1. A yield is not a serving count — it never reaches `serves` — but it
is a better starting divisor than the batch, and this endpoint is how an
admin overrides it. A basis change never clears `stale` — only a full
`…/nutrition/compute` re-match does. `422` before the first compute.

### `POST /api/v1/recipes/{idOrSlug}/nutrition/compute` (admin, full scope)

Starts a background match+compute and returns `202 {job_id}` immediately;
poll `GET /api/v1/nutrition/jobs/{id}` for progress (`status`: `running |
done | failed`) and re-fetch `…/nutrition` when it finishes. Single-flight
per recipe — a second call while one runs re-attaches to the same job — and
the recipe's `…/nutrition` body carries `computing_job_id` (admins only)
while a compute is in flight so a reopened page can re-attach. Cached and rate-limited
(~900 requests/hour shared budget); user decisions on unchanged lines
survive recomputes. Water/ice lines are matched locally for free. The job
fails (with the reason in its log) when no API key is configured, or when
FDC fails a request the compute needs — a search, or a food detail its
grams read (household portions, a bone-in cut's edible yield, a drained
can's share, a rule's record) or its totals read (a record's nutrient
sibling, when no cache holds it): its totals are not recomputed (lines
matched before the failure keep their new rows) and it stays `stale`, so
the next compute or `stale` sweep retries it. A line is
never stored counted at the printed weight because a yield could not be
fetched.

### `GET /api/v1/recipes/{idOrSlug}/nutrition/matches`

Per-line match transparency: the stored decision (`fdc_id`,
`description`, `data_type`, `confidence` 0–1, `grams`, `gram_source`:
`weight` (direct) | `portion` | `density` (estimate) | `piece` (estimate)
| `override` | `discarded` (a cooking medium the recipe throws away —
deep-frying oil ("for frying", or 400 g or more of oil), a brine's salt, a
buttermilk soak, a brine's sugar and the aromatics a step adds to a brine
the food is submerged (or weighed down) in and lifted out of before the
submerge — "Dissolve the salt, sugar, and paprika in the buttermilk … Add
the garlic and bay leaves, submerge the chicken in the brine"; "Add
brisket, 3 garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon
peppercorns, and coriander seeds to brine. Weigh brisket down with plate";
"8 whole cloves" too, read by its last word (the user's ruling, 2026-09-28;
never the submerged or weighed-down food, nor what the submerge's own
sentence adds to the brine, nor a second line of the same food) — stored as
`grams: 0`: resolved, adds nothing; an aromatic whose smaller share the
step WRITES ("3 garlic cloves" of "6 garlic cloves, peeled", the rest going
in the pot) stores the rest's grams and counts them; a "plus" line whose second part a step
eats — "1 cup plus 2 teaspoons table salt" with "remaining 2 teaspoons salt"
in the rub — stores that part's grams and counts them; a HELD medium's eaten
"plus" part is its grams too, held with it — "1 tablespoon plus 1 teaspoon
table salt" with 1 tablespoon in the drained pasta water and the "remaining 1
teaspoon salt" in the roux stores 6 g, `hold: discarded_medium`, and a
confirm counts those 6 g; so is the rest of a divided salt line whose WRITTEN
share goes in drained cooking water — "the remaining 1½ teaspoons salt and
the macaroni … Drain" of "2 teaspoons table salt" stores the other ½
teaspoon, 3 g, held) | `unmeasured` (a
matched line with no amount at all — "Lemon wedges, for serving" — or a sprig
the record gives no portion for, stored as `grams: 0`, its food kept, so it
leaves the review queue — or a sub-recipe line, below), `gram_basis`: a short human string of
what the grams were computed against — e.g. `"½ cup ≈ 118 mL"`, `"8¾
ounces"`, `"entered by hand"`, `"… × 0.57 edible (USDA refuse)"` for a
bone-in cut whose record publishes its raw refuse — or, for a WHOLE bird
("1 (4-pound) whole chicken") on a whole-bird record, its "yield from 1 lb
ready-to-cook" share (`"… × 0.61 edible (USDA ready-to-cook yield)"` on
171447) — `"… · approximate (gross weight, no USDA refuse portion)"` for a
bone-in, whole-bird or other refuse-bought line whose record publishes no
refuse portion (a whole turkey, a Foundation chicken part, a lamb chop, bird
pieces on the whole-bird record, whose yield is the whole bird's): counted at
the printed weight, bone included — no factor is borrowed (FDC gives no
turkey share) — and labelled, shellfish bought in the shell too (held
`in_shell`, below, and counted so once a person confirms it); the label is
the line's, read on the food's cached detail or else its cached search hit,
never lost for want of a detail no compute fetches (a Foundation or FNDDS
weight line); `"… · no edible yield read"` for one on an SR record whose
detail was never fetched (the basis never claims a yield the stored grams
lack, nor that the record has none) — `"4 × 336 g (USDA
edible bird portion)"` for counted birds ("4 Cornish game hens") sized by the
record's own edible bird rather than the printed weight, `"½ cup · USDA
portion of \"Onions, raw\""` for a volume on a record with no volume portion
of its own, read from a cached sibling's (the food stays the line's; "1 cup
fresh or frozen blueberries" on Foundation "Blueberries, raw" reads
"Blueberries, frozen"'s cup), `"… · nutrients of \"Cabbage, chinese
(pe-tsai), raw\""` for a line on a record that publishes no energy whose
totals read a sibling record's nutrients (Foundation napa cabbage, 2727583,
reads SR 169979; the food and grams stay the line's, and it is not held
`no_nutrients`; hand-entered grams say so too: `"entered by hand · nutrients
of \"Cabbage, chinese (pe-tsai), raw\""`),
`"pinch ≈ 1/16 tsp (USDA tsp portion)"` for a pinch or dash on a record with
no dash portion (a teaspoon ÷ 16), `"2 tablespoon ≈ 30 mL · juice only (the
zest is dropped)"` for a zest-plus-juice line counted on the fruit's juice
record, `"2 × 50 g egg + 2 × 17 g yolk, summed on the whole egg"` for an
eggs-plus-parts line counted on the whole-egg record,
`"… · drained (USDA can portion)"` for a drained can or jar (its printed
weight × the drained share of the record's own can portion), `"discarded in
cooking — counted as 0 g"`, `"discarded in cooking — only \"plus 2 teaspoons
table salt\" counted"`, `"discarded in cooking — only the part the recipe
keeps counted"` (a divided salt's written pot share, a divided aromatic's
written brine share), `"2/3 cup ≈ 16 crackers · USDA cracker portion"` for
crushed saltines (24 a cup, the corpus's own "⅔ cup crushed saltines (about
16)", on the record's one-cracker portion), `"18 × 13 g each (31 to 40 per
pound)"` for a bare count that prints its own count per pound, `"a sub-recipe —
counted as 0 g"`, `"no amount on the line — counted as 0 g"`, `"4
sprigs — a sprig is not measured, counted as 0 g"` — for
sanity-checking an estimate (null when there is no
amount; re-derived cache-only, never spends FDC budget), `status`: `auto |
confirmed | overridden | skipped | unmatched`, `hold`: why an `auto` line
is held out of the totals although its name confidence passes — `null`
(nothing holds it), `no_nutrients` (the record publishes no energy and is
missing protein, fat or carbohydrate, so counting it would add its grams at
0 kcal or a fraction of its energy; a record whose published macros already
make up 90 g per 100 g, such as an oil, is not held), `discarded_medium`
(frying oil, a brine or soak set to review, or milk curdled into cheese
whose whey is drained — and the salt, acid (lemon juice, vinegar) or
buttermilk the step that first names that milk puts in it; ¼ cup or more of
salt no step brines in or rubs on — a salt bed, an ice bath, a dunk that
leaves the liquid on the food — salt tossed with a vegetable in a colander
and rinsed off in that step, the soy sauce, sugar
or garlic of a brine the food then POACHES in (the recipe's title says
poach), and salt or baking soda a
step puts in boiling water (named earlier in that step or in the salt's
sentence) that a drain then follows — pasta water, a
blanching pot, a skinning bath, or a pot a skimmer or slotted spoon empties
(in the same step, or in the next when its sentence or the one before names
the water) — and sugar in a pot a skimmer or slotted spoon empties ("Bring
4 quarts water, sugar, and baking soda to boil … Using wire skimmer …,
transfer bagels to prepared wire rack"; a drain after a sugar keeps it: a
reserved cooking liquid, a jar); never a salt seasoned "to taste"; the
line's own amount written in the step, a WRITTEN smaller share of the line
that no other salt line starts with ("1 teaspoon of the salt", "the
remaining 1½ teaspoons salt", "½ teaspoon salt" of "1¼ teaspoons table
salt, divided" — the rest of the line is the row's grams), or
a bare "salt" when it is the recipe's only salt line — or, among several, the
one no step names with its amount and no volume makes a brine — or, with as
many such lines as bare mentions, the one in the same order ("Whisk flour
and salt" is the dough's, "bring water and salt to boil" the pot's) ("Add the
pasta and salt" is the 2 tablespoons' when the sauce names "1½ teaspoons
salt"); not a line that measures its salt apart, "plus salt for cooking …" —
are always held; salt a step dissolves in a written amount, the salt the
verb's object ("Dissolve salt in 2½ quarts water", not "dissolve sugar in 2
cups water, then whisk in the salt"), in a step that submerges the food, is
a brine at any volume, zeroed like one — a dough's salt dissolved in a little
water is eaten; these rules read the recipe's own steps only, never a
subsection's: a variation's pot never makes a main line a medium),
`in_shell` (shellfish bought in the shell — clams, mussels or oysters
scrubbed, live lobsters, shell-on shrimp — "shell-on shrimp …, peeled,
deveined …, shells reserved" too: its weight includes the shells the cook
peels off), with or without an amount (never 0 g counted); shucked shellfish, lobster
meat and clam juice name none of these: no record FDC answers publishes an edible share, so the gross weight
is not counted as meat; a LINE hold, like `second_food`),
`second_food` (the line names a second ingredient —
"egg whites plus 1 large egg", "chipotle chile in adobo sauce plus 2
teaspoons adobo sauce" — that the match does not cover; a counted fruit cut
into wedges, "plus 1 lemon, cut into wedges", is for serving and holds
nothing; such a line is also keyed apart from the first food's lines, e.g.
`egg plus white` for "5 large egg whites plus 1 large egg", so a decision on
`egg white` never reaches it. Two
shapes are counted by rule instead, unheld, under server switches on by
default: a zest or peel of at most a tablespoon plus the same fruit's juice,
either part first ("1 teaspoon grated lemon zest plus 2 tablespoons juice",
"½ cup juice plus 2½ teaspoons grated zest"), counts the juice amount on the
fruit's juice record (lemon 167747, lime 168156, orange 169098) with the
zest dropped, and eggs plus yolks or whites, or yolks plus whites ("1 large
egg, separated, plus 2 large yolks"), count the parts' summed piece weights
(egg 50 g, yolk 17 g, white 33 g) on the whole-egg record 748967. Their keys
name both parts, one key for either order: `lemon zest plus juice` (a zest
line whose item names no fruit takes the line's — "grated zest plus ½ cup
juice from 3 or 4 limes" is `lime zest plus juice`), `egg plus yolk`, `egg
plus white`, `egg yolk plus white` — the whole egg first, then the yolk,
whichever part the line names first; "whole" and a "with …" tail are not
part of it),
`unnamed_food` (the line names no food the matcher can read — a
continuation of the line above such as "lengthwise, seeded, and sliced thin
on bias", or "2 tablespoons juice" of no named fruit, with or without an
amount),
`dried_for_fresh` (the line asks for a fresh food — "1 teaspoon minced
fresh thyme" — and the engine's pick is a dried or ground spice or other
dried record; off when the server's dried-for-fresh switch accepts them;
never a fresh oregano, sage, tarragon, marjoram or chervil line — FDC has
no fresh record of them, so it counts on "Spices, <herb>, dried" (sage:
"…, ground"), a flagged approximation (below), a line offering the dried
form too),
`cured_for_fresh` (the line asks for a fresh meat — "bone-in fresh half
ham" — and the engine's pick is a cured, preserved record; the same
switch), `borderline`
(only when the server's borderline-band switch is on, off by default: an
engine pick scored from 0.52 up to 0.54); such a line sits in the `check` bucket until a person confirms,
re-picks or skips it — a person's decision clears the hold (a pick, a confirm,
a skip, a grams edit), and an un-skip re-derives it for the food now on the
line, so a person's food is never held for the engine's old reason (a
person's food — confidence 1, a pick or a decision, inherited or not — is
held again only by a LINE hold: `discarded_medium`, `second_food`,
`in_shell`; an un-skip is no confirm, and only a confirm or a pick on the
line clears one), and an engine row whose line the
second-food rule counts moves to the rule's record with the rule's grams,
as a compute writes it. A
decision reaching the line by `apply_to_all` or inheritance clears a FOOD
hold (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`, `borderline`,
`unnamed_food`) too, never a LINE hold (`discarded_medium`, `second_food`,
`in_shell`): a decision on the key names one food and cannot count the
line's other part, say what a discarded medium leaves or how much of a shell
is eaten) plus ranked `candidates`
for re-picking, `candidates_query` (the words FDC is asked for this line's
candidates, after normalization and the matcher's rewrites — e.g. `spices
pepper black` for a pepper line, `brandy` for "brandy or dry sherry" (an
"A or B" line reads A alone only when A's cached answer holds foods — an
empty one, like `pancetta`'s, keeps the whole phrase), or the singular
`pork tenderloin` whose cached answer a "pork tenderloins" line reads (a
line the rewrites changed never reads its singular form's answer); null
when the line has nothing searchable; a few rewrites are APPROXIMATIONS, flagged in
the server's rewrite table, for foods FDC has no record of: pancetta counts
as bacon, Asiago as Parmesan, whole allspice berries as ground allspice, lime
zest as lemon zest (`lemon zest`: "Lemon peel, raw", 167749) — FDC has no
lime peel, and its answer for `lime peel raw` ties lemon and orange peel —
chen pi (dried tangerine peel) as `orange peel` ("Orange peel, raw", 169103:
a raw-peel record, so the dried peel is counted about 3× short per gram — not
yet ruled on), pepperoncini as `pickled hot cherry peppers` ("Peppers, hot,
pickled", 2710095; FDC has no pepperoncini), and a FRESH oregano, sage,
tarragon, marjoram or chervil line on its dried spice record (the dried leaf
is several times as dense per gram; the fresh line's teaspoons and
tablespoons are sized by the record's own portions, a sprig is 0 g and a
leaf count has no grams) — a row on one of these records through one of
these rewrites (or a fresh herb line on its dried record) ends its
`gram_basis` with `" · approximation (counted as <record description>)"`,
e.g. `"from 2 ounce · approximation (counted as Pork, cured, bacon,
unprepared)"`; never "pancetta or bacon" (which reads the whole phrase), the
food's own line, or a person's pick of another record; the
ranker breaks two kinds of exact score tie toward the plainer record: the
"separable lean and fat" record over "lean only" (the default for an
unqualified cut), and the record naming fewer cookings — "Kielbasa, fully
cooked, unheated" over "…, grilled"; any other exact tie still goes to the
record FDC lists first) and
`line_amount` (the line's first amount that names a unit, as written — `"4
stick"`, `"1 piece"` — null when none does), `kcal_per_100g` (the picked
record's calories per 100 g as the totals count them — its energy, else
4/9/4 from protein, fat and carbohydrate — from the same caches ALONE, never
a fetch; null when nothing is picked or the record is uncached), `portions` (the picked record's
USDA household portions from the food-detail cache ALONE — reading them never
fetches; empty when the detail was never fetched or nothing is picked — each
`{amount, unit, description, grams, fill}`: `grams` the whole portion's
weight, `fill` the grams the line's `line_amount` weighs on it when the
portion NAMES that unit — its unit, or the first word of its description after
any count, `tbsp` for a tablespoon — e.g. `"4 sticks unsalted butter"` on
"Butter, without salt" (173430) fills its `stick` (113 g) with 452; null for a
portion of another unit. The app prefills a confirm's amount only when exactly
one portion fills, and lists the rest for reference),
`candidates_name_ingredient` (false when FDC's WHOLE cached answer — not
just the candidates shown — holds no record naming the ingredient, or the
answer was empty: the list is hopeless, not mis-ranked; null when FDC was
never asked), `candidates_cached_at` (when FDC was last asked them, null
if never — the search cache never expires on its own; the admin search
endpoint's `fresh=true` replaces it), `item` (the parsed ingredient item VERBATIM — it can carry
the line's parenthetical, e.g. `(1 1/2 sticks) unsalted butter`; a client
wanting a bare name strips parentheticals, as the app does; null when the
line has none), `others`: how many recipes hold an undecided line
with the same ingredient (keys are singular and accent-folded, so "onion"
and "onions" are one; the same recipe's other lines count) — at most what
`apply_to_all` (below) would reach, since a row whose line text changed since
its compute is counted here but skipped there — and `others_lines`: the same
rows counted as lines. A sibling on a DIFFERENT food counts whatever its
score — the decision changes its food. A sibling already on this line's food
counts only while it is still a flagged guess (confidence below 0.5) or held
by a food hold (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`,
`borderline`, `unnamed_food`): blessing it at confidence 1 is what moves it
out of the `check` bucket. A sibling held by a line hold (`second_food`,
`discarded_medium`, `in_shell`) is never counted, whatever its food or score: no
decision on the key releases it — nor is a sibling whose line names a
second food (one the second-food rule counts on its own record, or one not
matched yet, which the decision's food would hold `second_food`), nor an
unmatched discarded medium the engine holds (a brine sugar), nor a line of
shellfish bought in the shell (held `in_shell` on any food). These are
exactly the rows `apply_to_all` writes. One on this food at or above that threshold and unheld is already
counted (or short only an amount) and is neither counted here nor
rewritten, nor is one on this food the engine counts at 0 g whatever its
score or food hold (an amount-less line, a sprig) — a confirm would leave it
where it is. Candidates come
from the compute-time search cache only — reading this never spends the
FDC request budget. A stored decision whose line text changed since the
compute is reported as unmatched (`match: null`).

A sub-recipe line — "recipe(s) follow(s)" in its first alternative, a "(…
this page)" before its first comma ("1 recipe Buttery Croutons (this
page)", not "shrimp, peeled and deveined (see this page)"), or either
anywhere on a line opening "<n> recipe" — is not counted on a food (the
user's ruling: sub-recipes stay out of the main totals): it is stored
`confirmed` with no food, `grams: 0`, `gram_source: unmeasured`, the
description "Sub-recipe — made from its own recipe, not counted in these
totals", and resolved like a water line. A food offered first stays that
food: "½ teaspoon table salt or 1 recipe topping (recipes follow)" is the
salt. A bare count of the food itself — every amount unit-less, "3
hard-cooked eggs (recipe follows)", not "1 recipe Easy-Peel Hard-Cooked
Eggs", "4 cups Cream Cheese Frosting" or an amount-less line — is matched
like any other line and counted on its food; it stays the 0 g sub-recipe
only when its pick gives no grams ("8 Home-Fried Taco Shells (recipe
follows)").

A line with no amount whose item is seasoning to taste — salt, pepper,
"salt and pepper" and their common spellings — is confirmed as a deliberate
no-match ("Seasoning to taste — no measurable amount"), like water: it
contributes nothing measurable, and FDC's search for it returns vegetables
and salted nuts. A seasoning line WITH an amount is matched normally.

Decisions travel: at compute time a line whose item (the matcher's
normalized text, e.g. `without salt butter`) has a `confirmed` or
`overridden` food on any other line — another recipe's, or the same
recipe's — inherits that food — the most recent decision wins — with grams
from its own amounts, at confidence 1 and still `auto` (a decision made on
the line itself still wins). `skipped` does not travel: it is a call about
one recipe's line, not about the item.

### `PUT /api/v1/recipes/{idOrSlug}/nutrition/matches/{pos}` (admin, full scope)

A food decided here — a pick (`fdc_id`), or `confirmed: true` on a line that
has a food — becomes the INGREDIENT's decision, library-wide: it is stored in
its own row keyed by the ingredient (not by this recipe or this line), so
every other recipe's line of that ingredient inherits it at its next compute
as `auto` at confidence 1, and it survives this recipe being edited or
deleted. A grams-only edit decides the amount, not the food, and records no
ingredient decision; neither does `skipped`. The newest decision wins.
Ingredient keys are singular ("onion" and "onions" are one ingredient) and
accent-folded. A decided line also follows its text: an ingredient inserted,
deleted or reordered above it moves the line, and its decision moves with it;
an amount edit on a decided line keeps the food and the status and re-derives
the grams (a hand-typed weight for the old amount is dropped).

Override one line: `{fdc_id}` re-picks the food, `{grams}` hand-sets the
amount, `{confirmed: true}` blesses the auto match, `{skipped: true}`
excludes the line, `{skipped: false}` un-skips it — back to automatic
triage (`auto`), deliberately NOT `confirmed`, so a low-confidence match
is not silently blessed. Totals recompute instantly. A re-pick of a line
the engine discarded as a cooking medium keeps it discarded (0 g) whatever
food is picked — `{grams}` is how a person counts it. A re-pick of the
record the second-food rule counts a line on (the fruit's juice record for
a zest-plus-juice line, the whole egg 748967 for eggs plus yolks or
whites) keeps the rule's grams — the juice amount, or the parts' summed
weights — and its `gram_basis`; a pick of any other record on such a line
gets grams from the line's own first amount (the zest's teaspoon, the
whole eggs) like any pick. An engine pick below
0.5 is stored without fetching FDC's food detail, so a volume or count line
may have no grams yet; `{confirmed: true}` resolves them (at most one food
detail fetch). `{confirmed: true, grams}` confirms the food WITH its amount
in one write (the queue's grams-on-confirm): the line is `confirmed` with
`gram_source: override`. `422` for `{grams}`
on a line with no matched food (there is nothing to scale — pick a food
first).

Add `apply_to_all: true` — together with `fdc_id` or `confirmed: true`,
the decision being broadcast — to land the same food on every other
undecided (`auto` / `unmatched`) line with the same ingredient item (other
recipes, and this recipe's other lines), each with grams from its own amounts,
and recompute those recipes' totals. A line on a different food is a target
whatever its score; a line already carrying that food is one only below the
flagged threshold (confidence 0.5) or while held by a food hold, and not
counted at an engine 0 g (an amount-less line, a sprig), where
rewriting it as `auto` at confidence 1 with its hold cleared stops it being a
guess — how confirming one line clears an ingredient's whole group. A line
already on that food at or above 0.5 and unheld is left as it is, as is a
line a line hold holds (`second_food`, `discarded_medium`, `in_shell`,
whatever its food or score), a line that names a second food (counted by the
second-food rule, or unmatched), shellfish bought in the shell and an
unmatched discarded medium the engine holds — the same
rows `others` leaves out, so the offer and the apply agree.
The rows land
as `auto` at confidence 1, machine propagation of a human decision exactly
like inheritance — not as a human status, so a wrong pick applied
library-wide is corrected the same way, by a second `apply_to_all` with
the right food. A line a person already decided is left alone, as is one
whose text changed since its compute. The response carries `applied:
{recipes, lines, failed, completed, completed_recipes}`: `completed` counts
the reached recipes whose stored status turned `complete` with this apply
(the line's own recipe is not among them, nor a reached recipe that was
complete already — a different-food pick reaches counted lines) — what the
queue's `finishes` promised, so the receipt can say whether it came true —
and `completed_recipes` lists their ids, so a shortfall can be named;
`lines` counts the lines the decision moved —
whose review bucket changed, or that took the decided food (a line left
short of an amount on it too, which stays `no_grams`) — every line `others`
counted, less one a person decided meanwhile, one whose text changed since its compute, or one whose recipe failed —
`recipes` the recipes holding one, and `failed` how many recipes
failed part-way (their document would not decode, or the provider failed
while fetching a food detail one of their lines' grams read — household
portions, an edible yield, a drained can — or while their totals
recomputed — logged; what was written before the failure stays).
The decision itself needs no FDC call when the food is in a cached search
answer and its grams need no food detail no cache holds, so it lands with no
key set or the hourly budget spent. Grams that need one — a volume or count
amount (household portions), or a weight an SR Legacy record's edible yield,
drained can or game hen scales (a bone-in chop, a drained can) — fetch it;
when FDC fails the pick (or the confirm resolving an engine pick's grams)
answers `422` with nothing written, never a row stored at the printed
weight. `422`, with nothing written, when the request carries no food
decision (`grams` alone or `skipped`), or the line has nothing searchable
to match on.

### `GET /api/v1/nutrition/search?q={term}&fresh=` (admin, full scope)

Search USDA FoodData Central for a term and get ranked `{items: [{fdc_id,
description, data_type, confidence}], query, cached, cached_at}` (top 8;
`query` is what FDC was actually asked after normalization and rewrites,
`cached` whether this answer was served from the search cache, `cached_at`
when FDC was last asked it — the cache never expires on its own). Pass
`fresh=true` to bypass the cache and replace its row with a live answer
(one FDC request; the next compute of any line with that item sees it
too; a live answer with NO hits is reported but does not replace a stored
answer that had some — the cache never expires and an empty row counts as
a hit, so it would blank every line with that item for good) — the manual escape hatch
for when the matcher searched the wrong words and none of a line's
`candidates` fit. Feed a chosen `fdc_id` back through
`PUT …/nutrition/matches/{pos}`. Admin + full scope because a cache miss
SPENDS the FDC request budget (the per-line `matches` read stays
cache-only so members never can) — which also makes it a
[side-effectful GET](#cross-site-gets): a cookie session with neither
`X-Requested-With` nor a same-origin `Sec-Fetch-Site` gets `403 csrf`.
Repeat terms are served from the same search cache the matcher uses. The term is normalized like an ingredient
line, so it shares those cache keys and ranking — including the matcher's
rewrites of phrases FDC files elsewhere (pepper as a spice: `pepper`,
`black pepper`, `red pepper flakes` search FDC's `Spices, pepper, …`
records; brand liqueurs and spirits — Grand Marnier, Calvados, spiced rum,
bourbon — search the generic liqueur, brandy, rum and whiskey entries). `422` for a blank term,
one over 120 characters, or when no FDC API key is configured.

### `POST /api/v1/nutrition/bulk` (admin, full scope)

Start a background compute. Optional body `{"scope": "..."}`:

| `scope` | Covers |
|---|---|
| `missing` *(default)* | Recipes with no stored nutrition. |
| `stale` | Recipes whose INGREDIENT lines, own steps or title changed since their last compute — the results the UI already labels `stale` — or that were computed under an older matcher version (the version is part of the staleness hash, so a matcher change re-resolves every engine row while decisions stand). Re-resolving spends FDC only for words the change altered. |
| `all` | Every recipe, computed or not. |

A body is optional; sending none means `missing`, which is the historical
behaviour. An unrecognised scope is `422` rather than a silent fallback —
computing the wrong set spends real FoodData Central budget.

→ `202 {"job_id", "scope", "total"}` (`total` is the number of recipes
selected, so a `stale` sweep that finds nothing is visible immediately);
`409 conflict` while one is running. Failures land in the job log — nothing
is skipped silently. A job interrupted by a server restart is marked
`failed` at the next boot.

Recomputing is non-destructive: confirmed, overridden and skipped ingredient
matches whose raw text is unchanged are preserved — checked at write time, so
a decision made through the review UI while that recipe's compute is waiting
on FoodData Central survives it. A broad scope re-resolves `auto`,
`unmatched` (the engine's own "no match", not a decision) and genuinely
changed lines. A previously empty FDC search answer is served from the cache,
so an `unmatched` retry only finds something once the matcher's normalised
query or the cache changes.

A recipe already being computed by a per-recipe job is skipped by the sweep
(logged in the job) rather than computed twice; while a sweep is on a recipe,
`GET /recipes/{id}/nutrition` reports its `computing_job_id`.

A body is optional, but a body that is present must be `application/json`
(`422` otherwise, like every other endpoint) — a scope sent with another
content-type is refused, never silently treated as `missing`.

Note `stale` is derived, not stored: `recipe_nutrition.status` accepts the
value in its CHECK constraint but nothing ever writes it, so staleness is a
comparison between the stored `ingredients_hash` and one recomputed from the
recipe.

### `GET /api/v1/nutrition/bulk/counts` (admin)

How many recipes each `POST /nutrition/bulk` scope would select right now —
the preview the Settings → Nutrition scope control shows before the click:

```json
{"missing": 1190, "stale": 3, "all": 1198}
```

The same selection the sweep runs (`bulkScopeIds`), so each number is the
`total` the corresponding 202 would echo. Re-read it after a job finishes;
a `stale` count of `0` means every computed recipe still matches its
ingredients. Spends no FDC budget and writes nothing, so a `read` PAT may
read it — but `stale` hashes every computed recipe synchronously on the
serving isolate (~110–190 ms across a 1,198-recipe library), which makes
this a [side-effectful GET](#cross-site-gets): a cookie session with neither
`X-Requested-With` nor a same-origin `Sec-Fetch-Site` gets `403 csrf`.

### `GET /api/v1/nutrition/jobs/{id}` (admin)

`{id, status, total, done, failed, log, started_at, finished_at}`.

### `GET /api/v1/import/candidates` (admin)

The allowlisted import directory (env `IMPORT_DIR`, default
`DATA_DIR/import`) and the source folders detected inside it (the
directory itself plus direct children):

```json
{
  "import_dir": "/data/import",
  "items": [
    {"path": "The Complete America_s Test Kitchen …", "kind": "v1",
     "file_count": 1198}
  ]
}
```

`kind`: `v1` (Recipe Extraction root with `recipes/*.yaml`) or `legacy`
(old SaltToTaste v0 data dir with `_recipes/`).

The scan is synchronous over the import directory and every direct child,
so this is a [side-effectful GET](#cross-site-gets): a cookie session with
neither `X-Requested-With` nor a same-origin `Sec-Fetch-Site` gets
`403 csrf`.

### `POST /api/v1/import` (admin, full scope)

`{path}` — a folder relative to the import directory (or absolute), which
must canonicalize inside it (symlink escapes rejected). Format is
auto-detected. Starts a background job (own DB connection in an isolate;
imports are idempotent — unchanged files skip, changed files update with
an automatic backup). → `202 {"job_id"}`; `409 conflict` while an import
is already running.

### `GET /api/v1/import/jobs/{id}` (admin)

`{id, status: running|done|failed, source_path, legacy, total, done,
imported, updated, skipped, failed, log, started_at, finished_at}` —
`log` carries per-file warnings; a job interrupted by a restart is marked
`failed` at the next boot.

## Serving & deployment behavior

- **SPA fallback**: a `GET` for a non-API path with no file extension
  that matches nothing returns `public/index.html`, so deep links
  (`/r/<slug>`) survive refresh/bookmarks. API paths (`/api/…`,
  `/healthz`, `/images/…`) always stay JSON.
- **Security headers**: every response carries
  `X-Content-Type-Options: nosniff` and `Referrer-Policy: same-origin`;
  HTML additionally gets a same-origin `Content-Security-Policy` and
  `X-Frame-Options: DENY`. "Every" includes the static `public/` tree
  (`/index.html`, `/main.dart.js`, assets), which dart_frog serves from a
  cascade arm *above* the route middleware: the entry point wraps the whole
  cascade, not just the routes, because for a while `/r/<slug>` and
  `/index.html` returned the same shell with different headers.
- **Request bodies** must be sent as `Content-Type: application/json`; anything
  else is a `422 validation` envelope. This is a CSRF defence, not pedantry: a
  cross-site HTML form can only emit the three "simple" content types, and
  `enctype="text/plain"` can be shaped into a valid JSON document — so the
  unauthenticated endpoints (`/auth/login`, `/auth/setup`), which have no
  session for the `X-Requested-With` check to key on, had nothing else standing
  in front of them.
- **Env config**: `PORT`, `DATA_DIR`, `LOG_LEVEL`, `TRUST_PROXY`, `TRUSTED_PROXIES`,
  `SECURE_COOKIES`, `IMPORT_DIR`, `SEARCH_RATE_LIMIT` (text searches/min per
  user, default 60; `0` disables), `API_TOKEN_RETENTION_DAYS` (days a revoked
  token row is kept before daily pruning, default 90; `0` keeps forever),
  `CONNECTION_IDLE_TIMEOUT_SECONDS` (idle/stalled-connection reap, default 75;
  `0` disables — bounds slowloris half-open sockets),
  `SEARCH_WORKER_ISOLATES` (background isolates running the ranked search off
  the serving isolate, default 1; `0` runs it inline),
  `LOG_MAX_BYTES` (admin log-store rotation size under `<dataDir>/logs/`,
  default 4 MiB; `0` disables), `BACKUP_RETENTION` (backups kept per
  trigger, default 14, minimum 1), `TZ` (container tzdata),
  plus the dev-only `DEV_ALLOW_CORS`.
- **Graceful shutdown**: SIGTERM/SIGINT (`docker stop`) drains in-flight
  requests (bounded, force-closed only past the bound), then closes SQLite
  cleanly — the WAL checkpoints and the next boot needs no recovery. A slowloris
  half-open socket is reaped by the initial close and never extends the drain.
- `/data` must be a **local filesystem** (SQLite WAL is unsafe on
  NFS/SMB); the app assumes domain-root serving (sub-paths deferred).

## CLI

`dart run salt_server:recover [--data-dir=PATH]` — prints a single-use
account-recovery code (valid 15 minutes) and exits. In the container the
same tool ships as a compiled binary, needing no arguments (`DATA_DIR` is
already set):

```sh
docker exec <container> /app/recover
```

The code is printed to **that command's** stdout — it is not in the server's
log, so `docker logs` will never show it. Redeem it at `/recover` in the app
with a username and a new password: that account is reset to an enabled
admin, created first if it does not exist, and both its sessions and all of
its API tokens are revoked (a PAT is its own credential and would otherwise
outlive the reset). The way back in when every admin is disabled, locked
out, or gone.

Being able to run this on the server host (or `docker exec` into the
container) is the whole authorization story — the same trust model as the
first-boot setup code. `POST /api/v1/auth/recover` therefore takes no
credentials; it answers `403 forbidden` when no code is pending or the
pending one expired, `422 validation` for a wrong code or an invalid
username/password, and `429 locked` once the per-IP rate limit trips.
Rate-limited like `POST /api/v1/auth/login` (5 consecutive failures, then an
exponential lockout to 15 minutes) and every failed attempt is logged:
the endpoint is unauthenticated and grants admin, and checking a code costs
only a SHA-256, so it would otherwise be the cheapest thing in the API to
guess at. Only a SHA-256 digest of the code is stored, so the printed line
is the only place it can be read. Safe to run against a live server (no
restart needed). Exit codes: 0 ok, 64 usage.

`dart run salt_server:import <source-root> [--data-dir=PATH] [--legacy]` —
bulk-imports a Recipe Extraction source root (`source.yaml`,
`recipes/*.yaml`, `images/`) into the database and writes canonical v2
exports to `<data-dir>/library/<source-slug>/`. Idempotent: unchanged
recipes are skipped by content hash. Exit codes: 0 ok, 1 failures
occurred, 64 usage.

A **legacy SaltToTaste v0** data directory (the old Flask app's
`_recipes/` + `_images/` layout) is detected automatically (or forced with
`--legacy`) and mapped to schema v2: `description` → `background`,
`prep`/`cook`/`ready` → `times`, flat ingredient strings → structured
lines via the shared ingredient parser, `image`/`imagecredit` →
`images.*`, `source` URL → `source.url`. Old Edamam `calories` values are
dropped with a warning (nutrition is recomputed in P6). Ids are
`v0-<slug>` under library source `legacy-import/`.
