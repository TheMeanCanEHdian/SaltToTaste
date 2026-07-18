# SaltToTaste v2 (Dart/Flutter rewrite)

Self-hosted recipe app, rewritten from the original Python/Flask app to a
Dart Frog backend + Flutter web frontend on branch `feat/dart-rewrite`. The
legacy Python tree was removed at the P8 cutover (recoverable via git
history; its one v0 recipe is preserved as
`apps/server/test/fixtures/legacy-v0/` for the legacy-importer tests). All
code lives in `apps/` and `packages/`. Feature parity with the old app is
recorded in `docs/PARITY.md`.

## Architecture

- **`packages/salt_shared`** — pure Dart (web-safe, no `dart:io` in `lib/src`
  model/DSL code): schema-v2 recipe models (`dart_mappable`, snake_case keys),
  YAML codec + emitter, quantity/fraction utils, servings parser, search DSL
  parser. Everything the server and app share.
- **`apps/server`** — Dart Frog backend (added P1). SQLite (raw `sqlite3`,
  hand-written SQL, `PRAGMA user_version` migrations) is the runtime source of
  truth; every recipe save auto-exports canonical YAML to the data dir
  (`/data` in Docker, `./.data` dev). API-first: the web UI consumes only the
  public `/api/v1` (documented in `docs/API.md`).
- **`apps/app`** — Flutter app (added P2), web-first but portable: Forui
  (pinned 0.24.0), bloc/cubit, go_router, dio. No `dart:html`/`package:web`
  outside conditional-import files.

Approved plan: local (not in the repo). Progress tracker:
`docs/IMPLEMENTATION.md` (update at every phase boundary and whenever a
decision deviates from the plan).

## Data & formats

- Canonical recipe document = **schema v2 YAML**, a strict superset of the
  Recipe Extraction v1 format. v1 corpus (1,198 real ATK recipes) is
  external and not committed; point tests at it with the `SALT_CORPUS_DIR`
  env var (the source root containing `recipes/`, `images/`, `source.yaml`;
  the folder name has spaces — quote it). Corpus-backed tests skip when it
  is absent. Missing key ≡ null; subsections omit (not null) their optional
  keys for prose-only variations; `quantity` is always a string.
- Nutrition data (USDA FoodData Central; per-deployment API key) and per-user
  data (favorites, personal notes) live in the DB only — never in YAML.
- Exported YAML remains hand-editable: reconciliation scan (hash-based) —
  file wins on clean external edit, DB wins on conflict (edited file kept as
  `.conflict-<ts>.yaml`).

## Conventions

- **Testing uses real data only** — the ATK corpus, never fabricated
  fixtures. Exception: negative-path inputs that cannot come from the corpus
  (deliberately malformed YAML, a crafted malicious id) may be synthesized;
  everything valid must be real corpus data. Corpus location is overridable
  in tests via the `SALT_CORPUS_DIR` env var.
- **Mockup-first UI** — present HTML/SVG mockups for approval before
  implementing any significant screen in Flutter.
- **Ask the user** when choosing between packages.
- High-effort code review after every phase.
- Roles: admin = full access; member = read + personal features. Auth: opaque
  session tokens (HttpOnly cookie on web, bearer elsewhere) + per-user PATs
  scoped `read`/`full` (effective permission = role ∩ scope).
- Security invariants: prepared statements only; FTS queries compiled from the
  parsed AST; path containment checks on file serving; SSRF guards on URL
  fetches; secrets never logged (see plan → Security).
- Logging: `package:logging`, request-id middleware, uniform error envelope
  `{error: {code, message, requestId}}`.
- Only binding brand color: maroon `#960000`. Open Sans. Lucide icons.
- **Button colour system (Forui).** The brand is red, so destructive is
  distinguished from primary by FILL, not hue. Primary = solid maroon, white
  text (`FButton` default `.primary`). Destructive = Forui's tinted
  `.destructive` (the theme's `destructive` is pointed at `errInk` so buttons,
  error text, and danger borders agree). Neutral (cancel/secondary/outline/
  ghost) = grey (theme `secondary` = `chipNeutral`, `secondaryForeground` =
  `ink`) so a plain button and its hover never read as destructive. Never set
  button colours per-widget — pick the variant and let the theme paint it.
  Pinned by `apps/app/test/theme_test.dart`.

## Commands

```sh
dart pub get                                  # workspace root — resolves all packages
cd packages/salt_shared && dart run build_runner build   # regen *.mapper.dart after model changes
cd packages/salt_shared && dart test          # includes the 1,198-file corpus golden test
cd apps/app && python3 tool/gen_lucide_catalog.py  # regen lucide_catalog.g.dart after a lucide_icons_flutter upgrade
cd apps/app && python3 tool/gen_logo_assets.py     # after editing assets/images/logo.svg: re-adds the currentColor
                                                   # tint hook (colorFilter blanks on CanvasKit) + regens web/favicon.svg

# Server (apps/server)
cd apps/server && dart test
cd apps/server && dart run salt_server:import "<source-root>" --data-dir=.data
#   (a legacy v0 root — the old app's _recipes/ layout — is auto-detected; --legacy forces)
cd apps/server && dart run salt_server:recover --data-dir=.data
#   prints a single-use, 15-min recovery code; redeem at /recover to reset (or
#   create) an enabled admin. Local access is the authorization, as with the
#   first-boot setup code. Only its digest is stored.
cd apps/server && dart_frog dev               # needs a real TTY (hot-reload key listener);
                                              # headless: dart_frog build && DATA_DIR=.data dart build/bin/server.dart

# App against the server — prefer SAME-ORIGIN (auth cookies flow; matches prod):
cd apps/app && flutter build web --release --no-web-resources-cdn && rm -rf ../server/public && cp -r build/web ../server/public
# then run the server and open http://localhost:8080/
# (cross-origin dev via --dart-define=SALT_API_BASE + DEV_ALLOW_CORS=true works for
#  the API but Flutter-web image fetches won't send cookies -> photo placeholders)
```

API reference: docs/API.md — update it in the same commit as any endpoint change.
