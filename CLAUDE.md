# SaltToTaste v2 (Dart/Flutter rewrite)

Self-hosted recipe app being rewritten on branch `feat/dart-rewrite`. The legacy
Python/Flask app lives untouched in `saltToTaste/` until final cutover — do not
modify it. All new code lives in `apps/` and `packages/`.

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

Approved plan: `/Users/drivard/.claude/plans/background-a-long-warm-robin.md`.
Progress tracker: `docs/IMPLEMENTATION.md` (update at every phase boundary and
whenever a decision deviates from the plan).

## Data & formats

- Canonical recipe document = **schema v2 YAML**, a strict superset of the
  Recipe Extraction v1 format. v1 corpus (1,198 real ATK recipes):
  `/Users/drivard/Documents/Claude Projects/Recipe Extraction/The Complete
  America_s Test Kitchen TV Show Cookbook 2001–2023/recipes/` (path has
  spaces — quote it). Missing key ≡ null; subsections omit (not null) their
  optional keys for prose-only variations; `quantity` is always a string.
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

## Commands

```sh
dart pub get                                  # workspace root — resolves all packages
cd packages/salt_shared && dart run build_runner build   # regen *.mapper.dart after model changes
cd packages/salt_shared && dart test          # includes the 1,198-file corpus golden test

# Server (apps/server)
cd apps/server && dart test
cd apps/server && dart run salt_server:import "<source-root>" --data-dir=.data
cd apps/server && dart_frog dev               # needs a real TTY (hot-reload key listener);
                                              # headless: dart_frog build && DATA_DIR=.data dart build/bin/server.dart
```

API reference: docs/API.md — update it in the same commit as any endpoint change.
