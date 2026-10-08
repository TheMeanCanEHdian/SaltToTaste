# Corpus extraction findings for the recipe-extraction agent (2026-10-08)

Source: the SaltToTaste nutrition work on the ATK corpus (`The Complete America_s Test Kitchen TV Show Cookbook 2001–2023`,
1,198 recipe YAML files) — the two blind accuracy audits of 2026-10-07/08 and the design pass that followed. Everything below
was measured on the corpus checkout as of 2026-10-08 (the June extraction) and, where stated, checked against the EPUB's own
text. The two TSVs beside this file list every affected recipe and section.

## Why the nutrition analyzer cares

The analyzer reads a recipe's **steps** to decide what is eaten: whether a solid is strained out and discarded, whether frying
oil is poured off or reused, whether a coat is fried or baked, how long an alcohol simmers, whether a sub-recipe is served on
the side. A section that has ingredient lines but no steps is read on its ingredient data alone, so every one of those rules is
blind there. The analyzer keys a person's decisions and its own staleness on the **ingredient lines** (their raw text and
position), so a re-extraction must leave those byte-identical and add the missing text beside them.

## Finding 1 — 269 titled subsections have ingredient lines but no direction paragraph

- Count: 269 of the 403 subsections that carry their own ingredient lines (in 160 host recipes). Every one of them is stored
  as `kind: variation`, with `steps: []` and `body: ''` (not one of the 269 has any body text). List: `stepless_subsections.tsv`.
- The book prints the paragraph. Example, the pupusas' Curtido (`1101-pupusas-with-quick-salsa-and-curtido.yaml`, subsection
  "Curtido", 10 ingredient lines stored, `steps: []`, `body: ''`). The EPUB (`OEBPS/xhtml/Kitc_9781954210110_epub3_bm2a_r1.xhtml`)
  prints, after the ten lines: "Whisk vinegar, water, sugar, and salt in large bowl until sugar is dissolved. Add cabbage,
  onion, carrot, jalapeño, and oregano and toss to combine. Cover and refrigerate for at least 1 hour or up to 24 hours. Toss
  slaw, then drain. Return slaw to bowl and stir in cilantro."
- Shape of the stored section: keys `title, kind, body, servings, prep_notes, ingredients, steps, kind_needs_review`; the
  ingredients are `[{group, items}]` groups exactly like a top-level recipe's.
- Observation, not a diagnosis: the 269 are all `kind: variation`. A prose-only variation (no ingredient list) legitimately has a
  body and no steps; these have an ingredient list and lose the paragraph that follows it. Whatever path handles "a titled
  section that has its own ingredient list" seems to drop the text after the list. Many of these are full sub-recipes (a glaze,
  a slaw, a topping) rather than variations, which `kind_needs_review` may already flag.

## Finding 2 — 26 whole recipes have ingredient lines but `steps: []`

List: `stepless_recipes.tsv`. Examples: `0035-vegetable-broth-base.yaml` (8 lines), `0471-classic-guacamole.yaml` (7 lines —
the book prints the recipe with "MAKES 2 CUPS", its note, its lines and its directions), `0733-oven-fried-bacon.yaml` (1 line),
`0329-quick-tomato-sauce.yaml` (10 lines). Several are short "simple" recipes (couscous, farro, blanched green beans, broiled
asparagus) that carry their own subsections; the host's directions are missing while the subsections are stored.

## Finding 3 — an ingredient line split at a measurement continuation (2 known)

The extraction produced a second "ingredient" from the tail of a line, with no amount:
- `0054-green-bean-salad-with-cherry-tomatoes-and-feta.yaml`: the green beans line is stored as item `green beans` with prep
  `trimmed and cut into`, followed by a separate line `raw: "1- to 2-inch lengths"` (`amounts: []`, `item: 1- to 2-inch lengths`).
- `0061-italian-pasta-salad.yaml`: the mozzarella line is stored as item `fresh mozzarella cheese` with prep `cut into`, followed
  by `raw: "⅜-inch dice and patted dry with paper towels"`.
The analyzer then searches USDA for "1- to 2-inch lengths" and "⅜-inch dice and patted dry…" as foods. A continuation that
begins with a measurement fragment (`N- to M-inch …`, `⅜-inch dice …`) after a prep ending in "cut into" is the tail of the
previous line. A corpus-wide scan for amount-less lines whose text starts with a fraction or "N- to" would find any others.

## Finding 4 — a group heading applied past its scope (1 known)

`0070-skillet-chicken-fajitas.yaml` stores two ingredient groups: `CHICKEN` (10 lines) and `RAJAS CON CREMA` (14 lines). The
second group holds, after the rajas' own lines, the tortillas, the garnishes and the reference line "Spicy Pickled Radishes
(recipe follows)", which belong to the assembly rather than to the rajas:
    1. 1 pound (3 to 4) poblano chiles, stemmed, halved, and seeded
    2. 1 tablespoon vegetable oil
    3. 1 onion, halved and sliced ¼ inch thick
    4. 2 garlic cloves, minced
    5. ¼ teaspoon dried thyme
    6. ¼ teaspoon dried oregano
    7. ½ cup heavy cream
    8. 1 tablespoon lime juice
    9. ½ teaspoon salt
   10. ¼ teaspoon pepper
   11. 8–12 (6-inch) flour tortillas, warmed
   12. ¼ cup minced fresh cilantro
   13. Spicy Pickled Radishes (recipe follows)
   14. Lime wedges
The analyzer reads group headings (a CONDIMENTS heading marks a served-with line), so a heading that swallows the lines after
its section matters. The book's layout here (a sub-heading inside the ingredient list, then unheaded lines) is worth a look in the
grouping logic.

## Finding 5 — to verify against the book, not asserted as extraction errors

- `pane-francese` prints a bread-flour range "2⅔–3 cups (14⅔ to 6½ ounces)" — reversed bounds; the analyzer treats it as a typo for
  16½ and keeps the larger. Whether the book prints 6½ or the extraction dropped a digit is unverified.
- Weight ranges with a spaced mixed number, "(3 ½- to 4-pound)", occur once (pressure-cooker pot roast); the analyzer folds the
  space. If the book prints "3½", the space is an extraction artefact.

## What a re-extraction should preserve, for the analyzer's sake

1. Every existing ingredient line's `raw` text and its order (a dry-run diff of the ingredient lines before re-import; only
   `steps` and `body` should change, plus the two merged lines of Finding 3).
2. The subsection titles (the analyzer's section keys are `<host id>#<exact title>`; a retitled section loses its stored rows and
   any decision a person made on it).
3. The `kind` field, corrected where a titled section with an ingredient list is a sub-recipe rather than a variation.

After a re-import the analyzer re-reads every host whose text changed; its person decisions survive an ingredient-line-identical
re-import, which is why point 1 matters most.
