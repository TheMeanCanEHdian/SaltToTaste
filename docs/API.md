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
`X-Requested-With: SaltToTaste` (bearer requests are exempt).

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
| `POST /api/v1/auth/recover` | `{recovery_code, username, new_password}` — no auth; code from `salt_server:recover` on the server host; resets/creates that account as an enabled admin and revokes its sessions + API tokens; rate-limited per IP (`423 locked`) |
| `POST /api/v1/auth/login` | `{username, password, remember?}` → `{token, user}` + cookie; failures are uniform `422 validation` |
| `POST /api/v1/auth/logout` | ends the current session (cookie/session bearer only) |
| `GET /api/v1/auth/me` | `{user: {id, username, role, must_change_password, scope, via}}` |
| `POST /api/v1/auth/change_password` | `{current_password?, new_password}` — current required unless a change was forced; other sessions are signed out |

### Account management

| Endpoint | Role | Notes |
|---|---|---|
| `GET /api/v1/users` | admin | all accounts |
| `POST /api/v1/users` | admin | `{username, role}` → `{user, temp_password}` (shown once); duplicate → `409 conflict` |
| `PATCH /api/v1/users/{id}` | admin | `{role? \| disabled?}`; never your own account |
| `POST /api/v1/users/{id}/reset_password` | admin | new `temp_password` (once), forces change, and signs out everywhere — every session AND every PAT, with the count returned as `revoked_tokens`. Not your own account (use change password). Revoking the PATs is deliberate: a PAT is its own credential, so a reset that only dropped sessions left an attacker's token frozen rather than gone, and it returned to full service the moment the user completed the forced change |
| `GET /api/v1/sessions` | any | own sessions; `current` flags this one |
| `DELETE /api/v1/sessions/{id}` | any | sign out one session (own only) |
| `GET /api/v1/tokens` | any | own PATs (prefix only) |
| `POST /api/v1/tokens` | any | `{name, scope}` → `{token, item}` — full value only in this response. Capped at 20 live tokens per user (`422` past the cap); revoke one to free a slot |
| `DELETE /api/v1/tokens/{id}` | any | revoke (own only) |

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
  | `csrf` | 403 | Cookie-authed mutation missing `X-Requested-With: SaltToTaste` |
  | `password_change_required` | 403 | Must change password before anything else |
  | `conflict` | 409 | Conflicts with existing state (e.g. duplicate username) |
  | `locked` | 429 | Login lockout; message says when to retry |
  | `internal` | 500 | Unhandled server error (details only in server logs) |

- Timestamps are UTC ISO-8601 strings with a `Z` suffix. Keys are
  `snake_case`.

## Endpoints

### `GET /healthz`

Liveness probe (outside `/api/v1`, no auth ever). → `200 {"status": "ok"}`

### `GET /api/v1/recipes`

Paged recipe cards — ordered by title, or by relevance (bm25) when `q` runs
a search.

Query parameters:

