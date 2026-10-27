-- v12 = bucket_v11.sql + the sections arms (matcher v44, a18da27). REBUILT 2026-10-15: the
-- original v12 was lost with the scratchpad and its exact output is gone — this rebuild's output
-- (on a replay copy after rp43) is THE REFERENCE FROM v71 ON; do not diff it against older
-- bucket_v12 .out files. Main rows are recipe_id = host_id; section rows (key `<host>#<title>`)
-- are the rest. The CASE is SaltDatabase._reviewBucketCase verbatim (v11's arms: the no-record
-- arm, choose_recipe, a composite row is no no_match, the discarded/unmeasured arm counting
-- 0 g rows only) plus ONE harness arm: `blocked` — an engine line FDC could not serve
-- (engineUnavailableNote; rp43's rows col 22), ahead of no_match. Composite kinds use the
-- original's names (routed_section / section_held, e3dc14c "routed_section 60 -> 64").
CREATE TEMP VIEW b AS SELECT im.*,
  CASE WHEN im.recipe_id = im.host_id THEN 'main' ELSE 'section' END AS part, CASE
  WHEN im.status = 'skipped' THEN 'skipped'
  WHEN im.hold IN ('food_gone', 'food_unavailable') THEN 'check'
  WHEN im.hold IN ('choose_recipe', 'nested_recipe') THEN 'choose_recipe'
  WHEN im.status = 'overridden' AND im.grams IS NULL THEN 'no_grams'
  WHEN im.status = 'confirmed' AND im.fdc_id IS NOT NULL
    AND im.grams IS NULL THEN 'no_grams'
  WHEN im.status IN ('confirmed', 'overridden') THEN 'counted'
  WHEN im.description = 'FoodData Central could not serve this food' THEN 'blocked'
  WHEN im.fdc_id IS NULL AND im.gram_source IS NOT 'recipe' THEN 'no_match'
  WHEN im.gram_source IN ('discarded', 'unmeasured') AND im.grams = 0
    AND COALESCE(im.hold, '') != 'unnamed_food' THEN 'counted'
  WHEN im.confidence < 0.499999999 OR im.hold IS NOT NULL THEN 'check'
  WHEN im.grams IS NULL THEN 'no_grams'
  ELSE 'counted'
END AS bucket FROM ingredient_matches im;
.print '-- rows: main / section'
SELECT (SELECT COUNT(*) FROM ingredient_matches WHERE recipe_id = host_id) || ' / '
  || (SELECT COUNT(*) FROM ingredient_matches WHERE recipe_id <> host_id);
.print '-- buckets: MAIN rows'
SELECT bucket, COUNT(*) FROM b WHERE part = 'main' GROUP BY bucket ORDER BY bucket;
.print '-- buckets: SECTION rows'
SELECT bucket, COUNT(*) FROM b WHERE part = 'section' GROUP BY bucket ORDER BY bucket;
.print '-- holds: MAIN rows'
SELECT hold, COUNT(*) FROM b WHERE part = 'main' AND hold IS NOT NULL GROUP BY hold ORDER BY hold;
.print '-- holds: SECTION rows'
SELECT hold, COUNT(*) FROM b WHERE part = 'section' AND hold IS NOT NULL GROUP BY hold ORDER BY hold;
.print '-- section rule rows (the engine rule notes, confirmed on no food)'
SELECT description, COUNT(*) FROM b WHERE part = 'section' AND status = 'confirmed'
  AND fdc_id IS NULL AND description IN (
    'Sub-recipe — made from its own recipe, not counted in these totals',
    'Seasoning to taste — no measurable amount', 'Equipment — not food, counts as zero',
    'Water/ice — counts as zero', 'Continues the line above — counted with it',
    'Flavouring — no nutrients, counts as zero',
    'Reserved from the main recipe — no amount on the line, counts as zero',
    'Reserved from the main recipe — counted in the main recipe’s spice rub')
  GROUP BY description ORDER BY description;
.print '-- recipe status (main)'
SELECT status, COUNT(*) FROM recipe_nutrition WHERE recipe_id = host_id GROUP BY status ORDER BY status;
.print '-- section status'
SELECT status, COUNT(*) FROM recipe_nutrition WHERE recipe_id <> host_id GROUP BY status ORDER BY status;
.print '-- sections with a blocked line'
SELECT COUNT(DISTINCT recipe_id) FROM b WHERE part = 'section' AND bucket = 'blocked';
.print '-- main partial with nothing flagged on its main rows'
SELECT COUNT(*) FROM recipe_nutrition n WHERE n.recipe_id = n.host_id AND n.status = 'partial'
  AND NOT EXISTS (SELECT 1 FROM b WHERE b.recipe_id = n.recipe_id
    AND b.bucket IN ('no_match', 'no_grams', 'check', 'choose_recipe', 'blocked'));
.print '-- of which wait on a routed section child (a partial section it routes to)'
SELECT COUNT(*) FROM recipe_nutrition n WHERE n.recipe_id = n.host_id AND n.status = 'partial'
  AND NOT EXISTS (SELECT 1 FROM b WHERE b.recipe_id = n.recipe_id
    AND b.bucket IN ('no_match', 'no_grams', 'check', 'choose_recipe', 'blocked'))
  AND EXISTS (SELECT 1 FROM ingredient_matches m JOIN recipe_nutrition c
    ON c.recipe_id = m.child_recipe_id WHERE m.recipe_id = n.recipe_id
    AND m.child_recipe_id LIKE '%#%' AND m.hold IS NULL AND c.status = 'partial');
.print '-- composite rows by kind, gram_source, hold, status (routed_section / section_held: a child section key)'
SELECT CASE
  WHEN parts IS NOT NULL THEN 'two_part'
  WHEN child_recipe_id LIKE '%#%' AND hold IS NULL THEN 'routed_section'
  WHEN child_recipe_id LIKE '%#%' THEN 'section_held'
  WHEN child_recipe_id IS NOT NULL AND hold IS NULL THEN 'routed'
  WHEN child_recipe_id IS NOT NULL THEN 'child_held'
  WHEN gram_source = 'recipe' THEN 'recipe_held'
  END AS kind, gram_source, hold, status, COUNT(*)
FROM ingredient_matches WHERE parts IS NOT NULL OR child_recipe_id IS NOT NULL OR gram_source = 'recipe'
GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
.print '-- child-stamp check: composite rows whose stamp is not the child computed_at (expect 0)'
SELECT COUNT(*) FROM ingredient_matches m WHERE m.child_stamp IS NOT NULL
  AND m.child_stamp IS NOT (SELECT c.computed_at FROM recipe_nutrition c WHERE c.recipe_id = m.child_recipe_id);
.print '-- orphans: section rows with no stamp / section stamps with no rows (expect 0 / 0)'
SELECT (SELECT COUNT(*) FROM ingredient_matches m WHERE m.recipe_id <> m.host_id
    AND NOT EXISTS (SELECT 1 FROM recipe_nutrition n WHERE n.recipe_id = m.recipe_id))
  || ' / ' || (SELECT COUNT(*) FROM recipe_nutrition n WHERE n.recipe_id <> n.host_id
    AND NOT EXISTS (SELECT 1 FROM ingredient_matches m WHERE m.recipe_id = n.recipe_id));
.print '-- reach: section rows / main rows routed to a section'
SELECT (SELECT COUNT(*) FROM ingredient_matches WHERE recipe_id <> host_id) || ' / '
  || (SELECT COUNT(*) FROM ingredient_matches WHERE recipe_id = host_id
    AND child_recipe_id LIKE '%#%' AND hold IS NULL);
.print '-- reach partition: recipe rows a FOOD apply, shipped predicate would take / with the v41 clause (expect 0)'
SELECT COUNT(*) FROM ingredient_matches WHERE gram_source = 'recipe' AND status IN ('auto', 'unmatched')
  AND COALESCE(hold, '') NOT IN ('second_food', 'discarded_medium', 'starter_discard', 'coating',
    'partial_pour_away', 'ambiguous_medium');
SELECT COUNT(*) FROM ingredient_matches WHERE gram_source = 'recipe' AND status IN ('auto', 'unmatched')
  AND COALESCE(hold, '') NOT IN ('second_food', 'discarded_medium', 'starter_discard', 'coating',
    'partial_pour_away', 'ambiguous_medium')
  AND COALESCE(gram_source, '') != 'recipe';
