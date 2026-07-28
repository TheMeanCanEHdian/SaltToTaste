# API contract goldens

Committed `/api/v1` response bodies, captured from the **real Dart Frog
routes** over a real HTTP server running the **real production middleware
chain** (`buildAppMiddleware`, the same function `routes/_middleware.dart`
calls). The data is real too: the legacy-v0 recipe committed at
`apps/server/test/fixtures/legacy-v0/`, ATK corpus recipes, and the recorded
real FDC responses in `apps/server/test/fixtures/fdc/`.

They live here — in `salt_shared`, which both sides depend on — so neither
`apps/server` nor `apps/app` owns the contract. Both packages reach them at
`../../packages/salt_shared/test/fixtures/contract` from their own package
root, which is the working directory of `dart test` and `flutter test`.

Two tests hold the ends together:

| Side | Test | Needs the corpus? |
| --- | --- | --- |
| Server | `apps/server/test/contract_golden_test.dart` | **partly** — it regenerates each body from the live route and compares byte-for-byte |
| App | `apps/app/test/contract_golden_parse_test.dart` | **no** — it parses these committed files with the real repositories/models, so it runs in CI |

A server-side key rename therefore fails loudly instead of silently changing
what the Flutter app sees. The motivating case is `must_change_password`:
`AuthUserInfo.fromJson` defaults it to `false`, so a rename would quietly
stop forcing password changes.

## What runs without the corpus

The server-side captures are split in two, because a gate around all of them
would leave the pin to a developer machine — CI would only re-parse static
files that agree with themselves.

- **`corpusFreeContractGoldenNames`** (auth, tags, recipe cards, recipe
  detail, an uncomputed match list) are generated and compared on **every**
  run, CI included. Their recipe data is the committed legacy-v0 fixture.
- **`corpusBackedContractGoldenNames`** (import, library scan, nutrition,
  nutrition review) need a real v1 source root with hero images and a
  `source.yaml`, plus FDC responses recorded against those exact ingredient
  lines. Their group skips without `SALT_CORPUS_DIR`; the app still parses
  the committed files.

## Regenerating

Only when the shape change is **deliberate**:

```sh
cd apps/server
SALT_CORPUS_DIR="<corpus source root>" UPDATE_CONTRACT_GOLDENS=1 \
  dart test test/contract_golden_test.dart
```

That works from scratch too — delete the `*.json` here and they are rebuilt
clean, with the presence checks stepping aside for the regenerating run.
Then read the diff — every changed byte is something `apps/app` has to agree
with — and re-run the app side:

```sh
cd apps/app && flutter test test/contract_golden_parse_test.dart
```

## Volatile values

Opaque tokens, timestamps, temp-directory paths, and wall-clock durations are
replaced with a stable stand-in (`"<token>"`, `"<timestamp>"`, `"<path>"`,
`0`) by `redactContractVolatiles` in
`apps/server/test/support/contract_goldens.dart`. Only the **value** is
replaced; the key stays, so a renamed or dropped key still fails.

The stand-in also **declares the JSON type** that key must carry. A live
value of another runtime type is not redacted — it is replaced with a marker
naming both types, so the comparison fails. Without that, a `started_at` that
became an epoch int would pass green here while `LibraryRepository`
(`json['started_at'] as String?`) threw on the real body.

## Synthetic content

Every recipe, ingredient line, nutrient, and tag here comes from real data —
the ATK corpus or the committed legacy-v0 recipe. The only synthesized inputs
are the ones real recipe data cannot supply: account credentials, one
personal note (user-authored text, not recipe data), and one deliberately
malformed YAML document (`zzzz-malformed-document.yaml`) that drives the
importer's `failed` counter and the library scan's `skipped` entry.
