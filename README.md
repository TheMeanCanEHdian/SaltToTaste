# Salt to Taste

A self-hosted recipe manager. Your recipes are stored as a SQLite database
with every recipe **auto-exported to hand-editable YAML**, so you keep a
durable, plain-text copy of your library while getting a fast, searchable,
multi-user web app on top of it.

Version 2 is a full rewrite: a **Dart Frog** backend serving a **Flutter**
web frontend, replacing the original Python/Flask app. It runs as a single
Docker container.

## Features

- **Recipes as YAML + SQLite.** SQLite is the runtime source of truth;
  every save writes a canonical YAML file to the data directory. Edit
  those files by hand and a startup/rescan reconciliation picks the
  changes up (the file wins on a clean edit; conflicts are preserved as
  `.conflict-<timestamp>.yaml`, never silently lost).
- **Structured recipes.** Grouped ingredients (with the verbatim line
  preserved), numbered steps, subsections and technique blocks, prep/cook
  times, servings, tags, source, and background notes.
- **Search.** A query DSL — `title:`, `tag:`, `ingredient:`, `calories:<400`,
  quoted phrases, `and`/`or` — compiled to SQLite FTS5.
- **Nutrition.** Per-serving USDA FoodData Central data with a classic FDA
  label and per-ingredient match transparency you can review and correct.
  (Free API key from [api.data.gov](https://api.data.gov/signup); one per
  server.)
- **Multi-user.** Admin (full access) and member (read + personal
  favorites/notes) roles. First boot prints a one-time setup code to
  create the admin — no default credentials. Per-user API tokens (PATs,
  `read`/`full` scoped) for scripts and native apps.
- **Import.** Bring in a Recipe Extraction v1 corpus or a legacy
  SaltToTaste v0 data directory; the format is auto-detected.
- **Backups.** Automatic tar.gz snapshots (library + database) daily and
  before destructive operations, keeping the last 14.

## Quick start (Docker)

```sh
docker build -t salttotaste .
docker run -d --name salttotaste -p 8080:8080 -v salt-data:/data salttotaste
```

Then read the one-time setup code from the logs and open the app:

```sh
docker logs salttotaste | grep 'setup code'
# open http://localhost:8080 and create the admin account
```

> `/data` must be a **local filesystem** — SQLite's WAL is unsafe on
> NFS/SMB shares.

### Importing your recipes

Mount a folder of recipe sources into the container's import directory,
then import it from **Settings → Import**:

```sh
docker run -d -p 8080:8080 -v salt-data:/data \
  -v "/path/to/recipes:/data/import:ro" salttotaste
```

Run behind a TLS reverse proxy (Caddy/Traefik/nginx) and set
`TRUST_PROXY=true` so secure cookies are detected via `X-Forwarded-Proto`, and
`TRUSTED_PROXIES` to name the proxy — e.g. `TRUSTED_PROXIES=172.17.0.0/16` for
the default Docker bridge.

`TRUST_PROXY` on its own now trusts nobody, and the server says so at boot.
That is deliberate: it used to believe `X-Forwarded-For` from whoever
connected, so anyone who could reach the port got a fresh rate-limit bucket per
request just by inventing the header. A forwarded header only means anything
coming from the hop that appends it. Getting `TRUSTED_PROXIES` wrong costs you
one shared rate-limit bucket for everyone behind the proxy; leaving the header
unchecked cost the rate limit entirely.

## Configuration

All configuration is via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | HTTP listen port |
| `DATA_DIR` | `/data` | Database, YAML library, backups |
| `IMPORT_DIR` | `$DATA_DIR/import` | Allowlisted root for bulk imports |
| `LOG_LEVEL` | `INFO` | `ERROR` / `WARN` / `INFO` / `DEBUG` |
| `TRUST_PROXY` | `false` | Trust `X-Forwarded-*` from a reverse proxy. Inert on its own — set `TRUSTED_PROXIES` too |
| `TRUSTED_PROXIES` | — | Comma-separated peers allowed to set `X-Forwarded-*`: exact IPs (`10.0.0.5`, `::1`) or IPv4 CIDR (`172.17.0.0/16`, a Docker bridge) |
| `SECURE_COOKIES` | `false` | Always mark session cookies `Secure` |
| `SEARCH_WORKER_ISOLATES` | `1` | Background isolates running the FTS ranked search off the serving isolate; raise for more concurrent-search throughput, `0` runs it inline |
| `LOG_BUFFER_SIZE` | `1000` | Recent log records kept in memory for the admin log viewer; `0` disables it. In-memory only |
| `CONNECTION_IDLE_TIMEOUT_SECONDS` | `75` | Close a connection idle/stalled this long — bounds slowloris half-open sockets. Keep above the proxy's keep-alive; `0` disables |
| `TZ` | `UTC` | Container time zone |

The USDA FoodData Central API key is set in the app (Settings →
Nutrition), stored write-only — never in logs or the exported YAML.

## Development

This is a Dart [pub workspace](https://dart.dev/tools/pub/workspaces):

- `packages/salt_shared` — shared pure-Dart models, YAML codec, search DSL.
- `apps/server` — the Dart Frog backend (SQLite, API, YAML export).
- `apps/app` — the Flutter web frontend.

```sh
dart pub get                              # resolve the workspace
cd packages/salt_shared && dart test      # includes the corpus golden test
cd apps/server && dart test               # backend suite
cd apps/app && flutter test               # frontend suite

# run the app against the server, same-origin:
cd apps/app && flutter build web --release --no-web-resources-cdn
rm -rf ../server/public && cp -r build/web ../server/public
cd ../server && dart_frog build && DATA_DIR=.data dart build/bin/server.dart
# open http://localhost:8080/
```

## Documentation

- [`docs/API.md`](docs/API.md) — the full `/api/v1` reference.
- [`docs/PARITY.md`](docs/PARITY.md) — feature parity with the original app.
- [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md) — build history and
  design decisions.

## License

See [`LICENSE`](LICENSE).
