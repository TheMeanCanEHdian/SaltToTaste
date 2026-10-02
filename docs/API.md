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
  | `zero_row` | 422 | A bare confirm of a below-gate zero row (its food is a hidden guess): pick a food or skip it |
  | `line_moved` | 409 | A match write whose `raw` names a line no longer at its position (a save since); the envelope adds `position`, where that line is now (or null) |
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
(the only one in `no_match` / `check` / `no_grams`, whatever the filter)
AND a confirm can count it: a `check` line that has grams, or a `no_grams`
line (its confirm takes the amount) — else 0. A `skipped` or `counted`
line is 0, and so are a `no_match` line (no food to confirm) and a `check`
line with no grams (a plain confirm converts it only if USDA can; when it
cannot, the line lands in `no_grams` and the recipe stays partial). The
count may therefore under-promise a `check` line whose cached record does
convert, but it never promises what a confirm may not count. A group item
overrides it with the group's count (below). Every `finishes` count (both
modes, and `finishable`) reads the STORED match rows: for a recipe edited
since its last compute (`stale` on its nutrition — derived, never stored) a
reworded or added line has no row of its own, so the count is an upper
bound for that recipe (the apply skips a reworded line; the recompute
cannot account an added one).
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
its fix panel come from that recipe's `…/nutrition/matches`). An item's
`position` is its row's STORED position: after a save and before the next
compute, that line may sit elsewhere in the recipe (the per-recipe GET shows
each line its row where it is now). Send the item's `raw` with the PUT: a line
no longer at that position is refused with `409 line_moved` naming where it
is now, never written onto another line (the app finds the line by its text
in the recipe's matches, sends that line's position and text, and reloads on
a 409).

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
example IN `no_grams` (the confirm on it takes its grams in the same step; a
`check` or `no_match` example with no grams finishes nothing, since a plain
confirm cannot promise grams — it may under-promise one whose cached record
converts); a group of one (a line hold, a decided line)
counts its own recipe when that line is the recipe's last open one and it
has grams or sits in `no_grams`. A pick of a different food recomputes every
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
(`second_food`, `discarded_medium`, `starter_discard`, `coating`,
`partial_pour_away`, `in_shell`): no decision on its key
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
1 on a larger yield or serves count — unless the recipe SERVES one (its
serves count starts at 1: "SERVES 1", a bare "1") or its MAKES yield is
exactly ONE single portion: a yield count of 1 ("1" or "ONE") whose head
noun — the last word of the yield's first clause (up to a comma or
semicolon), a trailing parenthetical dropped ("MAKES 1 COCKTAIL (ABOUT 4
OUNCES)" is a cocktail) — is on the ruling's list, singular: omelet,
cocktail, sandwich, egg or drink. "MAKES 1 OMELET" and "MAKES 1 COCKTAIL"
are single portions; "MAKES 12 SANDWICHES" is a batch, "MAKES 1 SANDWICH
LOAF" a loaf, "MAKES 32 SANDWICH COOKIES" cookies, and a range starting at
one, "MAKES 1 TO 16 EGGS", names a plural and is a batch (its totals are
the range's midpoint, not one egg). These are the only such nouns among the
corpus's MAKES-1 yields; the rest are loaves, quarts, pies, tarts, crusts,
a square and a quarter cup of dressing. A single portion is a real serving
(the user's ruling, 2026-09-28), so it reads `per_serving`, as does every basis above 1: a larger basis
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
stale once for that. It also means the recipe's match rows were laid out
anew since (v22, Run 052 O1/S2): the stamp records the layout sequence it
was computed on (`recipe_nutrition.layout_seq`, migration 013), and the
recipe is fresh only while its inputs hash AND its layout are still those —
a save deleting a line, a person's write laying the rows out for it (the
line's row dropped) and a save restoring the line hash as before, but the
restored line has no row, so the recipe reads `stale` and the `stale` sweep
computes it. No stamp is fresh with a line that has no row. Every reader
of freshness — this body, the `stale` bulk scope, the job's re-run — reads
both halves. The layout sequence is one global counter (migration 013), so
a recipe deleted and re-created under its id never repeats a sequence a
writer read before the delete. Migration 013 stamps each existing
computation with its recipe's layout sequence (0 for a recipe never laid
out — every recipe computed before migration 012), and at every boot (v24,
Run 054 H4) each recipe with a stamp or match rows and no layout is seeded
one in a single transaction: a sequence drawn from the counter, the
recipe's current lines as its texts (or none, when a row does not stand on
its line and the old lines are unknown), and its stamp's 0 moved onto that
sequence — so an unedited recipe stays fresh through its first person's
write or apply-to-all after the upgrade, and every later layout, the first
included, draws a new sequence (v23's keep-0 first layout is gone: it let
a delete and re-create repeat 0, and recorded edited lines under the
stamp's 0). A recompute that re-matches nothing (a person's write, an
apply-to-all reaching the recipe, the serving-basis change below) carries
the stored stamp only while the stored recipe still hashes to it (v24, Run
054 O3: an edit, this recompute and a revert otherwise read fresh over the
edited recipe's totals; it stamps no hash, `stale`), and computes its totals on the STORED recipe and its
rows in the same step that writes them — after every food detail it
needed was fetched — never on a recipe or rows read before an await, so a
newer compute's fresh stamp never sits over older totals (v23, Run 053
O4). The ~30-nutrient
key set and FDA Daily Values match the legacy app's panel.

### `PUT /api/v1/recipes/{idOrSlug}/nutrition` (admin, full scope)

`{serving_basis}` (1–1000) — change the per-serving divisor and recompute
instantly from stored matches (no FDC calls). The default is the first of:
the stored basis, the parsed `serves` minimum, the parsed **yield** count
(so `MAKES ABOUT 16 LARGE COOKIES` divides by 16, not by the whole batch),
then 1. A yield is not a serving count — it never reaches `serves` — but it
is a better starting divisor than the batch, and this endpoint is how an
admin overrides it. A basis change never clears `stale` — only a full
`…/nutrition/compute` re-match does. `422` before the first compute. The
basis is read when the totals are stamped, after the compute's awaits, so a
save of `serves` during a first compute is the basis it stamps under. A
person's match write on a recipe never computed (or whose first compute
failed part-way) stores totals that read `stale`, never fresh, so the
`stale` sweep computes it.

### `POST /api/v1/recipes/{idOrSlug}/nutrition/compute` (admin, full scope)

