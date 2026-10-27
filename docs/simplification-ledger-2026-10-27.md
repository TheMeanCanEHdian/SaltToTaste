# Simplification ledger (the nutrition engine, 2026-10-27)

The read-only over-engineering audit of the tree at fab9f0f (matcher v82): eight lenses, a critic re-measuring every claim, a synthesizer ranking the ledger into replay-gated batches. **Owner ruling 2026-10-27: go with the synthesizer's recommendations (§5's Q1–Q20 all stand as written there); run R0 through R5 first.** The lens reports, the critique and the census scripts are archived locally under `.claude/diag/2026-10-26/simplification/audit/`. Verbatim below.

# SIMPLIFICATION AUDIT — THE LEDGER (synthesizer, READ-ONLY, tree fab9f0f = matcher v82, matcherVersion 78)

Inputs read whole: the brief (batch17/simplification_audit_brief.md), L1–L8.md, critique.md (97 entries: 84 CONFIRMED,
10 CORRECTED, 3 REJECTED, 10 duplicate pairs). Worktree wf_f576235b-496-10 checked out at fab9f0f (nutrition_v82_test.dart
present, 109,711 B). Snapshot copy simp/snap29_synth.db (chmod 444, opened -readonly). Synthesizer scripts: simp/synth/.
Only CONFIRMED / CORRECTED items enter §1; REJECTED ones (L1-8, L2-9, L5-8 as a kcal-neutral item) and the
measured no-change items (L1-1, L1-12, L1-13, L3-8, L3-13, L5-11, L6-14, L8-7) are listed in §4 as "keep".
Duplicates kept ONCE, as the critic's table says (L1-2⊃L6-11 table half, L1-3⊃L3-5 rack half, L6-4⊃L1-7(b) step half,
L1-9⊃L3-4, L2-3⊃L5-9, L2-8⊃L4-11, L4-2⊃L3-1's noun, L4-1⊃L5-1, L6-6⊃L4-5, L2-11⊃L5-8).

## §0 Synthesizer re-measurements on THIS tree (grep / span / census; each reproduces or corrects a lens figure)
- engine.dart 22,838 · matcher.dart 4,721 · grams.dart 4,725 · nutrition_handlers.dart 1,252 lines (33,536).
- matcher.dart: contract 123–131, "History:" opens at 132, `const int matcherVersion = 78;` at 1026 (L8-1 ✓).
- `expect(matcherVersion` in 31 v-files + 1 in nutrition_seasoning_ci_test (L7-1 ✓).
- `keptOilFries`: ONE lib occurrence, its definition (engine 2996) (L8-3a ✓); `driedForFresh`: definition matcher 3900 +
  3 doc mentions 3886 / 3903 / 4150 (L8-3b ✓); engine 828 is `(final Object? f, _, _, _, _) => '$f',` (L8-6 ✓).
- `freshMatch`: Resolving 17275 + forwards 17284 / 17305; only the compute (14855) passes it (L6-10 ✓).
- `_stepsOf` callers 3796, 4173; 12 `List<String> steps` params; 12 `_before(` refs (L2-1 / L2-2 ✓).
- Hold-string literals ('starter_discard' | 'coating' | 'partial_pour_away' | 'ambiguous_medium' | 'discarded_medium')
  in engine: 25 = 5 in the getter + 20 sites (L5-10 ✓).
- ALL 26 file-local publics of L8-8 (the critic sampled 11): 0 code references outside their own file across
  apps/server lib / routes / bin / test / tool, salt_shared lib + test, apps/app lib (synth/pubs26.py, comments and
  strings stripped, interpolations kept) ✓; 0 in rp43.dart and in the 7 sweep scripts (synth/harnessrefs.py).
- rp43.dart (harness == scratch v43 copy, filecmp) calls only matchAndCompute, gramBasisFor (memo-less), compositeFlagOf,
  bulkScopeIds and reads the row field `servingBasis` — no symbol any batch renames or deletes.
- Test tables (L7tools/tables.py re-run): 117 top-level table literals / 38,688 lines; the 13 must-not-move 21,121 ✓;
  100 v-files / 120,904 lines / 1,098 RE-PIN ✓.
- L3-5 `_edible` measured: the shared `× S edible · approximate (…)` GramResolution sits at grams 3168–3174, 3176–3183,
  3288–3294 (22 lines); the shell site 3126–3137 shares the template only in one branch of its own ternary →
  gain ≈ −13 (22 → 3 calls + a ~6-line helper), not the ~20 L3 wrote (that included the rack half, = L1-3).
- SQL on the copy: ingredient_decisions 0; statuses auto 13,491 / confirmed 1,052 / overridden 5 / unmatched 19;
  recipe_nutrition.totals NULL 0; user_version 20 (critic ✓).
- CORRECTION (new, not in the critique) — L2-6's proof "replay identical (hold notes are row text: byte-identity covers
  them)" is WRONG: rp43.dart has 0 hold_note / holdNoteOf references (L3-12); `_rawSentence` (2373 / 2397) builds
  `_oilOwnersOf`'s `ambiguous` note, read only by holdNoteOf 3535; `_dipsOf`'s `text` is read only by holdNoteOf 3544.
  So L2-6, L5-3 (3535 is one of its owner reads), L5-10 (holdNoteOf 3531–3549 literals) and L6-2 (derivedFor's note)
  are NOT proved by the replay. Census: 23 stored rows carry a note-bearing hold — ambiguous_medium 2, coating 6,
  partial_pour_away 15 (snapshot SQL = v82_rows col 10). → R0 adds a notes dump (GATE-N) before any of them.
- servingBasis: 19 `servingBasis:` hits in 9 test files, 4 of them L6-9's upsert seeds → ≤ 15 recomputeTotals calls in
  6 files (critic 12–13; immaterial).
- Person sweeps: sw3 / sw4 / sw5 / sw6 (c5 and v5, both 8,127 B) / sw7 / sw8 exist ONLY under scratchpad/fix82;
  .claude/diag/harness/ has no person_sweeps/ (L6-13 precondition still open).

## The gates every item's PROOF names (defined once)
- GATE-R (every refactor batch): (1) step zero on the batch's base — rp43 + bucket_v12 on a FRESH SNAPSHOT 29 copy
  (`PRAGMA journal_mode=DELETE` first) reproduce .claude/diag/2026-10-09/v82_{rows,recs,sections,calls}.tsv +
  v82_bucket.out byte for byte (they stay the reference for the whole series, since every batch is byte-identical);
  (2) after — the same, main AND --reverse-parents, cmp identical; calls 0, staleAfter 0, sectionsStale 0, kcalCheck
  208, sections 144 (14,567 rows, 1,342 bulkScope ids); (3) the full suites: server on the LIVE corpus
  (SALT_CORPUS_DIR set; result count stated against +2804 ~4 at fab9f0f — only stated deletions may move it),
  salt_shared, app; (4) `dart analyze` clean, `dart format` 0 changed; (5) the item's owner mutants on a scratch copy
  (restore by snapshot copy, chain `mut && run`), each killed by a VALUE pin — a mutant that only an equality pin
  between two table keys kills is a survivor; (6) stepIndexCounts exact on the v26 cost shapes, a moved family re-pinned
  as an EQUALITY; (7) grep the tree for every symbol the commit message names, verifiers confirm by diff;
  (8) the dual-fleet review (Sonnet 5.5, then Opus 5.5); (9) matcherVersion stays 78.
- GATE-P (person paths, adds): the archived v82 sweeps (R0) through the real PUT / GET / compute — closer 4 28,310
  combos, order C 2,831, verify5 36,828, the verifier's 55,893, skip / typed / un-skip 1,833: 0 divergent on base and
  tip; the owner's two v82 mutants (`held: plan?.held ?? false` → `false`; `_readsCoatHold` without
  `!_coatedFoodRow`) still die. The replay holds 0 decisions and 0 person M52 rows — it proves nothing here.