| Param | Default | Constraints |
|---|---|---|
| `page` | 1 | integer ≥ 1 |
| `limit` | 24 | integer 1..100 |
| `q` | — | search-DSL query (below), max 512 chars; parse errors → `422 validation` |
| `favorites` | — | `true` restricts the listing (and any `q` search) to the caller's favorites |

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
computed), `favorite` (the **caller's** favorite flag).

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
can safely update a single field. The slug is stable across renames (links
keep working); id, source identity, and extraction provenance are
preserved. Saving re-exports the canonical YAML; if the on-disk file had an
unsynced hand edit, that edit is preserved next to it as
`<id>.conflict-<timestamp>.yaml` (the save wins). → `200` detail body.

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
(content-type **and** magic bytes), size/time capped. → `201` detail body.

### `GET /api/v1/library` (admin)

`{"last_scan": {…} | null}` — the report of the most recent reconciliation
scan (also runs at every server start). Report fields: `started_at`,
`elapsed_ms`, `files_seen`, `updated_from_disk`, `added`, `re_exported`,
`skipped` (`[{file, reason}]`), `conflict_files`.

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
automatically before every recipe delete and daily; the newest 14 are kept.

### `GET | DELETE /api/v1/backups/{name}` (admin, full scope)

`GET` streams the archive (`application/gzip`, attachment). `DELETE` →
`204`. Names must match the strict backup pattern. The download requires
full scope even though it is a read: the archive contains the database
snapshot (credential hashes, private notes) — material no other endpoint
returns.

### `GET /api/v1/recipes/{idOrSlug}/yaml`

The canonical schema-v2 YAML document.

→ `200`, `Content-Type: application/yaml; charset=utf-8`,
`Content-Disposition: attachment; filename="<id>.yaml"`.

### `GET /images/{sourceSlug}/{file}`

Recipe images from the library. Segments are strictly validated (no path
traversal; extension whitelist `.jpg` `.jpeg` `.png` `.webp`).

→ `200` with correct `Content-Type` and `Cache-Control: public, max-age=86400`;
`404 not_found` for anything else.

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

### `GET /api/v1/recipes/{idOrSlug}/nutrition`

The computed per-serving label. → `200 {"status": "none"}` before the
first compute, else:

```json
{
  "status": "complete | partial | stale",
  "serving_basis": 12,
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

`low_confidence` counts auto-matched lines below 0.5 confidence that no
one has reviewed yet (confirm/override/skip clears one).

`computing_job_id` appears **only for admins, and only while a compute is in
flight** — it is the handle for re-attaching a reopened page to a running job
(see the compute endpoint below). It is omitted for members on purpose: the
job endpoint it points at is admin-only, so a member handed the id would
poll, get a 403 on every attempt, and surface a false error on a page they
cannot compute from anyway. It is also absent from the `{"status": "none"}`
body unless a first compute is currently running.

`stale` means the ingredients changed since the compute. The ~30-nutrient
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
fails (with the reason in its log) when no API key is configured.

### `GET /api/v1/recipes/{idOrSlug}/nutrition/matches`

Per-line match transparency: the stored decision (`fdc_id`,
`description`, `data_type`, `confidence` 0–1, `grams`, `gram_source`:
`weight` (direct) | `portion` | `density` (estimate) | `piece` (estimate)
| `override`, `status`: `auto | confirmed | overridden | skipped |
unmatched`) plus ranked `candidates` for re-picking. Candidates come
from the compute-time search cache only — reading this never spends the
FDC request budget. A stored decision whose line text changed since the
compute is reported as unmatched (`match: null`).

### `PUT /api/v1/recipes/{idOrSlug}/nutrition/matches/{pos}` (admin, full scope)

Override one line: `{fdc_id}` re-picks the food, `{grams}` hand-sets the
amount, `{confirmed: true}` blesses the auto match, `{skipped: true}`
excludes the line. Totals recompute instantly. `422` for `{grams}` on a
line with no matched food (there is nothing to scale — pick a food
first).

### `POST /api/v1/nutrition/bulk` (admin, full scope)

Start a background compute over every recipe without stored nutrition.
→ `202 {"job_id"}`; `409 conflict` while one is running. Failures land in
the job log — nothing is skipped silently. A job interrupted by a server
restart is marked `failed` at the next boot.

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
  `X-Frame-Options: DENY`.
- **Request bodies** must be sent as `Content-Type: application/json`; anything
  else is a `422 validation` envelope. This is a CSRF defence, not pedantry: a
  cross-site HTML form can only emit the three "simple" content types, and
  `enctype="text/plain"` can be shaped into a valid JSON document — so the
  unauthenticated endpoints (`/auth/login`, `/auth/setup`), which have no
  session for the `X-Requested-With` check to key on, had nothing else standing
  in front of them.
- **Env config**: `PORT`, `DATA_DIR`, `LOG_LEVEL`, `TRUST_PROXY`, `TRUSTED_PROXIES`,
  `SECURE_COOKIES`, `IMPORT_DIR`, `TZ` (container tzdata), plus the
  dev-only `DEV_ALLOW_CORS`.
- **Graceful shutdown**: SIGTERM/SIGINT (`docker stop`) drains in-flight
  requests (bounded), then closes SQLite cleanly — the WAL checkpoints
  and the next boot needs no recovery.
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
username/password, and `423 locked` once the per-IP rate limit trips.
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
