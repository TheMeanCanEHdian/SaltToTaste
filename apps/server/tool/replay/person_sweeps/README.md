# Person-path sweeps (the v82 review series, Runs 067/068) — archived 2026-10-27

The ONLY proof of every person-path (M52 Confirm / pick / skip / typed-grams) invariant:
stored == recomputeTotals == a full matchAndCompute, and the GET's grams and hold == stored, through the
REAL PUT. The corpus replay (rp43) holds 0 decisions and 0 person M52 rows, so it proves nothing here.
Each script settles a FRESH copy of snapshot 29 (.claude/diag/2026-10-25/snap29.db, md5 bf3503f0…)
by two computes of the 268 recipes holding an `auto` M52-class row, then sweeps under a NoNet provider
(every FDC request throws; `calls` must stay 0). Runners point at the scratchpad paths of the 2026-10-26
fix82 run — re-point `W` and `SNAP` before a re-run; each shard reads its own APFS clone of the settled DB.

| script | written by | spec | base 6ede11c (v81) | tip fab9f0f (v82) |
|---|---|---|---|---|
| sw3.dart (+ run_sw3.sh) | verify3 | the fleet's F7 combos: each M52 row c / p × the two largest foods × skip / un-skip / pick-same / typed / confirm, orders A / B; the pick-another verb skipped on 304 combos (no other cached detail under NoNet) | — | 4,740 combos, 0 divergent |
| sw4.dart (+ run_sw4.sh) | verify4 | settle + sweep split; c / all × 5 verbs, p × skip / pick-same, orders A / B | 195 divergent (c 101, all 52, p 42) | 41 of 21,368 — every one "pick the plan row, then skip the food" → closer 4 (D1 MED) |
| sw5.dart (+ run_sw5.sh, shard_sw5.sh) | closer 4 | sw4 extended: the plan-row PICK takes every food verb; order C (food skip → plan-row op → food un-skip) on every spec | named 28,310: 196; order C 2,831: 46 | named 0; order C: all 5 (0255\|all\|9, 0149\|all\|7, 0304\|all\|7, 1084\|all\|5, 0254\|all\|11) → closer 5 (D1 MED) |
| sw6.dart (+ run_sw6_sw7.sh) | verify5 (c5 and v5 copies identical) | sw5 + spec `pall` (every M52 row of the recipe picked on its own record) | 250 of 36,828 (named 196, order C 46, pall 8) | 0 of 36,828 after closer 5 (A 16,740, B 16,740, C 3,348) |
| sw7.dart (+ run_sw6_sw7.sh) | closer 5 | sw6 re-specced: a person's SKIP / typed 77 g / skip + un-skip of a PLAN ROW itself (no food op) — 611 rows × 3 | — | 1,833 combos, 0 divergent |
| sw8.dart (+ run_sw8.sh) | verify6 | sw6 + specs cp / pc (the plan row confirmed then picked / picked then confirmed) + order D (food skipped → plan-row op → food PICKED on its own record) | 519 of 55,893 (reproduces verify4's 195 and sw6's 250 exactly) | 0 of 55,893, 0 refused, 0 errors, calls 0 |

GATE-P of the simplification ledger (.claude/diag/2026-10-26/simplification/audit/ledger.md) = sw5 + sw6 + sw7 +
sw8 on base and tip of every person-path refactor batch: 0 divergent on both, and the owner's two v82 mutants
(`held: plan?.held ?? false` → `false`; `_readsCoatHold` without `!_coatedFoodRow`) still die.
Round reports: .claude/diag/2026-10-26/review67/v82_fixer_reports/{verify3..verify6,closer4,closer5}.md.
