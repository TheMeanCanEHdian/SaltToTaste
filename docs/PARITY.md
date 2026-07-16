# Feature Parity — legacy Flask app → v2 (Dart/Flutter)

Audit performed at the P8 cutover (2026-07-15) before removing the legacy
`saltToTaste/` Python app. Every user-facing feature of the old app was
inventoried from its source (`views/`, `models.py`, `decorators.py`,
`configparser_handler.py`, templates) and verified against the v2
codebase (`apps/server`, `apps/app`, `packages/salt_shared`) by an
independent multi-agent verification pass plus a completeness critic.

**Result: full functional parity.** Every legacy capability is covered,
improved, or intentionally dropped per the approved rewrite plan. No
capability was lost by accident.

## Matrix

| Legacy feature | v2 status | Where it lives now |
|---|---|---|
| YAML files + SQLite cache + Whoosh index | **improved** | SQLite is the source of truth with canonical v2 YAML auto-export (`library_io.dart`); FTS5 (`migrations.dart`, `salt_database.dart`) replaces Whoosh |
| Recipe fields (title, image, source, times, tags, ingredients, directions, notes…) | **improved** | Schema v2 `Recipe` (`packages/salt_shared`): structured ingredients/steps keep the verbatim text, plus subsections/techniques/background. `calories` → computed nutrition (DB only) |
| Startup file→DB sync (add/update/remove) | **improved** | `scanLibrary` reconciliation (`library_scan.dart`): file-wins on clean edit, DB-wins on conflict (`.conflict-<ts>.yaml`), re-exports missing files |
| Login/logout + remember-me | **improved** | `auth_handlers.dart` sessions (7-day / 90-day sliding); multi-user admin/member + first-boot setup code + Argon2id + rate limiting; PATs |
| `authentication_enabled` off / `userless_recipes` anonymous browsing | **dropped (by design)** | The v2 app always requires authentication (security posture — no default-unauthenticated or anonymous mode) |
| Settings page (user, api key, backups, edamam, custom tags) | **improved** | Settings tabs: Account, Users, API tokens (PATs), Tags (Lucide styles), Library (backups), Nutrition (FDC key), Import |
| Home grid + tag search | **improved** | Responsive grid, title-sorted; free-text search DSL (`title:`/`tag:`/`ingredient:`/`calories:`… , and/or, phrases) replaces the taggle box |
| Recipe detail + nutrition | **covered** | `recipe_detail_page.dart` renders every field + the FDA-style USDA label |
| Download recipe YAML | **covered** | `GET /api/v1/recipes/{id}/yaml` (serves the canonical export; filename is `<id>.yaml`) |
| Image serving | **covered** | `GET /images/…` (path-contained; auth-required, `private` cache) |
| Add recipe (form + image) | **covered** | Structured editor; photos attach via a separate authenticated upload after first save |
| Update recipe (rename on title change) | **improved** | Editor update with merge semantics; ids/slugs are stable across renames (no file/image rename needed — links don't break) |
| Delete recipe (backup first) | **improved** | Delete backs up automatically (no toggle); image files intentionally kept (may be shared/hand-managed) |
| Nutrition (~30 nutrients + DV, Edamam) | **improved** | USDA FoodData Central (free) with per-ingredient provenance + the ~30-nutrient FDA panel |
| REST API (single api key) | **improved** | `/api/v1` with per-user PATs (read/full scopes); search via `?q=`; SSRF-guarded from-URL image |
| Backups (recipe/image/db, `backup_count`) | **improved** | Streamed tar.gz (library + DB `VACUUM INTO`); daily + pre-destructive; retention 14 |
| Custom tag styling (icon/color/bg) | **covered** | Tag styles with Lucide icons (`tags_tab.dart`, `PUT /api/v1/tags/{name}/style`) |
| `--datadir` CLI flag | **covered** | `DATA_DIR` env var (server) + `--data-dir` on the import CLI |
| `downloadImage` from imagecredit URL | **improved** | SSRF-guarded from-URL image endpoint (any URL, not just the credit field; credit preserved separately) |
| **Search** (DSL, scoped terms, calories filter, help) | **covered** | Not on the original checklist but fully present: DSL parser (`salt_shared`), FTS5 compiler, search UI + syntax help, tag-tap search |

## Deliberate, documented differences (not accidental losses)

- **No unauthenticated / anonymous mode.** The old app shipped
  `authentication_enabled=False` by default and could serve recipes with
  no login. v2 always requires an account (first-boot setup code creates
  the admin).
- **Backups are always on, retention fixed at 14** — the old
  `backups_enabled` toggle and configurable `backup_count` are gone.
- **Home-grid card tag chips are display-only.** Tag-driven search moved
  to the detail-page chips and the search field; tapping a card opens the
  recipe.
- **Downloaded YAML is named `<id>.yaml`** (was `<title-slug>.yaml`).
- **Edamam → USDA FDC**, **single API key → per-user PATs**, **Font
  Awesome → Lucide**, and derived fields (`layout`, `title_formatted`,
  `file_hash`) dropped — all per the approved plan.

## Known minor gap (not blocking cutover)

- **"Save and add another"** — the legacy Add form had a second submit
  button that saved and reopened a blank form for rapid consecutive
  entry. The v2 editor has no equivalent. Low-impact productivity nicety;
  a candidate for a small follow-up if wanted.
- The author's personal **Donate/PayPal** navbar link was intentionally
  not carried over.
