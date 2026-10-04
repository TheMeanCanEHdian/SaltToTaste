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
convert, but it never promises what a confirm may not count — so a line
held for a food with no record (`food_gone`, `food_unavailable`: only a
pick or a skip finishes it, by the hold's action table, below) is 0 even
with grams typed, and counts as short in its group and in `finishable`
(v28, Run 058 O8, Sonnet critics 1 and 3). A group item
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
`partial_pour_away`, `ambiguous_medium`, `in_shell`): no decision on its key
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
  "stale_reason": "inputs | underived | interrupted",
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
that no one has reviewed yet (confirm/override/skip clears one — except
on a food with no record, `food_gone` or `food_unavailable`, which only a
pick of another food or a skip clears: its action table, below) — never an
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
of the stamp — this body, the `stale` bulk scope, the job's re-run — reads
both its halves; the body and the `stale` scope also read the THIRD half
below (no decided row underived), and the job's re-run does not (a second
pass would only ask USDA again for what it could not serve). The layout sequence is one global counter (migration 013), so
a recipe deleted and re-created under its id never repeats a sequence a
writer read before the delete. It also means (v27, RULE A) a person's
decision is UNDERIVED — its derivation could not run (FDC failing a fetch
it needs) — so the stamp is current but the totals do not count what the
decision derives. Since v28 a stale body says which with `stale_reason`
(present only when `status` is `stale`): `inputs` (the ingredients, steps,
title or layout changed since the compute: "ingredients changed") or
`underived` (the inputs are those the totals were stamped on; a decision
is waiting on USDA) — since v29 also when the last totals were stamped
waiting on USDA (an engine row's food no cache held, an apply-to-all
target FDC could not weigh: the stamp names the inputs it was written on,
marked so that no inputs equal it — never `inputs` when nothing changed,
Run 059 O23) — or `interrupted` (v29: a pass IN PROGRESS or one that
never wrote its totals — migration 017's owned count above zero, which a
live compute, a person's write or an apply-to-all target holds while it
runs, or a stamp a throw or the boot cleared; the two are not told apart
— the count is the only record, and `computing_job_id` says when a job
is live; the next compute repairs it). The app's stale banner says
which: "A decision is waiting on USDA: these totals do not include it
yet.", "A compute is in progress or was interrupted: these totals may
not count every line." or "Ingredients changed since this was
computed." (no `stale_reason`: the latter). Migration 013 stamps each existing
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
apply-to-all reaching the recipe) carries
the stored stamp only while the stored recipe still hashes to it (v24, Run
054 O3: an edit, this recompute and a revert otherwise read fresh over the
edited recipe's totals; it stamps no hash, `stale`), and computes its totals on the STORED recipe and its
rows in the same step that writes them — after every food detail it
needed was fetched — never on a recipe or rows read before an await, so a
newer compute's fresh stamp never sits over older totals (v23, Run 053
O4). The ~30-nutrient
key set and FDA Daily Values match the legacy app's panel.

### `PUT /api/v1/recipes/{idOrSlug}/nutrition` (admin, full scope)

