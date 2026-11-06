# Person-path sweeps (the v82 review series, Runs 067/068) — archived 2026-10-27

The ONLY proof of every person-path (M52 Confirm / pick / skip / typed-grams) invariant:
stored == recomputeTotals == a full matchAndCompute, and the GET's grams and hold == stored, through the
REAL PUT. The corpus replay (rp43) holds 0 decisions and 0 person M52 rows, so it proves nothing here.
Each script settles a FRESH copy of the batch's replay snapshot (snapshot 29 .claude/diag/2026-10-25/snap29.db
for v82–v89, snapshot 30 .claude/diag/2026-10-29/snap30.db for v90–v98, snapshot 32
.claude/diag/2026-11-02/snap32.db from v100) by two computes of the recipes holding an `auto` M52-class row
(268 on each), then sweeps under a NoNet provider (every FDC request throws; `calls` must stay 0). Run them
with `run.sh <swN.dart> <tree> <snap> <workdir> <nshards>` (12 shards; each shard reads its own APFS clone of
the settled DB); sw3 has its own `run_sw3.sh`, sw10 runs alone (below). The per-script runners the table's
second column once named (run_sw4/run_sw5/shard_sw5/run_sw6_sw7/run_sw8.sh) were never archived (v101 U16).

| script | written by | spec | base 6ede11c (v81) | tip fab9f0f (v82) |
|---|---|---|---|---|
| sw3.dart (+ run_sw3.sh) | verify3 | the fleet's F7 combos: each M52 row c / p × the two largest foods × skip / un-skip / pick-same / typed / confirm, orders A / B; the pick-another verb skipped on 304 combos (no other cached detail under NoNet) | — | 4,740 combos, 0 divergent |
| sw4.dart (+ run.sh) | verify4 | settle + sweep split; c / all × 5 verbs, p × skip / pick-same, orders A / B | 195 divergent (c 101, all 52, p 42) | 41 of 21,368 — every one "pick the plan row, then skip the food" → closer 4 (D1 MED) |
| sw5.dart (+ run.sh) | closer 4 | sw4 extended: the plan-row PICK takes every food verb; order C (food skip → plan-row op → food un-skip) on every spec | named 28,310: 196; order C 2,831: 46 | named 0; order C: all 5 (0255\|all\|9, 0149\|all\|7, 0304\|all\|7, 1084\|all\|5, 0254\|all\|11) → closer 5 (D1 MED) |
| sw6.dart (+ run.sh) | verify5 (c5 and v5 copies identical) | sw5 + spec `pall` (every M52 row of the recipe picked on its own record) | 250 of 36,828 (named 196, order C 46, pall 8) | 0 of 36,828 after closer 5 (A 16,740, B 16,740, C 3,348) |
| sw7.dart (+ run.sh) | closer 5 | sw6 re-specced: a person's SKIP / typed 77 g / skip + un-skip of a PLAN ROW itself (no food op) — 611 rows × 3 | — | 1,833 combos, 0 divergent |
| sw8.dart (+ run.sh) | verify6 | sw6 + specs cp / pc (the plan row confirmed then picked / picked then confirmed) + order D (food skipped → plan-row op → food PICKED on its own record) | 519 of 55,893 (reproduces verify4's 195 and sw6's 250 exactly) | 0 of 55,893, 0 refused, 0 errors, calls 0 |
| sw8r.dart (+ run.sh) | v96 closer 2 (verify2 D4; committed at v98) | sw8 with `planned()` = the 21 recipes the v96 browning arm moves (8 hold no M52 row on snapshot 30, so sw5–sw8 never settle them); snapshot 30 | base f912190 (v95): 3,858 combos, 0 divergent | v96: 5,433 combos, 0 divergent, 0 refused, calls 0 |
| sw9.dart (+ run.sh) | fix83 (v83 F2, ledger Q13) | the cold-cache apply: settle the 128 recipes and child sections (bulkScopeIds(all), closer 1: 124 recipes + 4 sections) of the 8 keys holding a Rule B1 row (bacon, thick-cut bacon, pancetta, pancetta or bacon, lemon / lime zest plus juice, orange peel plus juice, chickpea); from EACH auto food line of a key (130: 126 recipe lines + 4 section lines, each through its own recipe as the `?section=` PUT), evict the key's part records no library row counts as its food from both caches (168322 for the four bacon keys; none for the other four — each of their part records is a row food, cached by that row's compute), serve them from the provider (NoNet otherwise), pick another cached record then the line's own, each apply_to_all; every recipe of the key: stale_reason null, stored == a full matchAndCompute (0 requests), requests == the evicted parts the key's rows read, each once | base 4325a3d: 54 of 130 divergent (every line of a key whose rows read 168322 — 52 recipe lines + 2 section lines: requests [] and these left `underived`, stored != compute (each line's own recipe or section excepted): from the 28 bacon lines (2 of them section lines) the 8 B1 recipes and 0158's stuffing section; the 18 pancetta lines 0333 pasta-alla-gricia and 0434 salade-lyonnaise; the 6 thick-cut bacon lines 0040 wilted-spinach-salad, 0446 potato-casserole and 1134 tartiflette; the 2 pancetta or bacon lines 0332 pasta-with-tomato-bacon-and-onion — by key 14 recipes and 0158's section (closer 2); before closer 1 the sweep read main recipes only: 52 of 126) | v83: 0 of 130, 0 refused, 0 skipped; those 54 lines ask 168322 once |
| sw10.dart (one process) | fix83 (v83 F3, ledger Q14) | the Confirm round trip: every snapshot-29 row whose UNGATED move inverse names another record (156: 155 `weight`, 1 `piece`) Confirmed through the real PUT, the row removed (stands in for a text edit) and the recipe computed; the landed row == the row (record, grams, source), stored == a second full compute, calls 0; closer 1: each row also Confirmed with its own grams TYPED (`override`), which must decide what the bare Confirm decides | base 4325a3d: 155 of 156, bare and typed (0150\|6 decides 172378, lands on 172378 at 1,376.00 g, 958.56 /serving); before closer 1: 156 bare, 125 of 156 typed (the 31 gated `weight` rows decided their moved record) | v83: 156 of 156, bare and typed |
| sw11.dart (+ run.sh; classes: sw11_classify.py) | the Run 073 Sonnet fleet (archived review073/sw11_sonnet), adapted by fix101 (v101 U1) | pick ANOTHER candidate: sw8's plan with the pick-same verb replaced by pickOther / pickOtherSkip (pick, skip, un-skip) and their apply_to_all twins pickOtherAll / pickOtherSkipAll; the 'o' specs pick another record on a plan row (then skip, un-skip; 'all' = apply_to_all); spec 'n' = the food verbs alone on every recipe holding an auto row on a move TARGET ('separable lean and fat', a trimDepthRecords target, 173128); order D once per spec and food; the pick prefers a move SOURCE ('separable lean only', a trimDepthRecords key, 168743 — a hit of a cached answer allowed for a source) else a record whose detail is cached; snapshot 32 | base 30c1f83: settled 363, 39,760 combos, 2,405 divergent — touched-line (U1) 1,274 in 139 recipes (0082\|n\|0 169566 → 168661, 0091\|n\|0 168743 → 173128, 0426\|0 …), inherit 1,005, calls-only 126 | v101: 39,760 combos, 1,197 divergent, 0 errors — 'other' (touched-line) 6, all order B and present at base, the shared-key class not U1's (the food line and the plan row share a key and the later pick re-decides it — 0002 onion, 1105 table salt, 0466 unsalted butter), inherit 999, calls-only 192 (a decided un-skip on a hit-only record asks its detail once, as the compute does); calls 0 on every other combo; v102 (M98): 200 divergent, all energy-only (the 192 + the 8 0249\|o2\|0 tags, rows equal to the compute), inherit 0, other 0, 0 errors, tip ⊂ base |

GATE-P of the simplification ledger (.claude/diag/2026-10-26/simplification/audit/ledger.md) = sw5 + sw6 + sw7 +
sw8 on base and tip of every person-path refactor batch: 0 divergent on both, and the owner's two v82 mutants
(`held: plan?.held ?? false` → `false`; `_readsCoatHold` without `!_coatedFoodRow`) still die.
Round reports: .claude/diag/2026-10-26/review67/v82_fixer_reports/{verify3..verify6,closer4,closer5}.md.

v83 (batch M81, 2026-10-27): GATE-P on base 4325a3d and on v83 — sw5 31,141, sw6 36,828, sw7 1,833, sw8
55,893 combos, 0 divergent, 0 refused, 0 errors on both (12 shards each, run.sh); + sw9 and sw10 above.
sw9 runs as sw4–sw8 (`run.sh sw9.dart <tree> <snap> <workdir> 12`); sw10 alone
(`dart --packages=<tree>/.dart_tool/package_config.json sw10.dart <snap> <workdir>`, ~20 s with the typed pass).

v88 (batch M88, 2026-10-29; docs/API.md "Matcher v88"): GATE-P on base dbb6092 and on v88 (12 shards, fresh
snapshot-29 copies) — sw5 31,229, sw6 36,916, sw7 1,839, sw8 56,043 combos, 0 divergent, 0 refused, 0 errors on
both, calls 0.

v96 (batch M94, 2026-10-30; docs/API.md "Matcher v96"): GATE-P on base f912190 and on v96 (12 shards, fresh
snapshot-30 copies, .claude/diag/2026-10-29/snap30.db) — base sw5 31,229,
sw6 36,916, sw7 1,839, sw8 56,043; the tip sw5 31,757, sw6 37,444, sw7 1,875, sw8 56,943 combos; 0 divergent, 0
refused, calls 0 on both. Those sweeps reach 13 of the 21 moved recipes; sw8r.dart (above) the 21: settled 21, a
second pass moves 0, base 3,858 / tip 5,433 combos, 0 / 0, calls 0.

v98 (the Run 071/072 fixes, 2026-10-31; docs/API.md "Matcher v98"): GATE-P on base bdd0c5e and on v98 (12 shards,
fresh snapshot-30 copies) — sw5 31,757, sw6 37,444, sw7 1,875, sw8 56,943 and sw8r 5,433 combos, 0 divergent, 0
refused on both, calls 0; settled 268 (sw8r 21), a second pass moves 0.

v100 (batch M97, 2026-11-02; docs/API.md "Matcher v100"): GATE-P on base e3a4ed2 and on v100 (12 shards, fresh
snapshot-32 copies, .claude/diag/2026-11-02/snap32.db) — base sw5 31,757, sw6 37,444, sw7 1,875, sw8 56,943, sw8r
5,433; the tip sw5 31,713, sw6 37,400, sw7 1,872, sw8 56,868, sw8r 5,358 combos; plus sw8s = sw8r.dart with its
`_v96Slugs` = ['spaghetti-and-meatballs'] and the `!= 21` check `!= 1` (the one v100 reach recipe outside the 21;
not committed — the two-line edit above): base 48, tip 123. 0 divergent, 0 refused, 0 errors, calls 0 on both;
settled 268 (sw8r 21, sw8s 1), a second pass moves 0. The deltas are exactly broiled-chicken-with-gravy|12's specs
(the roux guard leaves it no plan row) and spaghetti-and-meatballs|10's +75 (its new shallow-fry plan row).

v101 (batch fix101, 2026-11-04; docs/API.md "Matcher v101"): GATE-P on base 30c1f83 and on v101 (12 shards, fresh
snapshot-32 copies) — sw5 31,713, sw6 37,400, sw7 1,872, sw8 56,868, sw8r 5,358, sw9 130, sw10 156 (bare and typed) on
both: 0 divergent, 0 refused, calls 0; settled 268 (sw8r 13 of its 21 on snapshot 32), a second pass moves 0. Plus sw11
(the row above), classed by sw11_classify.py: base 'other' (touched-line) 1,274 in 139 recipes → v101 6 — all order B,
all present at base, none U1's: 0002|o2|7 and 0002|c2|7 (170000 kept vs 790646 computed), 0466|c4|5 and 0466|o4|5
(172469 vs 173430), 1105|o5|10 and 1105|c5|10 (746775 vs 173468) — the food pick runs first, then a plan-row pick on a
SAME-KEY line re-decides the key and the touched row keeps the earlier pick until the next compute (the shared-key
class); inherit 999 (base 1,005), energy-only 192 (base 126); 6 + 999 + 192 = the 1,197 divergent (closer 2, verify2 D1). Refused 14,070 on both sides (the pick-another verb found no other cached candidate). The gate as RULED in the owner
gate (the brief's "0 divergent at the tip" is unmet as written, verify1–4): tip ⊂ base (0 tags at the tip absent at
the base) and 0 of U1's class; the `inherit` class (stored ≠ compute on the recipe's other lines of a picked key) is
the next person-path batch, recorded in docs/API.md.

v102 (batch M98, 2026-11-04; docs/API.md "Matcher v102": a decision PUT settles its own recipe): GATE-P on base 78e9aad
and on v102 (12 shards, fresh snapshot-32 copies) — sw5 31,713, sw6 37,400, sw7 1,872, sw8 56,868, sw8r 5,358, sw9 130,
sw10 156 (bare and typed) on both: 0 divergent, 0 refused, calls 0; settled 268 (sw8r 21, sw9 128), a second pass moves
0 — the expectation measured, since every repeated-key decision PUT there now runs the settle. sw11: base 78e9aad = the
v101 census byte for byte (fix101/sw11_v4/tip.divtags, 1,197; sw11_classify.py output identical); v102 200, all
energy-only = the base's 192 + the 8 atk-tv-2023-0249-roast-fresh-ham|o2|0 tags; inherit 0, other 0, err 0, 14,070
refused on both, the tip's tags ⊂ the base's. NOT committed (the L4 oracle): sw11c / sw8c = sw11 / sw8 with `state()`
writing each row's `:${r.confidence.toStringAsFixed(2)}` and the E token `E=…|fresh=${nutritionIsFresh(…)}` (a
two-line edit) — sw11c base 1,373 divergent (1,215 fresh after the PUTs), v102 the same 200 tags as sw11, every one stale
after its PUTs; sw8c base 1,648 (all confidence-only: the Confirm class), v102 0.

v103 (batch fix103, 2026-11-05; docs/API.md "Matcher v103"): GATE-P on base 63e4315 and on v103 (12 shards, fresh
snapshot-32 copies) — sw5 31,713, sw6 37,400, sw7 1,872, sw8 56,868, sw8r 5,358, sw9 130, sw10 156 (bare and typed) on
both: 0 divergent, 0 refused, calls 0; settled 268 (sw8r 21, sw9 128), a second pass moves 0. sw11: 39,760 combos,
200 divergent on both, all energy-only, inherit 0, other 0, err 0, 14,070 refused; the tip's tags identical to the base's.
