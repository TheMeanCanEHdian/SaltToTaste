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

**v47 (F11):** two `subsections` of one recipe may not share a title (the
exact string; untitled ones are free) — nutrition keys a section by
`<host id>#<title>`, so a second section of the same title would read the
first's lines. Create and update refuse it → `422 validation` "Two sections
share the title "{title}" — give each its own title." (the text is the
server's own; no copy sheet covers it). The import and the library rescan
apply the same check on the way in (the editor's caps always do — a
document the editor refuses would otherwise be imported and then
uneditable): the import counts such a file failed, the rescan skips it
with `reason` "fails validation: Two sections share the title "{title}" —
give each its own title." and keeps the stored version. No corpus recipe
holds a duplicate title.

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
[{recipe: {id, slug, title}, section, position, raw, bucket, finishes, match: {fdc_id,
description, data_type, confidence, grams, gram_source, status, hold,
child} | null}], page, limit}` (`hold` as in the per-recipe matches body below).
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
Since matcher v41 a fifth flagged bucket, `choose_recipe` (label "Choose
recipe", chip order `no_match`, `no_grams`, `check`, `choose_recipe`, then
`skipped`): a reference line held `choose_recipe` or `nested_recipe`,
whatever its status (a person's nested pick, a decided row whose child is
gone) — out of the totals until a recipe is chosen or the line skipped. It
counts in `total`, `open_lines` and every flagged count (ONE list, salt_shared
`flaggedBuckets`, read by every query); a group's worst bucket ranks
`no_match`, `choose_recipe`, `check`, `no_grams`, `skipped`. Such a line is
never promised to a confirm (`finishes` 0, short in its group: salt_shared
`holdsAConfirmCannotFinish`); the `discarded_recipe` marinade stays in
`check` and a Confirm finishes it. An item's `match` is non-null on a
reference line's row too (`gram_source` `recipe`, no food) and carries
`child`, null on every other line: the SLIM child `{state, reason, name,
slug, title, section, host_title, share_text, default, why}` of the matches body (never its
`candidates` — the fix sheet fetches the recipe's matches when opened; one
library index read per page).
Since matcher v44 (sections as children, S12 (a-i)): a section's lines are
queue lines too. An item's `recipe` is the section's HOST (`{id, slug,
title}` — a section key never reaches the wire) and a new `section` key
carries the section's title (null on a recipe's own line); the queue's
three reads join the host. A section line's group credits its `finishes`
to the RECIPES it would finish: a parent routed to the section (no hold,
not skipped) with no open line of its own, whose every incomplete child is
a section whose open lines all sit in that ONE group — each such parent
once, named in `finishes_recipes`; `last_open` counts them whatever the
grams. The banner's `finishable` and `open_recipes` read the same credit:
`finishable` is the sum of the groups' `finishes`, and `open_recipes`
counts recipes — a recipe with an open line of its own, or one routed to a
section that has one — never a section. A line item's `finishes` is 0 on a
section's line (its last open line finishes a section; the grouped count
is the promise). A recipe's OWN open lines credit it only while it has no
incomplete routed child (no hold, not skipped): that child keeps it partial
whatever the group decides — the under-promise direction (the gluten-free
pizza's psyllium line finishes nothing while its flour blend is partial).
**v47 (F4, Run 061 S6 / Run 062 O4):** a line item's `finishes` reads the
same rule in the line mode: a recipe's own last open line is 0 while the
recipe has an incomplete routed child (no hold, not skipped), and
`sort=finishes` follows — ONE `pend` text (salt_database `_pendSql`) read by
both modes, so neither promises what the other will not (before, the line
mode badged that psyllium line "finishes this recipe" and its confirm left
the pizza partial). On the v46 replay library (snapshot 20, cache only) no
recipe waits on an incomplete routed child, so this moves no count there:
262 groups, the sum of `finishes` 74 = `finishable` 74, `open_recipes` 209.
Measured on the v44 replay library: 279 groups, the sum of `finishes` 72 =
`finishable` 72, no credited recipe with an incomplete child.
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
  "includes": [{"slug": "…", "title": "…", "flag": "approximation"}],
  "partial": [{"position": 5, "kind": "held", "name": "Rustic Tart Dough",
               "title": null, "matched": null, "total": null,
               "reason": "missing"}],
  "served_with": [{"position": 3, "name": "Sweet-and-Sour Chutney"}],
  "computed_at": "…",
  "computing_job_id": 7
}
```

Since matcher v41 (the composite row): `includes` names every child recipe
the totals count (a routed reference row, below, not skipped, whose child
has stored totals), in line order: `{slug, title, flag}`, `flag`
`"approximation"` when the row carries a `flag` (a default pick, a partial
child), else null — the label's "Includes {n} recipe: {title} ({flag})",
shown to members too. `partial` names every reference line that makes the
label partial, in line order: `kind` `held` (a `choose_recipe` /
`nested_recipe` hold, or the engine's `discarded_recipe` marinade not yet
decided; `reason` as `child.reason` below), `child_partial` (a counted child
whose own label is partial: `title`, `matched`, `total` its counts) or
`not_routed` (R3's 0 g rule row: `reason` `section` | `served_with` (until
v52; since, listed in `served_with`) | `no_amount` | `no_share`, v47
`self`); `name` is the reference as the line writes it.
Both are `[]` on a recipe with none and absent from the `{"status":
"none"}` body. Read from the stored rows (no request); one library index
read per request at most. Since matcher v52: `served_with` — every
reference served with the dish (a `not_routed` row whose `reason` is
`served_with`: accounted, so never in `partial`), `{position, name}` with
`name` the reference's first alternative, in line order; `[]` when none —
the label's "Served with {name} — not counted." line (below, matcher
v52).