- GATE-N (hold notes, adds): the R0 notes dump byte-identical (the 23 note-bearing rows + every STATED note pin:
  31 `holdNoteOf(` test calls, `'hold_note'` in 10 files).
- GATE-C (cost, adds): RULE C ABBA at the editor caps on the cap shapes the item names; a new memo family enters
  cost_bounds (`expectBounded` fails on an unknown family) with an exact pin; the memoOffForTest oracle green in both
  line orders.
- GATE-T (test-only batches): no lib diff (replay = step zero only); result count before / after with the exact names
  of the deleted / added tests; every owner mutant a deleted or moved pin killed still dies on a kept pin (list them
  BEFORE deleting; a mutant killed only by the deleted pin is a pin to re-home, never accepted).

## §1 THE RANKED LEDGER (only CONFIRMED / CORRECTED; score = gain ÷ risk weight, NIL 1 · LOW 2 · LOW-MED 3 · MED 4 ·
##    MED-HIGH 5 · HIGH 8; gain = lines removed — "m" measured by grep / span, "e" the planner's estimate the batch
##    must measure). Lib code, tests and comments are ranked apart (a test line is not a lib line).

### §1a Lib code, kcal-neutral, no owner ruling needed (40 items + 7 structural)
| # | id (lens) | verdict | gain | risk | score | batch |
|---|---|---|---|---|---|---|
| 1 | L2-1 drop 12 legacy `steps` params + `_stepsOf` | CONFIRMED | ~40 e (12 params / ~21 args / 1 fn m) | NIL | 40 | R2 |
| 2 | L4-2 `_M52Row` bools → `_M52Kind` (+ L3-1's noun) | CONFIRMED | ~70 e (113 lines m) | LOW | 35 | R10 |
| 3 | L6-1 weighed row ×3 → `_weighedRow` | CONFIRMED (asymmetry PLAUSIBLE) | ~110 e (234 m) | MED | 27.5 | R16 |
| 4 | L4-1 one M52 line classifier (⊃ L5-1) | CORRECTED (≥4 predicates) | ≤80 e (120 code m, 9 sites) | LOW-MED | 26.7 | R15 / R20 |
| 5 | L4-3 recorded-reads memo for the plan key | CONFIRMED | ~165 e (~290 incl. docs m) | HIGH | 20.6 | R20 |
| 6 | L6-3 apply skeleton ×2 | CONFIRMED | ~75 e | MED | 18.8 | R17 |
| 7 | L8-3a delete `keptOilFries` | CONFIRMED | 37 m lib (+29 test) | LOW | 18.5 | R3 |
| 8 | L3-1 `discardedBasis()` list join | CORRECTED (6 + 2 spellings) | 30–40 e net of L4-2 | LOW | 17.5 | R11 |
| 9 | L3-6 M52 source phrases | CONFIRMED | ~15 e | NIL | 15 | R9 |
| 10 | L1-3 `_lambRack` const | CONFIRMED | 14 m | NIL | 14 | R5 |
| 11 | L3-5 `_edible` (3 sites) | CORRECTED (§0) | ~13 m | NIL | 13 | R5 |
| 12 | L5-2 `normalized` arg optional | CONFIRMED | ~25 e (16 sites m) | LOW | 12.5 | R7 |
| 13 | L6-5 `withWeight` ×6 | CONFIRMED | ~25 e | LOW | 12.5 | R13 |
| 14 | L6-4 `rankedFor` + one trim arm (⊃ L1-7(b) step half) | CONFIRMED | ~35 e | LOW-MED | 11.7 | R14 |
| 15 | L8-3b delete `driedForFresh` | CONFIRMED | 11 m | NIL | 11 | R3 |
| 16 | L6-2 sync core derivedFor ↔ `_unplannedOf` | CONFIRMED | ~55 e (132 m) | MED-HIGH | 11 | R18 |
| 17 | L4-4 three gate predicates | CONFIRMED (9 sites m) | ~20 e | LOW | 10 | R10 |
| 18 | L5-3 one owned-oil memo | CONFIRMED | ~20 e | LOW | 10 | R8 |
| 19 | L1-2 one gate per move, forward + reverse | CONFIRMED | ~15 e | LOW | 7.5 | R14 |
| 20 | L3-2 named-part suffix chain | CONFIRMED | ~15 e | LOW | 7.5 | R11 |
| 21 | L6-8 recomputeTotals local closures | CONFIRMED | ~15 e | LOW | 7.5 | R12 |
| 22 | L6-7 `per100` (keep the ethanol Atwater) | CONFIRMED (fusion = behaviour) | 10–15 e | LOW | 6.3 | R12 |
| 23 | L2-2 one `_before` | CONFIRMED (5 impl. m) | ~6 e | NIL | 6 | R2 |
| 24 | L4-7 coated-meat pick shared | CONFIRMED (gate stays at the plan) | ~12 e | LOW | 6 | R10 |
| 25 | L6-9 delete the pre-015 totals fallback | CONFIRMED (0 / 1,342 NULL m) | ~12 e | LOW | 6 | R12 |
| 26 | L3-3 `pair()` half only | CORRECTED (hoist half = RAW) | ≤12 e | LOW | ≤6 | R11 |
| 27 | L2-6 one raw-sentence accessor | CORRECTED (§0: GATE-N) | ~10 e | LOW | 5 | R8 |
| 28 | L4-8 one coat-part relation | CONFIRMED conditional | ~18 e | MED | 4.5 | R19 |
| 29 | L1-6 one citrus map | CORRECTED (6 readers) | ~8 e | LOW | 4 | R5 |
| 30 | L1-5 density pair | CORRECTED | 5–10 e | LOW | 3.8 | R5 |
| 31 | L4-10 fried-class memo read twice | CONFIRMED | 7 m | LOW | 3.5 | R10 |
| 32 | L6-6 confirm arm = `_byHoldKind` (⊃ L4-5) | CONFIRMED (equal by reading) | ~7 e | LOW | 3.5 | R13 |
| 33 | L5-7 one aromatic table (⊃ L5-6) | CORRECTED | 5–8 e | LOW | 3.3 | R7 |
| 34 | L2-4 one step dialect | CONFIRMED (census required) | ~6 e | LOW | 3 | R7 |
| 35 | L4-6 one inner loop per round | CONFIRMED (order unobservable) | ~6 e | LOW | 3 | R10 |
| 36 | L6-10 delete `freshMatch` (dead) + `servingBasis` (test-only) | CONFIRMED | ~6 m | LOW | 3 | R12 |
| 37 | L5-6 3 impossible head members | CONFIRMED | 3 m | NIL | 3 | R7 |
| 38 | L4-9 memo-less branch / lazy key | CONFIRMED | ~6 e | LOW | 3 | R20 only |
| 39 | L3-7 bacon flag stem | CONFIRMED | 1 m | NIL | 1 | R9 |
| 40 | L8-6 `_family`'s 5-field arm | CONFIRMED (0 hits corpus + suite) | 1 m | NIL | 1 | R3 |
| S1 | L8-8 26 file-local publics → private | CONFIRMED (§0: all 26) | 0 (lint coverage) | NIL | — | R3 |
| S2 | L8-5 count `setsOut` / `coatsWithCrumbs` | CONFIRMED (0 test refs) | 0 | NIL | — | R3 |
| S3 | L2-3 hoist constant RegExps (⊃ L5-9) | CORRECTED (≈0 lines) | 7 dup sources → 0 | NIL | — | R2 |
| S4 | L5-10 hold strings via the enum | CONFIRMED (25 m) | 0; a typo = compile error | NIL | — | R7 |
| S5 | L1-4 coat / uptake figures from fields | CORRECTED (15 coat + 11 uptake) | 26 literals → formula | LOW | — | R9 |
| S6 | L2-8 Expandos → index memo (⊃ L4-11) | CONFIRMED | 5 stores → 1; 4 made countable | LOW | — | R6 |
| S7 | L1-7(a) name the depth phrase | CONFIRMED | 3 positional reads → 1 name | LOW | — | R14 |

### §1a per-item proof (what the batch must carry beyond GATE-R)
- L2-1: no memo key or counted family reads the param (m); `_feedsStarter`'s list stays until L2-4. Mutant: none
  possible (unread params) — the analyzer + `stepIndexCounts` unchanged are the proof.
- L4-2: replay col 12 on the 162 M52-flag rows (coat 64 · uptake 42 · dip 40 · cut 7 · pan fat 6 · kept solids 2 ·
  crust 1); a differential mapping every plan entry the suite builds (old record → kind) through both `_gramBasis`
  forms; mutant: swap two kinds' phrases → a basis pin dies. Deletes the kept-solids re-derivation 17883–17885.
- L6-1: GATE-P + a carried-decision sweep (a decision on every plain and M52 key of the 268 v82 recipes, and
  apply_to_all from one line): stored == full matchAndCompute, request counts equal per case; RULE C pins
  `knownFoodReads` / `carriedReads`; mutants: swap the sibling-check order, drop `named`, drop `fetch`. BLOCKED on
  Q13 (the apply path's missing `_resolveParts` — decide before merging, so the merge neither fixes nor freezes it).
- L4-1: ONE `Set<_M52Line> _m52LinesAt(recipe, i)` + a named member set per reader (the 9 sites are ≥ 4 different
  predicates: the 7-term plan-weighs test ×3 = L5-1, `_m52OnConfirm`'s 4-term coat, the key's 5-term `dip:`, the media
  hold gate). R15 converts the 6 sites outside `_m52Key` / `_m52KeysAlike` (86 of the 120 code lines); the 3 key sites
  (22560–22578, 22581–22593, 22655–22660) go with L4-3 in R20. Proof: a per-line differential old predicate vs
  `set.intersects` on every line of the 1,342 ids AND every STATED copy the v60–v82 pins build (0 diffs); ≈ 39 member
  mutants (drop each member from each reader's set) each killed by a named pin — a survivor is reported as an
  unpinned member; GATE-P; the `_mediumAt` / `discardedMediumOf` counts must not rise.
- L4-3: after L4-4; the plan reads rows ONLY through a recording view (pass the view, never the rows); oracle: every
  confirm's answer memo-on == a fresh `_m52Plan` over the GATE-P sweeps; the 56 m52PlanRuns pin lines (9 files) and 5
  m52Keys lines hold or fall, never rise; `m52KeyOf`'s v78 / v80 pins get a replacement assertion; GATE-C on the six
  cap shapes the v60 / v61 / v82 cost pins name. The replay builds 0 keys (it proves nothing here — say so).
- L6-3: keep the recipe apply's `moved` via a flag (Q12) so the merge is receipt-neutral; a receipt differential
  (every v82-swept apply case, base vs tip, receipt JSON byte-equal); mutants: drop the layout re-check, swap a miss
  kind; GATE-P.
- L8-3a: delete the function + nutrition_v51_test's MARK test (607–635; 3 of its 7 expects call it) + API.md 3176's
  sentence; v53:368–378 (0215|3, 38.09 g) is the VALUE pin of the behaviour and stays (Q1).
- L3-1: AFTER L4-2 (the row carries its noun); keep the `' and '` chain for form (k) (0 rows / 0 pins / 0 API.md) so
  the bytes cannot move (Q20); first a STATED pin of forms (j) and (k); mutants: drop the yield tail →
  crispy-thai-eggplant-salad|1 moves; swap the list order → horseradish-crusted-beef-tenderloin|3 moves; measure the
  `discardedMediumOf` count per GET (≤ 3 is an upper bound, not a figure). `plusPartOf(line.raw)` 17908 and
  `_eatenPlusPart` are moved VERBATIM (RAW-adjacent).
- L3-6 + L1-4 + L3-7 (one batch): a one-off check that every `_readFig` literal == its formula at 2 dp on the 26
  records — 15 coat calls (b × 0.40 / r) + 11 uptake calls (o / r), 3 kept literal (porkCoated 6.61, parmigiana
  12.12, eggplantParm 7.93), the 13 `_derivedFig` untouched; `value` stays the 2-dp string `double.parse` reads;
  mutants: 0.40 → 0.41 and o → b each kill a named coat / uptake pin; drop the C4 tail → better-chicken-marsala|6
  moves; pan fat via the uptake getter with `b` → parmesan-crusted-chicken-cutlets|6 moves.
- L1-3: mutant `_lambRack.share` 0.73 → 0.72 must kill a VALUE pin (v43 / v62 / v79 'lamb rib loin (rack)' basis,
  the replay's 2 rack rows); v55:645 and v62:696–697 become tautologies — not counted as kills.
- L3-5: 234 + 2 rows end `× S edible · approximate (`; the AH-102 suites green; a compile-time identity.
- L5-2: `[String? normalized]` derived inside when null (73 test sites / 37 files untouched); 3 reroutes (5993,
  21545, 22771) through `_mediumAt` only AFTER R6 (L2-8) — else the reroute widens `_mediumAt`'s oracle blind spot;
  grep that no engine call passes a 3rd positional arg; `lineItemOf` itself is NOT rewritten (it is the RAW reader the
  fields replace — this item turns its 16 call sites into 1, which helps that later batch).
- L6-5: the helper keeps `clearHold` over `hold:` (salt_database 3630); unskippedRow's no-clearHold copy stays a no-op
  difference; mutant: flip the precedence → the F7 / closer-4 hold pins die; GATE-P (3 of 6 copies are person arms).
- L6-4: `rankedFor(line, query, hits, {recipe})` + `trimArmOf(recipe, ranked)` called by trimDepthRecord AND
  `_carriedIdOf` (one encoding of 168743 → 173128); a differential over every snapshot line: candidatesForLine
  (cacheOnly) vs the compute's chain return the same ids in order; F10 pins + cost_bounds `carriedReads` exact;
  mutant: drop the recipe arm from `trimArmOf` (the GET flat and the carried flat pins both die); GATE-P.
- L6-2: after L6-13 / R0; `_decidedOn(…, {required _M52Row? entry})` keeps the entry injection (derivedFor's m52 arm
  sets the `discarded` form the plan's candidate scan reads); GATE-P + GATE-N (derivedFor's note); the 56 m52PlanRuns
  pins unchanged.
- L4-4: one mutant per predicate (negate a term) dies on its shape's pin (H: v60 / v71; C: v66 doughnuts, v71 0659);
  delete the aliases `counted` / `engine` (21579–21580).
- L5-3: AFTER R3 (L8-3a removes the read at 3000 → 4 readers: 2746, 2865, 2982, 3535); GATE-N (3535 is holdNoteOf's
  ambiguous note); `memo:keptOil` keeps its once-per-line-text bound (cost_bounds 306), the new family exact.
- L1-2: a const list of (map, gate) read by `skinOffFood` and `decisionRecordOf`; the reverse stays WITHOUT
  `weighed` (decisionRecordOf has no resolution) — the shared gate is the line / recipe half only; `buysRefuse`,
  `boughtInShell`, `keepsWholeCan` called verbatim (RAW-adjacent); keys / values disjoint (a one-line assert in the
  batch's test); mutants: drop `boughtInShell` (v49 mussel pins die), drop `skinDiscarded` (v39 skin pins die); GATE-P
  (decisionRecordOf is corpus-blind). The round trip is NOT here (L6-11 → matcher series).
- L3-2: one `[...nonNulls].join(' · ')` over (measure, fit, standIn, m50, m52); first a STATED pin of a fresh-herb coat
  part at 0 g with an m52 flag (no corpus row has one); mutant: fit after standIn → the 7 approximation + stand-in
  rows move (ginger 4, ricotta 2, kasseri 1).
- L6-8: recordOf keeps the read order own → sibling (`knownFoodReads` pins); the child arm's missing `kept` guard is
  unreachable (0 of 79 routed rows carry a food id) — the shared closure adds it, stated.
- L6-7: one `per100(record, def)` for the five reads; the ethanol formula KEEPS its `204`-only fat term (fusing it
  onto `204 ?? 298` changes a typed alcohol record → Q17); digest unchanged (765,642.77, kcalCheck 208).
- L2-2, L4-7, L4-10, L4-6, L5-6, L3-7, L8-6, S3, S4: GATE-R alone (pure / const-identical / unobservable order —
  each measured in its lens: L4-6's loop 1 never makes `_m52Weighs` false; L4-7's `_isMeatRow` is null-safe where the
  inline copies assert `description!` — equal while a counted row has a description, stated).
- L6-9: `totalsJson` required; the 4 seeds (p5_edit_http ×2, recipe_review ×1, bulk_scope ×1) pass batch totals
  (value re-pin, no expectation moved); grep: no `nutrientsJson` read left in the totals path.
- L3-3 (`pair()` half): `pair(lead, to, what)` covers the 4 spellings (17717, 17725–17728, 17736, 17777–17780); only
  the corned-beef TITLE regex is hoisted; the `raw.toLowerCase()` word arms are untouched (RAW); mutant: a swapped
  lead → onion-braised-beef-brisket|0 or home-corned-beef-with-vegetables|0 moves.
- L2-6: GATE-N (§0) + `rawSentences` re-pinned as equalities (v25_rules 1, cost_bounds 1); `_sentenceAt` stays.
- L4-8: ONLY if a private probe finds 0 two-coat lines in the corpus and in every STATED copy; per-recipe set
  equality over the 1,342 ids + the v71 / v82 F6 copies (0279 shrimp, 0407 eggplant); else keep both + one doc line.
- L1-6: the merged map still serves 12364's `_citrusPeel.values.any(…)`; `_zestPlusFruit` 12475 untouched (RAW).
- L1-5: mutant: drop recordFirst on 'lentil' (candidates vospov-kofte|1, red-lentil-kibbeh|9) — confirm a pinned row
  moves, else add the pin.
- L6-6: `final (:grams, :source, keepsHold: _, resolves: _) = _byHoldKind(row, eaten, outcome);`; GATE-P (order C
  2,831, 0254 / 0149); mutant: the arm's `?? 0` dropped still dies. L4-5's further "one tail" (~25) is unmeasured —
  not in the ledger.
- L5-7 (+ L5-6): a unit test enumerating the old sets' membership against the table (equality).
- L2-4: a census that each of the 6 raw-case patterns' any() is equal raw-insensitive vs lower over the 5,475 main
  steps (expected 0 diffs) — required; `_rubStep` → `_rub`; `_kept` keeps `caseSensitive: false` for the title.
- L6-10: `freshMatch` off Resolving now; `servingBasis` only with its ≤ 15 test calls (6 files) rewritten to seed the
  basis (they pin the stamp, which survives).
- L4-9: only inside R20 (m52Keys exact counts re-pinned); rp43.dart:255's memo-less `gramBasisFor` call must keep
  working (`memo ?? ResolverMemo(db)`).
- S1 (L8-8): pure rename; re-point API.md (skinlessRecords 2, shellRecords 1, scallionPartOf 1) and the cross-library
  doc mentions (matcher / grams name skinlessRecords, shellRecords, skinOffFood); + the 9 test-only publics get
  @visibleForTesting (no deletion).
- S2 (L8-5): both families into `boundsOf` + one RULE C shape each (or drop the memo by an ABBA — GATE-C).
- S5 (L1-4): see L3-6 above (one batch).
- S6 (L2-8): 5 new families in cost_bounds; GATE-C (memoOffForTest on vs off, two orders; the oracle file's run time
  measured — `_mediumAt` re-derives per call under the oracle); a drop-memo mutant per family dies.
- S7 (L1-7(a)): `_depthPhrase` read by name at 15781 / 15965 / 17694 — the "APPENDED, never first" contract (15637)
  goes; zero behaviour.

### §1b Tests (lines of apps/server/test; GATE-T unless stated)
| # | id | verdict | gain | risk | score | batch |
|---|---|---|---|---|---|---|
| 1 | L7-1 delete the 31 v-file `expect(matcherVersion, 78)` tests (keep seasoning_ci:83, the CI one) | CONFIRMED | 554 m (~430 RE-PIN); 31 edits per bump → 1 | NIL | 554 | R1 |
| 2 | L7-3 row tables → committed golden TSVs (UPDATE_*=1 regenerate, as contract_golden) | CONFIRMED in kind | ≤ 13,900 e Dart → ~1,700 TSV | LOW-MED | ≤ 4,067 | T3… |
| 3 | L7-4 one support/row_harness.dart (11 helpers, 203 copies) | CONFIRMED (10 of 11) | ~2,340 m → ~300 e | LOW | 1,020 | T3… |
| 4 | L7-8 test→test imports → support/ | CONFIRMED | 39 import lines / 18 files; unblocks T3 / L7-2 / L7-6 | NIL | 39 | T2 |
| 5 | L7-5 split nutrition_v26_cost_test (3,484 lines) by subsystem | CONFIRMED (tail ≥ 242 s m) | wall 6:26 → ~3:40 e per full-suite gate | MED | — | T4 |
| 6 | L7-6 per-mechanism suites, group by group | CONFIRMED (+ own-commit rule) | ~3,400 e (1,202 imports + 2,208 headers) | MED | — | rides R-batches |
Proof notes: L7-1 — the kept pin fails on `matcherVersion = 77`; the result count drops by exactly the deleted tests.
L7-3 — the batch's generator reproduces every current table cell from the golden (0 missing, 0 changed); a golden in
rp43's 22 columns TIGHTENS some tables (state it per table, never widen); v71–v73's `_files` order kept per golden
(fixture state is order-dependent, v71_test 7771); the reviewer diffs the golden. L7-4 — each caller's column set
kept or tightened (stated); per-file test names + count equal. L7-5 — every count pin exact before / after (record each
asserted `stepIndexCounts` map, cmp); each new file alone and in the full suite; three timed full suites; the group
"Bounded, exact process-wide and per-request memos" (v26:587) stays in ONE isolate. L7-6 — a moved group is its own
commit inside the engine batch, with the count-and-value equality proof (so reviewers diff code and tests apart).
Pool note: L7-3's ≤ 13,900 is the planner's row-shaped subset of the 104 non-must-not-move tables (17,567 lines);
the 5 extra must-not-move tables (~610 lines) and `_v71Totals` (224) are counted under L7-2 / L7-9, not twice.

### §1c Comments (GATE-R minus the suites: analyzer + format + the v44_storage grep-pin 800–842)
| 1 | L8-9 version tombstones (grams 2503–2518, 3193–3197, 2187–2188, 3159–3160; engine 12372, 14126–14128; matcher 1886, 2881; 4 vanished symbols) | CONFIRMED | ≈ 30 e | NIL | 30 | R4 |

### §1d Owner-gated (CONFIRMED, replay-neutral, but a rule / process / pin-deletion ruling first — §5)
| # | id | gain | risk once ruled | score | Q |
|---|---|---|---|---|---|
| 1 | L7-2 the 18 must-not-move tables (CORRECTED: 13 + v58 `_kept`, v74 `_negatives`, v78, v79, v80) | ≈ 21,731 m test lines, 105+ RE-PIN | LOW (fixture path: 45 of 1,756 rows differ from the snapshot) | ~10,900 | Q2 |
| 2 | L8-1 matcher.dart 132–1025 history block | 894 m comment lines (matcher −19 %) | NIL | 894 | Q3 |
| 3 | L7-7 stop writing RE-PIN comments | 398 m left after L7-1/2/3; 26–117 per batch | NIL | 398 | Q4 |
| 4 | L7-9 `_v71Totals` + moved-since-v71 expects | ~250 m | NIL | 250 | Q2 |
| 5 | L5-5 delete `_brineShareOf` + `_bundled` (after R2: its `_stepsOf` call) | ~45 m lib (0 of 88 brine rows) | NIL | 45 | Q6 |
| 6 | L5-4 delete `DiscardedMediaPolicy` + `coatingFraction` + engineOutcome's `coating` param | ~36 m lib, 2 pins | NIL | 36 | Q5 |
| 7 | L8-2a delete the v7 re-key fallback (decision_rekey 82–110 + `byReading`) | 32 m lib, 45–90 test | NIL | 32 | Q7 |
| 8 | L8-4 delete `eatenOrder` (3466–3481 + family + 2 count pins) or pin it | 16 m | LOW | 8 | Q8 |
| 9 | L2-7 `index.where(p)` (22 families + `lastMatching` → 1) | ~90 e net | MED (RULE C design change) | 22.5 | Q10 |
| 10 | L1-11 poultry class-yield keys (12 keys, 0 rows) | ~10 e | NIL | 10 | Q9 |
| 11 | L2-5 `_baconKept` / `_yieldOilFlag` onto the index window | ~5 e | LOW (cap shapes move) | 2.5 | Q11 |
Proof once ruled: GATE-R (lib items) / GATE-T (test items) + the named pins deleted BY the ruling, nothing else;
L7-2 needs, first, the per-file list of mutants a table alone kills (re-home them) and — recommended — the rows
folded into L7-3's goldens rather than deleted (keeps the FixtureProvider path; ≥ 1,525 rows → TSV); L2-7 needs GATE-C
(the short-circuit loss; +0.9 % sentence tests is a Python approximation) and 48 pin refs re-pinned as equalities;
L8-4 the mutant log m_eatenOrder.log as the "before" (killed only by v27_cost 211 / 240 count pins).

### §1e [BEHAVIOUR] — not kcal-neutral or moves a person-path answer → the MATCHER series, never a refactor batch
- L2-10 `_mixVerb` prefix vs `_mixesWord`: 1,054 corpus sentences / 588 recipes disagree; `_leftInBowl` (5857, 5879)
  can move up to 3 recipes' Q21 flags (0255, 0758, 0852) — an F4 sibling, attr.py-attributed.
- L6-1's apply path calls no `_resolveParts` (0 hits in 19992–20333; compute 14605 / 14809): an applied bacon decision
  whose B1 parts record no cache holds may stamp the recipe waiting on USDA — PLAUSIBLE (argued) → reproduce first.
- L6-11 the move inverses' round trip: 0150|6 (173619 meat only, `piece`, 0.56) — a Confirm decides 172378, a record
  the line's own moves never reach — PLAUSIBLE (163 rows on a move's source / target; 1 with a non-weight source).
- L6-7's Atwater fusion (ethanol onto `204 ?? 298`): corpus-neutral (4 fat-298-only records, none alcohol, none
  publishing energy) but changes a typed alcohol record.
- L3-1 form (k) list wording; L3-4's 7 doubled stand-in rows; L3-9 one flag channel; L3-11 one prefix word
  (811 / 425 segments, ~1,456 test literals) — copy / API rulings (mockup-first for any app change).
- L6-3's 4-way miss split for the recipe apply (a receipt change).

### §1f [waits for the YAML fields] — LAST; what they wait for: the structured measurement / item / alternative fields
### of the ingredient-line rework (another agent; no key removals). Each reader then reads the field first, the raw
### parse kept as the fallback for old documents. Proof then: per reader, a differential raw-parse vs field over all
### 14,567 lines (identical medium, eaten part, item key), then the replay with every moved row attributed (attr.py) —
### NOT byte-identical by nature: this is the matcher's adjustment round, not a refactor.
- L2-11 (⊃ L5-8): 35 step readers re-parse the line on 63 code lines (engine-wide `lineItemOf(` 67,
  `normalizeItem(lineItemOf(` 61, `.raw.toLowerCase()` 27, `headNounOf(normalizeItem(lineItemOf(` 15 — lexer m);
  the two strained-solid predicates (`_strainedOut` 4711–4724 vs `_keptSolidsOf` 22248–22253, the juice term
  diverged, 0 corpus rows) become one THEN (zest|peel ∧ juice lines: 72 / 78 / 85 by method — the critic's 78).
- L2-12: the three A13 mention readers (`_ownMentions` 4 callers, `_lineMentionsOf` 7, `_linesNamedIn` 2; 95 lines) —
  a census of every line's three assignments first.
- L1-9 (⊃ L3-4): trimStandInFlagOf's 8 word-keyed arms → one (item, record) → label table (112 rows; ~40 lines);
  L1-10: approximationRecords (111 keys; 110 also `_rankAs` 99 / `_queryRewrites` 11) folded into its rank-as /
  rewrite entry (~113 table lines, +111 fields).
- L1-7(b) phrase half; L3-3's hoist / lower-once half (the word arms); L4-13 (the plan's `words` builder ×2, the R2
  eaten-part read, `_keptSolidsOf`'s raw zest, `_m52Laid`'s raw compare); L5-12 (38 raw reads in 13 media functions;
  `_forFrying` vs `_labelledFrying` stay two signals — 0357|10 and 0506|7 differ); L8-2b (`dropPrep`, −5); L8-3c
  (`yieldNamesOwnSection` takes a Recipe, `_yieldRead`'s null arm, −4 — or only its memo plumbing earlier).
- Before the fields land, RUN T2–T3 (L7-8, L7-3, L7-4): the adjustment round then re-pins by one golden
  regeneration per suite instead of hand-editing ~1,500 tabled rows (L7's measured reason).

### §1g Enablers (no lib / test change; do FIRST — R0)
- L6-13 archive sw3–sw8 + run.sh / shard.sh (54,937 B, scratchpad-only) to .claude/diag/harness/person_sweeps/ with a
  README line each (spec, base tree, base divergence): the ONLY proof of every person-path item.
- L3-12 + §0's correction: give rp43 a SEPARATE `--notes=notes.tsv` dump (holdNoteOf per row) so rows.tsv stays
  cmp-identical to v82_rows.tsv; take its baseline from fab9f0f; GATE-N reads it.
- The audit's own proof kit, equally scratchpad-only: L5work (census replicas l5Tag / l5TagSkip / strain, self-checked
  0 mismatches on 14,567 lines), L8work (rp43 under --branch-coverage, test_cov.sh, who.py / armwho.py, mutate.py),
  l4census, critic/*.py, L7tools, synth/*, and L1–L8.md + critique.md + this ledger → .claude/diag/2026-10-27/simp/
  (the 2026-10-15 wipe lost the harness once).

## §2 THE REFACTOR SERIES (small, one subsystem each; every batch GATE-R + its adds; each base = the previous tip;
##    the reference TSVs stay v82's because every batch is byte-identical; matcherVersion 78 throughout)
| batch | subsystem | items | gain | gate adds | needs |
|---|---|---|---|---|---|
| R0 | proof kit (no lib / test diff) | §1g: sweeps archived, rp43 notes dump + fab9f0f baseline, audit kit archived; the §5 rulings collected | enabler | — | — |
| R1 | tests: version pins | L7-1 | −554 test | GATE-T | — |
| R2 | step readers: dead params, pure order | L2-1, L2-2, S3 (L2-3 ⊃ L5-9) | ≈ −46 lib; 7 dup patterns → 0 | — | — |
| R3 | dead surface | L8-3a, L8-3b, L8-6, S1 (L8-8 + 9 @visibleForTesting), S2 (L8-5) | −49 lib, −29 test | GATE-C (S2) | Q1 for L8-3a's MARK test |
| R4 | comments | L8-9 (+ L8-1 once Q3 rules) | ≈ −30 (+894) | analyzer, format, grep-pin | Q3 for L8-1 |
| R5 | record tables / constants | L1-3, L3-5, L1-6, L1-5 | ≈ −40…−45 | — | — |
| T2 | tests: plumbing | L7-8 | −39 imports | GATE-T | — |
| R6 | step index memo store | S6 (L2-8 ⊃ L4-11) | 0; 5 stores → 1 | GATE-C | R2 |
| R7 | media classification | L2-4, L5-6, L5-7, S4 (L5-10), L5-2 | ≈ −39…−42 | GATE-N (S4), L2-4 census, membership test | R0, R6 |
| R8 | frying oil owners + notes | L5-3, L2-6 | ≈ −30 | GATE-N, rawSentences equality | R0, R3 |
| R9 | M52 text | L3-6, S5 (L1-4), L3-7 | ≈ −16; 26 literals | figure==formula check | — |
| R10 | M52-a (plan + `_gramBasis` phrase, auto arms) | L4-2, L4-4, L4-7, L4-10, L4-6 | ≈ −115 | differential plan entry → kind | — |
| R11 | basis composer | L3-2, L3-1, L3-3 (`pair()` half) | ≈ −45…−67 | STATED pins first (forms (j)/(k); fresh-herb coat part) | R10 |
| T3… | tests: goldens + harness, ONE suite per batch | L7-4, L7-3 (+ L7-2's rows folded in once Q2 rules, + L7-9) | ≈ −14,000 Dart over the T3 series | GATE-T, cell-for-cell generator check | T2 |
| R12 | totals write path (local) | L6-8, L6-10, L6-7 (`per100` only), L6-9 | ≈ −43…−48 | digest 765,642.77 | — |
| R13 | person paths (local) | L6-5, L6-6 | ≈ −32 | GATE-P | R0 |
| R14 | ranking + move chain | S7 (L1-7(a)), L1-2, L6-4 | ≈ −50 | GATE-P, compute / sheet differential | R0, R3 (renames) |
| T4 | tests: cost suite | L7-5 | wall ≈ −2:45 e | GATE-T, GATE-C, 3 timed suites | T2 |
| R15 | M52-b classifier | L4-1 on the 6 non-key sites (⊃ L5-1) | ≈ −57 e (pro rata 86 / 120 of L4-1's 80) | per-line differential, ≈ 39 member mutants, GATE-P | R10 |
| R16 | person paths: weighed row | L6-1 | ≈ −110 e | GATE-P + carried / apply sweep | Q13 settled in the matcher series |
| R17 | person paths: apply skeleton | L6-3 | ≈ −75 e | GATE-P + receipt differential | R16, Q12 |
| R18 | person paths: sync core | L6-2 | ≈ −55 e | GATE-P, GATE-N | R13, R16 |
| R19 | M52-c | L4-8 (only if the two-coat probe = 0) | ≈ −18 e | per-recipe set equality | R15 |
| R20 | M52-d (LAST non-YAML) | L4-3, L4-9, L4-1's 3 key sites | ≈ −190 e | the confirm oracle over the sweeps, GATE-C at the 6 cap shapes | R10 (L4-4), R15, R19 |
| O-batches | owner-gated, each once ruled | L5-5 (after R2), L5-4, L8-2a, L8-4, L1-11, L2-7 (after R6, GATE-C), L2-5 (rides R8's bacon reader) | §1d | GATE-R + only the ruled pin deletions | §5 |
| Y (LAST) | [waits for the YAML fields] | §1f, in reader order: L2-11 / L5-12 / L4-13 / L8-2b / L8-3c (item + measurement reads), then L2-12, L1-9, L1-10, L1-7(b) phrase, L3-3 word arms | ~265 lines touched (not counted as deletable) | §1f's differential + attributed replay (NOT byte-identical) | the fields landed; T3 done |
Why this order: R1–R5 are zero-count / zero-value (NIL–LOW, no person path) so the series and its gate get proved on
the cheapest diffs first; R6 precedes R7's `_mediumAt` reroute (oracle blind spot); R3's `keptOilFries` deletion
precedes R8 (one of its five reads); R10 precedes R11 (the row carries its noun) and R15 (the gates); the person-path
merges (R13 → R16 → R17 → R18) need R0's sweeps; L4-3 is HIGH and goes last, after L4-4's three predicates funnel the
plan's reads; T-batches interleave freely (no lib diff) but T3 must finish before Y. L7-6 rides every R-batch as its
own commit (the subsystem's groups move into its suite).

## §3 TOTALS (sums of §1 / §2; "m" = measured by grep / span, the rest planner estimates each batch must measure)
- LIB LINES DELETABLE, kcal-neutral series (R2–R20, no ruling): ≈ 1,010–1,045 code lines of the 33,536 in engine /
  matcher / grams / handlers (≈ 3 %): ≈ 505–540 in the NIL–LOW-MED batches R2–R14 (93 of them measured outright:
  L8-3a 37, L1-3 14, L3-5 13, L8-3b 11, L4-10 7, L6-10 6, L5-6 3, L3-7 1, L8-6 1) and ≈ 505 in the MED–HIGH merges
  R15–R20 (L4-3 165, L6-1 110, L6-3 75, L4-1 80, L6-2 55, L4-8 18, L4-9 6 — all estimates from measured spans).
  + comments: L8-9 ≈ 30 now; L8-1 894 once Q3 rules (matcher.dart −19 %).
  + owner-gated code: ≈ 234 (L2-7 90, L5-5 45, L5-4 36, L8-2a 32 in decision_rekey.dart, L8-4 16, L1-11 10, L2-5 5).
  If every ruling is yes: ≈ 1,250–1,280 code + ≈ 924 comment lines.
- TABLES MERGEABLE (now): 9 table declarations → 4 (citrus 3 → 1, densities 3 → 2, aromatic head sets 3 → 1);
  one-fact-many-places deduplicated: the rack flag 3 → 1, the bacon stem 2 → 1, the FNDDS phrase 3 → 1, the
  SR-derived phrase 2 → 1, "(no record for" 4 inline → the helper, the edible template 3 → 1, the braised-pair phrase
  4 → 1, 26 coat / uptake literals → their record's fields, 9 `_M52Row` literals → `_M52Kind` data + 1 builder,
  9 hand-kept M52 disjunctions → 1 classifier + named member sets, 6 move gates → 3, 20 hold literals → the enum.
  Owner: boneInClassYields' 12 poultry keys (0 rows). After the YAML fields: approximationRecords (111 keys) folded
  into `_rankAs` / `_queryRewrites` (−1 table), 8 word-keyed stand-in arms → 1 table. NOT merged: the "one record
  table" (L1-1 — 20 int-keyed tables, 14 value shapes, 1.27 declarations per record; gain ≤ 0).
- MEMOS UNIFIABLE: memo stores 6 → 1 (the index's + 5 per-Recipe Expandos; 4 uncounted, all 5 outside the
  memoOffForTest oracle — R6); uncounted families 2 → 0 (R3); one-memo re-derivations: the oil owner entry ×5 → 1
  (R8), `_friedClassOf` ×2 → the memo (R10), the raw split per call → per step (R8), `discardedMediumOf` ≤ 3 per
  discarded row → 1 (R11, an upper bound to measure); the M52 key mirror (3 functions, ~215 lines) → a recorded-reads
  check (R20). Owner: 22 sentence-scan families + `lastMatching` → 1 `memo:where` (L2-7, −22 cost_bounds entries);
  `eatenOrder` deleted (L8-4). cost_bounds net: +5 (R6) +2 (R3), −22 with L2-7.
- TEST LINES FOLDABLE (of 120,904 in 100 v-files): series ≈ 18,000 — L7-1 554 m, L8-3a 29 m, L7-8 39 m, T3's
  L7-3 + L7-4 ≈ 14,000 net (≤ 13,900 → ~1,700 TSV; ~2,340 → ~300), L7-6 ≈ 3,400 (imports + headers, as files
  empty); owner ≈ 22,450 — L7-2 21,731 m (18 tables; ≈ 20,200 net if folded into goldens), L7-9 ~250, L7-7 398,
  L8-2a 45–90. All: ≈ 38,900–40,500 (32–33 %). Every future batch then edits one suite + one golden instead of 23–36
  older files (v71–v82 measured: 276 older-file edits); a version bump edits 1 file instead of 31.
- WALL: the full server suite 6:26 → ~3:40 est. (L7-5; the v26_cost serial tail ≥ 242 s measured) — every gate runs
  it several times per batch.

## §4 WHAT MUST NOT CHANGE (no refactor batch may move these)
- THE BYTES: v82_{rows,recs,sections,calls}.tsv + v82_bucket.out (14,567 rows, 1,342 ids; kcalCheck 208, sections 144,
  calls 0; digest 765,642.77); from R0 the notes dump; matcherVersion 78 (a bump re-stales every recipe).
- THE THREE-CALL INVARIANT compute == PUT == GET (stored == recomputeTotals == matchAndCompute, GET == stored) on every
  person path — today held by the swept 123,862 cases, structurally only after R18.
- SINGLE SOURCES that already serve every caller (keep, never re-fork): recomputeTotals (the only totals writer;
  rebaseNutrition is the serving-basis route by design since v27), derivedFor (every decided row), routeShareOf,
  decisionRecordOf (offer == write), `_byHoldKind`, `_StepIndex` (sentences split once, `lower` once, `hits` keyed
  (RegExp, step) — keep a stable pattern identity), `naming` / `_occurrences` / `hits` + `sentenceAt` (three primitives,
  three jobs).
- RULE C: every memo family counted and bounded (`expectBounded` fails on an unknown family — "a memo no pin counts
  can be deleted with every test green", engine 363–367); the memoOffForTest exactness oracle (v27_memo_keys, v54, v76,
  v81); the 1,000-char window `maxScannedSentence` (inert on the corpus, longest sentence 371, but the editor-cap
  bound); one count pin per compound derivation (Run 055 S16) — only L2-7, if ruled, changes that design.
- THE M52 PLAN's stage order: candidates → coat budget (parts → k → B → f; W = 1.173 × B; C4 pan fat on the coated
  grams) → H holds → fryer (uptake reads stage 2's `batterCho`) → pans; kept solids alone; the per-shape float op order
  and rounding (L4-12 deferred for that reason); the 3-round revert ceiling (`ponytail:`); the key's own `ponytail:`
  until R20.
- PINNED TEXTS, byte for byte: every gram_basis (col 12: 13,419 rows, 4,620 suffixed, 1,583 distinct) and flag
  (col 19: 243 rows); the 174 pinned strings beyond the corpus (person paths, STATED copies, zero-reach arms:
  168743-depth, `pair()` = null "no step skims…", 174377 gross, "entered by hand", "poured away — counted as 0 g",
  "is partial:", discard forms (j) / (k)); every hold_note; API.md's quoted texts; both prefix words "approximate (" /
  "approximation (" (811 / 425) until Q15; trimStandInFlagOf's public signature (45 test calls / 10 files); the flag
  texts L1-8 kept verbatim.
- PUBLIC SYMBOLS tests and the harness read: nutrientSiblings, braisedKept, approximationRecords, volumeSiblings,
  boneInClassYields, ah102Meats, dryHeatKept, ah102Parts, trimDepthRecords, cannedBeanShares, alcoholRecords … (150
  test reads of 15 symbols); rp43's matchAndCompute / gramBasisFor (memo-less, rp43.dart:255) / compositeFlagOf /
  bulkScopeIds — their signatures or the gate breaks.
- RAW-LINE READERS stay unrewritten until the fields land (§1f); RAW-adjacent items (L1-2, L1-6, L3-1, L3-2, L5-2,
  L5-5) CALL them verbatim. `_forFrying` and `_labelledFrying` stay two signals (2 corpus lines differ).
- NOT DEAD (corpus-unreached but pinned or person-reached): the H-dip branch, `_m52OnConfirm`'s three branches,
  `_unplannedOf`'s pick / confirm / carried-decision arms, recomputeTotals' revert rounds 2–3, the 79 corpus-zero
  person-path / seam functions, the 21 test seams, the cache-cap clears; the typed-line guards of L5-11 ('for soaking'
  0 lines, the `_kept` guard, 'for brining' 4, shortening / lard); every `discardedMediumOf` arm (31, none superseded),
  every `_strainedOut` / `_discardedByName` exit; partial use (~380 lines, 9 rows, each an owner ruling); `_yieldOil*`
  (Q12 (a), 1 recipe); the 83 lines nothing runs (L8-7: pin gaps, not deletions).
- KEPT BY MEASUREMENT (no change): L1-1 one record table, L1-8 cooked pairs as data (≈ 0 lines on verbatim-pinned
  flags), L1-12 sibling maps, L1-13 single-record sets, L2-9 the alcohol sentence model (two depth rules by
  construction), L3-8 AH-102 flags (32 / 32 agree), L3-13 composite's flag-to-null, L6-14 the PUT's three derivedFor
  calls.
- TEST ASSETS: person-path pins (373 `applyMatchOverride(` calls / 48 files, receipts), STATED constructions (241 / 39
  files), 180 stepIndexCounts refs + cost_bounds' 164 families, each mechanism's reach rows (as goldens), the macro
  columns (v72 `_totals`), the corpus-free CI checks (10 v-files + seasoning_ci + pinned_corpus_text), the
  design-regex oracles (v26_cost 1464 / 2699 / 2817 / 3334, v72:7267, v74:186, v79:378, v81:1712, v81:1809 — they may
  move, not go), v71–v73's `_files` order, and every pin a recorded owner mutant needs.

## §5 OPEN QUESTIONS FOR THE OWNER (each with my recommendation; nothing in R1–R15 waits on them except where named)
- Q1 May a refactor batch delete a pin whose check SURVIVES elsewhere (L7-1: seasoning_ci:83 keeps the version check;
  L8-3a: v53:368–378 keeps 0215's value)? Rec: yes — the mutant still dies on the kept pin (GATE-T proves it).
- Q2 The 18 must-not-move tables (L7-2, ≈ 21,731 lines) and `_v71Totals` (L7-9): the replay is not committed, not in
  CI, needs the 57 MB snapshot and computes on snapshot data while the tables compute on FixtureProvider (45 of 1,756
  rows differ). Rec: FOLD their rows into L7-3's goldens (keeps the fixture path, ≈ 20,200 lines net) rather than
  delete; delete `_v71Totals` (a previous tree's values, re-pinned twice already).
- Q3 matcher.dart's 894-line history (L8-1): delete, or move verbatim to docs/MATCHER_HISTORY.md — and stop appending
  a per-batch entry there? Rec: move to docs (the maintained-docs rule), keep the 9-line contract + a pointer.
- Q4 Stop writing RE-PIN comments once a suite has a golden (L7-7; the golden's diff and the commit message become the
  re-pin record)? Rec: yes, from the first T3 batch on.
- Q5 Delete the two never-flipped USER SWITCHes (L5-4: `DiscardedMediaPolicy.review` read nowhere; `coatingFraction`
  superseded by the M52 coat budget since v53) with their 2 pins? Rec: yes.
- Q6 Delete `_brineShareOf` + `_bundled` (L5-5: 0 of 88 brine rows; kept alive by one STATED pin, v14a A2)? Rec: yes.
- Q7 Retire the v7 re-key fallback and its 2 v9 pins (L8-2a; 0 decisions; the 2026-10-09 no-compatibility ruling
  covers it)? Rec: yes; keep the 2 re-keyed-first v9 instances (they pass without it).
- Q8 `eatenOrder` (L8-4: corpus-dead, killed only by 2 count pins, no behaviour pin): delete, or add one STATED
  behaviour pin? Rec: delete (no row, no behaviour pin relies on it); add STATED pins to the three 1–5-line arms.
- Q9 boneInClassYields' 12 poultry keys (L1-11: 0 rows; the documented Y4 fallback): Rec: KEEP (−10 lines is not worth
  a rule change for future lines).
- Q10 `index.where(p)` (L2-7) replaces 22 per-derivation count pins with one per-pattern bound — a RULE C design
  change (Run 055 S16 argued the per-derivation form). Rec: yes, only if GATE-C's ABBA at the editor caps shows no
  regression from the lost short-circuit.
- Q11 Align `_baconKept` / `_yieldOilFlag` to the 1,000-char window (L2-5: corpus-neutral, moves only a > 1,000-char
  cap shape)? Rec: yes, with one STATED windowed-bacon pin — it closes the one detector the window does not bound.
- Q12 The recipe apply's receipt: keep `moved` for every miss (neutral) or adopt the food apply's moved / decided /
  gone split (L6-3)? Rec: keep `moved` in R17; the split, if wanted, is a matcher-series receipt change.
- Q13 The apply path's missing `_resolveParts` (L6-1, PLAUSIBLE): reproduce and fix in the matcher series BEFORE R16?
  Rec: yes — R16 must not merge an asymmetry it cannot tell a rule from a bug.
- Q14 The skin / shell / can inverses' round trip (L6-11: 0150|6's Confirm 172378 vs 173619, PLAUSIBLE): Rec: matcher
  series, with a Confirm sweep over the 163 move rows.
- Q15 Copy / API: one flag channel (L3-9), one prefix word (L3-11), the 7 doubled stand-in rows (L3-4), form (k)'s
  wording (L3-1). Rec: leave all four (byte-neutral is the series' rule; an app change needs a mockup first).
- Q16 `_mixVerb`'s prefix (L2-10: 1,054 sentences / 588 recipes disagree; up to 3 recipes' flags): Rec: matcher series
  (an F4 sibling), attributed by attr.py.
- Q17 Fuse the ethanol Atwater onto `204 ?? 298` (L6-7)? Rec: leave it out of R12; matcher series if ever.
- Q18 The gate lives under .claude/ (not version-controlled) and in a scratchpad that was wiped once: commit rp43 +
  bucket_v12 + the person sweeps + attr.py as a tool/ directory of the repo, or keep the R0 archive only? Rec: commit
  them (the series' only proof outlives a scratchpad), the snapshot itself staying local.
- Q19 Dual-fleet review per batch for the zero-count / zero-value batches R1–R5, T2? Rec: yes for R2–R5 (lib diffs);
  R1 / T2 (test-only, GATE-T) a single fleet — the standing rule says every review runs twice, so this is the owner's
  call.
- Q20 L3-1 form (k): keep the `' and '` chain (0 rows / 0 pins) — confirms Q15's "leave"; listed so R11 does not
  decide it silently.
