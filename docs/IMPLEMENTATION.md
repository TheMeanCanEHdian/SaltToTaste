# Implementation Tracker

Living status of the approved rewrite plan (local file:
`/Users/drivard/.claude/plans/background-a-long-warm-robin.md`). Statuses:
`pending` / `in-progress` / `done` / `changed(reason)`.

Last updated: 2026-07-14

## P0 — Workspace + salt_shared — **done**

| Item | Status | Notes |
|---|---|---|
| Pub workspace root (`pubspec.yaml`, `analysis_options.yaml`) | done | Dart 3.12 native workspaces; strict lints |
| Branch `feat/dart-rewrite` | done | |
| `salt_shared` package + schema-v2 models (dart_mappable, snake_case) | done | `lib/src/model/recipe.dart`; codegen green |
| YAML emitter (block style, literal blocks, PyYAML-safe quoting) | done | `lib/src/yaml/yaml_emitter.dart` |
| Quantity/fraction utils + servings parser (corpus-vocabulary driven) | done | 100% of 200 distinct corpus servings values parse |
| Search DSL parser (scoped terms, and/or, calories ops) | done | tolerant parser w/ error recovery; no parentheses (matches old DSL) |
| Recipe YAML codec (decode/normalize/v1→v2 upgrade, canonical encode) | done | quantity/isbn/extracted_at string-coercion; subsection key omission preserved |
| Corpus golden test: 1,198 files decode + round-trip model-equal | done | verified: 1198/1198 decode, 1198/1198 round-trip, 0 unparseable servings; 89/89 tests, analyze clean |
| CLAUDE.md + this tracker | done | |
| Phase code review (high effort, adversarial verify) | done | see review record below |

Known limitations (documented by module authors): quantity parser rejects
range strings (`1–2`) by design; DSL has no parentheses grouping; smart quotes
not treated as phrase delimiters; `MAKES ... CUPS` yields use the leading
number (serving basis is editable later).

### P0 code review record (2026-07-14)

8 finder angles → 27 deduped candidates → adversarial panel (3 refuters per
finding, ≥2 kills) → 23 survivors, 5 killed. All survivors fixed and covered
by regression tests (suite grew 89 → 107 tests), except three deferred items:

**Fixed (correctness):** emitter now quotes PyYAML date/sexagesimal forms
(`'2026-06-30'`, `'1:30'`); C1 controls + U+2028/9 escaped double-quoted;
non-finite doubles emit `.inf`/`.nan`; codec reads `schema_version` tolerantly
(`'1'`/`1.0`/unrecognizable→warn+v1); `SERVES 4-6`/`4–6` ranges; DOZEN
multiplies before rounding (`1½ DOZEN` = 18); `ABOUT/YIELDS n SERVINGS` and
`n TO m SERVINGS` parse via token scan.

**Fixed (design/cleanup):** encode now derived from generated `toMap()` +
canonical transform — model fields can never be silently dropped (tripwire
test added); redundant scalar coercion removed (dart_mappable String-coercion
behavior pinned by regression test); fraction char class shared between
quantity and servings parsers; corpus path/scanners consolidated into
`test/corpus.dart` with a decode-once cache; And/Or nodes share a sealed
junction base; contradictory coverage assertions resolved; `formatQuantity`
regexes hoisted; emitter public-API branches now tested.

**Killed by panel (spot-checkable):** subsection key-order fidelity (encode is
canonical-v2 by contract, source files never rewritten); versioned migration
chain (no v3 on roadmap; YAGNI); structured warning objects (two producers,
job-log contract only); generalized numeric filter node (calories-only is the
documented old-DSL parity); serves/times optionality asymmetry (deliberate
per-plan shapes).

**Deferred to user/P4:** search semantics changes vs old app — scope binds one
term (old: whole block) and adjacent same-scope terms AND (old: OR) — product
decisions pending; `calories:` queries must default to calories-ascending
ordering in the P4 compiler (old-app contract not expressible in the AST).

## P1 — Server core + import — **pending**
Logging/request-id/error-envelope middleware first; sqlite3 DAL + migration 001
(FTS5); import service + CLI; recipes list/detail/yaml endpoints; image serving.

## P2 — Flutter read-only app — **pending**
Mockups (grid/card/detail, desktop+mobile) → approval → theme/router/grid/detail.

## P3 — Auth — **pending**
Setup flow, sessions (cookie+bearer), CSRF, rate limiting + lockout, roles
(admin full / member read+personal), PATs scoped read|full, users CRUD, login UI.

## P4 — Search + tags — **pending**
FTS5 + DSL→FTS compiler, search UI, tag styles (Lucide) + editor.
Requirement from P0 review: `calories:` queries default to calories-ascending
result ordering (old-app contract). Pending user decision: scope-binding and
same-scope AND/OR semantics vs old app.

## P5 — Editing + export + reconciliation + backups — **pending**
CRUD, atomic auto-export, library reconciliation scan (file wins clean edit /
DB wins conflict + `.conflict` file), image upload + SSRF-guarded URL download,
rolling backups, legacy v0 importer, editor UI (mockup first), favorites/notes.

## P6 — Nutrition (USDA FDC) — **pending**
Provider + caches + matcher + gram resolver + aggregation, match overrides,
rate-limited bulk job, FDA label + review sheet (mockup first), `calories:` live.
Needs per-deployment api.data.gov key from user at phase start.

## P7 — Settings + import UI + Docker — **pending**
Settings tabs, import wizard, multi-stage Dockerfile (Flutter web → dart_frog
AOT compiled in-image → slim runtime + libsqlite3, `VOLUME /data`, non-root
user, HEALTHCHECK, multi-arch amd64+arm64), security headers. Server must ship:
SPA deep-link fallback (non-API GET → index.html), env-var config (PORT,
DATA_DIR, LOG_LEVEL, TRUST_PROXY, TZ), X-Forwarded-Proto trust for Secure
cookies behind reverse proxy, SIGTERM graceful shutdown (drain + clean SQLite
close). Document: /data must be local fs (no NFS/SMB); domain-root serving
assumed (sub-path deferred).

## P8 — Parity audit + cutover — **pending**
Checklist vs old app, delete Python tree, promote Dockerfile, README, Forui
upgrade pass.

## Decision log (deviations & clarifications)

- 2026-07-14 — Backend must be deployable as a Docker container (user):
  already covered by P7 single-container design; noted ARM multi-arch as a
  P7 consideration.
- 2026-07-14 — Container hardening specifics added after user question: SPA
  deep-link fallback route, X-Forwarded-Proto trust for Secure cookies,
  non-root user, SIGTERM graceful shutdown, HEALTHCHECK, env-var runtime
  config, local-fs-only /data caveat, domain-root serving assumption
  (sub-path support deferred).