Starts a background match+compute and returns `202 {job_id}` immediately;
poll `GET /api/v1/nutrition/jobs/{id}` for progress (`status`: `running |
done | failed`) and re-fetch `…/nutrition` when it finishes. Single-flight
per recipe — a second call while one runs re-attaches to the same job, and
when a save cut that job's compute off (its totals stamped stale) the job
computes the stored recipe again before it ends (at most three passes;
since v23 a recipe still stale after the third is logged and counted
failed: the job ends `failed`, a bulk sweep counts it in `failed` and its
log names it). A `stale` or other bulk sweep computing the recipe is the
job a call re-attaches to, and it runs the same step (v22, Run 052
S5/O5). The
recipe's `…/nutrition` body carries `computing_job_id` (admins only)
while a compute is in flight so a reopened page can re-attach. Cached and rate-limited
(~900 requests/hour shared budget); user decisions on unchanged lines
survive recomputes. Water/ice lines (since matcher v21 "filtered water"
too) are matched locally for free, as are equipment lines (since v21 a
banana leaf: the cochinita pibil's wrapper, not eaten). The job
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
`weight` (direct) | `portion` | `density` (estimate: a kitchen-figure
table for pantry staples, read before a record's own volume portions; since
matcher v18 its key matches the line's item as a word — 'salt' never sizes
"unsalted peanuts" (the normalizer's "without salt" is the food's state)
nor 'water' "watermelon", though 'nuts' still sizes "walnuts" — ice cream
is 0.558 g/mL (168809's "cup (4 fl oz)" 66 g a half cup), and dry milk,
milk powder, buttermilk powder, water chestnuts, ricotta, cream cheese and
oil-packed sun-dried tomatoes, which a key names but which are not its
food, weigh on their record's own volume portion instead ("½ cup plus ⅓
cup nonfat dry milk powder" is 100 g, not 203 g; a record's "whipped"
portion sizes only a whipped line, and since matcher v21 a portion that
measures what the food is made from — 2708216 Popcorn's "1 cup, unpopped,
yields" 193 g — sizes no line that names the popped food: "1 cup lightly
salted popcorn" is its "1 cup, popped" 14 g; since matcher v23 only a
line saying popcorn or popped, on a record with a popped portion, and
never one measuring the kernels ("½ cup popcorn kernels", "unpopped"
— 96.5 g, the popped mass they make; since matcher v24 read on what the
amount MEASURES, the line before a paren or a "from": "8 cups popped
popcorn (from ⅓ cup kernels)" is 112 g, not the yields cup's 1,544 g,
kettle and caramel corn are popped, and "½ cup popcorn kernels (about 8
cups popped)" keeps 96.5 g) — every other food keeps its own
"yields" portion, as a gelatin package's 540 g or a coconut's 206 g); since matcher v19 so do almond and
apple butter, and any item where a key only modifies a compound — the
key followed by "of" or "seed(s)": "2 teaspoons cream of tartar" is its
record's `tsp` 6.0 g, not 'cream' 1.01's 10.0 g, "¼ cup mustard seeds"
the ground seed's 24.6 g, not prepared 'mustard' 1.05's 62.1 g; a nut the
item names weighs on its record's own volume portion ahead of the
generic 'nuts' 0.55 ("½ cup unsalted roasted peanuts" is 173806's `cup`
146 g a cup, 73 g); since matcher v20 a key that only modifies the
item's head noun, on a record that names the key's food and has its own
volume portion, weighs by that portion ("¾ cup Dutch-processed cocoa
powder" is 169594's `cup` 64.5 g — the corpus's "1 cup (3 ounces)" — not
'cocoa' 0.52's 92 g; vanilla extract and cayenne pepper by their records'
`tsp`), while a key the record does not name keeps its figure ("panko bread
crumbs" on plain dry crumbs stay 'panko' 0.25), as does any key on a
record with no volume portion; sugar snap peas are no 'sugar' ("2 cups
sugar snap peas" is 170010's `cup, whole` 126 g, not 402 g); since
matcher v21 apple, currant and jalapeño jelly weigh 1.42 g/mL (169642
"Jellies"' `serving 1 tbsp` 21 g: "3 tablespoons apple jelly" is 62.99 g
— scoped to those names, so "apricot preserves or hot pepper jelly" keeps
its record's cup), and three stand-in figures the user approved as flagged
approximations, whose `gram_basis` ends `" · approximate (<stand-in>
density)"`: ground Aleppo pepper on paprika's 0.47 (FDC has no Aleppo
record), Pecorino Romano that says neither grated nor shredded on the
table's Parmesan 0.42 (since matcher v23 no corpus line; since v24
labelled `"· approximate (Parmesan density)"`, the figure it weighs on —
grated Parmesan is 0.24), ghee on oil's
0.92 (its record publishes no portion) — e.g. `"2 tablespoon ≈ 30 mL ·
approximate (paprika density)"`; since matcher v23 a line that says
grated Parmesan or Pecorino weighs the corpus's own printed conversion,
0.24 g/mL ("1 ounce Parmesan cheese, grated (½ cup)" and every grated
pair; the user's ruling Q6: a weight ATK prints wins) — "¼ cup grated
Pecorino Romano cheese" is 14.18 g, not 0.42's 24.84 g — whatever the
record (since matcher v24 ahead of the record's own cup portion too: an
FNDDS-style "1 cup" 100 g portion no longer weighs "¼ cup grated" at 25
g; and a volume "plus" part of the line weighs on the line's words: "1
ounce Parmesan cheese, grated (½ cup), plus 2 tablespoons" is 28.35 +
7.09 g), with `gram_basis` `"1/4 cup ≈ 59 mL · grated, at ATK's printed 1
ounce = ½ cup"`, and a line that says shredded weighs the corpus's
printed shredded pair, 3 ounces a cup, 0.36 g/mL ("1½ ounces Parmesan
cheese, shredded (½ cup)" and every other shredded pair), basis `"… ·
shredded, at ATK's printed 3 ounces = 1 cup"` — shredded Pecorino, which
the corpus never prints, on it and flagged `"· approximate (shredded
Parmesan density)"`: "¼ cup shredded Pecorino Romano cheese" is 21.26 g;
a "plus" part that prints its own weight weighs it, the parenthesis after
it a restatement — "1 Parmesan cheese rind, plus 3 ounces Parmesan,
shredded (1 cup)" is 85.05 g `"from 3 ounce"`, never its "(1 cup)" by a
density; since matcher v24 a part of ANOTHER food stands in for the line
only when the line's own primary, read on its text before the "plus",
weighs nothing (the rind) — "¼ cup grated Parmesan cheese plus 1 ounce
Pecorino, grated (½ cup)" is the quarter cup's 14.18 g, never the
Pecorino's 28.35; and a powder on a record of the drink made from it
("…, powder, prepared with whole milk") reads only its `dry` portions —
none: no grams, never the made-up drink's `cup (8 fl oz)` 265 g) |
`piece` (estimate; since matcher v21 the piece table reads "green
pepper", "Fuji" and "yolk" by its bell pepper 119 g, apple 182 g and egg
yolk 17 g: "1 small green pepper", "3 Fuji, Gala, or Golden Delicious
apples", "2 large yolks")
| `override` | `discarded` (a cooking medium the recipe throws away —
deep-frying oil ("for frying" — since matcher v24 "for deep frying" too —
or 400 g or more of oil — or, since matcher v23, ¼ cup or more of oil, its
same-food "plus" part included, in a recipe whose dredge is held `coating`
by its directions: the oil a dredged food fries in, 0149's "1¾ cups
vegetable oil" heated to 375 degrees, 0198's "⅔ cup" whose step discards
it, 0042, 0114, 0288; a sautéing tablespoon stays counted — or, since
matcher v24, with or without a dredge, ¼ cup or more of oil a sentence
naming it heats to a frying temperature, discards ("Discard the oil") or
pours off: 0491 Tostadas' "¾ cup vegetable oil" heated "to 350 degrees",
0 g; a part a sentence keeps, "pour off all but 2 tablespoons oil" (1193
Crispy Tempeh's cup), is counted — 28 g of the 224 —, the rest discarded;
0040's dressing oil, 0500's rice oil, 0672's coconut oil and the fritter
oils of 0674/0675, which no sentence heats to a temperature or discards,
stay counted), a brine's salt, a
buttermilk soak, a brine's sugar and the aromatics a step adds to a brine
the food is submerged (or weighed down) in and lifted out of before the
submerge — "Dissolve the salt, sugar, and paprika in the buttermilk … Add
the garlic and bay leaves, submerge the chicken in the brine"; "Add
brisket, 3 garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon
peppercorns, and coriander seeds to brine. Weigh brisket down with plate";
"8 whole cloves" too, read by its last word (the user's ruling, 2026-09-28;
never the submerged or weighed-down food, nor what the submerge's own
sentence adds to the brine, nor a second line of the same food); since
matcher v22 also a dry cure's salt or sugar a step rubs on and a later
sentence rinses off the food — "Rub each side evenly with salt mixture …
Refrigerate for 5 to 7 days … Rinse brisket and pat it dry" (New
England–Style Home-Corned Beef, the user's ruling Q3, 2026-10-01), never a
dry brine whose EXCESS is rinsed off ("Rinse off any excess salt", Roast
Salted Turkey) nor a rub no step rinses (a barbecue rub) — stored as
`grams: 0`: resolved, adds nothing; an aromatic whose smaller share the
step WRITES ("3 garlic cloves" of "6 garlic cloves, peeled", the rest going
in the pot) stores the rest's grams and counts them; a "plus" line whose second part a step
eats — "1 cup plus 2 teaspoons table salt" with "remaining 2 teaspoons salt"
in the rub — stores that part's grams and counts them (the FIRST part,
when the second is not named and a step names the smaller first: 0114's
"1 tablespoon plus ¾ cup vegetable oil" beats "1 tablespoon of the oil"
into the eggs, `gram_basis` `"discarded in cooking — only \"1
tablespoon\" counted"`, since matcher v23); a HELD medium's eaten
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
of its own, read from its SR sibling's — cached, or fetched once by the
first volume line that needs it (since matcher v17: Foundation pecans,
garlic, green cabbage, carrots, celery, baby spinach, iceberg and napa
cabbage read SR "Nuts, pecans", "Garlic, raw", "Cabbage, raw", "Carrots,
raw", "Celery, raw", "Spinach, raw", "Lettuce, iceberg (includes crisphead
types), raw" and "Cabbage, chinese (pe-tsai), raw") (the food stays the
line's; since matcher v19 a shredded, grated or thinly sliced line with no
portion of its own words reads a `shredded` or `grated` portion before the
median: "3 cups thinly sliced green cabbage" is `cup, shredded` 210 g,
"2⅔ cups shredded carrots" `cup grated` 293 g; "1 cup
fresh or frozen blueberries" on Foundation "Blueberries, raw" reads
"Blueberries, frozen"'s cup, "1¼ cups whole almonds" on Foundation "Nuts,
almonds, whole, raw" SR "Nuts, almonds"' `cup, whole`), `"8 · USDA
per-item weight"` for a bare count on the record's one-item portion — SR
Legacy's amount-1 bare noun counts as one ("shell" 12.9 g of "Taco shells,
baked", "leaf" of Swiss chard, "pepper" of a dried chile, "medium" of a
pear — a sub-gram "pepper", 168570's 0.5 g, weighs only a small DRIED
chile: an arbol or bird chile, or one the line calls small and dried —
since matcher v20 small in the item's own words, never its prep, and not
large ("2 dried New Mexican chiles, … torn into small pieces" has no
grams); a
fresh Thai chile, or any other pepper line, on it has no grams), and of
several portions the item names the medium one ("4 leaves Bibb lettuce" on
"leaf, medium"), or the small one when the line says small ("1 small
baguette" on "1 mini baguette", 152 g) — since matcher v19 read from the
item's own words, before its prep: "1 baguette, cut into small cubes" is
324 g, "2 large pita breads, cut into small wedges" two regular pitas; a portion over 250 g is a
prepared-dish serving, never one item, unless it is a numbered portion
naming the item's own noun (since matcher v17: "1 baguette" on "Bread,
French or Vienna"'s "1 baguette (about 22" long)", 324 g; an SR bare noun
such as "roast" 625 g stays capped; since matcher v21 a bare `fruit`
portion, or a bare one naming the item's own noun, up to 350 g is one
item: "2 mangos, peeled, pitted, and cut into ½-inch dice" is 169910's
`fruit without refuse` 336 g twice, 672 g, "4 whole chicken legs, …
skin removed" 173619's `leg, bone and skin removed` 265 g four times,
1,060 g, while the 625 g "roast" stays capped) — `"2 cup · USDA portion"` for a bare count whose
parenthetical prints its volume, which wins as a printed weight does ("4–6
Swiss chard leaves, ribs removed, torn into 1-inch pieces (about 2 cups;
optional)" is 72 g, not five whole leaves; "(½ cup plus 3 tablespoons)"
is both parts, in mL; since matcher v21 pints and quarts too, hyphenated
as a container's size: "2 (1-pint) containers coffee ice cream" is 2
pints at ice cream's 0.558 g/mL, 527.87 g; a paren that says "each", or an adjectival one with
nothing but the count before it, prints ONE item's volume, as for a
printed weight: "8 Swiss chard leaves, torn (about 1 cup each)" is 8 cups,
288 g; since matcher v18 also when the parse keeps it as the line's volume
amount: "2 (about 1 cup) ripe pears, sliced" is 2 cups, while "2 ripe
pears, sliced (about 1 cup)" is 1) — `"4 stick · USDA portion"` for a count
unit an SR bare noun names ("4 sticks unsalted butter" on `stick` 113 g;
the noun must LEAD the description — "cup, sliced" is a cup, so "2 slices
plums" finds no grams there, never two cups),
`"750 ml · USDA portion"` for a count unit sized by the volume printed
before it ("1 (750-ml) bottle red Burgundy or Pinot Noir") when the unit
itself finds no grams, `"from the printed weight"` for a per-unit weight
written in the item without a parenthesis too ("1 5-pound boneless pork
butt roast", "1 15-ounce can chickpeas"; a "(1-liter)" paren is 1,000 mL), `"… · nutrients of \"Cabbage, chinese
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
cooking — counted as 0 g"`, `"poured away — counted as 0 g"` (a person's
confirm or pick of a line counted as discarded with no eaten part — a held
medium, or one the policy zeroes such as frying oil), `"discarded in cooking — only \"plus 2 teaspoons
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
subsection's: a variation's pot never makes a main line a medium; salt
tossed with a vegetable in a colander whose excess is wiped off is held like
a rinsed one (Eggplant Parmesan's degorging salt, the user's ruling Q3); a
skimmer or slotted spoon empties nothing when the pot simmered dry
before it ("until water evaporates") or the step keeps the liquid after it
(reserved, ladled over); food lifted out of a discarded marinade leaves the
marinade counted; and (since matcher v14, checkpoint 8; v17 today) baking soda a food sits
in and is rinsed of in that step or the next (a velveting soak, "Rinse pork
in cold water"), soda or salt in boiling water a LATER step drains the
boiled food of ("Combine chickpeas, baking soda, and 6 cups water … bring
to boil", two steps on "Drain chickpeas"), the salt of a brine the food
poaches in (like its co-solutes above), the sugar a salt-bath salt's own
sentence names ("Whisk 2 cups water, salt, and sugar … gently dunk"), and a
line a sentence combines, whisks or dissolves ("Whisk milk and salt
together"; a salt, sugar or soda as its own mention reads it, another food
by the nth line of its head at the nth mention) when later in that step
the mixture it names drips back off the food ("allowing excess milk
mixture to drip back into bowl") or anything drains after an "add … toss"
("Add cabbage … toss to combine … Drain slaw"; "Do not drain slaw" drains
nothing), or when, in that step or
the next, a food that sentence names drains and something is discarded
("Drain the shrimp into a colander and discard the lemon halves, herbs, and
spices" — a court-bouillon's juice and sugar; the drained food itself and a
sprig line, 0 g already, are never held) — held as cooking water when a
later sentence cooks it, else as a salt bath. A held medium stores only its EATEN part as `grams` — a
"plus" part a step eats, the rest of a written share — and, with none
written, no grams at all (`grams: null`), never the whole poured-away line;
`confirmed: true` on such a row writes `grams: 0`, `gram_source:
discarded` (basis "poured away — counted as 0 g") unless `grams` are typed
in the same request — on any line the engine's own detector holds, whatever
hold the row stores — and a pick of a food on it does the same (since
matcher v23 a pick alone on a `starter_discard`, `coating` or
`partial_pour_away` line keeps the hold instead, below; one with an
eaten part keeps that part: Shrimp Salad's "¼ cup plus 1 tablespoon juice"
picked on "Lemon juice, raw" is its tablespoon, 15.2 g); an amount edit on a
confirmed or picked held medium keeps its hold AND the person's resolution
(matcher v16): 0 g poured away — or its eaten part — except a pick alone
on a `starter_discard`, `coating` or `partial_pour_away` line, which keeps
what a pick on the edited line writes (since matcher v23): no grams but
the eaten part, still held — and grams a person typed stay as typed, never `grams: null` (an edit that makes the line no
medium clears the hold, matcher v18; since matcher v24 so does a steps or
title edit: every compute re-reads a confirmed or picked row's hold from
the recipe as it is and, when it changed, rewrites the row as a person's
write on the line would now — its food and status kept, grams the person
typed never touched — so 0148's dredge flour picked with its hold kept, then
its dredge taken out of the directions, reads unheld and weighed, and a
later confirm counts it: Run 054 Opus critic 1); a bare re-confirm never replaces
typed grams; and an un-skip gives it back the engine's grams — none, or its
eaten part — and its hold, never a person's 0 g (which would read resolved
with nobody's decision), except grams a person typed, which come back as
the person's counted row (below); a
brine aromatic whose rest is tied into cheesecloth — "Place remaining 3
garlic cloves … in center of cheesecloth and tie into bundle" — is zero
whole, not just its written brine share),
`in_shell` (shellfish bought in the shell — clams, mussels or oysters
scrubbed, live lobsters, shell-on shrimp — "shell-on shrimp …, peeled,
deveined …, shells reserved" too: its weight includes the shells the cook
peels off), with or without an amount (never 0 g counted); shucked shellfish, lobster
meat and clam juice name none of these: no record FDC answers publishes an edible share, so the gross weight
is not counted as meat; a LINE hold, like `second_food`),
`starter_discard` (since matcher v22, the user's ruling Q1: every non-water
line of a sourdough starter whose feeding step keeps a little starter and
discards the rest — "discard remaining starter"; how much of the flour ends in the kept starter nothing says),
`coating` (since v22, Q2: ¼ cup or more of flour, starch or crumbs that
a step names in a dredge — "dredge … in the flour", "shake off excess
flour", or set out in a shallow dish — in a recipe that fries; or a line
that says "for dredging" / "for coating". Since matcher v23 the fry is
read from the directions, never the oil's mass: a step that says fry as a
verb ("pan-fry", "deep-fry", "shallow-fry", "continue to fry"; since
matcher v24 never a stir-fry or an oven-fry — another word hyphened
before "fry" — a noun — "each fry" of oven fries, a "deep-fry
thermometer" — an optional note that opens its sentence — "To pan-fry,
increase water" — a negation — "should not actively fry" — bacon or
prosciutto fried in its own fat, or rice toasted for a pilaf), heats
the oil to a frying temperature ("to 375 degrees") or
discards the oil the food cooked in, or a line "for frying" (since v24
"for deep frying" / "for deep-frying" too, the oil's own signal); 0149
Easier Fried Chicken, 0198 Crispy Pan-Fried Pork Chops, 0114, 0042 and
0288 joined, 16 lines in all. A sauté that keeps its fat and a baked
dredge stay counted — the user's pending question. A batter the food
is folded into is eaten whole and is none, nor is a sauce's thickener under
¼ cup, nor a dredge in a recipe that does not fry. Held until the server's
`coatingFraction` switch — null, no figure set — gives the share a fried
food keeps), `partial_pour_away` (since v22, Q4: a line of a braising
liquid — the sentence before the strain that names it and opens "whisk"
or "bring", the food added ("add", "arrange") in the next sentence — that
is strained after cooking ("cooking liquid through … strainer") and of
which a later step keeps only a written part ("Pour 1 cup defatted
cooking liquid", "½ cup reserved defatted liquid"), no step using the
"remaining" liquid; the kept part is `match.hold_note`). These three are
medium holds like `discarded_medium`: a LINE hold, no grams stored unless a
"plus" part is eaten — or, since matcher v23, a divided line's part a step
uses outside the medium: 1133 Francese's "¾ cup all-purpose flour,
divided" stores its "1 teaspoon flour" tossed with the sauce's butter,
0129 Indoor Pulled Chicken's liquid smoke the "remaining 1 teaspoon"
added after the strain, 0279's cornstarch the 3 tablespoons tossed onto
the shrimp (a step with a dredge sentence is the dredge's, all of it) —
a confirm writes 0 g poured away (or that eaten part) unless a person
types the eaten grams. Since matcher v24 a divided line's eaten part is a
mention no OTHER line of its ingredient writes as its own amount (1133's
line split into "¾ cup" and "1 teaspoon" flour lines leaves the teaspoon
to its own line: never counted twice). A pick ALONE (a food, no grams)
follows one rule, at the PUT and at every compute: on a DIVIDED line —
one whose eaten part the engine knows (the three above, or an eaten
"plus" part) — the pick counts that part and RESOLVES the hold (the
picked food, `overridden`, the eaten part's grams, `gram_source`
`discarded`, `hold` null, `match.hold_note` "eaten part counted after
your pick"); on any other held line (0148's dredge, a starter feeding,
0129 Mahogany's soy sauce) it keeps the hold with no grams — 0 g would
drop the part that is eaten with no flag — and the line stays in review
until a skip or typed grams answers it (`discarded_medium`, wholly poured
away, still writes 0 g on a pick),
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
`cured_for_fresh` (the line asks for a fresh meat and the engine's pick is
a cured, preserved record, when the answer holds no uncured one: the engine
first takes the answer's best uncured, undocked record — the one sharing
most of the line's words — so "1 (6- to 8-pound) bone-in fresh half ham
with skin, preferably shank end, rinsed" (Roast Fresh Ham) is "Pork, fresh,
leg (ham), shank half, separable lean and fat, raw" (168226), unheld and
still below the gate for a person, and the matches GET's `candidates` rank
it first the same way; the same switch), `borderline`
(only when the server's borderline-band switch is on, off by default: an
engine pick scored from 0.52 up to 0.54); `hold_note` (since v22): the
hold in words where the code alone does not say it — a
`partial_pour_away`'s kept part ("1 cup defatted cooking liquid"), and
since matcher v23 a divided `coating` or `partial_pour_away` line's part
eaten outside the medium, as written — "1 teaspoon flour is used outside
the dredge, eaten" (1133 Francese), "½ cup reserved defatted liquid; 1
teaspoon liquid smoke is used outside the braise, eaten" (0129 Indoor
Pulled Chicken): its grams, held until a confirm counts them — else
`null`. Such a held line sits in the `check` bucket until a person confirms,
re-picks or skips it — a person's decision clears the hold (a pick, a confirm,
a skip, a grams edit; since matcher v23 a pick with no grams keeps a
`starter_discard`, `coating` or `partial_pour_away` hold), and an un-skip re-derives it for the food now on the
line, so a person's food is never held for the engine's old reason (a
person's food — confidence 1, a pick or a decision, inherited or not — is
held again only by a LINE hold: `discarded_medium`, `starter_discard`,
`coating`, `partial_pour_away`, `second_food`, `in_shell`; an un-skip is no confirm, and only a confirm or a pick on the
line clears one), and an engine row whose line the
second-food rule counts moves to the rule's record with the rule's grams,
as a compute writes it. A
decision reaching the line by `apply_to_all` or inheritance clears a FOOD
hold (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`, `borderline`,
`unnamed_food`) too, never a LINE hold (`discarded_medium`,
`starter_discard`, `coating`, `partial_pour_away`, `second_food`,
`in_shell`): a decision on the key names one food and cannot count the
line's other part, say what a discarded medium leaves or how much of a shell
is eaten) plus ranked `candidates`
for re-picking, `candidates_query` (the words FDC is asked for this line's
candidates, after normalization and the matcher's rewrites — e.g. `spices
pepper black` for a pepper line, `brandy` for "brandy or dry sherry" (an
"A or B" line reads A alone only when A's cached answer holds foods — an
empty one, like `pancetta`'s, keeps the whole phrase; a second "or" makes
a list of foods, "⅔ cup crushed saltines (about 16) or quick oatmeal or 1⅓
cups fresh bread crumbs" the saltines, but an animal or adjective before a
longer B stays one, list or not: "chicken or beef or vegetable broth" is
never a whole chicken), or the singular
`pork tenderloin` whose cached answer a "pork tenderloins" line reads (a
line the rewrites changed never reads its singular form's answer); null
when the line has nothing searchable; since matcher v14 (checkpoint 8; v17
today) it rewrites,
each to a cached answer whose top record is the named one: `thick-cut
bacon` → `pork cured bacon unprepared`; `cilantro leaves and stems` and
`… and tender stems` → `cilantro`; `thai chile`, `thai chiles` and `green
or red thai chiles` → `jarred hot cherry peppers` ("Peppers, hot, raw",
2709798 — never the sun-dried record); `elbow macaroni` and `no-boil
lasagna noodles` → `pasta dry enriched`; `80 percent lean ground chuck` →
`80 percent lean ground beef`; `light or mild molasses` → `molasses`;
`oyster-flavored sauce` → `oyster sauce`; `shaoxing wine or dry sherry` →
`dry sherry or chinese rice wine` ("Wine, rice", 2710691); `dried new
mexican chiles` → `mild dried chile`; `flake sea salt` and `sea salt` →
`salt table` (flake, flaky, flaked, coarse(-grind) and Maldon sea salt,
and sea salt flakes — read on the raw line — weigh like kosher salt, 0.72
g/mL, never table salt's 1.22: "2 tablespoons flake sea salt" is 21.3 g;
plain and fine sea salt weigh as table salt, 6.0 g a teaspoon, matcher v16;
since matcher v18 only when that salt is the line's own food, nothing but
its amounts before it, so "3 tablespoons unsalted butter, melted, plus
flaky sea salt" weighs the butter at its own density, and the plus part of
"1 tablespoon plus 1 teaspoon coarse sea salt" is kosher too, 14.2 g;
since matcher v19 a quantity word in its amount — heaping, heaped, scant,
rounded, generous, level, about — is still its amount's: "1 heaping
tablespoon flaky sea salt"); `whole grain mustard` and `whole-grain mustard` → `mustard
prepared`; `beef tenderloin center-cut chateaubriand`, `center-cut filet
mignon` and `center-cut filets mignons` → `beef tenderloin`; `kale or
collard greens` → `kale`; `broccoli florets` → `broccoli`; `stone-ground
cornmeal` → `cornmeal`; `baby back or loin back ribs` → `pork backribs
raw`; `ripe but firm bosc pears` → `bosc pear`; `white baking chips` →
`white chocolate`; since matcher v17, `boneless country-style pork
spareribs` → `pork spareribs or country-style ribs or beef short ribs`
("Pork, fresh, loin, country-style ribs, …, raw", 167895 — never the
sparerib record); `whole bone-in turkey breast` and `whole bone-in skin-on
turkey breast` → `bone-in turkey breast` ("Turkey, all classes, breast,
meat and skin, raw", 171093); `red thai chile` → `jarred hot cherry
peppers` (`thai red chile` is deliberately not rewritten); `granulated
garlic` → `garlic powder` ("Spices, garlic powder", 171325, never "Garlic,
raw"); and, each to a query FDC answers only by one live search (until it
is asked the line is unmatched, never kept on the old food), `baguette` and
`crusty baguette` → `french bread` ("Bread, French or Vienna"); `broccoli
rabe` → `broccoli raab`; `instant tapioca` and `minute tapioca` →
`tapioca pearl dry`; `st louis style spareribs` and `full racks pork
spareribs` → `pork spareribs raw`; `pomegranate seeds` → `pomegranate raw`;
`milk chocolate` and `milk chocolate chips` → `milk chocolate candy`
("Candies, milk chocolate", never the chocolate-milk DRINK; `milk chocolate
chip` is deliberately not rewritten to `milk chocolate`); `skinless
swordfish steaks` → `swordfish raw` and `tuna steaks` → `tuna raw` (the
fish, never "Pepper steak"); `nonfat dry milk powder` → `milk dry nonfat
regular` (the dry powder, never the reconstituted liquid or cocoa);
`pumpkin puree` and `unsweetened pumpkin puree` → `pumpkin canned without
salt`; `nutella` → `chocolate hazelnut spread`; `water chestnuts` →
`waterchestnuts chinese raw` (FDC spells it as one word); `dried
buttermilk powder` and `buttermilk powder` → `milk buttermilk dried`;
since matcher v21 (zero requests: each target's answer is already cached,
and ranks the named record first under the target's words), the line's
own food under fewer words — `firm tart apples`, `firm sweet apples`,
`sweet and tart apples` → `apples`; `firm mcintosh apples` → `mcintosh
apples`; `ripe but firm peaches` → `peaches`; `red plums` → `plums`;
`vine-ripened tomato` → `ripe tomatoes`; `fire-roasted tomatoes` →
`crushed tomatoes`; `fire-roasted diced tomatoes` → `diced tomatoes`;
`globe or italian eggplants` → `eggplant`; `broccoli crowns` →
`broccoli`; `cauliflower florets` → `cauliflower`; `pickling cucumbers` →
`cucumbers` (never dill pickles); `fingerling potatoes` → `red potatoes`;
`flat-leaf parsley leaves`, `parsley leaves and stems` and `… and tender
stems` → `parsley`; `whole rosemary leaves` → `rosemary`; `mexican
oregano` → `dried oregano`; `lemongrass stalks` → `lemon grass
stalks`; `cardamom seeds` → `ground cardamom`; `green
cardamom pods` → `cardamom pods`; `canela cinnamon` → `ground cinnamon`;
`ancho or other mild chili powder` → `chili powder`; `ancho pods` →
`dried ancho chiles`; `bird chiles`, `arbol chiles`, `whole dried red
chiles`, `whole dried arbol chiles` and `dried de arbol chiles` → `dried
arbol chiles` (168570 "Peppers, hot chile, sun-dried"); `red pepper
fakes` (the corpus's typo) → `spices pepper red cayenne`; `pickled
jalapenos` and `jarred jalapenos` → `pickled jalapeno chiles`;
`commercial sazon` → `sazon`; `red miso paste` and `white miso paste` →
`white miso`; `chinese sesame paste or tahini` → `tahini`; `tabasco or
other hot sauce` → `hot pepper sauce`; `champagne vinegar` and
`champagne vinegar or white wine vinegar` → `vinegar`; `light or dark
molasses` and `mild or light molasses` → `molasses`; `bacon drippings or
vegetable oil` → `vegetable oil`; `chinese rice wine or dry sherry`,
`chinese rice cooking wine or dry sherry` and `rice wine or dry sherry` →
`dry sherry or chinese rice wine` ("Wine, rice" at exactly the 0.5 gate);
`sake or dry vermouth` → `sake`; `inexpensive fruity medium-bodied red
wine` → `red wine`; `100 percent agave tequila` →
`tequila`; `cold vodka or tequila` → `vodka`; `cold milk` → `milk`;
`strong coffee` → `brewed coffee`; `basmati rice` and `white rice` →
`long-grain white rice` (the raw grain, never cooked rice or "Beans and
white rice"); `calasparra or bomba rice` → `medium-grain rice`;
`quick-cooking oats` → `quick oats` (dry, never cooked); `prewashed white
quinoa` → `prewashed quinoa`; `israeli couscous` → `couscous`;
`coarse-ground cornmeal` → `cornmeal`; `king arthur bread flour` → `bread
flour`; `ditalini pasta` and `curly-edged lasagna noodles` → `pasta
dry enriched`; `chinese noodles` and `chinese wheat noodles` →
`pasta fresh-refrigerated plain as purchased` (never fried chow mein);
`phyllo sheets` → `phyllo`; `animal crackers` → `nabisco barnum s animal
crackers or social tea biscuits`; `kettle-cooked potato chips` → `plain
potato chips`; `green or brown lentils` and `brown lentils` → `lentils`;
`mixed berries` → `berries`; `toasted slivered almonds` → `slivered
almonds`; `whole pecans or walnuts` → `pecans`; `dried shiitake mushroom
caps` → `dried shiitake mushrooms`; `1 4-inch-thick deli ham` → `deli
ham`; `thick-sliced soppressata or salami` → `salami`; `white american
cheese` → `american cheese`; `bone-in skin-on split chicken breasts or 4
bone-in` → `bone-in skin-on chicken breast halves` and `bone-in split
chicken breasts and or leg quarters` → `bone-in chicken breasts`;
`skin-on haddock fillets` → `skinless haddock fillets`; `tamarind juice
concentrate` → `tamarind paste`; and two flagged approximations below,
`spicy greens` → `arugula` and `tapioca starch` → `tapioca pearl dry`.
Since matcher v21 a few items are RANK-AS items: the line reads an answer
FDC already gave (its own, or the named query's) ranked as if the
record's own name had been searched. An answer already cached sends
nothing; an answer not yet cached is searched once, under its own words,
as any line's is (in this library all 52 answers are cached). A rank-as
item is never a rewrite key or target (those are "A or B" food nouns:
the fragment `thai`, from "2 Thai, serrano, or jalapeño chiles", is
rank-as so "Thai or Italian basil leaves" is not read as hot peppers — it
keeps its own search, which in this library still lands in review on a
wrong record until the Thai-basil stand-in is approved). Each item →
(answer it reads; words that rank it): `snow peas`, `sugar snap peas`,
`snow peas or sugar snap peas` (reads `snow peas`) → `peas edible-podded
raw`; `dried mint` → `spearmint dried`; `collard greens` → `collards
raw`; `gai lan` → `broccoli chinese raw`; `lump crabmeat`, `jumbo lump
crabmeat`, `lump or backfin atlantic blue crabmeat` → `crab lump`;
`skinless red snapper fillets`, `skin-on red snapper fillets` → `snapper
raw`; `cherry preserves`, `raspberry preserves` → `jams and preserves`;
`red currant jelly`, `jalapeno jelly`, `red currant or apple jelly`,
`apple jelly` (reads `jalapeno jelly`) → `jellies`; `round rice paper
wrappers` → `rice paper`; `gyoza wrappers`, `square lumpia wrappers or
spring roll wrappers` → `wonton wrappers includes egg roll wrappers`;
`new england style hot dog buns` → `roll white hot dog bun`; `portobello
mushroom caps` (reads `portobello mushrooms`) → `mushroom portabella`;
`bone-in turkey thigh` → `turkey thigh meat only raw`; `mexican-style
chorizo sausage` → `sausage pork chorizo raw`; `1-pound whole boneless
shell sirloin steaks or whole flap meat steaks` → `beef top sirloin steak
raw`; `meaty smoked ham shank or 2 3 smoked ham hocks` → `pork ham
hocks`; `dried ladyfingers` → `cookie ladyfinger`; `lightly with salt
popcorn` → `popcorn`; `frozen pea-carrot medley` → `peas and carrots
frozen`; `medium-large onions` → `onions`; `all-bran original cereal` →
`cereal bran`; `seven-grain hot cereal mix` → `cereal`; `seltzer water`,
`unflavored seltzer water or club soda` → `water carbonated`; `whole
farro` → `farro dry`; `pork tenderloin`, `pork tenderloins` → `pork
fresh loin tenderloin separable lean and fat raw` (raw, never FNDDS
cooked); `chicken livers` → `chicken liver all classes raw`; `ground
chicken` → `chicken ground raw`; `ground veal` → `veal ground raw`; `hot
italian sausage` → `sausage italian pork raw`; `dried black beans` (reads
`black beans`) → `beans black mature seeds raw`; `dried chickpeas` (reads
`chickpeas`) → `chickpeas mature seeds raw`; `dried white beans`, `dried
beans`, `dried pinto beans` (read `navy beans`) → `beans navy mature
seeds raw` (raw dry legumes, never "from dried, fat added"); `coleslaw
mix` (reads `red or green cabbage`) → `cabbage raw` (never dressed
coleslaw); since matcher v22, `sugar cube` (reads `sugar`) → `sugars
granulated` (the record publishes no cube portion: the line stays in
review with no grams); `thai` (reads `jarred hot cherry peppers`) → the same words
("Peppers, hot, raw", 15 g a pepper); and the one-word items, kept off
the "A or B" food nouns, read their old rewrite target's answer under its
own words: `chianti` → `red wine`, `lemongrass` → `lemon grass stalks`,
`vermicelli` → `pasta dry enriched`. A few rewrites are APPROXIMATIONS, flagged in
the server's rewrite table, for foods FDC has no record of: pancetta counts
as bacon, Asiago as Parmesan, whole allspice berries as ground allspice, lime
zest as lemon zest (`lemon zest`: "Lemon peel, raw", 167749) — FDC has no
lime peel, and its answer for `lime peel raw` ties lemon and orange peel —
chen pi (dried tangerine peel) as `orange peel` ("Orange peel, raw", 169103:
a raw-peel record, so the dried peel is counted about 3× short per gram — not
yet ruled on), pepperoncini as `pickled hot cherry peppers` ("Peppers, hot,
pickled", 2710095; FDC has no pepperoncini), since matcher v21 (the
user's J2/J5, approved as a group) dried pinto beans and unnamed dried
beans as navy beans (173745) — the small white beans too —, spicy greens as arugula (169387), All-Bran
as bran flakes (2708456), seven-grain hot cereal as whole wheat hot
cereal (171667), fingerling potatoes as red potatoes (2346402) and
tapioca starch on the tapioca-pearl cup (169717: "3 cups tapioca starch"
is 456 g), and a FRESH oregano, sage,
tarragon, marjoram or chervil line on its dried spice record (the dried leaf
is several times as dense per gram, so — the user's ruling of 2026-09-28 —
the dried amount the line offers wins, "1 tablespoon minced fresh oregano
or 1 teaspoon dried" is the teaspoon on the record, 1 g; else a fresh
VOLUME is sized at ONE THIRD of that volume on the record's own portions,
the corpus's own fresh-to-dried ratio, "1 tablespoon minced fresh oregano"
1 g of the tablespoon's 3 g; a sprig and a count of fresh leaves ("12
whole fresh sage leaves") are 0 g unmeasured; a printed weight stays as
written; such a row's `gram_basis` ends `" · approximate (dried herb
record for a fresh herb)"` instead — never on grams typed by hand, nor on a
0 g sprig or leaf count, e.g. `"1 tablespoon · USDA portion × ⅓
(a fresh volume on the dried record) · approximate (dried herb record for
a fresh herb)"`) — a row on one of these records through one of these
rewrites ends its `gram_basis` with `" · approximation (counted as
<record description>)"`,
e.g. `"from 2 ounce · approximation (counted as Pork, cured, bacon,
unprepared)"`, whoever put the row there — a person's confirm or pick of
the record keeps it (the record relation IS the approximation); never
"pancetta or bacon" (which reads the whole phrase), the
food's own line, a person's pick of another record, or a SKIPPED row (it
counts nothing — nor does it carry the fresh-herb "approximate"); the
ranker breaks two kinds of exact score tie toward the plainer record: the
"separable lean and fat" record over "lean only" (the default for an
unqualified cut), and the record naming fewer cookings — "Kielbasa, fully
cooked, unheated" over "…, grilled"; any other exact tie still goes to the
record FDC lists first; a description word marking a modified form the
query does not ask for docks the record — since matcher v17 `liquid` too,
but only as the record's own form, a comma-separated description segment of
its own, so "unsweetened chocolate" is "Baking chocolate, unsweetened,
squares", never the tied "…, liquid", while FDC's canned wording ("solids
and liquids", "(liquid expressed …)") docks nothing and `clam juice`'s
query asks for the canned liquid and keeps it) and
`line_amount` (the line's first amount that names a unit, as written — `"4
stick"`, `"1 piece"`, or the unit alone when the line writes no number,
`"dash"` for `"Dash of hot sauce"` — else its bare count, `"8"` for `"8 large sea
scallops"`: a count is an amount the person converts; null only when the line
gives no amount at all), `kcal_per_100g` (the picked
record's calories per 100 g as the totals count them — its energy, else
4/9/4 from protein, fat and carbohydrate; a record whose nutrients are a
sibling's (Foundation napa 2727583 → SR 169979) reads the SIBLING, 16 not 4 —
from the same caches ALONE, never
a fetch; null when nothing is picked or the record (or its sibling) is
uncached), `portions` (the picked record's
USDA household portions from the food-detail cache ALONE — reading them never
fetches; empty when the detail was never fetched or nothing is picked — each
`{amount, unit, description, grams, fill}`: `grams` the whole portion's
weight, `fill` the grams the line's unit amount weighs on it when the
portion NAMES that unit (a bare count fills nothing) — its unit, or the first word of its description after
any count, `tbsp` for a tablespoon — e.g. `"4 sticks unsalted butter"` on
"Butter, without salt" (173430) fills its `stick` (113 g) with 452; null for a
portion of another unit, and null on every portion of a line the engine
holds as a discarded medium — its written amount is what is poured away
(matcher v16). The app prefills a confirm's amount only when exactly
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
and "onions" are one; the same recipe's other lines count; a line the
engine holds now is left out, read from its recipe as stored — each reached
line once per stored version of its recipe, kept across requests by the
recipe's content hash, so a GET runs no detector for a recipe unchanged
since: v24, Run 054 S4, 0491's GET 0.8 s → about 0.4 s the first time a
server process reaches those recipes, then about 30 ms; the cache is
filled lazily, never at boot — priming every reachable row there measured
1.8 s a boot for 12,382 rows of 1,195 recipes) — at most what
`apply_to_all` (below) would reach — an upper bound for OTHER recipes: their
stored rows are counted as stored, and the apply lays each recipe's rows out
on its current lines first, so a row whose line is now another ingredient,
or gone, is counted here but skipped there (one whose line was only
amount-edited is reached, written under the line's text with its grams,
Run 051 E3) — and `others_lines`: the same
rows counted as lines. A sibling on a DIFFERENT food counts whatever its
score — the decision changes its food. A sibling already on this line's food
counts only while it is still a flagged guess (confidence below 0.5) or held
by a food hold (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`,
`borderline`, `unnamed_food`): blessing it at confidence 1 is what moves it
out of the `check` bucket. A sibling held by a line hold (`second_food`,
`discarded_medium`, `starter_discard`, `coating`, `partial_pour_away`,
`in_shell`) is never counted, whatever its food or score: no
decision on the key releases it — nor is a sibling whose line names a
second food (one the second-food rule counts on its own record, or one not
matched yet, which the decision's food would hold `second_food`), nor an
unmatched discarded medium the engine holds (a salt bath, drained cooking
water — a brine, its sugar and its aromatics are zeroed, not held, and are
reached like any line), nor a line of
shellfish bought in the shell (held `in_shell` on any food). These are
exactly the rows `apply_to_all` writes. One on this food at or above that threshold and unheld is already
counted (or short only an amount) and is neither counted here nor
rewritten, nor is one on this food the engine counts at 0 g whatever its
score or food hold (an amount-less line, a sprig) — a confirm would leave it
where it is. Candidates come
from the compute-time search cache only — reading this never spends the
FDC request budget. An engine row whose line text changed since the
compute is reported as unmatched (`match: null`: the next compute
re-derives it). A person's decision an amount edit carried (the layout
pairs it to the edited line, same ingredient) is shown as what the next
compute and a person's write make of it (v22, Run 052 Opus critic 2; it
was `match: null` while the totals counted it): its status and food, the
grams re-derived for the NEW line from the caches alone (null when that
needs a fetch), and `match.carried_from`: the line's previous text — the
decision is from the line's previous amount until the next compute writes
it (null on every other row). `others` reads that food.

A sub-recipe line — "recipe(s) follow(s)" in its first alternative, "this
page" before its first comma ("1 recipe Buttery Croutons (this page)", not
"shrimp, peeled and deveined (see this page)"), or any line opening "<n>
recipe" ("1 recipe double-crust pie dough", "1 recipe Perfect Poached
Eggs") — is not counted on a food (the user's ruling: sub-recipes stay out
of the main totals): it is stored `confirmed` with no food, `grams: 0`,
`gram_source: unmeasured`, the description "Sub-recipe — made from its own
recipe, not counted in these totals", and resolved like a water line. A
food offered first stays that food: "½ teaspoon table salt or 1 recipe
topping (recipes follow)" is the salt; a store-bought alternative offered
after it does not count ("1 recipe Green Curry Paste (recipe follows) or 2
tablespoons store-bought green curry paste" stays 0 g). A bare count of the
food itself — every amount unit-less, "3 hard-cooked eggs (recipe
follows)", not "4 cups Cream Cheese Frosting" or an amount-less line — is
matched like any other line and counted on its food ("8 Home-Fried Taco
Shells (recipe follows)" is 8 × the 12.9 g "shell" of "Taco shells, baked",
103.2 g); it stays the 0 g sub-recipe only when its FOOD gives no grams (no
corpus line since matcher v14; v17 today) — a pick below the review gate whose detail
was never fetched stays that held pick in `check` instead (one whose detail
IS cached and gives no grams is the sub-recipe). "1 recipe X" whose
subsection X is one counted food is that food's yield on the line's own
pick (the user's ruling Q1, 2026-09-28: "1 recipe Easy-Peel Hard-Cooked
Eggs" is the subsection's "6 large eggs", 300 g); every other "1 recipe X"
stays 0 g. A measured "plus" part of another food is eaten and counted as
the line, the row keeping the line's text: "1 recipe Crispy Onions, plus 3
tablespoons reserved oil (recipe follows)" is 3 tablespoons of the
subsection's vegetable oil — the line every path weighs and shows: a
person's pick or confirm weighs the 3 tablespoons (42 g of oil, never "1
recipe" as one onion), and the matches GET's `line_amount` (`"3
tablespoon"`), `portions` fills, `candidates` and `candidates_query` are
the oil's; an edit to that subsection line makes the totals stale. The rule
holds on every write: a fresh match, a decision reused from another recipe,
an amount edit's re-attached decision, an `apply_to_all` landing on the
line, an un-skip, and a person's pick or confirm with no grams typed — in
that request or before it: grams a person typed stay through a later bare
confirm (matcher v16) — (a marked line its food gives no grams is stored as
the 0 g sub-recipe; the ingredient's decision is still recorded). The engine's own rows — a sub-recipe's, a seasoning's, an
equipment or water line's — are rewritten whenever the rule changes (a
person's confirm of a food, or a skip, is never).

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
an amount edit on a decided line keeps the food and the status (a skip stays
a skip) and re-derives the grams as a compute weighs the new line — the
discard policy included, so a poured-away medium stays at 0 g and an
un-skip never counts it. A hand-typed weight stays when the amount did not
change (a prep-only rewrite, "chopped fine" to "chopped"; every amount the
line writes counts, its "plus" part's too since matcher v22: "1 recipe
Crispy Onions, plus 3 tablespoons reserved oil" edited to 6 tablespoons, or
"2 large eggs plus 6 large yolks" to 8 yolks, is an amount change, as is
the same edit on a row whose food no cache holds) or the line is a
discarded medium, held or zeroed by the policy, read with its grams ("3
quarts peanut oil" is frying oil with no "for frying" in it); otherwise it
is dropped, and none derivable means none (an un-skip never revives the old
amount's weight). A skip, and a row a person typed grams on, stand ahead of
the sub-recipe rule (a pick at a typed weight on "10 cups Vanilla Frosting
(recipe follows)" keeps its food through "12 cups"); any other decided row
on such a line is gated by it as a confirm is. It is ONE outcome whether
the compute runs first or a person acts on the edited line before it (this
PUT starts from the same re-derived row, so a skip and an un-skip in that
window never carry the old amount's typed grams, Run 051 B1/B2). Lines find their rows
by text (a line diff with moves, matcher v19). The save is read as the cheapest
EDIT SCRIPT of the stored rows' texts (in position order) into the lines'
texts: a delete, an insert, a same-ingredient substitution (an amount edit:
the row, and its decision, stay with the line) and a move of one line cost
one each; a substitution to another ingredient IS a delete and an insert
(two ops; it carries nothing: its row is dropped and the line re-derived —
matcher v20; v19 counted it one op as written and so read a move + an
amount edit + a delete as a delete + a cross-ingredient edit, dropping the
moved line's decision). A row is of an ingredient by its STORED key — the
key of the line it was written for, the corpus's curated item included (on
51 corpus lines the editor's parse of the text gives another key, and an
amount edit in the editor keeps the curated item) — and by its own text's
key under the current matcher only where the stored key is absent or names
the same food by another wording, the same head noun (so a key a matcher
upgrade changed still carries an amount-edited row). A rewrite whose head
noun changes never carries (v22, Run 052 O4: 0132's chicken-breast line,
whose text alone keys 'whole bone-in', retyped as a turkey-breast line the
editor keys 'whole bone-in', dropped the pick; v20 carried it). A position with no row (a
person's decision in the window before the compute, or a compute that a
save cut off or FDC failed) is a line of unknown text: it fits any line and
carries nothing, so the line it became is not read as an insert another
row slides onto. Of the cheapest readings: the fewest decisions dropped,
then the most rows at their own positions (a layout is its own next
layout), then the least distance moved (of identical lines, the nearest).
The pairing finds that reading EXACTLY: a branch-and-bound search over the
lines, each line taking a row of its exact text or its ingredient, a gap,
or none, each row at most once, starting from the in-order alignment (which
wins ties; an unedited list is that alignment alone) and cutting every
branch whose lower bound is no better than the best layout found. It runs
synchronously on every compute, PUT and matches GET (as do the discarded-
media rules, which read the directions by sentence: since matcher v24 a
sentence over 1,000 characters is read as none and every amount run they
match is bounded, so member-supplied step text costs linear time — Run 054
Sonnet critic 1: a 16 KB "1 1 1 …" step took 3.3 s), so it expands at most
10,000 layouts (`pairingBudget`) and then keeps the best found so far:
reached only far past a few edits (a list shuffled whole with a quarter
rewritten in one save), never on a save of up to three edits the pairing
oracle draws. Measured (JIT, real corpus lines): an unedited list is one
expansion; at the edit service's cap of 400 lines a three-edit save takes
~50 ms and a save that stops at the budget ~100 ms (~120 ms cold), at 60
lines ~12 ms. A row only ever sits on a line of its exact text or its
ingredient. So a save making several edits keeps each decision on its line: Run 050's
"½ cup" oil deleted and the picked "¼ cup" moved up in one save keeps the
pick; a move plus an amount edit of the other oil keeps the moved line's
typed grams and the edited line's food (its grams re-derived for the new
amount, as above); the onion deleted, both oils amount-edited and lemon
appended keeps the skip and the pick each on its own oil. A decision on the
second "Salt and pepper" of Acquacotta stays on it whatever happens to the
first (edited or deleted), two decided copies with a line inserted or
deleted above both move with their lines, and an engine row (a rule row,
`auto` or `unmatched`) moves with its line and is re-derived there, never
given another copy's decision; a row no line takes is deleted. Every
layout keeps the texts of the lines it laid the rows on (`recipe_layout`,
migration 012), and the next pairing reads the version before the save from
them, not from the rows: a line with no row (a decision made in the window
before the compute, a compute cut off or failed) is still its line, and a
row still carrying an amount edit's old text reads as its line's. A recipe
not laid out since that migration has no texts: its first layout reads the
rows, a row-less position as a line of unknown text. Known limit:
text-only — where identical lines make an edit ambiguous, this is the
cheapest reading keeping the most decisions, which may not be what the
person did (which twin they deleted).
The whole layout is written in one transaction before the compute
asks FDC anything — and before this PUT reads its row — and a decision is
only ever moved (or dropped with its deleted line), never rewritten. A
layout that moves or drops a row, or lays the rows on other lines, bumps
the recipe's layout sequence in that transaction, and every row write — the
compute's, this PUT's, each apply-to-all target's — checks in its own
transaction that the sequence is still the one it read its rows under. So
a compute whose recipe's nutrition inputs (its lines, steps and title: what
the staleness hash reads) change while it waits on FDC — or whose rows a
person's write laid out anew meanwhile, even when a later save put the
lines back as they were (a save and its revert hash the same, Run 051 C1) —
writes no further rows and stamps its totals STALE, never fresh, so the
next sweep revisits it; a save changing nothing it reads (tags, notes,
times) blocks nothing, nor does a person's write on unchanged lines. The
compute's stamp is read after its own totals' awaits, with none between the
check and the write. The engine's writes never replace a person's decision
(the guarded write replaces only an undecided row — v20's clause replacing
any row of another text is gone, Run 052 S1/Opus critic 3), and the one
write over a decided row — the compute's amount-edited row — lands only
while the row is still the one it laid out: a person's write on that line
during the compute's awaits (an un-skip) stands (Run 052 O3).
`GET …/nutrition/matches` shows each line the row this layout gives it,
without writing, and each line's apply-to-all offer (`others`,
`others_lines`) counts this recipe's own rows as that layout places them —
never its own row for the line, nor a row the layout would delete.

This PUT reads the STORED recipe (never a copy read before a save), lays the
rows out on its lines — that layout is written even when the request is then
refused (a 422, a 409 after the awaits): it moves rows only as the next
compute would, and changes no decision's content — and reads the line's row.
After its own awaits (a food fetch), when the recipe was saved or its rows
laid out anew meanwhile, it re-reads the stored recipe (deleted: `404`),
answers `409 line_moved` when the line no longer stands at `{pos}`, lays the
rows out again, and writes only when the row that layout gives the line is
the one it read (else `409 line_moved`, `position` = `{pos}`): the decision
lands on the line the person acted on, or not at all. Optional `raw`: the line's text as the client saw it at `{pos}`. When
the line at `{pos}` reads otherwise (a save since), `409 line_moved` with
`{error: {code: "line_moved", message, request_id, position}}` — `position`
is the line with that text nearest `{pos}` now, or null when none — and
nothing is written. A non-string `raw` is a 422. The app sends it from the
review sheet, the fix pane, the queue and the apply-to-all resend — always
the text of the line the person acted on, never re-read from whatever row
now sits at `{pos}`: the resend names the line the offer was raised on, and
the queue pane the queued line's text (a queued line no row reads any more
shows as edited or removed and is not acted on). On a 409 it reloads the
rows so the screen finds the line where it is now; on every reload of the
rows a pending apply-to-all offer follows its line by text, or is withdrawn
(and the message says so) when no single row reads it. The offer itself is
raised on the text the PUT sent, placed on the response's rows by that text
(the row at `{pos}` when it still reads it, else the one row that does) —
never the row the response has at `{pos}`, which is read after the server's
awaits and can be another line a save put there — and not raised when no
single row reads it; the apply-to-all receipt stands under its line the same
way, and shows a non-zero `moved` ("N lines changed meanwhile and were left
for their next compute").

Override one line: `{fdc_id}` re-picks the food, `{grams}` hand-sets the
amount, `{confirmed: true}` blesses the auto match, `{skipped: true}`
excludes the line, `{skipped: false}` un-skips it — back to automatic
triage (`auto`), deliberately NOT `confirmed`, so a low-confidence match
is not silently blessed; the row is what a compute writes, weighed and
gated by the sub-recipe rule (a skipped rule row — a sub-recipe's, a
seasoning's, water or equipment — is that `confirmed` rule row again, never
an `auto` row on no food) — except a row whose grams a person typed
(`gram_source: override`), which comes back as a grams edit leaves an
`auto` row: `overridden`, their grams, no hold, counted — never an `auto`
row the next compute re-derives (matcher v18) — and before any gate: neither
the sub-recipe rule (a sub-recipe the recipe makes apart) nor the second-food
rule replaces a person's pick and typed grams (matcher v19). A skipped line
whose amount is edited keeps its skip, but not the grams of the old
amount, typed or derived: the compute re-derives its grams for the new
amount on the skipped row (none when it cannot), so an un-skip counts the
new amount — except on a discarded medium, held or zeroed by the policy,
where typed grams are the person's resolution and stay (as they stay on a
decided medium's amount edit). Totals recompute instantly. A re-pick of a line
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
first). `422 zero_row` for a bare `{confirmed: true}` (no `fdc_id`, no
`grams`) on a below-gate zero row — `auto` or `skipped`, a food below 0.5 at
0 g `unmeasured` or `discarded`, not held `unnamed_food`: its food is a
hidden guess the app never shows, and a confirm would decide it
library-wide. Pick a food (with an amount), type grams, or skip it.

Add `apply_to_all: true` — together with `fdc_id` or `confirmed: true`,
the decision being broadcast — to land the same food on every other
undecided (`auto` / `unmatched`) line with the same ingredient item (other
recipes, and this recipe's other lines), each with grams from its own amounts
— weighed and gated as a compute writes it: a sub-recipe's eaten "plus"
part, and a marked count the food gives no grams lands as the 0 g
sub-recipe, never a no-grams row — and recompute those recipes' totals. A line on a different food is a target
whatever its score; a line already carrying that food is one only below the
flagged threshold (confidence 0.5) or while held by a food hold, and not
counted at an engine 0 g (an amount-less line, a sprig), where
rewriting it as `auto` at confidence 1 with its hold cleared stops it being a
guess — how confirming one line clears an ingredient's whole group. A line
already on that food at or above 0.5 and unheld is left as it is, as is a
line a line hold holds (`second_food`, `discarded_medium`,
`starter_discard`, `coating`, `partial_pour_away`, `in_shell`, whatever its food or score), a line that names a second food (counted by the
second-food rule, or unmatched), shellfish bought in the shell and a line
the engine's medium rules hold, matched or not — read from the recipe as
stored, never from the row's stored hold, so on a stale recipe (a steps
edit, a matcher bump not yet swept) a line its steps now make a dredge or
a poured-away medium is not offered (v23, Run 053 Opus critic 3) — the same
rows `others` leaves out, so the offer and the apply agree; a line its
recipe's steps made held between the offer and its recipe's turn is not
written and counts in `moved`.
The rows land
as `auto` at confidence 1, machine propagation of a human decision exactly
like inheritance — not as a human status, so a wrong pick applied
library-wide is corrected the same way, by a second `apply_to_all` with
the right food. A line a person already decided is left alone, as is one
that is now another ingredient or gone (each recipe's rows are laid out on
its current lines first, and each reached row is found WHERE THAT LAYOUT
PUT IT — by the row itself, not its stored position, so a line a save only
shifted is reached at its new position, v22 Run 052 O14; a line only
amount-edited since its compute is reached under its new text, while a
line whose key now names another decision is not). Only an undecided row is
written: a person's skip or pick the layout carried onto a reached
position stands (Run 052 S1). A recipe whose rows are laid out anew while
the apply waits on FDC (a save and a person's write or a compute) is left
for its next compute: no row of it is written over what the layout put
there. The response carries `applied: {recipes, lines, failed, completed,
completed_recipes, moved, decided, gone, failed_lines}`, which accounts
for every line `others_lines` offered: each is in exactly one of `lines`
(written; see below), `decided` (a person decided it meanwhile — read as
a decided row of its text the recipe holds that it did not at the offer,
so a decision on one of two twin lines is `decided`, never `moved`: v23,
Run 053 O5/S3), `gone`
(its line is gone or another ingredient now, or its recipe was deleted —
during the apply's awaits too, Run 052 O6, or by a layout that ran before
its recipe's turn, v23 — and, since v24, a recipe laid out anew during
the awaits that no longer holds a line of that text or ingredient, deleted
and re-created or saved without it: Run 054 S3), `moved` (its recipe was laid
out anew during the apply's awaits, or the row was rewritten since the
offer: left for its next compute) and `failed_lines` (its recipe failed;
`failed` counts those recipes): `completed` counts
the reached recipes whose stored status turned `complete` with this apply
(not a reached recipe that was complete already — a different-food pick
reaches counted lines). The decided line's OWN recipe can be among them:
the apply reaches the same recipe's other lines of the ingredient, and when
they were its last open ones it completes during the apply (a pick on one of
Cranberry Pecan Muffins' two pecan lines reaches the other). The app's
apply offer promises only the OTHER recipes of the group's
`finishes_recipes` (less the line's own), so a receipt may complete MORE
than the offer promised — an extra id is a bonus, never an error — and
says whether the promise came true —
and `completed_recipes` lists their ids, so a shortfall can be named;
`lines` counts the lines the decision moved —
whose review bucket changed, or that took the decided food (a line left
short of an amount on it too, which stays `no_grams`) — every line `others`
counted, less those in `decided`, `gone`, `moved` and `failed_lines`:
every written line (v23: a line on the decided food that stayed in its
bucket was counted in none, Run 053 Opus critic 3) —
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
recipe — and, since v22 (migration 013), between the stamp's `layout_seq`
and the recipe's current layout sequence: a recipe laid out anew since its
stamp is in the `stale` scope whatever its hash (Run 052 O1/S2).

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
