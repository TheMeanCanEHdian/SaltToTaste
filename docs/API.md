# SaltToTaste API (v1)

Base path: `/api/v1`. All responses are JSON unless noted. Updated in the
same commit as any endpoint change (see CLAUDE.md).

**Status:** P1 — read-only surface, no authentication yet (auth, roles, and
personal access tokens land in P3; this document will gain a Roles & scopes
section then).

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
  | `internal` | 500 | Unhandled server error (details only in server logs) |

- Timestamps are UTC ISO-8601 strings. Keys are `snake_case`.

## Endpoints

### `GET /healthz`

Liveness probe (outside `/api/v1`, no auth ever). → `200 {"status": "ok"}`

### `GET /api/v1/recipes`

Paged recipe cards, ordered by title (case-insensitive).

Query parameters:

| Param | Default | Constraints |
|---|---|---|
| `page` | 1 | integer ≥ 1 |
| `limit` | 24 | integer 1..100 |

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
nutrition lands), `favorite` (false until auth lands).

### `GET /api/v1/recipes/{idOrSlug}`

Full recipe document by canonical id (`atk-tv-2023-0857-rich-chocolate-bundt-cake`)
or slug (`rich-chocolate-bundt-cake`).

→ `200`:

```json
{
  "recipe": { /* full schema-v2 recipe document, snake_case */ },
  "source_slug": "the-complete-americas-test-kitchen-tv-show-cookbook-2001-2023",
  "hero_image_url": "/images/<source-slug>/<file>.jpg"
}
```

→ `404 not_found` when neither id nor slug matches.

### `GET /api/v1/recipes/{idOrSlug}/yaml`

The canonical schema-v2 YAML document.

→ `200`, `Content-Type: application/yaml; charset=utf-8`,
`Content-Disposition: attachment; filename="<id>.yaml"`.

### `GET /images/{sourceSlug}/{file}`

Recipe images from the library. Segments are strictly validated (no path
traversal; extension whitelist `.jpg` `.jpeg` `.png` `.webp`).

→ `200` with correct `Content-Type` and `Cache-Control: public, max-age=86400`;
`404 not_found` for anything else.

## CLI

`dart run salt_server:import <source-root> [--data-dir=PATH]` — bulk-imports a
Recipe Extraction source root (`source.yaml`, `recipes/*.yaml`, `images/`)
into the database and writes canonical v2 exports to
`<data-dir>/library/<source-slug>/`. Idempotent: unchanged recipes are
skipped by content hash. Exit codes: 0 ok, 1 failures occurred, 64 usage.
