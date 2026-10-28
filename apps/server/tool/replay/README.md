# The replay harness — the proof kit of the matcher batches and the simplification series

Committed in R0 of the simplification series (2026-10-27, the owner's Q18 ruling: the series' only
proof must outlive a scratchpad). The snapshot it runs on stays LOCAL (`.claude/diag/…/snapNN.db`,
gitignored; a key-stripped, session-free copy of the live DB — never the live `apps/server/.data`).

- `rp43.dart` — the cache-only replay (its header documents every TSV column). Run from `apps/server`
  on a COPY of a snapshot (`PRAGMA journal_mode=DELETE` first; never open a snapshot in place):
  `dart --packages=<repo>/.dart_tool/package_config.json tool/replay/rp43.dart <db-copy> rows.tsv recs.tsv sections.tsv --calls=calls.tsv --notes=notes.tsv [--reverse-parents] [--id-order] [--no-rekey] [--append-check]`
  Every FDC request throws food-scoped (the snapshot's caches are the only answers); `calls=0` is the
  zero-request proof. `--notes` (R0) dumps each row's `holdNoteOf` — the rows TSV never carries it.
- `bucket_v12.sql` — the status / hold / source buckets (`sqlite3 <replay-copy> < bucket_v12.sql`).
- `attr.py` — attributes a rows/recs diff to recipes and reports new / gone keys.
- `gate.sh <gate-dir> <snapshot.db> <prev-prefix>` — the per-batch gate: fresh copies, main and
  `--reverse-parents`, `cmp` main == rev, `cmp` every TSV and the buckets against the reference set
  `<prev-prefix>_{rows,recs,sections,calls,notes}.tsv` + `_bucket.out`, then the attribution.
  The simplification series' reference = the v82 set (`.claude/diag/2026-10-09/v82_*`, made on
  snapshot 29); every refactor batch must reproduce it byte for byte.
- `digest.sh <gate-dir> [live-db]` — after a deploy: live buckets == replay buckets and the kcal digest.
- `person_sweeps/` — sw3–sw10, the only proof of the person paths (Confirm / pick / skip / typed grams
  through the real PUT); see its README for each sweep's spec and base / tip figures.

Conventions: one heavy run at a time; a gate run writes a full log and the reviewer greps it; the
scripts are frozen as they ran (style lints ignored per file) — a batch that renames a symbol they
read must update them in the same commit (the analyzer covers them).