Since matcher v44 (sections as children): an `includes` entry also carries
`section` (the section's title, null for a library recipe) and `host_title`
(another host's title only; an own section reads its bare title — "Includes
1 recipe: Tabil" — another host's "{title} (a section of {host title})");
`partial`'s `not_routed` gains `reason` `no_ingredients` (a reference to a
section with no ingredient lines). `?section=<title>` (exact title) answers
that section's own stored totals — per batch (`serving_basis` 1,
`basis_kind` `per_batch`, `calories_per_serving` the whole section: a
section has no serving basis of its own, never its host's serves nor its
yield's count), its own `includes`/`partial` (members too); an unknown or
empty title is `404 not_found` "No section with that title.". The
serving-basis PUT takes no section.

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
computed." (no `stale_reason`: the latter). **v47 (F5, Run 062 critic):** a
recipe whose totals count one of its SECTIONS (its own or another recipe's
— a routed row or a pick; not a skipped or held one) also reads `stale`
while that section is not fresh itself — edited in its host's document
(lines, yield, steps) since its last compute: `stale_reason` `inputs` (the
recipe's own stamp is current, its hash reading the section TITLES only,
but an ingredient its totals count changed); a section mid-compute or one
whose writer never finished: `interrupted`; holding a decision waiting on
USDA, or stamped waiting on USDA (an apply-to-all target FDC could not
weigh): `underived` — each section's stamp read exactly as its own page
reads it, so a parent never reads `inputs` when nothing changed (Run 059
O23; the v47 closer round 2's D1). The recipe's own `interrupted` or
`inputs` wins; otherwise a section's reason (`inputs` over `interrupted`
over `underived`), else the recipe's own `underived`. Before, the page read fresh and offered no Recompute
until a `stale` sweep (which already listed it). Recompute computes the
section first, then the recipe (the per-recipe job's children-first). A
library child (v41) is not read so: its own page goes stale and offers
Recompute, whose new stamp then stales its parents (`child_stamp`). Migration 013 stamps each existing
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
banana leaf: the cochinita pibil's wrapper, not eaten; since matcher v64
dried corn husks, the tamales' wrapper) and, since matcher
v37, a line the corpus split off the one above ("(about ¾ cup)", Hearty
Minestrone; "lengthwise, seeded, and sliced thin on bias", Bun Cha — a
line wholly in parentheses with nothing searchable, or one with no amount
opening on a cutting direction, "lengthwise" or "crosswise": the
library's only two), confirmed on no
food as "Continues the line above — counted with it" (an engine rule
row, rewritten when its rule changes), and, since matcher v37 (the class
ruling, 2026-10-04), a zero-nutrient flavouring — an EXPLICIT list of
exact items, `liquid smoke`, `red food coloring`, `green food coloring`,
`ball pickle crisp`, `angostura bitters`, `vanilla bean`, the library's
14 such lines (liquid smoke ×5, red and green food coloring, Ball Pickle
Crisp, Angostura bitters, vanilla bean ×5; FDC has no record of any, and
each sat on a wrong one: "Pectin, liquid", "Soup, bean", "Cheese ball";
since matcher v64 `gel food dye` too, the rainbow cake's)
— confirmed on no food as "Flavouring — no nutrients, counts as zero", 0
g unmeasured, basis `"flavouring, no nutrients — counted as 0 g"` (an
engine rule row). A person's row on such a line stands, and a line held
as a discarded medium stays held: "1 tablespoon liquid smoke, divided"
(Indoor Pulled Chicken) keeps its `partial_pour_away` hold. The job
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
the key's prior decision or a nutrient record failing) whose row already
carries a food (an `auto` row of an earlier compute) the row is KEPT as a
decided row is (v36, Run 060 S4: v29 overwrote it, so one flaky detail on an
`all` sweep dropped a correct match from the totals) — its food, grams and
status untouched, underived until held `food_unavailable`
(`stale_reason: underived` — a row carrying its own hold, `coating`,
`partial_pour_away` and the like, included: its derivation failed all the
same; its food or nutrient record no cache holds leaves it out of the
totals as a decided row's does), and the held write keeps its food (the
reviewer sees what it was) while `food_unavailable` replaces the line's
own hold until the line derives again, which re-derives that hold; only
a line with NO row carrying a food (a first compute, or its own unmatched
row) gets a row of its own — `unmatched`, no food,
`description` "FoodData Central could not serve this food" — underived
until held. Either way FDC serving the food again derives the line anew
(one request; the `all` scope's once-per-sweep re-ask below for a held one).
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

**Matcher v44, sections as children** (the owner's 2026-10-06 rulings S1–S15
on prep43/design_v2.md, all as recommended — S12 (a-i), S14 (a), S15 (a);
the approved copy delta `docs/mockups/v44-sections-copy.html`; migration
019). A recipe's titled subsection is a recipe of its own when a main
reference line needs it: its own lines, matches, totals and layout,
computed before the recipes that read it, and a reference line routes to
it as v41 routes to a library recipe. Storage keys it `<host id>#<exact
title>` (a `#` never occurs in an id) in the same three tables, their
`recipe_id` FK moved to a generated `host_id` (deleting the host deletes its
sections' rows; v47 F9, migration 020 — user_version 20: `host_id` indexed
in each table, `idx_matches_host` / `idx_nutrition_host` /
`idx_layout_host`, so the cascade and a host save's dead-section drop
SEARCH instead of scanning: 1,198 drops 1,074 → 8 ms, a 50-recipe cascade
207 → 16 ms on snapshot 20); the KEY never reaches the wire — a section is always its
host's `slug` plus its `section` title. Superseding v41's text below: a
section candidate is pickable and carries its totals; `other_section` lists
child sections only.

- **Which sections are children** (S2 (a), referenced only): a section a
  main reference line resolves to, one a "(recipes follow)" line lists (rule
  PO, below), or one an unmarked line names (A9) — 140 on snapshot 19
  (936 lines). A prose section (no ingredient lines) is never one. The bulk
  order is [child sections, recipes that read none, parents]; a section
  edit stales its key and every parent routed to it (v47 F5: the parent's
  own page too, at once — the nutrition GET, below); a sweep collects a key
  no main line needs any more (its stamp and engine rows — never a row a
  person decided). **v47 (F1):** a PERSON's pick keeps a section alive —
  every section a decided row routes to (`overridden` or `confirmed` with a
  section child) is a child too, whatever the engine routes now (a second
  host taking the title, N8; the routing line edited away): never
  collected, ordered and selected by the sweeps, computed first by the
  per-recipe job — before, the GC deleted its stamp, the parent stayed
  stale for good and its re-pick was refused. A stamp an admin's
  `?section=` PUT writes on a section no line routes to is collected by the
  next sweep unless a person picks that section meanwhile. A key whose host
  no longer carries the title (S15) is never revived by a pick. Migration
  020 indexes each table's `host_id` (the cascade and a host save's
  dead-section drop search, never scan).
- **Resolution** (v41's order; v44 changes): ONE own section whose title the
  item names routes to it (chraime's "1 tablespoon tabil (recipe follows)"
  → its Tabil, share ⅛ of "MAKES ABOUT ½ CUP"); another recipe's section
  routes only when exactly ONE other host carries the title under the
  resolver's normalised key (else held, listed: N8); the share reads the
  SECTION's own yield; a section whose lines hold a reference is
  `nested_recipe` (depth 1); a section with no ingredient lines is the 0 g
  rule row, `child.reason` **`no_ingredients`** (lemon-meringue-pie's
  "Single-Crust Pie Dough for Custard Pies"). A9: an UNMARKED line whose
  item is an own section's title (red-lentil-kibbeh's harissa) is a
  reference too; S11: such a line's bare count of exactly 1 reads one
  recipe. A section's rules read the SECTION's own steps (most store none).
  **v47:** (F6) of several own sections the looser title forms reach, the
  ONE whose title equals the item routes ("2 tablespoons harissa" is
  "Harissa", never held beside a "Harissa Yogurt"; no corpus line has two);
  (F7) a SECTION's line naming its own HOST ("1 recipe Yeasted Doughnuts
  (this page)" in its Boston Cream Doughnuts — seven corpus lines, all in
  sections no main line routes to) is the 0 g rule row with no child,
  `child.state` `not_routed`, **`reason` `self`** (new wire value; the
  app's reason maps show unknown values through their generic arm): the
  variation is made ON its host, so a host line routed to that section
  (held `nested_recipe`) and the section's line never stamp each other in a
  cycle; (F2) a prose section is a resolver input the parent's stale hash
  carries: the hash folds the keys of the prose sections its reference
  lines resolve to (only when there is one — lemon-meringue-pie and
  fresh-plum-ginger-pie on the corpus; every other recipe hashes as before,
  so a deploy stales exactly those two once), so a prose section given
  lines stales its parent at once (the page offers Recompute) and ONE stale
  sweep routes it, and a section whose lines are taken away sends its
  parent back to the `no_ingredients` rule row in one sweep.
- **Rule PO** (S8 (a)): a "(recipes follow)" line held `choose_recipe`
  generic or `discarded_recipe` lists, as `own_section` candidates, the
  recipe's sections WITH lines that no other reference line of the recipe
  routes to, in document order (glazed-spiral-sliced-ham's "1 recipe glaze"
  → Maple-Orange Glaze, Cherry-Port Glaze). Listed for a person; the engine
  never routes them.
- **`child`** (full and slim, and the queue's): + `section` (the title, read
  from the stored key — a section gone since still names its OLD title, for
  the held-missing note "{old title} is no longer a section of {host title}
  — choose again") and `host_title` (the host's title only when the host is
  ANOTHER recipe; null for an own section and for a library child). A
  section child's `slug` is its host's, `title` the section's, `yield_text`/
  `yield_units`/`status`/`matched_count`/`total_count` the section's own.
- **`candidates`**: every entry + `section` (null on a library recipe) and
  `state` (null on a library recipe). A section entry: `slug` its host's,
  `title` = `section` its title, `yield_text` its yield, `kcal` its stored
  batch energy, `kcal_per_serving` the line's share of it ÷ the parent's
  basis, `current` (the row is routed to it), `host_title` (another host
  only), `state` `ready` (stored totals) | `no_totals` (a child section not
  computed yet — until its sweep) | `no_ingredients` (a prose section) |
  `nested` (it holds a reference; a pick is stored held), and `pickable` =
  lines and stored totals. **v47 (F8):** on a SECTION's own line
  (`?section=`) no candidate is `pickable` (one level is read: the PUT
  refuses every pick there, "Only one level is read — …"), and no
  candidate names the section's own host in `host_title`.
  `other_section` lists only sections that are stored children (S14 (a);
  N4: read as "a section key with a `recipe_nutrition` row", one statement
  per request — a variation nobody
  routes is never offered: broccoli-cheese-soup's "Buttery Croutons" lists
  Carrot-Ginger Soup's, not Sweet Potato Soup's "Buttery Rye Croutons").
- **`?section=<title>`** (exact title) on this GET lists that section's own
  lines (any authenticated user, members too); an unknown or empty title is
  `404 not_found` "No section with that title.".
- **Reach** (S9 (a)): a section pick is line-local — a section child
  reaches nothing and a row routed to a section is never reached, so
  `others` / `others_lines` are 0 on a section row and no apply offer shows.
- **Identity across a retitle** (S15 (a), a one-way consequence of the key):
  a host saved with a section retitled or removed drops that key's rows,
  stamp and layout; every person's pick of it (stored on the parent) then
  holds `choose_recipe` missing, naming the old title, and every decision
  inside the section is gone. A v41 library child keeps its id across a
  retitle; a section cannot.
- **The 16 defect queries as rules** (S6 (a), zero requests): a salt line
  "for <purpose>" with no amount is the seasoning row (it also moves three
  MAIN rows, 0 g → 0 g: hand-rolled-meat-ravioli|16, orecchiette-with-
  broccoli-rabe-and-sausage-2|5, gado-gado|12); the typo "back pepper" reads
  black pepper; "warm tap water" is water; a lone "boneless" item is read on
  with its prep ("boneless skinless chicken breasts" → 2646170); a leaked
  "fluid ounce(s)" unit is dropped from the item (orange juice → 169098;
  orange liqueur → liqueur; peach schnapps → kirsch / liqueur, flagged
  2710623; sparkling wine → the champagne stand-in 2710689, flagged; the
  champagne line keeps its key); a SECTION line naming the parent's own
  reserved part with no amount ("reserved turkey giblets", "… drippings
  from …") is a 0 g rule row, note "Reserved from the main recipe — no
  amount on the line, counts as zero"; "reserved <X>" with an amount where
  the host's own ingredient group is <X> (the short ribs' spice rub) is a
  0 g rule row, note "Reserved from the main recipe — counted in the main
  recipe’s spice rub", basis "counted in the main recipe’s spice rub —
  counted as 0 g"; "green thai" reads the shipped 'thai' rank-as. S7 (a): ≤ 1
  tablespoon of zest "plus" a bare COUNT of the same fruit counts the fruit
  by FDC's portion and drops the zest ("½ teaspoon grated orange zest plus 5
  oranges" → 746771, 655 g, "5 × 131 g each · the fruit only (the zest is
  dropped)").
- **The 23 reads** (S5 (a), zero requests; each onto an answer already
  cached): rewrites — loaf country bread with thick crust (→ Italian bread
  174913), slices sandwich bread, ground celery seeds, jasmine or
  long-grain white rice, cilantro stems, espresso powder or instant coffee,
  navel oranges, sesame oil (→ toasted), ground fennel seeds, rubbed sage
  (→ sage, flagged 170935), peanut butter (→ creamy);
  rank-as — shiitake, jalapenos, tawny port and port (→ the ruby-port
  stand-in, flagged), salt-cured black olives (flagged), pods star anise
  (flagged), lemon grass, vegan mayonnaise, pepitas, raw sunflower seeds,
  toasted sesame seeds, white or cremini mushrooms; piece weights 'lemon
  grass' 10 g and 'pod star anise' 0.5 g.
- **Replay** (rp43 on a fresh copy of snapshot 19, cache-only): 63 main rows
  differ from v43's replay — 57 reference rule rows routed to a section, 3
  A9 food rows routed to their own section, the 3 salt rows above; every
  other main row byte-equal; main buckets counted 13,336 / check 214 /
  no_grams 17 / no_match 13 / choose_recipe 35 (A9: counted +2, check −1,
  no_match −1); recipes complete 935 → 976, partial 263 → 222 (41 move, 40
  of them among the 51 partial with nothing to review — 51 → 12); +76,418.6
  kcal per batch on main rows (+74,198.1 into complete sections, +2,220.4
  into five partial ones, flagged). Sections: 140 computed, 121 complete,
  19 partial; 13 of them wait on option A below (17 lines, 0 g, "FoodData
  Central could not serve this food").
- **Option A — to be spent by the owner** (S2 (a), never by the build: the
  replay's only calls, each unanswered until then): searches "unsweetened
  plain coconut milk yogurt", "mascarpone cheese", "potato starch" (ask
  first), "brown rice flour" (only if potato starch lands), "dairy-free sour
  cream", "coca-cola", "pineapple juice", "tangerines", "nutritional yeast",
  "frozen cranberries", "frozen cherries", "frozen pineapple chunks"; and
  the four read details no snapshot holds (2710205 vegan mayonnaise,
  2515380 pepitas, 2515381 raw sunflower seeds, 170151 toasted sesame
  seeds). Each answer is enabled only after its check (prep43/p2_spend.md
  §4).
  **SPENT 2026-10-06** by the owner on a scratch copy of snapshot 19 (the
  result snapshot 20): 11 searches + 9 details, 20 of the 22 approved —
  "brown rice flour" (A4) WITHHELD because potato starch (A3) failed its
  check, and the two records the ranker put on top that the checks reject
  (171884, 173444) never fetched. Outcomes (matcher v45, part 1): LANDED as
  they are — A7 "1 cup pineapple juice" on 2709329 "Pineapple juice, 100%"
  (248 g), A8 "4 tangerines … (about 1 cup)" on 2709175 "Tangerine, raw"
  (the cup, 195 g), A11 "10 ounces frozen cherries" on 2709233 "Cherries,
  frozen" (283.50 g), the two vegan mayonnaise reads on 2710205 (112.50 g,
  56.25 g). A RULE (rank-as: the line's OWN cached answer under the words of
  the record its check names) — A6 `coca-cola` → `soft drink cola`
  (2710541 "Soft drink, cola", 0.990, its fl-oz portions: 1 cup 248 g; not
  the Minute Maid lemonade the brand word leads); A5 `dairy-free sour
  cream` → `sour cream imitation` (2705617 "Sour cream, imitation", 0.990,
  `1 cup` 240 g: ¼ cup 60 g, FLAGGED "· approximation (counted as Sour
  cream, imitation)"; not the dairy fat-free 173444); A1 `unsweetened plain
  coconut milk yogurt` → `yogurt coconut milk` (2707569 "Yogurt, coconut
  milk", 0.990, weighed by its own `1 cup` 226 g: 2 tablespoons 28.25 g —
  the dairy 'yogurt' density 1.03 no longer applies to a coconut-milk
  yogurt; not the dairy 2259793 it sat on at 0.66). GRAMS for the three
  named seed reads (their details publish no volume portion): the volume
  siblings above (2515380 → 169415, 2515381 → 170154, 170151 → 2707586).
  FAILED their checks, pending the owner's part-2 rulings and unchanged —
  A2 mascarpone (no mascarpone record answered; the line stays on 2705720
  "Cheese, Monterey" at 0.465, below the gate), A3 potato starch (only
  gluten-free breads answered; 174099 at 0.256), A4 (withheld; its line
  still blocked), A9 nutritional yeast (2710005 "Yeast", baker's, counted
  at 0.565), A10 frozen cranberries (only juice concentrates answered;
  173653 at 0.000), A12 frozen pineapple chunks (only the sweetened record
  answered; 169946 at 0.890). Replay (rp43 on a fresh copy of snapshot 20,
  cache-only; --reverse-parents byte-identical): one call (the withheld
  search), staleAfter 0; exactly 6 section rows and 2 main rows differ from
  the pre-change replay on the same snapshot — the six lines above and the
  two parents routed to a section whose totals moved (buffalo cauliflower
  bites' Ranch Dressing, 289.55 → 296.32 kcal; the vegan Baja tacos'
  Vegan Cilantro Sauce, 131.19 → 255.99 kcal, now complete); main buckets
  and holds unchanged; sections complete 126 → 131 of 140 (Coca-Cola
  Glaze, Vegan Cilantro Sauce, the pepita relish, both broccoli toppings);
  recipes complete 977 → 978; the partial recipes with nothing to review
  11 → 10; +131.6 kcal per batch on main rows, +591.8 on section rows. With
  the skin step's four details (snapshot 19) the accuracy track's live
  requests total 84 (60 above + 4 + these 20).
  **SETTLED 2026-10-07** — the owner's part-2 rulings on the six failed
  answers ("go with your recommendations"; matcher v46, zero requests,
  each a stand-in or a same-food read of an answer already cached): A2
  `mascarpone cheese` and `mascarpone` → rank-as the cached `heavy cream`
  answer under `cream heavy` (Foundation 2346386 "Cream, heavy", 1.000 —
  FDC has no mascarpone; as crème fraîche), FLAGGED "· approximation
  (counted as Cream, heavy)", by the printed weights: the roulade's
  Espresso-Mascarpone Cream 467.77 g, tiramisu 680.39 g, the summer fruit
  tart 170.10 g; A3 `potato starch` → rank-as `cornstarch` (169698
  "Cornstarch", 1.000), FLAGGED, 198.45 g; A4 `brown rice flour` (never
  asked) → rank-as `white rice flour` under its own words (790214 "Flour,
  rice, white, unenriched", 1.000 — under the record's words it ties SR
  169714), FLAGGED, 212.62 g; A9 nutritional yeast stays on 2710005
  "Yeast" (0.565, counted, 12.00 g), now FLAGGED "· approximation (counted
  as Yeast)"; A10 `frozen cranberries` → REWRITE `cranberries` (171722
  "Cranberries, raw", 0.920 — every main cranberry line's record), 170.10
  g, unflagged; A12 `frozen pineapple chunks` → REWRITE `pineapple`
  (2346398 "Pineapple, raw", 0.970, every main pineapple line's record —
  not a rank-as under "pineapple raw", where FNDDS 2709260 ties it and is
  listed first), 283.50 g, unflagged. Replay (rp43 on a fresh copy of
  snapshot 20, cache-only; --reverse-parents byte-identical): NO call,
  pending 0, staleAfter 0, sectionsStale 0; exactly 6 section rows (the six
  lines) and 5 main rows differ from v45's — tiramisu's and the tart's
  mascarpone and the three parents routed to a section whose totals moved
  (the roulade's Espresso-Mascarpone Cream, 601.15 → 2,207.04 kcal; the
  gluten-free pizza's and the gluten-free cookies' flour blend at 16/42 and
  8/42, 1,075.82 → 1,654.64 and 537.91 → 827.32 kcal) — each loses its
  "partial" flag; main buckets counted 13,338 / check 214 / no_grams 17 /
  no_match 11 / choose_recipe 35; sections complete 131 → 134 of 140 (the
  gluten-free flour blend, Espresso-Mascarpone Cream, the pavlova's
  Orange, Cranberry, and Mint Topping); recipes complete 978 → 980 (the
  roulade, the summer fruit tart); the partial recipes with nothing to
  review 10 → 9; +5,393.9 kcal per batch on main rows, +3,130.1 on
  section rows.

**Matcher v41, the composite row** (the owner's 2026-10-05 rulings A1–A10,
"go with your recommendations"; design_v3, the approved mockup
`docs/mockups/v41-composite-rows.html`; migration 018). Still one row per
line; every `match` gains three keys, emitted on every row:

- `child` — null unless the line is a sub-recipe reference the engine reads
  as one and its row stands on no food. `{state, reason, name, slug, title,
  share_text, default, why, yield_text, share, yield_units, grams, kcal,
  kcal_per_serving, status, matched_count, total_count, kind, parent_kind,
  candidates}`: `state` `routed` (counted from a library recipe) | `held`
  (`reason` `missing` — no library recipe or section has the title, or a
  decided row's child was deleted — | `generic` — the line names no single
  recipe — | `nested` — the child is itself made from a recipe, depth 1 —
  | `marinade`) | `not_routed` (the shipped 0 g rule row: `reason`
  `section` | `served_with` | `no_amount` | `no_share`, since v44
  `no_ingredients`, since v47 `self` — a section's line naming its own
  host, below); `name` the
  reference as the line writes it ("Rustic Tart Dough"); `slug`/`title`/
  `yield_text` the child's (the no-share child's too); `share` the share of
  the child the line counts, `share_text` its copy ("1", "⅔", "1½", else
  two places); `yield_units` the units a share may be typed in (`[{unit:
  "recipe", per_recipe: 1}]`, plus the child's MAKES measure, e.g. `{unit:
  "cup", per_recipe: 1.5}`); `kcal` the child's batch energy × the share
  (routed only), `kcal_per_serving` that ÷ the parent's serving basis;
  `status`/`matched_count`/`total_count` the child's own label; `default`
  true on the engine's route to the first of two or more titles the
  parent's note names, `why` `default` there, else `none` (an exact or
  note-named route has no why line); `kind` the item's last word
  ("dough"), `parent_kind` the parent title's last word when it is pie,
  tart or quiche, else `recipe`. `candidates` (the fix sheet's groups, in
  the resolution order): `{group, slug, title, note, yield_text, kcal,
  kcal_per_serving, current, default, pickable, host_title}`, `group`
  `own_section` | `note_named` (`note` "named first" / "named second" / …)
  | `library` (the title equal to the item) | `similar` (library titles
  holding every word of the item, fewest extra words first, at most 5;
  `note` "not named in the note" when the note names titles) |
  `other_section` (other recipes' sections holding every word, at most 5;
  `note` "a section of {host title}"); sections are phase 2 — `pickable`
  false, `kcal` null (v41; since v44 a section candidate carries its totals,
  `state` and `pickable`, and `other_section` lists child sections only —
  above); a library candidate is `pickable` when it has stored
  totals (`kcal` = its batch energy, `kcal_per_serving` × the line's share
  of it ÷ the basis). An empty group is omitted (the app draws its empty
  text). The library's title and section index is read at most once per
  request.
- `parts` — a rendered row's two records (R2), `[{fdc_id, description,
  data_type, grams, role}]`, `role` `cooked` then `kept_fat`; since matcher
  v49 a zest-over-a-tablespoon-plus-juice row's (`zest`, `juice`) and a
  half-drained can row's (`drained`, `undrained`), the role as stored; `[]`
  on every other row. (The app's two-record line reads "cooked and drained"
  and "kept in the pan" only on the bacon, `role` `kept_fat`; the new roles
  read "matched to two records:" with the two records — their own copy is a
  later mockup.)
- `flag` — the composite row's flag on its own line, null elsewhere (the
  older flags stay `gram_basis` suffixes): "approximation (the first {kind}
  the note names: {title})" on an engine default (a person's Confirm or pick
  clears it), "approximation ({title} is partial: {m} of {n} lines)" on a
  counted partial child, "approximate (USDA AH-102 item 1981: bacon,
  sliced, all methods → cooked 33 % (18–43))" on a rendered row (since
  matcher v51; "approximate (rendered and drained; yield from FDC protein)"
  before — rule B1's bacon alone, v49's two-part rows carry no flag), and
  since matcher v54 (Q25) "approximate (USDA retention: alcohol cooked {N}
  min keeps {f} %)" and its forms on an alcohol row whose cooking keeps
  less than all its ethanol (below, "alcohol cooked off") — the last three
  name a fact and stay on a Confirm (A6); several join with " · ".

New `gram_source` `recipe` (a reference row: no `fdc_id`, no
`description`); new holds `choose_recipe`, `nested_recipe` (bucket
`choose_recipe`, below) and `discarded_recipe` (bucket `check`; a Confirm
is poured away, counted) — LINE holds (A2), each a queue group of one,
never reached by a key decision or an apply-to-all. A routed row's
`gram_basis` is "from the recipe {title}: {g} g, {kcal} kcal"; a held one
keeps "a sub-recipe — counted as 0 g"; a rendered row "{raw} g raw →
{cooked} g cooked bacon + {fat} g bacon grease kept in the pan" (since
matcher v51 ", sharing the {N} kept with the oil" when an oil shares the
pan). On a
routed row `others` / `others_lines` count the RECIPE reach: the key's
undecided routed rows (`auto`, `gram_source` `recipe`, a child, no hold) on
another child, or on the same child by a flagged default — an unflagged
row on the same child waits on nothing — whose line's share of the child
reads; on a held or not-routed reference line, 0. The food reach never
takes a reference row and the recipe reach never a food row (S18: the real
"barbecue sauce" key holds brisket's food line and two held references).

The rules (replay of snapshot 17, cache-only, 0 requests): **R1** —
sub-recipe routing, phase 1: a reference line resolves (first hit wins) no
amount → a marinade → ONE own section → the first library title the
parent's note names ("(this page)"; flagged when it names two or more) →
the library title equal to the item (unless the parent is made FOR it:
"… for Pan-Seared Steaks" is served with it, D7) → another recipe's
section → held; first " or " alternative only (D11); self never; a child
holding a reference row is `nested_recipe`; the share is a written "(½
recipe", else "N recipe", else the line's amount over the child's MAKES
measure in one unit family (a range's upper bound), else none (the 0 g
rule row, `no_share`). A routed row counts the child's stored batch totals
× the share (its grams live: the child's total grams × the share),
accounted only while the child is complete; a child recomputed, rebased or
deleted turns its parents stale (`child_stamp`, `stale_reason` `underived`)
and a sweep recomputes them parents last. 13 lines route in 13 parents
(the four double-crust pies flagged on their note's first dough; peach
tarte tatin unflagged, D2), +25,702.4 kcal per batch. **R2** — rule B1,
rendered bacon: a row on SR 168277 (`auto` or `confirmed`, grams > 0, not
"divided", never typed grams) whose recipe has ONE step that both moves
the bacon out and pours the fat down to N counts cooked SR 168322 at the
raw weight × 0.403 plus the kept fat on SR 172345, min(N × the unit's mL ×
0.8724 g/mL, raw × 0.2299) — since matcher v51 (M49) × 0.33 (USDA AH-102
item 1981) and raw × 0.2555, the kept N shared with an oil browned in the
same pan (below); the row keeps 168277 (a Confirm decides it
library-wide; each carried line re-runs B1 on its own steps); a person's
single-food pick or typed grams clear the parts (D12). 13 lines,
−891.0 kcal per batch. **R3** — every reference line not routed makes its
label partial (A3 a: the 68 rule rows leave the totals' accounted and
contributing counts, bucket `counted`): 87 recipes leave `complete` (1,022
→ 935). The owner's rulings: A1 (b) a recipe decision is never written to
`ingredient_decisions` — it travels only by an explicit apply-to-all, the
targets written `overridden`; A5 (a) the three reference marinades held
`discarded_recipe` (Skip / Confirm poured away / Choose a recipe); A7 (a)
the three un-noted single-crust lines held `choose_recipe` (R1 = 13, not
plan.md's 16); A8 (a) buffalo-wings|13 held `choose_recipe` (missing); A9
(a) the three unmarked own-section references unchanged; A10 (a) a food
pick accepted on a reference line whose top-level " or " alternative
carries an amount, weighed there and keyed on the row's own item key.
Deviations from the approved plan (decision log): A7's three lines held,
A8's line held, the marinade hold code `discarded_recipe` (Q7's
`discarded_medium` meaning kept), the counts 13 routes / 87 leave
complete (plan.md: 16 / "about 60"), A10's narrowed S14. No live request
(the accuracy track's live requests stay 55).

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
record's loose `tsp` 1.0 g; since matcher v37 (the queue sweep, Z5/Z6/Z11/
Z15) eight figures for a record that publishes NO volume figure of its own
(never over one: "¾ cup dried red lentils" keeps 174284's cup), each
labelled with its source — ATK's printed pairs: frozen pearl onions 113.4
g a cup ("8 ounces (about 2 cups) frozen pearl onions"; `"1 1/2 cup ≈ 355
mL · approximate (ATK: 8 ounces frozen pearl onions ≈ 2 cups)"`), lentils
7 ounces a cup ("1 cup (7 ounces) lentils"), strawberries 5 ounces a cup
("8 cups (40 ounces) strawberries"; the plural only, so "strawberry jam"
keeps 'jam'), grape tomatoes 0.575 g/mL ("12 ounces cherry or grape
tomatoes (about 2½ cups)"; "1 pint grape tomatoes" is 272.16 g), and,
flagged as approximate by nature, cooked poultry 6 ounces a cup ("6 ounces
cooked chicken, torn into 1-inch pieces (1 cup)", keyed on Turkey
Tetrazzini's one line, 680.39 g) and shredded Granny Smith 8 ounces a cup
("1½ pounds Granny Smith apples, peeled, cored, and shredded (3 cups)", a
purchase weight); FDC's figures on stand-in records: jarred roasted red
peppers on 168559 "Pimento, canned" `cup` 192 g (item-keyed; the record
2258590 carries fresh peppers too: `"… · approximate (pimento density,
FDC 168559 cup 192 g)"`) and crushed tomatoes on 170054 "Tomato products,
canned, sauce" `cup` 245 g (`"… · approximate (tomato sauce density, FDC
170054 cup 245 g)"`) — and crème fraîche at heavy cream's 1.01 g/mL on
2346386 "Cream, heavy" (flagged below; `"1/4 cup ≈ 59 mL · approximate
(heavy cream density) · approximation (counted as Cream, heavy)"`, 59.74
g); since matcher v23 a line that says
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
tablespoon)"`; since matcher v37 galangal by the same figure, ATK's own
substitute ("If galangal is unavailable, substitute fresh ginger", Guay
Tiew Tom Yum Goong), on the ginger-root record it ranks as (flagged
below): `"1 piece × 2 inch × 8 g per inch · approximate (ginger's figure
(ATK's substitute for galangal)) · approximation (counted as Ginger root,
raw)"`, 16 g; whole spices by a reference figure — a peppercorn 0.05 g,
a whole clove 0.1, an allspice berry 0.1, a cardamom pod 0.2, a coriander
seed 0.01, a star anise pod 0.5 (a flagged figure prints its decimals —
a sub-gram one all of them, flagged or not since matcher v63 (the bay
leaf's `"1 × 0.2 g each"`), `"15 × 0.05 g each · approximate (reference
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
Eggs Piperade); since matcher v37 (the queue sweep) a sugar cube 2.2 g
(ATK's own cubes in Champagne Cocktail, "¾ cup sugar" makes 64, on
746784's cup 188 g), a large sea scallop 34.0 g (the owner's pick of the
three figures the corpus prints: "1½ pounds large sea scallops (16 to 24
scallops)"; `"24 × 34 g each · approximate (ATK: 1½ pounds large sea
scallops ≈ 16 to 24)"`) and a gyoza wrapper 8 g (172802's own 3½-inch
square wonton wrapper, ATK's named substitute: `"24 round × 8.0 g each ·
approximate (FDC's 3½-inch square wonton wrapper, ATK's substitute)"`),
each flagged; a baguette by the length the line prints at 14.73 g an inch
(2707610's own `1 baguette (about 22" long)` 324 g; a piece count only:
`"1 piece × 3 inch × 14.73 g per inch · approximate (FDC: 1 baguette
(about 22" long) = 324 g)"`); a zest strip the corpus left in the item
("3 (2-inch) strips orange zest", no unit) is a strip count all the same;
an envelope of yeast is ATK's printed 2¼ teaspoons ("1 envelope (2¼
teaspoons) instant or rapid-rise yeast"), weighed at the yeast density:
`"1 envelope ≈ 2.25 teaspoon (ATK: 1 envelope = 2¼ teaspoons) · 2.25
teaspoon ≈ 11 mL"` (7.10 g). Not built (ruled no grams): dried jujubes and the mild
dried chile by the inch; an ancho keeps FDC's 17 g)
| `override` | `discarded` (a cooking medium the recipe throws away —
since matcher v50 also a solid a strain or a discard throws away and the
kept part of a printed partial use, the v50 paragraph below —
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
`ambiguous_medium`). Since matcher v53 (M52) a frying oil also counts
what its fried food absorbs, on top of its kept part, and an oil heated
for a coated food browned in it is a frying oil (the v53 paragraph below). Since matcher v31 a same-food "plus" part the steps
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
table salt (1.22) or 26.8 g of kosher (0.60865 since v63; 31.7 g at 0.72 before); a buttermilk soak's or a cheese
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
refuse portion and no class yield (below): counted at the printed weight,
bone included, and labelled (since matcher v30 "beef rib slabs" too) —
since matcher v39 only the either-bone steaks (173403: the line allows
boneless) and the ham hocks (2705900: FDC has no figure), the CP6 rulings
#11 and #5 (meats, birds and turkeys at gross weight) being REVISED by the
owner's 2026-10-05 ruling: a bone-in line weighed from a printed weight on
a record of a class FDC gives a yield for reads it, `"… × 0.61 edible ·
approximate (yield of chicken parts from FDC 171447)"` (the class table
under matcher v39, below; the record's own refuse portion and the whole
chicken's ready-to-cook yield go first) — since matcher v43 a bone-in
chicken or turkey PART reads the USDA Agriculture Handbook 102 figure of
the part the line names, the record deciding meat or meat and skin, in one
step (`"… × 0.70 edible · approximate (USDA AH-102 item 586: chicken thigh,
raw → meat and skin 70 % (63–81))"`; the AH-102 poultry table below; the
v39–v42 second step `"… × 0.79 meat · approximate (skin discarded; USDA
meat-only share)"` is retired);
shellfish
bought in the shell too (held `in_shell`, below, and counted so once a
person confirms it); since matcher v39 `"2 × 200 g · approximate (FDC's
1-lobster portion)"` for live lobsters, counted by the record's own "1
lobster" rather than the live weight; the label is
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
"2 tablespoons beaten egg" is 30.38 g);
since matcher v37 Foundation "Olives, green, Manzanilla, stuffed with
pimiento" (332791) reads FNDDS "Olives, green" (2710089, `1 cup` 135 g:
"½ cup pimento-stuffed green olives" is 67.5 g) and Foundation "Peppers,
jalapeno, seeded, raw" (2747661) FNDDS "Peppers, jalapenos" (2710096, `1
cup` 150 g), both details cached; since matcher v38, the owner's live
step's details read, Foundation "Radicchio" (2747664) reads SR "Radicchio,
raw" (168564, `cup, shredded` 40 g), Foundation "Cauliflower" (2685573)
SR "Cauliflower, raw" (169986, `cup chopped (1/2" pieces)` 107 g:
"2 cups (1-inch) cauliflower florets" is 214 g) and the sodium-added
canned chickpeas (2644288) SR "Chickpeas …, canned, drained, rinsed in
tap water" (173801, `cup drained, rinsed` 152 g); raw cashews stay dry —
SR 170162 publishes an ounce only; since matcher v45, option A's seed
details read, Foundation "Seeds, pumpkin seeds (pepitas), raw" (2515380)
reads SR "Seeds, pumpkin and squash seed kernels, roasted, with salt
added" (169415, `cup` 118 g: "¼ cup pepitas, toasted" is 29.50 g),
Foundation "Seeds, sunflower seed, kernel, raw" (2515381) SR "Seeds,
sunflower seed kernels, toasted, without salt" (170154, `cup` 134 g: "2
tablespoons raw sunflower seeds, toasted" is 16.75 g) and SR "Seeds, sesame
seeds, whole, roasted and toasted" (170151, an ounce only) FNDDS "Sesame
seeds" (2707586, `1 cup` 128 g: "2 tablespoons toasted sesame seeds" is
16.00 g) — the cups the library's main seed lines already read) (the food
stays the
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
butt roast", "1 15-ounce can chickpeas"; a "(1-liter)" paren is 1,000 mL;
since matcher v37 ONE item's weight printed in a comma clause — "1 whole
side salmon fillet, about 3½ pounds, white belly fat trimmed" is 1,587.57
g, "1 center-cut beef tenderloin roast, 3 pounds trimmed weight, …" is
1,360.78 g: the corpus's only two), `"(about 8 fillets) · 8 · USDA
per-item weight"` (since matcher v37) for a volume line nothing else
sizes, by its own "(about N noun)" count of the item ("4 teaspoons minced
anchovy fillets (about 8 fillets)", on 2706232's `1 anchovy` 4 g: 32 g —
the corpus's only such line), `"… · nutrients of \"Cabbage, chinese
(pe-tsai), raw\""` for a line on a record that publishes no energy whose
totals read a sibling record's nutrients (Foundation napa cabbage, 2727583,
reads SR 169979; since matcher v49 also Foundation 2758998 spaghetti → SR
169736 and the cooked-state FNDDS leeks 2709935 → SR 169246 and rhubarb
2709268 → SR 167758; the food and grams stay the line's, and it is not held
`no_nutrients`; hand-entered grams say so too: `"entered by hand · nutrients
of \"Cabbage, chinese (pe-tsai), raw\""`),
`"pinch ≈ 1/16 tsp (USDA tsp portion)"` for a pinch or dash on a record with
no dash portion (a teaspoon ÷ 16; since matcher v37 a record with no
teaspoon portion reads its tablespoon's, `"dash ≈ 1/16 tsp (USDA tbsp
portion)"` — "Dash of hot sauce" is 0.33 g — and "1 small pinch saffron"
is one pinch, 0.04 g), `"2 tablespoon ≈ 30 mL · juice only (the
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
is not counted as meat; a LINE hold, like `second_food`; since matcher v39
— the owner's ruling 2026-10-05, plan Q3 (b) — a line whose grams need no
shell yield is counted instead: a per-item read, FNDDS's "1 mussel" and "1
oyster" 15 g being the meat (paella's "1 dozen mussels" 180 g, the roasted
oysters' 24, 360 g) and a live lobster's count × the record's own "1
lobster" 200 g, flagged (`flambeed-pan-roasted-lobster` and the indoor
clambake's two lobsters, 400 g each), and shrimp the recipe's prep note
says are "eaten shell and all" (crispy salt-and-pepper shrimp, 680 g at
the gross weight, flagged); since matcher v40 (the live step, 2026-10-05)
the 6 clam lines bought by weight are counted too: they rank as SR 174214
"Mollusks, clam, mixed species, raw", whose detail publishes "lb (with
shell), yield after shell removed" 68 g, read ONLY in that shape (68 /
453.59 = 0.15 of the weight bought), unflagged — `"from 7 pound × 0.15
edible (USDA yield after shell removed)"`, New England clam chowder's 7
pounds 3,175.14 → 476 g; a line whose grams carry that yield is no longer
held; the 7 others bought by weight stay held — 5 mussel (SR 174216
"Mollusks, mussel, blue, raw" publishes only small 10 g, medium 16 g,
large 20 g, oz, 3 oz and cup 150 g: no with-shell portion) and 2 shell-on
shrimp whose shells are peeled off (no request was planned) — and the
peeled-and-deveined shrimp lines stay counted; since matcher v49 (M47 Q11)
those 7 are counted too, at their AH-102 shell rows (shrimp item 2333 ×
0.81 on 175179; mussels moved to 174216, item 1531 × 0.29, the liquor not
counted — the v49 paragraph below), so no corpus line stays held
`in_shell`; the hold remains for a shell weight no row covers, e.g.
oysters bought by weight),
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
(deep) frying"). Four such standing holds have no excess sentence — 0288
Maryland crab cakes' flour ("Lightly dredge"), 0149 Easier Fried Chicken's
2 cups, 0525 Orange-Flavored Chicken's cornstarch, 0042 Almond-Crusted
Chicken's panko — and stay held by the frying ruling (the owner's
decision, 2026-10-03: no change). v33 moved 25
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
that the crumbs adhere"). Since matcher v34 (the owner's
ruling, 2026-10-03, "the narrow version") the coat's OTHER LAYERS are held
with it: a nut, cheese, cracker, chip, cornflake or Melba toast line — a
quarter cup or more by volume (or by weight where the density table reads
one), or a count ("30 saltine crackers", "1 box … Melba toast"); never a
line with no amount; only the first line of its head, since the steps name
a second one the same way (0407's Parmesan topping stays counted) — that a
step names, by its head or by the kind its item carries ("Parmesan",
"saltines"), in a sentence that sets the coat out in its shallow dish or
names it with the crumbs ("Pulse the saltines and chips together …; place
in a separate shallow baking dish", 0315; "Whisk ¼ cup of the flour and
the ¼ cup grated Parmesan together in a shallow dish", 0419; "add the bread
crumbs and ground almonds", 0117; "Transfer the crumbs to a pie plate and
stir in the Parmesan", 0407) — (L1) in a recipe that holds a dredge (0042,
0117, 0315 ×2, 0407, 0416, 0419), or (L2) in a recipe whose directions
leave an excess of the coat with no dredge line to hold: 0150 Oven-Fried
Chicken's Melba toast ("Gently shake off the excess"). A layer in a recipe
with neither stays counted — a crust set out with no excess sentence (0415
best chicken Parmesan, 0041's Melba-crusted goat cheese, 0258's chip
crust), a cheese binder (0000), nuts in a filling (0957), chips for garnish
(0820), the cheeses of a sauce (0300 classic macaroni and cheese) — and so
does a line no coat sentence names, even in a recipe that holds a dredge:
0118's cream cheese and cheddar, a filling beside its held flour and
crumbs. So do 2 tablespoons of Parmesan tossed with the crumbs (0206:
under the quarter cup). 0407's and 0416's Parmesan are 0117's shape — the
cheese stirred into the coat's crumbs ("when cool, stir in the Parmesan",
0416) in a recipe whose flour is shaken of its excess — so both hold: the
crumbs they are stirred into already hold since v33 (0407's bread, 0416's
panko), and a layer mixed evenly through a held coat is left in the dish
in the same share. The hold is written only on a row with a food: 0198's cornflakes, a layer of a held coat with no FDC match,
stay `no_match` (a person's pick then reads the line held `coating`, like
any line hold). A divided
line's part set out in the coat's dish is the dredge's: 0206's "¼ cup plus
6 tablespoons" flour holds with its 6 tablespoons whisked into the egg
whites as the eaten part. Held until the server's `coatingFraction` switch
— null, no figure set — gives the share a dredged
food keeps; since matcher v53 (M52) the engine's own row counts its share
of a coat budget sized from the coated food, unheld — sautéed dustings,
coats with no meat line and nut or cheese layers stay held: the v53
paragraph below; since matcher v65, M66 R3, a layer a step names with a
crumb joins the budget), `partial_pour_away` (since v22, Q4: a line of a braising
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
(egg 50 g, yolk 17 g, white 33 g) on the whole-egg record 748967. Since
matcher v49 (M47 Q6) a zest over a tablespoon plus juice counts too, as two
parts (or the juice alone when a step strains or discards the zest; with
no recipe to read, held as before) — the v49 paragraph below. Their keys
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
and sea salt flakes — read on the raw line — weigh at kosher salt's old
round 0.72 g/mL (kosher itself 0.60865 since matcher v63), never table
salt's 1.22: "2 tablespoons flake sea salt" is 21.3 g;
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
is its printed 3,628.74 g, labelled approximate. (The live step: 16
requests on scratch copies — 2026-10-03, 12 food details and 2 searches;
2026-10-04, the search `mushrooms portabella raw` and the detail of
169255. No v32 or v35 rule makes a request; each reads answers already
cached: a rank-as candidate from a snapshot-13 search (fetched 2026-09-08 or
2026-09-26) or the 2026-10-04 search, a portion from a live-step detail.
The chorizo rule reads no live-step answer — 174603 is a hit in the
2026-09-26 `salami` answer — and the Foundation portobello detail
(2003598) and the two chorizo searches are read by no rule.) Since matcher
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
bun)"`). Since matcher v35 (the owner's two requests, 2026-10-04):
`portobello mushroom cap`, `portobello mushrooms` (each reads `mushrooms
portabella raw`) → `mushrooms portabella raw` (169255; the Foundation
2003598 the v32 check read publishes a racc portion only, so the cap
stayed dry until then): the detail's `piece whole` 84 g — a portion the
whole-item finder reads as a dish serving — carries them as
`portobello mushroom` and `portobello mushroom cap` piece figures of 84 g,
flagged approximate because a whole mushroom's portion is read as one
stemmed cap ("1 large portobello mushroom cap" = `"1 × 84 g each ·
approximate (FDC's 'piece whole' portion read as one cap)"` — "large" is
no piece-table size; "6–8 portobello mushrooms (each 4 to 6 inches)"
reads the bare range's midpoint, 7 × 84 = 588 g). The weighed
`portobello mushroom caps` line keeps 2003598. Since matcher v37 (the
queue sweep, part 1 — the planners' zero-request rows, the owner's "go
with your recommendations", 2026-10-04; every answer and detail already
cached in snapshot 15): `ripe firm pears` → `pears` (169118 "Pears, raw";
under `pears raw` FNDDS 2709254, whose detail is not cached, ties it
ahead); `whole side salmon fillet` → `fish salmon raw` (2706284, the
comma-clause weight above); `raisins or other dried fruit` (reads
`raisins`) → `raisins` (2709212, `1 cup` 160 g); `cheese or a combination
of cheeses` (reads `cheddar cheese`) → `cheese cheddar` (328637, the
library's cheddar record; the line is weighed); `orange juice and 3 strips
zest` (reads `orange juice raw`) → `orange juice raw` (169098, juice only);
`strips orange zest` (reads `orange peel`) → `orange peel raw` (169103, the
v31 strip figure: 4.8 g); `canning and pickling salt` (reads `table salt`)
→ `salt table` (173468), COUNTED (the owner's answer: the standing ruling
zeroes only a rinsed or wiped salt; 36.08 g); and food-only fixes on
lines already counted at 0 g — `table alt and pepper`, `table salt for
cooking broccoli rabe and pasta`, `table salt and cayenne pepper` →
`salt table` (173468); `extra-virgin olive oil for frying` (reads
`extra-virgin olive oil`, whose answer holds 748608 alone) → 748608;
`sprigs thai or italian basil` → `basil raw` (2709780, flagged below);
`white or red onion` (reads `white onion`) → `onions white raw`
(1104962); `whole sage leaves` → `spices sage ground` (170935);
`pickled jalapeno slices` (reads `jarred jalapenos`) → `peppers
jalapenos` (2710096); `mexican crema` (reads `sour cream`) → `cream sour
full fat` (2346387, flagged below) — and `lemon twist` (reads `candied
lemon peel`) → `lemon peel raw` (167749), no grams (no printed size).
The S groups (flagged stand-ins, below): `mirin` (reads `sherry`) → `wine
dessert sweet`; `gochujang`, `gochujang paste` (read `pickled jalapeno
chiles`) → `sauce hot chile sriracha`; `doenjang` (reads `white miso`) →
`miso` (SR 172442 ranks 1.0 ahead of FNDDS 2707439, which has no cached
detail); `galangal` (reads `piece ginger`) → `ginger root raw`;
`culantro` (reads `cilantro leaves`) → `coriander cilantro leaves raw`;
`alcaparrado` (reads `green olives`) → `olives green`; `multicolored
nonpareils` (reads `granulated sugar`) → `sugars granulated`; `five-spice
powder`, `chinese five-spice powder` (read `five-spice powder`) → `spices
pumpkin pie spice`; `garam masala` (reads `curry powder`) → `spices curry
powder`; `sichuan peppercorns`, `pink peppercorns` → `spices pepper
black`; `canned chipotle chile in adobo sauce`, `chipotle chile in adobo
sauce` → `sauce hot chile sriracha` (the held `second_food` lines whose
first food is this item — Tacos al Carbon, Tinga de Pollo — move with it
and stay held); `skinless white fish fillets` (reads `cod`) → `fish cod
atlantic wild caught raw`; `herb`, `herbs` (read `parsley`) → `parsley
fresh`; `creme fraiche` (reads `heavy cream`) → `cream heavy`. Built DRY
(commented LIVE STEP entries, each naming its request and the check to
make on the answer; 30 requests: 19 food details, 2 searches and the 2
details they name, the ya cai detail, and three speculative searches with
their details): bulgur 170688, powdered pectin 168821, barley malt flour
169740, fennel fronds on FNDDS 2709779 (flagged), sour cherries 167769
(flagged; the jar-weight reader first), seed gums 169045 (flagged),
salted pepitas 169415, Oreos 172718, parsnips 170417, turnip FNDDS
2709809, romaine 169247, red leaf lettuce 168431 (not reachable by a
rank-as: it needs a count-line sibling reader), kiwi 2709239, the
radicchio, cauliflower, canned chickpea and raw cashew volume siblings
(168564, 169986, 173801, 170162), malted milk powder 173220, seaweed
2709988 (nori, gim), frisée (search `endive raw`), cremini (search
`mushrooms brown italian crimini raw`), ya cai 169891 (flagged), candied
ginger (search `candied ginger`), freekeh (search `freekeh`) and whole
farro (search `farro`, or the owner's label figure).
Since matcher v38 (the owner's live step, 2026-10-04 on a scratch copy:
26 requests — 21 food details and 5 searches; the accuracy track's live
requests now total 42 with v32's and v35's 16; each check made on the
record's REAL portions, a rule enabled only where it passed):
`medium-grind bulgur`, `medium-grain bulgur`, `fine-grind bulgur` →
`bulgur dry` (170688, `cup` 140 g); `diastatic malt powder` → `barley
malt flour` (169740, `cup` 162 g: "1 teaspoon" is 3.38 g); `roasted with
salt pepitas` → `seeds pumpkin and squash seed kernels roasted with salt
added` (169415, `cup` 118 g); `oreo cookies` (reads `creme fraiche`) →
`cookies chocolate sandwich with creme filling regular` (172718: `3
cookie` 36 g — a count of three the whole-item finder never reads as one
item, so an `oreo cookies` piece figure of 12 g carries it: "16 Oreo
cookies" = `"16 × 12 g each"`, 192 g); `turnip` → `turnips raw` (FNDDS
2709809 "Turnip, raw", which ties SR 170465 and leads: `1 whole` 120 g;
the library's `turnips` weight lines are another item and keep 2747674);
`romaine lettuce leaves` → `lettuce cos or romaine raw` (169247: the
finder reads its first leaf portion, `leaf inner` 6 g — "5 romaine
lettuce leaves" is 30 g; `leaf outer` is 28 g); `frisee` (reads `endive
raw`) → `endive raw` (168412, the search's only candidate: `cup, chopped`
½ cup 25 g — "1 cup frisée" is 50 g; "1 head frisée (6 ounces)" its
printed 170.10 g); `cremini mushrooms` (reads `mushrooms brown italian
crimini raw`) → the same words (168434, SR, leading FDC's two-record
answer: `piece whole` 20 g — a portion the finder reads as a dish serving,
so a `cremini mushroom` piece figure of 20 g carries "24 cremini
mushrooms", 480 g, flagged approximate (`FDC's 'piece whole' portion read
as one cremini`); the library's 18 weighed cremini lines move to the same
food and keep their grams); `ya cai` (reads `salt`) → `cabbage mustard
salted` (169891, `cup` 128 g, flagged below); and the radicchio,
cauliflower and canned-chickpea volume siblings (above). Left DRY, with
the portions FDC published: powdered pectin (168821: `package (1.75 oz)`
50 g only), fennel fronds (FNDDS 2709779: `1 fennel bulb` 235 g, `Quantity
not specified` 25 g), sour cherries (167769 publishes `cup` 168 g, but no
reader yet skips the "(24-ounce)" jar weight read first — enabled since
matcher v64, M65 F5, below), seed gums
(169045: `oz` only), parsnips (170417: `cup slices` 133 g, no piece),
kiwis (FNDDS 2709239: `1 fruit` 75 g, no `large` — counted since matcher
v49 at that 75 g, below), malted milk powder
(173220: `serving (3 heaping tsp or 1 envelope)` 21 g, no level
tablespoon — the line stays on the prepared drink 174867), seaweed (FNDDS
2709988: `1 cup` 15 g, `1 strip` 0.5 g, no sheet; since matcher v64, M65
F7, the strained kombu line shows it at 0 g), raw cashews (170162:
`oz` only), and red leaf lettuce (168431, not fetched: no rank-as reaches
it). FDC has no record of three foods, whose lines stay a person's: the
`candied ginger` search answers tea, pickled, raw and ground ginger,
ginger ale and candies — no candied or crystallized ginger (never the
raw root); `freekeh` answers nothing; `farro` answers only 2710828
"Farro, pearled, dry, raw" (a 45 g racc, no cup), not whole farro, so
`whole farro` keeps its v21 words (the owner's label figure is the way
on).

**Since matcher v48 (batch M48, matcherVersion 47; the owner's 2026-10-07
re-ruling of checkpoint 9 Q5, prep47 design_v2 §1 Q1 = (c); zero
requests): every printed weight RANGE reads its midpoint.** Checkpoint 9 Q5 (2026-10-01)
kept "upper bound in parentheses, midpoint bare" — a convention that began
as B2's regex miss (2026-07-28, "won't fix, upper bound intended") and read
the same printed range two ways by spelling alone ("(10 to 12-ounce)" 312
g a breast, "(10- to 12-ounce)" 340 g). Audit 2 (P1) found 8 of the 10
sampled ranged lines above the auditors' midpoint (mean +6.1 %, L103's
"8 (5- to 7-ounce) bone-in chicken thighs" +16.6 %); every auditor and
calibrator read the midpoint (9 of 9 lines, 4 of 4 recipes). Now one rule
(grams.dart `_range`): the hyphenated "(5- to 7-ounce)", the fraction "(3½-
to 4-pound)" / "(8¾ to 10 ounces)", the en dash "(12–22 pounds gross
weight)" (the paren regex never saw it: it read "22 pounds"), a spaced
mixed number "(3 ½- to 4-pound)" (folded to "3½"; else ½ to 4 — a single
"(1 ½-pound)" folds too, 1½ lb, was ½), an ASCII mixed-number bound
as the editor and other libraries print it ("(3 1/2- to 4-pound)", "(1
1/4- to 1 1/2-pound)", "(3 1/2–4 pounds)" — the paren's number held no
space and read "1/2- to 4", ½–4 lb; a single "(3 1/2-pound)" follows, 3½
lb, was ½; the corpus prints none, so no replay row moves), the
whole-number "(5 to 6-ounce)" and a bare "1½–2 pounds" all read (low +
high) ÷ 2; the range switch `rangeWeightsMidpoint` is gone. **Reversed
bounds keep the larger** — "(14⅔ to 6½ ounces) bread flour" (pane-francese,
a corpus typo for 16½; 6½ ounces is not 2⅔–3 cups) stays 415.79 g, the
corpus's only one. One reader serves every amount, so a bare reversed
amount ("6½–4 ounces" → 6½ oz, basis "from 6 1/2–4 ounce", no midpoint)
and a reversed count or volume ("3–2 lemons" → 3) keep the larger too
(v47 read those at the midpoint; the corpus prints none). The figure
is the arithmetic mean of two printed figures, so **no approximation
flag**; the `gram_basis` names the range:
`"8 × 170 g (printed 5–7 oz, the midpoint) × 0.70 edible · approximate
(USDA AH-102 item 586: …)"` (per unit), `"from the printed weight (12–14
lb, the midpoint) × 0.65 edible · …"` (the line total), `"from 1 1/2–2
pound (the midpoint) × 0.70 edible · …"` (a bare amount); a single printed
weight keeps `"(printed weight)"` / `"from the printed weight"`, and so do
reversed bounds. Reach (the cache-only replay of snapshot 21, main and
reverse-parents byte-identical, calls 0): exactly 186 main rows change
grams (177 hyphenated, 8 fraction "A to B", 1 en dash) and 14 more change
basis only (7 whole-number "A to B" parens, 7 bare ranges — already at the
midpoint); 0 section rows, 0 parents, no status, bucket or hold moves;
−44,132.8 kcal per batch (−1.29 % of the library's 3,425,245): whole birds
−10,680, boneless roasts −9,991, bone-in roasts/ribs/hams −6,825, bone-in
poultry parts −6,524, steaks and chops −4,386, fish −2,849, boneless
poultry −2,420, dry goods −366, produce −92; per recipe (185) the median
−6.5 % a serving (−1.8 % to −21.8 %; the largest −212.8 kcal a serving).
L103 lands 952.54 g (the auditor's 953); a 12- to 14-pound turkey 4,137.40
→ 3,841.87 g; the en-dash turkey 6,501.63 → 5,023.98 g; the "(10- to
12-ounce)" breasts read their "(10 to 12-ounce)" twin, 923.06 g.

**Since matcher v49 (batch M47, matcherVersion 48 — records and published
figures; prep47 design_v2 §1 (B) and §2 "M47", decided under the owner's
2026-10-07 standing authorization; zero requests, every record cached in
snapshot 21).** Eight steps, each on a shipped mechanism:
(1) **Shellfish (Q11)**: a weight bought in the shell (`in_shell`'s
`boughtInShell`) reads USDA AH-102 (1975) Table 1 by its raw record
(grams.dart `ah102Shells`, after FDC's own "lb (with shell)" portion):
shrimp on SR 175179 × 0.81, flagged `approximate (USDA AH-102 item 2333:
shrimp, headless, in shell → shelled, deveined 81 % (77–82))`; mussels move
off FNDDS 2706350 "Mussels" (cooked meat) to cached SR 174216 "Mollusks,
mussel, blue, raw" (engine `shellRecords`, the `skinlessRecords` record
move; the decision names the record bought) × 0.29, flagged `approximate
(USDA AH-102 item 1531: mussels, whole → drained solids, raw 29 % (25–33);
the liquor in the pot is not counted)` — every mussel recipe serves the
liquor, which raw 174216 does not carry (item 1530, solids and liquor, is
51 %). Never where the recipe eats the shell (crispy salt-and-pepper
shrimp's "eaten shells and all": 680.39 g gross) nor a count (paella's "1
dozen mussels", 180 g on 2706350). No corpus line stays `in_shell`. An
un-skip re-derives the hold from the stored grams' basis as a compute does
(the AH-102 flag, v40's clam shell yield), so a skipped shell row comes back
counted, never held `in_shell` (closer round 2).
(2) **Kiwi (Q12, re-rules v21 R09's "STAY DRY")**: piece rows `kiwis` /
`kiwi` 75 g, FNDDS 2709239 "Kiwi fruit, raw" '1 fruit' (a cross-record
piece weight; the lines stay on Foundation 2710831); a sized count
("2 large kiwis") flagged `approximate (one fruit, FNDDS 2709239: 75 g; no
large size published)`. (3) **Citrus (Q6, amends checkpoint 5)**: a zest
or peel over a tablespoon plus the fruit's juice counts as TWO parts — the
zest on its peel record (lemon and lime 167749, the shipped flagged
lime-zest approximation; orange 169103), the juice on its own (167747,
168156, 169098) — `gram_basis` `"zest 1/4 cup · USDA portion + juice 1/4
cup · USDA portion"`, `parts` roles `zest`, `juice`; when a step at or after
the zest's first mention strains it ("Strain…", "through a fine-mesh
strainer") or discards it, the juice alone, `"· juice only (the zest is
strained out)"`. A tablespoon or less keeps the checkpoint-5 rule (juice
only, zest dropped — the boundary is kept, F17). The v44 S7 rule (a zest
plus a COUNT of the fruit reads the fruit) widens to lemons (2709168) and
limes (168155). (4) **Canned beans (Q14, Q14b; amends 2026-10-06)**: a can
line with no drain or rinse word whose steps add it "(and|with) (their|its)
liquid" (naming the line's head noun) keeps the can whole; a can kept whole
on a drained-and-rinsed record with a cached solids-and-liquids twin moves
to it, grams unchanged, no flag (grams.dart `cannedBeanLiquids`: chickpeas
2644288 → SR 175206, pinto 2644292 → 175201, kidney 2644289 → 175195), and
the half rule's undrained can is a part there (the row stays on the
record bought: `parts` roles `drained`, `undrained`; basis suffix "· the
undrained can on its solids-and-liquids record"); basis `"from the printed
weight (the steps add the beans and their liquid)"`, and on a bean with no
twin cached (navy, cannellini, black) `"… · approximate (no
solids-and-liquids record for this bean: the drained-and-rinsed record for
the whole can)"`. Acquacotta's reserved liquid is whisked back (Q14b): its
whole can on cannellini stays. Only an `auto` or `confirmed` row carries
the parts of (3) and (4): a person's pick clears them (one record, as rule
B1's bacon, D12) — crispy-orange-beef|3 picked to its peel 169103 counts
the zest alone, 24.00 g; espinacas-con-garbanzos|1 picked to 2644288 keeps
the half rule's 665.50 g — and typed grams clear them too (closer round 3).
(5) **Records (Q15, Q26, Q23)**: rank-as
`jarred hot cherry peppers` → the cached `pickled hot cherry peppers` answer
under its own words (FNDDS 2710095 "Peppers, hot, pickled", unflagged) — a
rank-as, not a rewrite: the phrase is the cached answer the Thai chiles
read, and a "Search live" asks the rewrite of a row's `candidates_query`,
so as a rewrite key it would re-ask the pickled answer on every Thai chile
row. The four Thai chile rewrites onto that answer became rank-as reads of
it (a rank-as key is never a rewrite target), same landing, and a live
search on any of these rows asks the answer it reads; rank-as `herbes de
provence` → 170938
"Spices, thyme, dried" flagged `approximation (counted as Spices, thyme,
dried)`; `frozen raspberries` → FNDDS 2709282 "Raspberries, frozen"
(unflagged); `halloumi cheese` and `halloumi` → FNDDS 2705720 "Cheese,
Monterey" flagged `approximation (counted as Cheese, Monterey)` (FDC has no
halloumi; the v46 mascarpone ruling). Red curry paste (`red curry paste`,
`thai red curry paste`) and Old Bay (`old bay seasoning`) — FDC has no
record in the three datasets it searches — land `no_match` with NO record
shown and no search sent: a VETO LIST keyed on the normalized item
(matcher.dart `noFdcRecordItems`), never their answers' tops "Beef curry"
2706388 and "Spices, poultry seasoning" 171331. (6) **Tapioca starch (Q5,
amends CP9)**: ATK's own "3 ounces (¾ cup)" (the GF flour blend), 113.4 g a
cup, over the stand-in pearl record's cup (152 g), flagged `approximate
(ATK's printed 3 ounces per ¾ cup)` (pão de queijo 456.00 → 340.19 g; a
weighed line and "instant tapioca" unchanged). (7)–(8) **Nutrient
siblings (Q15 iv, Q13)**: Foundation 2758998 "Pasta, dry, enriched,
spaghetti" (minerals only) → SR 169736 "Pasta, dry, enriched"; FNDDS's
cooked-state "Leeks" 2709935 → SR 169246 (raw, 61 kcal) and "Rhubarb"
2709268 → SR 167758 (raw, 21 kcal); grams unchanged. The pasta line
itself (pasta e fagioli, "8 ounces small pasta such as ditalini, …") is a
rank-as (the owner's 2026-10-07 ruling): `pasta such as ditalini` reads its
own cached answer under the record's words `pasta dry enriched` → SR 169736
"Pasta, dry, enriched", unflagged (that answer had ranked the spaghetti
record first at 0.0125, below the gate): 226.80 g, 841.41 kcal, the recipe
16 → 17 of 18 (partial: the Parmesan rind). The 2758998 sibling stays for
any other line that lands the Foundation record.
Reach (the cache-only replay of snapshot 21, main and reverse-parents
byte-identical, calls 0): exactly 61 rows differ — 7 shellfish, 2 kiwi, 11
citrus, 5 canned beans, 15 records (1 pepper, 4 herbes, 2 halloumi, 8
vetoed), 1 tapioca, 1 pasta (counted on 169736 by rank-as), 18
leek/rhubarb, and 1 parent re-reading its leek section; +926.9 kcal per
batch (shellfish +1,955.0, kiwi +195.2, citrus +299.2, beans −811.6,
records +1,135.2, tapioca −414.6, pasta +841.4, leeks/rhubarb −2,249.0 and
the parent −24.0); holds: `in_shell` 7 → 0, `second_food` 24 → 13,
`no_nutrients` 8 → 3; 22 recipes complete (980 → 1,002), 1 section (134 →
135); main `check` 214 → 184, `counted` 13,338 → 13,364, `no_match` 11 →
16.

**Since matcher v50 (batch M50, matcherVersion 49 — discards and partial
use; prep47 design_v2 §1 Q16, Q17, Q18, Q20, Q21, Q7 and §2 "M50", decided
under the owner's 2026-10-07 standing authorization; zero requests).** Four
new discarded media (engine `DiscardedMedium`), read from the steps alone
after every shipped reader (a drained pot's `discarded_medium`, the brine
co-solutes and the pour-aways keep their lines), on every write path:
(1) **Strained solids (Q16, `strainedSolid`; AMENDS the 2026-09-28 ruling
"poured-away media the rules could not see … are held" for strained solids
and removed aromatics — the 0 g footing is that day's brine ruling).** The
first sentence that strains and presses or discards the solids ("Strain …
pressing on the solids", "…; discard solids", a next sentence "Discard …
solids") or strains a stock or broth ("Strain broth through …") — never a
purée, soup, custard, batter or "mixture into" strain — counts 0 g
(`discarded`) every aromatic vegetable, herb, whole spice, peppercorn, kombu
and zest strip whose nth mention stands before it and whose food no later
sentence names again, `gram_basis` `"discarded in cooking — counted as 0 g ·
approximate (strained out and discarded — what it gives the liquid is not
counted)"`. Never a ground spice, a powder or a paste ("1½ teaspoons ground
cardamom" stays 3.03 g — they pass the strainer), never a line its own
steps blend smooth or into a paste (cochinita pibil's garlic, spices and
grilled onion), never one mixed in a bowl, mixer, processor or blender
unless a later "add the … mixture" in the pot carries it there (the Sauce
Base's processor vegetables are carried), never the second pot of a
"Meanwhile, strain …" step or a baking sheet beside a strained skillet;
"beef broth" or "lemon juice" is no mention of the beef or the lemon, and
the mixture the strain sentence itself strains ("Strain garlic-lemon
mixture …") named again ("Process garlic-lemon mixture") is the liquid, not
the garlic back. Never a vegetable a sentence lifts out with "the
vegetables" before the strain ("Using slotted spoon, transfer vegetables to
serving platter" — the French chicken's carrots are served; the garlic and
peppercorns "sprinkled … over vegetables" are set apart from them and
strained), and never a strain whose next sentence keeps some of the solids
("Measure 1 tablespoon of solids …", grilled potatoes). A numbered part the
line's own mention keeps out of the strained pot ("combine the remaining 2
tablespoons shallot … in a medium bowl", the poached salmon) is counted:
`"discarded in cooking: 2 of 4 tablespoons — only the rest counted ·
approximate (strained out and discarded — what it gives the liquid is not
counted)"`, 20 g of 40.
(2) **Cured pork a step strains out or discards (Q17) and ground stock meat
(critic F4):** 0 g when a sentence outside a parenthesis skims, separates
or pours off the pot's fat ("skim the fat off the surface", "into a fat
separator") — stock meat also when blanched and drained (the pho's beef) —
else **held** `discarded_medium` (new value `fatKept`: its rendered fat
stays in the dish in a share no source gives; no grams stored; the wedding
soup's only skim is the make-ahead "(… Skim off fat before reheating.)").
Zeroed: modern beef burgundy's salt pork, beef braised in Barolo's
pancetta, coq au Riesling's bacon, best beef stew's and daube provençal's
salt pork, the stuffed turkey's draped salt pork; held: the Calvados
chops' bacon, New England fish chowder's salt pork, milk-braised pork
loin's ("discard salt pork, leaving fat in pot"), modern ham and split pea
soup's bacon, the wedding soup's ground pork and beef. The four rows the
bacon batch (M49) would also read — the Barolo pancetta, coq au
Riesling's bacon, the Calvados chops' bacon, the split pea soup's bacon —
are settled here, and M49 never touches them (critic F11).
(3) **Whole aromatics removed and discarded (Q18, `removedAromatic`):**
"(remove and) discard (the) <noun list>" naming a bay leaf, a cinnamon
stick, star anise, kombu, an herb or cilantro bundle, onion halves or
rounds, a garlic head or crushed cloves, bell-pepper halves, a celery
bundle or lemons from a cavity — and the aromatics and whole spices a
sentence ties (tie, twine) into a bundle a later sentence removes or
discards ("remove herb bundle", "discard spice bundle"; never a citrus
line, whose juice is eaten) — counts 0 g, `"removed and discarded (step N)
— counted as 0 g"`; since matcher v63 (M64) "remove (the) bay leaf/leaves"
with or without "and discard" counts the bay leaf the same (the bay leaf
only); a line partly cut fine ("2 medium onions, 1 quartered
and 1 chopped fine") stays counted. A COUNT line partitioned by the steps
("Cut 1 of the lemons … in the cavity" … "Discard the lemons" … "Halve the
remaining lemon") zeroes only the discarded pieces (critic F12):
`"removed and discarded (step 6): 1 of 2 — only the rest counted"`, 58 g of
116; so do pieces ("1 bell pepper half, 1 onion half" in the beans' pot,
"the remaining peppers and onion" in the sofrito: `"… 1 of 4 halves …"`
178.50 g of 238, `"… 1 of 2 halves …"` 75 g of 150 — the design pinned
these at 0 g from a misreading; the corpus text and Q18's partition ruling
count the eaten halves), and a bundle tied from the line's own "remaining
10 cilantro sprigs" (`"removed and discarded (step 4): 10 of 30 — only the
rest counted"`, the leaves of 20 sprigs eaten). "Discard all but 3 tablespoons … fat" names the fat, never the food.
(4) **A printed part kept (Q20, `partialUse`):** (i) "Save the remaining 6
tablespoons butter for another use" subtracts the remainder in the line's
unit (`"the remaining 6 tablespoons saved for another use (step 1) — only
the rest counted"`, blueberry scones 226.89 → 141.81 g) — since matcher
v63 (M64 P10) also a counted part, "Set aside 1 pear half and reserve for
other use": N halves (quarters) of the line's count × 2 (× 4), the basis
the weighing's own text then `1 pear half saved for another use (step 2) —
only the rest counted`; (ii) a potato kept
by a printed COOKED weight — "Transfer 3 cups (16 ounces) warm potatoes",
or "Measure 1 very firmly packed cup potatoes" with the prep note's "1 very
firmly packed cup (½ pound) of mash" — converts to the raw record by FDC
carbohydrate on the flesh-only cooked record (critic F18; baked: SR 170033
21.6 g, boiled: SR 170114 20.1 g, over the line's record's own: 2346401
17.77125 g), `"from 16 ounces cooked (step 3) · approximate (the steps keep
16 ounces of the baked potato; its raw weight by FDC's carbohydrate,
170033)"` — potato gnocchi 907.18 → 551.32 g (the auditors' 570),
potato burger buns 367.41 → 256.52 g (230); a weight line whose record
detail no portion fetched reads its search hit's rounded carbohydrate
(17.8 g: 550.43 g); (iii) a whole food reserved for another use
("transfer the wings to a dinner plate to reserve for another use") or the
rest of it discarded ("Discard remaining beer and can") counts 0 g,
`"reserved for another use (step N) — counted as 0 g"` / `"the rest
discarded (step N) — counted as 0 g"`; (iv) a kept VOLUME with no printed
weight ("Measure 1⅓ cups lightly packed potato; discard the remaining
potato"; "Measure out 2 teaspoons porcini powder; reserve remainder", the
line named by its head or the word before it) counts the line whole, its
basis flagged `"· approximate (the steps keep only 1⅓ cups of it)"`.
(5) **Flags only, no grams move:** a dip, batter, glaze or egg wash the
steps leave an excess of in the bowl (Q21: "Scrape off excess chocolate",
"allowing the excess batter to drip off", "(you won't need all of it)") —
the food word's own lines, or a mixture's lines a whisk/combine/stir/sift
sentence names in the dip's step or the step before, with the making step
of a "<food> mixture" those sentences continue (fish-and-chips' batter from
step 2's flour mixture, the audit's baking powder L206) and, for a glaze,
the step that reduces it (negimaki) — `"· approximate (the
steps leave an excess of it in the bowl — how much is eaten is not
written)"`; a marinade the food is lifted out of (Q7, keeping the
2026-09-28 "a marinade's food stays counted": "Remove chicken from
marinade and wipe off excess", "Lift chicken from marinade") — the lines
the first step's whisk/combine/process/blend sentences name ("Process all
ingredients in blender": the first ingredient group) — `"·
approximate (lifted out of its marinade — how much clings is not
written)"`; never a marinade cooked into a sauce or kept ("leaving any
marinade that sticks"), never beef satay's (no sentence lifts the meat
out). Neither flag rides on typed grams, a held row or a 0 g row. Stated
ceilings (0 kcal): the spareribs' glaze (its liquid whisked two steps
before the reduction) and fish-and-chips' black pepper (the batter's one
"pepper" goes to the cayenne line) stay unflagged.
Reach (the cache-only replay of snapshot 21, main and reverse-parents
byte-identical, calls 0): exactly 333 rows differ — strained solids 132
(112 main, 20 section; 16 move no kcal: a sprig already at 0 g, a record
below the gate), stock meat held 2, cured pork 3 strained + 3 discarded
zeroed and 4 held, removed aromatics 102 (25 move no kcal), partial use 5,
flags 77 (3 kept volume, 34 dips, 40 marinades), and 5 parents re-reading
a strained section (the herb sauce's Sauce Base, steak Diane's, the
crisp-skin turkey's Turkey Gravy, and the Giblet Pan Gravy two roast
turkeys read); −14,714.3 kcal per batch on main rows (strained −3,653.9
incl. the held stock meat, cured pork −8,103.3, removed −518.3, partial use −1,818.6,
parents −620.2), sections −884.7; holds `discarded_medium` 58 → 64; 5
recipes complete → partial (the four held cured-pork recipes and the
wedding soup; 1,002 → 997); main `check` 184 → 189, `counted` 13,364 →
13,359 (one kombu row below the gate now 0 g counted).

**Since matcher v51 (batch M49, matcherVersion 50 — the bacon package and
fat poured off; prep47 design_v2 §1 Q4 (b) and Q19 (a), §2 "M49", decided
under the owner's 2026-10-07 standing authorization; zero requests).
RE-RULES Y11 (2026-10-06, "bacon keeps 0.403") and v40's "the wider bacon
lines a person's".** (1) **Rule B1's yield:** the cooked bacon is the raw
weight × **0.33**, USDA Agriculture Handbook 102 item 1981 "bacon, sliced,
all methods → cooked 33 % (18–43)" (transcribed in
`.claude/diag/2026-10-06/ah102_produce_meat.md`); the rendered fat follows
by the same fat balance on the two records the row is counted on, 168277's
fat less the cooked part's: 0.3713 − 0.33 × 0.351 = **0.2555** g a raw gram
(0.2299 at 0.403). The cost, stated: on 168322's composition 0.33 keeps
11.19 g of 168277's 13.66 g protein a 100 g raw, 18 % of the protein
balance given up — the two records are different samples, and item 1981's
own range (18–43) holds 0.403. The rendered row's flag is "approximate
(USDA AH-102 item 1981: bacon, sliced, all methods → cooked 33 % (18–43))".
(2) **Slices** (grams.dart's piece table, the longer key first — a
thick-cut or Canadian slice never reads the plain one, nor a plain one
either): `bacon` **28 g** (SR 168277's own "slice raw"; the corpus's "1
ounce a slice", 28.35 g, agrees to 1.3 %; the 24 g of d614c2e had no
source), `thick-cut bacon` **35.44 g**, the median of the corpus's three
thick-cut prints ("10 ounces (about 8 slices)" 35.44, "6 ounces … (about 5
slices)" 34.02, "5 ounces (about 3 slices)" 47.25), flagged "approximate
(the corpus's printed thick-cut slice, median of three)" (the CP9 Q6
corpus-print class), `canadian bacon` **28.5 g** (SR 167869's "2 slices (6
per 6-oz pkg.)" 57 g). A slice of 10 g or more that is no whole gram says
its own figure in the basis ("8 slice × 28.5 g each"). **The v40
amendment:** the raw-counted bacon lines v40 left to a person (fried and
drained lines rule B1 does not reach — oven-fried bacon, the bacon-wrapped
scallops) stay the person's to correct; the slice weight alone moves them
(oven-fried-bacon|0 288 → 336 g raw). (Matcher v59, M60 P7b: the
bacon-wrapped scallops, grilled, and the meatloaf's draped bacon now take
B1's parts with no fat kept.) (3) **An oil browned in a pan the
steps pour down to a printed part (Q19 a, P1 D3a):** the recipe's first
"(pour off | pour out | drain off | spoon off | discard | remove and
discard) all but N teaspoons/tablespoons/cups (of the) (rendered) fat /
oil / drippings / grease" sentence cuts the oil line whose LAST mention
before it — in its step, or the step before; since matcher v63 (M64 F9) in
any earlier step — puts it in a pan (heat,
cook, a skillet, a pot, a Dutch oven, a wok) and names ONE oil line (the
only one with an amount, or by a kind word only it has: "Heat vegetable
oil" is the lamb's, never its relish's olive oil; Chicken Marbella's "Heat
oil" names neither of its two oils, so neither is cut): the oil counts its
part in the pan at most the kept N, weighed as a line of N of that oil
weighs (`discarded`, `gram_basis` "N kept (the steps pour off the rest)");
its part written outside the pan stays whole ("Heat 2 teaspoons of the
oil" — Skillet Jambalaya's other 3 teaspoons go in after the pour-off, so
it does not move). A frying oil's own "Reserve N oil … and discard the
remainder" (`_Fat.reserveRest`, beside "pour off all but N oil") is its
kept part, counted WITH the part the steps use outside the fry
(horseradish-crusted beef tenderloin: "1 cup plus 2 teaspoons vegetable
oil" → the 2 teaspoons tossed with the crumbs + the reserved tablespoon,
23.07 g; basis "discarded in cooking — only "plus 2 teaspoons vegetable
oil" and the 1 tablespoon the steps keep counted"). (4) **The bacon pan
shared with an oil (P4 §4):** when rule B1's pour-off pan holds an oil
browned before it (the same window), the stated N covers both fats: the
kept fat is min(N, R + O) — R the bacon line's rendered fat (raw ×
0.2555), O the oil — the bacon's grease R / (R + O) of it and the oil row
O / (R + O) ("N kept with the bacon grease (the steps pour off the
rest)"): pasta with tomato, bacon and onion 170.10 g raw → 56.13 + 15.87 =
72.00 g (audit L145 94.3 → 72.0, auditors 75.5), its olive oil 27.21 →
9.93 g; salade lyonnaise 46.78 + 14.73, its oil 11.07 g; gricia's ⅓ cup
(68.80 g) now below R + O (57.95 + 13.60): 74.84 + 55.72, its oil 13.08 g.
(5) **The frying MARK (critic F13):** `keptOilFries` names the food a
frying oil's kept-part pour-off step fries before it ("Transfer the
potatoes and remaining 1 cup oil to the skillet" → `potato`), read by the
coats-and-uptake batch (M52) to add that food's uptake on top of the kept
part; no grams move on it here (the crispy tempeh, fried a step before its
pour-off, carries none). The four cured-pork rows M50 settled (Barolo,
coq au Riesling, the Calvados chops, the split pea soup) are untouched.
Reach (replay of snapshot 21, rp43, 0 requests): 35 rows — 13 rule-B1 rows
(10 the yield, 5 of them on slices; 3 the split), 11 slices, 1 thick-cut,
1 Canadian, 4 browning oils cut, the horseradish oil, 3 oils sharing a
bacon pan, 1 parent (the stuffed turkey re-reading its Bread Stuffing:
3,121.60 → 3,088.50 g); −2,328.5 kcal per batch (the bacon package
+586.4: the 13 rule-B1 rows at the yield (5 on the new slices, the 3
split rows' yield share) −407.7, the 12 raw-counted slices +954.5,
Canadian +39.6; the split −494.6;
the browning oils −375.4; the horseradish oil −1,890.0; the parent
−155.0; components rounded); no bucket, hold or status moves.

**Since matcher v52 (batch M51, matcherVersion 51 — references with no
amount; prep47 design_v2 §1 Q8, Q8b, Q9, Q22 and Q15 (iii), §2 "M51",
decided under the owner's 2026-10-07 standing authorization; zero
requests). RE-RULES prep41 A3 (a) ("a reference the engine does not route
reads partial until phase 2") for a reference with no amount, and CP3
(2026-09-27, "variations … stay OUT of the main totals") for a reference
to a prose variation; the copy is the approved
`docs/mockups/v51-references-copy.html` §4.** Three rules in
`resolveReference`, in this order:

- **SW — served with (Q8, Q8b).** A marked reference with **no amount**
  whose line says "optional", says "for serving", offers an alternative
  after " or " (the split the reference detector reads), or sits in an
  ingredient group headed CONDIMENTS (`servedWithMarked`), is served with
  the dish: the 0 g rule row as before, `child.reason` `served_with`, and
  **accounted** in the totals as a confirmed water row is — it no longer
  makes the label partial. D7's title rule (the parent "… for {child}", Q8b:
  restaurant-style herb sauce's "1 recipe Pan-Seared Steaks (this page)" is
  NOT routed to the steaks) keeps its own `served_with` answer, with or
  without an amount. The nutrition GET lists such rows in **`served_with`**
  (`[{position, name}]`, `name` the reference's first alternative —
  "Sweet-and-Sour Chutney", never "… or lemon wedges"; `[]` when none),
  never in `partial`; the app renders each as the non-partial label line
  "Served with {name} — not counted." Reach: 6 main lines —
  pan-seared-salmon|3, maryland-crab-cakes|10, the Indian curry's |16
  (CONDIMENTS) and |17, spanish-tortilla|8, the herb sauce|0; 0 kcal; the
  salmon, the curry, the tortilla and the herb sauce complete (crab cakes
  stays partial on |3 Old Bay, |8 the coating, |9 the frying oil).
  skillet-chicken-fajitas|22 is not SW: its group "RAJAS CON CREMA" is no
  CONDIMENTS heading.
- **The gate (critic F7).** A reference line WITH an amount never reads a
  served-with marker: the ruled practice stands (prep39 — optional and "for
  serving" lines with an amount are counted). The ten marked references
  with amounts (guay-tiew-tom-yum-goong|15, classic-roast-stuffed-turkey|10,
  crisp-skin-high-roast-butterflied-turkey|4, garlic-studded-roast-pork-
  loin|6, spanish-style-toasted-pasta-with-shrimp|16, juicy-pub-style-
  burgers|5, thai-green-curry|1, grilled-pork-chops|3, grill-roasted-bone-in-
  pork-rib-roast|4, dark-chocolate-cupcakes|11) are unchanged in child,
  share and grams.
- **WB — a whole batch (Q22).** A marked reference with no amount and none
  of SW's markers that the shipped order resolves to a child with lines
  that is not nested routes at **share 1.0** — the line names the recipe
  once and the steps plate it ("top with … pickled radishes", "serve over
  rice", "spoon … coulis onto … plates") — flagged **"approximate (no
  amount on the line — the whole batch counted)"** (`match.flag`; the
  label's includes entry reads `flag` "approximation"). Any other answer
  for such a line (held, nested, a marinade, no share, a PV base) stays the
  `no_amount` rule row. Reach: skillet-chicken-fajitas|22 → its own Spicy
  Pickled Radishes (184.3 g, 55.55 kcal), red-beans-and-rice|14 → 0521's
  Basic White Rice (402.2 g of Foundation 2512381, 1,442.71 kcal), panna-cotta|6 →
  its own Raspberry Coulis (748.2 g, 642.77 kcal); +2,141.03 kcal; three
  new child sections (computed sections 140 → 143); all three complete.
- **PV — a prose variation's base (Q9).** When the order reaches a section
  with no ingredient lines (`no_ingredients`), the line counts the BASE:
  of that section's host (when it lists lines and is neither the parent nor
  its host) and the host's sections that list lines (never the prose
  section, never the parent), the one whose title shares the most words
  with the prose section's (the resolver's normalised words); the host on a
  tie, else the first such section; no shared word keeps the
  `no_ingredients` row. Share from the line as before; flagged
  **"approximation (counted as {base title}; the variation's changes are
  not read)"**. The prose section itself is still never computed, and the
  parent's hash still folds it (v47 F2's `prose_sections`): it gaining lines
  stales the parent, whose next sweep routes to it. Reach:
  fresh-plum-ginger-pie|0 → 0976 "Foolproof All-Butter Dough for
  Double-Crust Pie" (6 of 8 words; 669.1 g, 3,427.26 kcal; 586.77 a
  serving), lemon-meringue-pie|0 → 0972's "Basic Single-Crust Pie Dough" (4
  words against the double-crust host's 3; 302.1 g, 1,544.71 kcal; 435.07 a
  serving); +4,971.97 kcal; both complete.
- **RA1 (Q15 iii)** shipped in v49 ('frozen raspberries' ranks the cached
  FNDDS 2709282 "Raspberries, frozen", unflagged); WB is what makes the
  coulis a child, so its line is read now (680.39 g, 387.82 kcal);
  raspberry-charlotte|4 ('raspberry', 2346410) is unchanged.

A recipe holding a reference also hashes its ingredient group headings (SW
reads a CONDIMENTS one), and, for a line with no amount and no served-with
marker, the child whose lines decide WB against `no_amount` (a section or
library recipe listing none, or one made from a recipe; the 0 g rule row
ties no stamp): that child gaining or losing those lines stales the parent
at once, and one stale sweep settles it (no library hash moves). After v52 no library line reads `no_amount` or
`no_ingredients` (both stay valid wire reasons). Replay (rp43 + bucket_v12
on fresh copies of snapshot 21, main and `--reverse-parents` identical):
calls 0, sections 143; vs v51 exactly 5 main rows differ (3 WB, 2 PV) and
11 section rows are new, +7,113.00 kcal per batch; the six SW rows are
byte-equal as rows (their change is the accounting); 9 recipes partial →
complete (997 → 1,006); the partial recipes with nothing to review 9 → 0.
Deploy note: matcherVersion 51 stales every recipe; a zero-request sweep
recomputes the library.

**Since matcher v53 (batch M52, matcherVersion 52 — coats and frying-oil
uptake; prep47 design_v2 §1 Q2 (a), Q3 (a) and Q24 (b), §2 "M52", critic
F1, F2, F8 and F13, decided under the owner's 2026-10-07 standing
authorization; zero requests). RE-RULES checkpoint 9 Q2 ("dredging flour
and crumbs HELD until a coating fraction is set"), the 2026-10-03 (night)
(1) ("the four fried dredges … STAY HELD"), and, for a coated food browned
in the oil, the 2026-10-03 R4 "shimmering/smoking stays non-evidence";
AMENDS the discarded-media zero for frying oil, whose reason was "no
source gives a fraction".** USDA's FNDDS fried and baked coated recipes
give one: their `inputFoods` (breading 99995000, vegetable oil, the meat),
read at the live steps M53 and M55 (the running live total 137; snapshot
22), are transcribed in `.claude/diag/2026-10-07/prep47/p3_read_figures.md`
— every k and u below is that table's READ figure unless marked derived
(an analytical SR record with no `inputFoods`). The engine rewrites the
coat and frying-oil rows it weighs — its OWN (`auto`) rows and a person's
CONFIRM with no grams typed — wherever a recipe is totalled (a compute, a
person's write, an apply-to-all target), from the other rows as they
stand. A confirm is "this food at the engine's current weight" (RULE A):
it keeps the budget's or the uptake's grams the GET showed, as a confirm
keeps rule B1's two parts, and follows the coated or fried food's grams as
the engine's row would (a confirmed row is written only while it is still
the row read); a pick is one record at the line's weight (a pick on a coat
keeps its `coating` hold), and typed grams are the person's.

(1) **The coat (Q2 a).** A line the engine holds `coating` counts
f = min(1, B / Σ coat carbohydrate) of its dredge, B = k × the coated
food's grams / 100 grams of coat CARBOHYDRATE. The coated food is the
largest counted line on a meat, poultry or seafood record (descriptions
opening Chicken, Turkey, Pork, Beef, Ham, Fish, Crustaceans, Mollusks).
The recipe's reached coat lines share B by their carbohydrate (dredge
grams × the record's nutrient 205), so a fresh-bread breading counts more
grams than a flour dredge for the same carbohydrate; a written part eaten
outside the dredge counts on top, as before. The row is unheld,
`gram_source: discarded` (as a held medium's eaten part already is: the
excess is thrown away, the kept part counted — and the recompute finds the
plan's rows by it, reading no other line's detectors), its basis
`discarded in cooking — only the coat on the food counted` (a part eaten
outside the dredge: `only "{part}" and the coat on the food counted`, or
`only the part the recipe keeps and the coat on the food counted`) with
the flag
`· approximation (coat: {k} g carbohydrate per 100 g of the raw {food} —
USDA FNDDS {id} recipe: {b} g breading per {R} g raw {food}; the dredge's
excess not counted)` (C3: `… — derived from USDA SR Legacy 171982
"Mollusks, squid, mixed species, cooked, fried"; …`). f is the food's,
never a fraction of the line: checkpoint 9's "no blanket coating fraction"
stands (the `coatingFraction` switch stays null).

| shape | when (read from the recipe) | k | source |
|---|---|---|---|
| C1 fried | the recipe fries | 5.73 (breast and any other food), thigh 6.10, wing 5.66 | FNDDS 2705975, 2706047, 2706065 |
| C1d | a second dredge after the egg ("coat with flour again", 0148, 0304) | 8.79 | FNDDS 2705842 |
| C2 baked | a bake after the coat that is also after the last frying sentence — the LAST cook decides (critic F2: 0118's cutlets and 0149's chicken are browned or fried, then baked) | chicken 3.18, legs 3.10, fish 7.41, pork 6.61 | FNDDS 2705980, 2705998, 2706243, 2705871 |
| C3 | fried Mollusks or Crustaceans with no crumb line | 3.94 | SR 171982, derived |
| C5 | a fried fish a sentence batters; the recipe's counted flour and starch come off B (since matcher v57 also battered shrimp, each on its own record, and a batter's own lines are parts, never off B — below) | 15.38 | FNDDS 2706244 (v57: shrimp 2706364, haddock 2706258) |

Stay held (20 rows): C4 sautéed dustings (neither fried nor baked —
piccata, marsala, saltimbocca, meunière, francese, seared salmon and pork),
coats with no meat line (eggplant parmesan, oven-fried onion rings), and
nut and cheese layers (a Nuts or Cheese record) — since matcher v65 (M66
R3, below) only a layer no step sentence names with a crumb.

(2) **The frying oil (Q3 a).** A line the engine zeroes as frying oil
counts u × the fried food's grams / 100 ON TOP of its kept part (critic
F13: the M49-marked pour-off too — horseradish-crusted-beef-tenderloin|3
23.07 kept + 10.9 % × its 137.78 g potato = 38.09 g), capped at the line
less that part; two oils of one fry split by their grams (1133 Chicken Francese's
olive and vegetable oils). The fried food: in a recipe that holds a coat or
shallow-fries a coated food ((3) below) the coated food, plus every counted
vegetable a frying sentence names (0255's chips beside its cod); otherwise
the counted foods a frying sentence names — the frying verb or "to / in /
into (the) (hot) oil", a vegetable also any sentence naming it with "oil"
("Combine the potatoes, oil …", 0317), or a "Fried …" title (0706
Plátanos Maduros prints no steps) — never the largest protein (pastelon's
beef, steak-frites' rib-eye and the tostadas' pork are not fried in it).

| class | u, % of the raw food | source |
|---|---|---|
| O1a coated skinless breast or cutlet | 6.68 | FNDDS 2705975 |
| O1b thigh | 7.11 | FNDDS 2706047 |
| O1w wings | 6.61 | FNDDS 2706065 |
| O1c bone-in skin-on chicken | 0 | FNDDS 2705996, read fat balance (below) |
| O1d beef | 9.89 | FNDDS 2705842 (a beef with no held dredge — 0536's cornstarch-tossed strips — a stand-in) |
| O1e pork; salmon and any other food (crab until matcher v62) | 6.68 | FNDDS 2705975, stand-in |
| O1k crab (since matcher v62, M63) | 7.69 | FNDDS 2706549 "Crab, cake" |
| O2 battered cod, haddock | 15.38 | FNDDS 2706244, 2706258 |
| O2s battered shrimp | 15.38 | FNDDS 2706364 |
| O3 floured squid or shrimp (a C3 coat) | 5.3 | SR 171982, derived |
| O4 potatoes | 6.0 | SR 170698, derived |
| O4c chips (a grated or shredded potato, or steps saying "chips") | 10.9 | SR 19411 "Snacks, potato chips, plain, salted" (FNDDS 2709422's one input), derived |
| O4p plantains | 5.5 | SR 168200, derived |
| eggplant, sweet potatoes | 6.0 | SR 170698, stand-in |
| O5 battered cauliflower | 30.32 | FNDDS 2710042 |
| O6 corn tortillas | 13.4 | SR 167525, derived |

The flag: `· approximation (frying oil absorbed: {u} % of the raw {food}'s
weight — USDA FNDDS {id} recipe: {o} g oil per {R} g raw {food})`, derived
`… — derived from USDA SR Legacy {id} "{description}"`, a stand-in adding
` (no record for {food}; read as {record})`, several fried foods joined by
"; "; the basis `discarded in cooking — only the oil the fried food absorbs
counted` (with a kept part `only "{part}" and the oil the fried food
absorbs counted`, or `only "{part}", the {kept} the steps keep and the oil
the fried food absorbs counted`). O1c's basis, 0 g: `frying oil: 0 g — USDA
FNDDS 2705996 recipe adds 7 g oil per 100 g, but the fried skin-on parts
carry less fat (17.2 g) than the raw parts counted here: no net uptake`
(crispy-fried-chicken|7, easier-fried-chicken|10). Stay 0: doughs and
batters fried whole (doughnuts, struffoli, falafel, pakoras, lumpia —
until matcher v60, M61 below, counts their uptake on the raw mix),
tempeh (its 28 g kept part counted), confit, yuca (no nutrients), and the
strained-and-kept shallot oil (no uptake; since matcher v63, M64, the ¼ cup
its yield prints as not poured out is counted).

(3) **Q24 (b) — a coated food browned in the oil.** An oil of ¼ cup or
more (or a line the mass rule could zero) that a sentence heats after a
sentence coating a food in flour, starch or crumbs, one of the next three
sentences browning, is that food's frying oil (engine `_shallowFries`; a
sauté's "Heat 2 tablespoons oil" is none): exactly five lines —
stuffed-chicken-cutlets-with-ham-and-cheddar|12 (its eaten tablespoon
kept), chicken-katsu|4, easy-salmon-cakes|11, maryland-crab-cakes|9 (from
`ambiguous_medium`) and best-chicken-parmesan|19 "⅓ cup vegetable oil"
(0415, katsu's twin: coated in crumbs, the oil heated "until shimmering",
the cutlets cooked "until … deep golden brown"; the design's list of four
came from a probe of oils of 100 g or more, and 0415's is 74.67 g — the
fifth oil was ruled in under the standing authorization). The dredge
cascade (critic F1): katsu|0 "2 cups panko" is now a held dredge,
budgeted C1 (118.29 → 63.19 g); easy-salmon-cakes|0 is no dredge (its
first amount, 3 tablespoons, is under ¼ cup) and is byte-equal — held, its
C1 budget would give f = 1 (32.49 g carbohydrate against the ¾ cup's
31.93). Stuffed-chicken-cutlets|10 and |13 read C2 by the last cook.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 22, main and
`--reverse-parents` byte-identical): calls 0, staleAfter 0, sectionsStale
0, kcalCheck 0, sections 143; vs the v52 rows exactly 70 rows differ, all
`auto`, 0 section rows: 31 coat rows +4,504.08 kcal, the katsu cascade
−217.66, 30 uptake rows +16,474.71, 2 O1c rows (basis only), horseradish|3
+135.19, the five Q24 oils −2,495.76; +18,400.56 kcal per batch; 16
recipes partial → complete (1,006 → 1,022), none down; buckets `coating`
51 → 20, `ambiguous_medium` 3 → 2, check 189 → 157. Deploy note:
matcherVersion 52 stales every recipe; a zero-request sweep recomputes the
library.

**Since matcher v54 (Q25 — alcohol cooked off; matcherVersion 53;
prep47 design_q25_v2, decided under the owner's 2026-10-07 standing
authorization with his Q-a..Q-h; zero requests).** A counted row on one of
the sixteen alcohol records (FNDDS wine white 2710689 / red 2710688 / rosé
2710690 / rice 2710691 / dessert sweet 2710692, beer 2710616, brandy
2710699, whiskey 2710700, vodka 2710704, rum 2710703, tequila 2710705,
liqueur 2710623; SR wine dessert dry 175112, Pinot Noir 174835, Riesling
173200, sake 167723) keeps its record and grams; only its energy changes.
Its ethanol energy per 100 g is the record's energy less the Atwater energy
of its protein, fat and carbohydrate (4/9/4, FDC 203/204/205 as cached) —
6.82–7.01 kcal per g of the record's measured ethanol (FDC 221, which the
engine never reads; FDC's factor 6.93; never 208 − 7 × 221, which leaves a
spirit −2.80 kcal of non-ethanol energy) — and the totals count that share
times the fraction the dish keeps, from the USDA Table of Nutrient
Retention Factors, Release 6 (2007), group 14, "Alcohol, ethyl":

| shape (read from the line's own steps) | kept | USDA |
|---|---|---|
| stirred into a hot liquid and off or served at once; under one printed minute; stirred in OFF the heat into a hot dish (Q-f) | 85 % | 5002 |
| heated with no time printed ("roast until … 160 degrees") | 85 % | 5002 |
| stirred in and simmered, braised or baked under 15 min (Q-a) | 85 % | 5002 |
| poured over or around a food and baked, not stirred, any length (Q-g) | 85 % | 5002 |
| flamed | 75 % | 5003 |
| stirred in and simmered or baked 15 / 30 / 60 / 90 / 120 / 150+ min | 40 / 35 / 25 / 20 / 10 / 5 % | 5004–5009 |
| flamed, then 15 min or more | the lower of 75 % and the time row | |
| no heat; a marinade or medium poured away, a beer can (the mass rules' hand-offs, Q-h); a sealed pressure cooker; no steps | 100 %, unflagged | |

The minutes are the printed durations of the heat the line stays in — a
range at its LOW end (Q-a2), alternatives the shorter, an optional "if
necessary" step none — following the line: into the vessel it is put in,
strained into a pan and reheated, back to the heat after a removal, a cold
premix from the moment it is put into a hot pan (never a pan's roux or
another food cooked beside it while the line waits in its bowl), a batter
or a dough at its own bake or fry; a side task ("Meanwhile, …", another
or a now-empty vessel, boiling water, a microwave) adds none. One line used
twice is split by the amounts the steps print, weighted by volume. A
stuffing rolled or wrapped inside a roast is not cooked by the roast (the
D1 ruling: those roasts print a rare doneness, 85–120 °F) — it keeps what
its own cook left. A person's typed grams are reduced the same way:
retention applies to whatever grams count and never changes them. A held
row counts nothing, reduced or not. Carbohydrate, protein and every other
nutrient are unchanged; the label shows no ethanol. Derived at compute from
the recipe's steps (already in the ingredients hash), never stored. The
row's `flag` (the composite channel, joined with " · " to another, kept on
a Confirm) says so, as the owner approved the forms (Q-e):

- `approximate (USDA retention: alcohol cooked {N} min keeps {f} %)`; at
  150 min and more `… keeps 5 %, the table's 2½-hour figure)`; under 15
  `… keeps 85 %, the stirred-into-hot-liquid figure)` — since matcher v65
  (M66, the owner's Q8 (b)) a batter left in the bowl and fried in oil adds
  `… figure (USDA prints no row for a batter fried in oil))`
- `approximate (USDA retention: alcohol stirred into hot liquid keeps 85 %)`
  — 5002's own row: boil-off, a sub-minute heat, and (Q-f) a line stirred
  in off the heat into a hot dish
- `approximate (USDA retention: alcohol heated, time not printed, keeps 85 %)`
- `approximate (USDA retention: alcohol flamed keeps 75 %)` and `… alcohol
  flamed, then cooked {N} min keeps {f} %)`
- `approximate (USDA retention: alcohol poured over and baked {N} min keeps 85 %)`
  ({N} the oven's minutes)
- a split: `approximate (USDA retention: {part} {use}; {part} {use})`, each
  use the forms above after "alcohol" without a figure's suffix, an off-heat
  part `{part} stirred in off the heat keeps 85 %` (the approved split form
  at Q-f's figure).

The owner's decisions (design §9): Q-a under 15 min reads 85 %, no
extrapolation; Q-a2 a cooking-time range at its low end; Q-b 5001 (70 %,
stored overnight) unused; Q-c covered braises and slow cookers read the
open-pot rows; Q-d vanilla extract stays out (a 17th record counts its
full energy until added); Q-e the flag forms; Q-f stirred in off the heat
into a HOT dish IS 5002 (85 %) — a line added to a dish that is not hot
keeps 100 %; Q-g the 5010 pour-over row (45 % at 25 min) dropped; Q-h the
hand-offs. Closer1's rulings under the standing authorization (D1, the
owner confirming at the gate): shrimp-scampi|5 is Q-f's shape (85 %);
modern-beef-burgundy|9 weighs its parts by volume (17.92 %);
broiled-chicken-with-gravy|11 reads 20 + the strained stock's 5 = 25 min
(40 %); the stuffing rule above (beef-wellington|14 and 0216|7 at their own
2 min, 85 %); and two table rows the hand reading corrected:
strawberry-rhubarb-pie|5 25 + 30 = 55 min (35 %, not 25 %) and
summer-peach-cake|1 split 2 T on the wedges baked 50 (35 %) and 3 T on the
chunks roasted 20 then baked 50 (25 %): 29.0 %.

Replay (rp54 — rp43 whose row kcal applies the retention — + bucket_v12 on
fresh copies of snapshot 22, main and `--reverse-parents` byte-identical):
calls 0, staleAfter 0, sectionsStale 0, kcalCheck 0, sections 143; vs the
v53 rows exactly 225 rows differ, only in their kcal and `flag` columns
(every other column byte-equal, 0 person rows): 212 main alcohol rows
−14,584.27 kcal per batch, 7 section rows −1,093.57 per section batch, and
the 6 parent rows routed to those sections (their kcal and the basis that
prints the child's kcal) −1,042.43; 201 recipes move (196 by their own
rows, 5 by a section), only in kcal per serving; statuses, buckets and
holds identical. The audited cases: crisp-skin turkey's Turkey Gravy 90 min
(20 %, −267.28 a batch), the herb sauce's Sauce Base 25 min (40 %, its
parent −104.39). Deploy note: matcherVersion 53 stales every recipe; a
zero-request sweep recomputes the library.

**Since matcher v55 (batch M56 — meat records at the right animal, cut and
fat level; matcherVersion 54; prep48 design_v2 §2 M56, decided by the owner
2026-10-08 under the standing authorization: Q1 (a), Q2 (i), Q3 (a), Q5
(a), Q7; critic F2, F11, F12; zero requests).** Three rules, each landing a
record a cached answer already holds; grams never move.

- **R1 — rank-as items** (each target the named answer's top under these
  words on snapshot 23; unflagged — the line's own cut on its own animal):

| item | reads answer | under | record |
|---|---|---|---|
| `boneless top loin roast` (R1a; "Top loin roast is also known as strip roast", a Beef title — it led with PORK 168314) | `strip steaks` | `beef short loin ny strip steak raw` | Foundation 2727572 *Beef, short loin (NY strip steak), raw* |
| `boneless strip steak(s)` (R1c; they read the Foundation LEAN-ONLY 746759 by its data-type bonus) | `strip steaks` | the same | 2727572 |
| `blade steak(s)` (R1b; beef in both recipes — it led with PORK 167849) | its own | `beef shoulder top blade steak boneless separable lean and fat trimmed to 0 fat choice raw` | SR 168707 (carbonnade's top blade record) |
| `beef brisket` (R1d; FNDDS 2705851 is a COOKED record, "1 oz yields 20 g", counted on raw weights) | its own | `beef brisket flat half boneless separable lean and fat trimmed to 0 fat choice raw` | SR 168743, the raw flat at 0" |
| `boneless center-cut pork loin roast`, `center-cut boneless pork loin roast`, `boneless center loin pork roast` (R1e, Q5 (a); they read SR 167889, the center RIB) | `boneless center-cut pork loin roast` | `pork loin boneless raw` | Foundation 2646168 *Pork, loin, boneless, raw* |

  **R1d's default is 0" when no depth is printed** (USDA publishes the flat
  at 0" and 1/8"; three of the four brisket lines print none). A brisket
  line printing "fat trimmed to ¼ inch" on 168743 (braised-brisket-with-
  pomegranate|0) says it stands in, in its basis, whoever chose the record:
  `approximate (the printed ¼-inch fat cap renders and is skimmed (step 5);
  counted as the 0-inch trimmed flat)` (Q2 (i), F2) — the 1/8" record
  (173128) is not read for it (Q2 (ii), deferred to a rendered-fat item).
- **R2 — the lean-and-fat sibling** (`leanAndFatSibling`, after the
  fresh-over-cured move, so after R1): a top whose description says
  "separable lean only", on a line that does not say `lean`, "trimmed of
  all fat" or "all visible fat", yields to its EXACT sibling in the same
  answer — the description with "lean only" read as "lean and fat" or "lean
  and fat only", case and spacing folded — at the top's confidence (the
  owner's tie-break "the cut's lean-and-fat record over 'lean only'" read
  past an exact tie). The blade-end pork loin roasts 169194 → 168381 (4
  rows), the eye-round roast 746760 → 171747. R1c runs first: by R2 alone
  the seven strip rows would land 173072 (Q1 (b), declined).
- **R3 — a printed trim** (`trimDepthRecords`, after R2, keyed on the top's
  record; the target a hit in the line's own answer): "fat trimmed to (⅛|¼)(
  to (⅛|¼))? inch" on NZ 172641 → Australian 174414 *rib chop/rack roast,
  frenched, bone-in, lean and fat, trimmed to 1/8" fat, raw*, weighed by
  172641's AH-102 item 1364 row (`ah102Meats[174414]`, verbatim); "fat
  caps? removed" on 2727572 → 171751 *top loin steak, boneless, lip off,
  lean and fat, trimmed to 0" fat, choice, raw* (Q7; keyed on 2727572, so it
  lives only under R1c, F12). Brisket pairs are not here. At M56 174414
  was a search hit only (snapshot 23 held no detail of it), so the rack read
  the AH-102 row ON THE HIT (`ah102MeatsOnHit`), assuming the detail
  publishes no refuse portion. Live step L cached the detail (snapshot 24):
  its portions are 'oz' and 'chop', no refuse portion — the assumption
  holds, and **M63 retired the set** (below): the rack's weight line reads
  the cached detail like every other `ah102Meats` key and lands the same
  row, byte-equal (1,241.71 g, 2,942.85 kcal).

Reach: 26 rows, −3,991.96 kcal per batch (design −3,991.94): R1a 1 (+599.86),
R1b 2 (−848.21), R1c 7 (+2,185.70, ultimate-charcoal|0 then −172.78 by Q7),
R1d 4 (−5,132.39), R1e 6 (−2,974.42), R2 5 (+1,505.92), R3 1 (+844.36).
Unreached by design: steak-au-poivre|4 and steak-diane|0 (already
2727572), carbonnade|0 (168707), the flat-iron rank-as (172125), the shanks
on lean-only 169441 (no lean-and-fat shank cached; their AH-102 228 flag
says so), the three top-sirloin roasts on lean-only 173408 (no sibling
cached; Q6's live search first), grilled-rack-of-lamb|5 (no printed depth),
the whole brisket on 168607, the oxtails ("¼ inch or less") and the pork
rib roast ("¼-inch thickness").

Known USDA-vs-judgment gaps (design §7 — the source stands, listed, never
overridden): rendered and skimmed fat on long cooks (the brisket's ¼-inch
cap, R12's short ribs; Q2 (ii)); the top loin roast's trimmed side strips
(a grams question); the rack on two records by whether a depth is printed
(origin and frenching differ too, F11); strip steaks at 2727572's 190.04
against the audit's 196; thighs on Foundation 2727567 (Q4); a COUNT strip
line would find no portion on 2727572 (none in the corpus).

Replay (rp43 + bucket_v12 on fresh copies of snapshot 23, main and
`--reverse-parents` byte-identical; STEP ZERO the v54 tree reproduces the
v54 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the
v54 rows exactly the 26 rows differ — record, description, confidence
(R1 rows 1.0; R2/R3 keep the top's), kcal, and pomegranate|0's basis; 0
person rows; 26 recipes move only in kcal per serving; statuses, sections,
buckets and holds identical. Deploy note: matcherVersion 54 stales every
recipe; a zero-request sweep recomputes the library.

**Since matcher v56 (batch M57 — a strain of "the liquid" whose solids
nothing uses; matcherVersion 55; prep48 design_v2 §2 M57 S1, critic F4 and
F14, decided by the owner 2026-10-08 under the standing authorization; Q19
NO; zero requests; step-reading, so its reach is pre-Q18).** M50's strained
solids (Q16 above) also read a strain of **"the liquid"**: a step sentence
matching `strain (the) (braising |cooking |poaching )liquid` ("strain the
liquid through a fine-mesh strainer into a bowl", "Strain liquid through
fine-mesh strainer into large bowl") is the recipe's strain when **no
sentence from it to the end of the steps names `solids`, `vegetables`, a
`blender`, a `food processor` or a `purée`** (the later-use guard: the pot
roasts blend their vegetables, the oxtails "return solids to now-empty pot",
carne deshebrada "Transfer remaining solids to blender" — eaten, so not
strained out). Figure and flag are M50's: its aromatic vegetables, herbs
and whole spices count 0 g
(`discarded`, the M50 Q16 policy — no new figure), `gram_basis` the shipped
strained-solid text byte for byte (`"discarded in cooking — counted as 0 g ·
approximate (strained out and discarded — what it gives the liquid is not
counted)"`), with every shipped guard unchanged (first own mention before
the strain, named again after it, the vessel guard, lifted-out vegetables,
the sheet, "meanwhile", the line blended smooth, ground/powder/paste). The
older strains (pressing on or discarding the solids, a stock or broth) are
read first, unchanged. A strain of the liquid the guard rejects **continues
the scan** — never ends it — so a later pressing strain is still the
recipe's strain (critic F14). Prunes are not a strained head (Q19 NO: the
short ribs' background says they melt into the sauce).

Reach: 4 rows, −591.09 kcal per batch — slow-cooker-beer-braised-short-ribs
|4 onions 1,360.78 → 0 g (−517.09) and |10 bay (−1.25); turkey-thigh-confit
|7 garlic 50 → 0 g (−71.50) and |8 bay (−1.25). The ribs read 1,080.67 kcal
per serving (was 1,210.25), the confit 510.86 (was 522.99); both stay
complete. Kept by the shipped guards: the ribs' prunes (96.00 g), the thyme
and parsley named after the strain, the confit's onions (processed in the
food processor). daube-provencal's porcini soak is now its strain; every
daube row stays as it was (the porcini are named again after the soak;
every other strained head is first named after it).

Known gaps (design §7 — the source stands): what a strained solid gives the
liquid (the flag says so); R12's short ribs stay +14.3 % over the
calibration (the prunes counted, the braise's rendered fat — Q2 (ii)'s
item); turkey-thigh-confit's rinsed cure ("rinse well", its |0 onions and
|3 sugar) is not read by the rinsed-cure reader — a later discard pass; the
corpus lost the steps of 269 subsections (Q18), which this step reader
cannot see.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 23, main and
`--reverse-parents` byte-identical; STEP ZERO the v55 tree reproduces the
v55 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v55
rows exactly the 4 rows differ — grams, basis and kcal; 0 person rows;
statuses, sections, buckets and holds identical. Deploy note:
matcherVersion 55 stales every recipe; a zero-request sweep recomputes the
library.

**Since matcher v57 (batch M58 — a batter left in the bowl joins the coat
budget; matcherVersion 56; prep48 design_v2 §2 M58 W + S + the negimaki
flag, the owner's Q8 (carbohydrate, and battered shrimp on its own record)
and Q10 (negimaki's glaze whole) and critic F10, decided 2026-10-08 under
the standing authorization; zero requests; step-reading, so its reach is
pre-Q18).** AMENDS M50 Q21 (D5, "flags only, no grams move") for a batter:
(W) the lines a batter leaves in the bowl — the D5 reader's lines reached
through the dip word **batter** ("allowing the excess batter to drip
off", "allowing any excess batter to drip back into bowl", "dip … in the
batter and let the excess run off") — join M52's coat (1) as parts when the
recipe has a coated food and a shape: each line's dredge is its WHOLE
grams, none eaten outside it, its carbohydrate its record's (nutrient
205); every part — flour, starch, leavening, spice, egg, beer, spirit,
seltzer — counts f × its grams at the coat's ONE f = min(1, B / Σ coat
carbohydrate) (a batter is one mixture; f is fixed by the read k, no new
figure). A C5 budget no longer subtracts a batter line's carbohydrate
(fish-and-chips' flour, already a coat part, rises as its starch and beer
join the parts). C5 now also reads `Crustaceans, shrimp` with a batter
sentence (before the C3 test), and its k is the battered food's own read
record: shrimp FNDDS 2706364, haddock 2706258, else cod 2706244 (all
15.38 — 25 g breading per 65 g raw; since matcher v65 the flag says
`25 g breading (USDA 99995000, 40.1 % carbohydrate) per 65 g raw …, matched
by its carbohydrate`, M66 below); battered shrimp's uptake stays O2s.
The rows are `gram_source: discarded`, basis `discarded in cooking — only
the coat on the food counted`, the D5 flag dropped, the coat flag reading
`… ; the batter's excess not counted)`. A person's Confirm of a batter
line keeps the plan's grams, `discarded`, as a coat's does. Egg, glaze,
chocolate, coating and dough dips are not W (E is M62, below). (S, flag only) A
coat figure READ on another food says so, as the uptake clause does:
`… {b} g breading per {R} g raw {food} (no record for {coated}; read as
{record})` — crispy-fried-chicken|8 (chicken on the country-fried steak),
crispy-pan-fried-pork-chops|0, pork-schnitzel|0 |1 (pork on the fried
breast), maryland-crab-cakes|8 (crab on the fried breast); a derived C3
figure says nothing new. A W batter read on a C1/C2 breading figure adds
` (a batter read on a breading figure)` (F10: dakgangjeong|8 |9 on the
wing's 5.66). (Q10, flag only) A glaze the steps divide evenly between two
bowls, one served and the other brushed on with its rest discarded
(negimaki|1–|4), is counted whole with `· approximate (the steps divide the
glaze evenly between two bowls — one half served, the other brushed on and
its rest discarded; counted whole)` in place of the D5 flag.

Reach: 17 rows move grams (−1,376.44 kcal per batch at the Q25 factor):
shrimp-tempura |2 flour 212.62 → 99.71, |3 63.88 → 29.96, |4 vodka 224.00
→ 105.05 (its 85 % Q25 flag kept), |5 egg 50.00 → 23.45, |6 seltzer 236.59
→ 110.95 (0 kcal) — f 0.4690; crispy-fish-sandwiches |6 |7 |9 |10 — f
0.7795 on haddock 2706258; dakgangjeong |8 120.66 → 40.36, |9 23.95 →
8.01 — f 0.3345; fish-and-chips |2 59.95 → 89.12, |3 63.88 → 31.45, |4,
|5, |8, |10 beer 340.19 → 167.52 — f 0.4924. 9 rows move their flag only
(S's five, negimaki's four). Per serving: tempura 381.94 → 280.02 (stays
partial), dakgangjeong 601.62 → 512.96, the sandwiches 1,057.75 →
1,028.23, fish-and-chips 1,003.49 → 981.40; no status moves.

Known gaps (design §7 — the source stands): tempura's coat at FNDDS's 25 g
breading per 65 g against the recipe's heavier batter; the flour, starch
and liquid split pro rata by carbohydrate (no source splits a batter); a
batter wetter than FNDDS's ~40 %-carbohydrate breading keeps more mass by f
than FNDDS's 25 g (Q8's mass option left aside); crab cakes and pork read
the breast's figure (S says so) until a read gives their own; the corpus
lost the steps of 269 subsections (Q18), which this step reader cannot
see.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 23, main and
`--reverse-parents` byte-identical; STEP ZERO the v56 tree reproduces the
v56 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v56
rows exactly the 26 rows differ (17 in grams, source, basis and kcal; 9 in
basis only); 0 person rows; statuses, sections, buckets and holds
identical. Deploy note: matcherVersion 56 stales every recipe; a
zero-request sweep recomputes the library.

**Since matcher v58 (batch M59 — the frying oil the steps keep or rinse
off, and a battered vegetable's uptake; matcherVersion 57; prep48
design_v2 §2 M59 C + F1 + D, the owner's Q13 (b) and critic F1, F9 and F12,
decided 2026-10-08 under the standing authorization; zero requests;
step-reading, so its reach is pre-Q18).** (C) A frying oil's kept part
(M49) has a second printed form: **"reserve N {teaspoons|tablespoons|cups}
(frying) oil"** in a sentence the oil line owns, counted only when a LATER
sentence heats **"reserved oil"** ("After frying, reserve 2 tablespoons
frying oil." … "Heat reserved oil in 12-inch skillet"); the shipped
"reserve … and discard the remainder" form is unchanged, and a reserve no
later sentence heats ("Reserve 3 tablespoons oil mixture", brushed on in
0661) is not read.
The part is weighed as the line is (2 tablespoons = 28.00 g on 2710180's
portion, 14.00 g a tablespoon) and M52's uptake lands on top; the basis is
the shipped kept-part one, `discarded in cooking — only the part the recipe
keeps and the oil the fried food absorbs counted`. (F1) A frying oil's
eaten part ("plus ¼ cup") is NOT eaten when the sentence naming it
**tosses** it with a food ("toss with ¼ cup of the oil") and LATER sentences
of the same step **drain** and **rinse** ("… drain the potatoes into a
large mesh strainer … Rinse well under cold running water") — 0 g, by CP9's
rinsed-cure precedent; a rinse before the toss, or a drain with no rinse,
keeps the part. No food is matched: the step stands in for the tossed food
(0255's rinse sentence names none, and its drain names "potatoes" where the
toss names "fries"), so a step draining and rinsing ANOTHER food after the
toss zeroes the part too (no corpus step tosses an oil and later drains and
rinses anything but 0255's). The basis reads `discarded in cooking — only
the oil the fried food absorbs counted ("plus ¼ cup …": the steps rinse it
off)`, naming a kept pour-off part beside the uptake when the steps keep
one (`only the 1 tablespoon the steps keep and the oil the fried food
absorbs counted (…: the steps rinse it off)`); the rinsed part is never
named as counted. (D) The fried cauliflower's uptake (O5, FNDDS 2710042: 12 g oil per
39.58 g raw cauliflower under 50 g batter — 1.26 g of batter a gram, every
other read record ≤ 0.38) scales to the batter the recipe carries: u ×
min(1, C / K), C = the carbohydrate (nutrient 205) of the counted rows of
the cauliflower's ingredient group other than the cauliflower (the frying
oil is `discarded`, never counted; a batter left in the bowl at its whole
grams), K = b × c_b / R × the cauliflower's grams, c_b = 0.40 (the FNDDS
breading's carbohydrate per gram, 0.397–0.401
on six read recipes, p3_read_figures.md). Flag: `approximation (frying oil
absorbed — derived: {u'} % of the raw cauliflower's weight — USDA FNDDS
2710042 recipe: 12 g oil per 39.58 g raw cauliflower, scaled to the
recipe's batter ({C} g of {K} g carbohydrate))`. Every other uptake keeps
its read figure.

Reach: exactly 4 rows (−578.07 kcal per batch): crispy-salt-and-pepper-
shrimp|7 36.06 → 64.06 g (+252.00), crispy-orange-beef|8 67.29 → 95.29
(+252.00; its toasted sesame oil |7 stays 6.80), fish-and-chips|1 226.78 →
170.78 (−504.00: the ¼ cup, 56.00 g, rinsed off; 15.38 % of the cod + 6.0 %
of the potatoes stay), buffalo-cauliflower-bites|4 137.53 → 73.30 (−578.07:
16.16 % = 30.32 × 122.16 / 229.20). Per serving: the shrimp 303.34 →
366.34, the beef 536.09 → 599.09, fish-and-chips 981.40 → 855.40, the
cauliflower 760.67 → 616.15; no status moves. The noodle oils the steps
rinse THEN oil (sesame-noodles|11, thai-style-stir-fried-noodles|5,
shrimp-pad-thai|6) are not frying oils and stay.

Known gaps (design §7 — the source stands): stuffed-chicken-cutlets|12
stays on O1a (Q13 a); shrimp-tempura|0's uptake at FNDDS's own ratio
against the recipe's heavier batter; D reads a batter left in the bowl
(M58 W) at its whole line grams on every path — a compute, a recompute, a
GET — though the coat budget counts only its share on the coated food, so
a batter shared with a coated food over-reads C (none on O5); the corpus
lost the steps of 269 subsections (Q18), which these step readers cannot
see.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 23, main and
`--reverse-parents` byte-identical; STEP ZERO the v57 tree reproduces the
v57 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v57
rows exactly the 4 rows differ, in grams, basis and kcal only; 0 person
rows; statuses, sections, buckets and holds identical. Deploy note:
matcherVersion 57 stales every recipe; a zero-request sweep recomputes the
library.

**Since matcher v59 (batch M60 — the bone-in turkey breast, a peel written
in the steps, bacon that drips; matcherVersion 58; prep48 design_v2 §2 M60
Y + P7a + P7b, the owner's Q14 (a) and Q15 (a) and critic F8 and F15,
decided 2026-10-08 under the standing authorization; zero requests; P7a
and P7b read steps, so their reach is pre-Q18).** (Y, closing Y7) A
bone-in turkey breast on SR 171093 (now in `ah102Records`, meat and skin)
reads `ah102Parts`' **turkey breast**: ATK's retail cut is the breast with
its upper back (rib) attached — six of the eight recipes cut or trim the
back away before cooking (both roast-whole recipes keep it for the gravy,
grill-roasted and porchetta save the bones for stock or discard them, the
crowd recipe names no use, en-cocotte trims the rib bones) and the other
two (braised, slow-roasted) print nothing on it — so the
figure is DERIVED from AH-102 item 2591's fryer-roaster carcass shares
(breast 33, rib 10) × item 2593's breast meat and skin 87 % (85–89):
33 × 87 % / 43 = **66.77 %** (meat 78 % → 59.86 %, which no record reads).
Basis `… × 0.67 edible · approximate (derived from USDA AH-102 items 2591
and 2593, fryer-roaster class: a breast sold with its upper back (rib)
attached — the breast's meat and skin, 87 % (85–89) of its 33 of 43 parts,
66.8 %; the back is not counted)`; `boneInClassYields[171093]` (the
chicken's 0.608) is deleted. (P7a) A produce line on a `produceYields`
record whose printed weight is in its HEAD and whose TAIL names no prep
word takes the record's **peeled** figure when a step sentence BEGINS with
the paring act — `^(using …,)? (peel | pare | remove (the) skin)` ("Peel,
halve, and core pears."; "Using sharp vegetable peeler or chef's knife,
remove skin and fibrous threads from squash …") — names the line's head
noun, prints no count of it smaller than the line's ("Peel, core, and cut
1 apple" pares one of 7; a line with no count has none to compare, so any
printed count holds it back), and follows no sentence that cooks it (boil,
simmer, steam, roast, bake, microwave, cook with the noun: the mashed
potatoes peeled after the simmer keep their printed weight — AH-102 prints
no cooked-pare row). The flag adds `; the steps peel it` (`… approximate
(USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % (75–88);
the steps peel it)`); a tail prep word still wins, and a line saying
"unpeeled" never reads a step. (P7b) Bacon on SR 168277 that rule B1
leaves unrendered (no lift-out-and-pour-off step), under B1's own gates,
whose steps arrange, lay, drape or shingle the bacon OVER a food (not a
towel, plate, sheet, rack or pan) or WRAP a food with or in bacon, and a
LATER sentence bakes, roasts, grills or broils, is B1's two parts with no
fat kept: [168322 raw × 0.33, 172345 0 g] (AH-102 item 1981; the fat drips
off the food, nothing serves it). Flag `approximate (USDA AH-102 item 1981:
bacon, sliced, all methods → cooked 33 % (18–43); the fat drips off the
food)`; the basis is B1's (`198 g raw → 65 g cooked bacon + 0.0 g bacon
grease kept in the pan`). Cost (RULE C at the editor caps): the drip and
B1's kept-fat reading (`_baconKept`, shipped in v41 and read per bacon row)
are read once per recipe, the lay and wrap tests in one pass over each
sentence's tokens (the first "over" a laid bacon reaches — what the lay
regex's first match captured; a seeded comparison pins the two equal);
the peel is read once per head, its sentences found by the step index's
naming lookup and each sentence's paring and cooking acts read once — so
the noun is named as every detector names a head (a "-y" head by its "-ies"
plural, never after "garlic ") and counted in the same forms. No corpus
row moves; a 400-line bacon compute at the caps fell from 5.3 s to about
1 s, and the drip read no longer costs 7 s a bacon line.

Reach: exactly 13 rows (+693.10 kcal per batch on the replay; design §2's
+693.11 summed en-cocotte's rounded grams): the 8 rows on 171093 —
roast-whole-turkey-breast-with-gravy|0, roast-whole-turkey-breast-with-
gravy-2|0, slow-roasted-turkey-with-gravy|6, braised-turkey|2,
grillroasted-boneless-turkey-breast|1 1,656.00 → 1,817.11 g (+252.94 each),
turkey-and-gravy-for-a-crowd|16 3,036.00 → 3,331.37 (+463.73),
turkey-breast-en-cocotte-with-pan-gravy|0 1,794.00 → 1,968.54 (+274.02),
porchetta-style-turkey-breast|8 2,070.00 → 2,271.39 (+316.18);
roasted-butternut-squash-with-browned-butter-and-hazelnuts|0 1,247.38 →
1,047.80 (−96.06), pear-walnut-upside-down-cake|4 680.39 → 530.70
(−100.29), best-baked-apples|0 1,190.68 → 928.73 (−154.22);
meatloaf-with-brown-sugarketchup-glaze|17 198.45 g raw → 65.49 g cooked
(−473.40), grilled-bacon-wrapped-scallops|0 336.00 → 110.88 (−801.56).
Kept: the turkey leg quarters, thigh and whole birds; the two mashed
potatoes (907.18 g); grill-roasted-beef-tenderloin|5 (a skewered stack
for smoke over no food — a fate, not a yield); smothered-pork-chops|0;
tartiflette|2 (already B1); oven-fried-bacon|0 (`steps: []` in the corpus —
it waits for Q18).

Known gaps (design §7 — the source stands): 2591's shares are the
fryer-roaster class applied to heavy toms (bounded above by 2593's 87 %);
butternut at USDA's 84 % against ATK's ⅛-inch-deep peel; the meatloaf's
top absorbs some bacon fat no USDA figure measures (F15), so it errs low;
the corpus lost the steps of 269 subsections (Q18), which these step
readers cannot see.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 23, main and
`--reverse-parents` byte-identical; STEP ZERO the v58 tree reproduces the
v58 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v58
rows exactly the 13 rows differ (grams, basis and kcal; the two bacon rows
also their parts and flag); 0 person rows; statuses, sections and holds
identical; the composite count of two-part rows 18 → 20 (the two bacon
rows take B1's shape). Deploy note: matcherVersion 58 stales every recipe;
a zero-request sweep recomputes the library.

**Since matcher v60 (batch M61 — fried doughs, fritters, rolls and falafel
take an uptake; matcherVersion 59; prep48 design_v2 §2 M61, the owner's
Q12 and rulings R-a … R-e, decided 2026-10-08 under the standing
authorization; zero requests — the records were read at live step L1;
step-reading, so its reach is pre-Q18).** An unheld `discarded` frying oil
whose recipe has no counted line as the fried food (M52's list empty, not
O1c) counts the uptake of the PRODUCT a frying sentence (a `fry`, or a food
put "to / in / into (the) (hot) oil") names — the first of **lumpia, egg
roll(s), spring roll(s), pakora(s), fritter(s), falafel, struffoli,
doughnut(s), batter, dough** a frying sentence holds (engine
`_friedProductOf`; the word elsewhere, "While struffoli cool", is not
read). The fried weight is the **raw mix**: the counted rows of the oil
line's ingredient group before it (Q12 ii; water carries no record; a
dipping-sauce group before it and a glaze or sauce group after it never
join). Each product's figure (u, the oil absorbed per 100 g of raw mix):

| product | record | u | how |
|---|---|---|---|
| pakoras | FNDDS 2710066 "Pakora" | 8.43 % | READ: 21 g oil per 249.18 g of its raw inputs other than the oil and 355.5 g of water |
| fritters, a bare batter | 2710066, a stand-in | 8.43 % | the same read, flagged `(no record for fritter batter; read as Pakora)` for fritters, `(no record for batter; read as Pakora)` for a bare batter |
| lumpia, spring rolls, egg rolls | FNDDS 2708702 "Egg roll, with beef and/or pork" (a stand-in but for egg rolls) | 7.62 % | READ: 8 g oil per 104.99 g — its prepared vegetable egg roll at the listed 90 g (no raw pair), its 10 g of pork steak (2705875) brought to raw by protein on the lumpia's own raw pork (2514745): 14.99 g |
| struffoli; a doughnut or dough with no yeast row | FNDDS 2708024 "Fritter, plain", a stand-in | 23.32 % | READ: 80 g oil per 343 g (120 g water dropped); Q12 (iii): the cake doughnut 2708063 lists no oil |
| doughnuts, a dough with a yeast row | SR 172758 "Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)" | 16.72 % | DERIVED (R-d): FNDDS 2708072 "Doughnut, yeast type" lists this record alone and no oil, so P3's composition balance reads it with the PROTEIN tracer (the record is glazed; a glaze carries no protein) against the corpus dough (protein 7.03 %, fat 9.28 %): 87.30 g of dough per 100 g, 22.7 − 87.30 × 9.28 % = 14.60 g of oil; a bare dough: a stand-in, `(no record for dough; read as Doughnuts, yeast-leavened, glazed, enriched (includes honey buns))` |
| falafel | SR 172455 "Falafel, home-prepared" | 21.64 % | DERIVED (R-e): FNDDS 2707408 "Falafel"'s 224 g oil row is one cup, the frying MEDIUM (41.2 g fat per 100 g; its formula's 60.07 % is rejected) — P3's balance with the carbohydrate tracer against the corpus mix (carbohydrate 45.73 %, fat 3.96 %): 69.54 g of mix per 100 g, 15.05 g of oil |

The flag is M52's: `approximation (frying oil absorbed: 8.43 % of the raw
pakora batter's weight — USDA FNDDS 2710066 recipe: 21 g oil per 249.18 g
raw pakora batter)`; `… 7.62 % of the raw lumpia's weight — USDA FNDDS
2708702 recipe: 8 g oil per 104.99 g raw egg roll (no record for lumpia;
read as Egg roll, with beef and/or pork)`; `… 23.32 % of the raw struffoli
dough's weight — USDA FNDDS 2708024 recipe: 80 g oil per 343 g raw fritter
batter (no record for struffoli dough; read as Fritter, plain)`; `… 16.72 %
of the raw doughnut dough's weight — derived from USDA SR Legacy 172758
"Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)"`;
`… 21.64 % of the raw falafel mix's weight — derived from USDA SR Legacy
172455 "Falafel, home-prepared"`. Split between two oils, the cap (the line
less its kept part) and the basis (`discarded in cooking — only the oil the
fried food absorbs counted`) are M52's. Q12 (iv): a record with no oil
input and no ruled figure counts nothing — a roll whose mix counts no Pork,
Beef or Chicken row (FNDDS 2708700, the meatless egg roll, was never read)
keeps its oil at 0 g.

Reach: exactly 5 rows (+5,107.46 kcal per batch), each 0 g before:
pakoras-south-asian-spiced-vegetable-fritters|14 → 40.72 g (+359.96 on
canola 172360, 8.84 kcal a gram; mix 483.06 g),
lumpiang-shanghai-with-seasoned-vinegar|17 → 99.34 (+894.06; mix 1,303.73
— the DIPPING SAUCE's 186.85 out), falafel|11 → 85.55 (+769.95; 395.35),
yeasted-doughnuts|7 → 213.80 (+1,924.20; 1,278.71 — the GLAZE's 368.94
out), struffoli-neapolitan-honey-balls|7 → 128.81 (+1,159.29; 552.37). Per
serving: pakoras 136.77 → 226.76, lumpia 506.71 → 655.72, falafel 421.35 →
613.83, doughnuts 439.26 → 599.61, struffoli 523.27 → 716.48; no status
moves (pakoras and struffoli stay partial on their unmatched ajwain and
gram-less candied cherries). Kept: crispy-tempeh-with-sambal-sauce|5
(tempeh is no product word; its 28 g kept part), turkey-thigh-confit|6
(confit fries nothing), crispy-thai-eggplant-salad's Fried Shallots oil
(shallots), corn-fritters|8 and southern-corn-fritters|1 (held
`ambiguous_medium`), and the 36 rows that already carry an uptake.

Cost (RULE C at the editor caps): M61 lets a product recipe reach M52's
frying-oil weighing, so two shipped per-row reads are now read once — the
matches GET reads M52's plan once per request (it re-ran it for every row:
a dough beside 399 frying oils went from 6.5 s to 636 s; the shipped
counted-pork fry already took 818 s), and again for every coat or frying
oil a person confirmed (the confirm's derivation planned its own: with all
399 oils confirmed the dough's GET took 15.7 s at v59, 35.6 s with M61);
the request's one plan now answers a confirmed row whose stored row is
already the confirm's on every field the plan reads, and any other (a line
edited since, carried) still plans its own. A line's grams read the
sentences naming the skin once per recipe (`skinDiscarded`, once per line
before). No row or basis moves; at the caps the dough's compute and GET
take about 1.0 and 0.7 s (3.7 and 6.5 s at v59), 1.0 s with every oil
confirmed (15.7 s at v59), the pork fry's 0.9 and 0.7 s (0.8 s confirmed).
A person's confirm of one of the dough's oils (the PUT) takes about 0.43 s
(0.17 s at v59, when the dough fried nothing): M61's weighing of its 399
pans, the pork fry's 0.36 s.

Known gaps (design §7 — the source stands): pakoras at FNDDS's 8.43 % (its
batter holds 355.5 g of water per 249 g of mix) against the audit's 72.5
g; the lumpia's egg roll counts a cooked prepared roll at its listed
weight, and the 608 g wrapper line's grams are a separate question;
struffoli's ½-inch kneaded pieces read on a fritter BATTER; the yeast
doughnut's balance is fitted on the corpus dough against a commercial
GLAZED record (glaze fat taken as 0) — its tracers spread 13.35 %
(carbohydrate, P3's convention for an uncoated food) / 16.72 % (protein,
chosen) / ≤ 25.67 % (carbohydrate net of the glaze the record's 22.8 g of
sugars imply — an upper bound, the dough's sugars a floor); falafel's
carbohydrate tracer 21.64 % against its protein tracer 13.99 % (SR's home
recipe is protein-richer than the corpus mix); fried-yuca|2 waits for its
yuca record; the corpus lost the steps of 269 subsections (Q18), which
these step readers cannot see.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 24, main and
`--reverse-parents` byte-identical; STEP ZERO the v59 tree reproduces the
v59 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v59
rows exactly the 5 rows differ, in grams, basis and kcal only; 0 person
rows; statuses, sections, review buckets (a 0 g `discarded` row and an
uptake row are both `counted`) and holds identical. Deploy note:
matcherVersion 59 stales every recipe; a zero-request sweep recomputes the
library.

**Since matcher v61 (batch M62 — egg dips sized by the read wet share,
held-coat dips held, no crumb rule; matcherVersion 60; prep48 design_v2 §2
M62 and §1 Q9 with H as the owner's decision, the planner's E-w on the
verified figures of the L2 read, decided 2026-10-08 under the standing
authorization; zero requests — FNDDS 2710785 was read at live step L;
step-reading, so its reach is pre-Q18).** AMENDS M50 Q21 (D5, "flags only,
no grams move") for an egg or buttermilk dip. (The trigger) a sentence that
dips, coats or dredges the food **in / into / with (the) egg mixture, egg
white mixture, buttermilk mixture, egg whites or eggs** and holds "excess"
anywhere ("Using tongs, dip both sides of the cutlets in the egg mixture,
allowing the excess to drip off") — the mixtures read before the bare nouns,
and the sentence read as this dip wherever it matches (never also as the
shipped "excess egg" food word, which took every egg line). (The lines) the
lines a mixing sentence (whisk, combine, stir, beat, mix, sift) naming the
dip's base word — egg or buttermilk — BEFORE the dip names: a line's A13
mention (the nth mention for a head's nth line), or any mention of a head no
other line shares (chicken-kiev's "3 large eggs, beaten", first named where
the plates are set out); never a line the steps use as a medium (the coat's
own parts, a frying oil's kept part — "beat the eggs with 1 tablespoon of
the oil") and never a row with no record. The ceiling, stated: a shared
head rides A13's order — nut-crusted's one "pepper" word goes to its first
pepper line, the cayenne |8 (scaled), and its black pepper |12 stays whole;
oven-fried-onion-rings|5 cayenne is not reached; spicy-fried-chicken-
sandwiches|5 garlic powder is named by no sentence. Read once per recipe and
base word (engine `_dipsOf`). (Since matcher v65 a shared head's line is
told apart by its own word — M66 R3', below: the pepper and onion-ring
ceilings closed.)

(E-w) In a recipe that budgets its coat without the dips (M52's coated food
and shape with a coat or batter part), the dip lines count **W = 1.17 g a
gram of the carbohydrate the coat's parts count** — C = min(B, Σ the parts'
carbohydrate); since matcher v65 C = B (M66 R1, below) — shared by their
whole grams: f_w = min(1, W / Σ whole), each
line f_w × its grams, `gram_source: discarded`, basis `discarded in cooking
— only the dip on the food counted · approximation (dip: 1.17 g per g of the
coat's carbohydrate — USDA FNDDS 2710785 "Breading or batter as ingredient
in food": 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100
g; the dip's excess not counted)`. 1.17 = (15 + 120) / (287 × 0.401): the
wet grams of the breading every read coat record lists (food code 99995000)
over its own carbohydrate — its inputs (flour 125 g, dry crumbs 25 g, egg
15 g, water 120 g, baking powder and salt 1 g each) sum to 115.04 g of
carbohydrate, the record's 40.1 %, confirming c_b 0.40 and B. The coat's own
parts keep their grams, basis and flag (no re-split: chicken-katsu|0 stays
63.19). A dip line below the confidence gate shares nothing. A person's
Confirm of a dip keeps its grams, `discarded`, as a batter line's does.

(H, the owner's Q9 one-way door — re-rules Q21 (a) for these lines) A dip
whose coat is held with no budget (no coated meat row, or C4's sautéed
dusting) is held `coating` with it — no grams, `hold_note` the dip sentence
as written. It is a coating hold in the Recipe-review queue: a person's
Confirm counts 0 g `discarded` ("poured away after your confirm" — no eaten
part is known), typed grams stand, a skip stores no hold, a pick keeps the
hold; a Confirm or a pick records the FOOD (never grams) for the item key
library-wide, apply-to-all allowed, as for every coating hold. (No coat) a
dip with no coat held or budgeted keeps the D5 flag only — since matcher
v65 (M66 R4, below) only where the recipe does not shallow-fry the coated
food or that food has no shape (a baked or air-fried egg wash with no coat
line keeps the flag).

(P2 — no crumb rule.) The read's crumb share (15.64 % of its carbohydrate)
is FNDDS's generic breading, not a recipe that prints only crumbs (it would
take chicken-katsu|0's panko 62.49 → 9.88 g), and Q9 (c) — 2705871's crumb
coat for every crumb budget — would override the coated chicken's own read
coat: both measured, both rejected. B and its pro-rata split stand.

Reach: exactly 44 rows (−2,060.27 kcal per batch), all `auto`, 0 person
rows. E-w, 28 rows (−1,413.53): breaded-chicken-cutlets|4 100.00 → 41.92 g;
chicken-katsu|1 100.00 → 53.35; chicken-schnitzel|1 100.00 → 46.80, |2 (the
tablespoon of oil beaten in) 14.00 → 6.55 — made two steps before the dip;
nut-crusted|8 → 0.04, |10 150.00 → 27.66, |11 → 1.91; stuffed|11 100.00 →
23.26; chicken-kiev|12 150.00 → 30.67, |13 → 1.06; crispy-fried-chicken|9
50.00 → 21.71, |10 → 1.97, |11 → 1.00, |12 buttermilk 244.00 → 105.95;
crispy-pan-fried-pork-chops|1 buttermilk 244.00 → 46.82, |2 → 5.96, |3 →
0.58; crunchy-baked-pork-chops|11 99.00 → 41.86, |12 → 19.69;
pork-schnitzel|2 100.00 → 38.11; chicken-fried-steaks|3 → 14.58, |4 → 1.32,
|5 → 0.67, |6 buttermilk 244.00 → 71.13; lighter-chicken-parmesan|6 99.00 →
23.79; almond-crusted|4 100.00 → 23.19, |5 → 1.20, |6 → 0.58 (C 21.29 < B
35.74: f = 1). H, 9 rows held `coating` (−646.74 counted):
eggplant-parmesan|6, oven-fried-onion-rings|1–|4, parmesan-crusted-chicken-
cutlets|4 |5, chicken-francese|10 |11 (all four already partial). The D5
flag, 7 rows (0 kcal): best-chicken-parmesan|12 |13, spicy-fried-chicken-
sandwiches|2 |3 |4 |6 |7. Per serving (13 E-w recipes, 4 H): breaded 372.02
→ 350.53, katsu 429.12 → 411.86, schnitzel 460.09 → 423.64, nut-crusted
407.15 → 360.45, stuffed 572.91 → 544.51, kiev 584.97 → 540.19,
crispy-fried 858.08 → 832.44, pork chops 506.39 → 480.50, crunchy 480.86 →
468.90, pork-schnitzel 390.64 → 367.75, steaks 555.87 → 534.48, lighter
239.19 → 232.29, almond 431.67 → 402.18; eggplant 409.66 → 360.33,
onion-rings 249.84 → 217.86, parmesan-crusted 167.60 → 153.54, francese
449.08 → 407.44. Kept: the egg dips no "excess" sentence names
(crunchy-oven-fried-fish|6, orange-flavored-chicken|12, oven-fried-chicken|9,
the other chicken-francese|6), the frying oils' kept parts beaten into the
dip (breaded|5, stuffed|12, pork-schnitzel|3), pork-schnitzel|9's
hard-cooked egg garnish, crispy-fried-chicken|3's brine, the rows with no
record, the ceiling rows, every coat part of the 13 recipes, the 36 uptake
rows and M58's batter rows.

Known gaps (design §7 — the source stands): the crumb coats LOW against the
audit (P2, median 0.44×) — FNDDS's own coated chicken prints its 15 g of
breading, 8.71 % of it crumbs; the read wet share is egg 15 g and WATER 120
g, the recipe's egg or buttermilk read at the same mass;
crunchy-baked-pork-chops|10's 6 tablespoons of flour whisked INTO the whites
stays a whole eaten part (45.24 g) while the whites scale (≈ −96 kcal if
scaled); almond-crusted|6's zest — 1 of its 1¼ teaspoons goes in the dip —
scales whole (−1.86); a dip's oil (chicken-schnitzel|2) scales as dip, not
as frying oil; crispy-fried-chicken falls (−11.0 % on the calibration) with
no crumb line to offset; §2's one-f gap — a dip taking a large f from a coat
whose cornflakes are unmatched — is closed by E-w (the pork chops'
buttermilk 46.82 g, not 120.68); the shared-head ceiling above; the corpus
lost the steps of 269 subsections (Q18), which these step readers cannot
see.

Cost (RULE C at the editor caps — 398 dip lines beside one coat, every
sentence a mixing and a dip one): the dip lines are read once per recipe and
base word — each line's own mentions, the earlier steps never re-read per
dip sentence (`memo:dips`; 400 distinct heads named two to a mixing
sentence read within the bounds). The coat's shape is read once per recipe
and coated record (`_coatShapeOf`, read in full on every plan before).
A person's decision on an M52 line reads M52's plan ONCE per request
(v61 closer 1, verify1 D1/D2): a coat, batter or dip line's entry is the
plan's coat block's, a function of the rows' coat key alone (`_m52Key`:
each row as that block reads it — weighed, the engine's, its hold none or
`coating`, a coat or oil medium, its record, below the gate — the coated
food's grams and, under C5, the counted flour and starch off B; never
another row's grams, so a dip's or coat line's `discarded` plan form and its
engine form key alike); a frying oil's entry is the whole plan's (the key
adds each oil's hold and the grams of every counted row the fryer block may
read: a row it may fry, by `_friedClassOf`'s name test, and every counted row
when M61's product mix or M59 D's cauliflower batter may be read). The
matches GET answers each decided line from the request's one plan whenever
the decision's row list keys as the stored one (a confirmed no-coat dip:
one plan per GET, not one per dip). A COMPUTE answers each decided M52 line
from one plan per kind (coat block, fryer) while the rows as they stand at
that derivation key alike and no FDC cache write has landed since
(`SaltDatabase.fdcCacheWrites`); a write that moves the key re-plans once —
a person's PUT plans its own list as before (a pick at a dip plans no other
dip). Measured at the editor caps (398 decided lines, every one confirmed
unless named): the E-w dips' compute 0.80 s (16.2 s before this closer;
0.42 s at v60, the eggs counted whole there) and the first compute after
the deploy, every confirmed egg as v60 left it, 0.85 s; every other dip
picked 0.67 s, H's picked dips 0.64 s; M58 W's batter lines 2.6 s (44.3 s
at v60, 20.8 s before); no-coat flagged dips 0.79 s, beside a frying oil
0.79 s (2.1 s before; 0.40 s at v60), their GET 0.78 / 0.76 s (0.82 / 2.3 s
and 399 plans before; 0.56 / 0.60 s at v60); every frying oil of v26's dough
and pork-fry shapes confirmed 1.03 / 0.91 s (34.4 / 19.7 s at v60 — the
shipped M52 door), and every oil confirmed between the engine's dips or
coat lines, which the compute rewrites as it goes, 1.00 / 0.83 s (18.0 /
18.2 s at v60). Every compute above plans at most twice (its decisions' plan
and the totals'), every GET once. The E-w shapes' compute, GET and confirm
PUT stay about 0.96, 0.66 and 0.50 s (0.82, 0.57 and 0.33 s at v60).

Replay (rp43 + bucket_v12 on fresh copies of snapshot 24, main and
`--reverse-parents` byte-identical; STEP ZERO the v60 tree reproduces the
v60 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v60
rows exactly the 44 rows differ — the 28 E-w rows in grams, source, basis
and kcal, the 9 H rows in grams, source, hold, basis and kcal, the 7 flagged
rows in basis only; 0 person rows; statuses unchanged (1,022 complete, 176
partial); review buckets: `check` +9 and `counted` −9 (the held rows), the
`coating` holds 20 → 29. Deploy note: matcherVersion 60 stales every recipe;
a zero-request sweep recomputes the library.

**Since matcher v62 (batch M63 — the 8-inch pita by FDC's per-area portion,
the crab cake's own oil, the sirloin stand-in flag, the rack's retired hit
read; matcherVersion 61; prep48 design_v2 §2 M63 and §1 Q3, Q6, Q11, Q16,
the owner's rulings of 2026-10-08 under the standing authorization; zero
requests — the records were read at live step L (L3–L5); no rule reads a
step, so no reach here is pre-Q18).** Four record reads:

(P10, Q16 — RE-RULES F3's "only on a printed 8-inch weight", the owner's
outcome B) A pita counted by its printed **"(N-inch)" diameter** (`\bpitas?\b`
in the item, never "pepitas"; a bare count or "piece"; the record FNDDS
2707616 *Bread, pita* alone — keyed by its id, not a description prefix, so
a person's pick of another *Bread, pita…* record keeps its own weighing:
none of them publishes a surface inch, and SR 174915 prints its own 4" and
6½" pitas) weighs the record's own **'1 surface inch' 2.0 g × π
(N/2)²** — an 8-inch pita 50.27 sq in, **100.53 g** — `gram_source: piece`,
basis `4 × 100.53 g each (8-inch round: 50.27 sq in × 2 g per surface inch) ·
approximate (derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the
printed diameter's area, π × 4²)` (grams `_perArea`, read at step 3a.6
beside the per-inch pieces, before the per-item portion; "about N inches
long" is a length, never read as a diameter). FNDDS names no diameter for
its small 28 / medium 57 / large 85 / extra large 114 g, and SR 174915
prints a 4" (28 g) and a 6½" (60 g) pita only: no source prints an 8-inch
weight, so the figure is DERIVED from the rows' own record (the baguette's
per-inch precedent, v37) and flagged so. Before: the medium 57 g.

(Crab, Q11) A fried crab absorbs the oil of FNDDS 2706549 *Crab, cake*'s
own recipe — **5 g of oil per 65 g of crab ("blue, cooked, moist heat"),
7.69 %** — not the chicken breast's 6.68 % stand-in (`_friedClassOf`; the
uptake table's O1e row loses crab to this O1k). Flag `frying oil absorbed:
7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65
g raw crab` (the template's "raw" is the shipped wording: the record's crab
and the line's are both cooked, so no protein conversion). The record's 5 g
of dry crumbs are mixed in — a binder, as the recipe's own crumbs are — so
no cake coat figure follows: the flour's coat stays on the breast's read
5.73 with M58's stand-in suffix.

(Top sirloin, Q6) Live step L5 found no lean-and-fat petite roast in FDC
(choice 173408, select 174695, all grades 173053 are all "separable lean
only, trimmed to 0" fat"); the cached lean-and-fat raw top sirloins are
steaks and cap steaks at a 1/8" depth no line prints, and one Australian
grass-fed cap-off record (171739, 127 kcal, below the lean-only choice
roast's 132 by origin and feed) — none a petite or center-cut roast — so R2
cannot fire and no rank-as is made. A line on 173408 that does not say
`lean` (a word) says it stands in, whoever chose the record
(`trimStandInFlagOf`, as the brisket's): ` · approximate (lean only — FDC
publishes no lean-and-fat top sirloin petite roast (search 2026-10-08); the
roast's separable fat not counted)`. Grams and energy unchanged.

(The rack, Q3) Live step L cached 174414's detail: its portions are 'oz'
(4 = 113 g) and 'chop' (63 g), no refuse portion — the assumption M56's
`ah102MeatsOnHit` made is verified, and the set is RETIRED: the rack's
weight line reads the cached detail (no request on a cache that holds it;
one detail on one that does not) and lands the same AH-102 item 1364 row,
byte-equal (1,241.71 g, 2,942.85 kcal — the detail's 237 kcal is the
hit's). Australian 174414 stays (the line prints "frenched" and the ⅛ inch;
the domestic 174377 is unfrenched, +44 %, and unreachable from the line's
answer without a rewrite and one more search — not spent).

Reach: exactly 8 rows (+1,717.16 kcal per batch at the stored grams), all
`auto`, 0 person rows. P10, 4 rows: grilled-arayes|18 "4 (8-inch) pita
breads", grilled-chicken-souvlaki|16 "4 (8-inch) pitas", shakshuka|0 228.00
→ 402.12 g (+478.84 each), fattoush|0 "2 (8-inch) pita breads" 114.00 →
201.06 (+239.42). Crab: maryland-crab-cakes|9 "¼ cup vegetable oil" 30.30
→ 34.88 g (+41.22). Sirloin, basis only: fennel-coriander-top-sirloin-
roast|0, beef-en-cocotte-with-mushroom-sauce|0, inexpensive-grill-roasted-
beef|4. Per serving: arayes 1,013.59 → 1,133.30, souvlaki 567.49 → 687.20,
shakshuka 534.91 → 654.62, fattoush 330.26 → 390.11, maryland 323.95 →
334.26 (partial, Old Bay). Kept byte for byte: the rack|0, grilled-rack-of-
lamb|5 on NZ 172641 (no depth printed), maryland|8's coat, the pita line
with no amount (clbr-turkish-poached-eggs|8), the pepitas, the "(N-inch)
flour tortillas" on 2707824 (quesadillas|0 52.00; the three fajita rows
260.00 — 2707824 prints no surface inch), the prosciutto weight lines,
best-crab-cakes|14's oil (measured tablespoons, counted whole), the top
sirloin steaks (2727574, 174707).

Known gaps (design §7 — the source stands): the pita's 2 g a square inch is
FNDDS's average thickness (SR's own sizes read 1.81–2.23 g; a thin 8-inch
pocket pita may weigh less) — the alternative reading, FNDDS's unnamed
"large" 85 g (an 8-inch pita ≥ SR's 6½"), is not taken (F3: larger than 6½"
does not say large rather than extra large), nor SR's 6½" 60 g scaled by
area (90.89 g; its 4" gives 112.00); the "(N-inch) flour tortillas" sibling
(no per-area portion on 2707824) is a later item; the crab cake's record is
unfloured while the recipe's cake is dredged — a floured cake may absorb more
than 7.69 %; lean only under-counts the seam fat a trimmed top sirloin roast
keeps; the rack is Australian frenched against the recipe's preferred
domestic (origin and frenching differ, F11); Q18 unchanged.

Replay (rp43 + bucket_v12 on fresh copies of snapshot 24, main and
`--reverse-parents` byte-identical; STEP ZERO the v61 tree reproduces the
v61 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v61
rows exactly the 8 rows differ — the 4 pitas and the crab oil in grams,
basis and kcal, the 3 roasts in basis only; 5 recipes move kcal per serving
and total grams; statuses (1,022 complete, 176 partial), holds and review
buckets unchanged. Deploy note: matcherVersion 61 stales every recipe; a
zero-request sweep recomputes the library (a cache without 174414's detail
asks it once).

**Since matcher v63 (batch M64 — corpus prints: kosher salt at half table
salt's weight by volume, the set-aside pear half, "remove the bay leaf", the
pour-off window, the Fried Shallots' printed oil yield, the "remove solids"
strain; matcherVersion 62; prep49 design_v2 §2 M64, the owner's Q12 (a)
under the standing authorization; zero requests; the bay, pear, pour-off,
yield and strain readers read steps, so their reach is pre-Q18).** Six
rules, each a corpus print:

(R-D) **Kosher salt weighs 0.60865 g/mL** — half of table salt by volume on
USDA SR 173468 "Salt, table"'s own '1 tsp' 6.0 g (6.0 / 4.92892 × 0.5; 3.0 g
a teaspoon). The corpus prints the conversion: "1 tablespoon kosher salt or
1½ teaspoons table salt" (crisp-skinned roast chicken, steak tacos — both
lines now weigh their own table-salt alternative, 9.00 g), 0091's "¾ cup
salt" with "If using Diamond Crystal kosher salt, increase the salt to 1½
cups", and 16 recipes name Diamond Crystal, 12 of them saying they were
developed with it. It was a round kitchen 0.72 (3.55 g a teaspoon), which
flake and coarse sea salt keep (no print converts them).
The basis ends ` · kosher salt at half table salt's weight by volume (the
corpus's own "1 tablespoon kosher salt or 1½ teaspoons table salt"; USDA SR
173468 '1 tsp' 6.0 g)` — after a plus part too ("2 tablespoon ≈ 30 mL + 2
teaspoons kosher salt · kosher salt at …"). The brine threshold's kosher
mass is now 26.8 g (44 mL); no corpus kosher line is written by weight, so
no hold moved. 0 kcal; ≈ −59.1 g sodium over the library.

(P10) **A counted part set aside for another use is subtracted**: "set aside
N <head> half/halves/quarter(s) (and reserve) for (an)other use" naming the
line's head, N of the line's count × 2 (× 4) — "Peel, halve, and core pears.
Set aside 1 pear half and reserve for other use" (pear-walnut upside-down
cake): 1 of 6 halves, `discarded`, basis the weighing's own text then `1
pear half saved for another use (step 2) — only the rest counted`. Never by
widening "reserve for another use" (that zeroes a whole food).

(R4, bay only) **"remove (the) bay leaf/leaves"** at or after the line's own
mention discards it like "discard the bay leaf" (`removedAromatic`, 0 g,
`removed and discarded (step N) — counted as 0 g`), with or without a
"discard" after it; every "remove" of a sentence is read ("Remove stew from
oven and remove bay leaves"). The bay leaf only: the same arm on every whole
piece would zero the stuffed peppers lifted from their pot, a roasted garlic
head squeezed into butter, a poached salmon's lemons. "Discard … the bay
leaf, if it can be easily removed" (paella) stays counted. (R4b) An
unflagged sub-gram piece prints its figure: `1 × 0.2 g each`, not `1 × 0 g
each`.

(F9) **The pour-off reads the last oil-naming sentence before it in any
earlier step** (the v51 window was its step or the step before): crispy-
skinned chicken breasts' step-3 "Place breasts, skin side down, in oil" is
cut by step 5's "Pour off all but 2 teaspoons oil from skillet"; `_panOil`
and the one-line binding unchanged; white chicken chili (pour-off step 3, oil
step 1) keeps 1 tablespoon of its 1 tablespoon, unchanged.

(Yield, Q12 (a)) **A frying oil whose yield prints the oil out** — "MAKES
ABOUT 1½ CUPS FRIED SHALLOTS AND ABOUT 1¾ CUPS FRIED SHALLOT OIL" beside "2
cups vegetable oil" — counts the difference of the printed volumes as the
part the food keeps (2 − 1¾ = ¼ cup, on the line's record: 2710180's '1 cup'
224 g → 56.00 g), the frying oil's kept-part slot (`_keptFryingOil`), basis
`discarded in cooking — only the part the recipe keeps counted · approximate
(the difference of the yield's printed volumes: 2 cups in, about 1¾ cups out
as shallot oil — the ¼ cup the shallots, the pan and the towel keep counted
as eaten)`. The only oil-product yield in the corpus. The flag is built from
the prints it subtracts, so an edited recipe reads its own: the line's volume
amount (a weight-first "16 ounces (2 cups)" line subtracts from its 2 cups),
the yield's "about" volume and the oil it names (less "fried"), the
difference in the line's unit, the food the yield names before it (else "the
food"), and the towel only when a step names one.
The difference is ALL the oil the food, the pan and the towel keep, never a
pour-off's pan residual: a food fried in that oil adds no frying uptake on top
(M52's pan loop reads the yield's part as the whole eaten oil — `_yieldKept`),
and on a plus line ("2 cups plus 1 tablespoon vegetable oil") the basis names
the plus part only when a step eats it, beside "the part the recipe keeps" and
the flag (closer 3; STATED synthesized edits of 0053 pinned: the main recipe
printing its frying oil out → 56.00 g, not 56.00 + the eggplant's 40.82; the
plus line 56.00 g or, with a step eating the tablespoon, 70.00 g). Limits, 0
corpus rows: a yield is read against every frying-oil line of its recipe (two
such lines would each keep line − q); a plus part no step eats is not added to
the "in" volume (the line's own volume amount is); a divided frying oil's part
used outside the fry is counted beside the yield's, its basis naming only "the
part the recipe keeps" and the yield's flag.

(H1, shipped on its condition) **"Using slotted spoon, remove solids from pot
and discard"** strains (`remove (the) solids … discard` joins the strain
readers): guay tiew's lemongrass is strained out; its scallions (the greens
go in after) and Thai chiles (one sliced, eaten) stay counted, as the
condition required.

Reach (replay of snapshot 25 against the v62 rows): exactly 127 rows, all
`auto`, 0 person rows, 0 hold moves, 0 status moves: R-D 90 kosher rows on
173468 (986.60 → 834.00 g, 0 kcal; crisp-skinned-roast-chicken|1 and
steak-tacos|8 10.65 → 9.00, pai-huang-gua|1 5.32 → 4.50, gravlax|1 42.59 →
36.00); P10 pear-walnut-upside-down-cake|4 530.70 → 442.25 g (−59.26); R4 11
bay rows → 0 g (3.80 g, −11.90: hearty-spanish lentil and chorizo soup,
catalan beef stew, hungarian beef stew, shepherd's pie, chicken marbella,
filipino adobo, pasta with creamy tomato sauce, coq au vin, carnitas, pesce
all'acqua pazza, hearty beef and vegetable stew) and 20 bay rows basis only
(R4b); F9 crispy-skinned-chicken-breasts|2 28.00 → 9.07 g (−170.38); the
shallot section's oil 0 → 56.00 g (+504.00); H1 guay-tiew|1 20.00 → 0
(−19.80); two routed parents — crispy-thai-eggplant-salad|14 151.80 → 170.37
g, 108.86 → 276.86 kcal (the section total STORED at 1 dp, 511.10 g × ⅓;
its kosher line moves too) and grill-roasted-beer-can-chicken|3 20.76 →
20.14 g, 0 kcal (the Spice Rub's kosher line, 110.70 → 107.40 g × 0.1875).
Row kcal +242.66 (the section's +504.00 counted once; the parent's +168.00
is its share). Per serving: pear cake 533.20 → 525.79, crispy-skinned
breasts 489.04 → 403.85, crispy Thai eggplant 419.95 → 503.95, guay tiew
601.77 → 596.82, the bay recipes −0.10 to −0.62. Kept: paella's bay leaf,
the 40-cloves bay leaf (now `1 × 0.2 g each`), the carnitas onion and the
stuffed peppers (bay only), white chicken chili's oil (1 tablespoon kept of
1 tablespoon), the eggplant's main frying oil (40.82 g), guay tiew's
scallions, chiles and galangal, the five flake / coarse sea-salt rows and
every table-salt row.

Known gaps (the source stands): a Morton kosher line (⅔ of table salt by
volume, 4.0 g a teaspoon) reads Diamond Crystal's half — the corpus means
Diamond (16 recipes name it, each printing a smaller Morton amount); flake
and coarse sea salt stay on the unsourced 0.72; the carnitas onion "remove …
and discard" stays
counted (a "remove" for every whole piece waits on the garlic-shrimp 4-of-14
share); Chicken Marbella's binder ("Heat oil" names neither oil — a
step-label reader, −40.86 kcal left); the shallot oil's "about 1¾ cups"
rounds to ⅛ cup (±28 g, ±252 kcal on the section); guay tiew's galangal is
no strained head (weighed on ginger, kept: 16.00 g, 12.80 kcal) and its
makrut lime leaves stay below the gate. Deploy note: matcherVersion 62
stales every recipe; one zero-request sweep settles it.

**Since matcher v64 (batch M65 — matcher landings with the record already
cached: jarred Morellos, corn husks, kombu, gel food dye, ricotta salata on
feta; matcherVersion 63; prep49 design_v2 §2 M65, the owner's Q14 under the
standing authorization; zero requests; no step is read).** Five landings, each
on a record snapshot 25 caches with its detail:

(F5) **A volume line bought "from N (W-ounce) jars|cans" weighs its
volume** — the paren is the container bought, not the measure: a line whose
FIRST amount is a volume and whose text reads `from N (W-ounce) jar(s)|can(s)`
skips the printed-weight read (grams `_fromContainers`). With it v38's dry
R05 is enabled: `jarred morello cherries` (reads `dried sour cherries`) →
`cherries sour canned water pack drained`, SR 167769 "Cherries, sour, canned,
water pack, drained" (42 kcal; `cup` 168 g), 1.0, a flagged approximation
(the pack is not printed). sour-cherry-cobbler|7 "8 cups jarred Morello
cherries from 4 (24-ounce) jars, drained, 2 cups juice reserved": 680.39 g
(one jar) on 2709231 "Cherries, raw" at 0.3767, `check` → 1,344.00 g (8 ×
168), `8 cup · USDA portion · approximation (counted as Cherries, sour,
canned, water pack, drained)`, +564.48 kcal. The only corpus line with those
words; "1½ cups (12-ounce bottle or can) dark beer or stout", "2 cups plus 2
tablespoons crushed tomatoes (from one 28-ounce can)" and "1 cup oil-packed
sun-dried tomatoes (one 8½-ounce jar)" still read their container (a gap,
below).

(F4) **Dried corn husks are a wrapper** (`isNonFood`: `corn husk`, the
banana-leaf class): tamales|3 "20 large dried corn husks" (167631 "Corn,
dried (Navajo)" at 0.3167, `check`) → confirmed on no food as "Equipment —
not food, counts as zero", 0 kcal. The library's other husk lines are food
(`ears corn`, tomatillos, `powdered psyllium husk`).

(F7) **The kombu line shows FNDDS 2709988 "Seaweed, dried"** (`square piece
kombu` reads `dried mint` → `seaweed dried`, 0.99; flagged — FNDDS's seaweed
is not kelp-specific): nikujaga|1 stays 0 g `discarded` (strained), its basis
adding `· approximation (counted as Seaweed, dried)`; it showed "Cereal, oat
squares" (0.1317). 0 kcal.

(F8) **Gel food dye is a zero flavouring** (`gel food dye` joins the
explicit list): rainbow-cake|8 (amount-less; "Fast foods, coleslaw" at 0.033)
→ "Flavouring — no nutrients, counts as zero", 0 kcal.

(F2, Q14) **Ricotta salata counts as SR 173420 "Cheese, feta"** (`ricotta
salata` reads `feta cheese` → `cheese feta`, 1.0): FDC holds no ricotta
salata in the three data types (its own answer: fresh ricottas only, 746766
at 0.195, below the gate); a stand-in by class (salted, firm, crumbled or
shaved), flagged with the composition it borrows — `from 4 ounce ·
approximation (counted as Cheese, feta) · approximate (FDC holds no ricotta
salata — a stand-in by class; feta's sodium (1,139 mg per 100 g) and fat
(21.49 g per 100 g) counted)` (`trimStandInFlagOf`, on 173420 only where the
line names ricotta salata; a feta line says nothing). brussels-sprout-salad-
with-warm-mustard-vinaigrette|10 113.40 g +300.50 (the stored 4 oz, 113.398
g × 2.65); pasta-alla-norma|9 85.05 g +225.38; both `check` → counted.

Reach (replay of snapshot 25 against the v63 rows): exactly 6 rows, all
`auto` before, 0 person rows; +1,090.36 kcal. Four recipes complete
(partial → complete): sour cherry cobbler 250.28 → 297.32 kcal a serving,
brussels sprout salad 240.27 → 290.36, pasta alla norma 443.35 → 480.91,
tamales (719.39, status only); nikujaga stays partial (its katsuobushi is
unmatched; the kombu row already counted at 0 g); the rainbow cake was
already complete. Statuses 1,022 / 176 → 1,026 / 172.

Known gaps (the source stands): the cobbler's "2 cups juice reserved" is
stirred into the filling ("Stir in the reserved cherry juice and wine") and
eaten, and is not counted — no sour-cherry juice record is cached and the
jar's pack (water or syrup) is not printed; feta's sodium and fat stand in for
ricotta salata's, which FDC does not publish; the three other volume lines
reading a container weight (the dark beer's 12-ounce bottle 340.19 g, the
crushed tomatoes' 28-ounce can 793.79 g for 2⅛ cups, the sun-dried
tomatoes' 8½-ounce jar 240.97 g) are outside F5's words. Deploy note:
matcherVersion 63 stales every recipe; one zero-request sweep settles it.

**Since matcher v65 (batch M66 — coat parts and dips: the gated nut/cheese
layer joins, C = B, a dip line's part used elsewhere, the shared-head split,
dips alone open a budget, the alcohol and C5 basis texts; matcherVersion 64;
prep49 design_v2 §2 M66, the owner's Q5 (a) gated, Q7 (the one-way door,
accepted 2026-10-09: no one uses the app yet) and Q8 (b) under the standing
authorization; zero requests; the gate and the dip readers read steps, so
the reach is pre-Q18).** All inside M52's plan at the recipe's shipped k:

(R3, Q5 a GATED) **A nut or cheese layer mixed into a crumb joins the coat's
parts.** A held coat row on a `Nuts,` or `Cheese,` record shares B at the one
f as panko and flour do — but only when one step sentence names both the
layer (its head, or the kind word its item carries, "parmesan", "saltine")
and a crumb (`bread crumbs`, `panko`, `crumbs`, `crackers`; engine
`_layerInCrumb`). almond-crusted|2 "1 cup sliced almonds" (S2: "Process the
almonds … to fine crumbs") held → 79.97 g of 92 (f = 35.74 / (92 × 0.2155 +
29.57 × 0.7198) = 0.869248), |3 panko 29.57 → 25.71; nut-crusted|2 "1 cup
almonds, chopped coarse" ("add the bread crumbs and ground almonds") held →
21.66 g of the line's `cup, whole` 143 g, |5 panko 10.99 → 8.96, |9 flour
22.42 → 18.28 (f 0.1515); lighter-chicken-parmesan|2 "1 ounce Parmesan"
("Spread the bread crumbs … ; when cool, stir in the Parmesan") held → 5.04,
|0 16.29 → 15.78, |3 11.07 → 10.73 (f 0.1779). parmesan-crusted|3 (0419: the
cheese IS the crust, "Combine the 2 cups shredded Parmesan and remaining 1
tablespoon flour" — no crumb) stays held, and has no budget anyway. A
one-sentence gate: a crumb named only in another sentence of the mixing step
leaves the layer held (no corpus recipe). The layer counts more MASS than
the record at equal carbohydrate (almond-crusted's coat 16.9 % of the raw
breast against 2705975's 14.3 %): a mass-matched budget would be a new
mechanism (not built).

(R1) **The dip is sized off B**: W = 1.17 × B, never min(B, the parts' Σ) —
the coated food's own read record's wet breading per gram of raw food. On
its own it reaches only R4's recipe: every other budget that sizes a dip
has f < 1, where the two agree, and the two budgets at f = 1 —
maryland-crab-cakes' flour and crispy-salt-and-pepper-shrimp's cornstarch
(the 2 tablespoons that dredge the jalapeños) — size no dip, so W has
nothing to size.

(R2) **A dip line's part a later step writes is eaten whole** ("remaining ¼
teaspoon zest", almond-crusted S4): the coat's reader (`_eatenOutsideMedium`)
on the steps AFTER the dip's (never the mixing step before it, which writes
the dip's own amounts), the step naming the line by its head or its item's
last word ("orange zest": head `orange`, written "zest"); never a mention
another line writes (Run 054 O7) — by the last word, every line whose head
or last word is that word and every line of the dip line's own head ("2
large eggs" whisked into a dressing beside a second "2 large eggs" line, or
a "2 large eggs plus 1 large white" line, is that line's; "1 teaspoon lemon
zest" beside a lemon-zest line is the lemon's); the part's grams
off the dip's whole, counted on top, basis `discarded in cooking — only the
part the recipe keeps and the dip on the food counted · approximation (dip:
…)`. almond-crusted (C = B 35.74, W 41.92 over 100 + 5.18 + 2.00): |4 eggs
23.19 → 39.11, |5 Dijon 1.20 → 2.02, |6 zest 0.58 → 1.28 (0.78 dip + 0.50
eaten on 169103's `tsp` 2.0 g).

(R3') **A head two lines share is told apart by each line's own word** — the
word right before the head in its item, written in no other line of that
head ("ground black pepper": black; "cayenne pepper": cayenne; never "and" /
"or") — at every sentence writing it; a line with none keeps A13's order.
nut-crusted|12 "¼ teaspoon ground black pepper" ("Lightly beat the eggs,
mustard, and black pepper") 0.58 → 0.11 g (dip); |8 "⅛ teaspoon cayenne
pepper" 0.04 → 0.23 whole (it goes into the panko mixture); |10 27.66 →
27.60, |11 1.91 → 1.90; oven-fried-onion-rings|5 cayenne 0.45 → held
`coating` with its siblings ("Whisk the remaining ¼ cup flour, the salt,
black pepper, and cayenne into the buttermilk mixture"), its `hold_note` the
dip sentence. The ceiling, stated: one token — a line told apart only by a
word further from its head has no own word and rides A13's order; and a
line WITH an own word is named only where that word is written, so a mixing
sentence calling it by its bare head ("the salt, pepper, and cayenne") no
longer names it, as v64's A13 did (on that STATED synthesized onion-rings
edit |4 counts whole, out of the held dip; pinned). No A13 fallback is read
for it — nut-crusted|8 cayenne, its word only in the crumb sentence, would
take the egg sentence's "black pepper" back.

(R4, P9) **An egg dip with no coat or batter line opens the budget** where
the recipe shallow-fries the coated food (M52 Q24 b, engine `_shallowFries`:
with no coat or batter line the plan finds a coated food only so, its
frying oil a medium) and that food has a shape. best-chicken-parmesan
(0415: "Whisk egg and flour together …; dredge cutlet in egg mixture,
allowing excess to drip off"; its Parmesan-panko crust counted whole) on
the breast's C1 (2705975, the record its oil already reads): W = 1.173026
× 5.73 × 396.89 / 100 = 26.68 g over 50 + 7.54 (f_w 0.46361) — |12 egg
50.00 → 23.18, |13 flour 7.54 → 3.50, `discarded`, the dip basis in place
of D5's bowl flag; −54.48 kcal.
Unreached (a baked or air-fried egg wash with no coat line keeps the D5
flag): the spicy chicken sandwiches' dips (air-fried: no shallow fry, and
no shape either — the air fryer neither fries nor bakes) and the three
non-coat D5 recipes (scones, truffles, macaroons: no coated food); so would
0415 with its cutlets baked instead of shallow-fried (|12 50.00 g whole,
flagged — though baked cutlets have the C2 shape).

(Basis texts, 0 grams, 0 kcal) the 15 C5 batter rows (shrimp-tempura|2–|6,
fish-and-chips|2 |3 |4 |5 |8 |10, crispy-fish-sandwiches|6 |7 |9 |10) say what
is applied — `… recipe: 25 g breading (USDA 99995000, 40.1 % carbohydrate)
per 65 g raw shrimp, matched by its carbohydrate; the batter's excess not
counted)` (the auditors read the shipped text as batter MASS); and (Q8 b) the
three alcohol lines of a fried batter (tempura|4 vodka, fish-and-chips|10 and
sandwiches|10 beer) keep 5002's 85 % and say `… the stirred-into-hot-liquid
figure (USDA prints no row for a batter fried in oil))`.

(Q7, the one-way door) A person's Confirm of a reached coat or dip row
reads the plan — almond-crusted|2's almonds 79.97 g `discarded` (no longer
0 g poured away), best-chicken-parmesan|12's egg 23.18 — and keeps following
it (`_m52Weighs`). Accepted by the owner (no one uses the app yet).

Reach (replay of snapshot 25 against the v64 rows): exactly 18 rows move
grams or hold — R3 almond |2 |3, nut-crusted |2 |5 |9, lighter |0 |2 |3; R3
+ R1 + R2 almond |4 |5 |6; R3' nut-crusted |8 |10 |11 |12, onion-rings |5; R4
best-chicken-parmesan |12 |13 — plus the 15 basis-only rows (3 of them the
alcohol flag); all `auto`, 0 person rows; +536.11 kcal (almond-crusted
+472.52, nut-crusted +101.55, lighter +17.95, best-chicken-parmesan −54.48,
onion rings −1.43). Holds: 3 released (the layers), 1 added (onion-rings|5).
Statuses 1,026 / 172 → 1,029 / 169: almond-crusted (402.18 → 520.31 kcal a
serving), nut-crusted (360.45 → 385.84) and lighter-chicken-parmesan (232.29
→ 235.29) turn complete — the released layer was each one's only uncounted
line; best-chicken-parmesan 500.12 → 486.50; oven-fried onion rings 217.86 →
217.50, partial. Cost: R2 reads the coat's per-head mention lists (each dip
line three binary searches over them, the steps after its dip a suffix);
R3' tallies each shared head's words once per recipe.

Known gaps (the source stands): P4's wet batters (9 HIGH audit lines) — the
coat + oil per gram of raw food reproduces each read FNDDS record's own
product energy to ≤ 1.5 % (tempura without the vodka 213.9 vs 214.9 kcal per
100 g raw; cod 214.2 vs 217.5; haddock 212.0 vs 211.6) and SR's restaurant
records carry MORE coat; tempura's remaining excess is the vodka and the
calibrator's yield. P8's dips on BAKED coats (nut-crusted|10, stuffed|11,
lighter|6 at −33 to −44 %) sit on the food's own read record (2705980's wet
share 3.73 % of the raw food baked vs 6.72 % fried). R4's B vs the counted
coat: best-chicken-parmesan's crust (Parmesan 42.52 g, panko 29.57 g, counted
whole) carries 26.56 g of carbohydrate against B 22.74; the dip is sized off
B (the shipped figure; the counted coat would give W ≈ 31.2). P5 crusts and
crab cakes: maryland-crab-cakes' flour (the budget exceeds the line, so the
whole ¼ cup counts), best-crab-cakes' panko, pork-schnitzel's crumbs — a
per-mass k cannot see a coat's thickness; no sourced per-area figure. The
spicy sandwiches (air fried, no record) stay whole and flagged. Not built:
C5 read as batter mass (−298) and baked dips on the fried 5.73 — both
override the coated food's own read record. Deploy note: matcherVersion 64
stales every recipe; one zero-request sweep settles it.

Since matcher v39 (edible yields, part 1 — the owner's "go with your
recommendations", 2026-10-05, on prep39/plan.md Q1 (a), Q3 (b), Q4 (b);
zero requests): **bone-in class yields** (revising CP6 #11 and #5). A line
that buys refuse, weighed from a printed weight, whose matched record
publishes no refuse portion of its own (and is no whole chicken, which
reads its ready-to-cook yield), reads its record's class figure, every one
an FDC portion, flagged `approximate (yield of <class> from FDC <id>)`:

| class | records | yield | derivation |
|---|---|---|---|
| bone-in pork chops | 167822 | 0.662 | 168242's own refuse: 133 g of a 201 g chop, lean+fat (the lean-only 0.570 also refuses the separable fat) |
| pork ribs (since v43 the baby backs 168299 only; the spareribs 167853 read AH-102 item 1925, below) | 168299 | 0.653 | 167895 country-style ribs, 128 of 196 g |
| a bone-in pork roast (since v43 the picnic 168367 only; the hams 168226 and 169177 read AH-102, below) | 168367 | 0.758 | 167849 Boston butt, 288 of 380 g |
| ~~a bone-in roast (the pork butt figure)~~ — since v43 the standing rib 168675 reads AH-102 item 238, below | — | ~~0.758~~ | cross-species: no beef refuse is cached |
| chicken parts (since v43 only a part-less, non-whole line: the AH-102 poultry table below) | 171447 (pieces), 2727566–69, 172378, and the meat-only 2646171, 173619 | 0.608 | 171447 "yield from 1 lb ready-to-cook chicken" 276 g; the Cornish hen's 336 of 567 g (0.593) corroborates |
| turkey parts (the chicken figure; since v43 the bone-in BREAST 171093 only — deferred, below) | 171093, 171533, 171497, 174518 | 0.608 | no turkey part figure exists |
| a whole turkey (interim: the chicken figure; since v43 0.6515, below) | 171081 | 0.608 | the live step (2026-10-05) found no bird yield: per ready-to-cook pound the breast 171093 is 146 g, the leg 171493 105 g, the wing 171495 33 g, but FDC has no raw "meat and skin" back or neck — 171096 back and 171086 neck are meat only and publish no share — so the parts (284 g = 0.626) are a partial sum and the interim stays (12 lines) |
| bony beef, lamb and veal (since v43 without the shank 169441, the rack 172641 and the foreshank 172513: AH-102, below) | 173405, 170827, 174875, 172648 | 0.657 | the median of the four above, (128/196 + 133/201) / 2 |
| oxtails | 2705843 | 0.564 | the record's own FNDDS "1 oz yields 16 g" (raw with bone → this cooked food) |

109 lines move (texas-style beef ribs 2,268 → 1,491 g; best prime rib
3,175 → 2,406 g; a 12- to 14-pound turkey 6,350 → 3,864 g); 103 recipes,
100 of them by more than 10 % a serving. **Skin discarded**: a bone-in,
skin-on thigh (2727567) or leg quarter (172378) the engine picked moves to
the cached meat-only record — 2646171 "Chicken, thigh, boneless,
skinless, raw", 173619 "…leg, meat only, raw" — at the bone yield × FDC's
meat share of meat and skin (SR 173619's "thigh bone and skin removed"
147 g of 172378's "thigh with skin" 185 g, 0.795; its "leg, bone and skin
removed" 265 g of the "leg, with skin" 344 g, 0.770), flagged, when the
line says "skin removed" or "skinned", or a step removes or discards the
skin ("remove and discard the browned chicken skin", "discard skin",
"peel skin off") and no sentence of the recipe naming the skin reserves
it, sets it aside, lays it back, stretches it, or takes it "if desired" or
from the "tapered" pieces only: 13 lines (Chicken Provençal's 8 thighs,
1,361 → 828 → 658 g). The move applies to every `auto` row on the skin-on
record — the engine's pick, or a person's decision carried from another
line or by `apply_to_all` — never to a person's own row on the line, which
shows the food they chose. A decision written from a row on a meat-only
record whose line trips (a Confirm of a moved row, or a pick of the
meat-only record there) records the SKIN-ON record bought, so the key's
other lines move only where their own recipe discards the skin: Chicken
Provençal's thighs confirmed leave Chicken Teriyaki's (skin eaten) on
2727567 at 828 g. Since matcher v40 (the live step, 2026-10-05) a whole
bird or pieces on 171447 moves the same way to SR 171052 "Chicken,
broilers or fryers, meat only, raw" (the search `chicken broilers or
fryers meat only raw` ranks it first; its detail publishes "unit (yield
from 1 lb ready-to-cook chicken)" 197 g against 171447's 276 g, and "0.5
chicken, bone and skin removed" 329 g), read at that yield and never a
class figure (171052 is in neither table): a WHOLE bird by the
ready-to-cook reader 171447's whole chicken uses, unflagged where the
whole skin goes — `"from the printed weight × 0.43 edible (USDA
ready-to-cook yield)"`, Moroccan chicken's 4 pounds 1,104 → 788 g — and PIECES at the same per-pound
figure, flagged `"… × 0.43 edible (USDA ready-to-cook yield) ·
approximate (skin discarded; the whole bird's meat-only yield)"` (tandoori
chicken's 3 pounds 828 → 591 g); a decision from a moved row records
171447. The signal moves five lines (pressure-cooker chicken noodle soup,
Moroccan chicken, grilled lemon chicken, pollo en mole poblano, tandoori
chicken). A whole bird whose tripping skin-off sentence also leaves part
of the skin on ("leaving skin on <part>" / "leave the skin on <part>") is
flagged with that part, the grams unchanged: grilled lemon chicken (recipe
0637, "peel skin off chicken, leaving skin on wings") reads `"from the
printed weight × 0.43 edible (USDA ready-to-cook yield) · approximate (skin
discarded except the wings; the bird's meat-only yield)"` at 788 g. A step
that takes the skin "from the <part>" (breast, thigh,
leg, wing, drumstick) trips only a line whose item names that part:
classic chicken noodle soup's whole bird, whose step discards "the skin
and bones from the breast pieces" only, stays on 171447 at 1,104 g;
Chicken Provençal's "from the chicken thighs" still trips. The breast is NOT
enabled: 171077 "Chicken, broiler or fryers, breast, skinless, boneless,
meat only, raw" publishes only "oz" 113 g, "package" 926 g and "piece"
272 g — no half breast to set against 171474's "0.5 breast, bone removed"
145 g — so the 5 breast lines stay at the bone yield with no skin step. **Shellfish**: the `in_shell`
paragraph above. **Canned coconut milk** (Q8): `coconut milk`,
`unsweetened coconut milk` and `regular or light coconut milk` (read as
regular: no light canned record is cached) read the cached `canned coconut
milk` answer, ranked as SR 170173 "Nuts, coconut milk, canned (liquid
expressed from grated meat and water)" (197 kcal/100 g), never FNDDS
2705413 "Coconut milk", the 31 kcal drink: 9 lines, unflagged (it is the
food); 9 recipes by more than 10 % (Thai green curry +105 %). A can keeps
its printed weight; the two volume lines read the `milk` density 1.03 as
the library's three `canned coconut milk` lines on 170173 already do (¾
cup 182.76 g, ½ cup 121.84 g — not 170173's `cup` 226 g, which would also
move those three). "¼ cup heavy cream or coconut milk" (its first option)
and `cream of coconut` (FNDDS 2707571) are other items. **Size words**
(Q9 (a), one scale): "small" or "large" in the item's own words — before
the first comma, outside a paren, before a cut ("2 medium onions, cut into
large pieces" stays medium) — on a count read from the piece table's
onion (any colour), carrot or round tomato reads the size portion of the
SR record its medium figure is: onion 170000 `small` 70 g / `large` 150 g,
carrot 170393 `small (5-1/2" long)` 50 g / `large (7-1/4" to 8-/1/2"
long)` 72 g, tomato 170457 `small whole` 91 g / `large whole` 182 g;
unflagged (FDC's own figures; basis `"1 × 150 g each"`). A plum tomato is
170457's `plum tomato` 62 g, small or not (no small plum is published).
118 lines (114 sized, 4 plum), 0 recipes by more than 10 %. Untouched:
"large" eggs (the 50/17/33 g figures are the large egg), "1 small celery
rib" (40 g — the corpus prints a small rib at 25–50 g, not SR's 17 g),
"large shrimp (31 to 40 per pound)", "small head", a green onion, the
cherry and grape tomato; unsized onions stay on SR's 110 g medium (C2, the
Foundation "Edible" onion, is not built). **Prep loss** (Q6): a prep word
reduces a line only when its grams are a PRINTED WEIGHT and the word sits
in the line's tail, after its first top-level comma (outside a paren); a
head word ("1 (14.5-ounce) can whole peeled tomatoes") names a prepared
product, and a count or portion read is already edible. Two shapes have a
figure: a counted item **peeled** on a record publishing a "Peeled"
portion (only Foundation's bananas, 1105314 115 g and 1105073 110 g) reads
the count × that portion, unflagged, basis `"6 × 115 g (USDA "Peeled"
portion)"` (ultimate banana bread 1,020.6 → 690 g; mulligatawny's banana
141.75 → 115 g; the detail is read for such a line on a Foundation
record); and a canned tomato (Foundation 333281 diced, 2685578 whole)
**drained** with no juice "reserved" anywhere in the line counts × 0.54,
flagged `approximate (ATK: 2 (28-ounce) cans whole tomatoes, drained, give
3 cups juice)` — ATK's printed "2 (28-ounce) cans whole tomatoes …,
drained, 3 cups juice reserved" by SR's juice cup: 28 lines (hearty lentil
soup 411.07 → 221.98 g), 0 recipes by more than 10 %; the 16 lines that
reserve juice put it back later and are untouched. Every other prep word
(peeled or cored produce, leek greens, scallion parts, deveined shrimp,
rinsed beans) has no figure and no rule. **Canned beans** (matcher v42,
the owner's ruling (b) 2026-10-06): a line naming a can or cans whose
grams are its PRINTED weight on one of the six Foundation "canned, sodium
added, drained and rinsed" bean records (2644288 chickpeas, 2644289 dark
red kidney, 2644292 pinto, 2644285 black, 2644287 cannellini, 2644286
navy) counts × its bean's drained share — FDC's own SR can pair, drained ÷
whole, to 3 dp: chickpea 0.565 (173800 "can drained" 253 g of 175206 "can
(total can contents)" 448 g), kidney 0.610 (174285 "can drained solids"
266 g of 175195 "can" 436 g), pinto 0.627 (174286 "can drained solids"
277 g of 175201 "can" 442 g); black, cannellini and navy, with no pair,
the three pairs' median 0.610. Flagged: basis `"from the printed weight ×
0.565 drained · approximate (drained weight: FDC's canned chickpea pair,
253 g of 448 g)"`, or `"… · approximate (drained weight: the median of
FDC's three canned-bean pairs, 0.610)"`. The rinsed kidney record 175243
publishes only a cup, so rinsing adds no factor. A line that keeps the
liquid — "undrained", "do not drain", "liquid reserved", "with their
liquid" — counts the can whole (chana masala, pasta e ceci, acquacotta);
"1 can drained, 1 can [left] undrained" takes the share on half the cans
(`"… × 0.565 drained on half the cans · …"`: espinacas con garbanzos
850.49 → 665.50 g, the garlicky shrimp stew 850.49 → 684.64 g). Since
matcher v49 (M47 Q14): a can with no drain word whose steps add it "and
their liquid" is whole too, and a can kept whole moves to its cached
solids-and-liquids twin (chickpeas 175206, pinto 175201, kidney 175195),
the half rule's undrained can a part there — the v49 paragraph. 22 lines
sit on the six records by a printed can weight: 19 change grams (harira
425.24 → 240.26 g; beef chili with kidney beans 850.49 → 518.80 g), 3 keep
the liquid; no bucket, hold or status moves; 10 recipes by more than 10 %
(ultracreamy hummus −22.4 %, pasta e fagioli −21.5 %). A canned-bean line
read from a cup (the hearty green salad's ⅔ cup) is untouched, as are
butter beans (FNDDS 2709850). The canned-bean live step (2026-10-06, on a
scratch copy of snapshot 17: 5 food details — 174285, 175195, 174286,
175201, 175243 — the result snapshot 18) brings the accuracy track's live
requests to 60.
**AH-102 poultry yields** (matcher v43, the owner's rulings Y1–Y7, Y12,
Y13 of 2026-10-06, "go with your recommendations"; zero requests). USDA
Agriculture Handbook No. 102, *Food Yields Summarized by Different Stages
of Preparation* (revised 1975), Table 1 raw boning data, replaces the
whole bird's 0.608 for bone-in chicken and turkey PARTS weighed from a
printed weight (`ah102Parts`). The part is the one the line names
(`birdPartOf`): a whole-bird line is whole; "chicken pieces/parts" and
"breasts and/or leg quarters" are pieces, a turkey's "drumsticks and
thighs" its leg; else the part named FIRST, parentheses aside ("3 pounds
split bone-in chicken breast (or thighs or drumsticks)" is breast); else
the record's own part. The RECORD decides the figure (Y13): a meat-only
record (2646171, 173619, 171052, 2646170, 174518, 171497) reads the
part's MEAT figure, a meat-and-skin record (171447, 2727566–69, 172378,
171081, 171533) meat and skin — whoever put the row there (a person's
pick of 2646171 for Chicken Teriyaki's skin-eaten thighs reads 59 %, where
v39 kept meat-and-skin grams on the meat record). A skin-discarded part
therefore reads its meat figure in ONE step from the printed weight (Y12:
the owner reversed the morning's "keep 0.795" with the handbook's numbers
in hand; v39's stack of the bone yield × FDC SR's skin share 0.795 / 0.770
is retired, `skinShares` deleted). Flag `"… × <share> edible · approximate
(<source>)"`, the share to two places:

| part | item | meat and skin | meat |
|---|---|---|---|
| chicken breast | 584 | 74 % (59–84) | 65 % (50–77) |
| chicken thigh | 586 | 70 % (63–81) | 59 % (48–68) |
| chicken drumstick | 585 | 63 % (50–75) | 55 % (44–69) |
| chicken wing | 590 | 50 % (41–60) | 31 % (13–42) |
| chicken leg (thigh + drumstick) — DERIVED; also a leg quarter | 585–586 by 583's carcass shares 19/17 | 66.7 % | 57.1 % |
| chicken pieces (breast, thigh, drumstick) — DERIVED | 584–586 by 27/19/17 | 69.8 % | 60.5 % |
| turkey thigh | 2598 | 82 % (77–85) | 77 % (76–80) |
| turkey drumstick | 2597 | 69 % (66–74) | 65 % (62–70) |
| turkey leg | 2596 | 75 % (70–79) | 71 % (66–74) |
| turkey leg quarter | 2595 | 71 % (69–73) | 64 % (62–65) |
| turkey wing | 2602 | 61 % (59–64) | 43 % (42–45) |
| whole turkey | dressing data, 12 lb and over (78 of 85) × 2592 | 0.6515 = 78/85 × 71 % (67–75) | — |

The derived rows say so (`"derived from USDA AH-102 items 585–586 by
583's carcass shares: leg (thigh + drumstick), raw → meat and skin
66.7 %; a leg quarter's back portion is not in this figure"`): the
handbook prints no chicken leg-quarter row (items 584–591 are breast,
drumstick, thigh, back, rib back, tail back, wing, neck), and a retail
leg quarter carries part of the back, so the figure reads high by an
unprinted amount. The turkey rows are the fryer-roaster class (the only
class boned; flagged "fryer-roaster class"); the whole turkey takes the
handbook's dressing ratio for birds of 12 lb and over (ready to cook
without / with neck and giblets, 78 of 85 — every library turkey is 12–22
lb and gives up its neck and giblets) × the carcass row 2592:
`"… × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb
and over (neck and giblets off 78 of 85); carcass → meat and skin, item
2592, fryer-roaster class, 71 % (67–75))"` (a 12- to 14-pound turkey
3,864 → 4,137.40 g). A skin-discarded breast on 2727569 now moves to
Foundation 2646170 "Chicken, breast, boneless, skinless, raw" (Y3,
`skinlessRecords`) at 584's meat 65 %; a Confirm records 2727569. All
five breast lines the v40 live step named trip the skin signal and move
(hearty chicken noodle soup, old-fashioned slow-cooker chicken noodle soup,
French-style chicken and stuffing in a pot, tortilla soup, white chicken
chili 828 → 884.50 g); the signal's "reserve" veto no longer reads
"reserved (cooked) chicken" — the meat kept, not the skin — so hearty
chicken noodle soup's "remove the skin and bones from the reserved cooked
chicken and discard" trips (414 → 442.25 g).
KEPT: whole chickens read FDC's own ready-to-cook yields (Y4: 171447 0.608,
171052 0.434, inside the handbook's whole-bird 58 (50–62) / 47 (40–53)),
with grilled lemon chicken's wing flag; the bone-in turkey BREAST (171093,
8 lines) keeps the interim 0.608 (Y7, DEFERRED: item 2593's breast, 87 %,
is a breast without the back ATK's bone-in breast carries, and no
breast-with-back row exists — closed by matcher v59's derived 66.77 %, M60
Y); the per-item and hen portions. 74 lines move
(56 chicken, 18 turkey), +17,515 kcal over the library; no bucket, hold or
status moves; Chicken Provençal's 8 thighs 657.92 → 802.86 g, barbecued
pulled chicken's leg quarters 1,488.31 → 1,813.36 g, buffalo wings 828 →
680.39 g. 1975 averages over the birds measured then, the ranges the
honest width.
**AH-102 produce and meat yields** (matcher v43, the owner's rulings Y8–Y11
of 2026-10-06; zero requests). Same handbook, Table 1 paring/trimming and
boning data, 1975 all-samples averages (no Granny Smith, Yukon Gold or
other modern cultivar row exists; Russet Burbank's 86 is not "russet").
**Produce (Y8, `produceYields`)**: a line whose printed weight is in its
HEAD (before its first top-level comma: "1½ pounds Golden Delicious apples
(about 3 large), peeled, cored, …", "1 medium butternut squash (about 2
pounds), peeled, …"), on one of the records below, with the prep word
word-bounded in its TAIL, counts the yield, flagged
`"from 1 1/2 pound × 0.78 edible · approximate (USDA AH-102 item 17: apples,
all cultivars, raw whole → flesh, pared and cored 78 % (60–87))"`. Never a
count read ("1 Granny Smith apple, peeled, cored, and shredded" is 1 ×
182 g, already edible), never a trailing prepared weight ("2 carrots,
peeled … (⅔ cup or 3 ounces)"), never "unpeeled", never a line that keeps
peels ("¼ of peels reserved"), and never a part clause whose line names
the other part as used too (a later "green parts", "white parts" or
"greens"; the scallion rule shares the check): "1½ pounds leeks, white and
light green parts halved lengthwise, …; 3 cups coarsely chopped dark green
parts, washed" eats the whole leek and stays `"from 1 1/2 pound"`:

| food (records) | prep word in the tail | item | stage | share |
|---|---|---|---|---|
| potatoes (2346401, 2346402, 2346403) | peeled | 2018 | all samples → pared, raw | 81 % (61–94) |
| apples (1750342, 168202, 2709215) | peeled | 17 | all cultivars → flesh, pared and cored | 78 % (60–87) |
| apples, same records | cored (not peeled) | 30 | all cultivars → cored only | 90 % (84–94) |
| sweet potatoes (168482) | peeled | 2496 | raw whole → hand or machine pared | 80 % (69–91) |
| pears (167778, 746773) | peeled | 1734 | raw whole → pared, cored flesh | 78 % (40–88) |
| carrots (2258586) | peeled | 481 | without tops → hand-scraped root | 82 % (58–93) |
| onions (1104962) | peeled | 1568 | mature, all samples → peeled | 90 % (50–99) |
| leeks (2709935) | white and light green part(s) | 1412 | raw → bulb and lower leaf | 44 % (35–58) |
| savoy cabbage (170388) — savoy is not printed: head cabbage stands in | cored, trimmed | 440 | whole head, green, red or white → ready to cook, without core | 93 % (91–96) |
| cauliflower (2685573) | cored, trimmed | 499 | whole head → fully trimmed, head or flowerbud | 92 % (83–100) |
| butternut squash (2685570) | peeled | 2459 | raw whole → flesh | 84 % (75–88) |
| zucchini (2685568) | trimmed | 2446 | raw whole → flesh and skin (ends 7) | 93 % (86–98) |
| yellow summer squash (2685569) | trimmed | 2444 | all samples → flesh and skin | 95 % (84–99) |
| strawberries (2346409) | hulled, stemmed | 2473 | good quality → flesh | 94 % (86–99) |

**Scallions (Y9, `scallionPartOf`)**: a COUNTED scallion (FNDDS 2709794,
"1 whole" 15 g) whose tail begins "white parts only" counts × 0.37
(`"(USDA AH-102 item 1575: white part 37 % (22–50) of the whole scallion
with rootlets)"`), "green parts only" × 0.59 — DERIVED: 1575's green tops
and rootlets 63 % (50–78) less 1573's rootlets 4 %. The base is the whole
scallion WITH its rootlets, as printed (whether FNDDS's "1 whole" carries
them is not known; 37/96 would be 0.385). Not "white and light green parts
only" nor "dark green parts only" (no figure is printed for them), not a
cup of greens, never a carrot or an onion. **Meats (Y10, `ah102Meats`)**:
where the handbook names the cut, its raw boning figure (lean and fat meat
as bought) replaces the borrowed class figure above, flagged with the item:

| cut (record) | item | yield | v42 |
|---|---|---|---|
| pork spareribs (167853) | 1925 | 58 % (43–71; bones 42) | 0.653 |
| beef standing rib (168675) | 238, retail ribs 11–12 | 82 % (78–86; bones 18) | 0.758 |
| beef fore shank (169441) — MISMATCH: lean and fat 61 %, "weighed on a lean-only record" | 228 | 61 % (59–62; bones 39) | 0.657 |
| lamb rack (172641, "fully frenched") — MISMATCH: "as measured unfrenched; a frenched rack yields less" | 1364, rib loin | 73 % (61–88) | 0.657 |
| lamb foreshank (172513) | 1339, choice foreleg (limited data) | 70 % (bones 30) | 0.657 |
| cured spiral-sliced ham (169177) — the figure also removes rind 5 and excess fat 15 a spiral ham may no longer carry | 1937, bone-in rind-on | 70 % (60–78) | 0.758 |
| fresh ham shank half (168226) — DERIVED: 1 − bones 22 (the printed row also trims the fat 18: lean 60 %) | 1930 | 78 % | 0.758 |

FDC's own refuse classes stay (168242 chops 0.662, 167849 butt 0.758,
167895 country ribs 0.653, oxtails 0.564), as do the blade chops, baby
back ribs, short/back ribs, picnic, lamb shoulder chops, veal shank and ham
hocks (no row). **Shellfish (matcher v49, M47 Q11, `ah102Shells`)**, read
for a weight bought in the shell on the raw record (transcribed into
`.claude/diag/2026-10-06/ah102_produce_meat.md`, read on the page crops):

| shellfish (record) | item | yield |
|---|---|---|
| shrimp, headless, in shell, thawed raw (SR 175179) | 2333 | shelled, deveined 81 % (77–82; shell 15, veins and handling 4) |
| mussels, whole (SR 174216; FNDDS 2706350 lines move there) | 1531 | drained solids, raw 29 % (25–33); solids and liquor 1530: 51 % (43–56) |

**Bacon (Y11)**: rule B1 keeps 0.403 (FDC's own protein
balance between the two records the row is counted on); the handbook's
cooked sliced bacon, items 1981–1985 (all methods 33 % (18–43), broiled 29,
oven 34, microwave 32, pan fried 29), is the comparison: 0.403 sits inside its
range (18–43), 7 points above the all-methods average — the 13 B1 rows do
not move. (Re-ruled by matcher v51, M49 Q4 (b): item 1981's 33 % is the
yield since — below.)
124 lines move (103 produce, −11,947 kcal; 6 scallion, −56; 15 meat,
−1,083: spareribs −2,754, prime rib +1,905); no bucket, hold or status
moves; rustic potato-leek soup −34.6 % a serving (its leeks 2,041.16 →
898.11 g). The bone-in turkey BREAST stays DEFERRED (above).
Since matcher v40 (edible yields, part 2 — the owner's live step,
2026-10-05 on a scratch copy of snapshot 16: 13 requests, 3 searches and
10 food details, the result snapshot 17; the accuracy track's live
requests now total 55 with the 42 above): the whole bird and pieces skin
move to 171052 and the clams' shell yield on 174214 (both above); not
enabled, with FDC's answers above: the breast share, the whole-turkey
yield, mussels, canned beans.
Since matcher v31 (the CP10 rulings, 2026-10-03): star
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
khorasan, cooked)"`, 473 g), since matcher v37 "Sprigs fresh Thai or
Italian basil" as basil (2709780) and Mexican crema as full-fat sour
cream (2346387), both 0 g lines, since matcher v37 (the S groups, every
one a food FDC has no record of) mirin as the sweet dessert wine
(2710692), gochujang and gochujang paste as sriracha (171186, ATK's own
"equal amount of sriracha"), doenjang as SR miso (172442, ATK's
"substitute red or white miso"), galangal as ginger root (169231),
culantro as cilantro leaves (169997), alcaparrado as green olives
(2710089), multicolored nonpareils as granulated sugar (746784, by
sugar's own portions), five-spice powder as pumpkin pie spice (171332),
garam masala as curry powder (170924), Sichuan and pink peppercorns as
black pepper (170931), canned chipotle chile in adobo as sriracha
(171186; the count line "1 chipotle chile in adobo sauce" gets the food
only, no grams), skinless white fish fillets as Atlantic cod (2684444)
and mixed fresh herbs as fresh parsley (170416), and crème fraîche as
heavy cream (2346386), since matcher v38 ya cai as salted mustard cabbage
(169891, "Cabbage, mustard, salted": "⅓ cup ya cai" is `"1/3 cup · USDA
portion · approximation (counted as Cabbage, mustard, salted)"`, 42.67 g),
since matcher v45 dairy-free sour cream as imitation sour cream (2705617),
since matcher v46 mascarpone as heavy cream (2346386), potato starch as
cornstarch (169698), brown rice flour as white rice flour (790214) and
nutritional yeast as FNDDS "Yeast" (2710005)
— and a FRESH oregano, sage,
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
recipe, not counted in these totals". Until matcher v41 it was resolved
like a water line; since v41 such a line is first READ as a reference to a
recipe (the matches GET's v41 block: routed to a library recipe and counted
at its share, R1; held `choose_recipe` / `discarded_recipe`; or, not routed,
this 0 g rule row) and the rule row is NOT accounted — its recipe reads
partial (R3, the owner's A3 a). A
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
is a reference line (v41: routed, held, or the 0 g rule row above). A
measured "plus" part of another food is eaten and counted as
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
confirm (matcher v16) — (a bare count of the food, "3 hard-cooked eggs (recipe
follows)", its food giving no grams, is stored as the 0 g sub-recipe; the
ingredient's decision is still recorded. On any other reference line a pick
with no grams typed is refused since v41 — 422, the PUT's v41 table — unless
the line's alternative after its first top-level " or " carries an amount,
A10 a). The engine's own rows — a sub-recipe's, a seasoning's, an
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

**Matcher v41: a recipe for a reference line.** Two body keys beside
`fdc_id` / `grams`: `child` (a library recipe's slug or id) and `share`
(a number, 0 < share ≤ 100; optional — absent, the line's own share of the
child, as the compute reads it; required when that share cannot be read). The actions on a composite row: Pick a
recipe `{raw, child}` (stored `overridden`, the child at the share,
derived at once: grams = the child's total grams × the share; the default
flag cleared); Save share `{raw, child: <current>, share}` (the same child,
a confirmed row stays `confirmed`); Confirm `{raw, confirmed: true}`
(`confirmed`, the child kept; on a `discarded_recipe` marinade: poured
away — the row keeps its hold and stores NO grams, `grams` and
`gram_source` null, and the totals count it as an accounted zero, the
recipe complete when nothing else is open); Skip `{raw, skipped: true}`. A child that is itself
made from a recipe is ACCEPTED and stored held `nested_recipe` (0 g). A
recipe decision is NEVER written to `ingredient_decisions` (A1 b): it
reaches other recipes only by `apply_to_all`. The action table decides what
a row accepts: a ROUTED row (it carries a child, no hold) reads
`routedActions` — skip, confirm, recipe; may be applied to others — a held
reference `choose_recipe` / `nested_recipe` skip or recipe, the marinade
`discarded_recipe` skip, confirm or recipe. A NOT-ROUTED reference row (the
0 g rule row, R3) takes no recipe and no bare food pick (S14); it reads the
unheld table, so as shipped before v41 it also accepts a confirm — which
changes nothing counted: the row stays the engine's rule row (stored with no
grams until the next compute rewrites it at 0 g), the recipe partial — and a
food pick WITH grams typed (`{raw, fdc_id, grams}`), which answers the line
on that food at those grams ahead of the sub-recipe rule (Run 051 B3; the
design's S14 refused every food pick there — kept as shipped, the owner's
call): stored `overridden`, accounted, so the recipe can read complete
(pumpkin-pie's "1 recipe Basic Single-Crust Pie Dough (this page), …" as
100 g of a food: 13/13).
The 422s, each before anything is written:

| request | message |
|---|---|
| `child` with `skipped` | `'skipped' cannot be combined with 'fdc_id', 'confirmed', 'grams' or 'child' — one decision per request.` |
| `child` with `fdc_id`, `confirmed` or `grams` | `'child' cannot be combined with 'fdc_id', 'confirmed' or 'grams' — one decision per request.` |
| `child` not a string, or no such recipe | `No recipe with that id.` |
| `child` = the recipe itself | `A recipe cannot be made from itself.` |
| `child` on a line that is no reference | `This line is not made from a recipe.` |
| `child` with no stored totals | `That recipe has no totals yet — compute it first.` |
| `share` not a number, ≤ 0 or > 100 | `'share' must be a positive number (at most 100).` |
| `share` without `child` | `Pick a recipe first, then set the share.` |
| `child` with no `share`, on a line whose share of that recipe its yield cannot read | `No share the yield can read — set the share.` |
| a food, a confirm or grams refused on a routed row | `This line is made from a recipe — confirm it, choose another recipe, or skip the line.` |
| a confirm, a food or grams on `choose_recipe` / `nested_recipe` | `This line is made from a recipe — choose a recipe, or skip the line.` |
| a food or grams on `discarded_recipe` | `This marinade is poured away — confirm it, choose a recipe, or skip the line.` |
| a food pick with no grams typed, or a recipe, on a not-routed reference line (S14; A10 a's amount-bearing alternative excepted) | `This line is made from a recipe that is not counted yet — skip the line if the recipe is made without it.` |
| `apply_to_all` on a held reference line (a LINE hold) | `A held recipe line is decided in this recipe only.` |
| `apply_to_all` on a routed row with no recipe decision in the request | `'apply_to_all' needs a recipe decision in this request — choose a recipe (child) or confirm the current one.` |

(The not-routed and the needs-a-recipe-decision texts are new beside the
design's list; the owner may reword any.) `apply_to_all` on a ROUTED row —
chosen by the row, so a Confirm and a pick alike — runs the recipe twin:
every row of the recipe reach (the matches body's `others_lines`) is
written `overridden` on the decided child at ITS OWN line's share, its
default flag cleared, derived with no request, and its recipe's totals
recomputed; a row a person decided meanwhile stands (`decided`); the
receipt is the same `applied` object. A food pick on a routed or held
reference row is refused (the table above); on a not-routed one, a pick
with no grams typed is refused unless its alternative after the first
top-level " or " carries an amount (A10 a: weighed on it, an ingredient
decision as any pick).

**Matcher v44: a section for a reference line.** One more body key beside
`child`: `section` — the exact title of a section of the `child` recipe
(`{raw, child: <recipe slug or id>, section: <title>, share?}`); an OWN
section is picked with `child` = this recipe (glazed-spiral-sliced-ham|2
`{child: "glazed-spiral-sliced-ham", section: "Cherry-Port Glaze"}`). It is
accepted on the same lines and holds as a library recipe, stored the same
way (`overridden`, the share typed else the line's share of the SECTION's
yield; a section holding a reference stored held `nested_recipe`); never an
ingredient decision, never applied to others (the reach above). With
`?section=<title>` the PUT decides a line OF that section (404 "No section
with that title." for none); the response is that section's matches body.
The section 422s, before anything is written (texts from the approved copy
delta §6; the v41 table's rows stand):

| request | message |
|---|---|
| `child` on a line of a section (`?section=` on the PUT) | `Only one level is read — a section's line is not made from another recipe.` |
| `section` without `child` | `Pick a recipe first, then its section.` |
| `child` holding a `#` (a storage key never travels) | `No recipe with that id.` |
| `section` not a string, or no section of that recipe has the title | `No section with that title in that recipe.` |
| `child` = the recipe itself with no `section` | `A recipe cannot be made from itself.` |
| a `discarded_recipe` marinade picked with no `share` (S10 (a): the share eaten is a person's) | `Set the share that is eaten — the rest is poured away.` |
| `section` that lists no ingredients | `That section lists no ingredients — it cannot be counted.` |
| `section` with no stored totals | `That section has no totals yet — compute its recipe first.` |
| `section` with no `share`, the section's yield gives none | `No share the yield can read — set the share.` |

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
**v47 (F3, Run 062 O3 / Run 061 S5) — the receipt counts RECIPES; a
section key never reaches it.** A reached line in a recipe's SECTION
counts its host in `recipes` (once, with any main line of it). A section is
not a recipe: what an apply completing one completes is the PARENTS routed
to it (the engine's route or a person's pick — the recipes a section
group's `finishes_recipes` credits), and `completed` / `completed_recipes`
name those whose stored status turns `complete`. They do in the SAME
request: every parent of a section the request recomputed has its rows on
that section re-derived as its compute derives them (the section's new
total grams × the share, its new stamp — no FDC request) and its totals
recomputed, its stamp kept (its own inputs did not move), so it reads fresh
— before, the parents stayed stored `partial` and read stale (`child_stamp`
behind) until a `stale` sweep, while the banner already dropped them from
`open_recipes`, and the receipt named the section KEYS. A single PUT on a
section's own line (`?section=`) does the same, apply or not: the grilled
corn's "Spicy Old Bay Butter" line confirmed completes the corn in that
request. With `apply_to_all` on a section's line, the parents that line's
own write completed, other than its host (the decided line's own recipe, as
the app's promise reads it), are in `completed_recipes` too. Measured on a
copy of the v46 replay library (cache only, 0 requests): pork-tenderloin|3
→ "Satay Glaze" and chicken-breasts|6 → "Coconut-Curry Glaze" picked, the
"red curry paste" group promises [gado-gado, chicken, pork] (`finishes` 3,
banner 76 / 209); gado-gado|0 confirmed with `apply_to_all` →
`completed_recipes` [pork, chicken] (was the two section keys), both stored
`complete` and fresh, the banner 73 / 206.
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
selected, so a `stale` sweep that finds nothing is visible immediately —
v47 (F12): RECIPES only; the sections the scope selects, computed first,
move neither `total` nor `done`);
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
{"missing": 1190, "stale": 3, "all": 1198,
 "sections": {"missing": 140, "stale": 2, "all": 140}}
```

The same selection the sweep runs (`bulkScopeIds`), so each number is the
`total` the corresponding 202 would echo. v47 (F12): the three numbers
count RECIPES; `sections` counts apart the recipe subsections (v44) each
scope computes first — before, a section counted as a recipe (`all` read
1,338 on the 1,198-recipe library). Re-read it after a job finishes;
a `stale` count of `0` means every computed recipe still matches its
ingredients. Spends no FDC budget and writes nothing, so a `read` PAT may
read it — but it decodes the library, resolves its child sections and
hashes every computed recipe synchronously on the serving isolate (v47
F10: ONE read for the three scopes, ~0.42–0.55 s on snapshot 20, was
~0.94–1.28 s), which makes
this a [side-effectful GET](#cross-site-gets): a cookie session with neither
`X-Requested-With` nor a same-origin `Sec-Fetch-Site` gets `403 csrf`.

### `GET /api/v1/nutrition/jobs/{id}` (admin)

`{id, status, total, done, failed, log, started_at, finished_at}`.
`total` / `done` count recipes (v47, F12); a `log` line names a recipe by
its id and a section as `{host slug} · {title}` (never its storage key).

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
- **Version skew — a known gap (v47 F13, Run 062 critic; deferred):** the
  server does not check the client's build. Since v44 a section candidate
  and a routed section child carry their HOST's `slug` plus a `section`
  title; an app bundle from before v44 knows no `section` key, so a tab
  left open across a deploy PUTs `{raw, child: <host slug>}` (or `Save
  share` with `{child: <host slug>, share}`) on a line routed to another
  recipe's section — stored as a person's pick of that host's WHOLE recipe
  (an own section's host is refused, `selfRecipeMessage`). Decided rows
  survive every sweep, so the wrong grams stay unflagged. Mitigation: deploy
  the server and the app together (the server half alone is never
  deployed), and reload every open admin tab after a deploy. A version
  header (a stale client answered `409` "reload the app") or a PUT refusing
  a host-slug child on a line whose stored child is a section key is a later
  design.

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
