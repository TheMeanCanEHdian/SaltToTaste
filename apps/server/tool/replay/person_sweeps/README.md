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
| sw9.dart (+ run.sh) | fix83 (v83 F2, ledger Q13) | the cold-cache apply: settle the 128 recipes and child sections (bulkScopeIds(all), closer 1: 124 recipes + 4 sections) of the 8 keys holding a Rule B1 row (bacon, thick-cut bacon, pancetta, pancetta or bacon, lemon / lime zest plus juice, orange peel plus juice, chickpea); from EACH auto food line of a key (130: 126 recipe lines + 4 section lines, each through its own recipe as the `?section=` PUT), evict the key's part records no library row counts as its food from both caches (168322 for the four bacon keys; none for the other four — each of their part records is a row food, cached by that row's compute), serve them from the provider (NoNet otherwise), pick another cached record then the line's own, each apply_to_all; every recipe of the key: stale_reason null, stored == a full matchAndCompute (0 requests), requests == the evicted parts the key's rows read, each once | base 4325a3d: 54 of 130 divergent (every line of a key whose rows read 168322 — 52 recipe lines + 2 section lines: requests [] and these left `underived`, stored != compute (each line's own recipe or section excepted): from the 28 bacon lines (2 of them section lines) the 8 B1 recipes and 0158's stuffing section; the 18 pancetta lines 0333 pasta-alla-gricia and 0434 salade-lyonnaise; the 6 thick-cut bacon lines 0040 wilted-spinach-salad, 0446 potato-casserole and 1134 tartiflette; the 2 pancetta or bacon lines 0332 pasta-with-tomato-bacon-and-onion — by key 14 recipes and 0158's section (closer 2); before closer 1 the sweep read main recipes only: 52 of 126) | v83: 0 of 130, 0 refused, 0 skipped; those 54 lines ask 168322 once |
| sw10.dart (one process) | fix83 (v83 F3, ledger Q14) | the Confirm round trip: every snapshot-29 row whose UNGATED move inverse names another record (156: 155 `weight`, 1 `piece`) Confirmed through the real PUT, the row removed (stands in for a text edit) and the recipe computed; the landed row == the row (record, grams, source), stored == a second full compute, calls 0; closer 1: each row also Confirmed with its own grams TYPED (`override`), which must decide what the bare Confirm decides | base 4325a3d: 155 of 156, bare and typed (0150\|6 decides 172378, lands on 172378 at 1,376.00 g, 958.56 /serving); before closer 1: 156 bare, 125 of 156 typed (the 31 gated `weight` rows decided their moved record) | v83: 156 of 156, bare and typed |

GATE-P of the simplification ledger (.claude/diag/2026-10-26/simplification/audit/ledger.md) = sw5 + sw6 + sw7 +
sw8 on base and tip of every person-path refactor batch: 0 divergent on both, and the owner's two v82 mutants
(`held: plan?.held ?? false` → `false`; `_readsCoatHold` without `!_coatedFoodRow`) still die.
Round reports: .claude/diag/2026-10-26/review67/v82_fixer_reports/{verify3..verify6,closer4,closer5}.md.

v83 (batch M81, 2026-10-27): GATE-P on base 4325a3d and on v83 — sw5 31,141, sw6 36,828, sw7 1,833, sw8
55,893 combos, 0 divergent, 0 refused, 0 errors on both (12 shards each, run.sh); + sw9 and sw10 above.
sw9 runs as sw4–sw8 (`run.sh sw9.dart <tree> <snap> <workdir> 12`); sw10 alone
(`dart --packages=<tree>/.dart_tool/package_config.json sw10.dart <snap> <workdir>`, ~20 s with the typed pass).