`{serving_basis}` (1–1000) — change the per-serving divisor: PURE
ARITHMETIC over the stored per-recipe totals (v27, RULE A; migration 015
stores them unrounded beside the per-serving label, which is those totals
divided by the basis when written). No row, food or cache is read and no
FDC call is made, so the change touches no row, no `derived_seq`, no
stamp, status, counts or `total_grams`: an outage or a food gone from
every cache can neither fail it with `422` nor make it drop a food and
read `partial` or `stale` (Run 057 Opus critic 3; the v27 closer, the
verifier's D1: the v27 first cut re-read the rows against the caches and
dropped 0857's 248 g of flour once its stand-in left the search cache).
A row stored before migration 015 has no totals: its per-serving amounts
times its stored basis stand in (each rounded to 0.01, so at most 0.005 ×
the basis off) until the next compute stores them. The default is the
first of:
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
log names it). Only a moved layout or content hash is a reason for
another pass (v27, RULE A): a decided row whose derivation could not run
is UNDERIVED — the recipe reads `stale`, the next sweep derives it — and
is asked for ONCE per pass (Run 057 S5/S16/O16: 0148's 13 such rows cost
42 requests in 3 passes and ended in "still stale after 3 compute passes";
now 13 in one). A `stale` or other bulk sweep computing the recipe is the
job a call re-attaches to, and it runs the same step (v22, Run 052
S5/O5). The
recipe's `…/nutrition` body carries `computing_job_id` (admins only)
while a compute is in flight so a reopened page can re-attach. Cached and rate-limited
(~900 requests/hour shared budget); user decisions on unchanged lines
survive recomputes. Water/ice lines (since matcher v21 "filtered water"
too) are matched locally for free, as are equipment lines (since v21 a
banana leaf: the cochinita pibil's wrapper, not eaten). The job
fails (with FDC's own reason in its log — a bulk sweep stops there, "stopped
at <id>: <reason>") when FDC fails in a way every request would: no API key
configured, the key rejected, the hourly budget spent, a rate limit, the
network down or timing out, or a SEARCH failing after its retries (a
GLOBAL failure, v28). A failure tied to ONE food — FDC failing that food's
DETAIL (a 4xx other than 404, an unreadable answer, a 5xx after the
retries) — is a FOOD failure. The provider's ONE classification table
(v29, Run 059 O22/O5/S5/S28/O14/S22, pinned arm by arm): on a food's
DETAIL a 404 is no record (no failure); another 4xx, a 5xx after the
retries and an unreadable 200 — not JSON, not UTF-8 (an HTML error page,
a truncated record: v28 read it as the network, GLOBAL, and every sweep
stopped at that recipe, "Could not reach FoodData Central"), not an
object, or an object of the wrong shape (a nutrient or portion entry that
is not an object, a description that is not a string — read defensively,
v29 closer: it threw a TypeError out of the pass) — are FOOD, said
"FoodData Central returned an unreadable answer."; a 401/403 (the key), a 429 after the retries (the key's rate
limit), the budget, no key, the network (a connect failure, a timeout, a
stream cut mid-body — GLOBAL even on a detail: nothing in it names one
food, and reading an outage as per-food failures would hold healthy rows
`food_unavailable`) and ANY failure of a SEARCH (a 404 too: v28 let a
private not-found escape the provider) are GLOBAL (v28, Run 058 Opus critic 1 / S27: v27 stopped
every stale sweep at the first recipe holding one such food, so no recipe
after it was ever computed). It is that LINE's state, for EVERY line kind
(v29, Run 059 Sonnet critic 1 / O3 / Opus critic 3 — v28 handled decided
rows only, and an engine line's failure threw the whole pass away): on a
decided row it leaves that row underived; on an ENGINE line (its candidate,
the key's prior decision or a nutrient record failing) the line gets a row
of its own — `unmatched`, no food, `description` "FoodData Central could
not serve this food" — underived until held (`stale_reason: underived`).
Either is counted (`ingredient_matches.retry_count`, migration 016), the
pass goes on to the next line, the compute writes the rest and its totals,
the job's log names it ("<id>: <reason>") and the job goes on — `done`, the
per-recipe job too; after 3 computes in a row the row is held
`food_unavailable` (a pick of another food or a skip finishes it, below).
The held write KEEPS the count (v29, Run 059 S2: it reset it, so every
later edit re-asked and re-staled a held row). A held row — and a
`food_gone` row — is RE-READ before it is enforced (v29, Run 059
O1/S1/S6/S27): every compute derives it from the caches alone (one reader,
`knownFood`: the food-detail cache, then the search-cache index; no
request) — a cache holding the food and its nutrient record again derives
it (counted), otherwise the hold stands, derived for the current inputs
(an edit neither re-asks nor re-stales it). A cache write that gains such
a food re-opens its held rows (their recipes read `stale`, the next
compute re-reads them; migration 017's partial index). FDC is asked again
for a `food_unavailable` row only by the `all` scope, ONCE per row per
sweep (a healthy food held by transient failures recovers with no
person); the `stale` and `missing` scopes never ask. A DETAIL outage is
not a food's, and it is counted in the JOB's units (v29, Run 059
O4/O10/S4/O11 — v28 counted within one pass, so failures landing one per
recipe never escalated: 1,184 detail requests on an emptied snapshot) —
by the owner's ruling on O11, two rules. (i) EVERY FOOD failure is
counted on its row, always: an escalation stops further requests and the
job, never discarding a count already taken (the request that tipped it
included), so broken records are held after 3 sweeps whatever else a
sweep meets. (ii) An outage is a property of the job, not of one recipe:
FOOD failures on 3 DISTINCT foods in a row — no detail answered between
them (a record or a 404) — that SPAN AT LEAST TWO RECIPES are GLOBAL with
FDC's own reason, every later detail of the job fails at once with no
request, and the job stops as above. One recipe's failures, however
many, are its rows' state, never the job's: three broken records in one
recipe, every other food cached, count and sweep on (held at the third
sweep, every later recipe computed); a fourth broken record in the next
recipe escalates there and stops the sweep — all four rows still
counted. (iii) A PASS asks at most 3 failing details in a row (the
owner's ruling on Run 059 O10; not an escalation): after FOOD failures
on 3 distinct foods it requested, nothing answered between, it asks FDC
for no more details — every row it failed is counted as usual, every
later line whose food no cache holds is left as it was (a decision
underived, an engine line's row as it stood), uncounted and unasked,
and the recipe reads stale (`stale_reason: underived`, the sweep moves
on; the next sweep asks again, held rows re-read from the caches with no
request, so a recipe's broken records are reached 3 at a time); a cached
food still derives. So a detail outage costs at most **4 detail requests
per sweep, whatever the recipes' sizes**: 3 in the first recipe (it
suspends), 1 in the next (it escalates, the job stops — "stopped at
<id>"; on a snapshot emptied of every cache, 4 requests, not the 6 one
recipe's distinct foods plus one cost under (ii) alone). A food that failed FOOD once in a job is not
asked again in it (the same failure answers: six recipes on one broken
record, one request). A person's write and its apply-to-all are one
recipe's job (never escalated; its requests are bounded, below). A
failed search stops the compute. A pass is IN PROGRESS until its totals
are written (v29, Run 059 Opus critic 1; migration 017's
`recipe_nutrition.computing`, an OWNED count): a compute pass, a person's
write and an apply-to-all target each add one BEFORE their first row
write and take their own one away with their totals, in the totals' own
transaction — never another writer's (a person's write during a sweep's
pass leaves the pass's mark standing) — and every freshness reader reads
a count above zero as `stale` (`stale_reason: interrupted`). A pass that
never returns (a restart, an OOM, an FDC await never answered) keeps its
mark; one that throws releases its own and clears the stamp (prefixed
`interrupted:` — no current inputs equal it): stale whatever rows it
marked derived, and the next compute repairs it. At boot, beside the
"interrupted by a server restart" job pass, every recipe still counted
has its stamp cleared so and its count reset. (v28's clearing of the
marked rows' keys on a throw is deleted: the mark is the one
mechanism.) A line is
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
cups popped)" keeps 96.5 g; since matcher v25 that is the item's noun
phrase, not the line cut at its first paren: a paren with a number or a
"from" sizes or sources the amount and is dropped — "6 cups (1 bag)
popped popcorn" is 84 g, "8 cups popped popcorn (⅓ cup kernels)" 112 g
— and any other is read as a modifier — "½ cup popcorn (unpopped)" and
"(kernels)" keep 96.5 g; since matcher v26 only a ONE-word paren
qualifies the head: a paren of more words is a note on the line, read as
no modifier — "8 cups popped popcorn (unpopped kernels discarded)" and
"(old maids and kernels removed)" are 112 g, not 1,544 — and a comma part
reads by the same rule: ", unpopped" keeps 96.5 g, ", unpopped kernels
discarded" is a note; since matcher v27 a paren or comma part qualifies by
VOCABULARY, not word count (Run 057: v26's rule weighed "½ cup popcorn
(unpopped kernels)" as popped, 7.0 g): it qualifies when every word is a
qualifier of what the amount measures — unpopped, popped, air-popped,
kernel(s), raw, dry, plain, yellow, white — so "(unpopped kernels)", "(raw
kernels)", "(dry, unpopped)" and ", unpopped kernels" keep 96.5 g; a number,
a "from" or a removal or reservation word ("discarded", "removed",
"reserved", "for another use", "(about)") makes it a note — "8 cups popped
popcorn (unpopped kernels discarded)" stays 112 g) — every other food keeps its own
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
approximate (paprika density)"`; since matcher v31 anchovy paste at 6.7 g
a teaspoon (1.36 g/mL), the mean of ATK's two printed equivalences ("Two
minced anchovy fillets can be used in place of the anchovy paste", Modern
Beef Burgundy, 2 × 2706232's 4 g fillet; "substitute 1½ teaspoons of
anchovy paste for the fillets", Pan-Seared Thick-Cut Boneless Pork Chops,
5.3 g a teaspoon), labelled `"1 teaspoon ≈ 5 mL · approximate (ATK: 2
anchovy fillets ≈ 1 to 1½ teaspoons paste)"`, and "instant espresso"
(171893) at its 13 "instant espresso powder" siblings' 0.43, never the
record's loose `tsp` 1.0 g; since matcher v23 a line that says
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
Pecorino's 28.35; since matcher v25 a same-food "plus" part of a grated
or shredded hard cheese is weighed in the form its OWN words name, else
the line's — "¼ cup grated Parmesan cheese plus 2 cups shredded" is
184.28 g (the shredded cups at 0.36), as the corpus's "… plus 6 ounces,
shredded (about 2 cups; see note)" weighs — since matcher v26 its words
after its comma too: "… plus 2 cups, shredded" (the corpus's own
spelling) is 184.28 g, never the grated 127.6; and a powder on a record of the drink made from it
("…, powder, prepared with whole milk") reads only its `dry` portions —
none: no grams, never the made-up drink's `cup (8 fl oz)` 265 g) |
`piece` (estimate; since matcher v21 the piece table reads "green
pepper", "Fuji" and "yolk" by its bell pepper 119 g, apple 182 g and egg
yolk 17 g: "1 small green pepper", "3 Fuji, Gala, or Golden Delicious
apples", "2 large yolks"; since matcher v30 (the user's Q6 ruling: a
weight ATK prints in the corpus where one exists) a dried New Mexican
and a dried guajillo chile 7.1 g each — ATK's "3 medium New Mexican pods
(about ¾ ounce)" (Chili con Carne) and "4 large dried guajillo chiles …
(about 1 ounce)" (Goan Pork Vindaloo) — flagged approximate: `"2 × 7.1 g
each · approximate (ATK: 3 medium New Mexican pods ≈ ¾ ounce)"`, `"10 ×
7.1 g each · approximate (ATK: 4 large dried guajillo chiles ≈ 1 ounce)"`;
keyed on the DRIED item, so a fresh chile, a chipotle in adobo and the
"(2-inch) piece mild dried chile" never reach them; since matcher v31 (the
CP10 rulings, each flagged with its source in the basis): a dried
chipotle 4.6 g (ATK's "½ dried chipotle chile … (scant tablespoon)" on
168570's cup, Pollo en Mole); fresh ginger and citrus zest strips by the
length the line prints — "(4-inch)", "(1½-inch piece)", "about 3 inches
long" — at 8 g an inch of ginger root (ATK's "1 (1-inch) piece fresh
ginger, grated (about 1 tablespoon)", Roast Fresh Ham, at the ginger
density) and 0.8 g an inch of orange or lemon peel strip (ATK's "10
(3-inch) strips orange peel … (¼ cup)", Crispy Orange Beef; lemon "the
orange-peel strip figure, extended to lemon"), only on the ginger-root or
peel record and only for a piece or strip count: `"1 piece × 4 inch × 8 g
per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1
tablespoon)"`; whole spices by a reference figure — a peppercorn 0.05 g,
a whole clove 0.1, an allspice berry 0.1, a cardamom pod 0.2, a coriander
seed 0.01, a star anise pod 0.5 (a flagged figure prints its decimals —
a sub-gram one all of them, `"15 × 0.05 g each · approximate (reference
figure: a whole peppercorn)"`, one under 10 g one decimal, `"10 × 3.2 g
each"`; one of 10 g or more its rounded grams); a lemongrass stalk 10 g
(reference: trimmed to its bottom 5–6 inches; "N stalks lemongrass" or
"N lemon grass stalks"); a no-boil lasagna sheet 17 g (Barilla
Oven-Ready: 9 oz, "at least 15 sheets", label 3 sheets = 51 g) and a
curly-edged lasagna noodle 25 g (Ronzoni No. 80: label 2 pieces = 50
g), the longer key winning for no-boil; a bunch
of scallions 7 × FDC's 15 g scallion (`"2 bunch × 7 × 15 g each ·
approximate (reference figure: 7 scallions a bunch)"`; any other bunch
keeps no grams); a cornichon 3.2 g (ATK's "6 cornichons, minced (about 2
tablespoons)" on 2710078's cup, Austrian-Style Potato Salad) and a
Cubanelle pepper 99 g (ATK's "3 cubanelle peppers (3 to 4 ounces each)",
Eggs Piperade). Not built (ruled no grams): dried jujubes and the mild
dried chile by the inch; an ancho keeps FDC's 17 g)
| `override` | `discarded` (a cooking medium the recipe throws away —
deep-frying oil ("for frying" — since matcher v24 "for deep frying" too —
or 400 g or more of oil — or, since matcher v23, ¼ cup or more of oil, its
same-food "plus" part included, in a recipe whose dredge is held `coating`
by its directions: the oil a dredged food fries in, 0149's "1¾ cups
vegetable oil" heated to 375 degrees, 0198's "⅔ cup" whose step discards
it, 0042, 0114 (0288 since matcher v31 held `ambiguous_medium`, below); a
sautéing tablespoon stays counted — or, since
matcher v24, with or without a dredge, ¼ cup or more of oil whose OWN
sentence heats it to a frying temperature, discards it ("Discard the
oil") or pours off all but a written part of it ("pour off all but N
oil" — only that form: 0523 Nasi Goreng's "Pour off the oil and reserve"
keeps it, counted): 0491 Tostadas' "¾ cup vegetable oil" heated "to 350
degrees", 0 g; a part its sentence keeps, "pour off all but 2 tablespoons
oil" (1193 Crispy Tempeh's cup), is counted — 28 g of the 224 —, the
rest discarded; 0040's dressing oil, 0500's rice oil and 0672's coconut
oil, which no sentence heats to a temperature or discards, stay counted
(the fritter oils of 0674/0675 too until matcher v31, which holds them
`ambiguous_medium`). Since matcher v31 a same-food "plus" part the steps
eat in pieces after the fat's LAST discard sentence is the eaten part
when those pieces total it — 0042 Almond-Crusted Chicken's "¾ cup plus 2
tablespoons vegetable oil": "Discard the oil …", then "Heat 1 tablespoon
more oil" and "add the remaining 1 tablespoon oil" (the dressing), 28 g
counted, the ¾ cup discarded — and a small FIRST part a step names is
the eaten one even when the steps name the large part too (0675's "1
teaspoon plus ½ cup"). Since matcher v25 (RULE B) a
sentence belongs to a LINE, never to the word "oil" — and since v26 to
every frying FAT the mass rule knows: oil, shortening and lard, each read
by its OWN noun ("Heat the shortening in a Dutch oven to 375 degrees"
fries a shortening line; v25 read only "oil"). Frying heat is POSITIVE
evidence (v26), its exclusion SCOPED since v27 (Run 057: v26 excluded a
temperature for an oven or bake word ANYWHERE in the sentence, so "drain
on a baking sheet", "the baking soda rub" or "roasted peanut" beside a real
fry counted the oil whole): a temperature is the fat's when "<fat>
temperature" comes before it ("maintain oil temperature between 350 and 375
degrees"), or when the fat's noun comes before it, a LEAD introduces it —
"to", "until", "registers/registered", "reaches/reached", "reads/read",
"is", "at", "a temperature of", "(", "between 350 and", a range's first end
("350–375", "350-375"; "350 to 375" is "to"), each with "about", "around",
"approximately", "approx(.)" or "roughly" between — and a heat verb (heat,
reheat, bring, warm, return, reach, register, read, maintain, keep, hold,
fry, deep-fry, pan-fry, in every form; never an air fry, an oven-fry or a
stir-fry) starts at or before the lead in its OWN verb phrase (after the
last "and"/"then" that opens a new one, not before an article: "Heat the
oil and cook the pitas at 375 degrees" is the pitas' heat; "Heat the oil and
the butter to 350 degrees" fries) — "Heat oil in large Dutch oven … to 375
degrees", "Return oil to 350 degrees", "when the oil reaches 385 degrees",
"until shimmering but not smoking (350 degrees)", "Fry the potatoes in oil
at 350 degrees", "Maintain the temperature of the oil at 350 degrees",
"Heat the oil to between 350 and 375 degrees", "until a deep-fry thermometer
reads 350 degrees". It is NOT the fat's when an appliance or a method
GOVERNS it: its clause — from the LATEST boundary at or before its lead
(matcher v29, Run 059 O7/S9): a clause mark "; , — ( )", an "and"/"then"
opening a new verb phrase (not before an article), or the fat's own
mention; never the evidence's own heat verb (since v28 — Run 058: v27 cut
there, so "bake them in an oven heated to 375 degrees", "heat grill until
lid thermometer registers 350 degrees" read as frying heat), and no mark
or opener whose phrase opens on a heat verb other than a fry (after an
"and"/"then"): its object unnamed, it continues the clause before — "in
the smoker, holding it at 300 degrees", "on the grill, keeping the
temperature at 350", "Rub the oil on the pizza stone and heat it at 350
degrees" are the appliance's, while "warm in the oven and fry the rest at
350 degrees" is the fat's. v28's participle exception (a mark before a
heat verb's participle opened no clause) is deleted: it gave the oven the
fat's own temperature when the participle phrase heats the fat ("…in a
200-degree oven, heating the vegetable oil … to 350 degrees", "Keep the
chicken warm in the oven, frying the remaining pieces in oil at 350
degrees"); the fat's mention inside that phrase is now the boundary, and
"Place a rack in the oven and heat the vegetable oil … to 350 degrees",
"Heat the oven to 200 degrees and heat the oil to 350 degrees" fry again
(v28 read them the oven's). A lead's own "(" opens the temperature's clause
("beside the oven (350 degrees)"); a boundary inside a lead ("between
about 350 and about 375") is none — names anywhere before
it an appliance (an oven, a broiler, a grill, an air fryer, a smoker, a
slow cooker, a pizza stone, a toaster, a convection setting — never a
VESSEL a fat fries in, since v28 every spelling: a Dutch or French oven
("Dutch-oven" too), an oven-safe, oven safe, oven-proof or oven proof pan,
a broiler or grill pan ("broiler-pan", "grill-pan" too, v29, Run 059
O8/S11: the corpus writes "broiler-pan" five times, none in a frying
sentence), a broiler-, grill-safe or -proof pan; "ovenproof",
a sheet pan and a pizza pan name no appliance) or a method verb
leading it ("bake/bakes/baking", "roast/roasts/roasting",
"broil/broils/broiling" … then "at", "to" or "in"; "baked/roasted/broiled/
grilled at|to|in" — never an adjective, "roasted peppers", nor a method word
naming a VESSEL, "baking/roasting/broiling" before "sheet", "dish", "pan",
"rack" or "tray", a hyphen too ("roasting-pan", "baking-sheet", v29) (v27 closer, the verifier's D8: "Heat the oil in a large
roasting pan over two burners to 350 degrees" fries), nor "baking
powder/soda"), or the words right after it do ("375 degrees in the oven",
"on the grill", "under the broiler", "in a hot oven" — three words at most
between, inside the temperature's clause: none of them a heat verb, so
"Heat oil to 375 degrees in pot and reheat oven" fries —, "a 350 degree
oven", "… and bake", "then roast", "and keep baking"). So "Heat the oil in a Dutch oven to 350 degrees; meanwhile
heat the oven to 200 degrees" fries, and "Brush the pitas with the oil and
heat them in the oven to 375 degrees", "… to 375 degrees and bake", "toast at
350 degrees" (no heat verb) heat nothing — nor "until shimmering" or
"smoking" with no temperature (a sauté's or a sear's: 81 counted ¼-cup oil
lines of the library sit beside one). Within one clause a method verb
or an appliance before the heat verb governs ("Brush the pitas with the
oil and heat them in the oven to 375 degrees"); since v29 "Set the pitas
in the oven and heat the oil to 375 degrees" and "Bake the croutons and
heat the oil to 350 degrees" fry (the new verb phrase and the fat's own
mention end the oven's or the method's clause; v26–v28 read them as
heating nothing). A frying temperature is
300–399 °F (judged at v28 on the library's six sentences naming a fat with
400–450 °F: 300–450 would read 0511's and 0672's 400-degree fries as
frying heat — their oils already zeroed by the mass rule — but would hold
0672's eaten "¼ cup coconut oil", its buffalo sauce, as ambiguous_medium)
written "350 degrees", "350 degree", "350 deg", "350 deg.", "350 degrees F",
"350 Fahrenheit", "350°F", "350° F", "350 °F", "350°" or "350F" (the degree
sign typed °, º or ˚), or the Celsius frying range 160–200 written "180°C",
"180° C", "180 °C", "180 degrees C", "180 degrees Celsius", "180 deg C",
"180 Celsius" or "180C"; never a number with a letter or another digit next
to it ("350 for", "180 cups", "1350 degrees"). Each of the library's 67
sentences naming oil with a 3xx-degree temperature reads as frying heat,
and v27's scoped rule changes no line of the library (all 13,615 replayed
rows and every oil and dredge line identical; v28's clause marks, vessels,
densities and thresholds change none either). The lead is ONE lookbehind
tried at the temperature's digits, the heat verbs one word scan with a set
lookup, the clause read only up to the temperature: linear in the
sentence (the v27 closer, the verifier's D11: the first cut's alternation
scans cost ~7 µs a frying sentence, +100 ms on a PUT over 36,361 frying
sentences at the caps; that PUT is now under 4a1c58e's, 387 -> 258 ms);
since v28 the words that can govern are located ONCE per sentence and each
temperature answered by a forward pointer (Run 058 S5/S9: v27 re-read the
clause per temperature — a 1,000-character sentence of 124 temperatures
1.19 ms, now 0.14, 4a1c58e 0.15). Since v29 (Run 059 S15 / Sonnet critic
2: v28 rebuilt its whole-sentence lists per fat per caller, 2–4× v27 on a
long sentence of one temperature) a sentence's reading — its
temperatures, heat verbs, boundaries, the fat's mentions, the governing
words — is built ONCE per recipe index and shared by every fat and caller,
each pass read only as far as a check needs and the governing words from
the clause's start, as v27 read the clause; every pass and pointer step is
counted (`heatClauseChars`). The heat paths of the cap shapes (heat-gov,
heat-mixed-3fat, heat-temps, heat-marks) run 106/170/143/84 ms against
v27's 164/261/198/148 and v28's 211/344/190/122.
A sentence binds to the line whose own written amount it names ("Heat 1 cup oil") or a word of
whose kind it names ("vegetable", "olive", "peanut", "sesame") — only
when the fat's noun phrase FOLLOWS that amount or word directly, with
nothing between but "of", "the", "a" and the recipe's own kind words of
that fat, eight words at most ("Heat ⅓ cup of the oil", "1 cup of the
vegetable oil" bind; "2 tablespoons butter to the oil" and "Stir 2
tablespoons lime juice into the salsa, then heat the oil" name no line;
a "pour off all but N" names the kept part, not a line). An amount or a
kind word two lines share binds NEITHER (v26: "Heat ¾ cup oil" beside a
"¾ cup vegetable oil" and a "¾ cup olive oil" holds both), and lines
count by position: two identical lines are two lines. One that names no
line belongs to the recipe's one frying CANDIDATE (or the one candidate
another sentence named), as does a fried food's held dredge. A candidate
is every line the mass rule could zero — ONE reading the mass rule
shares (v27, Run 057: v26 read candidacy from parsed amounts while the rule
read resolved grams, so "1 (48-ounce) bottle vegetable oil" or "3
tablespoons vegetable oil, for frying" was zeroed but no candidate and the
aioli beside it was zeroed alone): the mass rule itself — "for (deep)
frying", or 400 g or more of the fat read with NO food (its written volume
at the table density, 435 mL of oil, else its written or printed weight —
"1 (48-ounce) bottle" 1,361 g, "24 ounces" 680 g; the line's own amount,
not its "plus" part), the one reading the compute, the matches GET's
`held`, the apply-to-all's reach and an un-skip all read (the v27 closer,
the verifier's D3: the rule read the caller's resolved grams, so a reader
with none held the 48-ounce bottle while the compute zeroed it) —, a "for
(pan-/deep-)frying" label with any
amount, or ¼ cup or more in EITHER unit family — a written volume (its
same-food "plus" part included, since v28 in both families: "2
tablespoons plus 8 ounces vegetable oil" is one), or the line's grams resolved as the gram
rule resolves them (a written weight, a printed paren weight by its count)
at its food's table density: ¼ cup is 59.1 mL, 54.4 g of oil at 0.92 g/mL
(shortening and lard at 0.87 since v28, their FDC records' 205 g a cup;
a fat item the table refuses at oil's), so "8
ounces vegetable oil" fries like "1 cup" and every line the 400 g rule
zeroes is one. An amount-less line weighs nothing and is never zeroed or
held by a sentence. With two or more candidates, each such ¼-cup-or-heavier
line is held `ambiguous_medium` for a person, its `hold_note` the
sentence, never zeroed: 0690 Patatas Bravas' sauce oil typed as "½ cup
extra-virgin olive oil" beside its 3 cups — or the 3 cups written "24
ounces" — "Heat oil … to 375 degrees" is held, the 3 cups still frying
oil by their mass; since v27 so is it beside a "1 (48-ounce) bottle
vegetable oil", "1 bottle vegetable oil, for frying" or "3 tablespoons
vegetable oil, for frying" (each zeroed by the mass rule). A smaller line a sentence names keeps only that sentence. Since
matcher v27 EVERY medium threshold reads both unit families (Run 057: each
read `volumeMlOf` only, so a line written by weight skipped them all): a
line's written volume, else its grams at its food's table density — ¼ cup
of oil 54.4 g (0.92 g/mL), of flour 30.2 g (0.51), of panko 14.8 g (0.25),
of bread crumbs 26.6 g (0.45) and of a starch 31.9 g (0.54) since v28
(Run 058 S6: the corpus's "bread crumbs" and a tapioca or potato starch had
no figure, so "8 ounces plain dried bread crumbs" was no dredge — figures a
reader with no food reads, never a line's grams, which keep the record's
own portion), of sugar 50.3 g (0.85); the brine salt's 3 tablespoons (44 mL) 53.7 g of
table salt (1.22) or 31.7 g of kosher (0.72); a buttermilk soak's or a cheese
milk's 4 cups (exactly a written "4 cups", 946.35 mL, since v28) 974.7 g
(1.03): "20 ounces flour" is a dredge like "4
cups", "4 ounces table salt" a brine salt like "½ cup". A line whose food
the table has no density for keeps its volume reading. No library line
moves), a brine's salt, a
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
turkey share) — and labelled (since matcher v30 "beef rib slabs" too),
shellfish bought in the shell too (held
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
types), raw" and "Cabbage, chinese (pe-tsai), raw"; since matcher v32,
the live step's details read, FNDDS "Tamarind" (2709269) reads SR
"Tamarinds, raw" (167763, `cup, pulp` 120 g: "2 tablespoons tamarind
paste" is 15 g) and Foundation "Eggs, Grade A, Large, egg whole" (748967)
reads SR "Egg, whole, raw, fresh" (171287, `cup (4.86 large eggs)` 243 g:
"2 tablespoons beaten egg" is 30.38 g)) (the food stays the
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
large ("2 dried New Mexican chiles, … torn into small pieces" is no
small chile — since matcher v30 the piece table's 7.1 g pod, 14.2 g); a
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
a person's decision on such a row follows RULE A (since matcher v25, Run
055): the row stores ONLY the decision — its status, its food, grams a
person typed — and the hold, the grams unless typed, their `gram_source`
and `match.hold_note` are derived from the recipe AS IT IS NOW, by one
rule, at the PUT, at every compute (a steps, title or amount edit, a
matcher bump: the compute rewrites only those derived fields, never the
status, the food or typed grams) and at every matches GET (cache-only, so
a recipe saved since its compute already shows what the next compute
writes). The derived write is addressed by the row's CURRENT position: a
save that moves a decided row (a line deleted or inserted above it) and
changes what it derives is written at the line's new place (v26, Run 056
S1: 0129's confirmed liquid smoke, a line above it deleted and its strain
step taken out, is 14.2 g `portion` at its new position, fresh).
"Derived" is a fact ON THE ROW (v27, migration 014, Run 057): each decided
row's `derived_seq` names what its derived fields were computed for — the
layout seq and content hash its derivation read, `<seq>:<hash>`, the two
halves the freshness stamp names — written by every successful derivation
(a compute, a PUT) and, once, by the migration's boot backfill (a fresh
recipe's decided rows take its key). A recipe reads fresh only while
its stamp is current AND no decided row is underived (its `derived_seq`
is not the stamp's): ONE SQL predicate, read by the recipe page's
`status`, the `stale` sweep's scope and the job loops over the rows as
they are when read — so no writer's stamp can claim a derivation it did
not make (Run 057 S15/O1: a compute awaiting FDC stamped fresh over a
PUT's underived write). A derivation that cannot run because FDC fails a
fetch it needs (the food detail for household portions or an edible
yield, or the food itself when no cache holds it: the hourly budget spent,
no key, an outage) is ONE outcome on every path: the decision is stored (a
PUT answers `200`) with no `derived_seq` — UNDERIVED — its derived fields
exactly as the last successful derivation left them (never cleared; its
LINE hold kept, never a FOOD hold the engine row carried — Run 057 O3; a
decision an amount edit carried keeps its old text until a derivation
reads the new amount; a SKIP an amount edit carried keeps NO grams of the
old amount — a skip counts nothing, so they are only what an un-skip would
revive — unless typed on a discarded medium, which a successful derivation
keeps too: the v27 closer, the verifier's D2, 0279's peppercorns typed 77 g
for "2 teaspoons", skipped, edited to "3 teaspoons" and un-skipped during an
outage came back counted at 77 g), the recipe reads `stale` and the next
compute asks
FDC again — once per underived row per pass — and a compute goes on past
the row: it writes the rest and its totals, and only then reports the
failure (the job stops with FDC's reason). FDC answering "no such food"
when no cache holds the food is NOT an outage (v27, Opus critic 2): the
decision is derived — to the `food_gone` hold (above), typed grams kept
as typed, none derived — the row counts as derived (the recipe held, not
stale) and is not asked again until a pick, a skip or an edit moves it —
or a cache holds the food again: "derived for" names EVERY input a
derivation reads (v28, RULE A; Run 058 O1/S1), the recipe's inputs AND the
food caches, so every compute re-reads a `food_gone` row's food from the
caches (no request) and derives it again the moment one holds it (a search
answer listing it again: 0857's flour counts its 248 g, the matches GET and
the row agreeing). A record whose nutrients the totals read from a sibling
record (napa cabbage 2727583 reads 169979) has that sibling resolved WHERE
its food is — by the decided row's derivation (compute, PUT), by the
engine's candidate or the key's prior decision, by an apply-to-all's
weigh — never by a separate prefetch the totals depended on (v28, Sonnet
critic 2 / S3): a sibling FDC answers "no such food" for makes the decided
row `food_gone`, passes the engine's candidate over (the line matched by
the next candidate) and leaves an apply-to-all target `unavailable`; a
sibling FDC cannot serve now leaves the decided row underived.
The totals never fetch (v27): `recomputeTotals` reads the caches only (a
serving-basis change recomputes nothing: arithmetic over the stored
totals). A PLAIN recompute — a PUT, an apply-to-all target — whose totals
would meet ITS OWN line's food (or that food's nutrient record) no cache
holds resolves it first — at most two requests through the request's
one-per-food memo, the first GLOBAL failure stopping them (v29, Run 059
S13: v28 resolved every uncached food the recipe's rows read, one request
each — 400 sequential requests for one PUT on a recipe of 400 underived
rows, never stopping on an outage; v27 made none). Every OTHER food no
cache holds stays missing — a decided row underived (the next compute
derives it: `food_gone`, or the food counted), an engine row's recipe
stamped stale as waiting on USDA (the next compute re-matches it) — the
sweep's job, never the PUT's (0857's flour gone from every cache, a
confirm of its baking soda: no request, the flour underived, `stale`);
and a `food_gone` or `food_unavailable` row is held. Only the derivations that read a food fetch one: a skip
on the line's own amount reads none, and grams a person typed read the
food from the caches (0279's typed "2 teaspoons Sichuan peppercorns": no
FDC request at the PUT or at any compute) — and ask FDC only for a food no
cache holds; a confirm or a pick reads its food and, for a volume or count
amount or an edible yield, its detail. By hold kind: `confirmed: true` — "this food, at the engine's
current weight" — on a held medium counts its eaten part when the engine
knows one (a divided line's, an eaten "plus" part, the rest of a written
share; 0129 Indoor Pulled Chicken's liquid smoke, its "remaining 1
teaspoon", 4.73 g) and otherwise writes `grams: 0`, `gram_source:
discarded` (basis "poured away — counted as 0 g"), `hold` null, `hold_note`
"eaten part counted after your confirm" or "poured away after your
confirm"; a pick ALONE (a food, no grams) on a DIVIDED line (an eaten part
the engine knows, whatever the hold) counts that part and resolves the
hold (`gram_source` `discarded`, `hold` null, `hold_note` "eaten part
counted after your pick": Shrimp Salad's "¼ cup plus 1 tablespoon juice"
picked on "Lemon juice, raw" is its tablespoon, 15.2 g), on a line wholly
poured away (`discarded_medium`, no eaten part) writes 0 g, `hold` null,
`hold_note` "poured away after your pick", and on any other line held as a
medium part of which is eaten (`starter_discard`, `coating`,
`partial_pour_away` with no eaten part known, and since v25 an
`ambiguous_medium` oil, all or none of which is eaten: 0148's dredge flour, a
starter feeding) keeps the hold with `grams: null` — 0 g would drop the
eaten part with no flag — and `hold_note` the hold's own words, until a
skip or typed grams answers it; grams a person typed answer every hold
(`hold` null) and stay as typed through any edit but an amount edit of a
line that is no medium (then they are re-derived); a skip stores no hold.
A line that stops being held is weighed (0148's flour confirmed or picked,
then its dredge taken out of the directions: 566.99 g, whether or not a
compute ran between), and a line that becomes held is resolved or held by
the same rule. A line with no amount derives no weight for a person's
decision (v26, Run 056 O13/S22; the engine's 0 g is for lines no person
decided): a pick stays with no grams (in `no_grams`, for a person to
weigh; held, its hold by the kind rule above — 0318's poured-away "Kosher
salt" picked is 0 g `discarded`, "poured away after your pick"; a typed
"All-purpose flour, for dredging" picked keeps `coating`), a confirm of a
held medium is 0 g `discarded`, "poured away after your confirm", and a
confirm of an unheld line keeps the engine's 0 g `unmeasured`; "eaten part
counted" is said only when an eaten part weighs more than 0 g. A bare re-confirm never replaces
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
`coating` (since v22, Q2: ¼ cup or more of flour, starch or crumbs — since
v27 by weight too, 30.2 g of flour — that
a step names in a dredge — "dredge … in the flour", "shake off excess
flour", or set out in a shallow dish — or a line that says "for dredging" /
"for coating". Since matcher v33 (the owner's dredge-reach ruling,
2026-10-03, on the dredge survey of the 47 corpus recipes that coat a food
in a dry coat) such a line is held in ANY cooking class — sautéed, baked,
shallow- or deep-fried — whose directions LEAVE AN EXCESS of the coat: part
of a dredge stays in the dish and is thrown out whatever the cooking
method, so a person enters the grams eaten or confirms as is (no coating
fraction: none is sourced). The signal is a sentence that removes the
excess — a removal verb (shake, remove, pat), then "excess" naming the coat
or nothing: "dredge … in the flour, shaking off the excess" (0148, 0122
Kiev), "Shake excess flour from each steak" (0304), "coat with flour and
shake to remove excess" (0418 piccata), "shaking gently to remove excess"
(0415, 1133), "Using pastry brush, remove excess cornstarch" (0257),
"Thoroughly pat off the excess cornstarch mixture" (0235) — never a
liquid's excess ("allowing the excess to drip off", "blot the excess oil",
"wipe off the excess salt") and never in a step that shapes a dough (0792's
rolls and 0806's pita dusted with flour are no dredge). It reproduces the
survey's reading on all 47 recipes. A coat WHOLLY EATEN stays counted: a
toss (0536 orange beef, 0464 steak frites), a binder (0289 best crab
cakes), a crust pressed on with no excess sentence — a coat set out in a
shallow dish alone is no excess (0115 katsu, 0415 best chicken Parmesan,
0287 salmon cakes, 0414 Marsala, 1093 tacos, 1185's air-fried panko) — and
a batter the food is folded into (0672). The CP9 ruling stands as a
SUFFICIENT condition: a recipe that fries holds its dredge with or without
an excess sentence (the fry read from the directions since v23: a step
that says fry as a verb — "pan-fry", "deep-fry", "shallow-fry", "continue
to fry"; since v24 never a stir-fry or an oven-fry, and since v25 "stir
fry", "air fry", "oven fry", "dry fry" spelled with a space, "do not" /
"don't" / "never fry", a noun — "each fry", a "deep-fry thermometer" — an
optional note that opens its sentence, a negation, bacon or prosciutto
fried in its own fat, or rice toasted for a pilaf — heats a frying fat to a
frying temperature, discards the fat the food cooked in, or a line "for
(deep) frying"). Four such standing holds have no excess sentence and are
the owner's open question: 0288 Maryland crab cakes' flour ("Lightly
dredge"), 0149 Easier Fried Chicken's 2 cups, 0525 Orange-Flavored
Chicken's cornstarch, 0042 Almond-Crusted Chicken's panko. v33 moved 25
lines, 17 recipes complete → partial: 18 dredges (0077, 0117, 0118, 0122,
0206, 0235, 0254, 0257, 0315, 0407, 0415, 0416, 0418 ×2, 0419, 0420,
0421, 0466) and 7 crumb lines (below). Since matcher v31 (B4; every held dredge since v33) the bread a
held breading processes into its crumbs is held with its flour: a line
whose head is bread, in a recipe that holds a dredge, where a step puts the
bread through the processor ("Process the dry bread in a food processor to
very fine crumbs", 0233; "pulse the bread … to coarse crumbs", 0206) or the
line says so ("pulsed in a food processor to coarse crumbs", 0118), and a
sentence sets the crumbs out in a dredge or coats the food with them ("Coat
all sides of the chop with the bread-crumb mixture") — 0233's 7 slices,
0114's 3, and since v33 0118, 0122, 0206, 0254 and 0407. Since v33 a
crumb or panko line of at least a quarter cup is held too, in a recipe that
holds a dredge, when a sentence coats the food with crumbs — the steps
call these crumbs by another name than the line's head, so the dredge's
own detection never reaches them: 0416's "1½ cups panko" ("coat both sides
of the chicken with the bread crumbs"), 0117's "1 cup panko bread crumbs"
("Coat all sides of the breast with the panko mixture, pressing gently so
that the crumbs adhere"). A coat part that
is neither bread nor a dredge head — nuts, cheese, Melba toast, saltines,
potato chips, cornflakes — stays counted (the owner's follow-up). A divided
line's part set out in the coat's dish is the dredge's: 0206's "¼ cup plus
6 tablespoons" flour holds with its 6 tablespoons whisked into the egg
whites as the eaten part. Held until the server's `coatingFraction` switch
— null, no figure set — gives the share a dredged
food keeps), `partial_pour_away` (since v22, Q4: a line of a braising
liquid — the sentence before the strain that names it and opens "whisk"
or "bring", the food added ("add", "arrange") in the next sentence — that
is strained after cooking ("cooking liquid through … strainer") and of
which a later step keeps only a written part ("Pour 1 cup defatted
cooking liquid", "½ cup reserved defatted liquid"), no step using the
"remaining" liquid; since matcher v31 also a poach whose liquid is poured
away but a measured part — "Remove ¼ cup liquid from the saucepan and set
aside; discard the remaining liquid" (0488 Enchiladas Verdes): every line,
first of its head, that the sentences of that step before it name (the
oil, onion, garlic, cumin and broth simmered with the chicken; the
chicken lifted out is not named), unless a later sentence uses a
"remaining" liquid, the parts written after that step eaten ("the
remaining 2 teaspoons oil", 9.07 g; "the remaining 1 teaspoon garlic" —
no grams: 1104647 publishes no volume portion); the kept part is
`match.hold_note`, `"¼ cup liquid; 2 teaspoons oil is used outside the
braise, eaten"`),
`ambiguous_medium` (since v25, RULE B: an oil of ¼ cup or more that a
frying, discard or pour-off sentence — or a fried food's dredge — could
be about while another oil line could too, no word of the sentence
naming which; see `discarded` above; since matcher v31 also every frying
candidate of a fat no sentence of its own fries — none names it with a
frying heat, a discard or a pour-off — in a recipe whose evidence is the
fry VERB, when no line of the fat is zeroed by the mass rule (the owner's
R4 ruling: 0288 Maryland Crab Cakes' ¼ cup, "pan-fry until the outsides
are crisp", no longer zeroed by its dredge; 0674 Corn Fritters' ¼ cup and
0675 Southern Corn Fritters' "1 teaspoon plus ½ cup", "Fry until golden
brown", no longer counted whole — the teaspoon that sautés the corn is
the eaten part, 4.53 g held; 0672's sauce coconut oil stays counted, its
fryer oil zeroed by mass); the sentence is `match.hold_note`).
These four are
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
to its own line: never counted twice). A person's decision on such a line
is RULE A's (above: a confirm counts the eaten part or pours the line
away, a pick on a divided line counts its eaten part, any other keeps the
hold with no grams — at the PUT, every compute and every GET),
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
engine pick scored from 0.52 up to 0.54), and since matcher v27 one hold
of a person's decision, `food_gone` (FDC answers "no such food" for the
decided food — or for its nutrient record — and no cache holds it: out of
the totals, in `check`; a pick of another food or a skip finishes it — a
confirm or typed grams cannot count a food with no record; RULE A below),
and since v28 `food_unavailable` (FDC failed that food's detail — not a
404 — in 3 computes in a row: held the same way, re-read once the food's
detail is cached); `hold_note` (since v22): the
hold in words where the code alone does not say it — a
`partial_pour_away`'s kept part ("1 cup defatted cooking liquid"), and
since matcher v25 an `ambiguous_medium` line's sentence, quoted — `"Heat oil in
large Dutch oven over high heat to 375 degrees."` — or "a fried food is
dredged in a step", and
since matcher v23 a divided `coating` or `partial_pour_away` line's part
eaten outside the medium, as written — "1 teaspoon flour is used outside
the dredge, eaten" (1133 Francese), "½ cup reserved defatted liquid; 1
teaspoon liquid smoke is used outside the braise, eaten" (0129 Indoor
Pulled Chicken): its grams, held until a confirm counts them; and since
matcher v25, on a person's decision, what RULE A derived for it from the
recipe as it is: "eaten part counted after your pick" / "… after your
confirm", "poured away after your pick" / "… after your confirm" (a held
medium the decision resolved: `hold` null), or the kept hold's own words
on a pick that keeps it — else `null` (no hold, no decision that resolved
one). Such a held line sits in the `check` bucket until a person confirms,
re-picks or skips it — a person's decision resolves the hold by RULE A (a
confirm, a skip, a grams edit always; a pick on a divided or wholly
poured-away line, never on any other line held as a medium part of which
is eaten: that pick keeps the hold, `grams: null`), and an un-skip re-derives it for the food now on the
line, so a person's food is never held for the engine's old reason (a
person's food — confidence 1, a pick or a decision, inherited or not — is
held again only by a LINE hold: `discarded_medium`, `starter_discard`,
`coating`, `partial_pour_away`, `ambiguous_medium`, `second_food`, `in_shell`; an un-skip is no confirm, and only a confirm or a pick on the
line clears one), and an engine row whose line the
second-food rule counts moves to the rule's record with the rule's grams,
as a compute writes it. A
decision reaching the line by `apply_to_all` or inheritance clears a FOOD
hold (`no_nutrients`, `dried_for_fresh`, `cured_for_fresh`, `borderline`,
`unnamed_food`) too, never a LINE hold (`discarded_medium`,
`starter_discard`, `coating`, `partial_pour_away`, `ambiguous_medium`, `second_food`,
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
as any line's is (in this library all 142 answers are cached). A rank-as
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
`vermicelli` → `pasta dry enriched`. Since matcher v30 (the user's Q7
ruling of 2026-10-01: meats and birds at the printed GROSS weight,
labelled approximate, unless the record publishes a refuse yield) the
bone-in and whole cuts read their raw record: `7-pound first-cut beef
standing rib roast`, `first-cut beef standing rib roast` (read `beef rib
whole raw`) → `beef rib whole ribs 6-12 separable lean and fat trimmed
to 1 8 fat choice raw` (168675); `beef flap meat` (reads `sirloin steak
tips or boneless beef short ribs`) → `beef top sirloin steak raw`
(2727574, flagged below); `beef rib slabs` (reads `baby back ribs`) →
`beef rib back ribs bone-in separable lean and fat choice raw` (173405);
`bone-in boston butt roast`, `boneless pork butt roast with at least 1
4-inch-thick fat cap` (read `boneless pork butt roast`) → `pork fresh
shoulder boston butt blade steaks separable lean and fat raw` (167849:
the bone-in roast reads its USDA refuse, × 0.76); `bone-in chicken
parts`, `bone-in skin-on chicken parts` → `chicken broilers or fryers
meat and skin raw` (171447); `boneless long-cut beef shanks` → `beef
shank crosscuts separable lean only trimmed to 1 4 fat choice raw`
(169441); `butterflied leg of lamb`, `shank end boneless leg of lamb`
(read `shank end boneless leg of lamb`) → `lamb leg shank half separable
lean and fat trimmed to 1 4 fat choice raw` (174315); `cod or other thick
whitefish fillets` (reads `cod`) → `fish cod atlantic wild caught raw`
(2684444); `flat-iron steaks` → `beef chuck shoulder clod top blade steak
separable lean and fat trimmed to 0 fat choice raw` (172125); `frozen
butterball or kosher turkey` (reads `turkey whole meat and skin raw`) →
the same words (171081); `salmon steaks`, `skin-on side of salmon` (read
`salmon steaks`) → `fish salmon raw` (2706284, a search hit: a weight line
needs no detail); `turkey drumsticks and thighs`, `turkey leg quarters`
(read `bone-in turkey thighs`) → `turkey retail parts thigh meat and skin
raw` (171533, flagged below). The fresh half ham ("bone-in half ham with
skin", reads `meaty smoked ham shank or 2 3 smoked ham hocks`) → `pork
fresh leg ham shank half separable lean and fat raw` (168226) since
matcher v32: its detail, read in the live step, publishes no refuse yield
(4 oz, roast 3,868 g, lb), so "1 (6- to 8-pound) bone-in fresh half ham"
is its printed 3,628.74 g, labelled approximate. (The live step,
2026-10-03: 14 requests on a scratch copy — 12 food details and 2
searches. No v32 rule makes a request; each reads answers already
cached: a rank-as candidate from a snapshot-13 search (fetched 2026-09-08 or
2026-09-26), a portion from a live-step detail. The chorizo rule
reads no live-step answer — 174603 is a hit in the 2026-09-26 `salami`
answer — and the portobello detail (2003598) and the two chorizo
searches are read by no rule.) Since matcher
v32 (the live step) also `chicken leg quarters`, `bone-in chicken leg quarters`
(each its own answer) → `chicken leg meat and skin raw` (172378: no
refuse yield published — leg 344 g, drumstick 111 g, thigh 185 g, back
49 g — so the printed gross weight, labelled approximate); `oil-packed
tuna` → `tuna white canned in oil drained` (175157; "2 (6½-ounce) jars"
stays the printed 368.54 g); `sweetened cranberry juice` (reads
`cranberries`) → `cranberry juice cocktail bottled` (171903, `cup (8 fl
oz)` 253 g); `dried onions` (reads `onions`) → `onions dehydrated flakes`
(170002, tbsp 5 g); `jarred pimentos` → `pimento canned` (168559, cup
192 g); `cooked wheat berries` → `wheat khorasan cooked` (169744, cup 172
g, flagged below); `brioche buns` → `brioche` (2707682): its detail
weighs a bun only as "1 piece" 77 g, a portion the whole-item finder
reads as a dish serving, so a `brioche bun` piece figure of 77 g carries
it, flagged approximate because the piece is read as one bun ("4 brioche
buns" = `"4 × 77 g each · approximate (FDC's 1-piece portion read as one
bun)"`). Not enabled, its check failed: `portobello
mushroom cap` (2003598 publishes a racc portion only — no per-cap
weight). Since matcher v31 (the CP10 rulings, 2026-10-03): star
anise (`star anise pods`, `star anise pod`, each its own answer) →
`spices anise seed` (171316, flagged); Q7's eight small groups —
`kalamata olives`, `nicoise olives` → `olives black` (2710090); `ruby
port`, `cream sherry`, `sweet marsala`, `mirin or sweet sherry` (read
`sherry`) → `wine dessert sweet` (2710692); `dry marsala` → `wine dessert
dry` (175112); `dry riesling` → `wine table white riesling` (173200,
exact); `barolo wine` (reads `chianti`) → `wine red` (2710688, exact);
`fluid ounces champagne` (reads `dry white wine`) → `wine white`
(2710689); `kirsch` (reads `brandy`) → `brandy` (2710699); `peach
schnapps` (reads `kirsch`) → `liqueur` (2710623); `almond extract`,
`coconut extract` → `vanilla extract` (173471); `ancho chile powder`,
`kashmiri chile powder`, `pul biber or ground dried aleppo pepper` (read
`paprika`) → `spices paprika` (171329); `chipotle chile powder`, `ground
chipotle powder` (read `spices pepper red cayenne`) → `spices pepper red
or cayenne` (170932); `aji amarillo chile paste` (reads `pickled jalapeno
chiles`) → `sauce hot chile sriracha` (171186); `thai basil leaves`,
`thai or italian basil leaves` (read `basil leaves`) → `basil raw`
(2709780); `meatloaf mix` (reads `93 percent lean ground turkey`) → `beef
ground 80 lean meat 20 fat raw` (2514744); `duck fat` → `fat goose`
(173572; "6 cups duck fat, chicken fat, or vegetable oil for confit" is a
frying medium, 0 g discarded — the `fat` head joined the frying fats —
while "6 tablespoons duck fat" roasting potatoes counts 76.80 g); `chili
oil` and `vegetable oil more for cooking grate` (read `vegetable oil`) →
`vegetable oil nfs` (2710180; the grate line exact); `chinese black
vinegar` (reads `balsamic vinegar`) → `vinegar balsamic` (172241);
`anchovy paste` → `fish anchovy` (2706232, weighed above); the misc
mappings (each read from its prep30 review): `anaheim chiles`,
`cubanelle peppers`, `cubanelle pepper` (read `cubanelle peppers`) →
`pepper banana` (169394); `angel hair pasta`, `dried pappardelle`, `penne
rigate` → `pasta dry enriched` (169736, exact); `asian chili-garlic
paste` and `asian chili-garlic sauce` (read `pickled jalapeno chiles`) →
`sauce hot chile sriracha` (171186; the sauce read "Garlic sauce", 683
kcal); `broccolini` (reads `broccoli`) → `broccoli` (747447); `candied
yams` → `yam raw` (170071); `chicory or escarole` (reads `escarole`) →
`escarole cooked boiled drained no salt added` (168413); `ciabatta`,
`ciabatta bread`, `crusty bread`, `rustic crusty bread` (read `sprigs
thai or italian basil`) → `bread italian grecian armenian` (2707614,
exact); `cornichons` (reads `spicy pickled radishes`) → `pickles dill`
(2710078); `dried red beans` (reads `red kidney beans`) → `beans kidney
red mature seeds raw` (173744); `frank s redhot original sauce` (reads
`tabasco or other hot sauce`) → `hot pepper sauce` (2710093, exact);
`fresno chiles`, `habanero chiles`, `habanero chile`, `thai red chile`
(read `serrano or jalapeno chiles`) → `peppers hot raw` (2709798,
exact); `gai choy` (reads `dry mustard`) → `mustard greens` (169256,
exact); `instant espresso` (reads `instant espresso powder`) →
`beverages coffee instant regular powder` (171893, exact); `italian sub
rolls` → `roll multigrain` (2707782); `jarred whole artichoke hearts in
water` → `artichoke` (2709766); `ketchup or chili sauce` (reads
`ketchup`) → `ketchup` (2709733, exact); `lyle s golden syrup` (reads
`light corn syrup`) → `syrups corn light` (168837); `mexican lager`,
`mild-flavored lager` (read `beer`) → `beer` (2710616, exact); `montasio
or aged asiago cheese` (reads `parmesan cheese`) → `parmesan cheese`
(325036); `new mexican pods` (reads `ancho pods`) → `peppers ancho dried`
(169396); `ouzo`, `pastis or pernod` (read `brandy`) → `brandy`
(2710699); `palm sugar` → `sugar brown` (2710260); `preserved lemon`
(reads `lemon or lime wedges`) → `lemon peel raw` (167749); `radishes
with their greens` (reads `radishes`) → `radish` (2709803, exact); `sweet
onion or 2 shallots` → `shallots raw` (170499, exact); `thai with salt
preserved radish` (reads `dill or sweet pickles`) → `radishes pickled`
(2710099); Spanish chorizo — `spanish-style chorizo`, `spanish-style
chorizo sausage` (read `salami`) → `salami italian pork` (174603
"Salami, Italian, pork", flagged; matcher v31 read FNDDS "Chorizo",
2706179, a cooked fresh profile; FDC has no dry-cured chorizo — the live
step's `chorizo pork and beef` search returned two taco salads and
`chorizo` only 2706179 and the fresh SR links, both answers cached and
unused: the owner's decision of 2026-10-03) — and `linguica sausage`
(reads `smoked sausage`) → `sausage smoked link sausage pork` (174584,
exact). Since matcher v32 `low-fat sour cream` (reads `sour cream`) →
`sour cream light` (173443, not flagged; the 2 tablespoons are 28.69 g by
the sour-cream density, the record's own cup 230 g agreeing). A few
rewrites are APPROXIMATIONS, flagged in
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
is 456 g), since matcher v30 (Q7) beef flap meat (bottom sirloin) as top
sirloin (2727574: "1½ pounds beef flap meat, trimmed" is `"from 1 1/2
pound · approximation (counted as Beef, top sirloin steak, raw)"`) and
turkey drumsticks and thighs, and turkey leg quarters, as turkey thigh
meat and skin (171533; FDC's leg record 171493 has no cached detail —
their weight is the gross weight, labelled approximate too), since
matcher v31 (the CP10 rulings) star anise as anise seed (171316), and
every Q7 stand-in above not marked exact — the brined olives as black
olives (2710090), the sweet and fortified wines as dessert wines (2710692,
175112), champagne as white wine (2710689), kirsch, ouzo and pastis as
brandy (2710699), peach schnapps as liqueur (2710623), almond and coconut
extract as vanilla extract (173471), the single-chile powders as paprika
(171329) or cayenne (170932), ají amarillo and chili-garlic paste or
sauce as sriracha (171186), Thai basil as basil (2709780), meatloaf mix as
80/20 ground beef (2514744), duck fat as goose fat (173572), chili oil as
vegetable oil (2710180), black vinegar as balsamic (172241), anchovy
paste as fish anchovy (2706232), Anaheim and Cubanelle as banana pepper
(169394), broccolini as broccoli (747447), candied yams as raw yam
(170071), chicory or escarole as boiled escarole (168413), cornichons as
dill pickles (2710078), dried small red beans as kidney beans (173744),
Italian sub rolls as multigrain rolls (2707782), jarred artichoke hearts
as artichoke (2709766), Lyle's golden syrup as light corn syrup (168837),
Montasio or aged Asiago as Parmesan (325036), New Mexican pods as dried
ancho (169396), palm sugar as brown sugar (2710260), preserved lemon as
lemon peel (167749), Thai salted radish as pickled radishes (2710099) and
Spanish chorizo as FNDDS "Chorizo" (2706179), since matcher v32 as
"Salami, Italian, pork" (174603), and since matcher v32 cooked wheat
berries as cooked khorasan wheat (169744: "2¾ cups cooked wheat berries"
is `"2 3/4 cup · USDA portion · approximation (counted as Wheat,
khorasan, cooked)"`, 473 g) — and a FRESH oregano, sage,
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
`ambiguous_medium`, `in_shell`) is never counted, whatever its food or score: no
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
grams re-derived for the NEW line from the caches alone (when that needs
a fetch the GET never makes, or a food no cache holds, the row is shown AS
STORED — its grams, source and hold as the last derivation left them, what
the totals count: RULE A's one unhappy outcome, v26), and
`match.carried_from`: the line's previous text — the
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
media rules, which read the directions by sentence: since matcher v25 a
sentence over 1,000 characters is read for its first 1,000 and the rest
ignored — the server logs which step, once per recipe and content (v26) —
and the steps are indexed once per recipe (sentence breaks, each pattern's
matches, each salt's mentions), so a mention's sentence and every match
after it are found by binary search and the rules' cost is linear in the
recipe's step text, end to end — Run 055 S4/O2/O3: a salt line on 40 legal
steps took 39 s at v24, under 100 ms now. Since v26 that holds per LINE too:
whatever a rule derives per recipe or per food (who owns each mention, which
lines write each amount, the sentences naming a food, the frying-oil
owners) is derived once and shared, so a line's answer costs only its own
mentions — the compute, the matches GET, the PUT pick and confirm, the
decided GET and the apply-to-all are each pinned by counts (every memo
family bounded per recipe, head, step or sentence; a frying-heat check
read in full only on a sentence carrying a three-digit run, the digits
every frying temperature starts with; the layout decoded at most once,
twice on an apply-to-all) at the editor's caps (400 lines, 120 steps of
10,000 characters, 1,000 characters per line, each asserted by the shapes;
the server test
`nutrition_v26_cost_test.dart`, "RULE C end to end at the caps"): at v25
Run 056 measured a salt-written recipe at ~24–27 s per compute or member
matches GET and a dredge-written one at ~123 s per compute (159 s was the
v26 fixer's own one-readAll measurement of the salt shape, not Run 056's
figure), under 1.2 s now;
since v27 each per-recipe index is paid by the caller that amortises it,
and since v28 by MEASURED amortisation (the v28 closer; v27's "the second
food asked builds it" and the first v28 cut's one-line declaration were
proxies — Run 058 O4: an oil line in a recipe that dredges and fries asks
two foods, and each recipe the matches GET reached for 0149's ten shared
lines built the inversion, 22 per GET): a food named in the directions is
looked up alone until what a recipe's lookups have paid reaches the cost
of the inversion, then the inversion is built, once. Since v29 both read
ONE word index per step (every word's start and a hash of its letters,
built once per step in one pass over its characters, the sentences'
starts taken from the sentence split) and the cost unit IS the cost (Run
059 O9: v28 charged a regex pass over a step one unit per character,
which ran 0.1 ns a character over corpus steps and 9 over words sharing
the food's prefix, so a crafted recipe paid 30 such passes before
building and its whole read ran 2.5–4× slower than fd34433): a lookup
visits every word of the steps once, comparing its hash with the hashes
of the food's word forms — its own word, its "s"/"es" plural, a "-y"
food's "-ies" (a food of several words or other characters, "half-and-half",
by its leading word) — and confirms a hash that agrees AT the word (the
same match `_names` makes: the whole word, a word boundary after it,
never after "garlic ", within one sentence), so two words of one hash
never name each other. It pays, exactly, the words it visits plus each
confirm's characters; the inversion (each word's hash → its places, every
word read once) costs 12 lookups (measured, JIT, 3 rounds: a word visited
0.95–1.0 ns at the caps and 2.1 over the corpus, the inversion 7.1–8.9 ns
a word at the caps and 29–31 over the 1,198 corpus recipes — 7.5–9.4
lookups at the caps, 14–15 over the corpus; 12 is within 1.6× of each) and
is built when the paid lookups reach 12 × the words: the lookup that lands
exactly on it is the last (`<`, pinned by heads no step names, each paying
exactly the words). A food opening on no word character is read sentence by
sentence. So no reader pays more than about twice the cheaper choice
whatever the words spell: a reach that asks a cap recipe 8 foods never
builds it, a compute or matches GET of the cap recipe itself (400 foods)
builds it after 12 lookups. Run 059 O9's shape (400 one-word foods of 38
z's and a tag, 120 steps at the cap of words of 38 z's and "qq"; every
line's medium readers): fd34433 104–110 ms, v28 420–428 ms, v29 64–87 ms
(900-character foods: 494–505, 484–488, 463–471 ms). Run 058's O4 shape
cold (21 cap recipes): the oil reach 952–967 ms (v28) → ~985 ms, the
matches GET 1,451–1,460 ms → ~1,300 ms. Run 058's O4 shape
(21 cap recipes, 0149's lines; interleaved 3 rounds, fd34433 → v28): the
oil reach GET 6.3–6.4 s → ~1.5 s with 2 inversions (the viewed recipe's
own rows and the reach's copy of it, read for its 400 keys; v28's first
cut 22, 2.1 s), the garlic-line GET 1.7 s → ~1.4 s, the oil apply-to-all
6.4 s → 1.5 s with none. The oil GET stays 4–6 % over the garlic GET: each
reached recipe is asked 8 foods, not 1 (one lookup each). The price
of measuring, at the caps (v28): a recipe's own matches GET pays its scans
before the build, 20–60 ms over v28's first cut (brine, cheese and
long-lines shapes), and a compute that asks few foods never builds it,
~40 ms under. Accepted
(the owner, v28 closer): the frying-heat reading at the caps (three fats ×
1,200 sentences of ~990 characters, each a linear clause reading) stays at
1.0–1.3 s per compute, GET or write — v26's level, from 3.9–6.0 s at
fd34433. The matches GET resolves
each row's food from the caches ONCE (the derivation reads what the body
shows — v27 read it two or three times per typed row: 400 typed rows,
3.3 s → 70 ms against v26), and a compute, or a person's write with its
apply-to-all, asks FoodData Central ONCE per food per pass — every id
asked and every "no such food" or failure is remembered for the pass (400
typed rows on one retired food: 400 requests at v27, 1 now; 100 napa rows
whose nutrient record is uncached: 1 request) — and since v29 a FOOD
failure for the whole JOB (a sweep asks a failing food once).
The substring readers (a small salt dissolved beside a brine salt, a
"plus" line's amount named in a step) read ONE inverted name → sentence
index per recipe, never a scan per name or per pair of names — Run 057:
a 20-recipe reach at the caps 7.1 s → 1.9 s per cold GET and 13.9 s →
3.0 s per apply-to-all, 200 distinct dissolved salts beside 199 brine
salts 31 s → 0.3 s per pass; every memo key names every coordinate its
derivation reads, pinned by an oracle comparing every answer with the
memos on (both line orders) and off (`nutrition_v27_cost_test.dart`,
`nutrition_v27_memo_keys_test.dart`);
the matches GET reads each line's text, key and same-key reach once per
request, not once per line — Run 055 V1: 160 identical 1,000-character
lines took 16 s, ~0.3 s now),
so it expands at most
10,000 layouts (`pairingBudget`) and then keeps the best found so far:
reached far past a few edits (a list shuffled whole with a quarter
rewritten in one save), and — rarely — on a save of many identical lines.
Since v29 a RUN of identical lines (consecutive rows of one text and
ingredient) is ONE item, an ordered multiset (Run 059 O12/S12/S14: v28
laid a run in its own order but still chose which twin each line took, so
one line inserted, deleted or replaced before 50 or more twins spent the
whole budget — 400 twins 1.0–4.3 s a call, on every compute, PUT and
matches GET until the next compute): the search decides only how many of
a run's rows the lines take and on which lines, never which twin, and
reads a run's untaken rows as one block in its bound. A run giving fewer
rows than it has keeps its DECISIONS first (the fewest lost), in order;
of the rows it gives, the surplus is dropped where the fewest rows leave
their own positions, ties dropping from the END (a layout is its own next
layout: 400 decided twins with the first deleted keep rows 0–398 on lines
0–398 and drop the last row's decision; with the first line replaced by
another food, the replaced row's), and they are laid on their lines in
position order — exact for the reading's cost (a crossed pair of twins
uncrossed is an in-order chain at least as long) and for the decisions it
keeps. Then a twin standing off its own line swaps with the twin of its
run on it whenever that lowers the layout's tie-breaks, as before. The
400-twin one-edit saves (the first, middle or last line replaced,
deleted, inserted or appended) take ~800 layouts and 20–45 ms; 200 twins
every other one decided with a line inserted mid-run 10,000 → at most 402; the
gap oracle's seed 41487 (eleven twins, three edits) took 39,789 layouts at
v27, 4,916 at v28 and 2,760 now. The pairing oracle's model stays strict
(a move among twins costs a move): the engine never crosses two twins, so
each layout it returns is one the model already reads as cheapest, and a
twin swap on an unchanged save stays a violation. Twins apart (another
line between) are still distinct rows: a fuzz of 2,000 twin-heavy saves
(12–15 lines of three texts and an amount variant, one to three edits)
never reaches the budget, and of 30,000 saves of 11–16 lines over two
texts one does (v28: two). Measured (JIT, real corpus lines): an unedited list is one
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

Every hold has ONE action table (v28, RULE A; salt_shared `holdActions`,
read by this PUT's gate, the review queue's `finishes`/`finishable` and the
app's sheet and queue): which decisions finish the held line, which the
sheet offers, which this PUT accepts, and whether a pick or confirm on it
may become the ingredient's decision library-wide. A FOOD hold of the
engine's pick (`no_nutrients`, `unnamed_food`, `dried_for_fresh`,
`cured_for_fresh`, `borderline`) and the LINE holds `discarded_medium`,
`in_shell`, `second_food`: any decision finishes it. A medium a part of
whose line is eaten (`starter_discard`, `coating`, `partial_pour_away`,
`ambiguous_medium`): a skip, a confirm or typed grams finish it; a pick
alone is no promise (it keeps the hold unless the eaten part is known). A
food with no record (`food_gone`, `food_unavailable`): only a pick of
another food or a skip — `{confirmed: true}` or `{grams}` (with or without
`apply_to_all`) is `422` with nothing written and no FDC request (Run 058
O7/S13: the sheet's Confirm re-asked FDC and kept the row held): "USDA has
no record of this food to count — pick another food or skip the line."
on `food_gone`, "USDA could not serve this food — pick another food or
skip the line." on `food_unavailable` (v29, Run 059 S3). The gate judges
EVERY verb the body carries (v29, Run 059 Opus critics 2/3: it judged
one, so `{skipped: true, grams}` wrote typed grams on a held food) — a
pick puts another food on the line, so a confirm or grams with it are the
new food's — and `skipped` together with `fdc_id`, `confirmed` or `grams`
is `422` "'skipped' cannot be combined with 'fdc_id', 'confirmed' or
'grams' — one decision per request." before anything is read. A STORED
hold is RE-READ before it is enforced (v29, Run 059 O6/S1/S6/S27): when
the stored hold refuses the body, the row is first derived from the
caches alone (the GET's reading, no request) and the DERIVED hold is
judged — a food a cache holds again takes the confirm the GET offers.
A row carried to an edited line (its line's amount edited, not yet
recomputed) is judged again on its derived row. An un-skip that gives
typed grams back is a decision again: derived like any (a row typed
before its food went comes back held, never counted unheld),
and a confirm whose own derivation finds its food gone stores the decision
held but NEVER as the ingredient's library-wide decision (Run 058 Opus
critic 2: a confirm of 0148's `food_gone` line replaced the key's decision
173468 with the gone food in every recipe); with `apply_to_all` it is the
same `422`. The app reads the same table: it offers Confirm and Confirm
as-is only where the table offers a confirm, saves typed grams on the
line's own food only where it offers typed grams, and says how a held line
finishes from the table ("picking another food keeps it held" exactly
where a pick does not finish it; "a confirm or typed grams cannot count a
food USDA no longer serves / cannot serve now" for the two no-record
holds) — pinned hold by hold against the table
(`apps/app/test/hold_actions_parity_test.dart`).

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
`starter_discard`, `coating`, `partial_pour_away`, `ambiguous_medium`, `in_shell`, whatever its food or score), a line that names a second food (counted by the
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
completed_recipes, moved, decided, gone, failed_lines, unavailable}`, which accounts
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
offer: left for its next compute), `unavailable` (since v27: FDC could not
serve the portions its weighing needs — RULE A's one outcome, Run 057 Opus
critic 1: not written, its recipe's totals recomputed over what was
written and stamped stale, so the `stale` sweep inherits the decision
there) and `failed_lines` (its recipe failed;
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
counted, less those in `decided`, `gone`, `moved`, `unavailable` and
`failed_lines`:
every written line (v23: a line on the decided food that stayed in its
bucket was counted in none, Run 053 Opus critic 3) —
`recipes` the recipes holding one, and `failed` how many recipes
failed part-way (their document would not decode — logged; what was
written before the failure stays; since v27 a target FDC cannot weigh is
`unavailable`, never `failed`; since v29 a target's totals resolve only
the decided food and its nutrient record, and only an Exception counts a
recipe `failed` — an Error (a programming fault) propagates, Run 059 S29).
The decision itself needs no FDC call when the food is in a cached search
answer and its grams need no food detail no cache holds, so it lands with no
key set or the hourly budget spent. Grams that need one — a volume or count
amount (household portions), or a weight an SR Legacy record's edible yield,
drained can or game hen scales (a bone-in chop, a drained can) — fetch it;
when FDC fails that fetch the decision is stored with RULE A's one unhappy
outcome (above: `200`, the derived fields as the last derivation left
them — a pick's grams none, the hold kept — and the row UNDERIVED, no
`derived_seq`, so the recipe reads `stale` with `stale_reason:
underived` while the stamp is current — `inputs` when the recipe's inputs
moved too, Run 059 S30; never a row stored at the printed weight); only a pick of a food neither
a cached answer nor FDC can give answers `422` with nothing written (v26,
Run 056 S29: v9-v25 answered `422`). `422`, with nothing written, when the request carries no food
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
Repeat terms are served from the same search cache the matcher uses.
Which cached answers list which food is an index (migration 016,
`fdc_search_cache_foods`, kept by triggers on every write of the cache and
backfilled from the answers already cached when the migration runs), so a
food read from "any cached answer that holds it" — a typed row's food, a
decided food's stand-in — is an indexed lookup, never a scan of every
cached answer (Run 058 O5/S10; the "400 typed rows, 3.3 s → under 0.1 s"
the v28 notes credited to this index is v26's figure for the matches GET
resolving each row's food once (above), not a measurement of
the index, Run 059 S30). The term is normalized like an ingredient
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
