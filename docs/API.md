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

**v70 (F10, review Run 064's critic):** each subsection is held to the
recipe's own editor caps — at most 60 ingredient groups and 400 lines
(each line's `raw` 1–1,000 characters, `item`/`prep` ≤ 500, ≤ 8 amounts),
at most 120 steps of 1–10,000 characters — with the same `422 validation`
messages ("At most 400 ingredient lines.", "At most 120 steps.", "'step
text' must be 1-10000 characters.", …); before, only the 2 MB body bounded
a subsection. The import and the rescan apply it too; every corpus recipe
validates (its largest subsection: 18 lines, 9 steps, 906 characters).

**v81 (F14, review Run 065/066's critic):** an amount's `quantity` may not
print a number of 10 or more digits (a recipe's line or a subsection's) →
`422 validation` "'amount quantity' must print numbers of at most 9
digits."; the import and the rescan apply it too (the import counts the
file failed, the rescan skips it with `reason` "fails validation: …" and
keeps the stored version). No corpus quantity prints more than 2 digits.

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
since matcher v64 `gel food dye` too, the rainbow cake's; since matcher
v73 `makrut lime leaves` and `ground lapsang souchong tea leaves` — M73
below)
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
  PO, below), or one an unmarked line names (A9; since matcher v76 also by
  the yield-named tail — M76 below; since v91 by a two-word shared tail —
  M87) — 140 on snapshot 19 (936 lines); 144
  on snapshot 27 at matcher v76 (caramelized-onion-pear-and-bacon-tart's
  "Classic Pizza Dough" the 144th). A prose section (no ingredient lines) is never one. The bulk
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
  recipe. **v76 (M76, Q3 (a)):** so is an UNMARKED line with an amount
  whose item is the TAIL of an own section's title AND whose amount is that
  section's printed yield (`parseShare` == 1.0) — the tart's "1 pound pizza
  dough" → its "Classic Pizza Dough" (MAKES 1 POUND); a marked line keeps
  the forms above (M76 below). A section's rules read the SECTION's own
  steps (most store none).
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
2709268 → SR 167758; since matcher v77 Foundation 748608 extra-virgin olive
oil → SR 171413, whose discarded rows — a poured-off oil's kept part — say
so too; the food and grams stay the line's, and it is not held
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
counted as 0 g"`, `"no amount on the line — counted as 0 g"` (since
matcher v71, an amount the steps print for it: `"from step 2: 1 tablespoon
(no amount on the line)"`), `"4
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
crumb joins the budget; since matcher v68 (M69) a thin piece's sautéed
dusting (C4) and a coated eggplant baked after the coat count too — the
thick pieces' dustings, the onion rings and a fried coated eggplant stay
held; since matcher v80 (M80-1) a coated onion baked after the coat counts
too, a fried one stays held), `partial_pour_away` (since v22, Q4: a line of a braising
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
50 g only — enabled since matcher v69, M70 below, on the Sure-Jell label's
4 g a teaspoon), fennel fronds (FNDDS 2709779: `1 fennel bulb` 235 g, `Quantity
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
mussel, blue, raw" (engine `_shellRecords`, the `_skinlessRecords` record
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
("Measure 1 tablespoon of solids …", grilled potatoes — since matcher v71,
M71 below, that kept tablespoon is counted, shared by the strained lines). A numbered part the
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
(5) **The frying MARK (critic F13):** the food a frying oil's kept-part
pour-off step fries before it ("Transfer the potatoes and remaining 1 cup
oil to the skillet" → the potato) takes its uptake on top of the kept part
through the coats-and-uptake batch's (M52) own fried-food arm in
`_m52Plan` — a vegetable a sentence names with the oil
(`memo:friedNamed`); no grams move on it here (the crispy tempeh, fried a
step before its pour-off, carries none). The four cured-pork rows M50 settled (Barolo,
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
grams than a flour dredge for the same carbohydrate (since matcher v88, M88,
FNDDS 2706442's read splits them: its flour parts share a dredge budget by
carbohydrate, its other parts a crumb budget by dry-crumb mass); a written part eaten
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
| C2 baked | a bake after the coat that is also after the last frying sentence — the LAST cook decides (critic F2: 0118's cutlets and 0149's chicken are browned or fried, then baked) | chicken 3.18, legs 3.10, fish 7.41, pork 6.61; since matcher v68 (M69 R2) a coated eggplant 7.93; since matcher v80 (M80) a coated onion 50.53 (a stand-in) and a chicken whose budgeted parts include a `Bread,` record 12.12 (a nut part beside it a stand-in; since matcher v88, M88, its flour parts share 3.55 g carbohydrate and its other parts 11.905 g dry crumbs per 100 g raw, 12.12 sizing the dip only) | FNDDS 2705980, 2705998, 2706243, 2705871; 2710050; 2710042, 2706442 |
| C3 | fried Mollusks or Crustaceans with no crumb line | 3.94 | SR 171982, derived |
| C4 sautéed (since matcher v68, M69 R1) | a held coat on a THIN meat (a step pounds it ⅛–½ inch thick, or its line prints the thickness) that is neither fried nor baked after the coat | 3.18 (C2's read, a stand-in — the owner's ruling) | FNDDS 2705980 |
| C5 | a fried fish a sentence batters; the recipe's counted flour and starch come off B (since matcher v57 also battered shrimp, each on its own record, and a batter's own lines are parts, never off B — below) | 15.38 | FNDDS 2706244 (v57: shrimp 2706364, haddock 2706258) |

Stay held (20 rows): C4 sautéed dustings (neither fried nor baked —
piccata, marsala, saltimbocca, meunière, francese, seared salmon and pork),
coats with no meat line (eggplant parmesan, oven-fried onion rings), and
nut and cheese layers (a Nuts or Cheese record) — since matcher v65 (M66
R3, below) only a layer no step sentence names with a crumb. Since matcher
v68 (M69, below) a THIN piece's sautéed dusting counts as C4 and the
eggplant parmesan's coat on its own read; the thick pieces' dustings and
the onion rings stay held. Since matcher v80 (M80-1, below) the onion
rings' coat counts on the onion, a stand-in; the thick pieces' dustings stay
held.

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
tempeh (its 28 g kept part counted), confit, yuca (no nutrients; since
matcher v69, M70 below, on cassava at FNDDS 2709565's read 15 %), and the
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
  (Since matcher v67 the WHOLE brisket's ¼-inch cap reads its own ⅛"
  record, 168664 — batch M68 below; since matcher v69 the flat reads
  173128 with its braised pair's energy share — batch M70 below.)
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
  lives only under R1c, F12). Brisket pairs are not here (since matcher
  v67 the whole brisket's is: 168607 → 168664, batch M68). At M56 174414
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
the whole brisket on 168607 (on 168664 since matcher v67, M68), the
oxtails ("¼ inch or less") and the pork rib roast ("¼-inch thickness").

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
figure; since matcher v88, on FNDDS 2706442's read, M88's f_d / f_c — no
corpus batter reaches it). A C5 budget no longer subtracts a batter line's carbohydrate
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
join; since matcher v66 a dough the steps cut counts only the cut share,
below). Each product's figure (u, the oil absorbed per 100 g of raw mix):

| product | record | u | how |
|---|---|---|---|
| pakoras | FNDDS 2710066 "Pakora" | 8.43 % | READ: 21 g oil per 249.18 g of its raw inputs other than the oil and 355.5 g of water |
| fritters, a bare batter | 2710066, a stand-in | 8.43 % | the same read, flagged `(no record for fritter batter; read as Pakora)` for fritters, `(no record for batter; read as Pakora)` for a bare batter |
| lumpia, spring rolls, egg rolls | FNDDS 2708702 "Egg roll, with beef and/or pork" (a stand-in but for egg rolls) | 7.62 % | READ: 8 g oil per 104.99 g — its prepared vegetable egg roll at the listed 90 g (no raw pair), its 10 g of pork steak (2705875) brought to raw by protein on the lumpia's own raw pork (2514745): 14.99 g |
| struffoli; a doughnut or dough with no yeast row | FNDDS 2708024 "Fritter, plain", a stand-in (since matcher v66: SR 174990 "Doughnuts, cake-type, plain (includes unsugared, old-fashioned)" by P3's carbohydrate balance, 14.15 % — below) | 23.32 % | READ: 80 g oil per 343 g (120 g water dropped); Q12 (iii): the cake doughnut 2708063 lists no oil |
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
yuca record (since matcher v69, M70 below: 15 %, read); the corpus lost the steps of 269 subsections (Q18), which
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
dusting — since matcher v68 only a thick piece's, and no coated eggplant
baked after the coat: M69) is held `coating` with it — no grams,
`hold_note` the dip sentence as written. It is a coating hold in the
Recipe-review queue: a person's
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
when M61's product mix or M59 D's cauliflower batter may be read — save a
cut dough line, v66 M67 below: its line, record and hold, never its grams).
The matches GET answers each decided line from the request's one plan whenever
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
scallions, chiles and galangal (since matcher v71 strained — M71 below),
the five flake / coarse sea-salt rows and
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
no strained head (weighed on ginger, kept: 16.00 g, 12.80 kcal — closed in
matcher v71, M71 below) and its
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

**Since matcher v66 (batch M67 — fried doughs: the doughnut's printed cut
share, the struffoli uptake on the cake doughnut's composition;
matcherVersion 65; prep49 design_v2 §2 M67, the owner's Q9 (A2) and Q10
(a) under the standing authorization, Q7's one-way door accepted; zero
requests; the sheet read is a step read, so the reach is pre-Q18).** Both
inside M61's product branch (no counted line is the fried food; engine
`_friedProductOf`):

(A2, Q9) **A rolled dough the steps cut counts only the cut share.** One
step printing the sheet (`N by M-inch rectangle|square`), the count of
rounds (`cut N rounds`) and the round cutter (`N-inch round cutter`)
gives s = n · π (d / 2)² / (L · W), applied when 0 < s < 1 (engine
`_cutShareOf`, read once per recipe; the first step printing all three
decides; the recipe's own steps only — a variation's are never read).
Each dough line M52 weighs (the engine's or a person's confirm; unheld, on
its record, above the gate, no medium) counts round2(s × its WHOLE line),
`discarded`; the frying-oil uptake reads the sum of the cut grams (a pick
or typed grams in the dough stays at its own weight, whole). The holes cut
from the rounds are fried too ("For doughnut holes, transfer all to oil"),
so they stay inside the n discs; the sheet is rolled even ("about ½ inch
thick"), so area is mass. yeasted-doughnuts (1105 step 3: "Roll dough into
10 by 13-inch rectangle, about ½ inch thick. Using 3-inch round cutter
dipped in flour, cut 12 rounds."): s = 12 × π × 1.5² / 130 = 65.25 %, basis
`discarded in cooking — only the cut dough counted · approximation (the cut
share 65.25 %: 12 × 3-inch rounds from the steps' 10 by 13-inch sheet; the
remaining dough, cut only "if desired", not counted)` (the "if desired"
clause only where the step prints it). |0 flour 637.86 → 416.20, |1 sugar
99.22 → 64.74, |2 yeast 3.15 → 2.06, |3 milk 366.00 → 238.81, |4 egg 50.00 →
32.62, |5 salt 9.02 → 5.89, |6 butter 113.44 → 74.02, and the oil |7 213.80
→ 139.50 (16.72 % of the cut 834.34 g; its flag unchanged): −2,002.29 kcal,
per serving 599.61 → 432.75. The two variations that print the same sheet
(Jelly Doughnuts, Boston Cream Doughnuts) are `variation` subsections,
never computed (CP3). Not read: an "8-inch square" sheet with no "by", a
count of anything but rounds, rings or squares cut — they keep the whole
mix (a `ponytail:` names the ceiling); a dough line another rule discards
would count at the share (none in the corpus: one recipe prints the
geometry).

(B, Q10 a) **A cake dough reads the plain cake doughnut by its
carbohydrate.** The `cake` figure (struffoli; a doughnut or dough with no
yeast row) moves from FNDDS 2708024 "Fritter, plain" (23.32 %, a pourable
batter) to SR 174990 "Doughnuts, cake-type, plain (includes unsugared,
old-fashioned)" — the one input FNDDS 2708063 lists (no oil row, so P3's
balance reads it; the record is unglazed, so the carbohydrate tracer
applies with no departure): against the struffoli dough |0–|6 (552.37 g;
per gram protein 0.090501, fat 0.118227, carbohydrate 0.491276), D = 47.1 /
0.491276 = 95.873 g of dough per 100 g, O = 24.9 − 95.873 × 0.118227 =
13.565 g of oil, u = 14.15 %. struffoli-neapolitan-honey-balls|7 128.81 →
78.16 g (−455.85 kcal; per serving 716.48 → 640.51, still partial on the
candied cherries). Flag: `approximation (frying oil absorbed: 14.15 % of the
raw struffoli dough's weight — derived from USDA SR Legacy 174990
"Doughnuts, cake-type, plain (includes unsugared, old-fashioned)" by its
carbohydrate (no record for struffoli dough; read as a cake doughnut; by
its protein 30.62 %; FNDDS 2708024's fritter batter reads 23.32 %))`.

(Q7, the one-way door) A person's Confirm of a cut dough line reads the
plan — yeasted-doughnuts|0's flour 416.20 g `discarded` — and keeps
following it.

Reach (replay of snapshot 25 against the v65 rows): exactly 9 rows — A2
yeasted-doughnuts |0–|7, B struffoli|7 — all `auto`, 0 person rows;
−2,458.14 kcal (A2 −2,002.29, B −455.85). The 7 dough rows move their gram
source to `discarded` (the review bucket stays `counted`: its discarded arm
reads 0 g rows only); statuses, holds and sections unchanged. Cost: the
sheet read once per recipe (`memo:cutShare`); the matches GET plans M52
once; a compute with every dough line confirmed plans it at most twice — a
cut dough line is read on its line and record, never its grams, so its
engine form and the plan's key alike. At the editor caps (398 dough lines
before one oil, every step printing the geometry) the compute takes about
0.9 s and the GET 0.6 s (0.8 and 0.6 s at v65, where the dough is not
planned); with every dough line confirmed the GET 0.6 s and the compute 1.0
s (0.55 s at v65), 1.3 s for the first compute after the deploy (each line
rewritten from its whole form); the v26 cap shapes within ±1 % of v65.

Known gaps (the source stands): pakoras (L042, R22) — every sourced read
(the P3 balance 4.63 / 3.36 %; FNDDS's oil per mix carbohydrate ≤ 21.55 g,
per protein ≈ 16.5 g) lies BELOW the shipped 40.72 g, so the audit's 55 g
cannot be reached by a source; the doughnut glaze |8 counts whole (368.54
g; 172758's balance leaves 6.21 g of glaze carbohydrate against the 14.85 g
its sugars imply — no cling figure closes); struffoli's tracer spread (14.15
% by carbohydrate, 30.62 % by protein — its dough is egg-rich, P : C 0.184
against the record's 0.113 — no cached water can arbitrate; ½-inch pieces
fry more surface per gram than a rolled doughnut) and the honey left in the
pan ("lift struffoli from saucepan" with a slotted spoon: |8 counted whole);
the yeast doughnut's own spread (13.35 / 16.72 / ≤ 25.67 %) is unchanged —
A2 moves the mass it applies to. Deploy note: matcherVersion 65 stales
every recipe; one zero-request sweep settles it.

**Since matcher v67 (batch M68 — the whole brisket at its printed trim, the
home-corned briskets flag-only; matcherVersion 66; prep49 design_v2 §2 M68,
the owner's Q1 (a) for the whole cut and Q2 (c) for both corned recipes,
2026-10-09; zero requests; records and titles only — no step is read, so no
reach here is pre-Q18; shipped alone, §0.5).** Two record rulings:

(R-A, Q1 (a)) **A whole brisket printing "fat trimmed to ¼ inch" counts on
USDA's ⅛-inch record.** `trimDepthRecords`' trim phrase gains `168607 →
168664`: the whole brisket's lean-only SR 168607 (the top of the line's own
`whole beef brisket` answer) moves to SR 168664 *Beef, brisket, whole,
separable lean and fat, trimmed to 1/8" fat, all grades, raw* (253 kcal, P
18.4 g, F 19.1 g per 100 g), a hit in the same answer, at the top's
confidence; the line is weight-written, so it prices on the hit (calls 0)
and its grams never move. USDA publishes brisket at 0" and ⅛" only; ⅛" is
the deepest at or below the printed ¼". Flag (`trimStandInFlagOf`, keyed on
168664 AND the printed phrase): `approximate (the printed ¼-inch fat cap
counted at USDA's ⅛-inch trim, the deepest it publishes for brisket; the
fat that renders into the separator is not deducted — USDA's own braised
pair 168664 → 168665 keeps 93 % of the energy)` (since matcher v72
deducted, the flag naming the energy and fat shares — M72 below). The pair by the protein
tracer on the cached hits (M61 R-d's method): yield 18.4 / 25.8 = 0.713, fat
kept 0.713 × 24.5 / 19.1 = 91.5 %, energy kept 0.713 × 331 / 253 = 93.3 %.
USDA's FLAT pairs say otherwise — 168743 → 169440 (0", choice) keeps 58.8 %
of the fat and 82.0 % of the energy, 169570 → 169555 (0", select) 49.1 /
79.5 %, the lean-only 168657 → 170601 91.7 / 101.1 % — so the sources split
by CUT and the ruling is the whole cut's only: the FLAT (braised-brisket-
with-pomegranate|0, "flat cut, fat trimmed to ¼ inch") keeps R1d's 0" flat
168743 and its shipped flag until L49 reads a flat ⅛" braised record (none
is cached), to be decided in M70 (since matcher v69: 173128 × the braised
pair's 67.6 % — batch M70 below).

(Q2 (c)) **A home-corned brisket keeps the fresh flat and says the cure's
sodium is not counted.** A fresh flat 168743 in a recipe whose TITLE matches
`\bcorned beef\b` (case-insensitive; exactly two corpus titles — 0090
"New England–Style Home-Corned Beef and Cabbage", 0091 "Home-Corned Beef
with Vegetables") gains, after the ¼-inch cap's arm, `approximate (the
steps cure and rinse the brisket — the cure's sodium is not counted; a
rinsed cure counts 0 g, CP9)` — basis only, 0 kcal; the cure's salt, sugar,
curing salt and brine spices stay `discarded` 0 g. Why: both recipes RINSE
the cure ("Remove brisket from brine, rinse"; "Rinse brisket and pat it
dry"), and the owner kept CP9's "rinsed cure 0 g" and the 2026-09-27 "brine
co-solutes zero" literal. SR 170199 *Beef, cured, corned beef, brisket,
raw* (198 kcal, Na 1,220 mg per 100 g) is NOT ranked (design R-B, not
built): its gain over the fresh flat is mostly its FAT LEVEL — a commercial
lot at fat : protein 1.01 against the shipped flat's 0.49, its protein
diluted by the pumped brine (14.7 against 20.2 g) — not the cure; and
170199 → 170200 (cooked) is not mass-balanced (fat kept 103 % by the
protein tracer). The title is the cure's only read: a cured brisket in a
recipe not titled so is missed (none in the corpus).

Reach (rp43 + bucket_v12 on fresh copies of snapshot 25, main and
`--reverse-parents` byte-identical; STEP ZERO the v66 tree reproduces the
v66 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143
(unchanged); vs the v66 rows exactly 3 rows, all `auto`, 0 person rows —
barbecued-whole-beef-brisket-with-spicy-chili-rub|10 168607 → 168664,
4,535.92 g, 7,121.39 → **11,475.88 kcal (+4,354.48)**, per serving (18)
498.26 → 740.17; home-corned-beef-with-vegetables|0 (2,154.56 g, 3,641.21
kcal) and new-englandstyle-home-corned-beef-and-cabbage|6 (2,041.16 g,
3,449.57 kcal) in their basis only. Statuses 1,029 / 169, holds and buckets
unchanged. Unreached by design: the pomegranate flat (above),
onion-braised-beef-brisket|0 (no depth printed, no corned title: 168743
unflagged), the rack (174414 at 1,241.71 g / 2,942.85 kcal) and
grilled-rack-of-lamb|5 (172641).

Known gaps (the source stands): the whole brisket's rendered fat — its own
pair's 93.3 % would deduct 768.29 kcal (design_v2's −766.59 rounds the
share to 0.9332), a new cooked-loss deduction not proposed for one row (Q1
(b)) — since matcher v72 deducted (M72 below); 170199 is brine-pumped (its protein at the fresh weight 27 % low), one
reason it is not read; 0090's rub spices (0090|1–|5: pepper, thyme,
allspice, paprika, bay — 52.49 kcal) rinse off with the cure but are
counted; both recipes' cure sodium is uncounted (flagged, Q2 (c)); the
pomegranate flat waits for L49. Deploy note: matcherVersion 66 stales every
recipe; one zero-request sweep settles it.

**Since matcher v68 (batch M69 — sautéed and vegetable coats; matcherVersion
67; prep49 design_v2 §2 M69, the owner's Q4 ruling (b) of 2026-10-09 and Q6
(a), on L49's records; zero requests; reach PRE-Q18 — the thin trigger reads
the steps).** Two coats held since M52 now count; the onion rings stay held.

(R1, Q4 — the owner's ruling (b)) **A sautéed flour dredge on a THIN piece
counts at C2's read 3.18 as a stand-in.** `_m52Plan` reads a new shape C4
where `_coatShapeOf` returns null today (no fry, no bake after the coat), a
coat line is held and the coated MEAT is thin (`_thinPiece`): a step
sentence matching `\bpound\w*\b[^.]*?\bto (?:an )?(?:even )?(?:⅛|¼|⅜|½)-inch
thick(?:ness)?\b` ("pound cutlets to even ¼-inch thickness", 0418; "pound
the cutlets to an even ¼-inch thickness", 0419–0421; "gently pound to even
½-inch thickness", 0415, 0418 — read once per recipe), or the coated row's
LINE matching `(?<![\d¼½¾⅛⅜])(?:⅛|¼|⅜|½)[- ]inch[- ]thick\b` (0466's "4 (5-
to 6-ounce) sole or flounder fillets, ⅜ inch thick"). The trigger sits
outside `_coatShapeOf`'s memo (it keys the record's description; the line is
the row's), so no C1/C1d/C2/C3/C5 row can move. k = **3.18**: FNDDS 2705980
"Chicken breast, baked, coated, skin / coating eaten" (10 g breading per
125.77 g raw breast), the lightest coat USDA prints, for every C4 food (the
sole too). Flag: `approximation (coat: 3.18 g carbohydrate per 100 g of the
raw <food> — USDA FNDDS 2705980 recipe: 10 g breading per 125.77 g raw
chicken breast (no record for a sautéed flour dusting; read as the baked
breaded breast, the lightest coat USDA prints; FNDDS 2706416 Veal Marsala's
62.5 g flour per 617.60 g raw veal, 7.82, counts the dish's whole flour,
sauce included, and is not read); the dredge's excess not counted)`.
WHY NOT the read: L49 read FNDDS 2706416 "Veal Marsala" — ½ cup flour
(62.5 g, listed alone) per 1 lb COOKED grilled veal loin (453.6 g; to raw by
the protein tracer on SR 173826 / 172644, 29.75 / 21.85 → 617.60 g), on the
cached Foundation flour 789890 (77.3 %): k = 62.5 × 0.773 / 617.60 × 100 =
7.82. It counts the dish's WHOLE half cup — the shaken-off excess and the
sauce's thickening included (0418's note washes the excess starch into the
sauce) — and prices a sautéed dusting 36 % above the FRIED twin:
chicken-francese-2 (1133) counts 61.35 g flour on 793.79 g chicken at C1's
5.73 (7.73 g a 100 g), the sautéed chicken-francese (0420) would count 63.10
g on 623.69 g at 7.82 (10.12 g a 100 g). The owner chose (b) 3.18 over (a)
7.82, the fried twin's 5.73 (the stated ceiling) and "keep held". Audit 4's
hand counts (pB §3) — disclosed, not fitted (§0.6): at 3.18 the three
single-flour cutlets count ABOVE them (+55–63 %; piccata L103 18 g against
27.99), francese's double dredge and parmesan-crusted's dip BELOW (flour
−36 %, eggs −54 %, milk −68 %, whites −63 %); on the 8 audited lines 449.5
kcal by hand (the auditors' grams on each row's record) against 473.6 at
3.18. Francese's double dredge rides the single k (Q3 a). The dips of a C4
coat size by M62 E-w (W = 1.1730 × B): francese|10 |11 and
parmesan-crusted|4 |5 leave their H hold.

(R2, Q6 (a)) **A coated eggplant sizes the coat at 7.93, read from FNDDS
2710050.** With no counted meat beside a held coat, the coated food is the
largest counted row on a `_coatVegetables` record — `['Eggplant,']` only —
whose head a coating sentence names (`_coatedVegetable`; 0407 S3 "… shake
to coat the slices"): eggplant-parmesan|0, 907.18 g, shape C2 (it bakes
after the coat). The list holds ONLY records `_coatFigure` has an arm for:
the default C2 arm is the chicken breast's 3.18, so an unguarded fallback
would budget the onion rings on a chicken figure. And only at C2, the
eggplant's one arm: a coated eggplant the steps FRY with no bake after (C1,
C1d) has no coated food — it stays held, as before M69, never on the fried
chicken breast's 5.73 or the steak's 8.79 (pinned on a STATED synthesized
fried copy of 0407; no corpus recipe reaches it). The arm: FNDDS 2710050
"Eggplant parmesan casserole, regular" lists 41.4 g "Eggplant, raw" and a
13.2 g BATTER (flour 4 g, dried egg 0.5, tap water 8.3, nonfat dry milk 0.3,
baking powder 0.1) whose carbohydrate on the cached records (789890 77.3 %;
Foundation 329490 1.87 % for the dried egg and the vitamin-fortified twin
172195 51.98 % for the dry milk — their own SR inputs are not cached; 172803
27.7 %) is 3.28499 g: k = 3.28499 / 41.4 × 100 = **7.93**. Flag:
`approximation (coat: 7.93 g carbohydrate per 100 g of the raw eggplant —
USDA FNDDS 2710050 recipe: 13.2 g batter (4 g flour, 0.5 g dried egg, 8.3 g
water, 0.3 g dry milk, 0.1 g baking powder; 3.28 g carbohydrate) per 41.4 g
raw eggplant (a crumb coat read on a batter figure; 8.3 g of the 13.2 g
batter is water and carries no carbohydrate); the dredge's excess not
counted)` (`_coatFlag` names the coat by record: this one's batter, every
other read's breading). A batter left in the bowl among the eggplant's coat
parts reads on the batter it is: the crumb clause drops (the water clause
stays) and F10's ` (a batter read on a breading figure)` is never added on
2710050 (closer 3, verify3 D1; pinned on a STATED synthesized battered copy
of 0407; no corpus recipe reaches it). B is a carbohydrate budget,
food-agnostic by design;
the recipe's three-layer crumb coat (flour → egg → bread crumbs and
Parmesan) shares it at one f. The Parmesan |3 joins by M66's crumb gate (S2
"… stir in the parmesan" beside "crumbs"); the bread |2 weighs the piece
table's 28 g a slice (224 g). The frying-oil block's coated food stays the
meat (neither recipe has a frying oil row). `_m52Key` keys the coated
vegetable (its position, grams and description; only at C2) where no meat
is, and
`_m52KeysAlike` treats a counted `_coatVegetables` row like a meat row.
The coating-sentence test is read once per head (RULE C, `memo:coatNamed`:
read per row, it measured 2,135 ms against 167 for a totals recompute at
the caps); both M69 readers are pinned at the caps in v26
(`memo:poundsThin` once per recipe, `memo:coatNamed` once per head).

(Onion rings, Q6) **Held — no sourced figure.** FNDDS 2710055 "Fried onion
rings" lists only two prepared products (50 g SR 170415 "Onion rings,
breaded, par fried, frozen, prepared, heated in oven", 50 g "Fast foods,
onion rings, breaded and fried"), no coat input. A two-tracer balance on
170415 (the coat as FNDDS 2710785's breading) is ill-conditioned: on
Foundation 790646 "Onions, yellow, raw" (the row the recipe reads) k 5.48,
on SR 170000 "Onions, raw" k 1.08 — a 0.27 g / 100 g protein difference
moves k five-fold and both pass the energy check; only the 50/50 mixture's
water (34.0 g) is printed, none for the raw onion or the breading. Derived,
not sourced: the 8 rows (|0 keeping its 30.16 g eaten part) stay held; the
design's ≤ +1,256.9 bound is not shipped. Since matcher v80 (M80-1, below)
the rings count on FNDDS 2710042's fried-cauliflower coat, a flagged
stand-in.

Reach (rp43 + bucket_v12 on fresh copies of snapshot 26, main and
`--reverse-parents` byte-identical; STEP ZERO the v67 tree reproduces the
v67 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143
(unchanged); vs the v67 rows exactly 15 rows, all `auto`, held `coating`
0 g → counted `discarded`, 0 person rows, **+1,285.48 kcal** — R1 (11 rows,
+725.49): chicken-piccata|3 27.99 g (f 0.463950), next-level-chicken-
piccata|3 and better-chicken-marsala|6 32.66 (f 0.360850), chicken-
francese|9 25.66 (f 0.212644) with its dip |10 eggs 17.83 and |11 milk
5.43 (f_w 0.178329), chicken-saltimbocca|1 and fish-meuniere|0 25.66 (f
0.425288), parmesan-crusted-chicken-cutlets|2 17.49 (f 0.463949) with its
dip |4 whites 14.96 and |5 chives 0.91 (f_w 0.151071); R2 (4 rows,
+559.99): eggplant-parmesan|2 bread 76.37, |3 Parmesan 19.33, |5 flour 41.14
(f 0.340944 on B 71.94), |6 eggs 84.39 (f_w 0.421936). Per serving:
piccata 399.84 → 425.45, next-level 442.64 → 472.52, marsala 704.46 →
734.35, francese 407.44 → 438.34, saltimbocca 488.08 → 511.56, meunière
326.25 → 349.73, parmesan-crusted 153.54 → 171.67, eggplant-parmesan 360.33
→ 453.66. Statuses 1,029 / 169 → **1,035 / 163** (the first six turn
complete; parmesan-crusted keeps |3 held, the eggplant |1's kosher salt
`discarded_medium`); 15 coating holds released, 0 added (27 → 12); buckets
move by exactly those rows. A person's Confirm on a reached row reads the
plan's share through the real PUT (Q7 accepted: eggplant|6 84.39 g, no
longer 0 g poured away). Unreached by design: pan-seared-salmon-steaks|2
("¾ to 1 inch thick", no pound), maple-glazed-pork-tenderloin|6 ("slice into
¼-inch-thick pieces" — no pound), skillet-chicken-and-rice|2 (no print);
chicken-francese-2|5 (C1, 61.35 g); chicken-marsala (0414)|1; the onion
rings; vegan-baja-style-cauliflower-tacos.

Known gaps (the source stands): the thick pieces' dustings (salmon|2,
maple|6, skillet|2) stay held — a per-mass k cannot see a thick piece's
surface (audit P5); maple's patted-off sugar, salt and pepper count whole
(96.78 kcal of sugar — since matcher v71 held with the cornstarch, M71
below); parmesan-crusted|3's cheese crust (184.28 g; no
record of a cheese crust; Q5 (d) is the owner's); chicken-marsala (0414)|1
"1 cup flour" counts WHOLE (120.66 g, 441.62 kcal) — its steps print no
excess, so no `coating` hold and no C4 (a `_dredge` question, outside M69);
the inputs not cached — 2706416's flour (SR 20081) and 2710050's dried egg
and dry milk — are read on same-description Foundation records and the
fortified twin 172195 (0.156 g of 3.285 g); francese's double dredge on the
single k; the flag's "the dredge's excess not counted" also at f = 1 (the
shipped wording). H2, measured on the build, not shipped:
vegan-baja-style-cauliflower-tacos counts its coat (|6 coconut 93 g, |7
panko 59.15 g) and dip (|8 coconut milk 243.69 g) by portion and density —
no coat line is held, so `_m52Plan` never reads them, and R2 (eggplant only)
leaves every row byte-equal; were cauliflower a coated vegetable on the
shipped `_cauliflowerFried` (FNDDS 2710042, k 50.53), B = 210.86 g ≥ the
parts' 64.57 g of carbohydrate (f 1) and W = 247.35 g ≥ 243.69 (the dip
whole): 0 g would move. Deploy note: matcherVersion 67 stales every recipe;
one zero-request sweep settles it; §0.7 — a read-only count of person rows
on the 15 reached positions on the live DB before the deploy (> 0 blocks).

**Since matcher v69 (batch M70 — the records read at live step L49 and the
zero-request giblets; matcherVersion 68; prep49 design_v2 §2 M70, the
owner's Q1 flat (b′), Q11 (labels weigh a printed size or volume, never
composition — a standing rule) and Q13 G2, 2026-10-09; zero requests; reach
PRE-Q18 — the giblet and rind readers read steps).** Seven rulings and one
reported gap:

(1, Q1 flat (b′)) **The pomegranate flat counts at ⅛" with its braised
pair's energy share.** `trimDepthRecords`' trim phrase gains `168743 →
173128`: braised-brisket-with-pomegranate|0 "1 (4- to 5-pound) beef
brisket, flat cut, fat trimmed to ¼ inch" moves from R1d's 0" flat to SR
173128 *Beef, brisket, flat half, separable lean and fat, trimmed to 1/8"
fat, choice, raw* (a hit in the line's own `beef brisket` answer; 2,041.16 g,
weight, no detail asked). New one-entry map `braisedEnergyShare` (since
matcher v72 `braisedKept`, its fat columns too — M72 below) {173128:
e}: USDA's SAME cut, trim and grade braised, SR 173130 (L49's search; both
cached hits): yield by the protein tracer 18.1 / 28.7 = 0.6307, e = 298 ×
0.6307 / 278 = **0.6760** (fat kept 55.4 %; every other pair differs in
grade, trim or cut — the select ⅛" flat 0.6227, the 0" flats 0.80–0.82, the
whole ⅛" 0.933, the lean-only flat 1.03). `recomputeTotals` deducts
(1 − e) of the row's energy beside Q25's alcohol arm — ENERGY only, only on
a line `trimStandInFlagOf` flags (one raw test), a person's typed grams too;
the row's grams and kcal column stay gross (5,674.44, as an alcohol row).
Flag: `approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch flat
trim; USDA's braised pair 173128 → 173130 keeps 67.6 % of the energy by the
protein tracer — the fat the steps skim, deducted)`. 168743's ¼" arm stays
(the fallback if the answer loses 173128). Recipe energy 3,449.57 →
3,836.11 for the line (+386.54; deduction 1,838.33); batch 4,379.57 →
4,766.11; per serving 729.93 → 794.35.

(2, Q13 G2) **The Giblet Pan Gravy's giblets weighed off the host's bird.**
classic-roast-turkey §0|1 "Reserved turkey giblets, neck, and tailpiece"
(the 0 g amount-less rule row) is matched when a section step stirs the
giblets back (`\bstir\b[^.]*\bgiblets\b[^.]*\binto\b`: "Stir the reserved
giblets into the gravy") — `_rankAs['reserved turkey giblets']` reads SR
171083 *Turkey, whole, giblets, raw* (124 kcal) in the cached `giblet pan
gravy` answer — and weighed by `hostWeighedGiblets` (the one reader
`lineGrams` gives the compute, a Confirm and the GET): the host's first line
whose item's head is `turkey` (by its TEXT — a section computes before its
host), its printed weight 12–14 lb at the midpoint 5,896.70 g × (85 − 78) /
85 (AH-102's turkey dressing data, 12 lb and over: ready to cook with neck
and giblets 85, without 78 — the figure the bird row already takes off) ×
6 / (4 + 6) (item 2590: neck 4, giblets 6) = **291.37 g**, 361.29 kcal.
Basis: `the host's turkey from the printed weight (12–14 lb, the midpoint):
5897 g × 7/85 neck and giblets (USDA AH-102 turkey dressing data, 12 lb and
over: 85 with, 78 without) × 6/10 giblets (item 2590: neck 4, giblets 6,
fryer-roaster class) · approximate (the neck and tailpiece are strained out
— not counted)`. `buysRefuse` reads a line starting "Reserved" as bought by
no one, so no reader asks 171083's detail (it prices on the hit; the cache
holds no detail after a compute); the amount-less 0 g of `engineOutcome`
skips a weight resolution (this reader is the only one). The grams join
the SECTION's ingredients hash (a term only on the line this reader weighs,
so no other hash moves): a host-only edit of the bird's printed weight
stales the gravy — and so its routed parents — and the recompute reads the
new bird (12–14 → 16–18 lb: 291.37 → 381.02 g). crisp-skin's
"Reserved giblets, neck, tailpiece, and backbone and rib bones" stays the
0 g rule row (its gravy strains them out). The section 1,275.30 g / 787.56
kcal → 1,566.60 / 1,148.85; its routed parents re-read it: classic-roast-
turkey 678.04 → 714.17 per serving, classic-roast-stuffed-turkey 1,221.89 →
1,258.02.

(3, pF L1; R-1 read 2026-10-09) **Yuca on cassava with a READ uptake.**
`_rankAs['yuca roots']` → SR 169985 *Cassava, raw* (the cached `cassava raw`
answer; the line's own answer led with LEEKS 2727584, `no_nutrients`):
fried-yuca|0 907.18 g, 1,451.49 kcal. FNDDS 2709565 "Yuca fries" lists 100 g
"Cassava, raw", 15 g "Vegetable oil, NFS" and 0.4 g salt — its input IS the
raw cassava, so the uptake is read, not derived (`_yucaFries`; the house
derives only on a read input): `_friedClassOf`'s arm on cassava or yuca
reads 15.00 %. fried-yuca|2 "2 quarts vegetable oil" 0 g → **136.08 g**
(1,224.72 kcal on the stored grams), flag `approximation (frying oil
absorbed: 15.00 % of the raw yuca's weight — USDA FNDDS 2709565 recipe: 15
g oil per 100 g raw cassava)` — the house read form every read uptake
prints. The recipe stays partial (|1's salt in the boiling water held):
per serving — → 669.05.

(4, pF F3) **A Parmesan rind is the cheese, discarded whole.**
`_rankAs['parmesan cheese rind']` → SR 170848 *Cheese, parmesan, hard*
(index 2 of the line's own answer, whose top was FNDDS 2747676 WATERMELON
rind, 0.377 — the head `rind` dominated), and `rind` joins
`_wholePieceHeads`: hearty-minestrone|14 "1 piece Parmesan cheese rind,
about 5 by 2 inches" and pasta-e-fagioli|9 "1 piece Parmesan cheese rind,
about 5 inches by 2 inches" → 0 g `discarded`, counted (`removed and
discarded (step N) — counted as 0 g`: 0028 step 4 "Discard the bay leaf
and Parmesan rind, stir in the basil, …"; 0404 step 2 "Discard the cheese
rind."); both recipes turn complete.
italian-chicken-soup-with-parmesan-dumplings|8 "1 Parmesan cheese rind,
plus 3 ounces Parmesan, shredded (1 cup)" (0403: "Discard Parmesan rind.")
moves its record only — its
shredded cheese is cut fine (`_cutFine`), so it is never zeroed, and the
`second_food` hold stays (85.05 g; pF Q-F4 (a)). No `namesSecondFood` guard
is needed (it would change no row).

(5, pE Q6) **A chopped or minced basil volume reads SR's chopped
portion.** grams.dart `fineCutSiblings` {2709780: 172232} beside
`volumeSiblings`: a line cut fine (`chopped|minced|diced|grated`, "minced"
read as chopped since checkpoint 5) with a volume on FNDDS 2709780 *Basil,
raw* (its '1 cup' 24 g is SR's whole-leaf cup; its '1 tablespoon' 3 g names
no cut) weighs on SR 172232 *Basil, fresh*'s `tbsp, chopped` — 5.3 g at
amount 2: **2.65 g a tablespoon, 42.40 g a cup** (`fineCutWeighing`: the
line's food with only the sibling's chopped portions, through the shipped
resolver — plus parts summed, the amount divided as every portion is). The
record stays 2709780 (the two print the same composition). Basis suffix:
` · chopped: 2.65 g per tablespoon — USDA SR 172232 "Basil, fresh" 'tbsp,
chopped' × 2 = 5.3 g`. The sibling's detail is fetched once by the first
volume line on 2709780 when no cache holds it (`gramsFor`, the
`volumeSiblings` precedent; the library holds it: zero requests). 50 rows
(38 "chopped", 12 "minced"): 424.00 → 574.16 g, +34.60 kcal; 22 move up (a
cup 24 → 42.40 g), 28 down (a tablespoon 3 → 2.65 g); whole, packed, torn,
shredded, Thai, sprig and count lines keep FNDDS's portions.

(6, pF F6, Q11) **Hershey's Kisses on milk chocolate at the label's
piece.** `_rankAs['hershey s kisses']` → SR 167587 *Candies, milk chocolate*
(the cached `milk chocolate candy` answer's top; the line's own answer held
no milk-chocolate record — PAYDAY 170680 at 0 led). grams.dart
`_pieceWeights` ('hershey s kisses', 41 / 9 = 4.5556 g) with the
`_approximatePieces` label `Hershey's label: 9 pieces = 41 g (FDC Branded
1642930 and four more; three 2023 labels print 7 pieces = 32 g)` (L49's
Branded read; 4.5714 g, 0.3 % apart; 1198's "12-ounce bag … a few left
over" bounds 62 below 5.49 g). meringue-christmas-trees|8 "62 Hershey's
Kisses, unwrapped" → **282.44 g** (basis `62 × 4.6 g each · approximate
(…)`), 1,511.08 kcal; the recipe complete, 13.50 → 43.72 per cookie.

(7, pF F1, Q11) **Powdered pectin on SR 168821 at the Sure-Jell label.**
v38 R02's three `_rankAs` entries are enabled → SR 168821 *Pectin,
unsweetened, dry mix* (325 kcal; its one portion a 1.75-oz package);
grams.dart `_densities` ('fruit pectin', 4 / 4.92892) and ('sure-jell', 4 /
4.92892) — 0.811537 g/mL, longer than the stray `sugar` (0.85) that matched
"no-sugar-needed" — labelled `Sure-Jell label (Kraft Heinz, FDC Branded
2596757; the regular box — FDC holds no label of the low/no-sugar box the
line names; the other makers' boxes read 3.2–4.0 g per teaspoon): ⅛
teaspoon = 0.5 g`. THE LABEL DECISION (R-2, two Branded spellings,
2026-10-09: 50 hits, no low/no-sugar Sure-Jell label; FDC's four Sure-Jell
labels — 2596757, 2596756, 1664716, 1727454 — all print "1/8 tsp (0.5g)";
Mrs. Wages 0.8 g per ¼ tsp, Ball 1.0 g, Certo 0.9 g): the regular box's 4 g
a teaspoon, the plan's fallback. marbled-blueberry-bundt-cake|12 36.00 g,
fresh-peach-pie|4 and fresh-peach-pie-with-all-butter-lattice-top|4 24.00 g,
raspberry-sorbet|1 4.00 g, fresh-strawberry-pie|4 6.00 g — +305.50 kcal, the
five recipes complete.

(8, pD L, Q11) **The 8-inch lumpia wrapper — reported, no rule.**
lumpiang-shanghai|16 "18–20 (8-inch) square lumpia wrappers or spring roll
wrappers" stays 608.00 g (19 × SR 172802's 7-inch egg-roll wrapper, 32 g)
with |17's uptake 99.34 g: no label L49 read prints a size — Wei-Chuan
2623420 (12.5 g a sheet), Frieda's 2412362 and JSL Foods / Twin Dragon
2026771 (egg roll, 23 g), and the thin rice spring-roll sheets Blue Dragon
555172 and Oriental Select Farms 2426475 (8.5 g) and Gefen 2612612 (wheat,
12 g) — so under Q11 a label weighs nothing here. Every gram a sheet weighs
below 32 g moves the recipe **−68.32 kcal** (19 × 2.91 wrapper + 19 ×
7.6198 % × 9.00 uptake): at 12.5 g −1,332.24, at 23 g −614.88, at 8.5 g
−1,605.52 (per serving 655.72 → 433.68 / 553.24 / 388.13) — 608 g is a known
over-count of unknown size.

Reach (rp43 + bucket_v12 on fresh copies of snapshot 26, main and
`--reverse-parents` byte-identical; STEP ZERO the v68 tree reproduces the
v68 TSVs): calls 0, staleAfter 0, sectionsStale 0, sections 143; vs the v68
rows exactly the 63 rows above plus the 3 routed parents that re-read a
moved section (classic-roast-turkey|8, classic-roast-stuffed-turkey|10,
lighter-chicken-parmesan|9), all `auto` but the giblet row (the engine's
own `confirmed` rule row before), 0 person rows; recipe energy **+5,275.17
kcal** (sections once, parents not double counted: brisket +386.54,
giblets +361.29, yuca +2,676.21, rind 0, basil +34.54 — the rows' rounded +34.60, Kisses +1,511.08,
pectin +305.50); statuses 1,035 / 163 → **1,043 / 155** (the two rind soups,
the meringue trees, the five pectin recipes); buckets: `check` −9 (yuca|0,
the two rinds, the Kisses, the five pectin rows), `no_nutrients` −1,
`counted` +9, the giblet row leaves the rule arm; sections: the Giblet Pan
Gravy and the five basil sections only; no 171083 detail cached.

Known gaps (the source stands): 1 the pomegranate's fat counts whole (453.14
g; the pair keeps 55.4 % — 202.12 g not deducted, energy only as Q25; since
matcher v72 deducted — M72 below), the
line prints ¼" and USDA's deepest flat trim is ⅛", and the row's kcal column
shows the gross 5,674.44; 2 the turkey's tailpiece stays inside the bird's
78/85 carcass (AH-102 prints no tail-off figure), item 2590 is the
fryer-roaster class (a 12–14 lb bird is a young hen or tom), the giblets
count raw though they simmer; of the other reserved-for-gravy birds, 0155's
"Giblet Pan Gravy for a Crowd" passes every gate ("Reserved turkey giblets,
neck, and tailpiece"; "Stir the reserved giblets into the gravy and return
to a boil.") and reads 448.26 g off its own 18–22 lb bird (9,071.85 g × 7/85
× 6/10) whenever it is computed — no parent routes it, so the library never
computes it — while 0159 (no stir-back sentence) and 0175 ("Stir in diced
giblets, if using." — no "into") stay outside the rule; 3 the yuca's
bought weight counts the peel, stem and core the steps cut away (no cached
record or transcribed AH-102 page prints a cassava refuse; not estimated);
4 the dumpling soup's rind |8 stays held (`second_food`); 5 "minced" is read
as chopped (the house convention), FNDDS's unqualified 3 g tablespoon is
unexplained by any portion text, and shredded or torn lines keep FNDDS's
cup; 6 the Kisses labels differ 0.3 % (2021: 41 g / 9; 2023: 32 g / 7) and
the basis prints the piece to one decimal; 7 the pectin label is the
regular Sure-Jell, not the low/no-sugar box the lines name, and 168821's
composition is SR's generic dry mix (a label's dextrose share is never
read); 8 the 8-inch wrapper (above). Deploy note: matcherVersion 68 stales
every recipe; one zero-request sweep settles it (a fresh library asks the
`giblet pan gravy` answer and 172232's detail once).

**Review Run 063/064 fixes (matcher v70; matcherVersion unchanged, 68 —
every fix has corpus reach 0: the replay of snapshot 26 is byte-identical
to the v69 rows, calls 0; zero requests; server only).** Each restores an
invariant the dual-fleet review found broken on a non-corpus input:
- **F1 — RULE C on the giblet reader.** `hostWeighedGiblets` reads its stir
  gate once per step index (`memo:stirsGiblets`) and the host's bird once
  per section instance (`memo:hostBird`), off the host document the section
  was built from (`sectionRecipeOf` keeps it) — never a per-line host decode
  (a 400-line giblet section at the caps took 32.7 s to compute, 8.9 s per
  GET and 8.0 s per freshness check). The gate "stir … giblets … into" is
  three anchored finds per period-free stretch of a sentence — linear (the
  v68 regex's two greedy `[^.]*` were cubic: 6.35 s a scan of 1,200
  988-character sentences) and equal to it on every sentence (pinned).
- **F2/F3 — a set-aside half takes from ONE line.** "Set aside N <food>
  half" reduces only the food's largest count line (the first of equals),
  read once per head (`memo:setAsideLine`) with the name test before the
  parse; a second line of the food (a garnish) counts whole.
- **F4 — the move, the flag and the deduction never part.** The brisket
  stand-in flags (173128, 168743, 168664) read the printed depth by the
  same phrase `trimDepthRecords` moves the record by — ⅛, ¼ or "⅛ to ¼" —
  and print it ("the printed ⅛-inch fat cap …"); a ⅛-inch flat on 173128
  takes the braised pair's 67.6 % energy share as the ¼-inch one does.
- **F5 — a dimension is read whole or not at all.** The cut-share reader's
  sheet and cutter read a decimal ("3.5", "13.5" — the house style prints
  "16 by 13.5-inch"), a mixed number ("3 1/2", "3½", "3 ½") or a fraction
  whole by the house parser (88.81 % for a 3½-inch cutter on 1105's sheet,
  74.24 % for twelve 3.2-inch rounds), and a figure it cannot read
  ("3-1/2", or one after a period, ".5") reads nothing — the whole dough,
  never the denominator or a decimal's tail as the diameter. The
  thin-piece line test ignores the tail of a spaced mixed number ("1 ½ inch
  thick").
- **F6 — the chopped-portion note only where it sized the line.** A basil
  line printing a weight beside its volume is weighed from the weight and
  its basis names no chopped portion.
- **F7 — the group layout is an input.** `ingredientsHashOf` hashes each
  ingredient group's heading and line count wherever a heading or a second
  group exists (M52's plan, the alcohol reader and the marinade read them):
  a regroup or a heading edit alone stales the totals — a heading added
  to, renamed on or dropped from a recipe's one group too. A recipe of one
  unheaded group hashes as before; the others' stored stamps (320 corpus
  recipes and 9 titled sections) read stale once on deploy — one
  zero-request sweep re-stamps them on identical rows.
- **F8 — the amount-less 0 g rule.** Only the giblet reader's own weight
  passes it; any other amount-less line printing a paren weight counts 0 g
  `unmeasured`, as before v69.
- **F9 — a PUT and a full compute total the same rows.** An engine row an
  earlier M52 plan wrote (budgeted `discarded`, or held with its coat) that
  the current plan no longer covers goes back, in the same totals write, to
  the form the compute writes it (`engineOutcome` on the line's own grams):
  1105's dough rows after its frying oil is skipped, picked or typed
  (439.26 kcal per serving, not 328.13 on the cut share), 0418's flour after
  its chicken is skipped (held `coating`). A row that reverts is one the
  plan may read (a batter counted whole is the fried mix), so the plan runs
  again on the reverted rows, as the compute plans on the engine's: 1081's
  haddock skipped, the batter back to its whole lines and the oil 26.09 g
  on them (815.36 per serving, not 0.25 g on the salt alone and 757.22).
  Only a write that reverts a row plans twice. Closed by v82 F7 (closers
  4–5): a CONFIRMED plan row (a person's confirm, no grams typed) follows its
  food on another row's PUT as the next compute derives it — sw8 0 of 55,893
  divergent; re-confirmed by v83's GATE-P (sw5–sw8 0 divergent at 4325a3d
  and at v83).
- **F10 — a subsection is held to the recipe's editor caps** (60 groups,
  400 lines, 120 steps of 1–10,000 characters, the line and step field
  lengths): nutrition computes each titled subsection as a recipe; only the
  2 MB body bounded them before. Every corpus recipe validates.
- **F11 — the bird is the host's first turkey line WITH a printed
  weight**; a weight-less turkey line before it is passed over.

**Matcher v97 (batch M95; matcherVersion 92 — the fries' uptake from 2709458:
a fried potato keeps FNDDS 2709458's read 15 g oil per 119.89 g raw potato,
12.51 %, not SR 170698's derived 6.0 %; 10 rows, 8 recipes' totals; prep51
design_v2 §1 Q9 / §2 M95, ruled by the owner 2026-10-29 for the record's
own input; zero requests; replayed on snapshot 30 against the v96 rows, both
orders byte-identical, the rule reverted alone reproducing v96 byte for
byte, calls 0).** The O4 uptake (M52's fried-food class, `_friedClassOf`)
of a potato fried from raw — and of the sweet-potato and eggplant stand-ins
that read it — was DERIVED from analytical SR 170698 "Fast foods, potato,
french fried in vegetable oil" (fat 14.7 : carbohydrate 41.4); FNDDS's own
recipe for fries from fresh lists the oil it adds.
- **The record (`_friesFried`, engine.dart; the `_yucaFries` form).** FNDDS
  2709458 "Potato, french fries, from fresh, fried" (cached detail: E 198,
  P 1.93, F 13.1, C 18.5 per 100 g; the cache holds no inputs) — its
  inputFoods, read at live step L51 #2 (.claude/diag/2026-10-29/live51_raw/
  2709458.json), per 100 g of fries: 50 g 11674 "Potatoes, baked, flesh and
  skin, without salt", 50 g 11363 "Potatoes, baked, flesh, without salt",
  15 g 82101000 "Vegetable oil, NFS", 0.4 g salt.
- **The tracer pairs (carbohydrate, 205 — P3's uncoated convention).**
  11674 is not cached (as a hit or a detail), so the flesh-and-skin half
  reads the RUSSET pair, a stand-in by cultivar: SR 170030 "Potatoes,
  Russet, flesh and skin, baked" (a cached hit, 21.4 g — the orchestrator's
  live step L52 read its raw detail, .claude/diag/2026-10-30/live52_raw/
  raw_170030.json: NDB 11356, not 11674; 21.44) over SR 170027 "Potatoes,
  russet, flesh and skin, raw" (a hit, 18.1): 50 × 21.4 / 18.1 = 59.12 g
  raw. The flesh half is 11363 itself, SR 170033 (a hit, 21.6; L52's
  raw_170033.json: NDB 11363, 21.55 — the engine reads the cached hit's
  21.6; at 21.55 r would be 119.75) over the raw flesh the corpus fries
  lines land on, Foundation 2346401 "Potatoes, russet, without skin, raw"
  (the cached detail, 17.77125): 50 × 21.6 / 17.77125 = 60.77 g raw. r =
  119.89 g raw per 100 g of fries: 15 / 119.89 = 12.51 % (0.1251) of the
  raw potato's weight, was 6.0 %. Both halves on the russet pair (118.23 g,
  12.69 %) is not the record's flesh-and-skin / flesh and was not built.
  The three `_friedClassOf` sites read `_readFig('12.51', _friesFried)`
  (the sweet potato and eggplant keep `standIn`); `_friesSr` is gone. The
  split across a recipe's fryers (M83's B4, by the fryers' whole grams) and
  the cap are unchanged. The clause (`_uptakeClause`, derived from two
  records so the flag says so) was "6.0 % of the raw potatoes' weight —
  derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in
  vegetable oil"", now "12.51 % of the raw potatoes' weight — USDA FNDDS
  2709458 recipe: 15 g oil per 119.89 g raw potatoes (its baked potato
  brought to raw by carbohydrate on SR 170030 / 170027 (russet, a stand-in
  for the generic baked potato) and SR 170033 / Foundation 2346401)"; a
  stand-in adds "(no record for sweet potatoes; read as Potato, french
  fries, from fresh, fried)" (eggplant alike).
- **Reach (fix97 gate1, the v96 rows; 10 rows, 8 recipes, 0 person
  rows).** Every row printing the O4 clause, all `auto` / `discarded`,
  grams (kcal), each uptake × 2.085 of its fries' part:
  classic-french-fries|1 "2 quarts peanut oil" 53.53 → 111.60 g (+522.63)
  and |2 "¼ cup bacon fat, strained (optional)" 1.59 → 3.31 g (+15.43) —
  one uptake, 12.51 % × 918.52 g = 114.91 g, split by mass;
  easier-french-fries|1 65.52 → 136.62 g (+639.90) and |2 2.52 → 5.25 g
  (+24.49) (1,133.98 g gold potatoes); fish-and-chips|1 "3 quarts plus ¼
  cup peanut oil or canola oil" 170.78 → 242.53 g (+645.75) — the cod's
  15.38 % × 680.39 g = 104.64 g unchanged, the chips' 6.0 % → 12.51 % ×
  1,102.23 g = 66.13 → 137.89 g; steak-fries|1 and steak-frites|9 68.04 →
  141.86 g (+664.38 each); patatas-bravas|12 "3 cups vegetable oil" 49.60 →
  103.42 g (+484.38); thick-cut-sweet-potato-fries|4 (the stand-in) 65.32 →
  136.19 g (+637.83); crispy-thai-eggplant-salad|10 (the stand-in) 40.82 →
  85.12 g (+398.70) — its Fried Shallots section's oil (56.00 g, the
  printed yield) unmoved. ROW column 3,525,644.75 → 3,530,342.62 =
  +4,697.87; recipe energy 3,376,553.95 → 3,381,251.77 = +4,697.82 (the
  cents are per-serving rounding): per serving classic 309.90 → 444.41,
  easier 355.98 → 522.08, fish-and-chips 856.27 → 1,017.71, steak-fries
  382.59 → 548.68, steak-frites 1,079.57 → 1,245.66, patatas-bravas 423.36 →
  544.45, the sweet-potato fries 435.03 → 594.49 (4 servings each), the
  eggplant salad 491.27 → 690.62 (2); no status changes (two stay partial).
  Sections, holds, notes, buckets and calls identical; staleAfter 0,
  sectionsStale 0; a recompute writes nothing.
Attribution: the three sites put back alone (matcherVersion 92 kept) give
v96's rows, recipes, sections, calls, notes and buckets byte for byte; the
figure alone (12.51 on the old source) moves the same ten rows' grams and
energy and the same eight recipes byte for byte as the rule; the flag alone
the ten bases only; 0 unattributed.
Calibration (reported, never fitted; the direction was known — the FNDDS
record's fat : carbohydrate 0.708 against SR 170698's 0.355 — and every hand
was drawn on a lower uptake): audit 6 R06 easier-french-fries +16.71 →
+71.16 % (hand 305.02) and R07 classic-french-fries −5.32 → +35.77 % (hand
327.32); audit 5 R05 and audit 2 R02 crispy-thai-eggplant-salad +7.26 →
+50.79 % (hand 458.00) and +12.47 → +58.11 % (436.79); audit 3 R13
fish-and-chips +4.46 → +24.15 % (819.75) — all AWAY, disclosed (audit 6's
calibrator sized the uptake on SR 169836's 0.376 and trimmed R06's potatoes
15 % with no figure; at 2709458's 0.708 the audit put R06's hand at 417.8).
Audit 6 median |err| 3.23 % unchanged (mean 7.11 → 10.51); audits 2–5
median 6.87 → 6.95 % (mean 9.71 → 10.80). The owner gate's ruling on the
calibration (the orchestrator under the standing authorization): the gap
is the CHOICE OF RECORD the owner ruled on in Q9, not the arithmetic —
calibrator 1 sized the fries' oil on SR 169836's restaurant-fry fat :
carbohydrate 0.376, judged 2709458 "a soft-fry composition, not a crisp
1/4-inch fry" and trimmed R06's potatoes 15 % with no source (the audit's
own §6 item 7: "Neither is a measurement"); at 2709458's 0.708 it put
R07's hand at 447 a serving, which v97's 444.41 meets within 0.6 %, and
R06's at 417.8, a figure still carrying the unsourced trim (scaled to the
whole 1,133.98 g, roughly 492). Shipped as ruled; a re-ruling of Q9 is the
owner's. Not built, and a MISREAD (corrected here in the owner gate): the
record's 13.1 g fat per 100 g read as a NET of its inputs' 15.1 g ("about
10.8 % of the raw weight") — the record's profile is its inputs divided by
their 115.4 g sum (15 + 0.4 + 50 + 50), so (15 + 50 × 0.13 / 100 + 50 ×
0.10 / 100) / 1.154 = 13.10, the record's 13.1 exactly (the baked halves'
fat from L52's raw_170030 / raw_170033), and water 74.9, carbohydrate 21.5
and protein 2.30 over 1.154 give 64.9 / 18.6 / 1.99 against 65.1 / 18.5 /
1.93, within the russet stand-in's spread; nothing is netted out, and the
oil per gram of raw potato does not depend on that base. The uptake reads
the INPUT, as the yuca figure reads 2709565's (15 g per 100 g raw cassava,
its fries 13.94 g fat).
Person path: no hunk touches nutrition_handlers.dart, `derivedFor`,
`applyDecisionToOthers` or `decisionRecordOf` (a record tuple, a figure and
a flag string), so GATE-P was not run.
Pins: nutrition_v97_test (9 tests — matcherVersion 92; the engine's own
figure through `uptakeFigureForTest` on the real rows' records: 12.51,
2709458, 15 / 119.89 exactly and printed as its own o / r, the stand-ins
flagged, the plantain and yuca figures unchanged; the tracer pairs from the
fixtures' hits and detail → 119.89 = the engine's r; the ten rows on the
fixtures equal the replay (record, grams, energy, the basis verbatim); the
uptake by hand (the B4 split, fish-and-chips' two parts); the converses
crunchy-kettle-potato-chips|0 (10.9 %, the site's chips branch) and the
Fried Shallots oil; the eight totals (the fixtures' standing offsets, each
move the replay's); the GET basis; a second compute writes nothing). Each
mutant killed by a value pin (snapshot copy, anchor count 1, cmp restore):
the potato's figure back to 6.0 (classic|1 / |2 53.53 / 1.59 g), the
eggplant's or the sweet potato's alone, the sweet potato's stand-in flag
dropped, r read on the flesh-and-skin pair for the flesh (120.44) or on one
pair (118.23), the salt read as oil (15.4 g), the tracer clause dropped or
printed on every read figure (fish-and-chips' cod clause), matcherVersion
91. The existing suite re-pinned as equalities (RE-PIN M95): fourteen
version literals (v84–v96, seasoning_ci), three hashes (seasoning_ci,
v47_resolver F2, v83 F5c — the base engine with 92 gives them), the ten
rows and their totals in v53 / v54 / v58 / v60 / v63 / v66 / v69 / v71 /
v85 and 0255's STATED variants in v82 (F5's dips, F7's pick); no numeric
bound widened, nothing deleted.
Cost: no new reader — a record tuple, a figure and a string; every cap
shape keeps its counts.
Deploy note: matcherVersion 92 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 8 recipes' stored totals move (no
users).

**Matcher v96 (batch M94; matcherVersion 91 — the browning fat at 2705972's
share 1.52 %: a fat line a browning heats before the recipe's first skim or
plain pour-off of fat keeps only the film the browned food holds; 22 rows,
21 recipes' totals — the 15 of prep51 design_v2 §1 Q3 Part B and 7 beyond
them, RULED ACCEPT by the orchestrator 2026-10-30 (fix96/ruling4.md; v96
closer 1, verify1 D1);
option (d), ruled by the owner 2026-10-29; zero requests; replayed on
snapshot 30 against the v95 rows, both orders byte-identical, calls 0).**
A browning fat the steps then skim off a braise or pour off a skillet (no
kept part printed) counted whole; it now keeps the fat USDA's sautéed-breast
recipe holds per gram of the raw browned food, capped at the line.
- **The record and the share (`_breastSauteed`, `_browningFatShare`,
  engine.dart — its OWN constant, never the C4 `_panFatShare`).** FNDDS
  2705972 "Chicken breast, sauteed, skin not eaten" (a cached detail on
  snapshot 30: E 176, P 29.6, F 5.45; its `inputFoods` only in the raw JSON
  read by L51 #1, `.claude/diag/2026-10-29/live51_raw/2705972.json`): 98 g
  24122131 "Chicken breast, baked, broiled, or roasted, skin not eaten, from
  raw" and 2 g 82101000 "Vegetable oil, NFS". The 98 g brought to raw by
  protein on prep47's pair (p3_read_figures.md row 27, `_breastFried`'s
  104.76): FNDDS 2705956 (= 24122131; a cached search hit only, P 30.22) ÷
  SR 171077 "Chicken, broiler or fryers, breast, skinless, boneless, meat
  only, raw" (a cached detail, P 22.5) → 98 × 30.22 / 22.5 = 131.62 g; share
  = 2 / 131.62 = 0.015195 (1.52 g fat per 100 g raw; the design's ≈ 1.43 %
  was the protein-BALANCE estimate before L51 #1 read the inputFoods). The
  record lists an oil input, so design (c)'s fallback is not built.
- **The trigger (`_browningFatLines`, memo:browningFat, once per index).**
  The first sentence outside a parenthesis that skims, separates or pours
  off fat (`_skimsFat`: K1 a fat skim or fat separator, K2 a plain pour /
  spoon / drain-off of fat or grease) and is no pour-off down to a printed
  part (`_pourOffAllButFat` — that part is kept, `_partialUseOf`; bulalo's
  "Pour off and reserve oil left in pot" names no fat and is no trigger). A
  fat line (`_panFatHeads`) is admitted when every one of its own mentions
  (`_lineMentionsOf`; none: not admitted) lies before it, each in a sentence
  that heats it (`_panOil`, or a "repeat with the remaining …" of the step's
  browning, `_repeatWith`). A recipe with no fat line is not scanned.
- **The plan (`_browningFatPlan`, merged into `_m52Plan`'s returns first —
  the C4 arm's own write wins on a row both name, the C4 exclusion).** The
  browned food = the recipe's heaviest counted meat row (`_meatRecords` +
  lamb, veal, duck, game — pD d2_optc's set); each admitted engine row
  (unheld, not below the gate, no medium but a printed part used: bulalo's
  ¼ cup, 2 × 1 tablespoon used) is weighed whole as the engine writes it and
  keeps min(whole, share × the browned raw grams ÷ its OWN lipid, 204 of the
  record the totals read) — per line (v96 closer 1, verify1 D3: no budget
  shared between two lines); a line the rule leaves whole is not planned,
  its row as it was (closer 1, verify1 D4). Basis "skimmed / poured off —
  only the fat the browned food keeps counted" and the flag "approximation
  (browning fat: 1.52 g fat per 100 g of the raw beef — USDA FNDDS 2705972
  recipe: 2 g oil per 131.62 g raw chicken breast (the browned piece keeps a
  film; the steps skim / pour off the rest))" (a butter line adds "; a
  butter line weighed by its own fat"; the food's name the browned row's).
- **Reach (fix96/c1 gate, the v95 rows; 0 person, section or status rows).**
  The 15 (v95 → v96 g; 2710180 / 2710186 at 900 kcal, 748608 at its sibling
  171413's 884): hearty-chicken-noodle-soup|0 14.00 → 6.89 (ground chicken
  453.59 g), old-fashioned-slow-cooker-chicken-noodle-soup|2 14.00 → 6.10
  (S2's "Pour off all but 1 tablespoon fat" no trigger; S4's skim),
  pressure-cooker-chicken-noodle-soup|0 14.00 → 11.97, simple-pot-roast|2
  28.00 → 24.12, braised-beef-short-ribs|2 28.00 → 24.12 (beside |0's M72
  deduction), braised-oxtails…|3 26.82 → 15.56, maple-glazed-pork-tenderloin
  |11 28.00 → 18.95 (S3's "Pour off the fat"), pasta-with-hearty-italian-meat
  -sauce-sunday-gravy|0 28.00 → 10.13, chicken-bouillabaisse|2 26.82 → 15.30
  (the brief's 26.83 is M82's rounding), french-style-chicken-and-stuffing-
  in-a-pot|14 9.07 → 6.72, daube-provencal|4 56.00 → 24.12, irish-stew…|1
  42.00 → 20.39, pot-roast-with-root-vegetables|3 42.00 → 25.85,
  braised-lamb-shanks…|2 28.00 → 25.33 (beside M84's |0 pair),
  bulalo…|0 28.00 → 16.82 — ROW −1,439.47. BEYOND them (D1, RULED ACCEPT
  2026-10-30: the design's 15 were pD's hand-cleared rows; the trigger was
  never run over the corpus; the trigger built is the design's, two of the
  seven are true joins the hand pass missed, and no measured vessel or
  browning-subject narrowing keeps the 15 — fix96/ruling4.md): sunday-gravy|20 112.00 → 10.13 (the meatballs'
  skillet, another pan), albondigas-en-chipotle|2 26.82 → 5.17 (the sauce's
  saucepan), broiled-chicken-with-gravy|12 butter 28.36 → 20.68 (the gravy's
  roux), hungarian-beef-stew|6 28.00 → 24.12 (an onion sweat),
  chicken-teriyaki(1178)|6 9.07 → 8.44, best-beef-stew|4 28.00 → 27.57,
  slow-cooker-beer-braised-short-ribs|3 butter 28.36 → 27.93 — ROW
  −1,210.86. ROW column 3,528,295.08 → 3,525,644.75 = −2,650.33; recipe energy
  3,379,204.17 → 3,376,553.95 = −2,650.22 (the cents per-serving rounding).
  Admitted but left whole (20 lines capped on their own fat, e.g.
  steak-au-poivre|7, classic-chicken-noodle-soup|0; coq-au-vin|1's 0 g
  "as needed") and the C4 row
  saltimbocca|5 (23.14 g, the C4 arm's) do not move. Negatives (K-1):
  skillet-roasted-chicken-breasts-with-potatoes|2 84.00 g (mentions at and
  after the pour-off; its S2 bowl toss no heat sentence) and
  chicken-under-a-brick…|2 32.53 g (S2's small-bowl mix no heat sentence);
  steak-au-poivre|0 56.72 g (whisked in off the heat after the pour-off).
- **Person path (v96 closer 1, verify1 D2).** `derivedFor`'s Confirm arm reads
  `_m52OnConfirm` behind `_browningFatAt` too (M78 verify2 D2's `_panFatAt`
  form): a Confirm of a planned browning line is the plan's grams on the
  stored row, the derivation and the GET alike (short-ribs|2 24.12 g, bulalo|0
  16.82 g, maple|11 18.95 g); a line the rule leaves whole confirms at its
  engine weight; typed grams stand. GATE-P (person_sweeps run.sh, 12
  shards, fresh snapshot-30 copies; a `derivedFor` hunk): base f912190 sw5
  31,229, sw6 36,916, sw7 1,839, sw8 56,043 combos and the tip sw5 31,757,
  sw6 37,444, sw7 1,875, sw8 56,943 — 0 divergent, 0 refused, calls 0 on
  both. Those sweeps settle only the recipes holding an `auto` M52 row on
  the snapshot, so they reach 13 of the 21 moved recipes (as `discarded`
  plan rows): the 8 holding none on snapshot 30 —
  pressure-cooker-chicken-noodle-soup, braised-oxtails…, sunday-gravy,
  chicken-bouillabaisse, irish-stew…, chicken-teriyaki(1178),
  pot-roast-with-root-vegetables, braised-lamb-shanks… — are never settled
  or swept there (v96 closer 2, verify2 D4). sw8 with its `planned()` = the
  21 (closer 2, fresh snapshot-30 copies, 12 shards): settled 21, a second
  pass moves 0, calls 0; base 3,858 combos, the tip 5,433 — 0 divergent, 0
  refused on both. Pinned (closer 2): a person's skip of the browned meat
  through the PUT (`_unplannedOf` reads `_browningFatAt`) puts the browning
  line back to its engine row — short-ribs|0 skipped, |2 24.12 → 28.00 g
  `portion` (83.18 /serving); irish-stew|0 skipped, |1 20.39 → 42.00 g
  (166.10) — and a full compute after it writes nothing (verify2 D2); a
  browning line's engine and planned forms key alike in `_m52Key`
  (short-ribs|2, irish-stew|1; the K-1 negative skillet-roasted|2 keys its
  medium bit — verify2 D3, M78's `pans` twin).
Disclosed: a per-raw-gram share overstates a film on a large single piece —
the 1,247.38 g tenderloin keeps 18.95 g, 68 % of its 2 tablespoons.
Calibration (reported, never fitted; rescore2's loaders over v95_recs):
a6 R11 bulalo +8.47 → +3.81 % (hand 360.09; the design's +3.8 alone) and
R19 maple +13.01 → +9.56 % (hand 393.13; the design's +9.1 at 1.43 %) —
both toward; beyond rows move audit 3 R08 chicken-teriyaki-2 +11.95 →
+11.48 % and R12 slow-cooker-beer +4.60 → +4.52 % (toward); medians
unchanged (audit 6 3.23 %, audits 2–5 6.87 %).
Attribution: the bump alone (the base engine, matcherVersion 91) gives v95's
rows, recipes, sections, calls, notes and buckets byte for byte; the arm
alone (matcherVersion 90 kept) gives the tip's byte for byte; 0
unattributed. A literal `_panFatAt` exclusion (measured for the ruling,
not built) refuses maple-glazed-pork-tenderloin|11 — one of the 15, its C4
coat held with no budget — and chicken-teriyaki(1178)|6: 20 rows.
Sections, statuses, holds, notes, buckets and calls
identical to v95; staleAfter 0, sectionsStale 0, kcalCheck 209; a recompute
writes nothing.
Pins: nutrition_v96_test (20 tests — matcherVersion 91; the engine's own
share (`browningFatShareForTest`) equal to 2 / 131.62 and 0.015195 at six
places, ≠ the C4 share; the tracer pair from the fixtures' search hits
(2705956 30.22, 171077 22.5 → 131.62) and 2705972's 176 / 29.62 / 5.45; the
text reader on the real steps (the 22 rows named; the negatives refused; a
capped line and the C4 row named); the 15 rows and the 7 beyond on the
fixtures equal the replay (record, grams, energy, basis, below the whole);
the unmoved rows (the negatives, steak-au-poivre|0 / |7,
classic-chicken-noodle-soup|0 at `portion`, saltimbocca|5 at the C4 arm's
23.14 g); per line (sunday-gravy |0 and |20 10.13 g each; slow-cooker-beer
|3 27.93 g, |2 unplanned); STATED synthesized (a real recipe less one real
sentence, named): a K1 skim and a K2 plain pour-off each a recipe's only
trigger, a "pour off all but N" and bulalo's "pour off and reserve oil" no
trigger, a parenthetical skim no trigger (hungarian S4), a fat line no
sentence names (short-ribs less S1's two oil sentences), a mention IN the
first trigger sentence refused (skillet-roasted less its three real
non-browning oil sentences — S3's toss, S6's whisk and drizzle: |2 named in
S2's "Heat 1 tablespoon of the oil" and IN S5's "pour off any fat in the
skillet, add 1 tablespoon more oil" — closer 3); the heat sentence;
the 21 recipes' per serving (settled; every move the replay's to the cent;
the fixtures' standing offsets stated per recipe); a third compute and a
recompute write nothing; the Confirm, the typed-grams and the skip person
paths; the M52 key; the two cap shapes). Each mutant killed by a value
pin (snapshot copy, anchor count 1, cmp restore): the trigger dropped,
"none at or after" dropped
(steak-au-poivre|0 56.72 → 19.12 g; EQUIVALENT on skillet-roasted|2, which
the heat test refuses too — verify1 D6), the heat test dropped (brick|2
32.53 → 12.58 g), the share = the C4 share, the browning plan winning over
the C4 arm (saltimbocca|5 23.14 → 9.48 g), the derivedFor gate dropped, a
budget shared between lines, capped rows planned, the repeat arm dropped,
the "all but N" exclusion dropped, the parenthetical exclusion dropped, the
no-mention test dropped, `_unplannedOf`'s `_browningFatAt` gate dropped
(short-ribs|2 stays 24.12 g `discarded` after the skip — closer 2),
`_m52Key`'s `_browningFatAt` gate dropped (short-ribs|2's two forms key
apart — closer 2), the boundary read at-or-before (the IN case above {} →
{2}; equivalent on the corpus — its text census over the 1,198 files equals
the tip's 44 lines (closer 3), its replay the tip's rows (verify3 D6)), matcherVersion 90. EQUIVALENT, named: the plan's
guards copied from the C4 arm (an engine row, a held row, a row below the
gate, a medium other than a printed part used) — their mutant replays move
no row. The existing suite re-pinned as equalities (RE-PIN M94): 13 version
literals (v84–v95, seasoning_ci), 3 hashes (the base engine with 91 gives
them), cost maps (+ `memo:browningFat` 1 in v84 / v86 / v87 / v89 / v94;
v82 DECIDED's knownFoodReads + 2 and STRAIN TRUE's recompute strain read —
the plan weighing an admitted line), the 15's rows and totals in v56 / v68 /
v71 / v72 / v86, v72 R-E3's balance (+ the browning rows' move, its 0.006
bound kept), v71 pF R2's bulalo variant (the row the plan's 16.82 g on
either text — R2's own outcome 28.00 / 56.00 g pinned beside it), v81 F1's
sweep 17 → 18; tagged "D1 RULED" (kept by the ACCEPT of 2026-10-30):
v69 sunday-gravy, v71 chicken-teriyaki|6, v72 slow-cooker-beer|3 and its
totals, v54 best-beef-stew, the sweep audit's lazy-portions probe (its
subject, the portion on the cached detail, pinned beside the plan's row).
Cost (RULE C): the reader once per index under `memo:browningFat`, each fat
line's mentions once (`browningFatLineReads`, bounded by lines in
support/cost_bounds.dart); no fat line, no scan; the parenthetical index
only once a sentence skims fat. Two NEW cap shapes in nutrition_v96_test
(braised-beef-short-ribs' real meat line and 399 copies of its real "2
tablespoons vegetable oil" under 120 × 10,000-character steps heating the
oil; TRUE: the last step skims — every oil line named and planned, 24.12 g;
QUIET: no skim — none) count-pinned EXACTLY on compute / GET / recompute.
Base vs tip on the same shapes (closer 1's probe, twice each): QUIET adds
only `memo:browningFat` 1 (compute 924 / 931 → 953 / 944 ms, GET 758 / 792
→ 772 / 772, recompute 320 / 333 → 322 / 322); TRUE adds the reader (399
line reads, one `memo:naming`, the parenthetical index) and, its 399 rows
now plan rows, the plan's own readers once per index on the GET and the
recompute (compute 1,070 / 1,058 → 1,166 / 1,171 ms, GET 791 / 796 → 1,018
/ 1,009, recompute 327 / 331 → 443 / 427 — a NEW reader's TRUE shape,
count-pinned exactly; far under the 10,000 ms backstop). Every
exact-pinned existing cap shape (v84, v86, v87, v89, v94) gains exactly
`memo:browningFat` 1.
Deploy note: matcherVersion 91 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 21 recipes' stored totals move (no
users).

**Matcher v95 (batch M93; matcherVersion 90 — the C4 pan-fat share 3.71 %:
the fried coated breast's oil per gram of breading at the baked coated
breast's breading per gram of raw; 6 rows, 4 recipes' totals; prep51
design_v2 §1 Q3 Part A option (b) / §2 M93, ruled by the owner 2026-10-29;
zero requests; replayed on snapshot 30 against the v94 rows, both orders
byte-identical, the rule reverted alone reproducing v94 byte for byte,
calls 0).** M78's C4 pan fat (the sauté fat the steps pour off or wipe out
after a flour-dusted piece is pan-fried, `_panFatLines`) kept the BAKED
coated breast's oil; the pieces are pan-FRIED, so the kept fat now reads
the FRIED coated record's oil per gram of breading, at the breading the C4
stand-in already counts.
- **The rule (`_panFatShare`, engine.dart).** Two FNDDS recipes already in
  the tree, their `inputFoods` re-read from the raw JSONs on disk: FNDDS
  2705975 "Chicken breast, fried, coated, prepared skinless, coating eaten,
  from raw" (`_breastFried`: breading 99995000 15 g, baked breast skin not
  eaten 24122131 78 g, "Vegetable oil, NFS" 82101000 7 g) and FNDDS 2705980
  "Chicken breast, baked, coated, skin / coating eaten" (`_breastBaked`:
  baked breast skin eaten 24122130 88 g, breading 10 g, oil 2 g; 125.77 g
  raw = its 88 g cooked breast brought to raw by protein, USDA's retention
  convention, prep47's read figures). Share = 7 / 15 × 10 / 125.77 =
  3.7105 g fat per 100 g of the raw coated food (was 2705980's own 2 /
  125.77 = 1.5902). The split over the lines' fat (204, the record the
  totals read), the cap at the whole line, `_panFatLines` and every reader
  are unchanged. `_panFatFlag` names both records — derived from two
  records, so the flag says so. Was: "approximation (pan fat: 1.59 g fat
  per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 2 g oil
  per 125.77 g raw chicken breast (no record for the fat a sautéed piece
  keeps; the steps pour off / wipe out the rest))"; now: "approximation
  (pan fat: 3.71 g fat per 100 g of the raw chicken breast — derived from
  two USDA FNDDS recipes: 2705975's 7 g oil per 15 g breading × 2705980's
  10 g breading per 125.77 g raw chicken breast (no record for the fat a
  sautéed piece keeps; the steps pour off / wipe out the rest))" (a butter
  line adds "; a butter line weighed by its own fat"; a flatfish reads "the
  raw flatfish").
- **Reach (fix95 gate1, the v94 rows; 6 rows, 4 recipes, 0 person
  rows).** Every row that prints the flag, none capped (each below its whole
  line), all `auto` / `discarded`, grams and basis: chicken-saltimbocca|5 "4
  tablespoons olive oil" (FNDDS 2710186, 900 kcal) 9.92 → 23.14 g (+118.98
  kcal); chicken-francese|13 "2 tablespoons olive oil" 5.44 → 12.70 g
  (+65.34) and |12 "2 tablespoons unsalted butter" (SR 173430, 717; the
  split by its own fat, 81.11 %) 5.51 → 12.87 g (+52.77);
  fish-meuniere-with-browned-butter-and-lemon|3 "2 tablespoons vegetable
  oil" (FNDDS 2710180, 900) 5.44 → 12.70 g (+65.34) and |4 butter 5.51 →
  12.87 g (+52.77); parmesan-crusted-chicken-cutlets|6 "4 teaspoons olive
  oil" 6.76 → 15.78 g (+81.18; its whole line 18.14 g — uncapped). No fat
  record here is Foundation (all publish 208). ROW column 3,527,858.70 →
  3,528,295.08 = +436.38; recipe energy 3,378,767.81 → 3,379,204.17 =
  +436.36 (the 2 cents are per-serving rounding): per serving saltimbocca
  417.49 → 447.24, francese 357.45 → 386.97, meunière 258.01 → 287.54,
  parmesan-crusted 333.21 → 353.50 (4 servings each; all stay complete).
  Sections, statuses, holds, notes, buckets and calls identical; staleAfter
  0, sectionsStale 0; a recompute writes nothing.
Attribution: the engine reverted alone (matcherVersion 90 kept) gives v94's
rows, recipes, sections, calls, notes and buckets byte for byte; the share
alone (the v94 flag text kept) moves the same six rows' grams and the same
four recipes byte for byte as the rule; 0 unattributed.
Calibration (reported, never fitted; audit 5 drew these recipes, audit 6
none): R12 francese −19.49 → −12.84 % (hand 444.00); R18 meunière −12.48 →
−2.47 % (hand 294.81); R17 saltimbocca +4.23 → +11.66 % (hand 400.53) and
R21 parmesan-crusted +12.67 → +19.53 % (hand 295.75) — both AWAY,
disclosed (the design's +1.8 → +9.3 % for R17 was priced on v82's rows;
M86's 958 on the breast had already moved it to +4.23 %; R21 lands on the
design's +19.5 %). Audit 5 mean |err| 8.30 → 8.20
%; audits 2–5 median |err| 6.87 % and audit 6 median 3.23 % unchanged.
Person path: no hunk touches nutrition_handlers.dart, `derivedFor`,
`applyDecisionToOthers` or `decisionRecordOf` (a constant and a flag
string), so GATE-P was not run.
Pins: nutrition_v95_test (9 tests — matcherVersion 90; the engine's own
`_panFatShare` (`panFatShareForTest`) equal to 7 / 15 × 10 / 125.77 and
0.037105 at six places; the six real rows on the fixtures
equal the replay (record, grams, energy, the new basis, below the whole
line); meunière's split 23.142 g of fat → 12.70 / 12.87 g; the four totals;
the converses blackened-chicken|10 (in a pan-fat window, no dredged
pan-fry), chicken-piccata|4 (C4, no pour-off) and francese|0 (a fat before
the dredge) unchanged; the GET basis; STATED synthesized (no corpus row is
capped under either share): saltimbocca's pan line as skillet-lasagna's real
"1 tablespoon olive oil" — capped at its whole 14.00 g (v94 kept 9.92) —
and as 0258's real "1 teaspoon olive oil" (4.53 g, capped under both); a
second compute writes nothing). Each mutant killed by a value pin (snapshot
copy, anchor count 1, cmp restore): the share back to 2705980's own oil per
raw (saltimbocca|5 9.92 g), either record's figure swapped for the other's
(oil, breading, raw), the flag naming one record or its oil, the butter's
fat read as oil (meunière|4 11.65 g), the share hard-coded at its rounded
3.71 % (0.0371 — it passed every grams pin and the flag's two places until
the accessor pin), matcherVersion 89; the cap dropped is
EQUIVALENT on parmesan-crusted|6 (uncapped) and is killed by the STATED
capped line (14.00 → 23.14 g). The existing suite re-pinned as equalities
(RE-PIN M93): twelve version literals (v84–v94, seasoning_ci), three hashes
(seasoning_ci, v47_resolver F2, v83 F5c — the version alone: the base
engine with 90 gives them), the four recipes' per serving in v61 / v68 /
v78, v78's six rows, its flag text and its STATED EVOO / clamp / Confirm
cases (the clamp's 4.53 g unchanged), and v26's C4 cap shape's per-line
grams (0.03 → 0.06); no numeric bound widened, nothing deleted.
Cost: no new reader — a constant and a string. Every shape reading
`memo:panFatLines` (v26's C4 quiet / loud, v84 ×2, v86, v87, v89, v94 ×2)
keeps its exact count pins; nutrition_v27_cost_test's O9 / S8 shapes are
bounded by support/cost_bounds.dart, not exact-pinned — a measured probe
(closer 1, verify1's) gives all nine of its count maps base == tip, the
end-to-end O9 GET the one reading `memo:panFatLines` (1 on both).
Deploy note: matcherVersion 90 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 4 recipes' stored totals move (no
users).

**Matcher v94 (batch M92; matcherVersion 89 — the braised turkey: the
roasted same-cut SR pairs behind a line-order gate; 0 rows, 3 recipes'
totals; prep51 design_v2 §1 Q8 option (b″) / §2 M92, ruled by the owner
2026-10-29; zero requests; replayed on snapshot 30 against the v93 rows,
both orders byte-identical, the rule reverted alone reproducing v93 byte
for byte, calls 0).** The doctrine (§0.3): a raw → cooked pair deducts the
fat that leaves the meat only where the recipe's own steps print that it
is not served — and a served breast is never deducted.
- **The rule (`braisedKept` + `_lineOrderGated` + `braisedKeptOf`,
  engine.dart).** No braised turkey record is cached; the ROASTED same-cut
  SR pairs stand in by cooking method, shares by the protein tracer
  (cooked × P raw ÷ (P cooked × raw)), the raw side from the cached DETAIL,
  the cooked side from the cached HIT (neither cooked twin has a cached
  detail): 171093 "Turkey, all classes, breast, meat and skin, raw" (E 157,
  P 21.89, F 7.02, sat 1.91, mono 2.66, poly 1.66) → SR 171492 "…, cooked,
  roasted" (a hit in 'bone-in turkey breast': E 189, P 28.7, F 7.41, sat
  2.1, mono 2.45, poly 1.8) — energy 0.918176, fat 0.805091, saturated
  0.838590, mono 0.702503, poly 0.827043; 171533 "Turkey, retail parts,
  thigh, meat and skin, raw" (E 161, P 19.54, F 9.16, sat 2.386, mono
  2.994, poly 2.454) → SR 171137 "…, cooked, roasted" (a hit in 'bone-in
  turkey thigh': E 183, P 24.0, F 9.5, sat 2.96, mono 3.59, poly 2.95) —
  0.925419, 0.844387, 1.010031 (above 1: the tracer's figure, kept — the
  saturated column gains 1.0 % of the row's), 0.976239, 0.978725. Trans
  stays gross (171093 prints no 605; 171533 → 171137 0.106 → 0.138). For
  these two keys only (`_lineOrderGated`), behind M72's recipe-wide gate, a
  NEW line-order gate: the row's line is named (`_lineMentionsOf`)
  strictly BEFORE the recipe's first defatting sentence (`_firstDefatOf`).
  A line first named in that sentence, after it, or never is counted gross.
  M72's keys (173128, 168664, 168743, 170827) and M84's D3b pairs (167853,
  172513) carry NO such gate — unchanged. The rows stay GROSS (record,
  grams, kcal column, basis — no flag); the totals deduct through the one
  `recomputeTotals` arm, which passes the row's position. Not the
  mixed-part FNDDS 2706118 (option (s)).
- **Reach (fix94 gate1, the v93 rows; 0 rows move, 0 person rows).**
  braised-turkey (S5 "Transfer the liquid to a fat separator", both meat
  lines named in S4): |2 breast 1,817.11 g −233.43 kcal, |3 drumsticks
  and thighs 1,360.78 g −163.40; batch 5,757.53 → 5,360.70, 575.75 →
  536.07 a serving (10). turkey-and-gravy-for-a-crowd (S4's fat separator):
  |12 leg quarters 2,254.35 g −270.69 (named in S2); |16's two breasts,
  first named in S6, roasted on a rack, "Pour any juices from sheet into
  bowl" for the gravy — SERVED, gross (the recipe-wide gate alone would take
  427.96 more); 10,228.93 → 9,958.24, 568.27 → 553.24 (18).
  turkey-thigh-confit-with-citrus-mustard-sauce (S5's fat separator, the
  thighs named in S1): |5 1,487.78 g −178.65; 3,065.16 → 2,886.52, 510.86 →
  481.09 (6). The seven other rows on the two records (roast-whole-turkey-
  breast-with-gravy|0 and -2|0, slow-roasted-turkey-with-gravy|6 |7,
  turkey-breast-en-cocotte-with-pan-gravy|0, grillroasted-boneless-turkey-
  breast|1, porchetta-style-turkey-breast|8) print no defatting sentence:
  gross. ROW column unchanged (3,527,858.70); recipe energy 3,379,613.77 →
  3,378,767.81 = −845.96 (the three stored batch deductions sum to
  −846.16; the 20 cents are per-serving rounding). Rows, sections, statuses, holds, notes, buckets
  and calls identical; staleAfter 0, sectionsStale 0; a recompute writes
  nothing.
Attribution: the rule reverted alone (matcherVersion 89 kept) gives v93's
rows, recipes, sections, calls, notes and buckets byte for byte; 171093
dropped leaves braised-turkey only the thighs' deduction (559.41); 171533
dropped leaves only its breast's (552.41) and puts the crowd and the confit
back; the line-order gate dropped moves the crowd alone, to 529.46; 0
unattributed.
Calibration (reported, never fitted): audit 6 R12 braised-turkey +10.99 →
+3.34 % (hand 518.73); audit 4 R20 the crowd −4.28 → −6.81 % (hand 593.70) —
AWAY, disclosed: its hand counts the legs' rendered fat the steps reserve
for the gravy, which no ingredient line restores. audit 6 median |err| 3.23
% unchanged; audits 2–5 6.77 → 6.87 %.
Person path: no hunk touches nutrition_handlers.dart, `derivedFor`,
`applyDecisionToOthers` or `decisionRecordOf`, so GATE-P was not run.
Pins: nutrition_v94_test (17 tests — matcherVersion 89; the ten shares from
the recorded pairs; the 12 real rows' gate (deducts exactly braised-
turkey|2 |3, crowd|12, confit|5; none with no position, no flag); their
census (5 rows in the 3 recipes that defat, each line's first naming step:
braised-turkey S4 ×2, the crowd S2 / S6, confit S1); M72's and
M84's real rows deduct with no position; STATED on braised-turkey's real
steps (no corpus line sits at the boundary): a breast never named, named
before, IN, after the first defatting sentence and between it and a second
— only "before" deducts; `memo:defatsLiquid` read once for two rows,
nothing read with no position; the three whole recipes on the fixtures equal
the replay (gross rows, per serving, batch energy, fat, saturated); a second
compute writes nothing; two cap shapes). Each mutant killed by a value pin
(snapshot copy, anchor count 1, cmp restore): either key dropped, the gate
dropped, the boundary read at-or-before, the last defatting sentence read,
no position keeping, an unnamed line read as before, the gate on every key,
a share on the hit's rounded protein, the scan under its own memo key, the
totals passing no position, matcherVersion 88. The existing suite re-pinned
as equalities (RE-PIN M92): ten version literals (v84–v93), seasoning_ci's
version and three hashes (seasoning_ci, v47_resolver, v83 F5c — the version
alone: with 88 put back they read their old literals), braised-turkey's per
serving in v59 / v71 / v73 (and the crowd's in v59), and the map's key set
in v69 / v72 / v74 (the M74 / M84 precedent); no numeric bound widened,
nothing deleted.
Cost: no new sentence scan or regex — `memo:defatsLiquid`'s one scan keeps
where it stopped; the gate reads the per-head naming memo. M72's cap shape
(400 short-rib lines) counts equal on base and tip; the new TRUE / QUIET
shapes (400 thigh rows under 120 × 10,000-character steps) count exactly:
the compute + 1 `memo:defatsLiquid`, the GET unchanged, the recompute + 1
`memo:defatsLiquid`, + 1 `memo:naming` and the index's word list (built
once, as the compute and the GET already do) — recompute +2–9 %, far
under the backstop.
Deploy note: matcherVersion 89 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 3 recipes' stored totals move (no
users).

**Matcher v93 (batch M91; matcherVersion 88 — doubanjiang as miso: the
Asian broad-bean chili paste on SR 172442 "Miso", flagged; 2 rows; prep51
design_v2 §1 Q7 (i) option (a) / §2 M91, ruled by the owner 2026-10-29;
zero requests; replayed on snapshot 30 against the v92 rows, both orders
byte-identical, the four keys reverted alone reproducing v92 byte for
byte, calls 0).** Q7 (ii), the drained white tuna (pan-bagnat|14 at SR
173708's drained share, 333.84 g), already shipped in v84 (batch M82, C6b)
and is not part of this batch.
- **The rule (`_rankAs` + `approximationRecords`, matcher.dart — two table
  entries each).** FDC holds no doubanjiang: the lines' own cached answers
  ('asian broad bean chili paste', 'asian broad-bean chili paste' — the
  same 25 records) hold chili stews, FNDDS 2710309 "Bean paste, sweetened"
  and fruit / nut pastes, no miso, and landed SR 172110 "Chili with beans,
  microwavable bowls" at 0.09, below the gate (0 kcal). Both spellings now
  read the shipped doenjang form ('white miso', 'miso'): the cached 'white
  miso' answer (SR 172442 "Miso" at index 1, its detail cached — 198 kcal
  (208), portions tbsp 17 g, cup 275 g; FNDDS 2707439, index 0, has no
  cached detail) ranked under the words 'miso', where 172442 ranks first
  at 1.0 — a rank-as read, never a query rewrite (the v87 lesson).
  `approximationRecords` flags the record for both keys, so the basis
  reads "· approximation (counted as Miso)" through `isApproximation`. A
  stand-in by class (a fermented bean paste; mapo tofu's prep notes: "also
  known as doubanjiang or toban djan"); ATK's printed swap, 2 teaspoons of
  chili-garlic paste or sriracha for the 2 tablespoons (option (b)), is a
  different amount and was not built. [re-point → `item`]
- **Reach (fix93 gate1, the v92 rows; `auto`, 0 person rows).** Two rows,
  the corpus's only lines printing the paste (a third, in
  braised-eggplant's variation, is not computed):
  sichuan-stir-fried-pork-in-garlic-sauce|15 "2 tablespoons Asian
  broad-bean chili paste" 30.50 g on 172110 → 34.00 g on 172442, 67.32
  kcal, basis "2 tablespoon · USDA portion · approximation (counted as
  Miso)"; mapo-tofu-sichuan-braised-tofu-with-beef|6 "⅓ cup Asian broad
  bean chili paste" 81.33 g → 91.67 g, 181.50 kcal, "1/3 cup · USDA
  portion · approximation (counted as Miso)". ROW +248.82 (the design's
  +248.83 priced the mapo row at the rounded 91.67 g; ⅓ × 275 = 91.6667 g
  × 1.98 = 181.50); recipe energy 3,379,364.97 → 3,379,613.77 = +248.80
  over 2 recipes (servings 4: sichuan 400.29 → 417.12, mapo tofu 528.74 →
  574.11 — the cents are per-serving rounding). Mapo tofu turns complete
  (15 of 15 counted; total grams 1,885.3 → 1,977.0); sichuan stays partial
  (its baking soda has no grams; 954.2 → 988.2). Buckets: check 120 → 118,
  counted 13,428 → 13,430, complete 1,054 → 1,055, partial 144 → 143.
  Sections, holds, notes and calls identical; staleAfter 0, sectionsStale
  0; a recompute writes nothing.
Attribution: the four keys reverted alone (matcherVersion 88 kept) give
v92's rows, recipes, sections, calls, notes and buckets byte for byte; the
space spelling's two keys alone move exactly mapo-tofu|6, the hyphen's
exactly sichuan|15; 0 unattributed.
Calibration (reported, never fitted): neither recipe is in an audit 2–6
calibration set (unchanged); audit 6's line sample L010 (sichuan|15, food
WRONG) now reads the stand-in.
Person path: no hunk touches nutrition_handlers.dart, `derivedFor`,
`applyDecisionToOthers` or `decisionRecordOf`, so GATE-P was not run.
Pins: nutrition_v93_test (7 tests — matcherVersion 88; on the real lines
both spellings read `rankAsFor` = the doenjang entry and flag 172442,
never 172110; the converse sauteed-tilapia|3 "2 tablespoons white miso" is
no key and stays on its own answer, 172442 at 0.575 unflagged, 34.00 g;
each line alone on the fixtures (the v37 S3 form): 34.00 g / 91.67 g at
1.0 with their flagged bases; the two whole recipes on the fixtures equal
the replay — both rows, 417.12 and 574.11 a serving, total grams 988.2 and
1,977.0 —; a second compute writes nothing). The fixtures gain the
snapshot's 'soft tofu', 'fermented black beans' and 'sichuan chili powder'
answers, the two lines' own answers (read only when a key is dropped) and
FNDDS 2707359's detail (tool/record_fdc_fixtures.dart --from-db). Each
mutant killed by a value pin (snapshot copy, anchor count 1, cmp
restore): the hyphen spelling's rank-as key dropped (sichuan|15 back on
172110 at 0.09, held, the recipe at v92's 400.29 and 954.2 g), the space
spelling's (mapo-tofu|6 on 172110), either approximation key dropped (the
basis unflagged), the rank words 'white miso' for 'miso' (172442 at
0.575, not 1.0), the flag on 172110 for 172442 (unflagged),
matcherVersion 87. The existing suite re-pinned as equalities (RE-PIN
M91): ten version literals (v84–v92, seasoning_ci) and three hashes
(seasoning_ci, v47_resolver, v83 F5c — the version alone: with 87 put
back they read their old literals); the sweep audit's fixture census
(2707359's detail differs from its hits in some digit: compared 551 → 552,
differ 420 → 421); no numeric bound widened, nothing deleted.
Cost: no new reader — two entries in two shipped tables read by the
shipped rank-as path; no cap shape.
Deploy note: matcherVersion 88 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 2 recipes' stored totals move (no
users).

**Matcher v92 (batch M89; matcherVersion 87 — the repeat multiplier: a
counted "repeat with remaining <N> <piece>" repeats its step's prints; 1
row; prep51 design_v2 §1 Q5 option (c) / §2 M89, ruled by the owner
2026-10-29; zero requests; replayed on snapshot 30 against the v91 rows,
both orders byte-identical, the rule reverted alone reproducing v91 byte
for byte, calls 0).** The grilled pizza's oil:
- **Clause (1), the counted repeat (`_repeatsOf`, engine.dart — a NEW step
  reader).** A step sentence "repeat with (the) remaining <N> <noun>" (N a
  digit run or one–four) counts N further repeats of its step's work when
  <noun> is a PIECE: a unit of the shipped vocabulary (`isMeasureUnit`,
  grams.dart: `_volumeUnitMl` and the weight units, singular or plural)
  refuses — "Repeat with the remaining 1 tablespoon oil" is the remainder
  of a print, not a count (21 corpus recipes print a unit there: 10
  "tablespoon", 4 "tablespoons", 4 "teaspoons", 1 "teaspoon", 1 "cup", 1
  "cups"). The guard reads the noun word and, for the vocabulary's one
  two-word unit, the two words together: "remaining 2 fluid ounces"
  refuses (no corpus repeat prints it). The sentence's other words must
  multiply nothing (R-H1's
  `_multiplies`, once the phrase and a "for each <its noun>" — "for each
  round" for "2 dough rounds" — are blanked), else it refuses as guard (ii)
  always has ("Add the remaining 2 tablespoons oil to the skillet and
  repeat with the remaining 4 cutlets"). The corpus prints 22 counted
  repeats in 20 recipes, none in a section.
- **Clauses (2) and (3), in `_stepAmountsAt`.** Guard (ii) no longer
  refuses a counted repeat naming the head; the first counted repeat at or
  after a print in its step repeats it: (2) a repeat printing no amount of
  the head counts the step's earlier prints × (1 + N) ("Drizzle top of 1
  crust with 1 tablespoon oil … repeat with remaining 2 crusts" — 1
  tablespoon × 3); (3) a repeat printing its own amount ("Repeat with
  remaining 2 dough rounds, adding 1 tablespoon oil to baking sheet for
  each round") counts that print × (1 + N) and LEAVES the step's earlier
  prints (the ¼ cup the sheet is primed with — option (c): the top-up is
  the take), named in the basis "(the ¼ cup base left; …)". A print after
  the repeat counts once; a served print (v85's "each portion") keeps its
  serves; every other multiplying sentence still refuses. Steps only — the
  line's amount-less test is the shipped `line.amounts.isEmpty`
  [re-point → `measurement`].
- **Reach (fix92 gate1, the v91 rows; `auto`, 0 person rows).** One row:
  ultimate-grilled-pizza|12 "Extra-virgin olive oil" (748608) 0.00 g
  `unmeasured` → 80.47 g `portion`, 711.35 kcal (SR 171413's 884), basis
  "from steps 8, 9: 1 tablespoon × 3 + 1 tablespoon × 3 (the ¼ cup base
  left; no amount on the line) · nutrients of "Oil, olive, salad or
  cooking"" — the basis numbers the step LIST (0398 prints two steps "6",
  charcoal and gas, so its printed 7 and 8 are list steps 8 and 9). ROW
  +711.35 (the design's +711.30 multiplied 80.47 g by 240.52 ÷ 27.21, a
  rounded row's figure; 884 × 80.4698 ÷ 100 = 711.35); recipe energy
  3,378,653.61 → 3,379,364.97 = +711.36 over 1 recipe (per serving 800.64
  → 978.48, servings 4: the cent is per-serving rounding); total grams
  1,251.7 → 1,332.1 (the totals' 0.1 g rounding). Statuses, holds, notes,
  sections, buckets and calls identical; staleAfter 0, sectionsStale 0.
  pizza|4 (14.00 g) and |11 (2.00 g) and pB's five guard-(ii) rows
  (indoor-pulled-chicken|8, indoor-pulled-pork|2, bread-and-butter-pickles|11,
  torta-caprese|8, rainbow-cake|8: 0 g) are unchanged.
Attribution: the arm reverted alone (engine.dart and grams.dart at
a43ba1e, matcherVersion 87 kept) gives v91's rows, recipes, sections,
calls, notes and buckets byte for byte; 0 unattributed.
Calibration (reported, never fitted; v91 → v92 per serving): audit 6 R17
ultimate-grilled-pizza 800.64 → 978.48 against the hand 988.01: −18.96 →
−0.96 % (the design's −17.9 → +0.1 % was priced on v82's 811.11; M82–M87
moved the recipe's other rows since); audit 6 median |error| 4.35 → 3.23 %
(mean bias +3.55 → +4.27 %; beyond 15 %: 4 → 3); R17 is in no audit 2–5
set (unchanged).
Person path: none reads a step print's count; no hunk touches
nutrition_handlers.dart, `derivedFor`, `applyDecisionToOthers` or
`decisionRecordOf`, so GATE-P was not run.
Pins: nutrition_v92_test (18 tests — matcherVersion 87; clause (1) on real
sentences: the pizza's two repeats count 2; the noun guard refuses
braised-beef-short-ribs' "Repeat with the remaining 1 tablespoon oil and
the remaining meat." (its "the remaining meat" refuses too),
philly-cheesesteaks' "… 1 tablespoon oil and sliced meat.",
parmesan-crusted-chicken-cutlets' "… 2 teaspoons oil and chicken." and
smoky-pulled-pork's "… 2 cups unsoaked chips."; chicken-saltimbocca's and
best-crab-cakes' repeats refuse by their other "remaining"; the corpus
census (the 22 counted repeats exactly; the 21 unit-noun recipes read
none); clauses (2) and (3) on pizza|12 weighed alone (80.47 g and the
basis; the public reading names the two kept prints; |4 and |11 as at
v91); STATED synthesized cases, no corpus sentence reaching them: a number
word, a weight unit, the two-word unit "fluid ounces" (with or without a
following noun), "for each" another noun and the noun itself, a print
after the repeat (93.88 g), a non-repeat multiplying sentence before a
repeat (refused), a repeat naming the head in a step printing none of it
(40.23 g), gazpacho's served print before a repeat (35.76 g); the whole
recipes on the fixtures (pizza|12's row, 711.35 kcal, 978.43 a serving —
the replay's 978.48 less the fixtures' standing 0.05 —, total grams
1,332.1, the five guard-(ii) rows at 0 g, a second compute writing
nothing); each mutant killed by a value pin (snapshot copy, anchor count
1, cmp restore): × (1 + N) read × 1 (26.82 g), the base kept (134.12 g),
clause (2) dropped (53.65 g), the guard-(ii) exception dropped (0 g) or
taken for any later repeat, every print under the step's first repeat
(120.70 g), a multiplying sentence's step left unscanned, the repeat
counted before the serves (13.41 g), the unit refusal or its two-word
test dropped, the
residue test dropped, the "for each" blank, its plural or exact-noun test
dropped or widened to every noun, the number words dropped, the plural
strip or the weight units dropped from `isMeasureUnit`, the left basis or
the public reading's filter dropped, the `repeats` count dropped,
matcherVersion 86 (the "repeat with" pre-filter dropped is equivalent —
cost only). The existing suite re-pinned as equalities (RE-PIN M89): nine
version literals (v84–v91, seasoning_ci), three hashes (seasoning_ci,
v47_resolver, v83 F5c — the version alone: with 86 put back they read
their old literals), v71's pizza|12 row, its per serving (800.59 →
978.43), R-H1's negatives (pizza|12 leaves the list) and the corpus count
of read lines (5 → 6), v85's B1a negatives row; no numeric bound
widened, nothing deleted.
Cost (RULE C): `_repeatsOf` reads each sentence of a step holding a print
or a named multiplying sentence once per index, inside `memo:stepAmounts`
(a step printing no "repeat with" is never split); a line looks each print
up in its step's repeats by binary search. Cap shapes (0398, 400 lines of
distinct heads under 120 steps of 10,000 characters of the pizza's step 9
pair): QUIET (the repeat on "tablespoons" — the unit guard refuses all
9,325) — counts equal base's exactly, clock 88.5 / 88.5 → 90 / 90 ms
(+1.7 %); TRUE (on "crusts" — 9,705 counted repeats, every print × 3) —
counts base's plus `repeats` 9,705, pinned EXACTLY; clock 84 / 86 → 102.5
/ 103 ms (the reader's own work, no base equivalent); each under the
backstop.
Deploy note: matcherVersion 87 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 1 recipe's stored totals move (no
users).

**Matcher v91 (batch M87; matcherVersion 86 — the own-section rice route:
an unmarked line names its recipe's own section by a TWO-word shared tail
at the section's printed yield; 1 row; prep51 design_v2 §1 Q1 option (b′) /
§2 M87, ruled by the owner 2026-10-29; zero requests; replayed on snapshot
30 against the v90 rows, both orders byte-identical, the rule reverted
alone reproducing v90 byte for byte, calls 0).** The two-word tail:
- **The rule (`_yieldTailOf`, engine.dart — M76's yield-named tail).** The
  closure's first test (the reference item is the TAIL of the section's
  title) gains one arm: or the title's last two words are the last two of
  an item of three or more words (the title may be those two words alone);
  whole words, never one shared word. A shorter item keeps M76's test alone
  (its two shared words are the whole item; equality stays A9's form). The
  mark, the yield guard (the line's share of the section's printed yield is
  exactly 1.0), the memo keys and every reader are unchanged —
  `namesOwnSection` (so `isReferenceIn`, the stale hash, the bulk parent
  test and `routedSectionKeysOf` follow) and the resolver's `_ownTitles`.
  [re-point → `item`]: it reads the parsed item through `referenceItemOf`,
  never the raw line. The prep-note pointer (option (c)) is not built.
- **Reach (fix91 gate, the v90 rows; all `auto`, 0 person rows).** One row:
  fried-rice-with-shrimp-pork-and-shiitakes|9 "5 cups cold cooked white
  rice, large clumps broken up with fingers" (FNDDS 2708408, 790.00 g, 5 cup
  · USDA portion, 1,019.10 kcal) → a `recipe` row on its own "Basic White
  Rice" (MAKES ABOUT 5 CUPS; already stamped through red-beans-and-rice|14)
  at share 1.000000: 402.20 g, 1,486.68 kcal, basis "from the recipe Basic
  White Rice: 402 g, 1,487 kcal" — ROW +467.58 (the design's +423.61 at
  957; the section's Foundation 2512381 rice reads 958 since v90, K-4's
  +43.97). Recipe energy 3,378,186.01 → 3,378,653.61 = +467.60 over 1
  recipe (2 cents: per-serving rounding on both sides — 2,321.05 ÷ 4 =
  580.2625 → 580.26, 2,788.63 ÷ 4 = 697.1575 → 697.16; the batch delta
  is +467.58); per serving 580.26 → 697.16 (servings 4), total grams
  1,791.20 → 1,403.40 (the section's raw rice, not cooked mass). The
  section gains fried-rice
  as its second parent (red-beans-and-rice, fried-rice); its grams, batch
  energy and status are unchanged. Buckets: routed-section rows 65 → 66,
  `recipe` rows 117 → 118; statuses, holds, notes and calls identical; 0
  sections stale. The other shared-tail pairs stay off by the yield (0521|10
  "1 cup bean sprouts" against "Fried Rice with Peas and Bean Sprouts",
  SERVES 4 TO 6) or by the floor (every one-word pair, e.g.
  fresh-strawberry-mousse|5 heavy cream / "Lemon Whipped Cream" at ½,
  juicy-grilled-turkey-burgers|4 soy sauce / its three burger sauces): no
  corpus one-word pair reads the full yield.
- **R14's hash gains the reference terms** (prep notes, sections, groups —
  `ingredientsHashOf`); it re-stamps once, as its row moves anyway.
- **A pick of the whole fried-rice host** (red-beans-and-rice|14 with
  `child` the host, no section — no corpus row, no stored decision) is now
  held `nested_recipe` at 0 g: the host itself reads a sub-recipe (the
  shipped depth-1 rule, `_childRowOf`), as every host routing a line to a
  section already is; a pick of the section is unchanged (402.2 g).
Attribution: the arm reverted alone (matcherVersion 86 kept) gives v90's
rows, recipes, sections, calls, notes and buckets byte for byte; 0
unattributed.
Calibration (reported, never fitted; v90 → v91 per serving): audit 6 R14
fried-rice 580.26 → 697.16 against the hand 675.36: −14.08 → +3.23 % (the
design's +3.2 % with M86's 958; calibrator 2 priced the section's rice at
957, so the hand is itself low by K-4's 11 kcal a serving); audit 6 median
|error| 5.32 → 4.35 %; no other audit recipe is reached (audits 2–5
unchanged: median 6.77 %).
Person path: the routed row is gated by `subRecipeRowFor` (a food pick
re-gated to the 0 g reference row; `child` / `section` / `share`, skip or
typed grams re-point it); no hunk touches nutrition_handlers.dart,
`derivedFor`, `applyDecisionToOthers` or `decisionRecordOf`, so GATE-P was
not run.
Pins: nutrition_v91_test (11 tests — matcherVersion 86; fried-rice|9 on
the corpus line (the item, the yield's share 1.0, M76's tail refusing,
the arm naming it); the converses fried-rice|10, mousse|5 and
turkey-burgers|4; five STATED synthesized cases (0621's real "3
tablespoons fish sauce" against its "Peanut Sauce" printed MAKES 3
TABLESPOONS: refused — the floor; 0521's section retitled "Basic Offwhite
Rice": refused — whole words; retitled "Basic White Rice Pilaf": refused —
the pair is the title's TAIL; retitled "White Rice": named; fried-rice|9's
line and section read with the three-word item "cooked white rice":
named — the item floor's admitting edge); the corpus
scan — of the 49 line × section pairs sharing two or more trailing words
that M76's tail does not reach, exactly fried-rice|9 names its section;
the whole-recipe compute: the routed row 402.20 g at 1.000000, the child's
1,486.68 kcal, the basis, 697.16 a serving, the section's two parents, the
converse rows on their foods, a second compute writing nothing), each
mutant killed by a value pin (snapshot copy, anchor count 1, cmp restore):
the arm dropped, the floor at one word, the item floor at two words (v76's
has-lines pin), the item floor at four words, whole words dropped, the
pair anywhere in the title (`contains` for `endsWith`), the
title-is-the-pair clause dropped, matcherVersion 85. The existing suite re-pinned as equalities (RE-PIN
M87): the eight version literals, three hashes (seasoning_ci, v47_resolver,
v83 F5c — the version alone: at 85 with the arm kept they read their old
literals), v41's whole-library resolver map (+ fried-rice|9), v72's reach
row, totals and pA R2 (the record's portion now read off the fixtures), v73's
row and totals, v81 F15's host pick (`nested_recipe`, 0 g; the host's total
grams 1,403.4); no numeric bound widened, nothing deleted.
Cost: no new reader — the pair is computed once per line outside the
closure, and every read past the first test is the shipped memo's. The
yield cap shapes' counts are base's exactly; the new TRUE-path shape
(rtail2: 400 lines "1 pound cold pizza dough" × 60 subsections, one
"Classic Pizza Dough" at MAKES 1 POUND) routes every line and reads each
line's mark and share once and its yield once per step (400 / 400 / 400,
indexes 1), pinned EXACTLY; clocks within noise of rtail1.
Deploy note: matcherVersion 86 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 1 recipe's stored totals move (no
users).

**Matcher v90 (batch M86; matcherVersion 85 — 958 before 957: a Foundation
record's energy is its Atwater SPECIFIC figure; 1,299 rows on 107 records
and 30 routed parents; prep51 design_v2 §1 Q2 option (b) / §2 M86, ruled by
the owner 2026-10-29; ALONE — a one-way door; zero requests; replayed on
snapshot 30 against the v89 rows, both orders byte-identical, the list order
reverted alone reproducing v89 byte for byte, calls 0).** The energy order:
- **The rule (`nutrients.dart` energy `fdcNumbers`).** `['208', '957',
  '958']` → `['208', '958', '957']`. Every energy reader walks the one list
  — `kcalPer100g`, `recomputeTotals`' `add` (and its `hasEnergy`), the
  braised-share arm of `braisedKeptOf` (its 'energy' reads `kcalPer100g`),
  `ethanolKcalPer100g`, and the replay's `kcalOf` (tool/replay/rp43.dart
  reads `nutrientDefs.first.fdcNumbers`, no order of its own); the two
  presence checks (`_macroComplete`, `publishesNothing`) are order-free.
  RULE B's thresholds and every gram reader are unchanged: grams, basis,
  gram source, status, hold and record never move.
- **Census by data type (snapshot 30; the cache's 1,139 details and the
  cached search hits, 8,431 records).** Only Foundation records publish 957
  / 958, and never beside 208: Foundation 186 publish both (121 detail-
  cached), 24 publish 957 only (9 detail-cached: fennel, parsnips,
  jalapeño, poblano, serrano, radicchio, sea scallops, turnips, watermelon
  rind — they fall back to 957, unchanged), 82 publish 208, 60 none; every
  SR Legacy (4,567) and FNDDS (3,511) record publishes 208 alone (one FNDDS
  hit none). A per-dataType switch (option (c)) is therefore byte-identical
  to the reorder — not built.
Reach vs the v89 rows (fix90 gate1, main == rev; all `auto`, 0 person rows,
0 status / hold / gram-source / record changes; buckets, notes and calls
identical; 37 of 144 sections move, totals only):
- **1,299 rows on 107 Foundation records publishing 958**, each moving in
  its energy alone, and every counted row on such a record moves (0 left):
  1,298 single-record rows, every new figure the old × 958 / 957 within
  rounding, and one parts row, the drained-can split
  espinacas-con-garbanzos-andalusian-spinach-and-chickpeas|1 "2 (15-ounce)
  cans chickpeas (1 can drained, 1 can undrained)" — only its drained part
  on 2644288 moves, 240.26 g × (132.972 − 137.22) / 100 = −10.21 (703.90 →
  693.69 kcal; the undrained can's 425.24 g on SR 175206, 208 at 88,
  unchanged), so its figure is not the old × 958 / 957. ROW −9,044.14 (the
  design's −9,044.8 on the v82 rows). Down 79 records / 1,053 rows
  −17,870.15 (plants, nuts, cream), up 28 / 246 +8,826.01 (meats, rice). The
  ten largest record moves: 2346386 heavy cream 146 rows −2,322.55 (343.31
  → 335.89 kcal per 100 g), 2646170 chicken breast boneless skinless 49
  +1,950.43, 2346395 pecans 28 −1,852.39, 2646171 thigh boneless skinless 31
  +1,153.27, 2685581 crushed tomatoes 21 −951.42, 2646175 flank 18 +732.07,
  2346394 walnuts 13 −729.20, 2685578 whole canned tomatoes 33 −640.36,
  2727572 NY strip 9 +608.24, 2727573 tenderloin 8 +598.62. Search-hit-only
  records move too (no detail cached; their hit's figures): 1999633 mature
  spinach, 2646168 boneless pork loin (6 rows +415.03), … E.g. roasted-
  brussels-sprouts|0 "2¼ pounds Brussels sprouts, trimmed and halved" 918.52
  g on 2685575 546.38 → 448.04 kcal (59.485 → 48.7787).
- **30 routed parents** (source `recipe`; the child's kcal × share, and the
  basis quotes it — "from the recipe Basic White Rice: 402 g, 1,487 kcal":
  only its kcal changes), ROW −228.50: e.g. red-beans-and-rice|14 → Basic
  White Rice (2512381, 369.637 for 358.705) +43.97 and nasi-goreng|10 Faux
  Leftover Rice +43.97, cheesy-nachos|6 Chunky Guacamole −77.78, beef-
  satay|8 −54.50, bittersweet-chocolate-roulade|10 −43.55, tamales|10
  +29.69, the four double-crust pies |0 −1.58 each. The brief's census named
  only the rows on 958 records; the parents are the routing consequence (the
  M82 / M90 "routed parents" precedent).
- **Recipe energy** 3,387,063.25 → 3,378,186.01 = −8,877.24 over 758 recipes
  (the design's −8,877.6 / 758 on v82). The rows M90 also moved: 746784
  granulated sugar publishes 208 (385) — none of M90's sugar rows moves
  here; 8 rows move in both batches (chili-con-carne|13 masa harina on
  2710835 150.14 → 133.27 → 129.71 kcal, and 7 routed parents).
Attribution: the list order reverted alone (matcherVersion 85 kept) gives
v89's rows, recipes, sections, calls, notes and buckets byte for byte; 0
unattributed.
Calibration (reported, never fitted; v89 → v90 per serving): CIRCULAR — the
audits' hands read the engine's own records at 957 (audit 6 §4.2 item 10),
so agreement measures 957, not truth; calibrator 2's own 958 re-hands
(audit 6 calibration_2.md) agree with the move: R23 137.67, the replay's
figure exactly, and R16 peach-crisp 626.61 (the replay 627.67). Audit 6 median |error| 3.59 → 5.32 % (bias +3.67 →
+2.86 %; 12 of 25 move away): R23 roasted-brussels-sprouts 0.00 → −10.64,
R21 carrot-ginger-soup −18.06 → −20.06, R05 chicken-kiev +12.38 → +14.57,
R09 +6.24 → +7.83, R24 briam −0.67 → −2.89, R16 peach-crisp +0.17 →
−2.07, R07 −3.59 → −5.32, R04 +0.39 → +1.77, R25 0.00 → −1.04 (away); R06
easier-french-fries +18.47 → +16.71 and R18 cranberry-chutney +2.19 →
+0.54 (closer). The 100 (audits 2–5) median 6.25 → 6.77 % (beyond 15 %: 17
→ 15; 31 closer, 35 away): a5 R08 brussels-sprout-salad +7.55 → +2.44 and
R10 crispy-skinned breasts −11.36 → −8.36 (closer); a3 R09 breaded-
chicken-cutlets +9.42 → +12.42, a4 R21 garlic-studded pork +6.25 → +9.15,
a3 R10 herb-crusted pork +6.58 → +9.32, a5 R21 parmesan-crusted +10.45 →
+12.67, a5 R23 lighter-chicken-parmesan +10.23 → +12.57 (away — the
up-moving Foundation meats); audit 4 median 11.51 → 12.61 %, audit 3 6.58 →
6.93 %, audit 2 2.17 → 2.17 %, audit 5 5.20 → 5.20 %.
Person path: none — a kcal read; typed grams untouched; no hunk touches
nutrition_handlers.dart, `derivedFor`, `applyDecisionToOthers` or
`decisionRecordOf`, so GATE-P was not run.
Pins: nutrition_v90_test (5 tests — matcherVersion 85; the energy def's
order and `kcalPer100g` on 2685575's recorded hit (48.8, its 957 59.5),
2346386 (335.8933), the 957-only 2747662 (27.9906, its fallback), the
208 records 746784 (385) and 170848 (392); five stated corpus rows on a
whole-recipe compute — roasted-brussels-sprouts|0 on 2685575 (448.24 on
the fixtures' hit; the replay's detail gives 448.04), ultimate-cream-of-
tomato-soup|8 "½ cup heavy cream" 119.48 g, 401.32 kcal (was 410.18), and
unmoved: vietnamese-beef-pho|6 on 746784 24.81 g 95.50, skillet-chicken-
fajitas|10 on 2747662 453.59 g, italian-style-turkey-meatballs|3 on
170848 28.35 g 111.13; a6 R23's total 137.71 on the fixtures (the replay
154.06 → 137.67) and R03 oven-fried-onion-rings 541.73, unmoved; a second
compute writing nothing), each mutant killed by a value pin (snapshot copy,
anchor count 1, cmp restore): the list order restored, matcherVersion 84.
The existing suite re-pinned as equalities (RE-PIN M86). The census ran
first — the three suites on the changed tree before any pin: server 98
failing tests in 43 files, salt_shared 0, app 3 in 2 files. With the list
reverted alone (matcherVersion 85 kept) 9 of the 98 still fail — the six
version literals and three hashes (seasoning_ci, v47_resolver, v83 F5c:
the version alone); the other 89 pass at v89's literals, so every energy
move they carry is the reorder's. Re-pinned (in rounds — a test stops at
its first failing assertion): 42 server test files, 397 energy sites
(per-serving and batch totals, row kcal, section batches, routed-child kcal
and the "N kcal" their bases quote, v54's ethanol before / after pairs
moved alike), v72's moved-since-v71 iff gains `_m86Moved` (22 entries) and
its R-E3 deduction identity an `m86` term (each 958 row's grams × (958 −
957) / 100; `lessThan(0.006)` unchanged), nutrition_v63's "957 30.8"
sentence re-worded; no numeric bound widened, nothing deleted; 12 contract
goldens re-captured (values only: energy amounts, kcal per 100 g, calories
per serving, % DV, the routed basis's kcal), so the salt_shared and app
suites ran (the app's 2 files, 4 sites: Blueberry Pie's label 563 and its
dough 3,054 kcal). The records the re-pins name: 72 — 55 of foods.json's 68
details publishing 958 (the design's 66 + 2514744 ground beef 80/20 and
2710835 masa harina, recorded since) and 17 of searches.json's 99 958 hits
with no detail recorded (2685575 Brussels sprouts among them); none
outside.
Cost: no new reader — a constant list reorder that every energy reader
already walks; no cap shape (nothing per line or per step changes).
One-way door: every Foundation row (1,299 counted today, every future one)
and the stored totals of 758 recipes; no users (owner 2026-10-09) — ships
unguarded, alone. Deploy note: matcherVersion 85 stales every stamp — run
the owner's stale sweep after the deploy (0 requests); 758 recipes' stored
totals move. The kcal digest (`tool/replay/digest.sh`) moves 764,596.77 →
762,643.69, −1,953.08 (Σ total grams 1,891,121.0 unchanged over 1,342
rows) — a per-serving sum, not the recipe energy above.

**Matcher v89 (batch M90; matcherVersion 84 — 347 rows on the six keys'
own lines and 76 consequence rows, 423 in all: a corpus-printed cup over a
record's own volume figure; prep51 design_v2 §1 Q6 (b) / §2 M90, ruled
under the 2026-10-07 standing authorization; zero requests; replayed on
snapshot 29 against the v88 rows, both orders byte-identical, every moved
row attributed to its key by reverting that key alone, calls 0).** The
printed densities:
- **The rule (`_densities`, `_approximateDensities`).** Six keys weigh the
  corpus's printed cup AHEAD of the record's own volume figure — recordFirst
  false, v49's tapioca-starch form — each figure oz × 28.3495 ÷ 236.588 and
  each row flagged with its print (`· approximate (ATK: 1 cup … = N
  ounces)`); every count is a corpus grep of the "<volume> [packed]
  (<weight>) <item>" lines: packed **brown sugar** 7 ounces a cup (86 of 88
  prints; 7.2 and 7.11 the others) 0.8388, was 0.93 (SR 168833's 'cup
  packed' 220 g); **cornstarch** 4 (4 of 4 — three "¼ cup (1 ounce)", one
  "½ cup (2 ounces)") 0.4793, was 0.54 (SR 169698's 'cup' 128 g); **sugar**
  and **granulated sugar** 7 (225 of 237 exactly, superfine's two aside)
  0.8388, was the kitchen 0.85; **cornmeal** 5 (8 of 9; 0387's 5½) 0.5991,
  was the kitchen 0.66 (SR 169697's 'cup' 122 g is 0.516); **confectioners'
  / powdered sugar** 4 (34 of 34) 0.4793, was 0.51 (SR 169656's 'cup
  unsifted' 120 g); **bread flour** 5½ (21 of 31 exactly, 27 within 0.7 %)
  0.6590, was the kitchen 0.52 (SR 168913's 'cup unsifted, dipped' 137 g).
  A record's portion in the line's OWN unit still wins first: Foundation
  746784 "Sugars, granulated" publishes a 'cup' 188 g and a 'teaspoon' 4 g,
  so every cup and teaspoon line of sugar stays on the record — the print
  reaches its tablespoon lines and the volume parts the arm weighs (a cup of
  sugar does NOT read 7 ounces). The corpus's "confectioners’ sugar"
  normalizes to 'powdered sugar': no corpus line reaches the 'confectioners
  sugar' spelling (the table pins it). CLOSED, as the brief says: cake flour
  (no unprinted row), cocoa (the head-noun rule reads SR 169593's cup); Z5's
  recordFirst keys keep the record's own figure (red-lentil-kibbeh|9 "¾ cup
  dried red lentils" 144.00 g on 174284's cup). The `_approximateDensities`
  doc sentence: was "a printed figure for a portion-less record, never over
  a record's portion: 'lentil' …"; now "… a printed figure for a
  portion-less record (Z5's keys keep it: 'lentil' …). A key that is not
  `recordFirst` weighs ahead of the record's own volume figure: v49's
  tapioca starch, and since v89 … the six keys whose corpus print is the
  cookbook's own measure".
- **RULE B's medium thresholds read the same figures** (engine
  `_mediumMl` → `densityOf`, the v49 tapioca / v84 flour precedent): ¼ cup
  of cornstarch is 28.35 g (was 31.9) and of sugar 49.61 g (was 50.3); 0
  corpus rows change classification (no status, hold or gram source moves);
  nutrition_v28_rule_b's I3(e) reads cornstarch at its print (it left the
  record-cup list, as tapioca did at v49) and I3(f)'s brine-sugar boundary
  pair is 50 / 49 g (was 51 / 50: 50 g is 59.61 mL ≥ ¼ cup at 0.8388).
Reach vs the v88 rows (fix89 c1/g1, main == rev; all `auto`, 0 person
rows, 0 status / hold / gram-source changes; buckets, notes and calls
identical; 49 of 144 sections move, totals only): 423 rows, ROW column
−3,027.72, recipe energy 3,388,945.72 → 3,387,063.25 = −1,882.47 over 283
recipes (the design's ≈ −1,725.09 on ≈ 259 carried neither (c) nor (d)):
- (a) the brief's 347 density rows on the keys' own records, every one
  moved: brown sugar 110 (ROW −1,867.98), cornstarch 108 (−492.28), sugar
  112 — every one a tablespoon line on 746784 — (−147.71), cornmeal 8
  (−234.42), powdered sugar 6 (−20.32), bread flour 3 (+51.96); ROW
  −2,710.75 (the design's −2,711.93 scaled rounded v88 grams: 1 cent off
  the engine on 67 rows). E.g. cranberry-chutney-with-apples-and-
  crystallized-ginger|6 "1 cup packed brown sugar" 220.03 → 198.45 g,
  gingerbread-layer-cake|2 "3 tablespoons cornstarch" 23.95 → 21.26,
  kanelbullar|12 "1 tablespoon bread flour" 7.69 → 9.75 (the brief's 9.74
  was rounded).
- (b) 28 routed parents (source `recipe`, the child's kcal), ROW −158.76:
  the 10 whole-recipe dough parents of critique2's K-5, −10.85 (the
  design's −10.97 was its model) — blueberry, classic-apple, deep-dish-
  apple and sweet-cherry |0 (All-Butter Double-Crust 642.90 → 642.70 g),
  chocolate-cream-pie-with-all-butter-crust|0 and peach-tarte-tatin|0
  (334.60 → 334.40), fresh-plum-ginger-pie|0 (669.10 → 668.80), coconut-
  cream|9, key-lime|3, summer-berry|7 (Graham Cracker Crust 220.60 →
  220.10) — and 18 section-routed host rows, −147.91, the routing
  consequence of the 347's section rows (M82's "routed parents"): crisp-
  skin-high-roast-butterflied-turkey…|4 (Golden Cornbread, −83.90),
  bittersweet-chocolate-roulade|10, guay-tiew…|15, memphis-style-
  barbecued-spareribs|0, barbecued-pulled-pork|1, beef-satay|8, juicy-pub-
  style-burgers|5, grill-roasted-bone-in-pork-rib-roast|4, grilled-pork-
  chops|3, fresh-peach-pie|7 and its all-butter twin |7, triple-berry-
  slab-pie|0, the single-crust doughs of quiche-lorraine|0, pumpkin-pie|0,
  pecan-pie|0, lemon-meringue-pie|0 and fresh-strawberry-pie|0, pupusas…|7.
- (c) 20 coat and medium rows re-solved on the keys, ROW −70.68. The
  design's nine not-modelled `discarded` key rows (critique2 K-9), on this
  replay: crispy-pan-fried-pork-chops|0 49.83 g, orange-flavored-chicken|13
  45.47 and karaage…|7 45.47 UNMOVED (their budgets cap them); fish-and-
  chips|3 28.21 → 25.75, crispy-salt-and-pepper-shrimp|8 39.92 → 35.44,
  shrimp-tempura|3 29.96 → 27.39, crispy-fish-sandwiches…|7 46.41 → 43.57
  (the design's 31.45 and 49.79 were v82's, before M82's re-solve),
  dakgangjeong|9 7.02 → 6.35 with |8's flour 41.53 → 42.32 (§0.5's
  combined figures), indoor-pulled-pork…|1 25.14 → 24.81 (its "plus"
  part); with them 13 co-parts on NON-key records re-solving at the same
  budget, each UP (a lighter starch part leaves the others more):
  dakgangjeong|8, fish-and-chips|2 |4 |5 |8 |10, shrimp-tempura|2 |4 |5 |6,
  crispy-fish-sandwiches|6 |9 |10; and buffalo-cauliflower-bites|4, the
  frying oil scaled to the batter's carbohydrate (122.16 → 109.56 g of
  229.20): 73.30 → 65.74 g, −68.04. yeasted-doughnuts|1 prints its weight
  and does not move; the 26 zero-gram `discarded` key rows (brine and cure
  sugars — the design counted 25) do not move.
- (d) 28 rows beyond the design's census, ROW −87.53 — its census took only
  `density` rows on each key's own records; the same figure reaches them
  through another source or record, and no gate keeps them without an
  unsourced figure on the key's own food (§0.1), line grammar (§0.8) or a
  seventh key — ruled ACCEPT (fix89/ruling4.md): 21 "plus" parts
  weighed at the key's figure on weight / portion rows (brown sugar 2:
  apple-blackberry-betty|1 172.57 → 165.37 g, its ⅓ cup packed now 66.15 g
  — its own printed 2⅓ ounces — and apple-crumble|1 126.73 → 124.03; sugar
  19 on 746784, e.g. cream-cheese-coffee-cake|8 286.43 → 285.27, holiday-
  eggnog|1 119.14 → 118.81); shrimp-pad-thai|3's step print 39.21 → 38.71
  g; and two stand-in records a key sizes as a word — SR 170674 "Sugar,
  turbinado" (five rows, e.g. classic-creme-brulee|5 41.90 → 41.34 g, now
  flagged with sugar's print; its own 'cup' 202 g and the corpus's one
  turbinado print, "¾ cup (6 ounces)", are both heavier — these rows move
  away from both, 1.3 %; RECORDED: a turbinado item for the next design
  pass) and Foundation 2710835 masa harina (chili-con-carne|13 "5
  tablespoons masa harina or 3 tablespoons cornstarch" 39.92 → 35.44 g,
  onto masa harina's own print on 3 of its 4 lines, 4 ounces a cup).
Attribution (each key reverted alone on a scratch tree, fresh snapshot
copies; all six reverted reproduces v88 byte for byte): brown sugar 119
rows / recipe energy −961.13 (82 recipes), cornstarch 128 / −540.94 (97),
sugar 159 / −190.46 (135), cornmeal 10 / −221.61 (8), powdered sugar 7 /
−20.30 (6), bread flour 3 / +51.91 (3); 0 unattributed. Three rows answer to
TWO keys by construction (a child or a batter holds both): barbecued-
pulled-pork|1 (Dry Rub: brown sugar −7.69, sugar −0.48), crisp-skin-high-
roast-butterflied-turkey…|4 (Golden Cornbread: sugar −0.96, cornmeal
−82.95), buffalo-cauliflower-bites|4 (the batter's oil: cornstarch −53.10,
cornmeal −14.94).
Calibration (reported, never fitted; v88 → v89 per serving against each
audit's hand count): audit 6 median |error| 4.44 → 3.59 % (bias +3.95 →
+3.67) — R18 cranberry-chutney +8.48 → +2.19 %, R04 nasi-goreng +0.71 →
+0.39, R22 peach-tarte-tatin +0.59 → +0.52 (a K-5 parent), R15 shrimp-pad-
thai +0.23 → +0.15 (its step print, (d)), R20 gingerbread +0.03 → −0.08 and
R17 pizza −18.61 → −18.63 (away, by hundredths); audit 4 median 11.22 →
11.51 % (worse) — R14 buffalo-cauliflower-bites −11.22 → −15.80 % (AWAY,
3.1 points beyond the design's −12.7: it priced the cornstarch row alone,
the replay moves the batter's frying oil |4 too), R07 shrimp-tempura
+45.14 → +45.70 (away, its co-parts), R23 dakgangjeong −15.79 → −15.86,
R04 onion-braised-beef-brisket −19.75 → −19.87, R15 our-favorite-chili
−1.00 → −1.22 (away), R13 smoked-pork-loin +15.73 → +14.10, R19 meatloaf
+16.71 → +16.01; audit 3 R05 orange-flavored-chicken +14.07 → +11.76 %
(the design's +12.1), R13 fish-and-chips +4.29 → +4.35 (away, its co-
parts); audit 2 median 2.74 → 2.17 % — R06 beef-satay +26.02 → +24.90,
R09 summer-berry-pie +2.74 → +2.17 and R18 plum +1.25 → +1.01 (K-5
parents), R24 fluffy-dinner-rolls −0.06 → +1.02 and R01 crisp-skin turkey
−1.16 → −1.95 (away: bread flour, the cornbread's cornmeal); audit 5
median 5.41 → 5.20 %.
Person path: none — typed grams win (an `override` row keeps its typed
figure; the table sizes engine-derived grams only); no hunk touches
nutrition_handlers.dart, `derivedFor`, `applyDecisionToOthers` or
`decisionRecordOf`, so GATE-P was not run.
Pins: nutrition_v89_test (12 tests — the six figures as oz × 28.3495 ÷
236.588 for every spelling, the closed and neighbouring keys and RULE B's
two ¼-cup masses; one stated corpus row per key spelling at its print and
flag, through `lineGrams` on the row's own fixture record; the converses —
a weight-printed line per key, a cup-unit sugar line on 746784's own cup,
the Z5 lentil — at their v88 rows; every (d) row `lineGrams` weighs alone
as the replay moves it (27 — the 28th, the pad thai's step print, is
nutrition_v71's); the two-key rows and the nine section-routed hosts no
earlier pin held (beef-satay|8, fresh-strawberry-pie|0, grill-roasted-bone-
in-pork-rib-roast|4, juicy-pub-style-burgers|5, memphis-style-barbecued-
spareribs|0, pupusas…|7, triple-berry-slab-pie…|0, the turkey|4) on a
whole-recipe compute, barbecued-pulled-pork|1 as its Dry Rub's own total
(149.90 g, 369.28 kcal; the host reads 0.75) — each two-key row dying under
BOTH its keys' figure mutants, at the replay's single-key reverts (turkey|4
1,146.22 / 1,167.53 g, buffalo|4 71.64 / 67.40 g); dakgangjeong's |8 / |9 on the combined figure, two whole-recipe totals and
a second compute writing nothing; the two cap shapes), each mutant killed by
a value pin (snapshot copy, anchor count 1, cmp restore): each key's figure
put back (brown sugar 198.45 → 220.03 g, cornstarch 21.26 → 23.95, sugar
24.81 → 25.14, granulated sugar 24.81 → 25.14, cornmeal 26.58 → 29.28,
powdered sugar 7.09 → 7.54, bread flour 9.75 → 7.69; 'confectioners sugar'
by its table pin alone — no corpus line reaches that spelling), brown sugar
and bread flour recordFirst (the record's own 220 g packed cup, 168913's
8.56 g tablespoon), the cornstarch and sugar labels dropped (the flag
gone), matcherVersion 83. The existing suite re-pinned as equalities (RE-
PIN M90; 39 files): the version literals and three hashes (the version
alone — the base tree with only the bump gives each), the v69 sugar-density
table (all 234 rows), the coat budgets and the dips that ride on them (v50,
v53, v57, v58, v60, v65, v66, v69, v80, v82, v84), the dough children and
their parents (v41, v41_api, v46, v47_resolver, v52, v72, v81), the
totals, the RULE B boundaries (v28), and 13 contract goldens re-captured
(the legacy-v0 and corpus doughs' sugar, e.g. the all-butter double-crust
642.9 → 642.7 g) — so the salt_shared and app suites ran.
Cost: no new reader — a table change; the six figures and their
`_approximateDensities` entries are read by the volume arm `lineGrams`
already walks. The cap shapes (400 repeated real lines under the real
steps): TRUE 400 × gingerbread-layer-cake|2 "3 tablespoons cornstarch",
QUIET 400 × red-lentil-kibbeh|9 (Z5) — every step-index count identical to
base d02f207; base → v89, two runs each, compute + GET: TRUE 382, 367 →
381, 360 ms, QUIET 458, 479 → 449, 453 ms, each under the 10 s backstop.
Deploy note: matcherVersion 84 stales every stamp — run the owner's stale
sweep after the deploy (0 requests); 283 recipes' stored totals move (no
users). The kcal digest (`tool/replay/digest.sh`) moves 766,098.68 → 764,596.77, −1,501.91
(Σ total grams 1,891,890.0 → 1,891,121.0 over 1,342 rows) — a per-serving
sum, not the recipe energy above.

**Matcher v88 (batch M88; matcherVersion 83 — 10 rows in 4 recipes: the
coat parts of FNDDS 2706442's crust; prep51 design_v2 §1 Q4 (b) / §2 M88,
ruled under the 2026-10-07 standing authorization; zero requests; server
only; replayed on snapshot 29 against the v87 rows, both orders
byte-identical, every moved row attributed to the split by reverting it
alone, calls 0).** The dredge's own figure:
- **The two inputs.** FNDDS 2706442 "Chicken or turkey parmigiana"
  (live62_raw/2706442.json, inputFoods by `sequenceNumber`) prices the
  breading as SEPARATE inputs per 1 + 10 raw breast 510.3 + 170.1 = 680.4
  g: 3 flour 31.25 g (Foundation 789890 — the input itself, 77.3 %
  carbohydrate) and 5 dry crumbs 81 g (SR 174928, 71.98 %); 4 the egg 100 g
  is the wash, sized by W. Every corpus vehicle runs the record's order,
  flour → egg → crumbs (0122 S4, 0118 S4, 0117 S3, 0416 S3). Until v88 one
  f spread the whole k 12.12 (= 82.46 g carbohydrate / 680.4 × 100) over
  both, so a big flour line soaked up the crumbs' share.
- **The two shares (`_m52Plan`'s parts loop, NEW arm keyed on
  `identical(figure.read, _parmigiana)`; `_parmigianaDredge`,
  `_parmigianaCrumbs`, `_dryCrumbCarb`).** The budgeted parts on a `Flour,`
  record are the DREDGE: f_d = min(1, 3.55 × raw ÷ 100 ÷ Σ their dredge ×
  carbohydrate) (31.25 × 77.3 % / 680.4 × 100 = 3.5503); every other part is
  the CRUMB layer: f_c = min(1, 11.905 × raw ÷ 100 ÷ Σ w) (81 / 680.4 × 100
  = 11.9048 g dry crumbs per 100 g raw), w = a `Bread,` part's dredge grams
  × its carbohydrate ÷ 0.7198 — a fresh bread brought to SR 174928's dry
  crumbs by the shipped carbohydrate tracer (panko on 174928 itself is its
  own mass) — and a nut or cheese part (the stand-ins inside the crumbs)
  its own dredge grams, BY MASS (read instead by the bread's carbohydrate
  tracer, × 21.55 % ÷ 0.7198, nut-crusted|2's almonds would read
  132.54 g). B (12.12 × raw / 100) and W (1.173 × B) are
  unchanged, so the dips are; `_coatFigure`, `partOn` and CC11's
  after-the-loop k read are unchanged; a group with no part counts
  nothing — no fallback to one f (record-faithful; every corpus 2706442
  coat holds a flour part and a crumb part). Not proposed: the egg (input
  4) as a third group — it is the wash, W.
- **The flag** names both inputs: `approximation (coat: 31.25 g flour and
  81 g dry crumbs per 680.4 g raw chicken breast — USDA FNDDS 2706442
  recipe: flour (Foundation 789890) and dry crumbs (SR 174928) as separate
  inputs, 3.55 g flour carbohydrate and 11.905 g dry crumbs per 100 g raw
  (the dredge sized by the flour, the crumbs by their dry mass; a fresh
  bread brought to dry crumbs by carbohydrate); the record's 18.75 g grated
  Parmesan follows its mozzarella and sauce — a topping, not read; the
  dredge's excess not counted)`, and beside a nut crust `… by
  carbohydrate) (no record for a nut crust; read as FNDDS 2706442's crumb
  crust by mass); the record's …` (every other read's flag unchanged).
Reach vs the v87 rows: exactly the 10 coat parts (grams, basis and energy
only; all `auto`, `discarded`, 0 person rows) — by f_d the four flours:
chicken-kiev|11 73.34 → 39.06 g (268.42 → 142.96 kcal), lighter-chicken-
parmesan|3 45.83 → 29.29, stuffed-chicken-cutlets-with-ham-and-cheddar|10
46.76 → 28.64, nut-crusted-chicken-breasts-with-lemon-and-thyme|9 74.54 →
36.45; by f_c the six crumb parts: kiev|7 bread 93.87 → 147.47 g (four
45.36 g slices, 181.44 g, at f_c 0.8128), stuffed|13 bread 79.81 → 108.15
(at its budget, f_c 0.5961), lighter|0 panko 57.37 → 57.55 and |2 the
Parmesan 18.33 → 18.39, nut-crusted|2 almonds 75.19 → 66.85 (the stand-in)
and |5 panko 31.10 → 27.65. Each recipe's flour carbohydrate is 3.55 × its
raw breast / 100 and its crumbs' dry mass 11.905 × raw / 100 (kiev 850.49
g, lighter 637.86, stuffed 623.69, nut-crusted 793.79). ROW column
−234.72, recipe energy −234.70 (the design's composed ≈ −231.8 was an
estimate; the replay is the figure): kiev 668.42 → 672.70 kcal per serving
(+17.12), lighter 298.43 → 288.50 (−59.58), stuffed 639.11 → 641.38
(+9.08), nut-crusted 566.38 → 516.05 (−201.32); all four stay complete; 0
status / hold changes; the dips (kiev|12 116.88 g, |13 4.03; stuffed|11
88.67; nut-crusted|10 105.19, |11 7.26, |12 0.41; lighter|6 90.69),
sections, notes, calls and buckets identical. Reverted alone, f_d puts back
exactly the four flours and f_c exactly the six crumb parts. Not moved:
every C4 row, easier-fried-chicken|8 (C2's default, no crumb part), the C1
crusts (almond-crusted, breaded-chicken-cutlets, chicken-katsu,
chicken-schnitzel, pork-schnitzel — a flour beside a bread part on
2705975 keeps the one f), eggplant-parmesan|2 |3 |5 (its own arm),
the onion rings.
Calibration (reported, never fitted; v87 → v88 per serving against each
audit's hand count): a6 R05 chicken-kiev +11.7 → +12.4 % (away: its bread
reads the crumbs' own budget on M82's slice), R09 stuffed +5.9 → +6.2 %
(away); a5 R11 nut-crusted +3.3 → −5.9 % (away in size: its hand reads the
almonds at 80 % adherence, judgment), R23 lighter +14.0 → +10.2 %.
Person path (Q7, no users — unguarded): typed grams on a FLOUR line leave
it out of the parts (an `override` row is no plan part), so the crumbs keep
their OWN budget — kiev|11 typed: kiev|7 stays 147.47 g (v87: the whole
12.12 at one f, f = 1, 181.44 g); typed grams on the crumb line leave no
`Bread,` part and keep CC11's C2 3.18 (kiev|7 typed: the flour 34.99 g,
as at v87). GATE-P on base dbb6092 and on v88 (person_sweeps run.sh, 12
shards, fresh snapshot-29 copies): sw5 31,229, sw6 36,916, sw7 1,839, sw8
56,043 combos, 0 divergent, 0 refused, 0 errors on both, calls 0 (sw8's
1,542 combos on the four recipes include the typed 77 g on each flour
line).
Pins: nutrition_v88_test (12 tests — the ten parts and the dips at
the replay's figures with their basis; both budgets by arithmetic on each
recipe's own rows; 3.55, 11.905 and 8.57 from 2706442's inputs and the
fixtures' 789890 / 174928 carbohydrate beside v80's 12.12; this flag read
here character for character; the negatives; the totals; a second compute
writes nothing; the four typed-grams paths — the flour, the crumb line,
nut-crusted's almonds, leaving the panko at f_c = 1, its whole 59.15 g
line, and kiev|10's chicken at 4,000 g, past the 3,086.50 g where 3.55 ×
raw ÷ 100 meets the flour line's 109.57 g carbohydrate, leaving kiev|11 at
f_d = 1, its whole 141.75 g line), each mutant killed by a value pin
(snapshot copy, anchor
count 1): the split dropped (kiev|11 39.06 → 73.34 g), the split on every
read (breaded-chicken-cutlets|2 32.54 → 108.15), a Nuts part by the
bread's carbohydrate tracer, × its carbohydrate ÷ 0.7198 (nut-crusted|2
66.85 → 132.54), a Cheese part by the same tracer (lighter|0 57.55 →
74.87), a fresh bread by its own mass (kiev|7 147.47 →
101.25), W off the counted carbohydrate (kiev|12 116.88 → 116.87), f_c or
f_d back to the one f (kiev|7 → 93.87, kiev|11 → 73.34), the dredge by
mass (kiev|11 → 30.19), the flour test off (→ 53.89), a fallback to the
one f with no flour part (typed kiev|11: kiev|7 → 181.44), the cap dropped
(typed almonds: the panko 59.15 → 94.50), f_d's cap dropped alone
(typed chicken: kiev|11 141.75 → 183.70), the nut clause's "by mass"
dropped, the crumbs at 81 / 680.4 × 100 unrounded (the flag prints
11.904761904761905), matcherVersion 82; the existing suite re-pinned as
equalities (RE-PIN M88): the version literals and three hashes (the
version alone — the base tree with only the bump gives each), the M52 /
M62 / M66 / M70 / M78 / M80 / M82 / M85 coat pins of the ten parts and the
four totals (nutrition_v53, v61,
v65, v69, v78, v80, v84, v87), the flag text, v65's no-crumb lighter
variant (panko 75.94 g, the crumbs' whole budget) and v26's CRUMB COAT cap
shape (each panko 0.20 g, the counts unchanged).
Cost: no new reader — the arm is a pass over the parts the plan already
holds, only under 2706442; `_m52Key` is UNCHANGED (the split reads each
part's description and record and the coated food's grams, all keyed
already). At the v26 cap shapes (0416 padded to 400 lines with its own
panko line under 120 × 10,000-character steps; 0206 likewise with its
flour), base dbb6092 → v88, two runs each, compute / GET / recompute in
ms: CRUMB COAT TRUE (the coat on 2706442 — the split's path) 946, 848 →
874, 870 / 667, 608 → 636, 608 / 601, 588 → 578, 579; CRUMB COAT quiet
820, 796 → 834, 798 / 615, 618 → 621, 621 / 540, 549 → 538, 552; SET-OUT
TRUE (a coat on 2705871 at the one f) 1,061, 913 → 1,062, 901 / 718, 666 →
723, 674 / 568, 588 → 576, 570; SET-OUT quiet 918, 904 → 940, 897 / 690,
668 → 684, 663 / 566, 575 → 579, 573 — every step-index count identical to
base on all 24 paths (v26 pins them exactly), each under the 10 s
backstop.
Deploy note: matcherVersion 83 stales every stamp — run the owner's stale
sweep after the deploy (0 requests). The kcal digest (`tool/replay/
digest.sh`) moves 766,152.39 → 766,098.68, −53.71 (the four recipes' per
serving) — a per-serving sum, not the recipe energy above.

**Matcher v87 (batch M85; matcherVersion 82 — 98 rows + 4 re-solves: 111
rows change record, 98 of them counted, 13 amount-less at 0 g, and the 4
other parts of two coat budgets; prep51 design_v2 §2 M85, a record choice
shipped ALONE; zero requests; server only; replayed on snapshot 29 against
the v86 rows, both orders byte-identical, every moved row and recipe
attributed to one entry by reverting that entry alone, calls 0).** Grated
Parmesan on the block it is grated from, decided under the 2026-10-07
standing authorization:
- **The record.** Every grated-Parmesan line already weighs as block cheese
  grated by hand (grams.dart `_printedHardCheese['grated']` = the corpus's
  "1 ounce Parmesan cheese, grated (½ cup)", the owner's Q6 ruling) and the
  weight lines print a block's weight, but they counted Foundation 325036
  "Cheese, parmesan, grated" (421 kcal, 12.4 g carbohydrate, 1,750 mg
  sodium per 100 g, no portions) — the RETAIL grated product. They now
  count SR 170848 "Cheese, parmesan, hard" (392 kcal, 3.22 g, 1,175 mg; its
  detail cached), index 2 of the same cached `parmesan cheese` answer.
  Unflagged: it is the food. No ruling chose 325036 — this document named
  it only as the Montasio approximation's target (and as the v78 crust
  row's record); docs/MATCHER_HISTORY.md never names it.
- **The rank-as entries ([re-point → `item`]).** `_rankAs` gains
  `parmesan cheese` and `parmesan` → the cached `parmesan cheese` answer
  ranked under `cheese parmesan hard` (the shipped `parmesan cheese rind`
  entry's form): 170848 ranks first at 1.0 (the rows read 0.983333 /
  0.916667 under their own words). A bare `parmesan` line now reads the
  `parmesan cheese` answer (its own holds 170848 at index 2 as well; its
  `candidates_query` is now `parmesan cheese`).
- **The two approximations follow it ("as Parmesan").**
  `approximationRecords['asiago cheese']` and `['montasio or aged asiago
  cheese']` re-point 325036 → 170848; their basis reads "· approximation
  (counted as Cheese, parmesan, hard)". The map alone moves no line (it
  names the record relation the flag reads), so each line's read moves
  with it: Montasio's rank-as words `parmesan cheese` → `cheese parmesan
  hard` (the same answer), and the Asiago REWRITE onto `parmesan cheese`
  became a rank-as read of that answer under the hard block's words — a
  rank-as key is never a rewrite target (nutrition_v21_test's M2: as the
  Asiago rewrite's target, `parmesan cheese` was a `leftAlternative` food
  noun), the v49 Thai chiles' form. An admin's typed search "asiago
  cheese" now asks FDC those words, not `parmesan cheese`; a row's
  `candidates_query` (the answer it reads) is unchanged.
- **The coat budgets re-solve (the grams are keyed by the item, so no
  other row's grams move).** lighter-chicken-parmesan (FNDDS 2706442's
  crust) and eggplant-parmesan (2710050's batter) count a Parmesan PART
  whose carbohydrate falls 12.4 → 3.22 %, so f rises (eggplant 0.243091 →
  0.247443; lighter's parts ×1.0217) and every part moves: lighter |0 panko 56.15 → 57.37 g, |2 the
  Parmesan 17.94 → 18.33 g, |3 flour 44.85 → 45.83 g; eggplant |2 bread
  88.21 → 89.79 g, |3 the Parmesan 13.78 → 14.03 g, |5 flour 34.46 →
  35.07 g (M88, the dredge's own figure, re-derives them on these rows).
Totals vs the v86 rows: 115 rows — 111 change record (cols 4–6; 93 with
energy, 3 with energy and their flag, 2 coat parts with energy and
grams; 13 amount-less "Grated
Parmesan cheese[, for serving]" rows at 0 g either way) and 4 coat parts
(grams); row column −1,232.82 (the record moves −1,247.67, the four parts
+14.85), recipe energy −1,216.45 over 93 recipes; per entry, reverted
alone: `parmesan cheese` 109 rows / 87 recipes −1,035.63 (with both
re-solves and the two sections), `parmesan` 3 / 3 −28.76, Asiago 2 / 2
−20.54, Montasio 1 / 1 (frico|0, 1,909.62 → 1,778.08 kcal) −131.52; 0
status / hold changes, 0 person rows; buckets, notes and calls identical;
two sections move by their Parmesan rows only (fresh-pasta-without-a-
machine's Walnut Cream Sauce 1,899.33 → 1,891.11 kcal, grilled-stuffed-
pork-tenderloin's Porcini and Artichoke Stuffing 380.49 → 372.26). On the
111 rows sodium falls 75,448 → 50,666 mg (−32.8 %) and carbohydrate 534.60
→ 138.85 g (−74.0 %). Not reached: the rind rows (already on 170848) and
"Parmesan or Pecorino Romano cheese" (its item is no key: SR 171249
Romano). Both records publish 208 — no interplay with the energy order
(Q2). No stored person decision names 325036 or 170848 (snapshot 29 holds
none); a stored choice of 325036 would stay.
Calibration (reported, never fitted; this batch / M82–M85 from v82): a5
R21 parmesan-crusted-chicken-cutlets +15.0 → +10.4 % / +15.0 → +10.4 %,
R23 lighter-chicken-parmesan +13.7 → +14.0 % (away: the re-solve adds more
than the Parmesan part saves) / +14.2 → +14.0 %; a3 R06 best-chicken-
parmesan +6.2 → +5.6 % / +6.4 → +5.6 %, R17 deep-dish pizza +4.4 → +4.1 %;
a4 R25 eggplant-parmesan −11.4 → −11.5 % (away) / −10.7 → −11.5 %; a6 R17
ultimate-grilled-pizza −18.0 → −18.6 % (away until Q5) / −17.9 → −18.6 %.
Pins: nutrition_v87_test (9 tests — the four rank-as reads and the two
approximation records; the recorded answer ranking 170848 first at 1.0;
kale-caesar-salad|6 "1 ounce Parmesan cheese, grated (½ cup)" 28.35 g,
111.13 kcal, "from 1 ounce" (v86 119.35 on 325036); the bare `parmesan`
lines (turkey-meatloaf|12, farfalle-with-pesto|6); both Asiago lines and
the Montasio line on 170848 with their flags; the rind converse
(hearty-minestrone|14, 0 g) and one amount-less row; the six coat parts
and eggplant's topping |15; nine recipes' totals; a second compute writes
nothing; the cap shapes), each with its mutant (either key dropped, either
approximation left on 325036, the Asiago rank-as dropped (its own answer:
2705720 "Cheese, Monterey") or its rewrite restored (M2), Montasio's or
Parmesan's words back to `parmesan cheese`, matcherVersion 81); the
existing suite re-pinned as equalities (RE-PIN M85): the Asiago /
Montasio approximation pins (nutrition_c1, v10, v31), the M66–M80 coat
pins of lighter and eggplant (v53, v61, v65, v68, v78, v80, v81, v82),
the rows and totals on 170848 (v61, v65, v68, v69, v71, v73, v78), the
version literals and three hashes (the version alone).
Fixtures: from snapshot 29 the 'curly kale', 'rustic whole-grain bread',
'plain low-fat yogurt', 'vegetable or olive oil', 'red onions' and 'swiss
cheese' answers and SR 170886's detail (the census 550 → 551 / 420).
Cost: no new reader — the rank-as path is the shipped one (one `_rankAs`
lookup per line in `lineSearchFor`, before the rewrite and left-
alternative reads); nothing memoized is touched. At the caps (400
repeated real lines under 0044's steps, the compute and the GET): TRUE
(400 × kale-caesar|6's line) 609 / 542 → 634 / 523 ms, QUIET (400 × "3
tablespoons mayonnaise") 518 / 486 → 476 / 464 ms; counts equal to base,
pinned exactly; backstop 10 s.
Deploy note: matcherVersion 82 stales every stamp — run the owner's stale
sweep after the deploy (0 requests). The kcal digest
(`tool/replay/digest.sh`) moves 766,425.62 → 766,152.39, −273.23 (the 93
recipes' per serving −256.78 and the two sections' −16.45) — a per-serving
sum, not the recipe energy above.

**Matcher v86 (batch M84; matcherVersion 81 — 1 row's grams and 2 recipes'
deductions move, exactly the batch's reach; prep51 design_v2 §2 M84; zero
requests; server only; replayed on snapshot 29 against the v85 rows, both
orders byte-identical, every moved row and recipe attributed to one rule by
reverting that rule alone, calls 0).** Record maps, decided under the
2026-10-07 standing authorization:
- **D3b — two gated braised same-cut pairs (§0.3 the braised-pair doctrine;
  two `braisedKept` entries, nothing else).** The shipped M72 arm (read only
  through `braisedKeptOf`, behind `_defatsLiquid`: the recipe's OWN steps
  print that the fat is not served) gains 167853 "Pork, fresh, spareribs,
  separable lean and fat, raw" → SR 167854 "…, cooked, braised" and 172513
  "Lamb, New Zealand, imported, fore-shank, separable lean and fat, raw" →
  SR 172514 "…, cooked, braised" — USDA's same-cut pairs by the protein
  tracer (cooked × P raw ÷ (P cooked × raw)), the raw record's cached
  DETAIL against the braised record's cached HIT (no detail of either is
  cached): spareribs E 277 → 397, P 15.47 → 29.1, F 23.4 → 30.3, sat 7.529
  → 11.1, mono 8.542 → 13.5, poly 3.953 → 2.73 — energy 0.761918, fat
  0.688373, sat 0.783760, mono 0.840178, poly 0.367141; fore-shank E 183 →
  256, P 20.09 → 30.4, F 11.38 → 15.0, sat 4.621 → 5.56, mono 3.283 → 4.12,
  poly 0.518 → 0.697 — 0.924475, 0.871075, 0.795143, 0.829340, 0.889220.
  Trans stays gross, as M72's: 167854 prints no 605; 172513 → 172514 does
  (0.524 → 0.642, a kept share 0.8097) — the five columns, the stated gap.
  The gate is each recipe's own printed skim: chinese-style-barbecued-
  spareribs S2 "Using wide, shallow spoon, skim fat from surface and
  discard." (|9, 1,446.96 g, 4,008.07 kcal gross) 991.75 → 832.71 /serving
  (×6, −954.24; the batch −954.26); braised-lamb-shanks-with-red-wine-and-
  herbes-de-provence S4 "Skim fat from braising liquid …" (|0, 1,666.95 g,
  3,050.52 kcal) 613.48 → 575.08 (−230.40). The rows stay GROSS (F8) and
  carry no new flag (the brief's "nothing else": unlike 170827's clause,
  the basis does not name the pair — recorded for the owner). Not reached:
  the four other 167853 rows (rosticciana|0, kansas-city-sticky-ribs|5,
  memphis-style-barbecued-spareribs|1, oven-barbecued-spareribs|9) print
  no skim — gross; 172513 holds lamb|0 alone. braised-lamb-shanks|2 (its
  browning fat) is M94's — the combined recipe is pinned there. The
  doctrine's limits stand: a pair of another cooking method for the same
  cut (a roasted pair for a braise — the braised turkey) or a mixed-part
  FNDDS record is a stand-in, an owner question (Q8), never shipped here.
- **E2b — never weigh the bones as the marrow (L058; NEW arm in
  `lineGrams`, [re-point → `item`]).** After `lineGrams`' recipe-gated
  readers (`hostWeighedGiblets`, `stepAmountGrams`) and before any weighing
  of the record (the local `on(food)` closure), a line whose item's head
  is 'bones' (`headNounOf`'s key form, 'bone') on a record whose
  description says "bone marrow" gets NO grams (`_bonesNotMarrow`: no USDA
  or corpus figure gives the marrow share of a bone's weight); every
  matched-record weighing — the compute, the GET, a Confirm, the reach —
  passes there (`_freeGrams`' record-less weigh is not covered: no record,
  no marrow). The GET's basis (`gramBasisFor`, a row with no grams) "the
  line weighs the bones, not the marrow eaten — no figure for the marrow a
  bone holds". simple-pot-au-feu|2 "1½ pounds marrow bones" on SR 169800
  "Caribou, bone marrow, raw (Alaska Native)" (no portions) 680.39 g "from
  1 1/2 pound" → none; held below the gate either way (0.486667, the
  'alaska native' dock): 0 kcal, bucket `check` both ways. A person's
  Confirm of |2 counted 680.39 g × 7.86 = 5,347.87 kcal (+891.31 /serving);
  now 0 — grams a person types still count ("entered by hand"; no one-way
  door). E2c — counting step 3's "add 2 tablespoons" of minced marrow —
  stays DEFERRED: no marrow volume figure exists (169800 prints none; the
  cached 'marrow bones' answer holds only 169800) and reading it is new step
  grammar for one row. Not reached: tortilla-soup|3 (its head is 'bone' too
  — "… or 4 bone-in" — on 2646170, no marrow record: 442.25 g); the census
  — 2 of the corpus's 14,567 lines read the head 'bone', 1 row sits on a
  marrow record.
Totals vs the v85 rows: 1 row (pot-au-feu|2: grams, gram source, basis);
row column +0.00, recipe energy −1,184.64 (2 recipes, per-serving × 6;
the design's −954.25 / −230.39 price the row kcal unrounded); 0 status /
hold / fdc changes; buckets, sections, notes and calls identical. No
calibration recipe of audits 2–6 is reached.
Pins: nutrition_v86_test (12 tests — the four rows on real corpus lines
and the three recipes' totals at the replay's figures (chinese 832.71,
the shanks 575.08, memphis unchanged 1,070.60); a second compute writes
nothing; the ten shares re-derived by the protein tracer from the recorded
records, trans gross; the converse (tortilla-soup|3, real; the owner gate
— verify4 D1, closed by the orchestrator, no fifth round: the REAL
converse on the marrow record itself, 0133|0's bone-in chicken pieces,
head 'chicken', on 169800 — a person's pick from the line's own cached
answer, which holds the record at index 5 — weighed 2267.96 g; mutant:
the head gate reading "not marrow" for 'bone' — null); a marrow
record's line whose head is not the bones ("1½ pounds marrow" and "1½
pounds bone marrow", STATED) weighed 680.39 g, and the singular "1½
pounds marrow bone" (STATED; head 'bone', no 'bones' word) none; a step's
printed amount still reads first (|2 written amount-less "marrow bones"
with S1 "Place beef, 1½ pounds marrow bones, …", STATED: 680.39 g "from
step 1"); the Confirm through the real PUT adds 0.00 /serving and grams
typed add 262.00, "entered by hand"; the cap shapes' counts), each with
its mutant (either key dropped, the skim gate dropped — memphis 1,070.60
→ 832.03 —, a share written 0.76, the arm dropped or moved above the
recipe readers, either gate or the basis dropped, the head gate read as a
substring — "1½ pounds bone marrow" → none — or as the plural word —
"1½ pounds marrow bone" → 680.39 g —, matcherVersion 80); the existing
suite re-pinned as equalities (RE-PIN M84): the `braisedKept` key lists of
nutrition_v69 / v72 / v74, pot-au-feu|2 in nutrition_v39_meat (no grams,
the guard's basis, `check`), the version literals and the three hashes
(the version alone).
Fixtures: the 'st louis style spareribs' answer recorded from snapshot 29
(it holds 167854); the recorded-foods census unchanged (550 / 420).
Cost: no new step reader. D3b reads two more `braisedKept` entries behind
the existing `_defatsLiquid` gate (memoized once per index, no new scan).
E2b is a per-weighing predicate (the description's substring first, the
head only on a marrow record), nothing memoized. At the caps (400 repeated
real lines under 0092's steps, the compute and the GET): TRUE (400 ×
"1½ pounds marrow bones", every row on 169800, none weighed) 240 / 243 →
209 / 177 ms — the guard returns before the skin trip and three readers
only a weighed row reaches (five families fewer); QUIET (400 × tortilla-soup|3's
line on 2646170) 768 / 748 → 801 / 766 ms, counts equal; counts pinned
exactly; backstop 10 s.
Deploy note: matcherVersion 81 stales every stamp — run the owner's stale
sweep after the deploy (0 requests). The kcal digest (`tool/replay/digest.sh`)
moves 766,623.06 → 766,425.62, −197.44 over 2 recipes (chinese −159.04,
the shanks −38.40) — a per-serving sum, not the recipe energy above.

**Matcher v85 (batch M83; matcherVersion 80 — 7 rows move, exactly the 7
the batch names; prep51 design_v2 §2 M83; zero requests; server only;
replayed on snapshot 29 against the v84 rows, both orders byte-identical,
every row attributed to one rule by reverting that rule alone, calls 0).**
Step readers, decided under the 2026-10-07 standing authorization:
- **B1a — "each portion … with <amount>" counts × the serves (guard (ii)'s
  one exception; NEW arm in `_stepAmountsAt`, [re-point → `measurement`]).**
  R-H1's guard (ii) refuses an amount-less line whose head a multiplying
  sentence names. A sentence whose ONLY multiplying word is an "each
  portion|serving|bowl" phrase (`_eachServing`; the rest of the sentence
  matches no `_multiplies` word), and whose prints of the head follow it as
  "with (about) <amount>" (`_servedWith`, a 24-character window before the
  print, never before the phrase), serves that amount per portion: each
  such print counts × the recipe's serves — `Recipe.serves.min`, the lower
  printed number (the per-serving divisor before any person basis); a
  recipe printing no serves refuses as before. A per-serving sentence
  naming the head without its own print refuses. Basis "from step 2: about
  1 teaspoon × 8 portions (no amount on the line)". classic-gazpacho|10
  "Extra-virgin olive oil, for serving" (step 2 "Serve cold, drizzling each
  portion with about 1 teaspoon olive oil"; SERVES 8 TO 10) 0 → 35.76 g on
  748608 (8 × 4.93 mL × its 0.907 g/mL `portion`), +316.16 kcal; per serving
  88.11 → 127.63. Not reached (byte-equal): mulligatawny|16's yogurt ("spoon
  a dollop … into each bowl" prints nothing), ultimate-grilled-pizza|12
  ("Repeat with remaining 2 dough rounds … for each round": B1b, the owner's
  Q5 — not built) and the other R-H1 negatives. The serves are hashed
  (closer 1): `ingredientsHashOf` gains a `serves` term (`Recipe.serves.min`)
  only where a step prints the phrase (`_eachServing`, case-blind on the raw
  steps — 34 corpus recipes and 3 subsections), so every other recipe hashes
  as before; a servings edit stales the stamp and the recompute counts the
  new serves — gazpacho written SERVES 4: |10 17.88 g, "× 4 portions", 107.86
  kcal per label serving under the stored basis 8 (the batch's 4 teaspoons
  over an eighth of it). The label's divisor (the stored basis first) only
  divides the batch, so a person's serving basis (a rebase) leaves the oil
  at the printed count.
- **B4 — a fat joined to the frying oil takes its share of the uptake.**
  `_m52Plan`'s fryer filter drops v71's `!_joinedFryingFat` gate (the
  helper deleted): a fat `_joinsFryingOil` puts in the frying oil (pF R3) is
  a fryer like the oil — its mass share of the SAME uptake (`uptake *
  p.full / oil`; the joined row is `discarded` with kept 0, so the plan
  weighs it at its full grams), flagged as the oil is. `_m50DiscardedBasis`'s
  pF R3 basis ("… counted as 0 g · part of the frying medium (the fried
  food's uptake is counted on the frying oil's row)") is retired. No new
  figure: SR 170698's 6.0 % of the raw potatoes either way.
  classic-french-fries|2 ¼ cup bacon fat (51.60 g) beside 2 quarts peanut
  oil (1,741.29 g — "2 quart ≈ 1893 mL" × 0.92; 2710187 prints no quart)
  → 1.59 g, |1 55.11 → 53.53 g (each fryer rounded alone: 55.12 g in all);
  easier-french-fries|2 beside 6 cups (its 224 g cup, 1,344 g) → 2.52 g, |1
  68.04 → 65.52 g. Row column −0.04 (897 vs 900 kcal/100 g, and the
  classic's +0.01 g rounding), recipe energy +0.00 (per-serving rounding).
  Not reached: chicken-francese-2|8 |9 (no joined fat; 25.94 + 27.08 g of
  the 53.02 g uptake), dakgangjeong|0's sesame oil.
- **B5 — a strained line named by its item's own word (NEW fallback in
  `_strainedOut`, [re-point → `item`]).** When no step names the line's
  head (`_ownMentions` empty), `_strainedOut` reads the mentions of the
  item's own word before the head (`_ownWordOf`: the word-only token before
  the head as the item writes it, `_formsOf` — "porcini" of "dried porcini
  mushrooms"), provided no other line's item carries that word (counted
  once per index, `memo:itemWords`); every later guard — the first mention
  before the strain, named again after it, lifted out, the sheet, another
  vessel, "meanwhile", blended — reads those mentions. braised-turkey|11 "½
  ounce dried porcini mushrooms, rinsed" 14.17 → 0 g `discarded` (−41.96;
  step 2 "Toss the onions, …, porcini, and 2 tablespoons of the melted
  butter in a large roasting pan"; step 5's strain, press and "Discard the
  vegetables"), italian-wedding-soup|3 7.09 → 0 g (−20.98). Basis
  "discarded in cooking — counted as 0 g · approximate (strained out and
  discarded — what it gives the liquid is not counted) · approximate (FDC
  holds no porcini — counted as dried shiitake)" — the M73 stand-in flag
  stays, as a record's flag does on every discarded row (pho|7's anise).
  Not reached: guay-tiew-tom-yum|2 (its own word "green" — "scallions"
  normalizes to "green onions" — is first named in step 3's "scallion
  greens", after the strain: 60.00 g), caldo-de-siete-mares|0 (head
  `pepper`, no strained class).
Totals vs the v84 rows: 7 rows; row column +253.18, recipe energy +253.22
(5 recipes); 0 status (col 9) / hold / fdc changes; gram sources
unmeasured → portion (1) and weight → discarded (2); buckets, sections and
notes identical (a 0 g discarded row is `counted`, as a weighed one).
Calibration (reported, never fitted): audit 6 R12 braised-turkey 579.95 →
575.75 /serving against the hand 518.7 (+11.8 → +11.0 %); R06 / R07 (the
fries) ±0.0; no other calibration recipe.
Pins: nutrition_v85_test (34 tests — the seven rows and seven negatives on
real corpus lines, the replay's figures; the uptake sums; a second compute
writes nothing; the serves hash (a servings edit stales gazpacho, its
recompute 17.88 g; a recipe without the phrase hashes a serves edit as
before; a capitalized "Each portion" hashed; the LOWER serves hashed —
SERVES 6 TO 10 stales gazpacho and reads × 6, 26.82 g, while 8 TO 12
hashes and reads as before (closer 2)); B1a's and B5's gates one by
one on STATED rewrites of gazpacho's step 2 ("with chives and 1 teaspoon"
for `_servedWith`'s end anchor), braised-turkey's porcini line and steps
and the pho's steps 1–2 (its ground beef named "ground meat": the drained
guard reads the own word; closer 2: the line without "dried" read by
"porcini", a bare "mushrooms" not read, and "dried porcini mushrooms or
shiitake mushrooms" read by the word before the LAST head — "shiitake",
named by no step — as `_joinsFryingOil`'s lastIndexOf; closer 3: a
plain print beside the served one counted once — step 1 written "Add 1
teaspoon olive oil" reads 1 + 1 × 8 teaspoons, 40.23 g — "each bowlful"
refused, "porcini" twice on one line read, and step 2's porcini written
"1 cup porcini broth" not read; the owner gate — verify4's four LOW pin
gaps, closed by the orchestrator, no fifth round: a later multiplying
sentence after the served one ("Repeat with the remaining olive oil.")
refused, guard (ii) walking past the served sentence to it; every print
in the served sentence must follow "with" — "and adding 1 teaspoon olive
oil" refuses the sentence, "and finishing with 1 teaspoon olive oil"
counts both × 8, 71.53 g; the phrase printed twice refused (ruled: a
second phrase is another multiplier — no corpus sentence prints it
twice); a letter before the phrase ("the peach portion") refused,
`_eachServing`'s leading word boundary), each with its mutant; the cap
shapes' counts); the existing suite re-pinned as equalities
(RE-PIN M83): nutrition_v71_test's R-H1 negatives (gazpacho|10 leaves), its
corpus census (4 → 5 amount-less lines read), R-E5's porcini "stated gap"
(closed), the pF R3 rows and the duck-fat case; the fries' uptake rows of
nutrition_v53 / v60 / v66 / v69 (and v60's flag counts +2); the porcini
rows of nutrition_v73 and the per-serving pins of v59 / v71 / v73; the
version literals and the three hashes (the version alone).
Cost: two readers. B1a's per-serving phrase is read once per multiplying
sentence per index (`memo:stepAmounts`), each line's prints grouped by
sentence once, its "with" test a bounded window per print; guard (ii) walks
the shorter of the head's naming and the multiplying sentences (a
per-serving sentence no longer ends the walk). B5 reads the own word's
mentions once per word (`memo:foodNaming`) and the item words once per
index. At the caps (loop level, every line's three readers): B1a TRUE (400
distinct amount-less heads under 120 × 10,000 characters of "Serve,
drizzling each portion with about 1 teaspoon <head>.") 165 / 124 → 219 /
156 ms (the 400 lines weighed, no base equivalent), QUIET ("Serve the
remaining soup, …") 104 / 110 → 110 / 108 ms; B5 TRUE (400 own words each
tossed in before the strain) 37 / 29 → 43 / 33 ms, QUIET (400 copies of
the porcini line) 28 / 25 → 27 / 27 ms; counts pinned exactly (base's but
each reader's own memo); backstop 10 s. The `serves` hash term is one
case-blind scan of the raw steps per hash (no memo, no count): at the caps
(120 × 10,000 characters) 10.76 / 10.83 → 11.58 / 11.47 ms a hash where no
step prints the phrase, equal where one does (the scan stops at it).
Deploy note: matcherVersion 80 stales every stamp — run the owner's stale
sweep after the deploy (0 requests). The kcal digest (`tool/replay/digest.sh`)
moves 766,591.23 → 766,623.06, +31.83 over 5 rows (gazpacho +39.52,
braised-turkey −4.20, italian-wedding-soup −3.49, the fries ±0.01) — a
per-serving sum, not the recipe energy above.

**Matcher v84 (batch M82; matcherVersion 79 — 614 rows move: 569 of the
572 the batch names, 24 consequences of its rules on their own lines
beyond the brief's enumerated list (accepted, ruling4), 21 routed parents; prep51 design_v2 §2 M82; zero requests; server
only; replayed on snapshot 29 against the v82 rows, both orders
byte-identical, every row attributed to one rule by reverting that rule
alone, calls 0).** Pieces and densities, decided under the 2026-10-07
standing authorization:
- **C1 — the white sandwich-bread slice at ATK's prints.** `_pieceWeights`
  gains `('white sandwich bread', 45.36)` (Old-Fashioned Stuffed Turkey's
  "1½ pounds (about 15 slices) high-quality white sandwich bread") and
  `('hearty white sandwich bread', 40.5)` (Apple-Blackberry Betty's "10
  ounces (about 7 slices)"), both flagged in `_approximatePieces` — the CP9
  Q6 corpus-print class (v51's thick-cut bacon). SR 174924 publishes
  'slice' 29 / 25 g, 'slice, large' 30 g, 'slice, thin' 20 g, none the
  table's old 28 g. The unsourced `('sandwich bread', 28)` is deleted
  (ruling4): a loaf no print names weighs on its record's own slice —
  french-toast-casserole|5 "10 slices potato sandwich bread, halved
  diagonally" on SR 167943 "Bread, potato" 'slice' 32 g, 280.00 → 320.00 g
  "10 slice · USDA portion" (+106.40 kcal), as individual-summer-berry-
  puddings|6 reads the same record at v82 (384.00 g "12 slice · USDA
  portion") — one row beyond the brief, accepted (ruling4: the record's own
  FDC portion over a kitchen figure, CP9 Q6 / §0.1). 29 piece rows
  +3,811.80 kcal; 13 coat parts in 6 recipes re-solve with C5a (+51.42: a
  heavier slice lowers the coat's f).
  Unchanged: the cup-printed croutons (carrot-ginger-soup §0|2 70.00 g "2
  cup · USDA portion"), pork-schnitzel|0's cups, the weight rows.
- **C1b — "crusts removed" (NEW arm in `lineGrams`, a field read
  [re-point → `prep`]).** A slice of SR 174924 read as a piece whose parsed
  `prep` matches `\bcrusts? removed\b` keeps the record's own 'slice crust
  not eaten' 12 g of its 'slice' 29 g: basis "… × 12/29 crusts removed
  (USDA: 'slice crust not eaten' 12 g of 'slice' 29 g)". 10 rows, with C1
  −585.14 against v82 (C1b −1,386.82 against C1 alone); creamless-creamy-
  tomato-soup|6 84.00 → 56.31 g. A cup-printed slice line (pork-schnitzel|0,
  its own cups) and another record keep the whole slice.
- **C2 — the poblano at the corpus print.** `('poblano', 45)` (unsourced)
  → 129.6 g (Skillet Chicken Fajitas' "1 pound (3 to 4) poblano chiles" at
  the count's midpoint, as v37 Z9 reads a range), flagged "ATK: 1 pound
  poblano chiles, as bought, ≈ 3 to 4" — gross, on a seeded record. 5 rows
  +402.56 (the literal the basis prints: 4 × 129.6 = 518.40 g on
  roasted-poblano-and-black-bean-enchiladas|1; 453.59 / 3.5 gives 518.39).
- **C3a — a counted garlic clove reads its printed volume (NEW arm in
  `lineGrams`).** On a `volumeSiblings` record (1104647 → SR 169230) a line
  whose own reading is a PIECE, whose item names the clove, and whose
  amounts carry a volume, with no second count in the comma clause before
  its paren [re-point → `measurement`/`item`], weighs that volume on the
  sibling: pasta-caprese|2 "1 small garlic clove, … (about ½ teaspoon)" 3.00
  → 1.40 g, "1/2 teaspoon · USDA portion of "Garlic, raw"". Kept: a clove
  unit ("3 cloves garlic", 9.00 g), a second count ("5 … cloves, 3 peeled …
  and 2 minced (about 2 teaspoons)", 15.00 g), onions and every other
  sibling (C3b closed), a printed weight (the piece gate). 168 rows −180.32.
  With no 169230 cached the clove keeps its count; `gramsFor`'s sibling
  fetch gains the same predicate, so a compute fetches 169230 once for such
  a line (snapshot 29 caches it: 0 requests; a 404 is cached nowhere, so a
  superseded 169230 is asked once per pass, as base's sibling fetch).
- **C5a — the corpus's cup of flour on the portion-less records.**
  `_densities` 'all-purpose flour' / 'flour' 5 × 28.3495 / 236.588 =
  0.5991 (199 of 203 prints: 5 oz a cup) and 'whole-wheat flour' 0.6590
  (5½ oz), each `recordFirst` in `_approximateDensities` (the Z5 form;
  789890 / 790085 publish only a 30 g racc), flagged "ATK: 1 cup
  all-purpose flour = 5 ounces" / "… whole-wheat flour = 5½ ounces". 103
  density and coat rows +1,622.09 (wicked-good-boston-cream-pie|4 "¼ cup
  all-purpose flour" 30.16 → 35.44 g; the exact quotient, 0.599132 — 0.5991
  rounded gives 35.43). RULE B's medium threshold reads it too: flour's ¼
  cup is 35.4 g (was 30.2). Weight-printed flour lines keep their weight.
  The brief's C5a figure, ROW +1,643.61, is pC's C5a-alone model over its
  116 rows (these 103 and the 13 coat parts shared with C1); the replay with
  C1 reverted gives +1,660.96 over them, +17.35: pC's model put
  pork-schnitzel-breaded-pork-cutlets|1 "½ cup unbleached all-purpose
  flour" at 13.44 g (49.18 kcal) and its bread |0 at 37.16 g (98.85), the
  replay weighs 18.57 / 36.69 g (67.97 / 97.60: +18.79, −1.25) — the
  figures of pC's own joint model (SHIP_all), so the REACH decomposition
  below is unaffected — and 100 more rows differ by cents (−0.11).
- **C6a — an extra-virgin olive oil at its record's own volume figure.**
  `_volumeAliases` gains 'milliliter' and the NEW key `('virgin olive oil',
  0.92)` is `recordFirst` with no flag: 748608 "Oil, olive, extra virgin"
  weighs by its '100 milliliter' 90.7 g (eggplant-parmesan|9 "2 tablespoons
  extra-virgin olive oil" 27.21 → 26.82 g, "2 tablespoon · USDA portion ·
  nutrients of "Oil, olive, salad or cooking""). 'oil' itself stays
  table-first (ruling4): FNDDS spoon portions are rounded to the gram
  (2710180's '1 tablespoon' 14 g = 0.947 g/mL, 3 % off an oil's 0.92), so
  record-first standing goes to the record whose own volume figure is a
  precise per-100-mL portion (748608 '100 milliliter' 90.7 g), not to every
  oil record. 241 rows −1,421.16 (240 density rows −1,420.03;
  pollo-en-pepitoria…|2's "2 teaspoons kept" 9.07 → 8.94). The M77 section
  (BELOW — older sections follow) describes the v77 basis `1 tablespoon ≈
  15 mL · nutrients of "Oil, olive, salad or cooking"`; from v84 the 240
  measured 748608 rows are `portion` and print `… · USDA portion · nutrients
  of …` (0 of 240 carry "≈ N mL"). NOT RULED HERE (recorded for the owner):
  a rounded spoon portion as the density for a non-matching unit — 'oil'
  record-first moves 145 rows on other oil records, ROW +308.28 (2710180
  92, 2710190 25, 2710186 15, 2710187 7, 172336 2, four more 1 each) — and
  'oil' matching "oil-cured black olives": roasted-fennel §"Crunchy
  Oil-Cured Olives"|0 27.21 g at 0.92 for chopped olives against the olive
  record's own '1 cup' 135 g → 16.88 (2710090; the variant replayed on
  this tree, nothing shipped).
- **C6b — the drained oil-packed white tuna (design Q7 (ii) (b)).**
  `drainedCanGrams` reads `_drainedCanShares` (NEW): SR 175157, which
  publishes no sized drained portion, at SR 173708's 'can (12.5 oz),
  drained' 321 g of 354.37 g (0.906), flagged "approximate (drained weight:
  FDC's oil-packed light tuna can, 321 g of 12.5 oz)":
  pan-bagnat-provencal-tuna-sandwich|14 368.54 → 333.84 g, −64.55.
REACH (the replay): ROW +4,023.73, RECIPE ENERGY +3,789.78 over 424
recipes (the brief's ≈ +3,602.42 over ≈ 418; +187.36 = the consequence
rows below +184.41, K-8's three unmoved rows +4.26 — the brief's model
counts them at −4.26 —, the planner's models elsewhere −1.31). The 569 named rows
+3,530.30 against the brief's +3,527.32 for its 572: +2.98 = +4.26 the
three named rows the replay does not move (the brief's model: −1.24,
−1.63, −1.38), −1.13 C6a's 240 density rows (−1,420.03 against pC's
−1,418.90: pC's grams sit a cent off the replay's on 66 rows, −3.54, and
its model scales v82's 2-dp row energies, +2.41), −0.17 C5a (its 103 rows
−0.21 — the exact quotient 0.599132 against pC's 0.5991 puts 31 rows a
cent up, +1.08, the scaled 2-dp energies −1.29 — and the 13 coat rows it
shares with C1 +0.04, pC's coat model), −0.04 C3a (row-kcal rounding;
its 168 rows weigh pC's grams exactly), +0.04 C1 alone, C1 + C1b and C2
(+0.02, +0.01, +0.01; C2's the literal 129.6 the basis prints) and +0.02 the brief's own
rounding (its row model re-summed: +3,527.34). Not moved though named: the
three bacon-pan oils (pasta-with-tomato-bacon-and-onion|0 9.93 g,
pasta-alla-gricia…|1 13.08, salade-lyonnaise|1 11.07): rule B1's split
reads the pan's oil with no food (`_panOilGrams`, the one figure the bacon
row reads too), so they stay; K-8's ≈ −5.39 is pollo-en-pepitoria…|2's
row alone, −1.13 (80.17 → 79.04 kcal; its recipe −1.16) — accepted
(ruling4: a record-bound pan oil is a new cross-row read that re-splits
the bacon rows; not this batch, no follow-up). Consequences on the rules'
own lines beyond the brief's enumerated list, accepted (ruling4) (24 rows,
+183.27): french-toast-casserole|5 (C1, above, +106.40); the five
other-shape flour rows the brief bounds and their
batter / dip co-parts (fish-and-chips|2 89.12 → 93.89 g with |3 |4 |5 |8
|10, crispy-fish-sandwiches…|6 with |7 |9 |10, oven-fried-onion-rings|0
60.33 → 70.87, chicken-francese-2|5, best-chicken-parmesan|13 with |12);
the volume "plus" part of three weight-printed flour lines
(blueberry-boy-bait|0, congyoubing|7, french-apple-cake|3); a 26th coat
row, maryland-crab-cakes|8 30.16 → 33.62 (the ¼ cup's carbohydrate now
above the budget: f 0.949); falafel|11's uptake on the heavier mix 85.55 →
86.69; crispy-pan-fried-pork-chops|3 (a clove in a dip) 0.58 → 0.54 with its
buttermilk |1; chicken-francese-2's frying oils, which share the food's
uptake by their full grams — |8 26.13 → 25.94, |9 26.89 → 27.08, |8 + |9
= 53.02 g at v82 and v84 (the uptake's mass, the brief's "must NOT move",
pinned; only the split moves). 10 recipes move by those alone (+173.02). Routed parents (21,
+310.16) carry their moved sections and whole-recipe children (K-5's
guacamole hop among them: cheesy-nachos…|6 −0.29). Statuses, holds,
buckets and notes unmoved; 27 section lines move by their totals; a
recompute writes nothing. Two moved rows are stored `overridden` on
snapshot 29 (acquacotta…|4 |17: a pick of 748608, its grams derived — none
typed, no decision row): C6a's grams only, the pick kept.
Order rows (§0.5): the coat budgets M85 and M88 re-derive on these rows
(chicken-kiev|7 77.68 → 93.87 g, |11 83.69 → 73.34, breaded-chicken-
cutlets|3 29.01 → 25.43, dakgangjeong…|8 40.36 → 41.53 and |9 8.01 → 7.02).
Calibration (reported, never fitted): audit 6 R05 +11.4 → +11.7 %, R09
+5.8 → +5.9, R16 −1.0 → +0.2, R24 +0.3 → −0.7, R25 +0.6 → 0.0, R03
oven-fried-onion-rings +54.6 → +57.4 % (away); audit 4 R10 falafel +5.3 →
+6.6 % (away; the design's +6.1 before the uptake); audit 3 R10 +5.6 →
+6.6 % (away), R16 −0.6 → +1.3; audit 2 R08 salade-lyonnaise −8.8 %
(unmoved); french-toast-casserole is in no calibration set (audits 2–6).
Pins: nutrition_v84_test (25 tests — the three "plus" parts above among them; the replay's figures, every converse;
one mutant per rule and per gate, each killed by a value pin — the plain
'flour' mark's on a synthesized line, stated: every corpus line that key
reads prints its weight; SR 167943
and 175158 recorded from snapshot 29 — the recorded-foods census 548 → 550
/ 418 → 420; chicken-francese-2's |8 + |9 sum; french-toast-casserole|5
on 167943's slice, the plain key restored at 28 its mutant); the existing
suite re-pinned as equalities (RE-PIN M82; nutrition_engine_test's soft
sandwich bread: 6 slices 168 g → the white loaf 272.16 g, the plain item
none);
the contract goldens nutrition_matches_section_own and nutrition_section_own
re-captured (the legacy-v0 EVOO line 40.81 → 40.23 g).
Cost: no step reader; C1b one regex test of the parsed prep on a 174924
piece, C3a one regex of the item and one linear scan of the raw line on a
sibling-record piece. At the caps (400 × a real clove line under the
recipe's own steps) the compute and the GET count base's families exactly;
the TRUE shape (0327|2) measures compute 736 / 693 → 766 / 792 ms, GET 420 /
421 → 457 / 476 ms (each line weighed on the sibling; one more detail
fetched, 169230), the QUIET shape (0491|2) 621 / 634 → 618 / 627 ms and 412
/ 413 → 417 / 422 ms; backstop 10 s.
Deploy note: matcherVersion 79 stales every stamp — run the owner's stale
sweep after the deploy (0 requests on a cache that holds 169230). The kcal
digest (`tool/replay/digest.sh`: Σ calories_per_serving over
recipe_nutrition, sections included) moves 765,642.77 → 766,591.23,
+948.46 over 451 rows (424 recipes, 27 sections) — a per-serving sum, not
the recipe energy above (+3,789.78, kcal per serving × servings over the
recipes).

**Matcher v83 (batch M81; matcherVersion 78 — no corpus row moves; the
person paths and pins of prep51 design_v2 §2 M81; zero requests; server
only; replayed on snapshot 29, byte-identical to v82 on both orders, each
rule alone too).** Decided under the 2026-10-07 standing authorization:
- **F2 — the apply path resolves the parts (ledger Q13).**
  `applyDecisionToOthers` resolves each target's Rule B1 part records
  (`_resolveParts`, after `withParts`, before the line-hold test) where the
  row's food is, as the compute and the PUT's own line do; a provider
  failure there takes the weigh failure's arm (`unavailable`: the target
  stays the engine's row, its totals stamped stale). The apply's totals
  still never fetch (RULE A: `only:` the decided food). Before, a part
  record no cache held — 168322 "Pork, cured, bacon, pre-sliced, cooked,
  pan-fried", which snapshot 29 holds only as a hit of the 'thin-sliced
  cooked deli ham' answer — was never fetched, so every reached target with
  B1 parts was stamped `underived`, its bacon row out of the label until the
  sweep: chili-con-carne|7 "8 ounces bacon …" picked 167869 and then 168277,
  each apply_to_all, moved 9 labels on snapshot 29 (−4,816.60 kcal a batch,
  27 recipes reached, 0 requests): 8 recipes underived (−3,768.91;
  meatloaf-with-brown-sugarketchup-glaze 575.11 → 524.02 per serving,
  grilled-bacon-wrapped-scallops 350.84 → 221.11) and, through its section
  "Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions" (|0 on
  168277, parts 168322 149.69 g + 172345 38.70 g: the section underived at
  4,417.36 kcal, not 5,465.05), classic-roast-stuffed-turkey 1,258.02 →
  1,153.25 per serving (−1,047.69; closer 1, verify1 D3). Now each reads
  fresh at its v82 figure, equal to a full compute, and 168322 is asked
  once for every target of the apply. Pins (nutrition_v83_test, the
  fixtures; the deli-ham answer removed — a fresh deployment, STATED):
  those figures and the requests; an outage on 168322 leaves both targets
  `unavailable` (never `failed`, never written) and `underived`.
- **F3 — the skin, shell and can inverses gate on the forward move's term
  (ledger Q14).** `decisionRecordOf` takes the row's gram source, and its
  three table loops (`_skinlessRecords`, `_shellRecords`,
  `cannedBeanLiquids`) map a decision back to the record bought only for a
  `weight` row — the term `_skinOffFood` moves by. The GET's offer reads
  the source of the row it shows (an auto row's stored one, a decided
  row's derived one); the PUT the derived row's (a pick clears the
  edited row's: a pick of 171052 on grilled-lemon-chicken-with-rosemary|0
  still decides 171447). Before, oven-fried-chicken|6 "4 whole chicken
  legs, … skin removed" (173619, meat only, `piece` 1,060.00 g — a piece
  weight never moves) decided 172378 (meat and skin) on a Confirm, and the
  decision carried back landed on 172378 at 1,376.00 g: 958.56 kcal per
  serving, +430.63. Now it decides 173619 and lands on 173619 at 1,060.00
  g, 527.93. Every `weight` row still round-trips: grilled-lemon-chicken-
  with-rosemary|0 decides 171447 and lands on 171052 at 738.75 g, 312.17
  (pinned with each loop's own gate on its real row: 171052, 0294's
  mussels 174216, 0340's chickpeas 175206). One-way door (person path, Q7 —
  no users, unguarded): 0150|6's Confirm stores 173619, not 172378. Typed
  grams (`override`) are no weigh of their own (closer 1, verify1 D1): the
  term is then the line's own weigh on the row's food (`lineGrams` on the
  food the caller already holds, without the recipe's step readers — no
  read, no request; RULE C, closer 4, verify4 D1), so a Confirm, or a
  pick of 171052, on 0637|0 with grams typed still decides 171447 (before
  closer 1 it decided 171052, which perfect-roast-chicken|2 — skin eaten —
  then carried at 738.75 g, 604.23 per serving, not 171447 at 1,035.00 g,
  1,277.30); 0150|6 Confirmed with grams typed still decides 173619. On
  every corpus line a table gates, the step readers change no `weight`
  term (147 line × record cases on snapshot 29, 0 differ); an amount-less
  line whose steps print its weight (`stepAmountGrams`,
  `hostWeighedGiblets`) reads "not weighed" there, so its inverse does not
  fire when typed over — no corpus line does (stated, not guarded: Q7).
  Pinned with the GET's offer equal to the PUT's write on a typed row, on
  a `piece` row (closer 5, verify5 D1 — STATED: 0150 stored a second time,
  0150|6 being its key's one corpus row: the offer names 173619, offered
  (0, 0) and written (0, 0); before, 172378 offered and written (1, 1),
  the copy moved to 1,376.00 g; a GET reading every row as `weight`
  offers (1, 1) and writes (0, 0)), and at the editor caps (the cost note).
- **F5c — a main recipe's yield oil is an input.** `ingredientsHashOf`
  hashes a MAIN recipe's `servings` where `_yieldOil` matches it
  (`yield_oil`): `_yieldOilEaten` reads it for a main recipe as for a
  section, whose yield was hashed already. No corpus main recipe prints a
  yield oil (0053's "Fried Shallots and Fried Shallot Oil" is a section),
  so no stored stamp moves. Pin (STATED synthesized, the recorded
  exception): that section saved as a main recipe, its "ABOUT 1¾ CUPS
  FRIED SHALLOT OIL" edited to "ABOUT 1½ …", reads stale; the recompute
  counts 112.00 g of its oil, not 56.00. The host gate is pinned on the
  real section: its hash is the one every matcherVersion-78 library stores
  (the gate dropped would stale it on every deployment).
- **A5 — `_dipsOf`'s two order sites pinned (the U1 gap; no code
  change).** STATED synthesized on nutrition_v80_test's fried copy of 0315,
  real sentences moved between real recipes: with 0198 S2's buttermilk dip
  before 0315 S1's whisk, the salt, pepper and cayenne read 0315 S2's later
  dip and the egg and buttermilk 0198's; with 0420 S4's egg dip after 0315
  S2's, every dip line reads the earlier, 0315's; with 0198 S2's dip before
  0315 S1's beat of the egg and buttermilk and 0420 S4's egg dip right
  after it, the egg and buttermilk read 0420's — the earlier of the two
  bases' dips, though the buttermilk base is read first. Each site's
  mutant dies.
- **A6 — comment only:** `_mixVerb`'s unterminated prefix is deliberate
  (0758's "milk mixture"; `_dipsOf` reads the whole word).
GATE-P (the person sweeps, apps/server/tool/replay/person_sweeps; base
4325a3d / v83): sw5 31,141, sw6 36,828, sw7 1,833 and sw8 55,893 combos, 0
divergent on both; NEW sw9 (the cold-cache apply: every line of the 8 keys
holding a B1 row — the child sections' lines with the recipes' — its key's
part records no library row counts evicted from both caches — 168322 for
the four bacon keys) 54 of 130 divergent at base (every line of a key
whose rows read 168322: bacon 28 — two of them section lines; 0158's
stuffing section an underived target of the other 27 — pancetta 18,
pancetta or bacon 2, thick-cut bacon 6), 0 of 130 (those 54 ask 168322
once); NEW sw10 (a Confirm, the row removed and the decision carried back,
on every row whose ungated inverse names another record; each row also
Confirmed with its own grams typed, which must decide what the bare Confirm
decides) 155 of 156 round-trip at base, bare and typed; 156 of 156 bare and
125 of 156 typed before closer 1 (the 31 gated `weight` rows); 156 of 156
both.
Cost: no new step reader or regex; F2 adds one request per part record no
cache holds, per apply (count-pinned: one for two targets); F3 one string
compare per inverse, and one `lineGrams` of the line — no step reader — on
a typed row a table names: at the editor caps (STATED synthesized: 0637|0's
line × 400, typed on 171052, under 120 steps × 10,000 characters of a real
0637 sentence; the counts pinned exactly, equal to 4325a3d's) the TRUE
shape's GET (the skin trip fires) measures 4.42 / 4.43 s on 4325a3d and
4.47 / 4.34 s on v83 (two runs each; the QUIET shape 0.34 / 0.34 s and
0.37 / 0.36 s; the backstop 10 s) — with the step readers it measured
12.5 s (closer 4, verify4 D1); F5c one `_yieldOil` test per hash of a main
recipe.
Deploy note: no matcherVersion bump; the new hash term reads no stored
recipe (none prints a main-recipe yield oil) — nothing stales, no sweep;
the kcal digest does not move.

**Review Run 067/068 fixes (matcher v82; matcherVersion 78 — no corpus row
moves; the catch-up review of v55–v62, both fleets; zero requests; server
only; replayed on snapshot 29, byte-identical to v81).** Each restores an
invariant the dual-fleet review found broken:
- **F1 — the strain-the-liquid guard reads its tail once.** v56's guard
  ("no sentence from the strain to the end names solids, vegetables, a
  blender, a food processor or a purée") is "the LAST such sentence comes
  before the strain": that last sentence is found once per index (counted
  `lastMatching`), each guarded strain answered by position — the tail was
  rebuilt and rescanned per guarded strain (O(S²): 615 s for one
  `discardedMediumOf` at the editor caps, on the compute, the GET and the
  PUT). The strain sentence itself still counts as its own tail ("strain
  the liquid … over the vegetables" is guarded).
- **F2 — the reserved frying oil's heat is read once.** v58's "a later
  sentence heats the reserved oil" is "the LAST heating sentence comes after
  the reserve sentence", found once per fat's owners derivation
  (`lastMatching`): every later sentence was rebuilt per "reserve N oil"
  sentence (110 s at the caps). A reserve sentence that heats the oil
  itself is no reuse, as before.
- **F3 — the rinsed plus part is read once per amount and head.**
  `_rinsedOff` (v58 F1) is memoised per index on the plus part's lead
  amount and the fat (`memo:rinsedOff`), each step's last drain and last
  rinse sentence found once (`memo:rinseTails`): it ran per line, twice
  (engineOutcome and the GET's basis), rescanning the rest of the step per
  toss sentence (249–500 s for 400 plus-part oils). A toss sentence that
  drains and rinses itself rinses nothing, as before.
- **F4 — a dip sentence is never a mixing sentence.** `_dipsOf` reads a
  mixing sentence by the verb as a word (`_mixesWord`: never "mixture") and
  never a dip sentence: a second egg dip read the first ("dip each steak
  into the egg mixture …") as the mix, claimed the coated steaks as a dip
  line and sized them `discarded` (0304 + one repeated dip: 850.49 → 64.78
  g, the compute and the recompute planning apart). No corpus recipe holds
  two first-arm dip sentences (no corpus row moves).
- **F5 — a dip is never off C5's B.** The C5 batter budget's subtraction of
  the counted flour and starch, and `_m52Key`'s `offB`, skip a dip line: E-w
  writes it `discarded`, so it came off B in its engine form on the compute
  and not on the recompute (0255 + a tapioca-starch egg dip: the flour
  67.71 g on the compute, 89.12 on the recompute; now 89.12 on both).
- **F6 — the coated food is never a coat part.** The plan's coated food —
  a row on a meat record, or one on a coated-vegetable record (Eggplant,
  Onions) whose head a coating sentence names with a coat (the row the
  coated-vegetable route reads, whatever the shape) — mixed into a coat
  (0279's "Transfer shrimp to bowl, add 3 tablespoons cornstarch … and toss
  until well combined") is decided as any counted food (`derivedFor` never
  routes it to the plan) and the plan's held coat never holds it: a
  Confirm of the shrimp stored 0 g `discarded` for good (1,465.37 → 410.40
  kcal), a pick held it `coating`; on a coat held with no budget the engine
  held the shrimp itself. The same for the eggplant (closer 1): 0407 with
  "Toss the eggplant slices with the flour until well combined." in S3 (a
  stated copy; the engine's rows unchanged) stored 0 g on a Confirm (2,735.29
  → 1,938.5 kcal) and held it on a pick; now 907.18 g counted. A vegetable no
  coating sentence names (a minced onion stirred into the flour) and a
  seasoning named in the coating sentence (paprika) stay parts.
- **F7 — a Confirm the plan stops covering follows its food.** The v70 F9
  revert in `recomputeTotals` covers a person's CONFIRM (no grams typed) in
  the plan's form too: re-read as the compute derives it with no plan entry
  (`engineOutcome` decided; a held medium resolves to its eaten part or 0 g
  poured away) — a confirmed batter, dip, coat, uptake or product-fry row
  kept the old plan's grams through every PUT once its coated or fried food
  was skipped or picked (0511's confirmed egg 23.45 g, a compute 50.00;
  1194's oil 99.34, a compute 0.00). A person's PUT, a recompute and a full
  compute now total the same rows: confirm every discarded or coating row of
  the 241 corpus recipes holding one, then skip / pick / type / confirm each
  of the three largest counted foods, both orders — 5,448 cases, 53
  divergent at base, 0. Closer 4 (verify4 D1): a person's PICK of a plan row
  too (a dip or a coat's mixture part picked on a record, no grams typed) —
  derived on the PUT as `derivedFor` derives it: held `coating`, no grams,
  while its coat has no budget (M62 H: the hold a pick keeps), the line's
  own weight (`engineOutcome` decided, RULE A by hold kind — one block,
  `_byHoldKind`, read by both) once the coated food is back. The plan never
  weighs a pick, so the PUT kept the pick's grams once the food was skipped
  (0114's egg picked, the cutlets skipped: 100.00 g, 274.00 kcal, where the
  GET and a compute held it, 126.00; 0255's cornstarch 1,749.54 against
  1,506.16) and kept the hold after an un-skip. The hold is read from the
  plan's own entry (no extra plan); the line test reads a picked coat line's
  mixing sentences once each (`mixTests`, count-pinned). The sweep
  (verify4's, extended): every M52 row of the 268 recipes holding one
  confirmed, picked on its own record, or all confirmed × the two largest
  counted foods × skip / un-skip / pick / typed / confirm × the plan row
  first or the food first — 28,310 cases, 196 divergent at base, 41 before
  this closer (every one a pick, then the food skipped), 0; and the food
  skipped, the plan row decided, the food un-skipped — 2,831 cases, 41 picks
  divergent at base and before this closer, 0. Closer 5 (verify5 D1): a
  coat's mixture part CONFIRMED while H held it is stored resolved (0 g
  poured away, no hold); once the food was back the plan had no entry for it
  and the confirm arm read a part only while held `coating`, so the 0 g
  stood through every PUT (the food skipped, every M52 row confirmed, the
  food un-skipped: 0254's eggs, mayonnaise and seasonings 0 g, 943.56 kcal
  stored against a compute's 1,382.58; 0149's buttermilk 0 against 305.00 g,
  2,550.27 against 2,721.73). The revert now reads a row on a coat-mixture
  line (`_coatOfPart`) in either plan form — budgeted or resolved
  (`discarded`, no hold) as well as held `coating`, the v70 F9 rule's own
  scope; an engine part read only while held before — so a Confirm H
  resolved follows its food; the coated food's row too (`derivedFor` decides
  it as any counted food, the same derivation: a 0 g a base F6 Confirm
  stored heals on the next PUT). Order C (the food skipped, every plan row
  decided, the food un-skipped): 2,831 cases, 46 divergent at base, 5 before
  this closer (the five confirm-all), 0; verify5's whole sweep (36,828
  cases, with every M52 row picked) 0; a person's skip, typed grams, or skip
  and un-skip of each plan row itself (1,833) 0.
- **F8 — confirmed coat parts key as dips.** `_m52Key` and `_m52KeysAlike`
  read a coat's mixture part on its line, record and hold, never its medium
  bit (a part has no medium; a Confirm keyed `discarded` against its stored
  engine source): one plan per confirmed part on the GET and the compute
  (0149's five parts confirmed: the GET 6 → 1 plans, a compute 6 → 2).
- **F9 — the fried cauliflower's batter reads each row once a plan.** C, the
  carbohydrate of the group's counted rows, reads each row's record once per
  plan, never once per fried cauliflower row (the GET and the PUT read
  [knownFood]: 161,214 reads and 9.9 s at 399 cauliflower lines; now 1,219
  reads and 0.46 s).
- **F10 — a line-conditioned move never travels as the decision.**
  `decisionRecordOf` maps every move of the ranked path back to the record
  bought, the last move first: the step-printed trim (173128 → the 0" flat
  168743, M74), a `trimDepthRecords` entry the line prints (v55 R3, Q7's
  "fat caps removed", the whole brisket, the flat's ¼ inch, v79's
  "trimmed" racks), then R2's lean-only top of the line's own cached answer
  (`leanAndFatSibling`; read once per line text and record while no FDC
  cache write lands, `leanOnlyReads`) — after the skin, shell and can maps.
  Each trim or R2 reverse stands only where the line's own moves land a
  decision on the record bought back on the row's record (the round trip —
  the line's phrase, the step-printed trim and the target in the line's
  answer are its gates, none of their own): a person's pick of a record
  the line's moves never reach decides that record. 0228|0 ("fat trimmed to
  ⅛ to ¼ inch") picked to 174414 decides 174414 — the v55 entry's 172641
  never re-lands there (0228's answer holds no 174414) and had been carried
  to 0622|5, a record nobody chose; 0187|0 picked to 171751 decides 171751;
  0223|0 or 0090|6 picked to 173128 decide R2's 174057 (carried back to
  173128); 0224|0 picked to the 0" flat 168743 decides 168743 (closer 2,
  verify2 D1 / D2). The compute's carried decision and apply_to_all's targets re-apply the
  ranked path's chain (`carriedFoodOf`: freshOverCured → leanAndFatSibling
  → trimDepthRecord, with the recipe) with the decided record as the top of
  the line's own cached answer, so each line lands as its own engine pick
  does, zero requests. Before, a Confirm of 0586's strip steak (Q7's
  171751) decided 171751 for every 'boneless strip steak' (six lines), a
  decision on 2727572 cancelled 0586's move, and a Confirm of a moved
  brisket decided 173128 for every brisket; now 0586 decides 2727572, the
  flat decides 168657 (R2 → 168743 → the trim → 173128: 0090|6 and 0223|0
  on 168743, 0091|0 and 0224|0 on 173128), the whole brisket 168607, the
  racks 172493 (R2 → 174321 → "trimmed" → 174377). The GET's others offer
  reads the same function (offer == write), and the reach (`decisionReach`,
  the offer's and the write's) leaves out a row the decision's moves leave
  on its own record — an unheld row above the gate on a lean-and-fat record
  (every move target is one: R2's, each `trimDepthRecords` target, 173128)
  whose line's chain lands the decision there, read on the row's text (the
  step-printed trim on its recipe), once per text and record a request — as
  it leaves out a row already on the decided food (0228's Confirm offers
  nothing: 0622's trimmed rack lands 174377 again; without it the offer
  counted no-op rows and the GET decoded the recipe it reached again). No
  corpus row moves (ingredient_decisions holds none). Not mapped back:
  freshOverCured's choice (no fixed pair — a word overlap); a carried
  decision re-applies it, and a row it would leave in place stays offered.
- **F11 — the stale window reads the coated food as the totals do** (folded
  into F7). The plan (and its key) read a row whose line was edited and not
  yet computed when it is still the same ingredient (its item key the
  line's, never an empty one: an amount edit) at its stored grams, as
  `recomputeTotals` counts
  it: crispy-fried-chicken's confirmed flour (144.06 g), its chicken line
  edited 4 → 10 pounds, read 0 g "poured away after your confirm" on the
  GET, and a Confirm in that window stored 0 g and held the dips (3,329.77
  → 2,723.81 kcal); now the window reads and keeps 144.06 g and the next
  compute writes 360.15 g, a fresh compute's.
Cost (RULE C, the editor caps: 120 steps × 10,000 characters, 400 lines;
medians, ABBA against 6ede11c): the quiet shapes within ±1.2 % (the strain
shape −1.0 / −0.4 / −0.0 % on the compute / the matches GET / a recompute,
the reserve shape −0.4 / +0.6 / −1.2 %, a 400-line R2 roast +0.5 / +0.7 /
−1.0 %); the TRUE paths from minutes to under 1.3 s (every strain guarded
417 / 384 / 276 ms; every reserve sentence unheated 437 / 392 ms — base 103
s each; 400 rinsed plus-part oils 1,276 / 1,136 / 781 ms — and with no toss
at all 1.28 / 1.14 / 0.78 s against base's 6.7 / 6.5 / 3.4 s; 389 fried
cauliflower lines 496 / 477 / 171 ms against 512 / 9,850 / 9,552; 400
confirmed coat parts 830 / 470 / 370 against 1,994 / 1,932 / 370). Each new
reader is count-pinned exactly on its quiet and TRUE shapes
(nutrition_v82_test: `lastMatching`, `memo:rinsedOff`, `memo:rinseTails`,
`leanOnlyReads`, `m52Keys` — the GET of 400 confirmed parts builds one M52
key, 395 without F8's O(1) path — the plans and the record reads). The
compute's carried decision (closer 2, verify2 D5) reads its moves once per
line text, item and record while no FDC cache write lands (`carriedReads`;
the moved food with it, once): 0239's roast line 390 more times under a
decision (169194, each line moved to 168381 by R2) computes in 254 / 250 ms
against base's 246 / 255 (ABBA medians; base carries 168381 unmoved;
before the memo 795 ms — the line's answer ranked 391 times), the GET
+0.3 % and a recompute +1.4 %;
with every memo voided before each path (a cache write) 250.5 / 699.5 /
144 ms against 250 / 688 / 141.5 (+0.2 / +1.7 / +1.8 %); the shape pinned
exactly (compute 1 read, 401 record reads — base 400: the moved food once).
The freed Confirm (closer 5): 0149 at the caps (389 more paprika parts), the
chicken skipped, every M52 row confirmed, then un-skipped — the PUT
re-derives each part once (797 record reads, the coat's mixing sentences
once each, the plan twice: the v70 revert's second pass) in 517 / 522 ms
against base's 320 / 325 (ABBA medians), where base keeps the 396 parts
at 0 g a compute counts; count-pinned exactly (nutrition_v82_test,
CONFIRMED PARTS FREED; the verifier's own run 522.5 against 317.5, +64.6 %);
the next recompute (the compute's own state) −1.1 to +0.4 % against base
across closer 5's and verify6's ABBA runs (369 / 371 ms against 372 / 375;
369 against 367.5); the quiet strain, reserve and parts shapes — where the
revert now asks an engine row in a plan's form whether its line is a coat's
mixture part (memoised per index) — within ±2 % of base: −2.0 to +1.2 %
across those runs (closer 5 −0.4 to −2.0 %; verify6, two rounds of 7 and 9
reps, −0.2 to +1.2 % on every path, the parts recompute 0.0 to +0.3 %).
Deploy note: no matcherVersion bump and no hash term — nothing stales, no
sweep; the kcal digest does not move.

**Review Run 065/066 fixes (matcher v81; matcherVersion 78 — the catch-up
review of v47–v54, both fleets; zero requests; server and salt_shared;
replayed on snapshot 29).** Each restores an invariant the dual-fleet
review found broken; one (F8) moves corpus rows:
- **F1 — an un-skip is the compute's row.** `unskippedRow` hands rule B1
  the line's ENGINE grams (`engineOutcome` on its own derivation, as the
  compute hands `withParts`), never its raw weight: a v50 cured pork the
  steps strain or discard stays 0 g (beef-braised-in-barolo|2 came back
  63.22 g rendered, +406.55 kcal under a fresh stamp). A skip and un-skip
  of every parts, alcohol, discarded and coating row of snapshot 29 (829
  rows) returns the compute's row and energy.
- **F2 — the alcohol reader reads the steps once per index.** Every fact a
  text gives it (stops, heats, minutes, vessels, words, mixtures, own
  mentions, printed parts …) is read once per text of the step index
  (`memo:alcoholTexts`); a name's mentions, uses, part-printing mentions
  and sharing lines, each line's group, alternatives and words, and the
  last hand-off once per recipe (`memo:alcoholRecipe`); and a run (the
  walk from a use to its end) is a function of its state from a step's
  first sentence on — a later run reaching a state an earlier one read
  takes what follows it, the minutes replayed in order (the same sums, bit
  for bit). The 20-line wine GET at the editor caps: 16.5 s → 0.37 s (stock
  0.31 s); 400 lines: a first run of every sentence plus 399 runs each to
  its first step boundary (98,553 sentence reads, not ≈ 13 million).
  Each line's foods vocabulary (the other lines' words a trail can take
  on) is narrowed to the words the index's sentences print — the only
  words `_alcoholHeadsIn` can match (a sentence, or a cut of one at a word
  boundary) — so lines that differ only by words the steps never print
  share their runs (closer 1, verify1 D1: 400 lines "1 (750-ml) bottle
  <own word> dry white wine" read 13,264,077 run sentences, none shared,
  10.9 s a compute; now 98,553 and 399, 1.5 s). Against base (verify1's
  ABBA rounds): the 400-line wine shapes −99.7 % (344 s → 1.1 s a path),
  their QUIET twin −55 to −74 %. Residual, stated and count-pinned
  (nutrition_v81_test's ALCOHOL OWN-NAMED): lines whose OWN words the
  steps print read different vocabularies and never share — each run
  reads from its use to its end, at most the lines' runs over the steps
  (`alcoholRunSentences`): at the editor caps 13,312,877 run sentences,
  ≈ 10 s a path and 1.0 GB max RSS (the run memo keeps every run's
  minutes); the identical-vocabulary shapes ≈ 0.4 GB.
- **F3 — the stop reader is linear.** The run's end ("serve", off the
  heat, a rest or chill, a strain or a move out) is read by one pass of
  its stop words and, for each greedy arm, the period-free piece's LAST
  tail — the last "from the heat", the last "cool/stand/rest", the last
  " to " whose word chain reaches a vessel (the first vessel on it), the
  last "to/on/onto" whose chain reaches a surface (the last on it) — each
  chain position read once per text; v54's single regex nested a greedy
  `[^.;]*` and a repeated `([\w-]+ )*` (cubic: ≈ 35 ms a 1,000-character
  sentence, 42 s one wine line under cap-sized steps; now 0.39 s). Equal to
  the regex — start, end and kind — on 120,000 sentences built from the
  corpus's.
- **F4 — the fried-food scan once per word.** The frying-oil block reads
  whether a frying sentence names a fried class's word once per word and
  index (`memo:friedNamed`), never per counted row (399 potato lines and
  an oil: 14.2 s a plan → 0.8 s compute, 0.4 s recompute; −95 % against
  base, verify1's ABBA rounds; the one scan left ≈ 30 ms against the scan
  stubbed, count-pinned once per index).
- **F5 — the offer is the write.** The matches GET counts `others` with the
  record the decision names (`decisionRecordOf`, the PUT's own): a canned
  bean the v49 twin move put on the solids-and-liquids record, and a
  skinless meat-only row, decide the record bought (chana-masala|11 was
  offered 6 recipes and wrote 1; 23 of the 96 twin-moved rows disagreed).
- **F6 — a prep note read is hashed.** `ingredientsHashOf` folds
  `prep_notes` wherever a reader beside the resolver can read it — the
  shell reader's "eaten shell and all", v50's potato kept-cooked kind,
  which takes a weight from the note's "cup(s) (…)" — for a recipe and a
  section copy alike. The gate reads the NOTE alone, never a step (closer
  2, verify2 D1: every freshness check runs it — the recipe nutrition GET
  too — and closer 1's linear step scan backtracked its amount run, 733 ms
  a hash and a nutrition GET 13–19 → 729–746 ms on "transfer 1" and a run
  of spaces at the caps; v81's first gate 9.8 s a hash on "Transfer 1 cup
  (warm "): a note printing "cup(s) (" folds whether or not a step reads
  it — a superset, so a re-stamp on identical rows, never a stale fresh.
  Deploy (F6 alone): 9 keys recompute once on identical rows — 7 re-stamp
  (their hash moves: 0279 (the shell), 0365, 0783, 0790, 0958, 1086 and the
  section 0393#The America's Test Kitchen All-Purpose Gluten-Free Flour
  Blend — the 6 notes printing one: 5 recipes', 1 section's — pinned
  corpus-wide) and the section's 2 routed parents, 0393 the-best-gluten-
  free-pizza and 0819 gluten-free-chocolate-chip-cookies, re-derive through
  its `child_stamp` (their hash and totals unchanged; closer 3, verify3
  D1 — pinned on a note edit of the section). Count-pinned (`prepNoteFolds`: a compute 2, a recompute 1,
  the nutrition GET 1, the matches GET 0; never on a note printing none);
  the hash = base on every shape (9–11 ms at the caps, both).
- **F7 — the coated vegetable is the one the coat coats.** A coating
  sentence sizes a held coat from a vegetable only when it names a coat
  line beside it (a line whose medium is the dredge) or a batter
  (`memo:coatLineSentences`): "Toss the onions with … butter to coat" beside
  a crumbed food no longer sizes the crumbs from the onion. The onion
  rings and the eggplant unchanged. Each line's medium is read by the coat
  arms alone (`discardedMediumOf`'s `coatOnly` — the same answer: coating is
  returned there or nowhere; closer 2, verify2 D3: the whole detector of
  every line made v80's ONION recompute run the oil, set-aside and bundle
  passes, +21 / +18 / +62 %); count-pinned = base on that shape but the
  reader's own memo and one more naming on the GET; against base (ABBA,
  medians of 5) compute +1.5–1.9 %, GET +0.3–0.5 %, recompute +2.0 % —
  the reader's own pass (one coat-arm read per line, one substring test
  per sentence for "batter"); the v26 ONION test +1.7 %.
- **F8 — a strained aromatic is the line's.** Whether a strained solid
  went back into the dish reads only the mentions of its food no line owns
  (A13's shared tail): the soup's own onion re-added after the stock's
  strain is the soup's line. **6 rows**, each now 0 g `discarded`
  ("approximate (strained out and discarded — what it gives the liquid is
  not counted)"): classic-chicken-noodle-soup|2 onion 110 g,
  hearty-chicken-noodle-soup|2 onion 70 g, |3 carrot 61 g, |4 celery 40 g,
  roast-butterflied-leg-of-lamb…|3 shallots 90 g, thai-style-chicken-soup|3
  cilantro 8 g — −170.99 kcal (per serving 531.36 → 524.40, 530.91 →
  515.27, 899.22 → 891.12, 401.31 → 401.00). Unchanged: a tail mention
  every line shares (0415's porcini, re-named by the cremini).
- **F9 — the stored position is never read.** The alcohol flag reads the
  line it is handed (its own place in the recipe's lines), never the row's
  stored position, which an edit leaves stale until the next compute (a
  matches GET after a save that shortened 0005's lines threw a 500).
- **F10 / F13 — two readers once per index.** Whether the steps strain a
  zest (`memo:zestStrained`) and whether a can's head is added with its
  liquid (`memo:canLiquid`, per head), both over the index's lower-cased
  steps — its windowed sentences, where v80 read the raw step text (they
  differ only past a 1,000-character sentence) — the regexes hoisted (7.4 s
  and 8.8 s computes at the caps before).
- **F11 — an emptied pick reads as the rule row.** A person's pick of a
  section its host later empties of ingredient lines reads as the engine's
  `no_ingredients` rule row: counted at 0 g and named in the label's
  `partial` (`not_routed`, `no_ingredients`), never `includes`; the pick
  stays the person's and the section a child, so lines added back route it.
  The totals read it too (closer 1, verify1 D2 — R1's parity): the line is
  neither matched nor accounted, so the parent reads PARTIAL exactly as the
  engine's own route of the same emptied section does (chraime|7 → its
  emptied Tabil: partial, 15 of 16; the roast's pick of it: partial, 5 of
  6). Sections only: a library recipe printing no lines is never one; and
  EMPTY only — a section cut to one line still routes (closer 3, verify3
  D2: Tabil cut to one real line keeps both parents complete, 16 of 16 and
  6 of 6).
- **F12 — the cut-word guard yields to a discard of the whole line.** A
  line cut fine WHOLE (no whole, halved, quartered, smashed, crushed,
  remaining, reserved or stem part; no plus part) and the only line of its
  head is removed when a discard clause names its food ("… pour through a
  fine-mesh strainer … Discard the garlic.", 0031's Garlic Croutons — a
  variation, so no computed row moves); a cut PART stays eaten. 0346|2
  already counts only its 5 minced cloves (15 g). A cut line reaches its
  mentions only where a discard clause names its head (closer 2, verify2
  D3: every cut line of a whole-piece or strained head read the by-name
  scan, v26 long-lines +14 %): count-pinned = base; the v26 long-lines
  tests +1.8 % end to end, +0.2 % at the loop level.
- **F14 — numbers are bounded.** `parseQuantity` (salt_shared) reads at
  most `maxQuantity` (1e9): a longer digit run — whole, numerator or
  denominator — or a non-finite decimal parses to null (an unmeasured
  amount), never an `int.parse` overflow or Infinity grams (each bound
  pinned, a 10-digit numerator and denominator included); the server's
  own digit reads (a bottle's count and size, a paren volume, a per-pound
  count, a duration's minutes) go through it, and a per-pound count of 0
  reads nothing. The editor refuses a quantity printing a number of 10 or
  more digits — a recipe's line or a subsection's, on create and update —
  `422 validation` "'amount quantity' must print numbers of at most 9
  digits." (closer 4, verify4 D2 — the v47 F11 / v70 F10 convention:) the
  import and the library rescan apply the same check on the way in: the
  import counts such a file failed, the rescan skips it with `reason`
  "fails validation: 'amount quantity' must print numbers of at most 9
  digits." and keeps the stored version. No corpus quantity prints a digit
  run longer than 2.
- **F15 — a recipe pick reads the route's share** (closer 4, the Opus
  critic). One function, `routeShareOf`, is the share the resolver routes a
  line at — the yield's (`parseShare`), a section's bare count of 1 (A9),
  rule WB's whole batch (1.0) for a line with no amount of a child with
  lines, never one a served-with marker reads (rule SW: the route never
  reads such a line) — and every reader of a line's share of a child reads
  it: the route, the PUT's recipe-pick gate and the share it stores, the
  derive of a decided child row when its line's amount moved, a recipe
  decision's reach and its apply-to-all write, and the fix sheet's
  candidates' `kcal_per_serving`. red-beans-and-rice|14 "Basic White Rice
  (this page)" (WB: 0521's section, 402.2 g): its section or its host
  picked with no share was refused "No share the yield can read" while the
  GET offered share 1.0 and `pickable`; now stored at 1.0 (402.2 g; the host
  1,791.6 g), and the candidate offers 240.45 kcal a serving (was null);
  the shared contract golden `nutrition_matches_wb.json` moves by that one
  value (panna-cotta|6's own-section coulis candidate: 80.35 a serving,
  the routed row's own; was null).
  Pinned beside it on a STATED amount-less copy of deep-dish-apple-pie|0
  (no corpus WB line routes to a library recipe): the library candidates
  382.09 / 440.00 / 456.17 a serving (were null), the reach takes the line
  (base: left out) and the apply writes it at 1.0; a decided row whose line
  is edited amount-less keeps 1.0 and 658.2 g (base: share 1.0 shown, 0 g
  counted). Served-with lines keep asking for the share (tortilla|8). A9's
  bare count of 1 stays a SECTION's (closer 5, verify5 D1): vegan-baja-
  style-cauliflower-tacos|14 "1 Vegan Cilantro Sauce" (its own section at
  1.0) picked as the library recipe 0521 with no share is refused, as
  before. No corpus row moves (person paths).
- **F16 — a section's job failure is the section's** (closer 4). In the
  per-recipe job a child section's failure was logged under the recipe's
  id; in a sweep a section's failure counted in `failed` (a 1-recipe sweep
  read "done 1, failed 2"). Now the log names the compute that failed and
  `failed` counts recipes (`GET /api/v1/nutrition/jobs/{id}`).
- **F17 — rule PV's choice is hashed** (closer 4). `ingredientsHashOf`
  folds, for each prose section a line reads (`prose_sections`), the base
  rule PV counts for it (`prose_bases`): PV reads the prose host's title
  and its other sections' titles and lines, and no stamp tied the parent to
  them — lemon-meringue-pie|0 → 0972's Basic Single-Crust Pie Dough, with
  0972's host retitled to a tie (→ the host) or given a sibling with lines
  under a closer title, read FRESH on the old base through every stale sweep
  while pumpkin-pie|0 still routed to it (the section GC heals only an
  abandoned base). Now the parent reads stale at once and ONE sweep
  re-routes it. Deploy (F17 alone, snapshot 29, zero requests): 2 recipes
  re-stamp once on identical rows — the two PV parents, 0983 fresh-plum-
  ginger-pie and 0989 lemon-meringue-pie (their hash moves; rows and totals
  unchanged); with F6, 11 keys in one round (the version bump re-stamps
  every recipe in any case). Pinned on both edits. Cost (closer 5, verify5
  D3; RULE C): every freshness check hashes, so PV's choice of base — the
  host's and every sibling's title words and lines, and whether the base
  is made from a recipe — is read ONCE per prose section a hash reads
  (`proseChoices`); read per line it cost +81 % a hash, +18–23 % a compute
  at the caps. What a line still reads is its own share of the base (the
  route's `routeShareOf`: the line's text and amounts against the base's
  yield — a line PV leaves unrouted has no stamp to carry it), once per
  prose-reference line and hash (`proseShares`): the residual, count-pinned
  exactly on the STATED cap shape (lemon's real line 0 repeated to 400
  lines beside real 0972; compute 2 / 800, recompute 1 / 400, the recipe
  nutrition GET 3 / 1,200, the matches GET none). Measured there (ABBA, two
  rounds, against cae00d4): a hash 14.0–14.7 ms vs 13.0–13.5 (+5–11 %;
  closer 4 read 22.4–23.1), a compute 84–86 ms vs 82–85 (+1–4 %), the
  recipe nutrition GET 145–149 vs 145–152 and the matches GET 263–268 vs
  267–276 (within noise); lemon itself (14 lines, one prose line) 0.86–
  0.94 ms vs 0.81–0.89.
Deploy note: matcherVersion 78 stales every recipe; one zero-request sweep
settles it; the kcal digest moves by the four recipes' per-serving changes
(−6.96 −15.64 −8.10 −0.31 = −31.01).

**Since matcher v71 (batch M71 — step prints: printed amounts, strained
solids, kept spoonfuls, frying media; matcherVersion 69; prep50 design_v2
§2 M71, decided under the 2026-10-07 standing authorization; zero
requests; reach PRE-Q18 — every reader reads a section's OWN steps).**
Seven rules, each a step sentence the engine now reads:

(1, pC R-H1) **An amount-less line the steps print an amount for.**
`stepAmountsOf` (the reading) and `stepAmountGrams` (its weighing, read
first in `lineGrams` after the giblets): a line with
no amount [re-point → `measurement`] reads every "<amount> <unit> (of)"
print (teaspoon, tablespoon, cup, ounce, pound) followed by up to three of
the line's own words and its head, in the line's SCOPE — where the line's
group is headed and two or more groups are, the steps carrying that
group's label ("FOR THE DOUGH"; an unlabelled step inherits the last
label), NONE when no step carries it (nothing is read); else every step;
a section reads its own. Three guards: (i) no
other line of the scope has the head (the print is that line's); (ii) no
sentence of the scope naming the head prints `repeat`, `each`, `per`,
`remaining` or `portion` (the amount multiplies or partitions — nothing is
read); (iii) a print in a sentence printing `to taste`, `up to` or `if
using` is dropped (a to-taste extra in ANOTHER sentence leaves the print a
floor). Several prints sum. The print is weighed on the line's own record
(`resolveGrams` on `<amount> x`, as a printed part is). Basis `from step N:
<amount> (no amount on the line)` (several: `from steps 2, 4, 5: ¼ teaspoon
+ 3 tablespoons + ⅛ teaspoon (no amount on the line)`; past eight prints
the first eight, then `+ … (3120 in all)` — every print is still
summed); no flag (a printed amount). The step LABELS join the ingredients
hash where a step carries one. 4 rows: ultimate-grilled-pizza|4 "Vegetable oil" 14.00 g (DOUGH, step
2 "Add 1 tablespoon oil and salt to dough …"), |11 "Sugar" 2.00 g (SAUCE,
step 3 "… ½ teaspoon salt, and ½ teaspoon sugar"; step 3's "Season with
additional salt and sugar to taste" is another sentence), shrimp-pad-thai|3
"Sugar" 39.21 g (steps 2, 4, 5; the ¼ teaspoon goes into a drained radish
soak — 1.00 g counted, a gap), quick-cooked-tough-greens|4 "Red pepper
flakes" 0.45 g: +286.08 kcal. Not read: pizza|12 (its PIZZA steps print
"Pour ¼ cup oil onto center of rimmed baking sheet." and "Drizzle top of 1
crust with 1 tablespoon oil.", but "Repeat with remaining 2 dough rounds,
adding 1 tablespoon oil …" names oil with `repeat` / `remaining`),
classic-gazpacho|10 ("each portion"), lighter-corn-chowder|10 ("up to 1
tablespoon sugar … to taste"), moqueca|8, the mac and cheese|5,
barbecued-pulled-chicken|18 and chocolate-volcano-cakes|9 (another line of
the scope shares the head), meringue-christmas-trees|6 (no print), and the
other 240 amount-less rows; the salt lines are rule rows (0 g `confirmed`),
out of reach by construction. An amount-less line whose steps print a volume FETCHES its record's
detail as a typed line would (the prints decide `gramsFor`'s fetch — never
a cache's luck: computed alone in a fresh library, 0685's pepper flakes,
0398's oil and 0554's sugar weigh 0.45 / 14.00 / 39.21 g, the same as in the
replay; the follow-up verifier's D1).

(2, pC R-E5) **"Strain … Press the solids … Discard the vegetables."**
`_strainAt` gains an arm beside its "discard … solids" next sentence: a
strain naming the vegetables, contents or liquid, its next sentence
opening "press (on) (the) solids" and the one after opening "discard (the)
vegetables|solids". `_strainedOut` and its guards are unchanged (0 g
`discarded`, `approximate (strained out and discarded — what it gives the
liquid is not counted)`). braised-turkey |4 onions, |5 celery, |6
carrots, |7 garlic, |8 bay, |10 parsley (−233.14) and slow-roasted-turkey-
with-gravy |0 |1 |2 |4 (−225.44) → 0 g; the two thyme-sprig lines
(braised|9, slow-roasted|3, 0 g either way) now read the strained basis, as
the library's 19 other strained sprigs do. braised-turkey|11 "½ ounce dried
porcini mushrooms" (audit L070) is NOT reached: its head is `mushroom` and
the steps call it "porcini", so `_strainedOut`'s own-mention test finds no
mention (a gap; reaching it needs a mention by the item's own word, which
would also reach italian-wedding-soup|3 — closed at v85: M83 B5 reads that
word, both rows 0 g `discarded`). R-E5 as built: 10 kcal rows and
the 2 basis-only sprig rows, row column −458.58 / recipe energy −458.50 —
the design's §2 figure, −500.54 on 11 rows, less the porcini's 41.96.
Not reached: pumpkin-pie and
jellied-cranberry-sauce ("press the solids through" — eaten), arista (its
lemon squeeze prints "Press on solids to extract all pulp; discard solids."
— one sentence: the engine splits at periods only), chicken-teriyaki,
braised|12–|14 (the kept liquid).

(3, pC R-E2) **A printed part of strained solids kept.** grilled-potatoes-
with-garlic-and-rosemary step 1: "Pour mixture through fine-mesh strainer
into small bowl; press on solids. Measure 1 tablespoon of solids and 1
tablespoon of oil into large bowl and set aside. Discard remaining solids
but reserve remaining oil." (the corpus's one such sentence; closer 1's
V1-D3 counted the lines whole, and `_strainAt` still skips the strain).
`_keptSolidsOf` reads it; M52's plan (`_m52Plan`, as the cut dough) weighs
each strained line named before the strain (`_strainedHeads`, a zest
strip; no ground spice) at s × its whole grams, s = min(1, kept / Σ whole),
the kept tablespoon at SR 169230 "Garlic, raw" '1 tsp' 2.8 g × 3 = 8.4 g
(`_keptSolidsTsp`): |1 garlic 27.00 → 8.19 g, |2 rosemary 0.70 → 0.21 g
(s = 0.303249), −27.54 kcal. Basis `discarded in cooking — only the 1
tablespoon of strained solids the steps keep (step 1) counted · approximate
(the cooked solids weighed as raw minced garlic, USDA SR 169230 2.8 g per
teaspoon)` — a floor (blond-fried garlic has lost water). A Confirm reads
the plan's grams; a row the plan stops covering goes back to its whole
line (the v70 F9 revert).

(4, pE R-E3) **Galangal is a strained aromatic** (`_vegetableHeads`):
guay-tiew|5 16.00 → 0 g (−12.80; step 2 smashes it with the lemongrass,
"remove solids from pot and discard"). Its |2 scallions and |4 chiles stay
(the whites and the whole chile leaving at step 2 are a part-of-line gap,
< 20 kcal).

(5, pF R2) **A fat whose steps use only printed spoonfuls of "the reserved
oil".** `_partialUseOf`'s new kind `used` (`_reservedUseOf`; the oil branch
of `discardedMediumOf` reads only this kind): a fat line (oil, fat,
shortening, lard) by volume, counted whole, whose scope prints
`(?<![\w¼½…])(<amount>)\s+(teaspoons?|tablespoons?)\s+(?:of the\s+|more\s+)?
reserved\s+<head>\b` and no sentence `\bremaining (?:reserved )?<head>\b`
that does not open "discard" (a discarded remainder does not block; a used
one does): kept = Σ the prints at the line's own g/mL, below the line.
Basis `only <prints> of it used (from step N) — the rest counted as 0 g ·
approximate (the steps use <prints> of the reserved oil; the rest is not
used here — the fried aromatics' oil not counted)` — `<prints>` names at
most 8 printed amounts, then `+ … (<n> in all)` (R-H1's form; the sum
covers every print). The tom yum's Nam Prik
Pao §0|0 "½ cup vegetable oil" 112.00 → 28.00 g ("2 tablespoons reserved
oil"; the section 1,211.70 → 455.70 kcal and its parent's |15 row with it),
nasi-goreng|9 112.00 → 51.33 g ("1 teaspoon of the reserved oil", "1
teaspoon more reserved oil", "3 tablespoons more reserved oil"),
bulalo|0 56.00 → 28.00 g ("1 tablespoon reserved oil" twice, "Discard any
remaining reserved oil"): row column −2,310.00, recipe energy −1,553.94
(the replay's per-serving sums; §2 printed −1,554.00, rounded).
Not reached: arista|1 ("… with remaining reserved oil"), crispy-salt-and-
pepper-shrimp and crispy-orange-beef ("Heat reserved oil", no amount),
mujaddara ("reserved onion oil"), the oil mixtures (italian-style grilled
chicken, souvlaki, mechouia), spanish-migas|5, braised-turkey|12,
beef-burgundy|12 |21, cuban-shredded-beef|3. Gap: the fried aromatics'
oil uptake (no cached record) — an undercount, flagged.

(6, pF R3) **Bacon fat added to the frying oil joins the frying medium.**
`_joinsFryingOil`: a fat line (fat, lard, shortening — never an oil) an
"add" or "combine" sentence names (its own word with any fat word: "bacon
grease" for "bacon fat") in a step naming the oil, where a line headed
`oil` is a frying oil → `DiscardedMedium.fryingOil`, 0 g; M52's plan sizes
no uptake for it (the fried food's uptake stays on the oil's row). Basis
`discarded in cooking — counted as 0 g · part of the frying medium (the
fried food's uptake is counted on the frying oil's row)`. (v85, M83 B4: the
plan now gives it its mass share of the same uptake, flagged as the oil is
— 1.59 g and 2.52 g; this basis is retired.)
classic-french-fries|2 ("Add the bacon grease (if using).") and
easier-french-fries|2 ("Combine the potatoes, oil, and bacon fat (if
using) …") 51.60 → 0 g: −925.70. Not reached: dakgangjeong|0 (sesame oil).

(7, pE D-E1) **The lines whisked into a coat held with no budget are held
with it.** `_coatPartsOf` / `_coatOfPart`: a line (no medium, no dip) a
mixing sentence (whisk, combine, stir, beat, mix, sift as whole words —
never "mixture") names with a coat line (`_dipsOf`'s own-word naming);
only in M52's no-budget branch, as a held coat's
dips are (`coating`, no grams; a Confirm 0 g poured away; a pick keeps the
hold): maple-glazed-pork-tenderloin |7 sugar 25.14 g, |8 salt, |9 pepper
("Whisk the cornstarch, sugar, salt, and black pepper in a small bowl
until combined.") → held: −108.41; the recipe stays partial (audit 5's
pattern D calls this mixture eaten — the hold follows its coat). A
budgeted coat's seasonings are counted as before (easier-fried-chicken,
crunchy-oven-fried-fish, fish-and-chips, chicken-fried-steaks, the fried
calamari: 19 rows the branch gate keeps); skillet|2 and salmon|2 hold a bare
coat.

Totals vs the v69 rows (snapshot 27): 28 rows — the 25 food rows above, the
2 sprig rows (basis only) and the tom yum's parent row; row column
−3,556.96, recipe energy −2,800.76; statuses unchanged; holds +3. Known gaps
kept: marinade pickup (no USDA figure); the roast-salted turkey's dry brine;
the 11 unmeasured pour-offs outside C4; braised-turkey's kept broth ("use
any remaining broth for another use", a volume with no weight); the
sub-noise lines (an "extra sauce" salt, bay leaves, gravlax's scraped dill);
the 248 amount-less lines no step sizes (the sugar stars, the oiled
counters) at 0 g; the fried aromatics' uptake; the porcini above (closed
at v85, M83 B5).

**Beyond the brief — a line's position by identity.** `_positionsOf`, the
line → position map M71's readers key on (the scope, the memo keys), was
first built as an equality-keyed map, so two groups' identical lines
(braised turkey's "Table salt and ground black pepper" in its turkey and
gravy groups) collapsed onto the LAST one's position — the first group's
copy was read at the other's position, in the other's scope (found by the
cap shape: its DOUGH copies read the SAUCE steps). It now maps each line object to its own
position; a caller's re-decoded copy of a line falls back to the first
equal line. No corpus row moves for it (the replay with the equality map
restored is byte-identical); pinned on a stated synthesized 0398 with a
copy of SAUCE's "Sugar" in the PIZZA group.

**Cost (RULE C).** R-H1 reads its prints in ONE pass per step index
(`_stepPrintsOf`, `memo:stepAmounts`): the sentences naming an amount-less
line's head (the steps' word index), each `_stepAmount` match filed by
(form, step) with its sentence's hedge test, and the named sentences that
multiply, so a line walks only its own scope's prints (counted
`stepPrints`, `stepPrintsWalked`) and looks each multiplying sentence up in
its head's naming. Measured against v70 (8f42742) on the editor-cap shape
of `nutrition_v26_cost_test` (0398's two labelled groups of 200 amount-less
lines, 120 steps × 10,000 characters; 9 runs × 6 interleaved, base-tree-
tree-base): where no step prints an amount of those heads, compute 519.7 →
519.2 ms, the matches GET 466.7 → 468.8, the recompute 176.3 → 178.5 (−0.1 /
+0.5 / +1.2 %); where EVERY sentence prints nine (56,160 prints, 20 lines
each summing its group's 3,120), compute 503.0 → 551.3 ms (+9.6 %), the GET
449.7 → 502.0 (+11.6 %). That residual is the reader's own per-print work,
with no base equivalent — the regex's match objects alone are about 20 ms
(4 %) of it — and is pinned at its measured size (56,160 prints indexed;
3,120 walked per read line, never the other group's 6,240). The D-E1 gate
(`_coatOfPart`, asked for every held part on every decided path) tests each
sentence for a mixing word once per index (`_mixesAt`, `memo:mixes`, each
test counted `mixTests`), reads the coat-mixture pass once (`memo:coatMixes`,
its lines counted `coatMixLines`) and its "could any line be a coat" test
once (`memo:mayHoldCoat`); pinned on a held-mixture cap shape (0235 with
391 rows held `coating`, 390 of them decided parts the GET reads through
the gate) where the pass run per gate call fails a count (312,000 lines
read against 400), as it does on the long-lines shape (800 against 400).
pF R3 (`_joinsFryingOil`, asked for every fat, lard or shortening line by
`discardedMediumOf`, the GET's basis and the plan's pans) reads the
add-or-combine sentences of the steps naming the oil ONCE per index
(`_fatsIntoOil`, `memo:fatsIntoOil`: the word before each fat word and the
fat heads each names, every sentence read counted `fatsIntoOilReads`); a
line looks up its own word, and whether an `oil` line fries is asked once
(`memo:friesOil`). Before (the review of M71, verify2 D1) each call walked
every add sentence with its own pattern and scanned the whole step for
"oil" once per sentence naming the line: on 0316's lines with 399 copies of
its bacon-fat line under 120 steps × 10,000 characters of "Add the bacon
fat to the bowl.", compute 104 s and the GET 211 s (v70: 0.6 s / 0.4 s).
Measured now against v70 (8f42742), base-tree-tree-base, 5–9 runs each:
where no step names the oil (the potatoes, or the bacon fat, added to a
bowl) compute −0.9 / −0.5 % and the GET +0.7 / +2.1 % — against the same
tree with R3 switched off, compute +0.0 % and the GET +1.9 % (one pass
per index that stops at each step's first add sentence); where every
sentence adds the bacon fat to the hot oil (35,280 sentences, each one R3
must read) compute −2.4 %, the GET +7.2 % — the pass's own per-sentence
work (about 20 ms per index, no base equivalent), pinned at its size in
`nutrition_v26_cost_test` ("R3 FAT LINES"). pF R2 (`_reservedUseOf`, asked
for every fat line by `discardedMediumOf`'s oil branch and `_partialUseOf`
— the compute, the GET's basis, engineOutcome) finds a head's printed
spoonfuls ONCE per index (`memo:reservedUse`, each counted `reservedHits`,
each distinct printed amount parsed once) and sums them ONCE per head and
scope (`memo:reservedUseIn`, keyed by the scope's heading; each print walked
counted `reservedHitsRead`), naming at most 8 of them; a line compares its
own volume with its scope's sum. The pattern runs over each whole step
(none of it matches a period, so no print spans a sentence break), only on
steps holding "reserved"; the remainder test only on steps holding
"remaining". Before (the review of M71, verify3 D1) each call filtered and
parsed every print of the head: on 0523's lines with 386 copies of its "½
cup vegetable oil" under 120 steps × 10,000 characters of "Heat 1 teaspoon
of the reserved oil." (32,400 prints), compute 50.8 s and the GET 99.8 s
(v70: 1.2 s / 0.9 s); and (verify4 D1) each row's basis named every print
twice — with "Heat 1/10000 teaspoon reserved oil." in every sentence
(33,240 prints, Σ below the line: the read on every copy) one matches GET
was 489,617,983 characters (v70: 729,010), each basis 1,263,287; now 922,897
and 509 (the 387 read rows' own basis text). Measured against v70
(8f42742) and against the same tree with R2 alone switched off, 5 runs per
arm in base-tree-off-off-tree-base order (closer 4, the final tree): USED
("Heat 1 teaspoon of the reserved oil.", no read) compute +0.0 %, the GET
+1.3 % (off +0.1 / +0.7 %); BELOW (steps 1–23 one teaspoon) compute +0.5 %,
the GET +1.1 % (off −0.9 / +0.3 %); MANY compute +1.6 % (off −1.3 %), the
GET +5.5 % (off −1.0 %) — earlier runs of the same protocol +2.1 / +2.7 %
and +6.0 / +5.9 %. The MANY GET's residual, measured with a Stopwatch
around each reader: R2's own pass (one regex over the 1.2 MB of steps and
its 33,240 matches; 14.3 ms, 12.4 on USED, 3.9 on BELOW — 18.5 before the
whole-step pass); the shipped v51 pour-off reader (`_keptInPanBasis`, asked
by the basis of every `discarded` row with grams), whose detectors build
once per index the first time a GET meets such a row — 30 ms on MANY
whatever the row count (24, 100, 400 lines: 30.1, 30.3, 31.8 ms), 12 on
BELOW, never asked on a `portion` row; and `_m50DiscardedBasis`, about 32 µs
per read row (12.2 ms for 387). None has a base equivalent: base reads no
print and writes `portion`. The recompute where the read fires is +71–72 %
(285 → 491 ms on MANY, 285 → 488 on BELOW): the read's 387 `discarded` oil
rows are asked about by the shipped readers of a discarded engine row (the
M52 plan's media, v53; the F9 revert check, v70), whose step detectors build
once per index; with both readers off the recompute is 293 ms, and a
`portion` row asks neither (USED +0.5 %). Pinned in
`nutrition_v26_cost_test` ("R2 RESERVED OIL USED / BELOW / MANY": the
counts, every read row's exact basis, the GET body within 2 % of its
measured size).

**Since matcher v72 (batch M72 — records, yields and rendered fat;
matcherVersion 70; prep50 design_v2 §2 M72, decided under the 2026-10-07
standing authorization; zero requests; reach PRE-Q18 — the gate reads a
recipe's OWN steps).** Six rules:

(1, pA R2) **Cooked white rice on FNDDS's plain cooked record.**
`_rankAs['cold cooked white rice']` → the line's own cached answer, ranked
as `rice white cooked no added fat`: FNDDS 2708408 *Rice, white, cooked, no
added fat* (129 kcal; its detail cached, '1 cup, cooked' 158 g; index 3 —
the glutinous 2708422, a variety the line never prints, led at 0.6775).
Unflagged (the record is the food).
fried-rice-with-shrimp-pork-and-shiitakes|9 "5 cups cold cooked white rice,
…" 870.00 g / 835.20 → 790.00 g / 1,019.10 (+183.90); per serving 534.43 →
580.41. Not moved: kimchi-bokkeumbap|10 (short-grain, printed), every raw
rice line, the rice sections. The only other corpus line with the item is
0521's own variation "Fried Rice with Peas and Bean Sprouts" (no line routes
it; never computed). Not linked to the recipe's Basic White Rice: that
section prints no cooked yield.

(2, pA R3) **Cassava pared at AH-102 item 496.** `produceYields[169985]`
(`peeled`, 0.74) and the record set `_paredAsBought` {169985}: a line on the
record weighed in its HEAD reads the pared figure with no prep word in its
tail — the root's brown skin is never the food (no item-grammar guard: no
corpus line prints a pared or frozen root before the noun) [re-point →
`prep`]. The step reader cannot reach it: 1098's paring sentence ("Place
pieces cut side down and use knife to remove skin …") names "pieces", not
yuca. Basis `from 2 pound × 0.74 edible · approximate (USDA AH-102 item 496:
cassava, common, bitter, raw → pared root 74 % (limited data; brown skin
and thin inner layer 26); the woody stem ends and core the steps also cut
are not deducted)`. fried-yuca|0 907.18 → 671.32 g (1,451.49 → 1,074.11);
|2 the frying uptake follows the row's grams (FNDDS 2709565's 15 g per
100 g raw cassava): 136.08 → 100.70 g (1,224.72 → 906.30); per serving
669.05 → 495.10; stays partial (the boiling salt held).

(3, R-Y) **Peaches and Brussels sprouts at their AH-102 rows** (the
shipped tail-word reader [re-point → `prep`]): SR 325430 *Peaches, yellow,
raw* `peeled` 0.76 — `USDA AH-102 item 1654: peaches, raw whole, all
samples → peeled flesh 76 % (32–94; pits and skins 24)` (printed p. 77);
Foundation 2685575 *Brussels sprouts, raw* `trimmed` 0.90 — `USDA AH-102
item 423: Brussels sprouts, raw, untrimmed, good quality → trimmed, ready
to cook 90 % (88–92; outer leaves 10)` (printed p. 23; no all-samples row,
good quality is the retail grade, fair quality 70 not read). Seven rows:
peach-crisp|8, fresh-peach-pie|0, fresh-peach-pie-with-all-butter-lattice-top|0
1,360.78 → 1,034.19 g (−137.17 each), peach-tarte-tatin|4 907.18 → 689.46 g
(−91.44); brussels-sprout-salad-with-warm-mustard-vinaigrette|8 680.39 →
612.35 g (−40.47), roasted-brussels-sprouts|0 1,020.58 → 918.52 g (−60.71),
skillet-roasted-brussels-sprouts|0 453.59 → 408.23 g (−26.98). Not moved: a
pitted-only line (summer-peach-cake|0, the two free-form tarts — AH-102
prints the pits alone only for cling 12 / freestone 5), a count
(the-best-summer-fruit-tart|10 "2 ripe peaches, peeled"), the two
frozen-peach rows (another record).

(4, pE R-E1 + R-E2) **`braisedKept`: the pairs deduct the fat columns too,
and the whole brisket's rendered fat is deducted.** `braisedEnergyShare`
(matcher v69) became `braisedKept`, record → {`energy`, `fat`, `saturated`,
`monounsaturated`, `polyunsaturated`} — each column's own share of USDA's
same-cut raw → braised pair by the protein tracer (cooked × P raw ÷
(P cooked × raw), every value a cached record's); protein, sodium,
cholesterol and the rest stay gross (the steps skim FAT). Trans: neither
brisket pair publishes it (no 605 on 173128/173130 or 168664/168665);
170827 → 171223 does (1.118 → 1.52 g per 100 g, a kept share 0.925368) and
it stays gross — the design's five columns (a known gap, below). One arm of
`recomputeTotals` loops
the map — energy and fat never part; the row's grams and kcal column stay
gross.

| raw → braised (USDA SR) | cut | energy | fat | sat | mono | poly |
|---|---|--:|--:|--:|--:|--:|
| 173128 → 173130 | brisket flat, ⅛", choice (M70) | 0.676033 | 0.553960 | 0.579870 | 0.558149 | 0.538644 |
| 168664 → 168665 | brisket whole, ⅛", all grades | 0.933051 | 0.914810 | 0.894077 | 0.912399 | 0.918487 |
| 170827 → 171223 | chuck short ribs, boneless, 0", choice | 0.899002 | 0.858391 | 0.886218 | 0.878281 | 0.941400 |

The flags print both shares: braised-brisket-with-pomegranate|0 `… USDA's
braised pair 173128 → 173130 keeps 67.6 % of the energy and 55.4 % of the
fat by the protein tracer — the fat the steps skim, deducted)` — its fat
−202.12 g (sat −76.67, mono −85.50, poly −7.94), energy unchanged (794.35
/serving; M70's stated gap closed);
barbecued-whole-beef-brisket-with-spicy-chili-rub|10 `approximate (the
printed ¼-inch fat cap counted at USDA's ⅛-inch trim, the deepest it
publishes for brisket; USDA's braised pair 168664 → 168665 keeps 93.3 % of
the energy and 91.5 % of the fat by the protein tracer — the fat that
renders into the separator, deducted)` — recipe energy −768.29 (740.17 →
697.49 /serving), fat −73.81 g (sat −36.18, mono −33.85, poly −2.44); the
row stays 11,475.88 gross. (Q1 for the whole cut was an authorization
decision declined in prep49 only for lacking M70's deduction.)

(5, R-E3) **The gate: a pair deducts only where the recipe's own steps
print that the fat is not served** (design §0.3, the braised-pair
doctrine), and the boneless short ribs join. NEW `_defatsLiquid` (read once
per step index, `memo:defatsLiquid`): a step sentence matching
`\bskim\w*\b[^.]*\bfat\b|\bfat\b[^.]*\bskim\w*\b|\bfat separator\b|\bdefatted\b|\bstrain off the fat\b`
— read LINEAR (`defatsSentence`: the substrings "fat" and "skim" first, the
phrases, then the skim and the fat as two finds in each period-free piece —
the regex's `[^.]*` never crosses a period; pinned against the regex). The
gate applies to EVERY `braisedKept` record — 0224's "Using wide, shallow
spoon, skim fat from surface and discard." and 0595's "… pouring any meat
juices into fat separator." pass — through ONE function, `braisedKeptOf(raw,
fdcId, recipe)`, that the deduction (`recomputeTotals`), the basis flag
(`trimStandInFlagOf`, now given the recipe) and so the matches GET read
with the same recipe; a record the printed depth moves a line onto (173128,
168664) still needs that depth printed (since v74 a step's printed trim
also carries 0091's flat onto 173128 — M74 below). `braisedKept[170827]`: SR 170827
*Beef, chuck, short ribs, boneless, separable lean and fat, trimmed to 0"
fat, choice, raw* (detail) → SR 171223 *… cooked, braised* (a hit in the
cached `bone-in english-style beef short ribs` answer): P 17.22 → 25.3
(yield 0.680632), E 240 → 317, F 19.03 → 24.0. Flag `approximate (USDA's
braised pair 170827 → 171223 keeps 89.9 % of the energy and 85.8 % of the
fat by the protein tracer — the fat the steps skim, deducted)`. Twelve rows
sit on 170827; six are gated, basis only (rows gross), **recipe energy
−2,065.59**: tuscan-style-beef-stew|0 −439.79 ("Strain sauce through
fine-mesh strainer into fat separator." / "… return defatted liquid to
pot."), braised-beef-short-ribs|0 −384.82 ("… and strain off the fat."),
slow-cooker-beer-braised-short-ribs|0 −361.39 ("… skim off the hardened fat
from the liquid."), beef-short-rib-ragu|10 −219.90 ("… skim off any excess
fat …"), carne-deshebrada-shredded-beef-tacos|12 −329.85 ("… skim any fat
off surface."), chinese-braised-beef|11 −329.85 (the separator and the
defatted liquid). Not gated, byte-equal: nikujaga-beef-and-potato-stew|3
("Pour off all but 2 tablespoons fat from pot." — a browning pour-off; the
simmer liquid is served), catalan-style-beef-stew-with-mushrooms|11,
pub-style-steak-and-ale-pie|2, panang-beef-curry|0,
grilled-boneless-beef-short-ribs|0, best-old-fashioned-burgers|1 (ground
raw). 0090's "skimming any scum" is no skim of fat (no pair there either).
A 173128 or 168664 line whose steps skim nothing (none in the corpus) —
or asked with no recipe — says `… no step skims the rendered fat — not
deducted)` and counts gross; a 170827 row ungated has no flag. Not the
shipped `_fatSkimmed` (Q17's discarded-media reader): that one also fires
on a pour-off, which §0.3 excludes.

Batch: 10 rows in grams + 8 basis-only; the ROW column −1,143.02, RECIPE
ENERGY −3,976.92; statuses, holds and buckets unchanged; 0 requests.

**Cost (RULE C).** The gate is one pass over the steps' sentences per
index, a substring test first; the design's `[^.]*` pair is quadratic on a
sentence of repeated words and the finds are linear — pinned in
`nutrition_v26_cost_test` as 1,200 sentences of ≈ 1,000 characters in each
of three shapes, each read under 200 ms: "fat " repeated with no skim (the
critic's shape for Run 064's gate; it bounds only the substring test, which
stops it), skim words with no fat word, and fat words with "skim" only
inside a word (these two reach the skim arm's finds; either half of the
design's pair restored reads them in 630–800 ms, the tree in ≈ 9 ms). The
cap shape — 400 short-rib lines under 120 steps × 10,000 characters
naming "skim" and "fat" in separate sentences,
never a skim of fat (the gate false: every sentence read) — reads the gate
once per index (`memo:defatsLiquid` pinned in `nutrition_v26_cost_test`);
measured against matcher v71 (4 rounds base-tree-tree-base, 7 runs each,
the means): compute +0.1 %, the matches GET +0.5 %, a recompute +1.2 %
(the gate's own read ≈ 4 ms over the shape's 53,400 sentences; a recompute
builds no flat sentence list for it). The flags join no list.

Known gaps: the spiral-sliced hams stay at AH-102 item 1937's 0.70 (the
auditors' 0.83× — no row names a spiral or cured half ham); the yuca at
671 g, below the auditors' 705 g (the source pares 26 %), a bitter-cultivar
row on sweet yuca, the stem ends and core unsourced; the corned briskets'
cure sodium (Q2 (c)); the peaches' pits on pitted-only lines (no
all-samples pit row); Brussels' Foundation energy order (F9: 2685575 is
read at Atwater 957's 59.49 kcal per 100 g, not 958's 48.78); the whole
brisket's 2 h dry grill phase is not in USDA's braised pair, and the cup of
defatted juices returned carries a little protein the tracer reads as lost;
a make-ahead note in parentheses that skims fat would gate (none on a
pair's recipe); the six gated short-rib recipes keep 170827's trans fat
gross (USDA's pair keeps 92.5 % of it, 1.118 → 1.52 g per 100 g by the
protein tracer; the undeducted 7.5 % is 0.76–1.51 g a recipe —
tuscan-style-beef-stew stores 20.28 g, 1.51 g of it skimmed; `braisedKept`
carries the design's five columns only). Deploy note: matcherVersion 70 stales every recipe; one
zero-request sweep settles it.

**Since matcher v73 (batch M73 — flags and flavourings; matcherVersion 71;
prep50 design_v2 §2 M73, decided under the 2026-10-07 standing
authorization; zero requests; no step read).** Four rules (the second
widened by the orchestrator's ruling R1, 2026-10-18), 106 rows, 0 kcal:

(1, pD C3) **Makrut lime leaves and the Lapsang smoking tea are
zero-nutrient flavourings** (the v37 class: an explicit list of exact
NORMALIZED items — the corpus lines print `makrut lime leaves` and `ground
lapsang souchong tea leaves`, plural; the decision key singularizes, the
list does not — and a line held as a discarded medium still stays held).
FDC holds no lime leaf (the cached 'makrut lime leaves' answer holds 25 leaf
records of 14 plants, none a lime leaf); 0615's tea is sprinkled under the
rack to smoke the ribs (step 2), never eaten. guay-tiew-tom-yum-goong…|3 (its
leaves are also fished out and discarded at step 2), panang-beef-curry|7 and
oven-barbecued-spareribs|10 leave SR 168416 *Drumstick leaves, raw* at
confidence 0 (264 g / 5.25 g displayed, 0 kcal) for the rule row "Flavouring
— no nutrients, counts as zero", 0 g; guay-tiew and the spareribs →
complete, panang stays partial (its curry paste |2 unmatched).

(2, pD C4) **The K stand-ins say so** (flag only, the 173408 / 173420
precedents; `trimStandInFlagOf` [re-point → `item`]): a line naming
`dijon` on Foundation 326698 *Mustard, prepared, yellow* → `approximate
(FDC holds no Dijon mustard — counted as prepared yellow mustard)` (70 rows,
8 of them section rows; the 5 discarded dip rows keep their dip basis and
gain the flag), and a line naming `porcini` on SR 168436 *Mushrooms,
shiitake, dried* → `approximate (FDC holds no porcini — counted as dried
shiitake)` (15 rows, incl. grilled-stuffed-pork-tenderloin's Porcini and
Artichoke Stuffing and braised-turkey|11, still counted at 14.17 g — M71's
strain did not reach it: its head is `mushroom`, the steps say porcini; at
v85 M83 B5 strains it out by that word, 0 g, the flag kept on its
discarded row). No cached answer
holds a Dijon or porcini record (the 'dijon mustard' answer is FNDDS
2710202 honey mustard dressing alone). Not flagged by this arm: the 23
other lines on 326698 (16 whole-grain — flagged by (2′) —, 6 yellow,
boston-baked-beans' brown) and the 7 shiitake lines on 168436.

(2′, R1 — the orchestrator's ruling, 2026-10-18, under the 2026-10-07
standing authorization) **Whole-grain mustard says so too.** §2 M73 flagged
it "only if its cached answer holds no whole-grain record"; the condition
is read as no whole-grain MUSTARD record. The cached answers ('whole-grain
mustard', 'whole grain mustard') hold 25 whole-grain GRAIN foods each
(waffles, flours, breads) and no mustard, the line reads the `mustard
prepared` rewrite, and no cached record anywhere is a whole-grain mustard.
A line naming `whole-grain`, `whole grain` or `coarse-grain mustard`
(`\b(?:whole|coarse)[- ]grain mustard\b`, after the Dijon arm — no corpus
line names both) on Foundation 326698 → `approximate (FDC holds no
whole-grain mustard — counted as prepared yellow mustard)` (16 rows, 4 of
them section rows — garlic-studded-roast-pork-loin's Mustard–Shallot Sauce
and glazed-salmon's three glazes —, basis only, 0 kcal; it moves
brussels-sprout-salad-with-warm-mustard-vinaigrette|1, M73's whole-grain
negative, into the reach). SR 172234, the cached rewrite's other prepared
yellow record, holds no row, so no arm reads it. Not flagged: the 7 other
lines on 326698 — yellow mustard, the record's own food
(indoor-pulled-chicken|0, peruvian-roast-chicken-with-garlic-and-lime|7,
indoor-pulled-pork-with-sweet-and-tangy-barbecue-sauce|4,
oven-barbecued-spareribs|0, jerk-chicken|9,
grill-roasted-cornish-game-hens|4) — and boston-baked-beans|6's prepared
brown mustard (Gulden's; outside R1).

(3, pE R-E4; keep 32 g) **The lumpia row says what it counts**: a line
naming `lumpia` on SR 172802 *Wonton wrappers (includes egg roll wrappers)*
→ `approximate (USDA SR 172802's 7-inch egg-roll wrapper, 32 g a sheet —
FDC holds no 8-inch lumpia or spring-roll sheet and no label read prints a
size (L49); the thin lumpia sheet likely weighs less)` [re-point → `item`].
lumpiang-shanghai-with-seasoned-vinegar|16, 608.00 g unchanged. Not
flagged: shu-mai|15 (5½-inch egg roll wrappers — the record's own food),
pork-and-cabbage-dumplings|16 (gyoza, its own label). Not built: the
per-area figure (64 sq in × 0.653061 g = 41.80 g a sheet, +669.26 kcal) —
it moves away from every label L49 read.

(4, critic F7, L221) **The berries read raw raspberries**:
`_rankAs['raspberries and or blackberries']` → the cached 'raspberries'
answer ranked as `raspberries raw` [re-point → `alternative`]:
buttermilk-vanilla-panna-cotta-with-berries-and-honey|7 "Fresh raspberries
and/or blackberries" FNDDS 2707997 *Pie, berry* (confidence 0, a wrong
food) → FNDDS 2709281 *Raspberries, raw* (1.0), still 0 g `unmeasured` (no
amount on the line); the recipe stays complete (281.02 /serving).

Batch: 106 rows (3 rule rows, 102 basis-only, 1 record-only), 13 of them
section rows; 0 kcal (row column = recipe energy = 0); 2 recipes complete
(1,045 / 153); buckets check −3, counted +3; holds and sections unchanged;
0 requests. The flags are fixed texts and join no list; no step reader.

Known gaps: panang eats its few sliced leaves (no FDC record — counted 0);
the panna cotta's step "top with 3 to 5 berries" is a count no unit reads
(no piece figure is cached for a berry); the lumpia sheet's own weight
(the per-area figure, not built); Dijon's, whole-grain mustard's and
porcini's own compositions (no FDC record); boston-baked-beans' brown
mustard counted as yellow, unflagged. Deploy note:
matcherVersion 71 stales every recipe; one zero-request sweep settles it.

**Since matcher v74 (batch M74 — the brisket flats; matcherVersion 72;
prep50 design_v2 §2 M74, the owner's Q1, 2026-10-15: (b) for 0091, (a′) for
onion-braised, (a) keep for 0090; zero requests; shipped ALONE, a record
ruling; reach PRE-Q18 — both rules read a recipe's OWN steps).** Two rules,
2 rows:

(1, Q1 (b)) **A step's printed trim moves the 0" flat to the ⅛-inch flat.**
NEW `_trimsFatTo(recipe)` (read once per step index, `memo:trimsFatTo`): the
step (1-based) and depth of the first step sentence matching
`^\s*trim fat\b[^.]*\bbrisket\b[^.]*\bto (⅛|¼)[- ]inch\b` — read LINEAR
(`trimsFatSentence`: the substrings "trim fat", "brisket" and "inch" first;
then, in the sentence's first period-free piece, "trim fat" at its start, the
first "brisket" after it and the last depth after that — the regex's
`[^.]*` never crosses a period and its greedy capture is the last depth;
pinned against the regex). `trimDepthRecord` gains `{Recipe? recipe}`: when
the top is SR 168743 (flat, 0") and the LINE prints no depth, a step hit
moves SR 173128 *Beef, brisket, flat half, separable lean and fat, trimmed
to 1/8" fat, choice, raw* first (a hit in the line's own `beef brisket`
answer: zero requests). The corpus has exactly one such sentence: 0091 S1
"Trim fat on surface of brisket to ⅛ inch." (tacos-al-carbon's "Trim fat
deposits on steak to ⅛-inch thickness." names no brisket). `braisedKeptOf` deducts the 173128 pair (energy and the four fat
columns, M72's shares) on such a row with NO skim gate — the owner's ruling:
most of the 2 quarts of cooking liquid is never served. Flag (the corned
clause composed by the title):
`approximate (the steps trim the fat cap to ⅛ inch (step 1) — USDA's ⅛-inch
flat; its braised pair 173128 → 173130 keeps 67.6 % of the energy and 55.4 %
of the fat by the protein tracer — the fat that renders into the cooking
liquid, deducted (no step skims it: the steps serve 1 cup of the 2 quarts and
the broth the vegetables cook in, not counted); the steps cure and rinse the
brisket — the cure's sodium is not counted; a rinsed cure counts 0 g, CP9)`.
home-corned-beef-with-vegetables|0 "1 (4½- to 5-pound) beef brisket, flat
cut": 168743 → 173128, 2,154.56 g unchanged, row 3,641.21 → 5,989.68 kcal
gross, the pair deducts 1,940.46; recipe +408.02, 577.01 → 628.01 per
serving; fat 217.47 → 270.00 g. Its cure rows (salt, brown sugar, curing
salt, the cure's aromatics) stay `discarded` 0 g. The record carries no trans
fat (no 605), so the recipe's trans total (10.84 g, all the 0" record's) is
absent; its sodium and protein follow the record.

(2, Q1 (a′)) **onion-braised's 0" flat at its own braised pair.**
`braisedKept[168743]` = SR 168743 → SR 169440 *Beef, brisket, flat half,
separable lean and fat, trimmed to 0" fat, choice, cooked, braised* (both
hits in `beef brisket`): P 20.2 → 32.2, E 169 → 221, F 9.86 → 9.24 — energy
0.820354, fat 0.587883, saturated 0.617156, mono 0.523432, poly 0.537486
(169440 publishes no trans: it stays gross, as M72's). Gated by M72's
`_defatsLiquid`: S6 "Scrape off and discard any congealed fat from the
sauce, … skimming any fat on the surface with a wide shallow spoon". Flag `approximate (USDA's braised pair 168743 → 169440
(flat, 0" trim) keeps 82.0 % of the energy and 58.8 % of the fat by the
protein tracer — the fat the steps skim, deducted; the steps name a fat
layer the 0" record does not carry — the cap's depth is not printed)`.
onion-braised-beef-brisket|0 basis only (2,041.16 g, row 3,449.57 gross):
recipe −619.70, 692.11 → 588.82 per serving (3,532.95 / 6). A 0" flat
standing in for a cap its LINE prints (the ¼-inch fallback when the answer
loses 173128) stays gross — its flag says "counted as the 0-inch trimmed
flat" and no pair deducts.

**The invariant.** The deduction (`recomputeTotals`), the basis
(`gramBasisFor`, so the matches GET) and the GET's candidate sheet
(`candidatesForLine`, which now takes `{Recipe? recipe}` and is passed the
line's recipe) rank and gate with the SAME recipe: 0091's row, its flag, its
deduction and the sheet's first candidate are all 173128 (Run 047's class:
a sheet ranked without the recipe would lead with 168743).

Not moved, byte-equal: new-englandstyle-home-corned-beef-and-cabbage|6
(168743, its corned flag; S3 "skimming any scum" is no skim of fat —
`_defatsLiquid`'s `\bfat\b`), braised-brisket-with-pomegranate-cumin-and-
cilantro|0 (its line prints ¼": the line arm first; 794.35 per serving),
barbecued-whole-beef-brisket-with-spicy-chili-rub|10 (168664 at M72's share),
tacos-al-carbon-grilled-steak-tacos|4, every other row. A step-less 0091
(Q18) would not move.

Batch: 2 rows (1 record + kcal + basis, 1 basis-only); the ROW column
+2,348.47, RECIPE ENERGY −211.69 by the stored batches (+408.02 − 619.70;
−211.74 as per-serving × servings, the per-serving rounding); statuses,
holds, buckets and sections unchanged; 0 requests. Calibration moves AWAY
(design_v2 §3): a4 R02 home-corned +4.1 → +13.3 %, a4 R04 onion-braised
−5.9 → −20.0 %.

**Cost (RULE C).** The reader is one pass over the steps' sentences per
index (`memo:trimsFatTo`), substring tests first, then three anchored finds;
the design's `[^.]*` pair is quadratic on a sentence of repeated words —
pinned in `nutrition_v26_cost_test`: 30,000 seeded sentences agree with the
regex (3,616 of them hits), and 1,200 sentences of ≈ 1,000 characters in
each of two shapes ("trim fat" then "brisket" repeated with no "to";
"brisket to ⅛ inc" repeated) are read under 100 ms (the tree ≈ 3–5 ms, the
regex restored 226–311 ms). It is read only where the top is 168743 and the
line prints no depth (the compute, the GET sheet) or where a row sits on
173128 with no printed depth (the deduction, the basis). The cap shape —
0091's lines and 400 flat lines under 120 steps × 10,000 characters of "Trim
fat on the brisket brisket brisket, about 1 inch." (every sentence reaches
the finds; none prints a depth), and a loud variant whose S1 is 0091's real
sentence (every flat moves and deducts) — reads it once per index; measured
against matcher v73 (5 rounds of the base, the base with only the 168743
entry, and the tree, interleaved, 9 runs each, the means): compute +1.76 %,
the matches GET +1.87 %, a recompute +3.43 %, of which the 168743 entry alone
is +0.89 / +1.08 / +3.49 % — the step reader's own share +0.87 / +0.79 /
−0.06 %. The recompute's residual is M72's gate, now read for the shape's
168743 rows (every sentence names "fat"; one linear read per index, pinned by
count), not the new reader, which a quiet recompute never reads. The flags
join no list.

Known gaps: 0091 serves 1 cup of the cooking liquid over the meat and
"Moisten with additional broth" — that returned fat has no USDA share and is
not counted; onion-braised's cap depth is not printed (USDA publishes the
flat at 0" and ⅛" only; the steps name a fat layer) and its S6 "trimming and
discarding any excess fat, if desired" is not deducted; the corned
briskets' cure sodium (Q2 (c)); the flats' trans fat (169440 and 173128
publish none). Deploy note: matcherVersion 72 stales every recipe; one
zero-request sweep settles it.

**Since matcher v76 (batch M76 — eaten foods below the gate; matcherVersion
73; prep50 design_v2 §2 M76, the owner's Q3 (a) and Q4 (a); zero
requests).** Two rules, 2 rows and one new child section:

(1, Q3 (a); pD C1) **The yield-named own section — a new arm of A9.**
`yieldNamesOwnSection(line, item, section)`: an UNMARKED line (no "recipe(s)
follow(s)" / "this page" mark) WITH an amount whose reference item
(`referenceItemOf`) is the TAIL of one of the recipe's own section titles
(title = "<words> <item>", normalised: the item is the title's LAST whole
words — "Classic Sourdough" does not end in the item "dough", and "Classic
Pizza Dough for Grilling" holds "pizza dough" but does not end in it; since
matcher v91 (M87, above) also when the title's last two words are the last
two of an item of three or more — "Basic White Rice" ← "cold cooked white
rice") AND
whose amount is that section's
printed yield exactly (`parseShare(line.raw, line.amounts,
section.servings) == 1.0`) [re-point → `item`]. Read where A9 is read:
`namesOwnSection` (so `isReferenceIn`, the stale hash, the bulk parent test
and the child-section set follow) and the resolver's own-section list —
which the fix sheet's `own_section` group reads too ("in the resolution
order": the sheet lists the section the line routes to). A marked line keeps
v47's forms: barbecued-pulled-pork|4 "2 cups barbecue sauce (recipes
follow)" stays rule PO's (held `choose_recipe`, its two sauces listed). The
yield guard is what makes the tail safe: without it
simple-grill-roasted-turkey|0's turkey ("Gravy for Simple Grill-Roasted
Turkey", MAKES 6 CUPS) and fried-rice-with-shrimp-pork-and-shiitakes|10's
"1 cup bean sprouts" ("Fried Rice with Peas and Bean Sprouts", SERVES 4 TO
6) would read their sections; neither reads a share of the yield. The
corpus has exactly one such line: caramelized-onion-pear-and-bacon-tart|6
"1 pound pizza dough" (below the gate on FNDDS 2708008 *Dessert pizza*,
0.465, 0 kcal) → its own "Classic Pizza Dough" (MAKES 1 POUND; the prep
note: "you can use our Classic Pizza Dough (recipe follows), if
preferred"), share 1.0, 348.10 g, basis `from the recipe Classic Pizza
Dough: 348 g, 1,314 kcal`. The section becomes a child (sections 143 →
144) and its own rows appear: the flour "2 cups plus 2 tablespoons bread
flour (11½ ounces)" on SR 168913 *Wheat flours, bread, unenriched* at the
printed 11½ oz (326.02 g, 1,176.93 kcal — the item's left-over "plus 2
tablespoons" is stripped by the matcher), yeast FNDDS 2710005 3.55 g (11.53),
table salt 4.51 g, olive oil FNDDS 2710186 14.00 g (126.00), the water the
shipped rule row; the section 1,314.46 kcal, complete. The recipe goes
complete, 217.66 → 381.96 per serving (8). Not moved: the 22 marked dough
references; red-lentil-kibbeh|4's A9 harissa (equality, Harissa at 0.25).

(2, Q4 (a); pD C2) **Kasseri on provolone.** FDC holds no kasseri (its own
answer: processed cheese food, cream-cheese spreads, Monterey at 0.465, below
the gate). `_rankAs['kasseri cheese']` reads the cached `provolone cheese`
answer ranked as `cheese provolone` → SR 170850 *Cheese, provolone* (its
top; detail cached), `approximationRecords['kasseri cheese'] = 170850`, and a
`trimStandInFlagOf` arm for a line naming `kasseri` on 170850 [re-point →
`item`]: `approximate (FDC holds no kasseri — counted as provolone, the
larger part of the recipe's own substitute: 3 oz provolone with 1½ oz
Pecorino Romano for 4 oz kasseri)` (pastitsio's prep note prints the
substitute). pastitsio|23 "4 ounces kasseri cheese, shredded (1 cup),
divided": 2705720 (0.465, 0 kcal) → 170850 (1.0), 113.40 g, 398.03 kcal,
basis `from 4 ounce · approximation (counted as Cheese, provolone) ·
approximate (FDC holds no kasseri — …)`; complete, 403.16 → 469.49 per
serving (6). Not flagged: the 3 provolone lines on 170850 and the 29 Pecorino
Romano lines on 171249.

Batch (the replay of snapshot 27 against matcher v74's rows): 2 rows moved
and the new section's 5 rows; the ROW column +3,026.95 (the routed row
1,314.46, the section's rows 1,314.46, kasseri 398.03); RECIPE ENERGY
+1,712.49 by the stored batches (+1,712.38 as per-serving × servings, the
per-serving rounding); 2 recipes complete (1,047 / 151); buckets MAIN check
−2 / counted +2, SECTION counted +5, sections complete +1, routed sections
+1; holds unchanged; 0 requests. No step reader; the basis texts join no
list. No calibration recipe moves (design_v2 §3).

Cost (RULE C; v73 closers 3–5, verify3 D1, verify4 D2, verify5 D2): rule 1
is read for every (line × own section) of every `isReferenceIn` and every
resolve, so its per-line reads sit outside the per-section loop — the tail
(`endsWith`) first, on the title the caller has already normalised; then,
on the line's first tail hit, the mark (`isSubRecipeReference`, which
`namesOwnSection` has already read and hands over) and the line's own share
reads (`shareReaderOf` in salt_shared: `parseShare` curried, unchanged, its
written "(½ recipe" regex skipped on a raw without the word "recipe"); a
section's yield once per distinct servings string. A compute reads a
reference line through `isReferenceIn` AND the resolver's own list — six
reads of a routed line, up to five in a GET — so both per-line reads are
memoised per recipe instance (the mark by the raw, the share reader by the
raw and the amounts): ONCE per line and instance, a yield once per line,
instance and servings string. `namesOwnSection` and the resolver's list
normalise each title once. Counted (`memo:yieldMarks`,
`memo:yieldShareReaders`, `yieldServingsReads`; cost_bounds: once per line
and instance, a yield once per line, instance and servings string) and
pinned at the editor caps — 400 lines of 1,000 characters × 60 subsections
(nutrition_v26_cost_test) — including the ROUTING shapes, where every line
names an own section at its yield (one "Classic Pizza Dough" at MAKES 1
POUND: every line routed; sixty such titles: every line held): compute, GET
and recompute each read exactly 400 marks, 400 share readers and 400
yields. The memo keeps its own store, never the step index: the reads take
nothing from the steps, and a recompute reads its STORED copy's lines — a
memo on the step index built that copy's index, windowing every step, which
no v74 recompute does (≈ +22 ms, +9 %, of a recompute at the editor's step
caps). So every step builds v74's step indexes (compute and recompute one;
pinned EXACTLY on every yield cap shape). Measured against matcher v74
(medians of four base and four tree processes, ABBA twice, compute / GET /
recompute; fix76/closer5.md), at the 400 × 1,000-character lines × 60
subsections and again with the editor's 120 steps × 10,000 characters:
titles never ending in the item +0.5 / +0.1 / +0.4 %; every title ending
in it (MAKES 2 POUNDS) −0.6 / +1.6 / +2.9 % (+2.4 ms: its 400 share readers
and 400 yields), at the step caps −0.1 / +1.6 / +0.5 %. The routing shapes
route on the tree and not on v74 (v74 counts the line as its food: −55 /
+480 / +42 % on the same input, the GET's routed child read included), so
their base is v74's own A9-equality routed shape ("Pizza Dough", MAKES 1
POUND): one routing title +1.4 / +0.1 / +13.7 %, at the step caps +2.0 /
+0.8 / +3.4 %. STATED RESIDUALS, each pinned by count: that recompute's
+13 ms (+9 ms at the step caps) is its one mark per line
(`memo:yieldMarks` 400, ≈ 36 µs on a 1,000-character raw), which the
equality never reads; 60 DISTINCT yields under titles all ending in the
item +4.4 / −1.1 / +35.2 % (+29 ms; at the step caps +3.3 / +0.4 /
+11.3 %, +27 ms) — one yield read per (line, distinct servings string), each a
short servings string, never the raw (the base itself normalises every
title per line, the same order); 400 MARKED lines against titles ending in
their item +4.8 / +8.9 / +12.4 % (at the step caps +4.1 / +4.6 / +5.7 %)
— one mark read per line and instance. The tree before closer 3 read the mark
and the share's raw regex per (line × section): 7.6–14.7× base on these
shapes; closer 3's tree read a routed line six times a compute (the memo:
−7.2 / −3.0 / +0.8 % on the one-title routing shape, −4.2 / −1.1 / −3.1 % on
sixty).

Known gaps: the tart's line buys a ready-made pound of pizza dough — the
recipe's own homemade dough (the cook's option in its prep note) is what is
counted, no record of a bought pizza dough is cached; pastitsio's printed
substitute is a MIX (1½ oz Pecorino Romano with 3 oz provolone per 4 oz) —
only its larger part is counted (the mix by weight would be ≈ +13.6 kcal; no
stand-in reader builds a mix), and kasseri's own composition is unsourced in
FDC. Deploy note: matcherVersion 73 stales every recipe; one zero-request
sweep settles it.

**Since matcher v77 (batch M77 — extra-virgin olive oil's energy;
matcherVersion 74; prep50 design_v2 §2 M77, the owner's Q5 (a), 2026-10-15;
zero requests; shipped alone).** One record ruling. Foundation 748608 *Oil,
olive, extra virgin* publishes only NLEA fat (298 = 93.7 g per 100 g) and no
energy; it is not held (`publishesNothing`: 93.7 g of macros leave no room
for a missing one), so the totals priced it by Atwater, 9 × 93.7 = 843.3
kcal per 100 g, on every extra-virgin line (the 'extra-virgin olive oil'
answer holds 748608 alone — a rank-as cannot move the rows). Engine
`nutrientSiblings` now maps **748608 → SR 171413** *Oil, olive, salad or
cooking* (884 kcal, fat 100 g; its detail cached — the napa 2727583 → 169979
precedent): a row keeps its record, its confidence and its own grams (748608's
90.7 g per 100 mL — the fix sheet's portion stays that record's), and its
nutrients are 171413's — energy 884, fat 93.7 → 100 g per 100 g, saturated
15.4 → 13.808, mono 69.2 → 72.961, poly 9.07 → 10.523, plus what the
Foundation record lacks (sodium 2 mg, iron 0.56 mg, vitamin E 14.35 mg,
vitamin K 60.2 µg — the record, not a rule). The fix sheet's `kcal_per_100g`
reads 884. The basis names the sibling, `"1 tablespoon ≈ 15 mL · nutrients
of \"Oil, olive, salad or cooking\""` (v84: `· USDA portion`, the record's
own 100 mL) — and, new in v77, so does a
poured-off oil's kept part or a frying oil's uptake (the DISCARDED shape,
counted grams > 0: `"⅓ cup kept with the bacon grease (the steps pour off
the rest) · nutrients of \"Oil, olive, salad or cooking\""`), which named no
sibling before (no earlier sibling row was discarded); an amount-less row
counted 0 g keeps its text.

Reach on snapshot 27 (the v76 rows): 251 rows in 220 recipes (240 density,
5 discarded, 6 unmeasured at 0 g; 10 of them section rows), 11,437.63 g;
the rows' energy 96,452.47 → 101,108.04 (+4,655.57; ≈ grams × 0.407), and
the 5 routed parent rows that read a section holding one (Spicy Garlic Oil,
Orange Salsa with Cuban Flavors and Toasted Bread for Bruschetta at share
1.0, Black Olive Tapenade × 2/9, Harissa × 0.25) +70.45 — the row column
+4,726.02; recipe energy (stored batch energy over the 1,198 recipes)
+4,542.81 (the 5 unrouted section rows reach no recipe: roasted-fennel's
Orange-Honey Dressing "1 tablespoon extra-virgin olive oil" 114.72 → 120.26
moves its section page 165.67 → 171.21 and not the parent, whose "1 recipe
topping (optional)" is held, rule PO). 214 recipes and 10 sections move;
statuses, holds, grams, records and buckets unchanged; 0 requests. Not
moved: the 96 plain "olive oil" rows on FNDDS 2710186 *Olive oil* (900) —
**disclosed: the same food now 1.8 % apart (884 vs 900) instead of 6.3 %**;
SR 171413 is the analytical "salad or cooking" record and stands for extra
virgin (FDC prints no energy for the extra-virgin Foundation record). Not
mapped: the three other fat-only Foundation oils, 748278 canola, 1750348
peanut and 1750351 extra-light olive — no row sits on any of them. Deploy
note: matcherVersion 74 stales every recipe; one zero-request sweep settles
it (171413's detail is in the caches; a library without it fetches it once,
RULE A); the kcal digest moves by +4,543.51 of per-serving × servings energy.

**Since matcher v78 (batch M78 — the C4 recipes: the Parmesan crust and the
pan fat; matcherVersion 75; prep50 design_v2 §2 M78, the owner's Q6 (c) and
Q7 (c), 2026-10-15; zero requests).** Two rules on M52's coat plan
(`_m52Plan`). **The crust whole (Q6 (c), pB R-D1):** a nut or cheese coat
layer that no step names with a crumb (`_layerInCrumb` rejects it — a
pressed crust) counts its WHOLE line, outside the coat's budget (f, B and W
unchanged), its basis the line's own weighing and the flag `approximate (a
pressed cheese crust: no USDA record of a cheese crust, and the coat
record's breading does not describe one — the line counted whole as
printed; the part left in the dish is not deducted)` ("nut" for a `Nuts,`
record). Before v78 such a layer stayed held `coating`. Reach: one row —
parmesan-crusted-chicken-cutlets|3, held → 184.27 g on 325036 (+775.78
kcal; ¼ cup grated 14.175 g + 6 ounces 170.097 g), the recipe partial →
complete. **The pan fat in fat grams (Q7 (c), pC R-E4, F12 — a stand-in on
the owner's Q4 (b) record):** under C4 (a thin piece's sautéed dusting), a
step that pours off the fat with no kept part written (`\bpour off (?:the
|any )?(?:excess )?fat\b`) or wipes the skillet out (`\bwipe (?:out )?(?:the
)?skillet\b`) makes the fat lines a sauté heats — a frying fat or butter
line a sentence names after the first sentence that coats or dredges and
before the first such step (engine `_panFatLines`, once per step index) —
keep FNDDS 2705980's oil (`_breastBaked`: 2 g oil per 125.77 g raw breast,
1.5902 % of the coated raw food) as FAT grams: the kept fat is shared by
the lines' fat (each line's whole grams × its record's total lipid, 204, on
the record the totals read — a `nutrientSiblings` entry's), and each line
counts that one share of its whole grams, so an oil line's grams are its
fat's and a butter line's its fat ÷ 0.8111 (never more than the whole
line). Flag `approximation (pan fat: 1.59 g fat per 100 g of the raw
<food> — USDA FNDDS 2705980 recipe: 2 g oil per 125.77 g raw chicken breast
(no record for the fat a sautéed piece keeps; the steps pour off / wipe out
the rest)[; a butter line weighed by its own fat])`, after the basis
`discarded in cooking — only the fat the sautéed food keeps counted`. A
line the engine reads as a discarded medium (a frying oil, whose uptake
rule the fryer pass applies) is never a pan line — on the corpus 0042|7,
0114|5, 0115|4 and 1133|8/|9 sit in a pour-off window and keep that rule —
so a pan line's medium bit is read nowhere and M52's plan key reads it on
its line, record and hold only. A person's Confirm of a pan line is the
plan's grams, as a confirmed coat's is (saltimbocca|5 stays 9.92 g
`discarded` on the row and the GET); a pan row the plan stops covering —
the only coated food skipped — returns to its whole line at the recompute
(parmesan-crusted|6 18.14 g, meunière|3 / |4 28.00 / 28.36 g). Reach: 6
rows in 4 recipes —
chicken-saltimbocca|5 56.00 → 9.92 g, fish-meuniere|3 28.00 → 5.44 g and
|4 (butter, 81.11 % fat) 28.36 → 5.51 g (an oil reading would give 4.99),
parmesan-crusted|6 18.14 → 6.76 g, and **chicken-francese|12 28.36 → 5.51 g
and |13 28.00 → 5.44 g**: 0420's S5 wipes the skillet after each batch
("Wipe out the skillet with paper towels.", twice); its sauce is S2's, made
in a saucepan from |0 (before the dredge, so |0 stays whole) — the design's
"francese (the fat makes the sauce)" misread it (the orchestrator's ruling (a)
of 2026-10-18 under the 2026-10-07 standing authorization: the mechanism's
reach, never a gate fitted to a calibration). Per serving:
parmesan-crusted 171.67 → 340.01, saltimbocca 511.56 → 407.88, meunière
349.73 → 258.01, francese 438.34 → 346.62. 7 rows in all; the ROW column =
RECIPE ENERGY −475.11 (the design's five −108.23 — its −108.10, 184.28,
5.45 / 5.52 and 258.03 add rounded parts; the engine sizes the meunière
budget at the unrounded 9.918 g); +1 complete, holds −1 (coating 15 → 14);
0 requests. Not reached: piccata and next-level piccata, both marsalas
(no pour-off, no wipe), every non-C4 pour-off (the C4 gate), meunière|5's
browned butter (its own mention is the wipe sentence), saltimbocca|8 (after
the pour-off). **Gaps, disclosed:** the grated ¼ cup S2 whisks into the
flour dredge counts whole with the crust (≤ 32 kcal over at C4's f; the
line's two amounts split by part waits for the structured fields); a baked
breast record's oil read for a pan's kept fat (a stand-in on a stand-in,
flagged); calibration moves (§0.7, never fitted): saltimbocca +27.7 → +1.8 %,
parmesan-crusted −42.0 → +15.0 %, **meunière +18.6 → −12.5 %** and
**francese −1.3 → −21.9 %** (both now under their hand counts — francese's
earlier −1.3 % was partly the whole frying fat offsetting its double dredge
read at Q4 (b)'s 3.18, a gap §2 keeps); the 17 thick crust parts at the
read k pending M80; the thick dustings held; the `fat > 0` guard (no line's
fat read) has no reach — the one cached fat record with no 204, 748608,
reads its sibling. COST (RULE C): `_panFatLines` is memoised once per step
index (`memo:panFatLines`) and reads each fat line's mentions once
(`panFatLineReads`); the regexes are fixed alternatives (linear). The v26
cap shapes (saltimbocca's lines + 389 × "4 tablespoons olive oil", 120 ×
10,000-character steps) pin, EXACTLY on every path, one index, the reader
once and — on the TRUE path, where every oil line is a pan line weighed at
0.03 g — 391 line reads (quiet: none). Timing vs the v77 tree d1cf094 (8
ABBA processes × 3 timed reps, medians; closer 1): quiet +0.82 / +0.82 /
+0.92 % (compute / GET / recompute) — within ±2 %; the TRUE path +5.4 /
+4.6 / +23.2 % (+45 / +31 / +118 ms) — STATED RESIDUAL: the plan weighs
390 pan lines (each line's record and whole grams), work the base never
does on this shape (the oil lines are counted whole there); linear and
count-pinned (the M71 precedent). Deploy note:
matcherVersion 75 stales every recipe; one zero-request sweep settles it;
the kcal digest moves by the 4 recipes' per-serving × servings energy.

**Since matcher v79 (batch M79 — records read in L50: stand-ins and
siblings; matcherVersion 76; prep50 design_v2 §2 M79 as the planner's
report corrects it — plan_figures.md C0–C13 and the closer's CC5–CC9 —
under the orchestrator's rulings Q9 (a) at option A, Q9 (b) HOLD and Q10
(b′), 2026-10-18; zero requests; replayed on snapshot 28).** Three rules,
each on shipped maps plus, for the racks, one NEW map and one NEW step
reader. **Crystallized ginger (Q9 (a)):** FDC holds no crystallized
ginger — the lines' own 'crystallized ginger' answer leads with the raw
root 169231 at 0.462, below the gate (0 kcal, the recipe partial) and
never holds SR 167781 *Candied fruit* (322 kcal; its detail read at L50,
no portion), which sits in the cached 'candied ginger' answer (index 22).
Matcher `_rankAs['crystallized ginger']` reads that answer under the words
'candied fruit'; `approximationRecords` flags it (`· approximation
(counted as Candied fruit)`), and engine `trimStandInFlagOf` adds
`approximate (FDC holds no crystallized ginger — a stand-in by class: SR
167781 Candied fruit (322 kcal); weighed at a Branded label's ¼ cup of the
product as sold, 30 g — FDC Branded 2132938 and three others; nine ¼-cup
labels print 28–50 g, every printed volume 0.47–1.01 g/mL)`. Grams (the
owner's Q11 standing rule — a label's grams for a printed volume): grams
`_densities` 'crystallized ginger' = 30 / (0.25 × 236.588) = 0.50721 g/mL,
the modal and median of the nine ¼-cup labels L50 #8 read (28, 28, 30 × 4
— 2132938 CIBO VITA, 2106313 Sugar 'N Spice, 1900068 Tree of Life, 1981078
Price Chopper — 40, 40, 50 g), named in the basis (`approximate
(crystallized ginger labels (…): ¼ cup = 30 g)`); longer than 'ginger'
(the fresh root's 0.54), so it wins; one figure per key, so the ½-cup line
is not read at the ⅓-cup label (41 g; that option B would be +8.05 kcal).
Reach: carrot-ginger-soup|2 ¼ cup 30.00 g / 96.60 kcal, cranberry-chutney…|9
⅓ cup 40.00 / 128.80, gingerbread-layer-cake|22 ¼ cup (optional — counted;
`_optionalLine` reads reference lines only) 30.00 / 96.60,
triple-berry-slab-pie…|3 ½ cup 60.00 / 193.20 (each was 169231, below the
gate, 0 kcal); +515.20; the four recipes partial → complete (136.91 →
153.01, 428.70 → 471.63, 723.55 → 731.60, 458.11 → 468.84 per serving).
**Candied peel (Q9 (b)) is HELD** — no record, label or portion prints a
volume of the candied product: stollen|6 / |7 (½ cup candied lemon / orange
peel on the raw peels 167749 / 169103, 48 g each) and
struffoli-neapolitan-honey-balls|11 (2 tablespoons, 12 g) are unchanged;
not taken: on 167781 gram-less −80.76, at the raw peels' grams +267.00
(`volumeSiblings[167781] = 169103` would carry it — a raw peel's volume is
not the candied product's), at the ginger label +353.94.
**The seedless watermelon (pD C7; the napa 2727583 → 169979 precedent, in
BOTH sibling maps):** Foundation 2747675 *Watermelon, seedless, flesh only,
raw* publishes no energy and no portion (held `no_nutrients`, no grams);
engine `nutrientSiblings` and grams `volumeSiblings` map it to SR 167765
*Watermelon, raw* (30 kcal; L50 #3) — the row keeps 2747675, its nutrients
are 167765's and its cups are 167765's two cup portions ('cup, diced' 152 g,
'cup, balls' 154 g: "pieces" names neither, so their median, 153 g).
watermelon-salad-with-cotija-and-serrano-chiles|5 "6 cups 1½-inch seedless
watermelon pieces" → 918.00 g, 275.40 kcal, basis `6 cup · USDA portion of
"Watermelon, raw" · nutrients of "Watermelon, raw"`; 154.42 → 223.27 per
serving, partial → complete. Either map alone leaves 0 kcal (the nutrient
map alone: gram-less; the volume map alone: 918 g but held).
**The racks of lamb (Q10 (b′)):** both rack lines (0228 roast rack, 0622
grilled rack — each recipe's prep note: "We prefer the milder taste and
bigger size of domestic lamb") read their own 'racks of lamb' answer,
imported racks only (NZ 172641; 0228's printed "fat trimmed to ⅛ to ¼ inch"
moved it to the Australian 174414, v54). Matcher `_rankAs['racks of lamb']`
reads the cached 'lamb rib separable lean and fat choice raw' answer (L50
#6: 174321 ¼" HIT, 174377 ⅛" DETAIL, 172493 lean-only HIT); '1/8"' and
'1/4"' are no words, so FDC's order puts the HIT 174321 first (the
planner's C7 — a weight read on it would fetch its detail), and engine
`trimDepthRecords` gains a third, APPENDED entry, `\btrimmed\b` →
{174321: 174377} (both lines print "trimmed"; appended because
`trimStandInFlagOf` and `braisedKeptOf` read the FIRST entry's depth
phrase), moving SR 174377 *Lamb, rib, separable lean and fat, trimmed to
1/8" fat, choice, raw* first at the top's confidence before any weight
read — 0 requests; the v54 172641 → 174414 move no longer fires on these
lines. Grams unchanged: grams `ah102Meats[174377]` carries AH-102 item
1364's row verbatim (73 %, as 172641 / 174414 do): 2 × 850.485 × 0.73 =
1,241.71 g, 2 × 737.087 × 0.73 = 1,076.15 g. The drippings (§0.3's
dry-heat clause; the planner's C8 — a record-keyed `braisedKept` entry
holds one pair and reads M72's skim gate, which neither rack prints): a
NEW cooking-keyed map engine `dryHeatKept` = {174377: {roasted → SR 172552,
broiled → SR 174378}}, each column's share by the protein tracer from the
snapshot-28 records (the 174377 DETAIL: E 342, P 15.32, F 30.71, sat 13.43,
mono 12.6, poly 2.42; the HITS 172552: 341, 21.8, 27.5, 11.7, 11.6, 1.99 and
174378: 340, 23.1, 26.8, 11.4, 11.0, 2.17; no trans on any): roasted energy
0.700697, fat 0.629296, sat 0.612226, mono 0.646978, poly 0.577883;
broiled 0.659325, 0.578764, 0.562958, 0.578987, 0.594691. It is read
through `braisedKeptOf` (a `dryHeatKept` record first) by the ONE
`recomputeTotals` arm — energy and the four fat columns never part;
protein, sodium and cholesterol stay gross — and the cooking is the NEW
step reader `_dryHeatOf` (`memo:dryHeat`, once per step index, the index's
lower-cased sentences by step; pre-Q18 a section reads its own steps):
'broiled' when a sentence matches `\bheat (?:the )?grill\b`, else 'roasted'
when one matches `\bheat (?:the )?oven\b` AND one pours off fat (the
design's `\bpour off\b[^.]*\bfat\b`, read as two finds in each period-free
piece — the same answer, linear; `pourOffFatSentence`), else none (gross).
§0.3 rulings on the steps: 0228 ROASTED (S1 "heat oven to 250 degrees",
the racks on a wire rack over the sheet; S3 "Pour off all but 1 teaspoon
fat from skillet" — the sheet's drippings and the skillet fat never reach
the plate); 0622 BROILED (S1 "Heat grill until hot"; S3 "fat has begun to
render"; nothing is made from the drippings). The flag (the deduction, the
basis and the GET sheet read the same recipe — M74's invariant):
`approximate (USDA's domestic choice rib at ⅛", unfrenched — the recipe
prefers domestic lamb; its roasted pair 174377 → 172552 keeps 70.1 % of the
energy and 62.9 % of the fat by the protein tracer — the drippings,
deducted; the frenched bones' trim not deducted)` (broiled: 174378, 65.9 %
and 57.9 %); with no cooking printed (or no recipe asked) `… the recipe
prefers domestic lamb; counted gross (no step prints the cooking))`.
Reach: roast-rack-of-lamb-with-roasted-red-pepper-relish|0 2,942.85 →
4,246.64 kcal gross, deducting 1,271.03 (fat 381.33 → 239.97 g kept): +32.76
recipe energy, 878.57 → 886.76 per serving; grilled-rack-of-lamb|5
1,818.69 → 3,680.42 gross, deducting 1,253.83 (fat 330.48 → 191.27 g):
+607.91, 498.95 → 650.93; both stay complete. **Disclosed (§0.7):** the
racks are the only dry-heat rows with a drippings deduction (the gate
answers broiled for 102 corpus recipes and one section, roasted for 26 —
but only a row on 174377 reads it); the frenched bones' trim (a frenched rack
yields less than AH-102's unfrenched 73 %) is not deducted.
ROW column +3,956.12 (7 rows: the ginger +515.20, the watermelon +275.40,
the racks +3,165.52 gross); RECIPE ENERGY +1,431.27 by stored batch energy
(+1,431.21 as per-serving × servings); +5 complete (holds `no_nutrients` −1);
0 section rows, 0 requests. Not moved (byte-equal): the 101 other rows on
169231 (fresh ginger, the galangal rank-as), the 15 ground-ginger rows on
170926, pumpkin-pie|6's candied yams on 170071 (its 'candied yams' answer
also holds 167781; its rank words keep the yam), struffoli|12's candied
cherries (167563, gram-less), the peel and zest rows on 167749 / 169103,
every other sibling row, the ten other lamb rows (four of them print
"trimmed" on a top that is not 174321 — the appended entry's key), every
`braisedKept` row. COST (RULE C): `_dryHeatOf` is memoised once per step
index (`memo:dryHeat`) and read only for a row on a `dryHeatKept` record;
its three tests are linear (the two heat regexes have no `[^.]*`; the
pour-off test is two finds per period-free piece — a 30,000-sentence fuzz
equal to the design's regex; on "fat" then "pour off" repeated — the v26
group's own hostile shapes — the tree reads one sentence of 1,000 / 10,000
/ 100,000 characters in ≈ 1–4 / 7–11 / 64–91 µs, at most ×10 per ×10
characters — linear; the 1,000-character read carries the call's fixed
cost — where the regex takes ≈ 249–265 µs / 21–22 ms / 1.9–2.1 s, ×80–97
per ×10 — quadratic: warm medians and the v26 pass run cold in a fresh
process, by the closer and three verifiers; a pass of the v26 loop reads
≤ 5 ms on the tree and ≥ 290 ms on the restored regex). The v26 cap
shapes (0228's lines +
391 rack lines on 174377, 120 × 10,000-character steps naming a grill, an
oven, a pour-off and fat that match none — quiet — or ending in 0622 S1's
grill sentence or 0228's oven and pour-off sentences — the TRUE paths) pin,
EXACTLY on compute, GET and recompute, one index and the gate once. Timing
vs the v78 tree de8fa1b (ABBA × 2 rounds, 4 processes a side × 5 timed
reps, medians): compute −30.0 / −30.1 / −28.9 % and GET
−39.3 / −40.5 / −38.1 % (quiet / broiled / roasted) — the racks rank a
3-record answer instead of the 14-record 'racks of lamb' one —; recompute
(measured again by the closer, verify1 D4: ABBA × 4 rounds, 9 timed reps a
process, medians) +4.1 / +0.5 / +6.5 % (+12 / +2 / +19 ms; the verifier's
3 rounds: +5.2 / +1.8 / +7.1 %, +15 / +5 / +21 ms). STATED RESIDUAL: the
quiet and roasted recompute exceed ±2 % by the gate's own scans — the gate
alone reads 11.6 / 5.8 / 18.7 ms on these steps (two, one or three full
scans of 16,560 sentences) — 3.9 / 2.0 / 6.3 % of the base recompute
(1.2–2.4 % of its compute and GET), work the base never does on this shape
(no row on 174377 there); linear and count-pinned (the M71 / M78
precedent). Deploy
note: matcherVersion 76 stales every recipe; one zero-request sweep settles
it (the three details and the rank-as answer are in snapshot 28's caches; a
library without them fetches each once, RULE A); the kcal digest moves by
the seven recipes' per-serving × servings energy.

**Since matcher v80 (batch M80 — coats read in L50; matcherVersion 77;
prep50 design_v2 §2 M80 as the planner's report corrects it —
plan_figures.md C10–C13 and the closer's CC1–CC4, CC7, CC10, CC11 — under
the orchestrator's rulings Q11 (b) and the crumb-crust k 12.12, 2026-10-18;
zero requests; replayed on snapshot 28).** Two coat figures, each a read
FNDDS recipe on `_coatFigure`'s C2 shape (p3's method: the breading's
carbohydrate per 100 g of the RAW coated food); R-G1 is not built.
**The onion rings (Q11 (b), pB R-D2):** L50 #7 ("onion rings") returned
only restaurant products — no raw-ring recipe — so engine
`_coatVegetables` gains 'Onions,' and `_coatedVegetable` sizes the coat
from the largest counted onion row a coating sentence names (0315 S2
"dredge each onion ring in the flour"), only where no meat is coated and
only at C2; `_coatFigure`'s onion arm reads FNDDS 2710042 "Fried
cauliflower", the only USDA coated vegetable with a separable coat: 50 g
breading × `_breadingCarbPerGram` 0.40 (every shipped k's) per 39.58 g raw
cauliflower = **50.53** g carbohydrate per 100 g of raw onion (pB's 50.66
read 0.401 — the planner's C13). The flag names the stand-in by its read
food: `approximation (coat: 50.53 g carbohydrate per 100 g of the raw
onions — USDA FNDDS 2710042 recipe: 50 g breading per 39.58 g raw
cauliflower (no record for onions; read as Fried cauliflower); the
dredge's excess not counted)`. The engine's own split (the margins
disclosed): B = 50.53 × 300 g / 100 = 151.59 g; the parts |0 (the flour's ¼
cup in the dish — the ¼ cup S1 whisks into the buttermilk is its eaten part,
counted whole on top, never a dip line), |6 saltines and |7 chips carry
143.72 g → f = 1 (margin 5.5 %); the dips |1–|5 weigh 176.04 g whole against
W = 1.173 × B = 177.82 g → share 1 (margin 1.0 % — fragile: read as a dip,
the flour's eaten 30.16 g would make it 0.862). Reach:
oven-fried-onion-rings|0 30.16 g held → 60.33 g / 220.81 kcal, |1 egg 50.00
/ 74.00, |2 buttermilk 122.00 / 52.46, |3 salt 3.01 / 0.00, |4 black pepper
0.58 / 1.46, |5 cayenne 0.45 / 1.43, |6 30 saltines 90.00 / 376.20, |7 4 cups
chips 100.00 / 532.00 (each held `coating` before, 0 kcal); ROW +1,258.36,
RECIPE ENERGY +1,258.35; 217.50 → 532.09 per serving; partial 2/10 →
complete; the `coating` hold −8. |8 onion 300 g and |9 oil 84 g unchanged.
A FRIED coated onion stays held (`_coatedVegetable` returns only at C2).
Since M80 the corpus holds no dip of a coat held with no budget (the six
`coating` holds left — skillet-chicken-and-rice, maple-glazed, salmon steaks
— have none), so M62 H is pinned on a stated synthesized fried copy of 0315.
Disclosed (§0.1): the auditors' ≈ 879 kcal on these lines is judgment, not
a figure.
**The crumb-crust k (pB R-F1; the orchestrator's 12.12, closer CC4):** L50
#4 read FNDDS 2706442 "Chicken or turkey parmigiana", which lists RAW
chicken and its breading as SEPARATE inputs; by `sequenceNumber`: 1 raw
chicken breast 510.3 g · 2 salt 3 · 3 flour 31.25 · 4 egg 100 · 5 dry crumbs
81 · 6 mozzarella 170 · 7 tomato sauce 425.25 · 8 grated Parmesan 18.75 · 9
oil 42 · 10 raw chicken breast "with added solution" 170.1 — the breading run
3 → 4 → 5; the Parmesan follows the mozzarella and the sauce, a topping, not
read (the eggplant read takes its batter only too). k = (81 × 71.98 % [SR
174928, the crumbs input's record] + 31.25 × 77.3 % [Foundation 789890, the
flour's]) / 680.4 × 100 = 82.46 / 680.4 × 100 = **12.12**; the egg is the
wash, sized by W (100 g per 82.46 g of the dredge's carbohydrate = 1.21; W
1.17). Engine `_parmigiana` (b 112.25 = the crumbs and flour, o 42, r 680.4)
is read by `_coatFigure`'s NEW arm after the legs arm — C2, a chicken, and
`crumbCrust`: a coat part the budget shares on a `Bread,` record (dry
crumbs, panko, sandwich bread); `nutCrust` — one on a `Nuts,` record — makes
it a stand-in. `_m52Plan` reads k AFTER its parts loop (closer CC11): the two
tests read the parts the budget shares under the loop's own filters, never
the line list — a person's typed grams on the crumb line leave the rest at
C2's 3.18. The budget, f and W are unchanged (since matcher v88, M88, the
parts on this read share two budgets of their own — the flour parts f_d by
carbohydrate, every other part f_c by dry-crumb mass — not the one f; B and
W unchanged). The flag at v80 (re-worded by matcher v88, M88 — see that
section): `approximation (coat:
12.12 g carbohydrate per 100 g of the raw chicken breast — USDA FNDDS
2706442 recipe: 112.25 g crust (81 g dry crumbs and 31.25 g flour as
separate inputs; 82.46 g carbohydrate; the record's 18.75 g grated Parmesan
follows its mozzarella and sauce — a topping, not read) per 680.4 g raw
chicken; the dredge's excess not counted)` and, beside a nut crust, `… per
680.4 g raw chicken (no record for a nut crust; read as FNDDS 2706442's
crumb crust); …` (engine `_coatFlag` reads the figure's stand-in on this
read — its first-word test sees 'chicken' on both; closer CC1 — gated on
2706442 so the onion keeps its own stand-in text). FNDDS 2706445 "Chicken
kiev" lists ONE coated input (butter 9.7 g + a fast-food fried breast 90.3
g): nothing is read off it. Reach (f / the dip share stay below 1: lighter
0.678 / 0.916, kiev 0.694 / 0.779, stuffed 0.603 / 0.887, nut-crusted 0.577
/ 0.701), grams and kcal: lighter-chicken-parmesan|0 panko 15.78 → 60.16 g
(62.33 → 237.63), |2 Parmesan 5.04 → 19.22 (21.22 → 80.92), |3 flour 10.73 →
40.91 (39.27 → 149.73), |6 egg whites (dip) 23.79 → 90.69 (13.08 → 49.88);
chicken-kiev|7 bread 20.38 → 77.68 (54.21 → 206.63), |11 flour 21.96 → 83.69
(80.37 → 306.31), |12 eggs 30.67 → 116.88 (45.39 → 172.98), |13 Dijon 1.06 →
4.03 (0.65 → 2.46); stuffed-chicken-cutlets-with-ham-and-cheddar|10 flour
14.32 → 54.59 (52.41 → 199.80), |11 eggs 23.26 → 88.67 (34.42 → 131.23), |13
bread 17.73 → 67.57 (47.16 → 179.74); nut-crusted-chicken-breasts (the
flagged stand-in)|2 almonds 21.66 → 82.55 (125.41 → 477.96), |5 panko 8.96 →
34.14 (35.39 → 134.85), |9 flour 18.28 → 69.65 (66.90 → 254.92), |10 eggs
27.60 → 105.19 (40.85 → 155.68), |11 Dijon 1.90 → 7.26 (1.16 → 4.43), |12
pepper 0.11 → 0.41 (0.28 → 1.03). Per recipe (ROW / RECIPE ENERGY by stored
batch energy): lighter +382.26 / +382.25 (235.26 → 298.97 per serving), kiev
+507.76 / +507.75 (540.19 → 667.12), stuffed +376.78 / +376.77 (544.51 →
638.71), nut-crusted +758.88 / +758.88 (385.84 → 575.56); all four complete
before and after. Bounds (closer CC2 — R-F0's column holds the crust parts
only): lighter panko + Parmesan +235.00 ≤ 386.2, kiev bread +152.42 ≤ 243.7,
stuffed bread +132.58 ≤ 250.7, nut almonds + panko +452.01 ≤ 900.8; the
flour dredge and the dips scale with B outside it; the true whole bound
(every part and dip counted whole, less today) lighter +609.16, kiev
+784.08, stuffed +643.14, nut +1,462.99 — every recipe inside. Not taken:
the Parmesan read as crust (12.46; +77 kcal on the four), the egg in k
(12.26). **R-G1 (Q12) is not built:** FNDDS 2710065 "Vegetable tempura"'s
batter is tap water 474 g, flour 312.5 g and egg yolk 51 g — no beer or
spirit, so FDC prints nothing on ethanol in a fried batter either way; Q8
(b) stands (85 % kept) and −276.81 kcal stays unbuilt (shrimp-tempura|4
vodka −206.27, fish-and-chips|10 beer −38.39,
crispy-fish-sandwiches-with-tartar-sauce|10 beer −32.15).
M80 in all: 25 rows (the onion rings' 8, the three crumb recipes' 11,
nut-crusted's 6), ROW column +3,284.04, RECIPE ENERGY +3,284.01 by stored
batch energy; +1 complete (1,053 → 1,054); the `coating` hold 14 → 6; 0
section rows, 0 requests. Not moved (byte-equal): eggplant-parmesan|2 |3
(its own arm), buffalo-cauliflower-bites|4 |5 |6 |10 and
vegan-baja-style-cauliflower-tacos|7 |12, every recipe with an onion row
beside a coated meat (skillet-chicken-and-rice — its thick dusting still
held —, stuffed-chicken-cutlets|1, maryland-crab-cakes|1,
chicken-fried-steaks|9: the meat stays the coated food),
easier-fried-chicken|8 (C2 with no crumb part, 3.18), every C4 row and M78's
pan rows, crunchy-baked-pork-chops|2, crunchy-oven-fried-fish|0 and
oven-fried-chicken|8 (their arms come first), the C1 crusts (almond-crusted,
breaded-chicken-cutlets, chicken-katsu, chicken-schnitzel, pork-schnitzel).
COST (RULE C; no new step reader): 'Onions,' widens two existing reads — the
plan's coated vegetable (a meatless recipe with a held coat) and `_m52Key`'s,
which reads the coated vegetable whatever the coats (kcal-neutral — a key
changes only where the food turns non-null). Closer CC7's 122 meatless
recipe groups with a counted onion are CANDIDATES: `_m52Key` runs only
through `_m52Stored` and the confirm path, i.e. for a recipe with a coat,
frying-oil, batter, dip, cut, kept or pan row. Measured over all 1,342 keys
against 2cf977a (a fresh recipe instance per path — the step index lives on
the instance): the naming memo is newly read by 4 GETs
(oven-fried-onion-rings, falafel,
pakoras-south-asian-spiced-vegetable-fritters,
crispy-tempeh-with-sambal-sauce), 1 compute and 1 recompute (the onion
rings), each once, no key more often than its step indexes
(nutrition_v80_test pins the onion rings' and falafel's three paths).
The v26 cap shapes pin it: ONION (0315 + 390 ring lines under 120 ×
10,000-character steps — the TRUE path, the coat and dips budgeted) and
ONION QUIET (0570 falafel's 17 lines, its frying oil among them, + 383
onion lines under steps that coat nothing — the GET's key reads the memo,
false), ONION's three paths and QUIET's GET each reading
`memo:coatNamed` within 1..copies, QUIET's compute and recompute never (0,
pinned), every family bounded. Timing vs the v79
tree 2cf977a (ABBA × 2 rounds, 4 processes a side, 5 timed computes / GETs
and 9 recomputes a process, medians): QUIET compute +1.3 %, GET +0.4 %,
recompute +0.1 %; the eggplant shape (a coated vegetable before and after)
+0.4 / 0.0 / +0.3 % — within ±2 %. STATED RESIDUAL: the ONION shape +11.2 /
+10.4 / +22.9 % (+123 / +114 / +110 ms) — the shipped coat and dip block's
own reads of the steps on a recipe the base holds unbudgeted (constant in
the line count: recompute +105 / +100 / +110 ms at 100 / 200 / 400 lines,
one plan each), work the base never does on this shape; count-pinned by the
cap shape (the M71 / M78 precedent). The crumb test reads the plan's own
parts list (no new pass). Deploy note: matcherVersion 77 stales every recipe; one zero-request
sweep settles it; the kcal digest moves by the five recipes' per-serving ×
servings energy.

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
`_skinlessRecords`) at 584's meat 65 %; a Confirm records 2727569. All
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

**Scallions (Y9, `_scallionPartOf`)**: a COUNTED scallion (FNDDS 2709794,
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
(325036; since matcher v87 → `cheese parmesan hard`, SR 170848); `new
mexican pods` (reads `ancho pods`) → `peppers ancho dried`
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
as bacon, Asiago as Parmesan (since matcher v87 a rank-as read of the
`parmesan cheese` answer, on SR 170848), whole allspice berries as ground allspice, lime
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
Montasio or aged Asiago as Parmesan (325036; since matcher v87 SR 170848
"Cheese, parmesan, hard"), New Mexican pods as dried
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
| `child` with no `share`, on a line whose share of that recipe the route cannot read (its yield; v81 F15: an amount-less line not served with reads rule WB's whole batch, 1.0) | `No share the yield can read — set the share.` |
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
| `section` with no `share`, the section's yield gives none (a bare count of 1 reads one; v81 F15: so does an amount-less line not served with) | `No share the yield can read — set the share.` |

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
v81 (F16, review Run 066's Opus critic): `failed` counts recipes too — a
section's failure moves no count, its log line names the section (in the
per-recipe job as in a sweep: it was logged under the recipe's id), and
each parent of it in the job fails with it ("still stale after 3 compute
passes"); a job stopped at a section by a provider failure logs `stopped at
{host slug} · {title}: …` with `status` `failed`.

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
