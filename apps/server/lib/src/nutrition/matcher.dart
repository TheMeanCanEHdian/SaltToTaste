/// Ingredient → FDC food matching: query normalization and candidate
/// ranking with a 0–1 confidence score.
library;

import 'package:meta/meta.dart';
import 'package:salt_server/src/nutrition/provider.dart';

/// Words that describe handling/quality, not identity — dropped from the
/// search query so "unbleached all-purpose flour" still hits "Flour, wheat,
/// all-purpose". Deliberately small: over-stripping hurts more than it
/// helps ("unsalted", "brown", "dark" are identity and stay).
const Set<String> _stopWords = {
  'fresh',
  'freshly',
  'optional',
  'preferably',
  'plus',
  'extra',
  'good-quality',
  'high-quality',
  'quality',
  'store-bought',
  'storebought',
  'homemade',
  'best',
  'favorite',
  'your',
  'assorted',
  'unbleached',
  'organic',
  // "1 dozen mussels" is mussels (Paella, 0105); the grams read the dozen.
  'dozen',
};

/// Preparation words — how the cook cuts/handles the food, never what it IS.
/// Dropped from the query so "minced fresh oregano" searches "oregano"
/// (otherwise "minced" hits "Ham, minced") and correct matches stop being
/// confidence-deflated by noise tokens. Deliberately CONSERVATIVE: anything
/// that could change the food's identity (raw/cooked/roasted/dried/ground)
/// stays out of this list. "leaves"/"cut" also stay out — dropping them turns
/// "bay leaves" into "bay".
const Set<String> _prepWords = {
  'minced',
  'chopped',
  'sliced',
  'diced',
  'grated',
  'shredded',
  'crushed',
  'crumbled',
  'halved',
  'quartered',
  'cored',
  'peeled',
  'seeded',
  'pitted',
  'trimmed',
  'sifted',
  'packed',
  'softened',
  'melted',
  'beaten',
  'cubed',
  'mashed',
  'thawed',
  'drained',
  'rinsed',
  'divided',
  'julienned',
  'shaved',
  'coarse',
  'coarsely',
  'fine',
  'finely',
  'thin',
  'thinly',
  'roughly',
  // "torn fresh basil" keyed 'torn basil' (checkpoint 5).
  'torn',
  // Size / vessel words: describe the piece bought, not the food. "small head
  // escarole" must search "escarole", not drag in "Beans, Dry, Small Red".
  // ("whole" stays — it's an FDC form, e.g. "whole milk", "whole wheat".)
  'small',
  'medium',
  'large',
  'head',
};

/// Items that are nutritionally (effectively) zero — matched locally so
/// they never cost an FDC request and never dilute the match ratio.
const Set<String> waterLikeItems = {
  'water',
  'boiling water',
  'cold water',
  'warm water',
  'hot water',
  'ice water',
  'iced water',
  'tap water',
  'ice',
  'ice cubes',
  // v21: "3½ cups filtered water" (cold-brew coffee concentrate) counted
  // 385 g of "Water, tap" in check.
  'filtered water',
};

/// Kitchen-name → FDC-vocabulary synonyms applied word-by-word.
const Map<String, String> _synonyms = {
  'confectioners': 'powdered',
  "confectioners'": 'powdered',
  // FDC's house style for salt state.
  'unsalted': 'without salt',
  'salted': 'with salt',
  'scallions': 'green onions',
  'scallion': 'green onion',
  // FDC files bittersweet/semisweet bars under "Chocolate, dark, <n>%".
  'bittersweet': 'dark',
  'semisweet': 'dark',
};

/// Bumped whenever [normalizeItem], [itemKeyFor], the rewrite table or the
/// ranker changes what a line searches, how it is keyed, or how candidates
/// score. Folded into the nutrition staleness hash, so every computed recipe
/// becomes `stale` and the stale sweep re-resolves its engine rows (human
/// decisions are kept) — otherwise stored scores and picks stay frozen at the
/// matcher that wrote them, which the 2026-09-04 survey measured on every
/// computed recipe. Decision rows are re-keyed at boot from their item text
/// when this changes (services/decision_rekey.dart).
///
/// History: 1 = everything before 2026-09-07; 2 = diacritics folded, canned
/// crushed/diced tomatoes keep their form word, singular decision keys;
/// 3 = the ranker requires the ingredient's head noun, docks composite and
/// branded records harder, 'juice from 1 lemon' normalizes to 'lemon juice',
/// and the rewrite table gained the spice/bacon/shrimp/sherry/beer/mustard/
/// pasta entries (design review D4, measured on the 2026-09-08 diagnostic
/// set: 19 of 31 confidently wrong foods fixed, 0 correct lines regressed);
/// 4 = a second amount left in the item ("plus 2 tablespoons …", "or ¼
/// teaspoon dried") is dropped from the query and the key, equipment lines
/// are zeros, and the engine searches a cached "A or B" alternative alone and
/// reads a same-key sibling's cached answer (sweep audit, 2026-09-26);
/// 5 = "A or <amount> B" keeps B (only the amount goes), a leading amount
/// before "juice from N lemons" no longer eats the juice, an empty cached
/// answer for A no longer splits "A or B", and a rewritten line never reads
/// its key-form sibling (sweep-batch review, 2026-09-26);
/// 6 = the accuracy batch (sweep audits 1 and 2, 2026-09-26): whole-bird,
/// dish, product and kind-word rewrites, a species/variety/cut dock, count
/// nouns out of the ranker's coverage, the head noun read before "with"/
/// "on", "N percent" as "N%", an "A or B" split only on an answer naming A
/// (a stand-in A takes B), a negated word ("not sweetened") covers nothing,
/// and a lower record replaces the top pick for its macros only as the same
/// food in another form; audit 3 (ACCURACY-2) added a can on a legume line,
/// a cook-state and a meat-only dock, compound-head and kind-word rewrites,
/// and keys a line naming a second food apart — all within version 6;
/// 7 = audit 4 and the v6 review (2026-09-27): chicken pieces, instant
/// yeast, Cornish hens, cherry tomatoes and curing salt rewritten, the
/// unsweetened-coconut target names "not sweetened", imported as a variety
/// word, 'cooked' as a cook state, instant as a modified form, "loosely
/// packed" drops the adverb, an oven bag is equipment, the
/// count-noun cap never leaves only a dish word, a cured meat for a fresh
/// line is held as dried-for-fresh, a lone qualifier reads on until a
/// segment names a food, and a second food's key comes from each part with
/// its amounts cut;
/// 8 = checkpoint 5 (2026-09-27): coverage-only credits (chile→pepper,
/// zest→peel, spice qualifiers, descriptor words) with
/// literal precision, 'or'/'and' out of the ranker (switch), 'imported'
/// docked only beside a domestic record of its cut, 'white' docked only on
/// an egg, pods as count nouns, a dropped
/// word's leaked connector/measure cut from the key, prep-only comma
/// segments dropped, egg and citrus second-food keys tidied, and rewrites
/// for desiccated coconut, pancetta, panko, stout, madeira, tubetti, mezze
/// rigatoni, sukang maasim and cherry tomatoes;
/// 9 = checkpoint 5 review (2026-09-27): a credited word leaves the
/// denominator only of a record carrying the head (a variety word only of
/// one naming no variety), the chile credit only on a hot pepper record, a
/// count noun that is an alternative's food kept, identity participles kept
/// in a comma-listed food, "3 or 4 limes" moved to the front, a fruitless
/// zest-plus-juice item keyed by the line's fruit, and egg-part keys food
/// first;
/// 10 = checkpoint 6 (2026-09-27): a bare 'zest'/'peel' item searches and
/// keys the line's fruit ("1 (2-inch) strip zest from 1 lemon" is 'lemon
/// zest'), 'skinless' credited (not on a line that names no species) with
/// "Lomi salmon" and a salad named for the food ("Salmon salad") docked as
/// dishes, and rewrites for country-style ribs (to the raw record),
/// gorgonzola, arborio, 90% lean ground sirloin, andouille, kielbasa
/// sausage, the flagged asiago and allspice-berry approximations, and lime
/// zest (a bare 'peel' item is left alone: no line of the library is one —
/// this entry said it took the fruit too, corrected in v11);
/// 11 = checkpoint 6 review (2026-09-28): a lean-only/lean-and-fat tie
/// goes to the lean-and-fat record and a cooked/uncooked one to the record
/// naming fewer cookings (other exact ties still follow FDC's order); lime zest
/// searches as lemon zest, "Lemon peel, raw" (a flagged approximation); the
/// water and dissolve rules read the recipe's own steps only, a dissolve
/// needs the salt as its object and a submerge, a bare "salt" in cooking
/// water is the one salt line no step names with its amount, a held
/// medium's eaten "plus" part is its grams; an amount-less line in the
/// shell is held (shell-on shrimp the line peels stays held: weighed with
/// its shells); the
/// staleness hash reads the steps and the title;
/// 12 = checkpoint 7 (2026-09-28): the ranker strips "-es" only after s,
/// ch, sh or o ('whites' is 'white', not 'whit'), with the class word
/// "Spices," covering nothing, "puree" a base-form change, an "Alaska
/// Native" record docked and V8 covered by "vegetable"; "1 dozen" read as 12
/// and keyed without 'dozen'; a dangling "and" cut from a split line; the
/// segments before the food in "medium, firm, ripe tomatoes" read past,
/// 'firm' dropped; rewrites for the shrimp size words, skin-on salmon,
/// pepperoncini, juice oranges, ripe avocado and bananas, chen pi (a flagged
/// approximation) and the halibut lines (pending one live search);
/// 13 = the checkpoint-7 review and the user's rulings of 2026-09-28: the
/// oyster-mushroom dock written ([_varietyHosts]), "-es" off after x too (a
/// z loses its "s" alone — this entry said "and z", corrected in v14), a
/// dangling "or" cut like "and", a coated record a composite, fresh
/// oregano, sage, tarragon, marjoram and chervil counted on their dried
/// spice (a flagged approximation), and rewrites for center-cut skin-on
/// salmon and white chocolate chips; with it the engine's sub-recipe lines
/// (0 g, no food), the R2 held and R3 zeroed media and the below-gate sized
/// twin re-resolve every computed recipe;
/// 14 = the Run 045 review, checkpoint 8 and the user's rulings Q1–Q4 of
/// 2026-09-28: a second "or" makes a list of foods ("crushed saltines … or
/// quick oatmeal or … bread crumbs" is the saltines); with it the engine
/// rewrites its own rule rows, gates every write path by the sub-recipe
/// rule (a "1 recipe" line is one whatever its mark; a single-food "1
/// recipe X" counts its yield; a sub-recipe's eaten "plus" part counts), a
/// cheesecloth-bundled brine aromatic is zero, a skimmer leaves no liquid
/// the pot simmered dry or keeps, and a held medium stores only its eaten
/// part as grams; a fresh herb on its dried record counts a third of its
/// volume (its written dried amount; a leaf count 0 g); SR bare-noun
/// portions, an in-item weight and a bottle's printed volume are read; soda
/// rinsed off, a later drain, a court-bouillon, a dip, a drained pickle, a
/// poaching brine's salt and a dunk's sugar are held; and 26 rewrites of
/// checkpoint 8's cached-answer keys (thick-cut bacon … white baking chips);
/// 15 = the Run 047 review: a repeated line takes the nth row of its text
/// (an engine row never takes another copy's decision), one weighed line
/// (a sub-recipe's eaten "plus" part) and one sub-recipe gate on every
/// write path — a confirm, a pick, an un-skip and an apply-to-all too — an
/// edited held medium keeps its hold, and an un-skip gives a held medium
/// back the engine's grams; flake and coarse sea salt weigh like kosher
/// salt, a sub-gram "pepper" portion weighs only a small dried chile, a
/// bare count's printed paren volume wins, an animal or adjective before a
/// list of foods is never split, and the detector and portion alternatives
/// no library line reached are gone; 16 = the Run 048 review: the pairing
/// laid out before any write (lines aligned with rows by text, one
/// transaction, no demotion), a held medium keeps a person's resolution
/// through an edit, a confirm and an un-skip, a pick and an apply-to-all
/// weigh the weighed line, only flake and coarse sea salt weigh like kosher
/// salt (plain and fine sea salt as table salt again), a volume paren
/// saying "each" is per item, and the guards other libraries' lines need
/// are back (a portion must lead with its unit, "do not drain" drains
/// nothing, an in-item ounce weight, a litre paren); 17 = checkpoint 8's
/// approved requests: rewrites of names FDC spells another way (baguette,
/// broccoli rabe, quick tapioca, St. Louis spareribs, pomegranate seeds,
/// milk chocolate, swordfish and tuna steaks, nonfat dry milk, pumpkin
/// purée, Nutella, water chestnuts, buttermilk powder) and of keys whose
/// record leads a cached answer, an unasked 'liquid' FORM segment docked as
/// a modified form, eight SR volume siblings, and a named whole item's
/// portion past the 250 g bare-count cap (grams.dart); 18 = checkpoint 9's
/// density guard (a density key matches as a word, 'ice cream' 0.558, dairy
/// powders, water chestnuts, ricotta, cream cheese and oil-packed tomatoes
/// on their record's own portion) and Run 049: flake and coarse sea salt
/// only as the line's own food (and its plus part, and more spellings), a
/// per-item volume paren the parse kept; 19 = Run 050's grams: a density
/// key that only modifies a compound ('cream of tartar', 'mustard seeds',
/// almond and apple butter) and a named nut ('nuts') on their record's
/// own portion, no drink's portion for its powder, a shredded or grated
/// portion for a shred, 'small' read from the item's own words, and
/// quantity words before a flake salt; 20 = Run 051's grams: a density key
/// that only modifies the item's head weighs on a record of the key's own
/// food by that record's volume portion (vanilla extract, cayenne pepper,
/// cocoa powder), sugar snap peas are no sugar, and a dried chile is small
/// by its item's own words; 21 = the v21 plan's zero-request rules: 82
/// rewrites onto cached answers, 51 rank-as items ([_rankAs]), filtered
/// water, banana leaf, and the grams rules (scoped jelly densities, flagged
/// stand-in densities, piece aliases, pint and quart parens, the bare
/// 'fruit'/own-noun whole-item portion up to 350 g); 22 = the checkpoint 9
/// rulings: a starter's feeding flour, a fried food's dredge and a braise
/// kept only in part held (`starter_discard`, `coating`,
/// `partial_pour_away`), a rinsed dry cure 0 g discarded; 23 = Run 053's
/// rules and grams: grated Parmesan and Pecorino at the corpus's printed
/// 0.24 g/mL, a dredge held when the DIRECTIONS fry it (not by the oil's
/// mass), a divided dredge's or braise's part used outside it eaten, a pick
/// keeping an eaten-in-part hold, `_asPrepared` only on a popcorn line, the
/// oil a held dredge fries in discarded by the same directions (not its
/// mass; a smaller first part a step names stays eaten), shredded Parmesan
/// at the corpus's printed 0.36 g/mL, and a "plus" part's printed weight
/// used over the density. 24 (Run 054): the step and line regexes linear on
/// hostile text (a sentence over 1,000 characters read as none — since
/// 25 its first 1,000 are read), a
/// decided row's hold re-derived on every compute, and the oil, dredge,
/// _asPrepared and plus-part cheese rules of that run (v24's "a sentence
/// over 1,000 characters read as none" is superseded by 25's window). 25
/// (Run 055): RULE A — a decided row's every derived field (hold, grams
/// unless typed, their source) re-derived from the recipe on every
/// compute, PUT and GET; RULE B — a sentence belongs to the line that owns
/// it (a frying sentence binds by the oil's own amount or kind word with
/// its noun phrase following directly, oven heat is never frying heat, two
/// candidates held `ambiguous_medium`); RULE C — a detector costs O(text)
/// per recipe (a per-recipe step index, the first 1,000 characters of an
/// over-long sentence read, the matches GET memoised per key and raw); and
/// the grams change: `_asPrepared` on the measured head, a plus part's own
/// grated/shredded form. 26 (Run 056): RULE A — the derived write at the
/// row's current position, ONE "derivation unavailable" outcome on every
/// path, the totals' food fetch included (decision stored, derived fields
/// as last derived, the recipe stale, never a throw for one row), and an
/// amount-less decided line deriving no weight (a confirmed held one 0 g
/// `discarded`); RULE B for every frying fat (oil, shortening, lard, each
/// by its own noun), a binding key two lines share binding neither, lines
/// counted by position, every line the mass rule could zero a candidate
/// (a written weight of 400 g or more too; an amount-less "for
/// (pan-)frying" line), and frying heat as positive evidence from the
/// whole sentence in every temperature spelling; RULE C at the loop
/// level — what a rule derives per recipe or per food (mention owners,
/// amount writers, the sentences naming a food, the frying-oil owners)
/// derived once and shared, a line costing its own mentions, the
/// over-long-sentence notice logged once per recipe and content; the
/// grams change: a plus part's form read after its comma, and only a
/// one-word paren (or comma part) a modifier of the measured head (the v25
/// replay byte-identical). 27 (Run 057): RULE A as a ROW fact — each
/// decided row's `derived_seq` (migration 014) names the layout and inputs
/// its derived fields were computed for, and freshness is the stamp AND no
/// decided row underived (one SQL predicate every reader reads); a food FDC
/// no longer serves is the `food_gone` hold, derived; an outage leaves the
/// row underived (one request per row per pass, the job stopping with the
/// provider's reason); the totals cache-only; an apply-to-all target FDC
/// cannot weigh counted `unavailable`. RULE B — an appliance or method
/// word excludes only the temperature its own clause governs (never a
/// vessel — "baking sheet", "roasting pan" —, "roasted peppers", an oven
/// past a ";" or past a heat verb), the leads and heat verbs open (at, is,
/// reads, a temperature of, between … and, a range; maintain, keep, hold,
/// fry …) and every degree spelling (º, ˚, deg, Fahrenheit); the mass rule
/// read with no food (a written volume at its density, a written or
/// printed weight: the 48-ounce bottle zeroed on every path, the GET's
/// `held` and the compute one answer) and the candidacy on the same
/// reading (a printed-weight bottle, a "for (pan-)frying" line with any
/// amount); every medium
/// threshold in both unit families (a weight-written oil, dredge, brine salt
/// or soak at its density). RULE C — the naming index built on the second
/// head asked, inverted name and amount indexes for the dissolve and plus
/// readers. The grams change: a paren or comma part qualifies the popcorn
/// head when every word is a qualifier ("(unpopped kernels)" 96.5 g).
/// 28 (Run 058): RULE B — a scope boundary is a clause MARK, never the
/// evidence's own word: a frying temperature's clause runs from the last
/// "; , — ( )" (a mark directly before a heat verb's participle opens
/// none: "in the smoker, holding it at 300"), so an appliance governs the
/// temperature its own verb heats ("an oven heated to 375", "until the
/// oven thermometer registers 375"); the governing words located once per
/// sentence, each temperature answered by a forward pointer (linear per
/// clause, `heatClauseChars`); a vessel never excludes (Dutch/French oven,
/// oven-safe/-proof, broiler/grill pan, broiler-/grill-safe); the fry range
/// kept at 300–399 °F, judged on the library's 400-degree sentences; the
/// medium thresholds read food-free densities for bread crumbs, a starch,
/// shortening and lard (0.87, FDC 173584/171401) — never a line's grams —
/// a same-food plus part in both unit families, and four cups exactly.
/// RULE A — "derived for" names every input a derivation reads: a
/// `food_gone` row re-read from the caches on every compute (no request;
/// derived again once a cache holds the food); the nutrient sibling
/// resolved where its food is (a 404'd sibling is the row's `food_gone`,
/// an engine candidate passed over; the separate prefetch deleted); a plain
/// recompute resolves a food no cache holds before it reads the totals;
/// two failure classes (`FailureScope`: GLOBAL stops the job, FOOD is the
/// row's — underived, counted, held `food_unavailable` at the third
/// compute); a pass that throws leaves no row marked derived; one action
/// table per hold (salt_shared `holdActions`) read by the PUT's gate and
/// the queue's SQL; migration 016 (`retry_count`, the search-cache food
/// index). Replay: no row moves (RULE A changes no landing).
/// RULE C — the naming inversion built by MEASURED amortisation (each food
/// scanned for alone — a pass per step for where its word starts, the
/// sentences of only the steps that have it — until the scans paid on the
/// recipe's index reach the inversion's measured cost: the reach and the
/// apply-to-all build none, the compute and matches GET of a cap recipe
/// build it once), the inversion linear per sentence (each word confirmed
/// at the word), the matches GET resolving each row's food once, one FDC
/// request per food per pass
/// (`onePass`: asked ids, 404s and failures remembered). Pairing: a run of
/// identical lines laid out in its own order (never branched on; exact
/// for the script's cost and the decisions kept). The app reads the same
/// action table (`holdActions`) for its buttons and copy, and the stale
/// banner names its cause (`stale_reason`). The closer: a detail outage
/// (FOOD failures on 3 distinct foods in a row within a pass) escalates to
/// GLOBAL, counting and holding none; the PUT's gate reads the stored hold
/// before a carried row's derivation; which holds a pick keeps is the
/// action table's. Replay: no row moves (RULE C and the pairing change no
/// landing).
/// 29 (Run 059): RULE B — a frying temperature's clause starts at the
/// LATEST boundary at or before its lead: a clause mark, an "and"/"then"
/// opening a new verb phrase, or the fat's own mention; a mark or opener
/// whose phrase opens on a non-fry heat verb (its object unnamed: "in the
/// smoker, holding it at 300", "on the pizza stone and heat it at 350") is
/// none — the v28 participle exception deleted, so "…oven, heating the oil
/// to 350" and "Place a rack in the oven and heat the oil to 350" are the
/// oil's heat again; a lead's own "(" opens the clause, a boundary inside
/// a lead none. The hyphenated vessels (grill-pan, broiler-pan,
/// roasting-pan, baking-sheet/-dish) never exclude. The heat reading's
/// whole-sentence passes built once per sentence per index, shared by
/// every fat and caller, each read only as far as a check needs and the
/// governing words from the clause's start (`memo:heatReading`,
/// `heatClauseChars` counting every pass and pointer step). FDC's failure
/// table: an unreadable 200 on a detail is the food's (FOOD), a search 404
/// GLOBAL (no private exception escapes the provider), the network GLOBAL
/// even on a detail. Replay: no library row moves (the boundary changes
/// only typed sentences; the 78 corpus fat-and-temperature sentences and
/// all 13,615 oil/dredge readings identical to v28).
/// RULE A (the same release): a hold is RE-READ before it is enforced —
/// a cache-only derivation through `knownFood` at every compute, at the
/// PUT's gate and at the GET (a cache write that gains the food re-opens
/// the held rows); an ENGINE line's FOOD failure is its row's state
/// (counted, held `food_unavailable` at the third), never the pass's; the
/// outage escalation is counted across the JOB, spans two recipes and
/// never discards a row's count; a pass is in progress until its totals
/// are written (migration 017's owned count); the PUT judges every verb
/// and resolves only its own line's foods; the held write keeps its count
/// and the `all` scope asks a held food once; the hold families live in
/// the action table. Replay: no row moves (RULE A changes no landing).
/// RULE C (the same release): a cost unit IS the cost — a food named in
/// the steps is looked up over ONE word index per step (each word's start
/// and hash, built once), a lookup paying exactly the words it visits and
/// its confirms' characters (`namingPaid`), the inversion the word index
/// inverted, built at 12 × the words (Run 059 O9: v28's regex step pass
/// cost 0.1–9 ns a character as the words spelled). Pairing: a run of
/// twins is ONE ordered multiset — the search never chooses a twin, a run
/// keeps its decisions first, its surplus dropped where the fewest rows
/// move (ties from the end), laid in position order (400 twins, one edit:
/// 10,000 layouts → ~800). Replay: no row moves.
/// 30 = the rulings already made, built as table entries only: Q7's bone-in
/// parts (18 rank-as items onto their raw records at the printed gross
/// weight, labelled approximate; flap meat, turkey drumsticks/thighs and
/// leg quarters flagged approximations; "rib slabs" buys bone) and Q6's
/// corpus-printed pods (dried New Mexican and guajillo chiles 7.1 g each,
/// flagged). Replay: 24 rows move (20 bone-in, 4 chile), 17 recipes
/// complete. The fresh ham, the live step's details and searches wait,
/// commented where they will go.
/// 31 = the CP10 rulings (2026-10-03), table entries plus the narrowest rule
/// each named recipe needed. Q6: fresh ginger and citrus zest strips by
/// their printed length (8 and 0.8 g an inch), the dried chipotle (4.6 g),
/// whole spices, lemongrass, lasagna sheets (Barilla 17 g, Ronzoni 25 g)
/// and a scallion bunch (7 × 15 g), each flagged with its source; star
/// anise on anise seed, flagged. Q7: the eight small groups, anchovy paste
/// (6.7 g a teaspoon), the misc mappings (Cubanelle 99 g, cornichon 3.2 g,
/// instant espresso at its siblings' 0.43), Spanish chorizo on 2706179 and
/// linguiça on the smoked pork link; a confit's duck fat is a frying medium;
/// a held breading's bread is held with its flour. The held-media rulings:
/// a poach whose liquid is poured away but a measured part is held
/// `partial_pour_away` (0488), a plus part eaten after the fat's last
/// discard counts (0042), and a fat fried by the verb alone is held
/// `ambiguous_medium` (0288, 0674, 0675). Replay: 191 rows move (A 49,
/// B 133, C 9), complete 847 → 939. The light sour cream, the brioche and
/// the dry-cured chorizo wait for the live step, commented.
/// 32 = the live step's rules, enabled (12 details and 2 searches recorded
/// 2026-10-03). Each dry entry enabled once its detail was read and its
/// check held: chicken leg quarters (172378, no refuse yield: gross,
/// approximate), oil-packed tuna (175157), sweetened cranberry juice
/// (171903), dried onions (170002), the fresh half ham (168226, no refuse
/// yield: gross, approximate), cooked wheat berries (169744, flagged),
/// jarred pimentos (168559), low-fat sour cream (173443), brioche buns
/// (2707682, sized by a 77 g piece figure from its "1 piece" portion, which
/// the finder alone reads as a dish serving), and the tamarind and egg
/// volume siblings (167763 "cup, pulp" 120 g; 171287 cup 243 g). One stays
/// dry, its check failed: the portobello cap (2003598 publishes a racc
/// portion only). Spanish-style chorizo moves
/// to a flagged "Salami, Italian, pork" (174603): FDC has no dry-cured
/// chorizo (the owner's decision).
/// 33 = the dredge-reach ruling (2026-10-03): a reachable dredge (flour,
/// starch, crumbs, panko, ¼ cup or more, named in a dredge sentence) is
/// held `coating` in ANY cooking class whose directions leave an excess of
/// the coat — a sentence that shakes, removes or pats off the excess, never
/// a liquid's, never in a dough step — and still whenever the recipe fries
/// (the CP9 ruling, sufficient). A coat wholly eaten (a toss, a binder, a
/// crust pressed on with no excess sentence) stays counted. The bread a
/// held breading puts through the processor (a step, or the line itself)
/// is held with its flour when a sentence coats the food with the crumbs,
/// and so is a crumb or panko line (¼ cup or more) of a recipe that holds a
/// dredge when a sentence coats the food with crumbs (0416, 0117: the steps
/// name the panko as "the bread crumbs", "the panko mixture").
/// 34 = the coat's other layers (the owner, 2026-10-03, "the narrow
/// version"): a nut, cheese, cracker, chip, cornflake or Melba toast line
/// (a quarter cup or more, or a count; the first line of its head) named in
/// a sentence that sets the coat out in its dish or names it with the
/// coat's crumbs is held `coating` with the dredge of a recipe that holds
/// one (L1: 0042, 0117, 0315 ×2, 0407, 0416, 0419), or of a recipe whose
/// directions leave an excess of the coat with no dredge line to hold (L2:
/// 0150's Melba toast). A row with no food gets no hold (0198's cornflakes
/// stay no match). The four fried dredges with no excess sentence stay held
/// by the frying ruling (no change).
const int matcherVersion = 34;

/// Letters FDC and the corpus both write plainly: 'jalapeño' searched as
/// 'jalape o' (the split treated ñ as punctuation) on 65 corpus lines.
const Map<String, String> _folded = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// [text] with each "(…)" replaced by a space, as `\(.*?\)` replaces them
/// (a paren never spans a line break) — in one pass: the lazy run re-read
/// the rest of the text from every unclosed "(" (Run 055 S6: 5 ms for
/// 1,000 of them, 23 ms for 2,000, per call).
String _withoutParens(String text) {
  final out = StringBuffer();
  var from = 0;
  var open = text.indexOf('(');
  // The next line break at or after [open], looked up again only once
  // passed: each character is read once.
  var broken = -1;
  while (open >= 0) {
    normalizeSteps++;
    final close = text.indexOf(')', open);
    if (close < 0) {
      break;
    }
    if (broken < open) {
      broken = text.indexOf(_lineBreak, open);
      broken = broken < 0 ? text.length : broken;
    }
    if (broken < close) {
      // Every "(" before the break meets it before this ")".
      open = text.indexOf('(', broken);
      continue;
    }
    out
      ..write(text.substring(from, open))
      ..write(' ');
    from = close + 1;
    open = text.indexOf('(', from);
  }
  return (out..write(text.substring(from))).toString();
}

/// The steps [normalizeItem]'s one-pass forms took since reset — each
/// "(" [_withoutParens] closes or skips, each number word
/// [_withoutAmounts] reads — what the tests pin their linearity by beside
/// a clock (Run 056 O20/S20: a 5 ms clock alone).
@visibleForTesting
int normalizeSteps = 0;

/// What `.` never matches: a line break.
final RegExp _lineBreak = RegExp('[\n\r  ]');

/// A character [_folded] folds, compiled once.
final RegExp _foldedChar = RegExp('[${_folded.keys.join()}]');

/// Prep words that name the PRODUCT when they precede these foods: a can of
/// crushed or diced tomatoes is a different food from a fresh one (FDC files
/// them apart), and stripping the word folded 51 canned lines into the
/// 9 fresh ones under one key.
const Set<String> _formPhrases = {'crushed tomatoes', 'diced tomatoes'};

/// The FDC search query for an ingredient item: lowercased, accents folded,
/// parentheticals and stop-words removed, synonyms applied, whitespace
/// collapsed. Empty when nothing searchable remains.
String normalizeItem(String item) {
  var text = item.toLowerCase();
  text = text.replaceAllMapped(_foldedChar, (m) => _folded[m[0]]!);
  text = _withoutParens(text);
  // The grade of a curing salt is not an amount: "pink curing salt #1"
  // searched and keyed 'pink curing salt 1' (audit 3, A11).
  text = text.replaceAll(RegExp(r'(?<=curing salt)\s*#\s*\d+'), ' ');
  final raw = text.split(RegExp('[^a-z0-9%-]+'));
  final words = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final word = raw[i];
    if (word.isEmpty || _stopWords.contains(word)) {
      continue;
    }
    final formWord =
        i + 1 < raw.length && _formPhrases.contains('$word ${raw[i + 1]}');
    if (_prepWords.contains(word) && !formWord) {
      continue;
    }
    // How a leaf is packed is not the food: "½ cup loosely packed fresh
    // cilantro leaves" kept 'loosely', half the query once the count noun
    // left it (audit 4: 10 herb lines fell into check).
    if (_packedAdverbs.contains(word) &&
        i + 1 < raw.length &&
        raw[i + 1] == 'packed') {
      continue;
    }
    // "very finely minced shallot" keyed 'very shallot' (checkpoint 5); a
    // very ripe banana is still a ripe one.
    if (word == 'very' &&
        i + 1 < raw.length &&
        _prepWords.contains(raw[i + 1])) {
      continue;
    }
    words.add(_synonyms[word] ?? word);
  }
  _dropLeadingLeaks(words);
  // Citrus first, so "zest plus 1 tablespoon juice from 1 lemon" still names
  // the fruit before the second amount is cut — the moved fruit does not
  // count as a food ahead of a leading amount ("plus 1 tablespoon juice from
  // 2 to 3 lemons" is lemon juice); and again after, per alternative, for
  // "juice from 1 lemon or 1 teaspoon champagne vinegar".
  final moved = _fruitFromTail(words);
  final lead = identical(moved, words) ? 0 : 1;
  final kept = _withoutAmounts(moved, lead: lead);
  final out = <String>[];
  var start = 0;
  for (var k = 0; k <= kept.length; k++) {
    if (k == kept.length || kept[k] == 'or') {
      out.addAll(_fruitFromTail(kept.sublist(start, k)));
      if (k < kept.length) {
        out.add('or');
      }
      start = k + 1;
    }
  }
  // A line the corpus split mid-phrase keeps its dangling connector: "1
  // teaspoon grated fresh lime zest and" (Sweet and Saucy Glazed Salmon)
  // keyed 'lime zest and' and missed the lime-zest rewrite (checkpoint 7).
  // A dangling "or" is the same artifact (v13; no corpus line ends in one).
  if (out.lastOrNull == 'and' || out.lastOrNull == 'or') {
    out.removeLast();
  }
  return out.join(' ');
}

/// What a dropped word leaves at the front of an item (checkpoint 5: 38
/// lines under 21 keys, split from their siblings): the connector of a
/// dropped alternative ("minced or grated fresh ginger" keyed 'or ginger';
/// "fresh or frozen cranberries" 'or frozen cranberry', its form word an
/// alternative too), a measure with no number ("1 small pinch saffron";
/// "Dash of hot sauce" parses 'dash' as its unit and leaves 'of'). ('dash',
/// 'pinches' and a doubled "or" were here too: none changed a key of the
/// library, refix round 1.)
void _dropLeadingLeaks(List<String> words) {
  // Counted first and removed once: a removeAt(0) per word is quadratic in
  // a run of them (Run 055 S6).
  var k = 0;
  while (words.length - k > 1) {
    final first = words[k];
    if (first == 'or' || first == 'and') {
      k++;
      if (words.length - k > 1 && _formWords.contains(words[k])) {
        k++;
      }
    } else if (_leadingMeasures.contains(first)) {
      k++;
    } else {
      break;
    }
  }
  words.removeRange(0, k);
}

/// A measure the parse left at the front of the item, with its "of".
const Set<String> _leadingMeasures = {'pinch', 'of'};

/// Adverbs of "packed" ([normalizeItem] drops them with it).
const Set<String> _packedAdverbs = {'loosely', 'lightly', 'tightly'};

/// Measure words a leaked second amount carries ("plus 2 tablespoons").
const Set<String> _amountUnits = {
  'teaspoon',
  'teaspoons',
  'tsp',
  'tablespoon',
  'tablespoons',
  'tbsp',
  'cup',
  'cups',
  'pint',
  'pints',
  'quart',
  'quarts',
  'gallon',
  'gallons',
  'ounce',
  'ounces',
  'oz',
  'pound',
  'pounds',
  'lb',
  'lbs',
  'gram',
  'grams',
  'liter',
  'liters',
  'ml',
  'pinch',
  'pinches',
  'dash',
  'dashes',
  // "cherries from 4 (24-ounce) jars", "from 2 (15-ounce) cans" (audit 3,
  // A11).
  'jar',
  'jars',
  'can',
  'cans',
};

/// Words left dangling by a cut: "thyme or", "cornstarch dissolved in",
/// "cherries from".
const Set<String> _cutConnectors = {'or', 'and', 'in', 'with', 'from'};

/// How the food was mixed, left before a cut: "cornstarch dissolved in 2
/// tablespoons water" searched 'cornstarch dissolved' although 'cornstarch'
/// is cached (audit 3, N8).
const Set<String> _cutParticiples = {
  'dissolved',
  'mixed',
  'whisked',
  'stirred',
  'combined',
};

/// A SECOND amount the corpus parse left in the item — "½ cup plus 2
/// tablespoons olive oil" keeps "plus 2 tablespoons olive oil", "thyme or ¼
/// teaspoon dried", "zest plus ½ cup juice" (the split turns "1/4" into
/// "1 4"). A number run followed by a measure word is dropped when it leads
/// the item (the first [lead] words — a fruit [_fruitFromTail] moved to the
/// front — do not count) or directly follows an "or" (B's own amount in
/// "masa harina or 3 tablespoons cornstarch": the amount goes, B stays), and
/// cuts the item when it follows a food (the rest names another amount of
/// the same or another food; a trailing "or"/"and"/"in"/"with" goes with
/// it).
/// Before this, 252 library lines searched and were keyed with the second
/// amount in them (153 queries, 70 once it is gone), and "2 teaspoon kosher
/// salt" matched pickles. A number followed by anything else stays: "85
/// percent lean", "2 percent milk", "egg 1 yolk".
List<String> _withoutAmounts(List<String> words, {int lead = 0}) {
  final digits = RegExp(r'^\d+$');
  final out = <String>[];
  var dropped = false;
  var i = 0;
  while (i < words.length) {
    var j = i;
    while (j < words.length && digits.hasMatch(words[j])) {
      normalizeSteps++;
      j++;
    }
    // One word may stand between the number and its measure: "plus 2
    // additional tablespoons" (audit 3, A11).
    final unit = j < words.length && words[j] == 'additional' ? j + 1 : j;
    if (j > i && unit < words.length && _amountUnits.contains(words[unit])) {
      dropped = true;
      i = unit + 1;
      if (out.length <= lead || out.last == 'or') {
        continue;
      }
      break;
    }
    // A number run with no measure after it stays whole: every later word
    // of the run ends at the same word, so none is a measure's either —
    // never re-walked from each of its words (Run 055 S6: quadratic, 140 ms
    // a pass over a legal 1,000-character line).
    final end = j > i ? j : i + 1;
    out.addAll(words.sublist(i, end));
    i = end;
  }
  while (dropped &&
      out.isNotEmpty &&
      (_cutConnectors.contains(out.last) ||
          _cutParticiples.contains(out.last))) {
    out.removeLast();
  }
  return out;
}

/// Citrus the corpus writes as "juice from 1 lemon" / "zest from 2 limes":
/// FDC names the fruit first ("Lemon juice, raw"), and the count is not part
/// of the food. 120 corpus lines; before this they searched 'juice from 1
/// lemon' (bottled concentrate won) under a key no other lemon-juice line
/// shared.
const Set<String> _citrus = {
  'lemon',
  'lime',
  'orange',
  'grapefruit',
  'tangerine',
  'clementine',
};

/// "<what> from (about) N (to M) <citrus>" → "<citrus> <what>", the fruit
/// named once. Anything else is returned unchanged.
List<String> _fruitFromTail(List<String> words) {
  final from = words.lastIndexOf('from');
  if (from < 1 || from == words.length - 1) {
    return words;
  }
  final tail = words.sublist(from + 1);
  final fruit = _keyWord(tail.last);
  if (!_citrus.contains(fruit)) {
    return words;
  }
  final countWords = tail.sublist(0, tail.length - 1);
  if (!countWords.every(
    (w) =>
        RegExp(r'^\d+$').hasMatch(w) || w == 'about' || w == 'to' || w == 'or',
  )) {
    return words;
  }
  final what = [
    for (final w in words.sublist(0, from))
      if (_keyWord(w) != fruit) w,
  ];
  return [fruit, ...what];
}

/// The key a human decision is stored and reused under (`ingredient_matches
/// .item_key`, `ingredient_decisions.item_key`): [normalizeItem] with every
/// word singular, so "1 onion" and "2 onions" — 66 such pairs, 2,036 corpus
/// lines — are one ingredient. Only the KEY: the FDC query keeps the line's
/// own words, so nothing cached is invalidated and ranking is unchanged.
/// Empty when nothing searchable remains.
String itemKeyFor(String item) => [
  for (final word in normalizeItem(item).split(' '))
    if (word.isNotEmpty) _keyWord(word),
].join(' ');

/// [word] in its decision-key form (singular), for tables keyed by word.
String keyWordOf(String word) => _keyWord(word);

/// Singular form for a decision key. Deliberately plain: a key only has to
/// be the SAME for both spellings, not a dictionary word ('cooky' is fine).
/// Guards keep singular words that end in s ('asparagus', 'molasses').
String _keyWord(String word) {
  if (word.length <= 3 ||
      word.endsWith('ss') ||
      word.endsWith('us') ||
      word.endsWith('is')) {
    return word;
  }
  if (word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('ves')) {
    // leaves → leaf, halves → half, loaves → loaf; but 'olives', 'chives',
    // 'cloves' keep their v: strip the s only.
    const fToVes = {'leaves', 'halves', 'loaves', 'calves', 'knives'};
    return fToVes.contains(word)
        ? '${word.substring(0, word.length - 3)}f'
        : word.substring(0, word.length - 1);
  }
  if (word.endsWith('oes')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('es')) {
    final stem = word.substring(0, word.length - 2);
    if (stem.endsWith('ss')) {
      return word; // molasses
    }
    final sibilant =
        stem.endsWith('s') ||
        stem.endsWith('x') ||
        stem.endsWith('z') ||
        stem.endsWith('ch') ||
        stem.endsWith('sh');
    return sibilant ? stem : word.substring(0, word.length - 1);
  }
  if (word.endsWith('s')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// Whether the normalized item is water/ice (skip FDC, contribute zeros).
bool isWaterLike(String normalizedItem) =>
    waterLikeItems.contains(normalizedItem);

/// Equipment the corpus lists among the ingredients ("Wooden skewers", "2 cups
/// wood chips", "1 36-inch square cheesecloth", "disposable aluminum roasting
/// pan"): 55 library lines that FDC answered with crackers, cereal and
/// baking powder ("cheesecloth" counted 30 g of oat squares). Matched like
/// water — a confirmed zero, never searched. "pan" alone is deliberately
/// absent: "pan sauce", "giblet pan gravy" and "pan-seared steaks" are food.
const Set<String> _nonFoodWords = {
  'disposable',
  'aluminum',
  'cheesecloth',
  'skewer',
  'skewers',
  'twine',
  'parchment',
  'toothpick',
  'toothpicks',
  'charcoal',
};

/// Whether the normalized item names equipment, not food (skip FDC,
/// contribute zeros).
bool isNonFood(String normalizedItem) =>
    normalizedItem.split(' ').any(_nonFoodWords.contains) ||
    normalizedItem.contains('wood chips') ||
    normalizedItem.contains('wood chunks') ||
    // "1 large oven bag" searched french fries (audit 4: one detail fetch).
    normalizedItem.contains('oven bag') ||
    // "lollipop or popsicle sticks" counted 120 g of "Popsicle" at the gate
    // (checkpoint 5).
    normalizedItem.contains('popsicle stick') ||
    // "8 ounces banana leaf, cut into long strips" wraps the cochinita pibil
    // and is not eaten: it counted 193 kcal of banana (v21 plan §3).
    normalizedItem.contains('banana leaf') ||
    normalizedItem.contains('banana leaves');

/// Seasoning a recipe adds "to taste": with no amount on the line it
/// contributes nothing measurable, and FDC's search for it returns bell
/// peppers and salted nuts. Such a line is confirmed as a deliberate
/// no-match instead of sitting in the review queue forever. A line WITH an
/// amount ("1 teaspoon table salt") is matched normally.
const Set<String> seasoningToTasteItems = {
  'salt',
  'table salt',
  'kosher salt',
  'sea salt',
  'flaky sea salt',
  'flake sea salt',
  'pepper',
  'black pepper',
  'ground pepper',
  'ground black pepper',
  'salt and pepper',
  'salt and black pepper',
  'salt and ground pepper',
  'salt and ground black pepper',
  'table salt and pepper',
  'table salt and ground black pepper',
  'kosher salt and pepper',
  'kosher salt and ground black pepper',
};

/// Whether an amount-less line of [normalizedItem] is seasoning to taste.
bool isSeasoningToTaste(String normalizedItem) =>
    seasoningToTasteItems.contains(normalizedItem);

/// Phrases FDC's search cannot find under the recipe's words, rewritten to
/// the words FDC files them under. Keyed by the NORMALIZED item — exactly
/// as [normalizeItem] leaves it, prep words already gone — the value is the
/// query. Bare 'rye' is deliberately absent: in recipes it is a grain or a
/// bread (every corpus use); the spirit is 'rye whiskey'. Every target was
/// chosen from a recorded FDC answer (test/fixtures/fdc/searches.json).
///
/// Pepper: FDC's search for "black pepper", "pepper" or "red pepper flakes"
/// returns only the vegetables ("Peppers, sweet, green…"); the spice records
/// answer to "spices pepper …". Spirits: FDC has no brand liqueurs at all —
/// "grand marnier" found a candy bar — but clean generic entries for
/// liqueur, brandy, rum and whiskey.
const Map<String, String> _queryRewrites = {
  // pepper, the spice
  'pepper': 'spices pepper black',
  'black pepper': 'spices pepper black',
  'ground pepper': 'spices pepper black',
  'ground black pepper': 'spices pepper black',
  'cracked black pepper': 'spices pepper black',
  'black peppercorns': 'spices pepper black',
  'peppercorns': 'spices pepper black',
  'whole peppercorns': 'spices pepper black',
  'whole black peppercorns': 'spices pepper black',
  'cracked peppercorns': 'spices pepper black',
  'cracked black peppercorns': 'spices pepper black',
  'white pepper': 'spices pepper white',
  'ground white pepper': 'spices pepper white',
  'red pepper flakes': 'spices pepper red cayenne',
  'cayenne': 'spices pepper red cayenne',
  'cayenne pepper': 'spices pepper red cayenne',
  'ground cayenne pepper': 'spices pepper red cayenne',
  // orange liqueurs and liqueurs in general
  'grand marnier': 'liqueur',
  'cointreau': 'liqueur',
  'triple sec': 'liqueur',
  'orange liqueur': 'liqueur',
  'amaretto': 'liqueur',
  'kahlua': 'liqueur',
  'coffee liqueur': 'liqueur',
  // brandies
  'calvados': 'brandy',
  'cognac': 'brandy',
  'armagnac': 'brandy',
  'apple brandy': 'brandy',
  // rums
  'spiced rum': 'rum',
  'dark rum': 'rum',
  'light rum': 'rum',
  'white rum': 'rum',
  'gold rum': 'rum',
  // whiskeys
  'bourbon': 'whiskey',
  'bourbon whiskey': 'whiskey',
  'rye whiskey': 'whiskey',
  'scotch': 'whiskey',
  'scotch whisky': 'whiskey',
  'whisky': 'whiskey',
  // Design review D4 (2026-09-08), every target's answer recorded from live
  // FDC in the diagnostic cache: ground spices file under their seed; canned
  // tomatoes aside, FDC's spice records lead with "Spices, …".
  'ground cumin': 'cumin seeds',
  'ground coriander': 'coriander seeds',
  'ground fennel': 'fennel seeds',
  'cinnamon': 'ground cinnamon',
  'cinnamon stick': 'ground cinnamon',
  'cinnamon sticks': 'ground cinnamon',
  'whole cloves': 'ground cloves',
  'frozen phyllo': 'phyllo',
  'bay leaves': 'bay leaf',
  'parsley leaves': 'parsley',
  'vegetable oil for frying': 'vegetable oil',
  // 'bacon' alone returns bits, meatless and turkey bacon before pork.
  'bacon': 'pork cured bacon unprepared',
  // Every bare 'shrimp' answer is a dish (cocktail, scampi, fried).
  'shrimp': 'shrimp raw',
  'extra-large shrimp': 'shrimp raw',
  'jumbo shrimp': 'shrimp raw',
  'shell-on shrimp': 'shrimp raw',
  // The size words the list above missed (checkpoint 7): each answer was
  // dishes, and "Shrimp, NFS" held 4 lines under the gate.
  'medium-large shrimp': 'shrimp raw',
  'colossal shrimp': 'shrimp raw',
  'shell-on jumbo shrimp': 'shrimp raw',
  // FDC files sherry under dessert wine and lager under beer.
  'sherry': 'wine dessert dry',
  'dry sherry': 'wine dessert dry',
  // FDC has no vermouth record; its answer for 'dry vermouth' is junk. The
  // fortified dry wine it is closest to is the sherry target (recorded).
  'vermouth': 'wine dessert dry',
  'dry vermouth': 'wine dessert dry',
  'lager': 'beer',
  'mild lager': 'beer',
  'dijon mustard': 'mustard prepared',
  // Pasta shapes FDC does not know by name.
  'penne': 'pasta dry enriched',
  'campanelle': 'pasta dry enriched',
  'spaghettini': 'pasta dry enriched',
  'linguine': 'pasta dry enriched',
  'rigatoni': 'pasta dry enriched',
  'orecchiette': 'pasta dry enriched',
  'farfalle': 'pasta dry enriched',
  'ziti': 'pasta dry enriched',
  'fusilli': 'pasta dry enriched',
  'gemelli': 'pasta dry enriched',
  'cavatappi': 'pasta dry enriched',
  'bucatini': 'pasta dry enriched',
  'tagliatelle': 'pasta dry enriched',
  'fettuccine': 'pasta dry enriched',
  'pappardelle': 'pasta dry enriched',
  'orzo': 'pasta dry enriched',
  'ditalini': 'pasta dry enriched',
  // Bare 'spaghetti' ranked Foundation "Pasta, dry, whole grain, spaghetti"
  // (2759000) first, a record with no energy and no macros; the cached
  // answer for the target ranks "Pasta, dry, enriched" (169736) at 1.00.
  'spaghetti': 'pasta dry enriched',
  // Sweep accuracy batch (2026-09-26). A bare animal is the whole bird:
  // 'turkey' ranked "Bologna, turkey" first (11 whole turkeys, +48,058 kcal)
  // and 'chicken' "Chicken spread"; FDC's answers hold no whole-bird record.
  // The cuts FDC files under the animal's name. Each target is pending ONE
  // live search (not in the recorded fixtures — pinned as such).
  'turkey': 'turkey whole meat and skin raw',
  'chicken': 'chicken broilers or fryers meat and skin raw',
  // The whole-bird class is this key, not bare 'chicken' (1 line): 26 lines
  // held 46,266 g on "School Lunch, chicken nuggets" (audit 3).
  'whole chicken': 'chicken broilers or fryers meat and skin raw',
  'whole chickens': 'chicken broilers or fryers meat and skin raw',
  'standing rib roast': 'beef rib whole raw',
  // The corpus writes steak tips, never bare 'sirloin tips' in a line FDC
  // answered: 8 lines counted "tri-tip … cooked, broiled" (audit 3).
  'sirloin tips': 'beef sirloin tip',
  'sirloin steak tips': 'beef sirloin tip',
  'sirloin steak tip': 'beef sirloin tip',
  'sirloin tip steaks': 'beef sirloin tip',
  'sirloin tip steak': 'beef sirloin tip',
  // Dishes and products that beat the ingredient (audit 1 rank 9): the
  // answer's own words cover "Egg sandwich on white bread", "Sweet potato
  // tots", "Blackeyed peas, from frozen", "Beverages, Clam and tomato juice",
  // "Tomato chili sauce", "Babyfood, juice, orange". Targets name FDC's raw
  // or plain record; 'short' is "short, curly pasta" cut at the comma.
  'white sandwich bread': 'bread white commercially prepared',
  'hearty white sandwich bread': 'bread white commercially prepared',
  'slice white sandwich bread': 'bread white commercially prepared',
  // "Veggie burger, on bun" counted for burger buns; FDC files the plain bun
  // as "Rolls, hamburger or hotdog, plain" (172796, in the recorded
  // 'hamburger rolls' answer).
  'burger buns': 'rolls hamburger or hotdog plain',
  'burger bun': 'rolls hamburger or hotdog plain',
  'hamburger buns': 'rolls hamburger or hotdog plain',
  'hamburger bun': 'rolls hamburger or hotdog plain',
  'sweet potatoes': 'sweet potato raw unprepared',
  'frozen peas': 'peas green frozen unprepared',
  'frozen baby peas': 'peas green frozen unprepared',
  'frozen petite peas': 'peas green frozen unprepared',
  'frozen green peas': 'peas green frozen unprepared',
  'clam juice': 'mollusks clam canned liquid',
  'bottle clam juice': 'mollusks clam canned liquid',
  'bottled clam juice': 'mollusks clam canned liquid',
  'tomato sauce': 'tomato products canned sauce',
  'canned tomato sauce': 'tomato products canned sauce',
  'simple tomato sauce': 'tomato products canned sauce',
  // "Rice and vermicelli mix, beef flavor" (4 lines); the recorded 'rice
  // noodles' answer ranks "Rice noodles, dry" (169742) first.
  'rice vermicelli': 'rice noodles',
  'orange juice': 'orange juice raw',
  'short': 'pasta dry enriched',
  'dark': 'chocolate dark',
  'romaine heart': 'lettuce romaine raw',
  'romaine hearts': 'lettuce romaine raw',
  'romaine lettuce heart': 'lettuce romaine raw',
  // A kind word the head noun hides (audit 2): the butt is not the loin,
  // cottage cheese is not ricotta, masa harina is the dry flour, lo mein
  // noodles are fresh egg pasta, not fried chow mein.
  'boneless pork butt roast': 'pork boston butt lean and fat',
  'boneless pork butt': 'pork boston butt lean and fat',
  'bone-in pork butt': 'pork boston butt lean and fat',
  '4-pound boneless pork butt roast': 'pork boston butt lean and fat',
  '5-pound boneless pork butt roast': 'pork boston butt lean and fat',
  'cottage cheese': 'cheese cottage creamed curd',
  'whole-milk cottage cheese': 'cheese cottage creamed curd',
  'whole-milk or 1 percent cottage cheese': 'cheese cottage creamed curd',
  'masa harina': 'corn flour masa harina',
  'lo mein noodles': 'pasta fresh-refrigerated plain as purchased',
  // Herbs FDC files under another word: 'dill' ranked "Pickles, cucumber,
  // dill" and 'mint' "Mint julep"; kosher salt is table salt to FDC.
  'dill': 'dill weed',
  'dill leaves': 'dill weed',
  'mint': 'spearmint',
  'mint leaves': 'spearmint',
  'kosher salt': 'salt table',
  // Wrong foods the grams fill-in would start counting (their volume lines
  // were held in no_grams only for want of grams): both coconut answers are
  // coconut water and cream, never the meat; 'baby back ribs' named no animal
  // and took beef back ribs; the orange liqueur took the coffee one.
  // The not-sweetened record: under 'nuts coconut meat dried' the CREAMED
  // one ranked first (audit 4); under this target the recorded answer ranks
  // "…dried (desiccated), not sweetened" first (pending one live search).
  'unsweetened coconut': 'nuts coconut meat dried not sweetened',
  'sweetened coconut': 'nuts coconut meat dried sweetened',
  'baby back ribs': 'pork backribs raw',
  'orange-flavored liqueur': 'liqueur',
  // Compound heads (audit 3, N3): the head noun is the second word of
  // another food — "Almond butter", "Peanut butter", "Pie, coconut cream",
  // "Blackeye pea, dry", "Gelatin dessert", "Green beans … with butter".
  'butter': 'butter salted',
  // The normalizer spells 'salted' "with salt": the target re-searched from
  // the sheet must land on the same cache key.
  'butter with salt': 'butter salted',
  'european-style without salt butter': 'without salt butter',
  'cream of coconut': 'coconut cream canned sweetened',
  'gelatin': 'gelatins dry powder unsweetened',
  'unflavored gelatin': 'gelatins dry powder unsweetened',
  'unflavored powdered gelatin': 'gelatins dry powder unsweetened',
  'powdered gelatin': 'gelatins dry powder unsweetened',
  'peas': 'peas green raw',
  'butter beans': 'lima beans',
  // Kind words (audit 3, N10): celery root is celeriac, not celery; a
  // coloured mustard seed is the seed ('mustard seeds' is recorded), not
  // prepared yellow mustard.
  'celery root': 'celeriac raw',
  // "Archway Home Style Cookies, Dutch Cocoa" counted 0.55 for Dutch cocoa:
  // a mixed-case brand gets past [_brandToken] (pinned); the recorded
  // 'dutch-processed cocoa powder' answer ranks the alkali cocoa first.
  'dutch-processed cocoa': 'dutch-processed cocoa powder',
  'yellow mustard seeds': 'mustard seeds',
  'brown mustard seeds': 'mustard seeds',
  // With the count noun gone, "lemon-lime soda" covered both alternatives
  // (0.54) and the amount-less line resolved on it at 0 g, out of review.
  'lemon or lime wedges': 'lemon wedges',
  // Audit 4 (checkpoint 4, snap6). Mixed chicken pieces are the whole bird:
  // "Chicken skin" crossed the gate at exactly 0.50 for skin-on pieces (4
  // lines, 6,577 g at 450 kcal/100 g) and fried skin-and-breading held the
  // rest; the target's answer is recorded (171447 first).
  'bone-in skin-on chicken pieces':
      'chicken broilers or fryers meat and skin raw',
  'bone-in chicken pieces': 'chicken broilers or fryers meat and skin raw',
  // "Yeast" (2710005) scores 0.37 under the alternative, 0.57 under the
  // recorded 'instant yeast' answer: 48 lines in check, 21 recipes blocked.
  'instant or rapid-rise yeast': 'instant yeast',
  // The raw bird, not FNDDS "Cornish game hen, cooked, skin eaten" (3 lines,
  // 8,165 g); its record 171507 leads the recorded 'cornish game hens'
  // answer under the target (pending one live search).
  'cornish game hens': 'chicken cornish game hens meat and skin raw',
  'whole cornish game hens': 'chicken cornish game hens meat and skin raw',
  // Cherry tomatoes are tomatoes: under their own words every record fell
  // below the gate once roma was docked (9 lines, 5,408 g). Under 'tomatoes'
  // roma won and has no volume portion (2 lines in no_grams); the recorded
  // 'ripe tomatoes' answer ranks 170457 first, whose portions include a cup
  // of cherry tomatoes (checkpoint 5).
  'cherry tomatoes': 'ripe tomatoes',
  // Curing salt is salt to FDC ("Pork, cured, salt pork" at 0.34).
  'pink curing salt': 'salt table',
  // Checkpoint 5. The desiccated coconut the joined comma segments name:
  // "Coconut water, unsweetened" counted 720 g for the macaroons (0831).
  // (Bare 'desiccated coconut' is no line's key: not here.)
  'unsweetened desiccated coconut': 'nuts coconut meat dried not sweetened',
  // Names FDC has no record under — each answer is recorded as [] — moved to
  // a recorded stand-in. Pancetta is an APPROXIMATION the user flagged:
  // cured unsmoked pork belly, counted as bacon (18 lines).
  'pancetta': 'pork cured bacon unprepared',
  'panko': 'bread crumbs',
  'stout': 'beer',
  'mezze rigatoni': 'pasta dry enriched',
  'tubetti': 'pasta dry enriched',
  'madeira': 'wine dessert dry',
  'sukang maasim': 'vinegar',
  // Checkpoint 6. FDC answers the country-style rib lines' own words with
  // COOKED records only ("…, boneless, cooked, broiled", 4 each): 7 raw
  // lines counted broiled meat at bought weight (0612 about 619 kcal a
  // serving over). The recorded answer for the 0352 phrase ranks the raw
  // record 167895 first — whose detail's refuse yield (0.65) the bone-in
  // line reads. (A cook-state dock beside a raw record of the same cut was
  // measured first: no answer of these lines holds one, 0 rows moved.)
  'boneless country-style pork ribs':
      'pork spareribs or country-style ribs or beef short ribs',
  'bone-in country-style pork ribs':
      'pork spareribs or country-style ribs or beef short ribs',
  // Variety words FDC files under another name (checkpoint 6: each answer
  // was all dishes tying at 0.465 — "Cheese, Monterey" for gorgonzola, "Rice
  // crackers" for arborio, veal for 90% lean ground sirloin). Every target's
  // answer is recorded and ranks the named record first.
  'gorgonzola cheese': 'blue cheese',
  'arborio rice': 'short-grain white rice',
  'valencia or arborio rice': 'short-grain white rice',
  '90 percent lean ground sirloin': '90 percent lean ground beef',
  'andouille sausage': 'smoked sausage',
  'kielbasa sausage': 'kielbasa',
  // APPROXIMATIONS the user accepted (like pancetta above): FDC has no Asiago
  // (its answer is dishes and "Cheese, Monterey") — counted as Parmesan, the
  // hard grating cheese it is closest to; and no whole allspice — counted as
  // "Spices, allspice, ground" (the answer's top was "Berries, NFS").
  'asiago cheese': 'parmesan cheese',
  'allspice berries': 'ground allspice',
  'whole allspice berries': 'ground allspice',
  // An APPROXIMATION the user accepted (like pancetta above): FDC has no
  // lime peel — its answer for 'lime zest' held none ("Lime, raw" won at
  // 0.485), and the ONE approved live search for 'lime peel raw' tied
  // "Lemon peel, raw" with "Orange peel, raw" at 0.637, so FDC's order
  // picked. Lime zest searches as lemon zest, whose answer ranks "Lemon
  // peel, raw" (167749) alone first (v11).
  'lime zest': 'lemon zest',
  // Checkpoint 7, each target's answer recorded and ranking the named record
  // first. A skin-on fillet's answer holds no raw salmon ("…king, with skin,
  // kippered, (Alaska Native)" held 9 lines at 0.473); the skinless
  // fillet's ranks "Fish, salmon, raw" first — the skin changes little.
  'skin-on salmon fillet': 'skinless salmon fillet',
  'skin-on salmon fillets': 'skinless salmon fillet',
  // "6 (6- to 8-ounce) center-cut skin-on salmon fillets" (Grill-Smoked
  // Salmon, 0646) kept its cut word and missed the entry above (v12 review).
  'center-cut skin-on salmon fillets': 'skinless salmon fillet',
  // FDC has no pepperoncini (its answer is []): a pickled hot pepper, whose
  // generic record "Peppers, hot, pickled" (2710095) leads this answer.
  'pepperoncini': 'pickled hot cherry peppers',
  // Oranges for juicing are oranges: "Orange Pineapple Juice Blend" took the
  // line at 0.90 once 'oranges' stemmed to 'orange' (v12).
  'juice oranges': 'oranges',
  // An APPROXIMATION (like pancetta above): FDC has no dried tangerine peel;
  // its answer for 'chen pi' is all cookies and pies at 0 — counted as
  // "Orange peel, raw". Dried peel counted on a RAW-peel record is about 3×
  // short per gram (the water it lost): flagged in docs/API.md, and a ruling
  // the user has not made yet.
  'chen pi': 'orange peel',
  // "1 medium, ripe avocado, diced medium" (0487) and "2 large, firm, ripe
  // bananas" (0959) searched nothing until v12 read past their size
  // segment; the recorded plural and 'very ripe' answers rank "Avocado,
  // Hass, peeled, raw" and "Bananas, ripe and slightly ripe, raw" first.
  // "Cookie, chocolate chip" counted for white chocolate chips (Low-Fat
  // Chocolate Mousse, 0933; Blondies): once coated records are composites
  // the cached 'white chocolate' answer ranks "Candies, white chocolate"
  // (167571) first (v13, Opus critic).
  'white chocolate chips': 'white chocolate',
  'ripe avocado': 'ripe avocados',
  'ripe bananas': 'very ripe bananas',
  // The raw halibut record 174200 leads no recorded answer: the cooked FNDDS
  // "Fish, halibut" (175 kcal / 100 g) took the skinless lines, and "Pepper
  // steak" the steaks. PENDING one live search (pendingSearches).
  'skinless halibut fillet': 'halibut atlantic and pacific raw',
  'skinless halibut fillets': 'halibut atlantic and pacific raw',
  'halibut steaks': 'halibut atlantic and pacific raw',
  // Checkpoint 8 (B2): keys in check whose right record leads a cached
  // answer — each target's answer is in snapshot 12's search cache and
  // ranks the named record first over the gate (pinned).
  'thick-cut bacon': 'pork cured bacon unprepared',
  'cilantro leaves and stems': 'cilantro',
  'cilantro leaves and tender stems': 'cilantro',
  // Fresh Thai chiles took the SUN-DRIED record; FDC's raw hot pepper
  // "Peppers, hot, raw" (2709798) leads only this cached answer (0.52).
  'thai chile': 'jarred hot cherry peppers',
  'thai chiles': 'jarred hot cherry peppers',
  'green or red thai chiles': 'jarred hot cherry peppers',
  'elbow macaroni': 'pasta dry enriched',
  'no-boil lasagna noodles': 'pasta dry enriched',
  '80 percent lean ground chuck': '80 percent lean ground beef',
  'light or mild molasses': 'molasses',
  'oyster-flavored sauce': 'oyster sauce',
  // Shaoxing is a Chinese rice wine: "Wine, rice" (2710691).
  'shaoxing wine or dry sherry': 'dry sherry or chinese rice wine',
  // A mild dried chile, on "Peppers, hot chile, sun-dried" (168570).
  'dried new mexican chiles': 'mild dried chile',
  'flake sea salt': 'salt table',
  'sea salt': 'salt table',
  'whole grain mustard': 'mustard prepared',
  'whole-grain mustard': 'mustard prepared',
  // The tenderloin by its cut names: "Beef, tenderloin steak, raw".
  'beef tenderloin center-cut chateaubriand': 'beef tenderloin',
  'center-cut filet mignon': 'beef tenderloin',
  'center-cut filets mignons': 'beef tenderloin',
  'kale or collard greens': 'kale',
  'broccoli florets': 'broccoli',
  'stone-ground cornmeal': 'cornmeal',
  'baby back or loin back ribs': 'pork backribs raw',
  'ripe but firm bosc pears': 'bosc pear',
  'white baking chips': 'white chocolate',
  // Matcher v17 (checkpoint 8, approved live searches): names FDC spells
  // another way, whose right record sat under the gate in every cached
  // answer. Each target was searched live once (snapshot 13) and is
  // recorded; the pins read FDC's real answer.
  // FDC has no 'baguette': "Bread, French or Vienna" (2707610) scored 0.
  'baguette': 'french bread',
  'crusty baguette': 'french bread',
  // FDC spells it 'raab' ("Broccoli raab, raw", 170381, at 0.16).
  'broccoli rabe': 'broccoli raab',
  // Quick-cooking tapioca is the dry pearl (169717, at 0.44 ahead of the
  // puddings).
  'instant tapioca': 'tapioca pearl dry',
  'minute tapioca': 'tapioca pearl dry',
  // "Pork, fresh, spareribs, separable lean and fat, raw" (167853, 0.26).
  'st louis style spareribs': 'pork spareribs raw',
  'full racks pork spareribs': 'pork spareribs raw',
  // The arils are the fruit ("Pomegranates, raw" / "Pomegranate, raw").
  'pomegranate seeds': 'pomegranate raw',
  // The candy, never FNDDS "Chocolate milk, whole" (2705467, the DRINK, 83
  // kcal / 100 g) — "Candies, milk chocolate" (167587) ranked 20th under
  // 'milk chocolate'. ('milk chocolate chip' is deliberately NOT mapped to
  // 'milk chocolate', which lands on the drink.)
  'milk chocolate': 'milk chocolate candy',
  'milk chocolate chips': 'milk chocolate candy',
  // A fish steak, never "Pepper steak" (2706747, 0.47, 'steak' as the head
  // noun): "Fish, swordfish, raw" (173703) / "Fish, tuna, raw" (2706308).
  'skinless swordfish steaks': 'swordfish raw',
  'tuna steaks': 'tuna raw',
  // The dry powder (172195 / 170877 "Milk, dry, nonfat, regular, …"), not
  // cocoa (0.48); 'nonfat dry milk' would rank the RECONSTITUTED liquid.
  'nonfat dry milk powder': 'milk dry nonfat regular',
  // "Pumpkin, canned, without salt" (168450), not "Prune puree" (0.48);
  // 'canned pumpkin' ties the salted record.
  'pumpkin puree': 'pumpkin canned without salt',
  'unsweetened pumpkin puree': 'pumpkin canned without salt',
  // The spread, not "Nutella sandwich on wheat bread" (0.43).
  'nutella': 'chocolate hazelnut spread',
  // FDC spells it 'Waterchestnuts' (170066); the cached answer held only
  // "Jai, Monk's Food".
  'water chestnuts': 'waterchestnuts chinese raw',
  // "Milk, buttermilk, dried" (171274), not dried egg white or baobab.
  'dried buttermilk powder': 'milk buttermilk dried',
  'buttermilk powder': 'milk buttermilk dried',
  // Rewrites to answers already cached (no request). Boneless country-style
  // "spareribs" are the loin's country-style ribs (167895 first at 0.52),
  // not the sparerib record they sat on at 0.39.
  'boneless country-style pork spareribs':
      'pork spareribs or country-style ribs or beef short ribs',
  // 'whole' and 'skin-on' only lowered 171093 "Turkey, all classes, breast,
  // meat and skin, raw" (0.48, 0.43); the cached answer ranks it at 0.55.
  'whole bone-in turkey breast': 'bone-in turkey breast',
  'whole bone-in skin-on turkey breast': 'bone-in turkey breast',
  // A fresh red Thai chile, not the sun-dried 168570: the other Thai chile
  // keys' answer ranks "Peppers, hot, raw" (2709798) first. ('thai red
  // chile' is NOT mapped: the piece table's 'thai chile' misses it, so its
  // count would read the record's 15 g whole pepper.)
  'red thai chile': 'jarred hot cherry peppers',
  // Granulated garlic is the dried powder, not "Garlic, raw" (1104647,
  // 0.55): the cached answer holds "Spices, garlic powder" (171325) alone.
  'granulated garlic': 'garlic powder',
  // v21 (the v21 plan §2–§3, every target an answer snapshot 13 holds,
  // ranked under the target's own words onto the named record; pinned in
  // test/nutrition_v21_test.dart). Queue tier a — the right food ranked
  // under the line's extra words ("firm tart apples", "ancho pods",
  // "king arthur bread flour"), or a wrong record in check ("pickling
  // cucumbers" on dill pickles, "fingerling potatoes" on potato bread,
  // "calasparra or bomba rice" on rice crackers). Flagged approximations
  // ([approximationRecords]): fingerling → red potato, spicy greens →
  // arugula, tapioca starch → tapioca pearl.
  '1 4-inch-thick deli ham': 'deli ham',
  '100 percent agave tequila': 'tequila',
  'cold vodka or tequila': 'vodka',
  'ancho or other mild chili powder': 'chili powder',
  'ancho pods': 'dried ancho chiles',
  'animal crackers': 'nabisco barnum s animal crackers or social tea biscuits',
  'commercial sazon': 'sazon',
  'bacon drippings or vegetable oil': 'vegetable oil',
  'bone-in skin-on split chicken breasts or 4 bone-in':
      'bone-in skin-on chicken breast halves',
  'bone-in split chicken breasts and or leg quarters':
      'bone-in chicken breasts',
  'broccoli crowns': 'broccoli',
  'calasparra or bomba rice': 'medium-grain rice',
  'cardamom seeds': 'ground cardamom',
  'green cardamom pods': 'cardamom pods',
  'inexpensive fruity medium-bodied red wine': 'red wine',
  'chinese sesame paste or tahini': 'tahini',
  'coarse-ground cornmeal': 'cornmeal',
  'cold milk': 'milk',
  'ditalini pasta': 'pasta dry enriched',
  'dried shiitake mushroom caps': 'dried shiitake mushrooms',
  'fire-roasted diced tomatoes': 'diced tomatoes',
  'fire-roasted tomatoes': 'crushed tomatoes',
  'firm mcintosh apples': 'mcintosh apples',
  'firm sweet apples': 'apples',
  'firm tart apples': 'apples',
  'sweet and tart apples': 'apples',
  'flat-leaf parsley leaves': 'parsley',
  'globe or italian eggplants': 'eggplant',
  'green or brown lentils': 'lentils',
  'israeli couscous': 'couscous',
  'king arthur bread flour': 'bread flour',
  'light or dark molasses': 'molasses',
  'mild or light molasses': 'molasses',
  'mexican oregano': 'dried oregano',
  'phyllo sheets': 'phyllo',
  'pickled jalapenos': 'pickled jalapeno chiles',
  'jarred jalapenos': 'pickled jalapeno chiles',
  'prewashed white quinoa': 'prewashed quinoa',
  'quick-cooking oats': 'quick oats',
  'red miso paste': 'white miso',
  'white miso paste': 'white miso',
  'red pepper fakes': 'spices pepper red cayenne',
  'red plums': 'plums',
  'ripe but firm peaches': 'peaches',
  'skin-on haddock fillets': 'skinless haddock fillets',
  'strong coffee': 'brewed coffee',
  'tabasco or other hot sauce': 'hot pepper sauce',
  'thick-sliced soppressata or salami': 'salami',
  'toasted slivered almonds': 'slivered almonds',
  'vine-ripened tomato': 'ripe tomatoes',
  'white american cheese': 'american cheese',
  'whole pecans or walnuts': 'pecans',
  'whole rosemary leaves': 'rosemary',
  'fingerling potatoes': 'red potatoes',
  'pickling cucumbers': 'cucumbers',
  'lemongrass stalks': 'lemon grass stalks',
  'kettle-cooked potato chips': 'plain potato chips',
  'canela cinnamon': 'ground cinnamon',
  'chinese rice wine or dry sherry': 'dry sherry or chinese rice wine',
  'chinese rice cooking wine or dry sherry': 'dry sherry or chinese rice wine',
  'rice wine or dry sherry': 'dry sherry or chinese rice wine',
  'bird chiles': 'dried arbol chiles',
  'arbol chiles': 'dried arbol chiles',
  'whole dried red chiles': 'dried arbol chiles',
  'whole dried arbol chiles': 'dried arbol chiles',
  'dried de arbol chiles': 'dried arbol chiles',
  'basmati rice': 'long-grain white rice',
  'parsley leaves and tender stems': 'parsley',
  'parsley leaves and stems': 'parsley',
  'champagne vinegar': 'vinegar',
  'champagne vinegar or white wine vinegar': 'vinegar',
  'sake or dry vermouth': 'sake',
  'cauliflower florets': 'cauliflower',
  'mixed berries': 'berries',
  'spicy greens': 'arugula',
  'tamarind juice concentrate': 'tamarind paste',
  'curly-edged lasagna noodles': 'pasta dry enriched',
  'chinese noodles': 'pasta fresh-refrigerated plain as purchased',
  'chinese wheat noodles': 'pasta fresh-refrigerated plain as purchased',
  'white rice': 'long-grain white rice',
  'brown lentils': 'lentils',
  // The tapioca-pearl cup (169717, 152 g) for tapioca starch: the same
  // 358 kcal/100 g, a denser cup (J5, approved flagged).
  'tapioca starch': 'tapioca pearl dry',
};

/// The FDC search query for a normalized item: the item itself, unless a
/// [_queryRewrites] phrase applies. The item key (identity across recipes)
/// stays the normalized item; only what is sent to FDC — and so the search
/// cache key — changes.
String searchQueryFor(String normalizedItem) =>
    _queryRewrites[normalizedItem] ?? normalizedItem;

/// Rank-as items (v21): normalized item → (the CACHED answer the line reads,
/// the record's own words that rank it). For a right record that leads no
/// cached answer under any cached query's own words (crab lump, collards,
/// raw dry legumes, raw pork tenderloin…): the line reads an answer FDC
/// already gave — its own or another query's — ranked as if the record's
/// name had been searched. An answer already cached sends nothing; one not
/// yet stored is searched once under its own words, as any line's is (all
/// of them are cached in snapshot 13's library). Never a [_queryRewrites]
/// key or target: those are [leftAlternative] food nouns, and a fragment
/// key there ('thai') split "Thai or Italian basil leaves" into 225 g of
/// hot peppers (v21 plan). Each landing is pinned in
/// test/nutrition_v21_test.dart.
const Map<String, (String, String)> _rankAs = {
  // The "2 Thai, serrano, or jalapeño chiles" fragment: the record's whole
  // hot pepper (15 g each; a Thai chile is ~2 g — accepted, J6).
  'thai': ('jarred hot cherry peppers', 'jarred hot cherry peppers'),
  // One-word items the v21 plan wrote as rewrites, kept off the
  // [leftAlternative] food nouns: each reads its old target's answer under
  // the same words, so its line lands where the rewrite put it.
  'chianti': ('red wine', 'red wine'),
  'lemongrass': ('lemon grass stalks', 'lemon grass stalks'),
  'vermicelli': ('pasta dry enriched', 'pasta dry enriched'),
  // The v21 plan §2–§3 (each landing pinned): wrappers, crab lump,
  // collards, gai lan, raw snapper, the jams and jellies ('apple jelly'
  // reads the 'jalapeno jelly' answer: its own holds no jelly record), and
  // the counted wrong-food classes — dried legumes on FNDDS "from dried, fat
  // added", raw pork tenderloin, raw ground meats and livers, coleslaw mix
  // on dressed coleslaw. Flagged approximations ([approximationRecords]):
  // pinto and other dried beans → navy beans, All-Bran → bran flakes,
  // seven-grain hot cereal → whole wheat hot cereal.
  'round rice paper wrappers': ('round rice paper wrappers', 'rice paper'),
  'gyoza wrappers': (
    'gyoza wrappers',
    'wonton wrappers includes egg roll wrappers',
  ),
  'square lumpia wrappers or spring roll wrappers': (
    'square lumpia wrappers or spring roll wrappers',
    'wonton wrappers includes egg roll wrappers',
  ),
  'new england style hot dog buns': (
    'new england style hot dog buns',
    'roll white hot dog bun',
  ),
  'portobello mushroom caps': ('portobello mushrooms', 'mushroom portabella'),
  'dried mint': ('dried mint', 'spearmint dried'),
  'snow peas': ('snow peas', 'peas edible-podded raw'),
  'sugar snap peas': ('sugar snap peas', 'peas edible-podded raw'),
  'snow peas or sugar snap peas': ('snow peas', 'peas edible-podded raw'),
  'cherry preserves': ('cherry preserves', 'jams and preserves'),
  'raspberry preserves': ('raspberry preserves', 'jams and preserves'),
  'red currant jelly': ('red currant jelly', 'jellies'),
  'jalapeno jelly': ('jalapeno jelly', 'jellies'),
  'red currant or apple jelly': ('red currant or apple jelly', 'jellies'),
  'apple jelly': ('jalapeno jelly', 'jellies'),
  'bone-in turkey thigh': (
    'bone-in turkey thigh',
    'turkey thigh meat only raw',
  ),
  'mexican-style chorizo sausage': (
    'mexican-style chorizo sausage',
    'sausage pork chorizo raw',
  ),
  'lump crabmeat': ('lump crabmeat', 'crab lump'),
  'jumbo lump crabmeat': ('jumbo lump crabmeat', 'crab lump'),
  'lump or backfin atlantic blue crabmeat': (
    'lump or backfin atlantic blue crabmeat',
    'crab lump',
  ),
  'collard greens': ('collard greens', 'collards raw'),
  'gai lan': ('gai lan', 'broccoli chinese raw'),
  'skinless red snapper fillets': (
    'skinless red snapper fillets',
    'snapper raw',
  ),
  'skin-on red snapper fillets': ('skin-on red snapper fillets', 'snapper raw'),
  '1-pound whole boneless shell sirloin steaks or whole flap meat steaks': (
    '1-pound whole boneless shell sirloin steaks or whole flap meat steaks',
    'beef top sirloin steak raw',
  ),
  'dried ladyfingers': ('dried ladyfingers', 'cookie ladyfinger'),
  'meaty smoked ham shank or 2 3 smoked ham hocks': (
    'meaty smoked ham shank or 2 3 smoked ham hocks',
    'pork ham hocks',
  ),
  'lightly with salt popcorn': ('lightly with salt popcorn', 'popcorn'),
  'frozen pea-carrot medley': (
    'frozen pea-carrot medley',
    'peas and carrots frozen',
  ),
  'medium-large onions': ('medium-large onions', 'onions'),
  'seven-grain hot cereal mix': ('seven-grain hot cereal mix', 'cereal'),
  'all-bran original cereal': ('all-bran original cereal', 'cereal bran'),
  'seltzer water': ('seltzer water', 'water carbonated'),
  'unflavored seltzer water or club soda': (
    'unflavored seltzer water or club soda',
    'water carbonated',
  ),
  'whole farro': ('whole farro', 'farro dry'),
  'pork tenderloin': (
    'pork tenderloin',
    'pork fresh loin tenderloin separable lean and fat raw',
  ),
  'pork tenderloins': (
    'pork tenderloins',
    'pork fresh loin tenderloin separable lean and fat raw',
  ),
  'chicken livers': ('chicken livers', 'chicken liver all classes raw'),
  'ground chicken': ('ground chicken', 'chicken ground raw'),
  'ground veal': ('ground veal', 'veal ground raw'),
  'hot italian sausage': ('hot italian sausage', 'sausage italian pork raw'),
  'dried black beans': ('black beans', 'beans black mature seeds raw'),
  'dried chickpeas': ('chickpeas', 'chickpeas mature seeds raw'),
  'dried white beans': ('navy beans', 'beans navy mature seeds raw'),
  'dried beans': ('navy beans', 'beans navy mature seeds raw'),
  'dried pinto beans': ('navy beans', 'beans navy mature seeds raw'),
  'coleslaw mix': ('red or green cabbage', 'cabbage raw'),
  // v30 (Q7, ruled 2026-10-01: meats and birds at gross weight, labelled
  // approximate): bone-in and whole cuts on their raw record, each the
  // named record of an answer snapshot 13 holds (q7_records.md
  // §AX_bone_in_parts). The weight stays the printed gross weight;
  // `buysRefuse` reads a published refuse yield (the Boston butt × 0.76) or
  // labels it approximate. Flagged approximations ([approximationRecords]):
  // flap meat → top sirloin, turkey drumsticks/thighs and leg quarters →
  // turkey thigh meat and skin.
  '7-pound first-cut beef standing rib roast': (
    'beef rib whole raw',
    'beef rib whole ribs 6-12 separable lean and fat trimmed to 1 8 fat '
        'choice raw',
  ),
  'first-cut beef standing rib roast': (
    'beef rib whole raw',
    'beef rib whole ribs 6-12 separable lean and fat trimmed to 1 8 fat '
        'choice raw',
  ),
  'beef flap meat': (
    'sirloin steak tips or boneless beef short ribs',
    'beef top sirloin steak raw',
  ),
  'beef rib slabs': (
    'baby back ribs',
    'beef rib back ribs bone-in separable lean and fat choice raw',
  ),
  'bone-in boston butt roast': (
    'boneless pork butt roast',
    'pork fresh shoulder boston butt blade steaks separable lean and fat raw',
  ),
  'boneless pork butt roast with at least 1 4-inch-thick fat cap': (
    'boneless pork butt roast',
    'pork fresh shoulder boston butt blade steaks separable lean and fat raw',
  ),
  'bone-in chicken parts': (
    'chicken broilers or fryers meat and skin raw',
    'chicken broilers or fryers meat and skin raw',
  ),
  'bone-in skin-on chicken parts': (
    'chicken broilers or fryers meat and skin raw',
    'chicken broilers or fryers meat and skin raw',
  ),
  // v32 (the live step, detail 168226 read 2026-10-03): its portions are
  // 4 oz 113 g, roast 3,868 g, lb 453.6 g — NO refuse yield, so under the
  // ruling the bone-in ham counts at its printed gross weight, labelled
  // approximate (roast-fresh-ham|0, 3,628.74 g).
  'bone-in half ham with skin': (
    'meaty smoked ham shank or 2 3 smoked ham hocks',
    'pork fresh leg ham shank half separable lean and fat raw',
  ),
  'boneless long-cut beef shanks': (
    'boneless long-cut beef shanks',
    'beef shank crosscuts separable lean only trimmed to 1 4 fat choice raw',
  ),
  'butterflied leg of lamb': (
    'shank end boneless leg of lamb',
    'lamb leg shank half separable lean and fat trimmed to 1 4 fat choice raw',
  ),
  'shank end boneless leg of lamb': (
    'shank end boneless leg of lamb',
    'lamb leg shank half separable lean and fat trimmed to 1 4 fat choice raw',
  ),
  'cod or other thick whitefish fillets': (
    'cod',
    'fish cod atlantic wild caught raw',
  ),
  'flat-iron steaks': (
    'flat-iron steaks',
    'beef chuck shoulder clod top blade steak separable lean and fat '
        'trimmed to 0 fat choice raw',
  ),
  'frozen butterball or kosher turkey': (
    'turkey whole meat and skin raw',
    'turkey whole meat and skin raw',
  ),
  // A search hit with no cached detail (the 14 other salmon lines count on
  // it): a weight line needs none.
  'salmon steaks': ('salmon steaks', 'fish salmon raw'),
  'skin-on side of salmon': ('salmon steaks', 'fish salmon raw'),
  'turkey drumsticks and thighs': (
    'bone-in turkey thighs',
    'turkey retail parts thigh meat and skin raw',
  ),
  'turkey leg quarters': (
    'bone-in turkey thighs',
    'turkey retail parts thigh meat and skin raw',
  ),
  // v32 (the live step, 2026-10-03): each target ranked first in an answer
  // snapshot 13 holds, enabled once its detail was read and its check held.
  // Leg quarters on the leg record (172378: leg with skin 344 g, drumstick
  // 111 g, thigh 185 g, back 49 g, 4 oz — no refuse yield, so the printed
  // gross weight, labelled approximate, under the ruling).
  'chicken leg quarters': (
    'chicken leg quarters',
    'chicken leg meat and skin raw',
  ),
  'bone-in chicken leg quarters': (
    'bone-in chicken leg quarters',
    'chicken leg meat and skin raw',
  ),
  // 175157 publishes a drained can (178 g) and 3 oz.
  'oil-packed tuna': ('oil-packed tuna', 'tuna white canned in oil drained'),
  // 171903 publishes "cup (8 fl oz)" 253 g.
  'sweetened cranberry juice': (
    'cranberries',
    'cranberry juice cocktail bottled',
  ),
  // 170002 (the dehydrated flakes the cached 'onions' answer names)
  // publishes tbsp 5 g and ¼ cup 14 g.
  'dried onions': ('onions', 'onions dehydrated flakes'),
  // NOT enabled: the singular portobello cap (detail 2003598) publishes
  // only a racc portion (85 g) — no per-cap portion, so "1 large
  // portobello mushroom cap" would gain no grams; the line stays in review.
  // 'portobello mushroom cap': ('portobello mushrooms', 'mushroom portabella'),
  // 168559 publishes cup 192 g, tbsp 12 g, slice, whole pimiento 66 g.
  'jarred pimentos': ('jarred pimentos', 'pimento canned'),
  // 169744 publishes cup 172 g; a flagged stand-in (khorasan for wheat
  // berries, [approximationRecords]).
  'cooked wheat berries': ('cooked wheat berries', 'wheat khorasan cooked'),
  // v31 (Q7, ruled 2026-10-03): the eight small groups, q7rules.py
  // verbatim (olives, sweet and fortified wines, extracts, chile powders,
  // Thai basil, meatloaf mix, fats, black vinegar) — each target named in an
  // answer snapshot 13 holds; a stand-in is flagged ([approximationRecords]).
  // Duck fat's confit line is a frying medium (engine.dart's
  // discardedMediumOf reads a `fat` head), never 1,230 g of it eaten.
  // olive
  'kalamata olives': ('oil-cured black olives', 'olives black'),
  'nicoise olives': ('oil-cured black olives', 'olives black'),
  // wine
  'ruby port': ('sherry', 'wine dessert sweet'),
  'cream sherry': ('sherry', 'wine dessert sweet'),
  'sweet marsala': ('sherry', 'wine dessert sweet'),
  'mirin or sweet sherry': ('sherry', 'wine dessert sweet'),
  'dry marsala': ('wine dessert dry', 'wine dessert dry'),
  'dry riesling': ('dry riesling', 'wine table white riesling'),
  'barolo wine': ('chianti', 'wine red'),
  'fluid ounces champagne': ('dry white wine', 'wine white'),
  'kirsch': ('brandy', 'brandy'),
  'peach schnapps': ('kirsch', 'liqueur'),
  // extract
  'almond extract': ('almond extract', 'vanilla extract'),
  'coconut extract': ('coconut extract', 'vanilla extract'),
  // chile
  'ancho chile powder': ('paprika', 'spices paprika'),
  'chipotle chile powder': (
    'spices pepper red cayenne',
    'spices pepper red or cayenne',
  ),
  'ground chipotle powder': (
    'spices pepper red cayenne',
    'spices pepper red or cayenne',
  ),
  'kashmiri chile powder': ('paprika', 'spices paprika'),
  'pul biber or ground dried aleppo pepper': ('paprika', 'spices paprika'),
  'aji amarillo chile paste': (
    'pickled jalapeno chiles',
    'sauce hot chile sriracha',
  ),
  // basil
  'thai basil leaves': ('basil leaves', 'basil raw'),
  'thai or italian basil leaves': ('basil leaves', 'basil raw'),
  // meatloaf
  'meatloaf mix': (
    '93 percent lean ground turkey',
    'beef ground 80 lean meat 20 fat raw',
  ),
  // fat
  'duck fat': ('duck fat', 'fat goose'),
  'chili oil': ('vegetable oil', 'vegetable oil nfs'),
  'vegetable oil more for cooking grate': (
    'vegetable oil',
    'vegetable oil nfs',
  ),
  // vinegar
  'chinese black vinegar': ('balsamic vinegar', 'vinegar balsamic'),
  // v31 (Q7): anchovy paste on its own line's record (2706232 "Fish,
  // anchovy"), weighed by ATK's printed equivalence (grams.dart, flagged).
  'anchovy paste': ('anchovy paste', 'fish anchovy'),
  // v31 (Q7 misc, ruled after every mapping was read, prep30/misc.md): the
  // planner's mappings; Cubanelle and the cornichon weigh their corpus
  // figure (grams.dart), instant espresso its siblings' 0.43 g/mL.
  'anaheim chiles': ('cubanelle peppers', 'pepper banana'),
  'angel hair pasta': ('pasta dry enriched', 'pasta dry enriched'),
  'asian chili-garlic paste': (
    'pickled jalapeno chiles',
    'sauce hot chile sriracha',
  ),
  'broccolini': ('broccoli', 'broccoli'),
  'candied yams': ('candied yams', 'yam raw'),
  'chicory or escarole': (
    'escarole',
    'escarole cooked boiled drained no salt added',
  ),
  'ciabatta': (
    'sprigs thai or italian basil',
    'bread italian grecian armenian',
  ),
  'ciabatta bread': (
    'sprigs thai or italian basil',
    'bread italian grecian armenian',
  ),
  'cornichons': ('spicy pickled radishes', 'pickles dill'),
  'crusty bread': (
    'sprigs thai or italian basil',
    'bread italian grecian armenian',
  ),
  'rustic crusty bread': (
    'sprigs thai or italian basil',
    'bread italian grecian armenian',
  ),
  'cubanelle peppers': ('cubanelle peppers', 'pepper banana'),
  'cubanelle pepper': ('cubanelle peppers', 'pepper banana'),
  'dried pappardelle': ('pasta dry enriched', 'pasta dry enriched'),
  'dried red beans': ('red kidney beans', 'beans kidney red mature seeds raw'),
  'frank s redhot original sauce': (
    'tabasco or other hot sauce',
    'hot pepper sauce',
  ),
  'fresno chiles': ('serrano or jalapeno chiles', 'peppers hot raw'),
  'gai choy': ('dry mustard', 'mustard greens'),
  'habanero chiles': ('serrano or jalapeno chiles', 'peppers hot raw'),
  'habanero chile': ('serrano or jalapeno chiles', 'peppers hot raw'),
  'instant espresso': (
    'instant espresso powder',
    'beverages coffee instant regular powder',
  ),
  'italian sub rolls': ('italian sub rolls', 'roll multigrain'),
  'jarred whole artichoke hearts in water': (
    'jarred whole artichoke hearts in water',
    'artichoke',
  ),
  'ketchup or chili sauce': ('ketchup', 'ketchup'),
  'lyle s golden syrup': ('light corn syrup', 'syrups corn light'),
  'mexican lager': ('beer', 'beer'),
  'mild-flavored lager': ('beer', 'beer'),
  'montasio or aged asiago cheese': ('parmesan cheese', 'parmesan cheese'),
  'new mexican pods': ('ancho pods', 'peppers ancho dried'),
  'ouzo': ('brandy', 'brandy'),
  'pastis or pernod': ('brandy', 'brandy'),
  'palm sugar': ('palm sugar', 'sugar brown'),
  'penne rigate': ('pasta dry enriched', 'pasta dry enriched'),
  'preserved lemon': ('lemon or lime wedges', 'lemon peel raw'),
  'radishes with their greens': ('radishes', 'radish'),
  'sweet onion or 2 shallots': ('sweet onion or 2 shallots', 'shallots raw'),
  'thai red chile': ('serrano or jalapeno chiles', 'peppers hot raw'),
  'thai with salt preserved radish': (
    'dill or sweet pickles',
    'radishes pickled',
  ),
  // The chili-garlic SAUCE read "Garlic sauce" (683 kcal); it reads the
  // paste's sriracha (171186, the cached 'pickled jalapeno chiles' answer).
  'asian chili-garlic sauce': (
    'pickled jalapeno chiles',
    'sauce hot chile sriracha',
  ),
  // v32 (the live step, 2026-10-03): low-fat sour cream on 173443 "Sour
  // cream, light" (the cached 'sour cream' answer ranks it first under these
  // words; its detail carries energy, 136 kcal, and tablespoon 12 g, cup
  // 230 g).
  'low-fat sour cream': ('sour cream', 'sour cream light'),
  // v32 (the live step's check M4, met: "a '1 …' piece portion", 4 × it a
  // plausible bun): brioche buns on 2707682 "Brioche" (ranked 0.99 in the
  // line's own cached answer), sized by the piece figure 'brioche bun' 77 g
  // read from that detail's "1 piece" (grams.dart: the finder alone reads
  // "piece" as a dish serving, so the rule needs the figure).
  'brioche buns': ('brioche buns', 'brioche'),
  // v32 (Q7 chorizo, the owner's decision 2026-10-03): FDC has no
  // dry-cured chorizo — the live step's 'chorizo pork and beef' search
  // returned two taco salads, and 'chorizo' only FNDDS "Chorizo" (2706179)
  // and the fresh SR pork links (173859 raw, 746781 cooked). Spanish-style
  // chorizo counts on the cured Italian pork salami the cached 'salami'
  // answer names (174603), flagged. Both chorizo answers stay cached,
  // unused. Linguiça on its exact class.
  'spanish-style chorizo': ('salami', 'salami italian pork'),
  'spanish-style chorizo sausage': ('salami', 'salami italian pork'),
  'linguica sausage': ('smoked sausage', 'sausage smoked link sausage pork'),
  // v31 (Q6 (d), ruled 2026-10-03): star anise on anise seed, a flagged
  // approximation — FDC has no star anise record; each line's own cached
  // answer names 171316 (q6 §2). The pod's weight is the piece table's
  // reference 0.5 g.
  'star anise pods': ('star anise pods', 'spices anise seed'),
  'star anise pod': ('star anise pod', 'spices anise seed'),
  // v22 (F10): "1 sugar cube" (Champagne Cocktail) led its own answer with
  // "Beef, steak, cube" at 160 g; it is granulated sugar. The record
  // publishes no cube portion, so the line stays in review with no grams.
  'sugar cube': ('sugar', 'sugars granulated'),
};

/// The (rank words, cached answer) a rank-as item reads ([_rankAs]), in
/// `lineSearchFor`'s shape; null for any other item.
({String query, String answer})? rankAsFor(String normalizedItem) {
  final entry = _rankAs[normalizedItem];
  return entry == null ? null : (query: entry.$2, answer: entry.$1);
}

/// The rank-as items ([_rankAs]), for the tests.
Iterable<String> get rankAsKeys => _rankAs.keys;

/// The first alternative of an "A or B" item (the second when A is a
/// [_standIns] substitute), searched alone in place of the whole phrase —
/// whose extra words empty FDC's strict search and pull the ranker's
/// coverage down ("brandy or dry sherry" matched Brandy at 0.10, "madeira
/// or dry sherry" matched dry lentils). Null when the item should be
/// searched as written.
///
/// Narrow on purpose: A must already be a known query — [isCached] (a stored
/// FDC answer) or a rewrite phrase. And a one-word A before a longer B is
/// usually an adjective sharing B's noun ("green or brown lentils", "chicken or
/// vegetable broth", "light or dark brown sugar": 'chicken', 'dark' and
/// 'light' are all cached queries), so it splits only when the rewrite table
/// names it — a key or a target, i.e. a food noun ("brandy", "calvados",
/// "parsley").
String? leftAlternative(
  String normalizedItem,
  bool Function(String query) isCached,
) {
  final words = normalizedItem.split(' ');
  final or = words.indexOf('or');
  if (or < 1 || or == words.length - 1) {
    return null;
  }
  final left = words.sublist(0, or).join(' ');
  // A stand-in is the last resort, never the line's food: "dry vermouth or
  // dry white wine" is the white wine FDC knows (B, under the same test).
  if (_standIns.contains(left)) {
    final right = words.sublist(or + 1).join(' ');
    return _queryRewrites.containsKey(right) || isCached(right) ? right : null;
  }
  final rewrite =
      _queryRewrites.containsKey(left) || _queryRewrites.containsValue(left);
  // An animal is a rewrite key ('chicken' is the whole bird) but before a
  // longer B it is the adjective: "chicken or vegetable broth"; so are
  // 'dill' ("dill or sweet pickles") and 'dark' ("dark or light brown
  // sugar", "bittersweet or semisweet chocolate").
  // A second "or" makes a list of foods, never an adjective: "crushed
  // saltines (about 16) or quick oatmeal or 1⅓ cups fresh bread crumbs"
  // (Meatloaf with Brown Sugar-Ketchup Glaze, 0306) is the saltines, which
  // read 192 g of dry bread crumbs by the salt density (Run 045) — but an
  // animal or an adjective stays one before a list too: "chicken or beef or
  // vegetable broth" is broth, never a raw whole chicken (Run 047).
  if (or == 1 &&
      words.length - or - 1 > 1 &&
      (_animals.contains(left) ||
          _adjectiveKeys.contains(left) ||
          (!rewrite && !words.skip(or + 1).contains('or')))) {
    return null;
  }
  return rewrite || isCached(left) ? left : null;
}

/// Rewrite keys that are also adjectives before a longer alternative.
const Set<String> _adjectiveKeys = {'dill', 'dark'};

/// Rewrite keys whose target is a SUBSTITUTE for a food FDC has no record
/// of (vermouth reads as the dry sherry target): the key alone searches it,
/// but an "A or B" line takes B.
const Set<String> _standIns = {'vermouth', 'dry vermouth'};

/// A ranked candidate.
class RankedCandidate {
  /// Pairs a candidate with its score.
  const RankedCandidate({
    required this.candidate,
    required this.confidence,
    this.docked = false,
  });

  /// The FDC search hit.
  final FdcCandidate candidate;

  /// 0–1; ≥ 0.75 reads as high, ≥ 0.5 medium, else low.
  final double confidence;

  /// Whether the ranker docked this record as a wrong food — no head noun,
  /// a dish/composite/analog, a brand, another animal. The engine's
  /// macro-complete fallback never steps down to such a record: "Black bean
  /// salad" (#2) counted for black beans because #1 lacked macros.
  final bool docked;
}

/// The ranker's stem of [word] — both the query's and every record's words
/// go through it. "-es" comes off only after s, x, ch, sh or o (peaches,
/// radishes, tomatoes, mixes; 'cheeses' stems 'chees', which keeps "Classic
/// Grilled Cheese Sandwiches" off a seven-layer salad); any other plural
/// loses its "s" alone — a z too: 'glazes' is 'glaze', not 'glaz' (v13
/// refix 2: no corpus line has a "-zes" plural to earn the strip); the
/// "-es" rule stemmed 'whites' to 'whit' against the record's 'white', and
/// 26 "egg whites" lines sat at 0.415 on the right record (checkpoint 7).
String _singular(String word) {
  if (word.length > 3 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.length > 3 && RegExp(r'(s|x|ch|sh|o)es$').hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.length > 2 && word.endsWith('s')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// "93 percent lean" as FDC writes it ("93% lean"): the split kept {93,
/// percent} against the record's {93%}, so the fat level never matched and
/// the Foundation 80/20 record won (audit 1: 5 lines).
final RegExp _percent = RegExp(r'(\d+) percent\b');

Set<String> _tokens(String text) => {
  for (final word
      in text
          .toLowerCase()
          .replaceAllMapped(_percent, (m) => '${m[1]}%')
          .split(RegExp('[^a-z0-9%]+')))
    if (word.length > 1) _singular(word),
};

/// Description tokens that mark a MODIFIED form of a food — penalized
/// unless the query itself asks for them, so "large eggs" prefers
/// "egg, whole" over "egg white", and "espresso powder" prefers regular
/// coffee over decaffeinated.
const Set<String> _modifiedFormTokens = {
  'low',
  'light',
  'white',
  'yolk',
  'decaffeinated',
  'dried',
  'dehydrated',
  'powdered',
  'canned',
  'frozen',
  'cooked',
  'roasted',
  'toasted',
  'sweetened',
  'fat-free',
  // "2 percent milk" is fluid milk: evaporated 2% out-scored it on the SR
  // nudge once the fat level matched (sweep accuracy batch).
  'evaporated',
  'kippered',
  'smoked',
  'nonfat',
  'lowfat',
  'reduced',
  // Prepared-product forms: recipes call for the ingredient, not the
  // ready-to-drink/ready-to-pour product built from it.
  'beverage',
  'mix',
  'syrup',
  'drink',
  'prepared',
  // "Rice, white, long-grain, precooked or instant" took 'long-grain or
  // basmati rice' once brown was docked (audit 4).
  'instant',
};

/// Added meat qualifiers a generic query didn't ask for: "sausage"/"bacon"
/// default to pork, not "Sausage, turkey" / "Bacon, turkey"; a deli/luncheon
/// cut is not the raw ingredient ("chicken breast" wants the raw cut, not
/// "Lunchmeat, chicken breast"). Query-gated, so "turkey bacon"/"chicken
/// sausage"/"deli ham" still match. ("bits" is deliberately NOT here:
/// penalizing it surfaced Canadian bacon — leaner and further from real bacon
/// than the crumbled-bacon "Bacon bits".)
///
/// Docked HARDER than a plain off-form ([_modifiedFormTokens], -0.06): the
/// wrong MEAT is a bigger error than the wrong cook-state, and at -0.06 it lost
/// to it — "breakfast sausage" matched a raw TURKEY link (which also took the
/// +0.02 raw-form bonus) over the real pre-COOKED beef breakfast sausage
/// (docked -0.06 for "cooked"). The species dock must outweigh that ~0.08 form
/// swing so meat type wins. Still light enough that a turkey/chicken match with
/// no better option merely falls toward the review gate, not off a cliff.
const Set<String> _offMeatTokens = {
  'turkey',
  'chicken',
  'lunchmeat',
  'luncheon',
  'deli',
  'blood',
};

/// A food processed into a DIFFERENT staple — "almonds" is not "almond FLOUR",
/// "Dijon mustard" is not "mustard OIL", "rice" is not "rice FLOUR". A base-
/// form change is a much bigger error than an off-form ([_modifiedFormTokens]),
/// so it takes a heavier penalty — enough to reliably demote it below the whole
/// food. Applied only when the query itself did not ask for the form.
const Set<String> _baseFormChangeTokens = {
  // "Prune puree" out-ranked the dried prunes once 'prunes' stemmed to
  // 'prune' (v12, 3 lines; 2 counted 96 g for 58 g).
  'puree',
  'flour',
  'oil',
  'juice',
  'sauce',
  'paste',
  'meal',
  'butter',
};

/// Reconstitutable-concentrate markers. A bouillon CUBE, broth GRANULE, or
/// juice CONCENTRATE is a fundamentally different food from the ready-to-use
/// liquid a recipe asks for — and because grams are then estimated from the
/// recipe's VOLUME, matching "8 cups chicken broth" to dry cubes overstates
/// calories 10-50×. So a candidate whose description carries one of these takes
/// the heavy base-form-class penalty, unless the query itself names the form
/// ("beef bouillon" still matches bouillon).
///
/// Matched as SUBSTRINGS, not tokens, on purpose: the ranker's plural stemmer
/// mangles the very words at issue ("cubes" → "cub", "granules" → "granul"), so
/// a token-set check would silently miss them. Substrings also fold the
/// singular/plural/-ed variants (cube/cubes/cubed) into one marker.
///
/// Deliberately excludes dry/dried/powder/powdered/condensed/instant: those
/// correctly describe foods that ONLY exist concentrated (cocoa powder,
/// gelatin, dry milk, condensed milk), and penalizing them would sink the one
/// correct match below the review gate. The distinction rides on these narrow
/// reconstitution nouns, not on "dry".
const Set<String> _concentrateMarkers = {
  'cube',
  'bouillon',
  'concentrate',
  'granule',
};

/// Meat-analog markers. An IMITATION/vegetarian version is a fundamentally
/// different food from the meat a recipe asks for ("Bacon, meatless" is soy;
/// "Hot dog, vegetarian" is not a beef frank). Whole-word, query-gated, so a
/// query that itself names the analog ("vegetarian sausage") still matches it.
const Set<String> _meatAnalogMarkers = {
  'meatless',
  'vegetarian',
  'vegan',
  'imitation',
  'substitute',
  'analog',
  'analogue',
};

/// Prepared-dish / composite markers. A raw ingredient must not match a
/// finished dish or beverage built from it ("ginger" → "Tea, ginger",
/// "shrimp" → "Shrimp cocktail", "chicken" → "Chicken cacciatore"). Whole-word
/// and query-gated ("curry powder", "shrimp salad" still match).
///
/// Deliberately EXCLUDES words that FDC also uses to file real INGREDIENTS,
/// found by an adversarial live-FDC sweep:
///  - `soup`/`salad` — broths are "Soup, X broth", mayo is "Salad dressing";
///  - `pie` — "Pie crust" covers graham-cracker/cookie crusts and tart shells;
///  - `wonton` — "Wonton wrappers" is FDC's entry for egg-roll/gyoza wrappers;
///  - `dip` — tzatziki/queso/baba ganoush are filed "X dip";
///  - `sandwich` — sandwich cookies (Oreos) are "Cookies, sandwich";
///  - `adobo` — "chipotle in adobo" is a common ingredient.
/// (`tea` is kept: ginger→"Tea, ginger" is common and correctable to Ginger
/// root; the rare matcha/hibiscus whose ONLY match is tea-filed just fall to
/// the review gate — an honest gap, not a wrong number.)
const Set<String> _dishMarkers = {
  'cocktail',
  'scampi',
  'fajita',
  'teriyaki',
  'creole',
  'stroganoff',
  'croquette',
  'burrito',
  'quesadilla',
  'enchilada',
  'tamale',
  'risotto',
  'pilaf',
  'quiche',
  'souffle',
  'frittata',
  'omelet',
  'cacciatore',
  'parmigiana',
  'scallopini',
  'marsala',
  'gratin',
  'tempura',
  'lasagna',
  'tea',
  'pizza',
  'taco',
  'gumbo',
  'chowder',
  'bisque',
  'casserole',
  'stew',
  'curry',
  'pudding',
  'toast',
  'chips',
  'nugget',
  'fritter',
  'dumpling',
  'paella',
  'jambalaya',
  // A "... breakfast biscuit" is a sandwich, not the meat: "breakfast sausage"
  // otherwise matched "Sausage, egg and cheese breakfast biscuit" over the real
  // sausage. Query-gated, so a recipe that asks for "biscuit(s)" still matches.
  'biscuit',
  // "Lomi salmon" is a Hawaiian salmon-and-tomato salad: it tied "Fish,
  // salmon, raw" on coverage and won on precision for skinless salmon
  // fillets once 'skinless' was credited (checkpoint 6). ("Salmon salad",
  // the next tie, is a salad NAMED for the food: [rankCandidates].)
  'lomi',
};

/// USER ANSWER #6 SWITCH (variety dock). True (the recommended default)
/// docks a record [_varietyDock] for each variety word the query does not
/// name, so an unqualified 'onion'/'carrot' takes the generic or yellow/
/// mature record: Foundation's +0.10 nudge made "Onions, red, raw" beat
/// "Onions, raw" (audit 1: onion→red 94, carrot→baby 53, cremini→beech 8).
/// Known cost: 4 cherry-tomato lines fall from roma (0.53) into check and
/// 'long-grain or basmati rice' moves to instant rice. False turns it off.
const bool varietyDockOn = true;

/// Variety words a generic ingredient does not mean. 'yellow' is left out:
/// it sent cornmeal to "Cornmeal, blue (Navajo)". 'imported': "Beef,
/// Australian, imported, grass-fed, ground, 85% lean" beat the generic 85%
/// record for '85 percent lean ground beef' (audit 4: 13 lines).
/// ('australian' too moved only two lamb lines' scores.)
const Set<String> _varietyWords = {
  'red',
  'baby',
  'brown',
  'roma',
  'beech',
  'imported',
};

/// The variety a food means unqualified, never docked: rice is white rice
/// (checkpoint 5: 0005, 0062 and 0709 counted brown rice).
const Map<String, String> _defaultVariety = {'rice': 'white'};

/// The variety dock: small, a tiebreak between records of the same food.
const double _varietyDock = 0.03;

/// Legumes FDC files dry, raw, NFS and canned apart.
const Set<String> _legumes = {'bean', 'chickpea', 'lentil', 'pea', 'garbanzo'};

/// Whether [raw], a line of the legume [normalizedItem], names a can or jar:
/// the canned record's word ([rankCandidates]). Legumes only — on every can
/// line it sent canned pumpkin puree to "Tomato, puree, canned" and jarred
/// baby food, pistachios and artichoke hearts into check (replay).
bool namesCannedLegume(String raw, String normalizedItem) =>
    normalizedItem
        .split(' or ')
        .any((item) => _legumes.contains(headNounOf(item))) &&
    RegExp(r'\b(cans?|canned|jars?|jarred)\b').hasMatch(raw.toLowerCase());

/// Whether a bone-in bird cut is skin-on though the line does
/// not say so — how it is sold unless skinned. "1 (6- to 7-pound) whole
/// bone-in turkey breast" read FDC's class word 'whole' in "Turkey, whole,
/// breast, meat only, raw" over "…breast, meat and skin, raw" (audit 3, A9:
/// 2 lines, 6,350 g). A named cut only: mixed "chicken parts"/"pieces"
/// then ranked a cooked "NS as to part, rotisserie" record into the totals.
bool impliesSkinOn(String raw, String normalizedItem) =>
    normalizedItem.contains('bone-in') &&
    _birdCuts.contains(headNounOf(normalizedItem)) &&
    !removesSkin(raw);

/// Whether [raw] says the skin comes off ("4 whole chicken legs, separated
/// into drumsticks and thighs and skin removed"): [rankCandidates] docks a
/// "meat and skin" record for it.
bool removesSkin(String raw) => RegExp(
  'skinless|skinned|skin removed|without skin|remove(d)? (the )?skin',
).hasMatch(raw.toLowerCase());

/// The bird cuts sold skin-on: [impliesSkinOn]. ponytail: no bone-in veal
/// breast or lamb leg is in the corpus; gate on the animal if one appears.
const Set<String> _birdCuts = {'breast', 'thigh', 'leg', 'drumstick', 'wing'};

/// A cooking a record was analysed after, docked when the line names none:
/// 40 counted lines took a cooked record for a raw one ("tri-tip … cooked,
/// broiled", "country-style ribs … broiled", beans "from dried, fat
/// added"; audit 3, N2). 'cooked' itself is a modified form already.
/// ('braised' was here: it changed no line of the library, audit 4 P9.)
const Set<String> _cookStateTokens = {'broiled', 'roasted'};

/// FNDDS's own cook state: "Cornish game hen, cooked, skin eaten" (audit 4:
/// 3 hens counted at 2,722 g each on it), "Escarole, cooked". An SR or
/// branded "pre-cooked" sausage is a product form, not a cooking.
const String _fnddsCooked = 'cooked';

/// Words that say the line's food is already cooked.
const Set<String> _cookingWords = {
  'cooked',
  'broiled',
  'braised',
  'roasted',
  'grilled',
  'baked',
  'fried',
  'boiled',
  'steamed',
  'poached',
  'smoked',
  'toasted',
  'stewed',
  'sauteed',
  'seared',
  'rotisserie',
  'leftover',
  'barbecued',
};

/// The cook-state dock.
const double _cookStateDock = 0.10;

/// Description tokens for the plain/whole form — a small tiebreak bonus.
const Set<String> _plainFormTokens = {'whole', 'raw', 'regular'};

/// Whole words of [text], lowercased, no stemming — for marker sets that must
/// match "tea" without also matching "steak" (a substring check would).
Set<String> _words(String text) =>
    text.toLowerCase().split(RegExp('[^a-z]+')).toSet();

/// Words that say how an ingredient comes, never what it is. Dropped when
/// looking for the head noun. The conjunctions are here because
/// 'half-and-half' would otherwise have the head 'and' (21 corpus lines).
const Set<String> _formWords = {
  'ground',
  'whole',
  'dry',
  'dried',
  'fresh',
  'frozen',
  'ripe',
  'firm',
  'mild',
  'large',
  'small',
  'medium',
  'chopped',
  'and',
  'or',
  'plus',
  // Prepositions a hyphen split leaves behind ('bone-in' → 'in').
  'in',
  'on',
  'with',
  'without',
  // Measurement units a trailing "or ¼ teaspoon dried" leaves as the last
  // word (14 corpus lines).
  'teaspoon',
  'teaspoons',
  'tablespoon',
  'tablespoons',
  'cup',
  'cups',
  'ounce',
  'ounces',
  'pound',
  'pounds',
  'inch',
  'inches',
  'quart',
  'quarts',
  'pint',
  'pints',
  // FDC's own form words, met on REWRITTEN queries ('shrimp raw', 'pasta
  // dry enriched', 'wine dessert dry', 'pork cured bacon unprepared').
  'raw',
  'enriched',
  'prepared',
  'unprepared',
  'cured',
  'dessert',
};

/// Count nouns, BOTH numbers: 'garlic clove' and 'garlic cloves' must both
/// give the head 'garlic' (a plural-only list docked 'Garlic, raw' on 93
/// corpus lines).
const Set<String> _countNouns = {
  'leaf',
  'leaves',
  'wedge',
  'wedges',
  'clove',
  'cloves',
  'sprig',
  'sprigs',
  'stalk',
  'stalks',
  'fillet',
  'fillets',
  'piece',
  'pieces',
  'half',
  'halves',
  'slice',
  'slices',
  'stick',
  'sticks',
  'head',
  'heads',
  'ear',
  'ears',
  'bunch',
  'bunches',
  // "cardamom pods": the head is the spice (checkpoint 5: 'pod' was the
  // head, and "Drumstick pods" won the cardamom line). (Singular 'pod'
  // moved only a confidence that stays in check, refix round 1.)
  'pods',
};

/// Whether [word] counts pieces of a food ('sprig', 'leaves', 'cloves')
/// rather than naming one.
bool isCountNoun(String word) => _countNouns.contains(word);

/// Compound identities whose LAST word names the form: 'anchovy paste',
/// 'celery root', 'tomato sauce' — the head is the word before.
const Set<String> _identityTails = {
  'paste',
  'sauce',
  'root',
  'dough',
  'zest',
  'thread',
  'threads',
  'mix',
  'spray',
  // Rewritten spice queries: 'cumin seeds' names cumin.
  'seed',
  'seeds',
  // 'romaine heart' is romaine, not the organ "Heart" (audit 1); artichoke
  // hearts and hearts of palm name the plant the same way.
  'heart',
  'hearts',
  // 'crab meat', 'beef flap meat': the word before names the food. As the
  // head, 'meat' let "Meat loaf made with beef" count for flap meat.
  'meat',
};

/// The corpus says chile; FDC says pepper.
const Map<String, String> _headSynonyms = {
  'chile': 'pepper',
  'chili': 'pepper',
  'chily': 'pepper',
};

Set<String> _keyTokens(String text) => {
  for (final word in text.toLowerCase().split(RegExp('[^a-z0-9%]+')))
    if (word.length > 1) _keyWord(word),
};

/// Whether [description] carries [head]. The key stemmer turns 'cookies'
/// into 'cooky' but leaves 'cookie' alone, so an -ies head also matches its
/// -ie spelling (cookies/cookie, brownies/brownie). A negated head does not
/// count: "Chili hot dog, no bun" is not a bun.
bool _carriesHead(String description, String head) {
  // A dish names the ingredient after "with" ("Soup, vegetable with beef
  // broth"): only the words before it name the record's own food (audit 1:
  // 34 lines, none right lost). (" on " was cut too; it changed no line of
  // the library, audit 4 P9.)
  var own = description.toLowerCase();
  final at = own.indexOf(' with ');
  if (at > 0) {
    own = own.substring(0, at);
  }
  final words = [
    for (final word in own.split(RegExp('[^a-z0-9%]+')))
      if (word.length > 1) _keyWord(word),
  ];
  final ie = head.endsWith('y')
      ? '${head.substring(0, head.length - 1)}ie'
      : head;
  for (var i = 0; i < words.length; i++) {
    if (words[i] != head && words[i] != ie) {
      continue;
    }
    if (i > 0 && (words[i - 1] == 'no' || words[i - 1] == 'without')) {
      continue;
    }
    return true;
  }
  return false;
}

/// Whether [description] is the LEAVES of [head] ("Sweet potato leaves,
/// raw") on a line that does not ask for leaves: the plant, not the food.
bool _leavesOf(String description, String head, String queryLower) {
  if (RegExp(r'\blea(f|ves)\b').hasMatch(queryLower)) {
    return false;
  }
  final words = description.toLowerCase().split(RegExp('[^a-z0-9%]+'));
  for (var i = 0; i + 1 < words.length; i++) {
    if (_keyWord(words[i]) == head &&
        (words[i + 1] == 'leaves' || words[i + 1] == 'leaf')) {
      return true;
    }
  }
  return false;
}

/// The word that names the food in [query] (the FDC search query), in its
/// key form — or null when nothing identifies one. A trailing " for …"
/// clause and an "or … recipe …" cross-reference are cut (never a plain
/// "or": 'instant or rapid-rise yeast' needs its last alternative); form,
/// prep and stop words and count nouns are dropped; the last survivor is
/// the head, stepping back over an identity tail ('anchovy paste' →
/// anchovy). A modified-form word ('yolk', 'white') is never the identity.
///
/// Measured over all 13,614 corpus lines (design review D4): 484 distinct
/// heads, 261 lines with none; the risky heads a literal "last token" rule
/// produced (paste 106, chil 48, whit 29, and 21, lim 8) all go to zero.
String? headNounOf(String query) {
  var text = query;
  // A trailing purpose: "table salt for cooking pasta".
  final purpose = text.indexOf(' for ');
  if (purpose > 0) {
    text = text.substring(0, purpose);
  }
  final parts = text.split(' or ');
  while (parts.length > 1 && parts.last.contains('recipe')) {
    parts.removeLast();
  }
  text = parts.join(' or ');
  final words = text.split(RegExp('[^a-z0-9%]+'));
  final kept = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    // "with skin", "without salt": the preposition and its object are how
    // the food comes, never the food ('ham with skin'; 'thai with salt
    // preserved radish' — normalizeItem spells "salted" that way).
    if (w == 'with' || w == 'without') {
      i++;
      continue;
    }
    if (w.length < 2 ||
        _formWords.contains(w) ||
        _prepWords.contains(w) ||
        _stopWords.contains(w)) {
      continue;
    }
    // 'rib' counts celery (72 corpus lines); on a cut it IS the food
    // ('short ribs', 'country-style pork ribs', 'baby back ribs' — 25).
    final celeryRib =
        (w == 'rib' || w == 'ribs') && i > 0 && words[i - 1] == 'celery';
    if (_countNouns.contains(w) || celeryRib) {
      continue;
    }
    kept.add(w);
  }
  if (kept.isEmpty) {
    return null;
  }
  // The last survivor names the food — stepping back over a form tail
  // ('anchovy paste' → anchovy) and over a modified-form word when a food
  // word precedes it ('spices pepper white' → pepper; 'egg yolk' → egg).
  // A lone modified-form word ('yolks') names no identity.
  while (kept.length > 1 &&
      (_identityTails.contains(kept.last) ||
          _modifiedFormTokens.contains(_keyWord(kept.last)))) {
    kept.removeLast();
  }
  final head = _keyWord(kept.last);
  if (_modifiedFormTokens.contains(head)) {
    return null;
  }
  return _headSynonyms[head] ?? head;
}

/// Whether any of [candidates] names the ingredient's head noun. False means
/// the search answer holds no record of the food at all — a list that is
/// hopeless, not mis-ranked (37 of 878 diagnostic lines): the sheet says so
/// instead of offering the top junk record.
bool candidatesNameIngredient(String query, List<FdcCandidate> candidates) {
  final head = headNounOf(query);
  if (head == null) {
    return true;
  }
  return candidates.any((c) => _carriesHead(c.description, head));
}

/// Composite records — a dish or a product built from the food, never the
/// food. Only the markers MEASURED to change a chosen food on the 878-line
/// diagnostic set, both numbers (the older dish list is unstemmed, which is
/// why 'nugget' never docked "chicken nuggets"). Not 'bits' (FDC files
/// Canadian bacon under it), not 'pie'/'cookie' (they would dock "Pie
/// Crust, Cookie-type, Graham Cracker" — pinned).
const Set<String> _compositeMarkers = {
  'sandwich',
  'sandwiches',
  'cake',
  'cakes',
  'roll',
  'rolls',
  'bun',
  'buns',
  'nugget',
  'nuggets',
  'mock',
  'dressing',
  'dressings',
  'topping',
  'toppings',
  'candy',
  'candies',
  // Products built from the food (audit 1): "Baby Toddler prunes",
  // "Babyfood, juice, orange", "Sweet potato tots", "Mint julep".
  'toddler',
  'babyfood',
  'tots',
  'julep',
  // "Sweet Potato puffs, frozen" (refix round 2, beside the tots).
  'puffs',
  // "Refried beans, canned (pinto)" out-ranked the canned pinto beans once a
  // can on the line named 'canned' (audit 3, N1).
  'refried',
  // "Turkey and gravy, frozen" counted 9,979 g for a whole frozen turkey
  // (0155) once the connectors stopped costing it precision (refix round 1).
  'gravy',
  // "Olive tapenade" took 4 niçoise olive lines from "Olives, black" once
  // 'olives' stemmed to 'olive' (v12).
  'tapenade',
  // A food coated in the line's food is a product of it: "Pretzels, hard,
  // white chocolate coated" ranked 0.87 over "Candies, white chocolate" for
  // '6 ounces white chocolate' (Triple-Chocolate Mousse Cake), and a
  // chocolate-coated granola bar 0.87 for milk chocolate chips (v13; no
  // other cached top pick moves).
  'coated',
};

/// FDC's class first segments ([rankCandidates]): a filing, not the food.
const Set<String> _classSegments = {'spices', 'beverages'};

const List<String> _compositePhrases = [
  'school lunch',
  'with meat',
  // A traditional food of one programme: "Caribou, bone marrow, raw (Alaska
  // Native)" counted 680 g for "1½ pounds marrow bones" once 'bones' stemmed
  // to 'bone' (v12); "…salmon, king, with skin, kippered, (Alaska Native)"
  // held 9 skin-on salmon lines.
  'alaska native',
];

/// "not sweetened": the word after "not" is what the record is NOT.
final RegExp _negated = RegExp(r'\bnot\s+([a-z0-9%]+)');

/// Animals a record is filed under. A query that names one never wants a
/// record that names only a different one: 'turkey drumsticks and thighs'
/// counted 3,629 g of "Chicken, skin (drumsticks and thighs)" at 0.54. In
/// the ranker's token form (`_tokens` stems plurals).
const Set<String> _animals = {
  'chicken',
  'turkey',
  'beef',
  'pork',
  'lamb',
  'veal',
  'duck',
  'salmon',
  'tuna',
  'cod',
  'halibut',
  'trout',
  'tilapia',
  'haddock',
  'swordfish',
  'catfish',
  'anchovy',
};

/// The species-mismatch dock: a wrong animal is a wrong food, and it must
/// outweigh a shared cut word ('thigh', 'roast', 'tip'). Measured (audit 1,
/// P8 replay): exactly the 2 turkey drumstick/thigh lines left counted.
const double _speciesDock = 0.30;

/// The dock for a boneless record on a bone-in line (or a meat-only one on a
/// bone-in or skin-on line): the off-meat magnitude — the right animal, the
/// wrong cut.
const double _cutDock = 0.12;

/// The dock for a wrong-food record (analog, dish, composite): −0.25 left
/// "School Lunch, chicken nuggets" counted for 'whole chicken' at 0.627;
/// −0.40 puts it at 0.477. Measured: only those lines differ.
const double _wrongFoodDock = 0.40;

/// A token FDC writes with three or more capitals in a row is a brand
/// (SWANSON, POPEYES, REAL LEMON — and McDONALD'S, McFLURRY, whose lowercase
/// 'c' defeated an all-caps rule) unless the query names it. "USDA's" is a
/// programme note and NFS/NS are "not further specified", never brands.
final RegExp _brandToken = RegExp("[A-Za-z'&-]*[A-Z]{3,}[A-Za-z'&-]*");
const Set<String> _notBrands = {'NFS', 'NS'};

/// The brand tokens of [description] the query [queryLower] does not name.
List<String> brandTokensOf(String description, {String queryLower = ''}) => [
  for (final m in _brandToken.allMatches(description))
    if (!m[0]!.startsWith('USDA') &&
        !_notBrands.contains(m[0]) &&
        !queryLower.contains(m[0]!.toLowerCase()))
      m[0]!,
];

/// USER ANSWER #5 SWITCH (dried-for-fresh). Dropping count nouns from the
/// ranker's query ([rankCandidates]) also lifts a DRIED herb record over the
/// gate for a fresh line — 'oregano leaves' → "Spices, oregano, dried" (11
/// lines in audit 1: oregano 4, sage 4, tarragon 2, marjoram 1). False (the
/// default until the user answers) keeps the count noun in the query for a
/// dried record the line does not ask for, so those lines stay in `check`,
/// and the engine holds any fresh line an engine pick put on a dried or
/// ground spice ([driedForFresh], `hold: dried_for_fresh`) — 'fresh oregano'
/// keys 'oregano', has no count noun, and A5's portion density would count
/// it on the dried record (25 lines, audit 3). True accepts both.
const bool allowDriedForFresh = false;

/// Whether [raw] asks for a fresh herb and [description] is a dried or
/// ground spice record: '1 tablespoon minced fresh oregano' on "Spices,
/// oregano, dried", 'fresh sage' on "Spices, sage, ground". A line that
/// also offers the dried form ("1 tablespoon minced fresh oregano or 1
/// teaspoon dried") is held too: counting the FRESH amount on the dried
/// record sized it three times over (albóndigas, refix). Not "fresh grated
/// nutmeg" or "fresh ground pepper" — there the ground spice is the food.
/// A cured meat is the same mistake: "bone-in fresh half ham with skin"
/// (0249) scored exactly 0.50 on "Pork, cured, ham, rump, …" (audit 4).
bool driedForFresh(String raw, String description) =>
    freshHoldOf(raw, description) != null;

/// The hold [driedForFresh] puts on a fresh line: `cured_for_fresh` for a
/// cured record (a preserved meat — the 0249 fresh ham), `dried_for_fresh`
/// for a dried or ground one; null when the line is not fresh or the record
/// is (checkpoint 5: the ham was held under the herb's label).
String? freshHoldOf(String raw, String description) {
  final record = description.toLowerCase();
  if (!_asksFresh(raw)) {
    return null;
  }
  if (record.contains(RegExp(r'\bcured\b'))) {
    return 'cured_for_fresh';
  }
  if (freshHerbOnSpiceRecord(description)) {
    return null;
  }
  return record.contains(RegExp(r'\bdried\b')) ||
          (record.startsWith('spices,') &&
              record.contains(RegExp(r'\bground\b')))
      ? 'dried_for_fresh'
      : null;
}

/// Whether [raw] asks for a fresh food: "fresh", not "fresh grated" or
/// "fresh ground" (there the ground spice is the food).
bool _asksFresh(String raw) =>
    RegExp(r'\bfresh\b(?!\s+(grated|ground))').hasMatch(raw.toLowerCase());

/// The flagged APPROXIMATIONS the user accepted (docs/API.md): each
/// approximation rewrite's or rank-as item's normalized item
/// ([_queryRewrites], [_rankAs]) → the record
/// that rewrite's answer leads to (snapshot 11, every such line): pancetta
/// counted as bacon, Asiago as Parmesan, whole allspice berries as ground
/// allspice, lime zest as lemon peel, chen pi as orange peel, pepperoncini
/// as "Peppers, hot, pickled". A line on another record (a person's pick of
/// another record, "pancetta or bacon", which reads the whole phrase) is not
/// one; a person's confirm or pick of THIS record is — the record relation
/// is the approximation, whoever chose it (Run 046).
const Map<String, int> approximationRecords = {
  'pancetta': 168277,
  'asiago cheese': 325036,
  'allspice berries': 171315,
  'whole allspice berries': 171315,
  'lime zest': 167749,
  'chen pi': 169103,
  'pepperoncini': 2710095,
  // v21 (J2/J5, approved as a group — each line is one veto): pinto, small
  // white and unnamed dried beans as navy beans, spicy greens as arugula
  // (the first green the line names), All-Bran as bran flakes, seven-grain
  // hot cereal as whole wheat hot cereal, fingerlings as red potatoes,
  // tapioca starch on the tapioca-pearl cup.
  'dried pinto beans': 173745,
  'dried beans': 173745,
  'dried white beans': 173745,
  'spicy greens': 169387,
  'all-bran original cereal': 2708456,
  'seven-grain hot cereal mix': 171667,
  'fingerling potatoes': 2346402,
  'tapioca starch': 169717,
  // v30 (Q7 bone-in parts, ruled): flap meat (bottom sirloin) as top
  // sirloin; turkey drumsticks and thighs, and leg quarters, as turkey thigh
  // meat and skin (the leg record 171493 has no cached detail).
  'beef flap meat': 2727574,
  'turkey drumsticks and thighs': 171533,
  'turkey leg quarters': 171533,
  // v32 (the live step: detail 169744 read, cup 172 g): cooked wheat
  // berries as cooked khorasan wheat.
  'cooked wheat berries': 169744,
  // v31 (Q7 groups, misc, anchovy paste, chorizo; ruled 2026-10-03).
  'kalamata olives': 2710090,
  'nicoise olives': 2710090,
  'ruby port': 2710692,
  'cream sherry': 2710692,
  'sweet marsala': 2710692,
  'mirin or sweet sherry': 2710692,
  'dry marsala': 175112,
  'fluid ounces champagne': 2710689,
  'kirsch': 2710699,
  'peach schnapps': 2710623,
  'almond extract': 173471,
  'coconut extract': 173471,
  'ancho chile powder': 171329,
  'chipotle chile powder': 170932,
  'ground chipotle powder': 170932,
  'kashmiri chile powder': 171329,
  'pul biber or ground dried aleppo pepper': 171329,
  'aji amarillo chile paste': 171186,
  'thai basil leaves': 2709780,
  'thai or italian basil leaves': 2709780,
  'meatloaf mix': 2514744,
  'duck fat': 173572,
  'chili oil': 2710180,
  'chinese black vinegar': 172241,
  'anchovy paste': 2706232,
  'anaheim chiles': 169394,
  'asian chili-garlic paste': 171186,
  'broccolini': 747447,
  'candied yams': 170071,
  'chicory or escarole': 168413,
  'cornichons': 2710078,
  'cubanelle peppers': 169394,
  'cubanelle pepper': 169394,
  'dried red beans': 173744,
  'italian sub rolls': 2707782,
  'jarred whole artichoke hearts in water': 2709766,
  'lyle s golden syrup': 168837,
  'montasio or aged asiago cheese': 325036,
  'new mexican pods': 169396,
  'ouzo': 2710699,
  'pastis or pernod': 2710699,
  'palm sugar': 2710260,
  'preserved lemon': 167749,
  'thai with salt preserved radish': 2710099,
  'asian chili-garlic sauce': 171186,
  'spanish-style chorizo': 174603,
  'spanish-style chorizo sausage': 174603,
  // v31 (Q6 (d)): star anise counted as anise seed.
  'star anise pods': 171316,
  'star anise pod': 171316,
};

/// Whether the food [fdcId] ([description]) on the line [raw], whose
/// normalized item is [item], is a flagged approximation: the record an
/// approximation rewrite led to ([approximationRecords]), or a fresh herb
/// line on its dried spice record ([freshHerbOnSpiceRecord]). The matches
/// body's `gram_basis` says the first as "· approximation (counted as …)";
/// a fresh herb's basis says "· approximate (dried herb record for a fresh
/// herb)" instead (`gramBasisFor` reads it first).
bool isApproximation({
  required String item,
  required String raw,
  required int? fdcId,
  required String? description,
}) =>
    fdcId != null &&
    (approximationRecords[item] == fdcId ||
        (description != null && freshHerbLine(raw, description)));

/// Whether the line [raw] asks for a fresh herb and [description] is that
/// herb's dried spice record ([freshHerbOnSpiceRecord]): the engine sizes
/// the line as the user ruled on 2026-09-28 (Q2) and its basis says "·
/// approximate (dried herb record for a fresh herb)".
bool freshHerbLine(String raw, String description) =>
    _asksFresh(raw) && freshHerbOnSpiceRecord(description);

/// Fresh herbs FDC has no fresh record of — no cached answer holds one
/// (snapshot 11: every answer for oregano, sage, tarragon, marjoram and
/// chervil, 'leaves' or not, holds only the "Spices," record).
const Set<String> _herbsWithoutFreshRecord = {
  'oregano',
  'sage',
  'tarragon',
  'marjoram',
  'chervil',
};

/// Whether [description] is the "Spices, X, dried" (or ground) record of a
/// herb in [_herbsWithoutFreshRecord] — the only records any cached answer
/// files such a herb second in (so reading the class and the form changed
/// no line of the library: removed, v13 refix). A fresh line of one COUNTS
/// on it: a flagged APPROXIMATION the user ruled on 2026-09-28 (docs/API.md)
/// — the dried leaf is several times as nutrient-dense per gram as the
/// fresh one, and the fresh volume is sized by the dried record's own
/// portions (a sprig 0 g, a leaf count no grams). A line offering the dried
/// form ("1 tablespoon minced fresh oregano or 1 teaspoon dried",
/// albóndigas) is never held either. v12 held 57 such rows `dried_for_fresh`.
bool freshHerbOnSpiceRecord(String description) {
  final segments = description.toLowerCase().split(',');
  return segments.length > 1 &&
      _herbsWithoutFreshRecord.contains(segments[1].trim());
}

/// The query tokens a candidate is scored against: [tokens] less its count
/// nouns (and 'rib' after celery) when another token remains. A count noun
/// is how the food is counted, never the food, yet it cost the coverage of
/// every record — "Thyme, fresh" scored 0.48 for 'thyme leaves' and 'lemon
/// wedges' held "Lemon, raw" at 0.49 (audit 2: 199 right check lines).
///
/// A fish fillet keeps 'fillet' when the line names no species ('white fish
/// fillets'): without it 'white' alone lifted "Fish, sucker, white, raw" —
/// one freshwater species — from check to counted (2 lines, refix round 2).
///
/// Nor may the cap leave only a dish word: 'curry leaves' as 'curry' scored
/// every curry dish 0.89 (audit 4). ('half' stays a count noun: kept, it
/// sent breast halves and spiral-sliced half hams to check; the fresh half
/// ham it lifted onto a cured record is held by [driedForFresh].)
///
/// A count noun that IS an alternative's food stays: the spice of "ground
/// cloves or allspice" (0241), whose 'ground cloves' names nothing else
/// ([headNounOf] finds no head in it). Dropped, the whole phrase covered
/// allspice fully and counted the second alternative (checkpoint 5 review,
/// once 'or' stopped costing coverage).
Set<String> _countedTokens(Set<String> tokens, String query) {
  final named = {
    for (final alternative in query.split(' or '))
      if (alternative.contains(' ') && headNounOf(alternative) == null)
        ..._tokens(alternative),
  };
  final drop = {
    for (final noun in _countNouns)
      if (!named.contains(_singular(noun))) _singular(noun),
    if (tokens.contains('celery')) 'rib',
  };
  if (tokens.contains('fish')) {
    drop.remove(_singular('fillet'));
  }
  final kept = tokens.difference(drop);
  final dishOnly = kept.every(
    (token) => _dishMarkers.any((marker) => _singular(marker) == token),
  );
  // An empty set is dish-only too: a query of count nouns alone ("3 cloves",
  // typed) keeps its tokens — the coverage would divide by zero.
  return dishOnly ? tokens : kept;
}

/// USER QUESTION SWITCH (connector tokens, checkpoint 5 — measured apart).
/// True (the audit's recommendation) drops 'or' and 'and' from the query's
/// and every record's tokens: 'or' capped every "A or B" line and credited
/// FDC's own "X or Y" descriptions ("canola or vegetable oil" counted a
/// Spanish rice mix "…canola/vegetable oil blend or…"), and the 'and' of
/// "lean and fat" cost that record precision against "lean only" (68 lines
/// flip to lean and fat — the user may veto that list). False scores them
/// as words, as before.
const bool connectorTokensDropped = true;

/// The connector words [connectorTokensDropped] drops.
const Set<String> _connectorTokens = {'or', 'and'};

/// Coverage-only synonyms, in the ranker's stem form: the corpus's word
/// covers the one FDC files it under. (A 'chil' entry for the old stem of
/// 'chiles' went with it: v12 stems the plural to 'chile'.)
/// ('chili' and 'chily' were measured too: neither moved a recorded answer
/// of the library, so they are not here.)
/// Measured on the checkpoint-5 gate band: 45 right chile lines sat at
/// 0.495, and lemon zest scored "Lemon, raw" over "Lemon peel, raw".
/// (cremini → crimini was measured too: it raised 19 counted cremini lines
/// from 0.525 to 0.95 and moved no food, bucket or gram, so it is not here.)
const Map<String, String> _coverageSynonyms = {
  'chile': 'pepper',
  'zest': 'peel',
  // V8 is FDC's "Tomato and vegetable juice, 100%": once 'juices' stemmed
  // to 'juice' (v12), "Beverages, V8 V-FUSION Juices, Tropical" took the two
  // V8 juice lines (0028, 0286) at 0.48 with no grams.
  'v8': 'vegetable',
};

/// Qualifiers FDC's ground-spice records never carry ("Spices, paprika" is
/// sweet, smoked or hot): not counted against a 'Spices,' record. Never
/// globally — smoked is a fish's identity, sweet a potato's. ('hungarian'
/// and 'spanish' moved no recorded answer of the library.)
final Set<String> _spiceQualifiers = {
  for (final word in const ['smoked', 'sweet', 'ground', 'hot'])
    _singular(word),
};

/// Variety and descriptor words no FDC record of the food carries, measured
/// one at a time on the gate band with 0 wrong lines counted: not counted
/// against coverage when uncovered and not the head ('red plums' is plums).
/// 'skinless' (checkpoint 6) only once "Lomi salmon" is a dish
/// ([_dishMarkers]); not 'whole' (it moved egg yolks).
final Set<String> _noCreditWords = {
  for (final word in const [
    'skinless',
    'english',
    'plum',
    'slivered',
    'thread',
    'pecorino',
    'littleneck',
    'ripe',
    'prewashed',
    'mcintosh',
    'pearl',
    'seedless',
    'unseasoned',
  ])
    _singular(word),
};

/// The [_noCreditWords] that name a VARIETY of the food: credited only on a
/// record that names no variety of its own — every word it adds is plain
/// ([_plainVarietyTokens]). FDC files Fuji and Gala apples but no McIntosh:
/// 'mcintosh' left the denominator of "Apples, fuji, with skin, raw" too,
/// and 1005's McIntosh apples counted as Fuji at 0.91 (checkpoint 5
/// review).
final Set<String> _noCreditVarieties = {
  for (final word in const ['mcintosh', 'english', 'littleneck'])
    _singular(word),
};

/// The words a record may add and still name no variety of its own.
final Set<String> _plainVarietyTokens = {
  for (final word in const [
    ..._plainFormTokens,
    'with',
    'without',
    'skin',
    'peel',
    'peeled',
    'fresh',
    'nfs',
  ])
    _singular(word),
};

/// The words of a HOT pepper record, which alone take the chile → pepper
/// credit ([_coverageSynonyms]): FNDDS files sweet bell peppers without
/// 'sweet' — "Peppers, red, cooked" (2709977) took the credit over "Peppers,
/// hot chile, sun-dried" for a Thai red chile (0551, 0053, 0523, 0547;
/// checkpoint 5 review).
final Set<String> _hotPepperTokens = {
  for (final word in const [
    'hot',
    'chili',
    'chile',
    'chilies',
    'chiles',
    'jalapeno',
    'jalapenos',
    'serrano',
    'poblano',
    'ancho',
    'chipotle',
    'habanero',
    'cayenne',
    'guajillo',
    'pasilla',
    'arbol',
  ])
    _singular(word),
};

/// The comma segments of [description], lowercased.
Iterable<String> _segments(String description) =>
    description.toLowerCase().split(',').map((segment) => segment.trim());

/// The cut an imported record names: its first segment after 'imported'
/// that is not a descriptor ("Lamb, New Zealand, imported, fore-shank, …" →
/// 'fore-shank'). 'imported' is docked only when a domestic record in the
/// same answer files that cut: the 85% ground beef has one, but no domestic
/// fore-shank exists, and the dock sent 1192's lamb shanks to a leg roast
/// (checkpoint 5).
String? _importedCut(String description) {
  final segments = _segments(description).toList();
  final at = segments.indexOf('imported');
  for (final segment in at < 0 ? const <String>[] : segments.skip(at + 1)) {
    if (!const {'grass-fed', 'fresh', 'frozen'}.contains(segment)) {
      return segment;
    }
  }
  return null;
}

/// Ranks [candidates] against the normalized [query].
///
/// Score = token overlap between the query and the candidate description
/// (how much of the query the description covers, discounted by how much
/// extra specificity the description adds), plus a data-type nudge
/// (Foundation is the highest-quality analysis set), a full-coverage
/// bonus, and modified-form tiebreaks (see [_modifiedFormTokens]).
List<RankedCandidate> rankCandidates(
  String query,
  List<FdcCandidate> candidates, {
  bool canned = false,
  bool skinOn = false,
  bool skinless = false,
  bool dropConnectors = connectorTokensDropped,
}) {
  Set<String> tokensOf(String text) => dropConnectors
      ? _tokens(text).difference(_connectorTokens)
      : _tokens(text);
  // A can or jar on the line is the canned record's word, ranked but never
  // searched: 7 canned-bean lines counted dry or raw beans (audit 3, N1).
  // A bone-in bird cut is sold skin-on ([impliesSkinOn]), ranked the same way.
  final allTokens = {
    ...tokensOf(query),
    if (canned) 'canned',
    if (skinOn) 'skin',
  };
  final cooked = allTokens.any(_cookingWords.contains);
  if (allTokens.isEmpty || candidates.isEmpty) {
    return const [];
  }
  final countedTokens = _countedTokens(allTokens, query);
  final head = headNounOf(query);
  final queryWords = _words(query);
  // The cuts some record files WITHOUT 'imported' ([_importedCut]).
  final domesticSegments = {
    for (final candidate in candidates)
      if (!_tokens(candidate.description).contains('imported'))
        ..._segments(candidate.description),
  };
  // Whether some record files the head in its FIRST segment ("Oysters,
  // raw"): then a [_varietyHosts] record naming it only later is a variety
  // of the host food, not the food.
  final headFiledFirst =
      head != null &&
      candidates.any(
        (c) => _keyTokens(c.description.split(',').first).contains(head),
      );
  final ranked = <RankedCandidate>[];
  for (final candidate in candidates) {
    final descriptionTokens = tokensOf(candidate.description);
    if (descriptionTokens.isEmpty) {
      continue;
    }
    // A fresh herb FDC has no fresh record of counts on its dried spice
    // ([freshHerbOnSpiceRecord]): its count noun goes, as for any record.
    final queryTokens =
        !allowDriedForFresh &&
            descriptionTokens.contains('dried') &&
            !allTokens.contains('dried') &&
            !freshHerbOnSpiceRecord(candidate.description)
        ? allTokens
        : countedTokens;
    // A negated word covers nothing the query names: "…dried (desiccated),
    // not sweetened" counted for 'sweetened coconut'. It still weighs on
    // precision, so a record gains nothing from what it is not.
    final negated = {
      for (final match in _negated.allMatches(
        candidate.description.toLowerCase(),
      ))
        _singular(match[1]!),
    };
    // FDC's "Spices," and "Beverages," are its classes, not the food: once
    // v12 stemmed them 'spice' and 'beverage' (not 'spic', 'beverag'), the
    // class covered "five-spice powder" ("Spices, chili powder" counted for
    // it, 10 lines) and took the ready-to-drink dock ([_modifiedFormTokens])
    // on "Beverages, coffee, instant, regular, powder". A later segment's
    // word ("Spices, pumpkin pie spice") is the food's own, and a query
    // naming the class ('spices pepper black', a rewrite target) keeps it.
    final segments = candidate.description.toLowerCase().split(',');
    final first = segments.first.trim();
    final classWord =
        _classSegments.contains(first) &&
            !queryWords.contains(first) &&
            !_tokens(segments.skip(1).join(',')).contains(_singular(first))
        ? _singular(first)
        : null;
    final own = descriptionTokens.difference({...negated, ?classWord});
    // Coverage credits (checkpoint 5): a word FDC files under another word
    // covers it ([_coverageSynonyms]); a word no record of the food carries
    // leaves the denominator when uncovered and not the head — a qualifier
    // on a 'Spices,' record ([_spiceQualifiers]) or a variety or descriptor
    // word ([_noCreditWords]). Precision stays the LITERAL overlap.
    // A sweet record takes no synonym credit — a sweet pepper is no chile:
    // the credit lifted "whole dried red chile" onto "Peppers, sweet, red,
    // freeze-dried" (0525, 0545; judged wrong). The chile credit goes to a
    // hot pepper record only: FNDDS's sweet bell peppers do not say sweet.
    bool synonymCovers(String token) {
      final synonym = _coverageSynonyms[token];
      return synonym != null &&
          own.contains(synonym) &&
          !own.contains('sweet') &&
          (synonym != 'pepper' || own.any(_hotPepperTokens.contains));
    }

    final covered = {
      for (final token in queryTokens)
        if (own.contains(token) || synonymCovers(token)) token,
    };
    final spice = candidate.description.toLowerCase().startsWith('spices,');
    // A credited word leaves the denominator only of a record of the food:
    // one that carries the head ("Tofu, raw, firm" covered 'firm' of 'firm
    // mcintosh apples' and overtook "Apple, raw", checkpoint 5 review) — and,
    // for a variety word, names no variety of its own.
    final ofTheFood =
        covered.isNotEmpty &&
        (head == null || _carriesHead(candidate.description, head));
    final ownVariety = own.any(
      (token) =>
          !queryTokens.contains(token) &&
          token != head &&
          !_plainVarietyTokens.contains(token),
    );
    // Nor on a line that names no species ('skinless white fish fillets':
    // 'white' alone covers "Fish, sucker, white, raw"), as for 'fillet'
    // ([_countedTokens]).
    final uncredited = !ofTheFood || head == 'fish'
        ? 0
        : queryTokens
              .where(
                (token) =>
                    !covered.contains(token) &&
                    token != head &&
                    ((_noCreditWords.contains(token) &&
                            !(ownVariety &&
                                _noCreditVarieties.contains(token))) ||
                        (spice && _spiceQualifiers.contains(token))),
              )
              .length;
    final coverage = covered.length / (queryTokens.length - uncredited);
    final precision =
        queryTokens.intersection(own).length / descriptionTokens.length;
    var score = 0.65 * coverage + 0.2 * precision;
    if (coverage == 1) {
      score += 0.1;
    }
    score += switch (candidate.dataType) {
      'Foundation' => 0.1,
      'SR Legacy' => 0.05,
      // FNDDS values are recipe-CALCULATED, not directly analyzed, so it sits
      // just below SR Legacy for raw single ingredients — but it's the right
      // (and often only) layer for cooked/composite lines ("chicken broth",
      // "escarole, cooked"), so it wins there on the name match alone.
      'Survey (FNDDS)' => 0.04,
      _ => 0.0,
    };
    for (final token in descriptionTokens) {
      if (queryTokens.contains(token) || token == classWord) {
        continue;
      }
      if (_baseFormChangeTokens.contains(token)) {
        score -= 0.25;
      } else if (_offMeatTokens.contains(token)) {
        score -= 0.12;
      } else if (_modifiedFormTokens.contains(token) &&
          // 'white' is an egg's part; on rice, onions or cornmeal it is a
          // variety ([_varietyDock] below): as a modified form it sent '1
          // cup long-grain rice' (0005) to brown rice (checkpoint 5).
          (token != 'white' || descriptionTokens.contains('egg'))) {
        score -= 0.06;
      }
    }
    // An unasked 'liquid' docks as a modified form only as the record's own
    // FORM, a description segment of its own: "Baking chocolate,
    // unsweetened, liquid" (472 kcal) tied the squares (642) at 0.90 under
    // 'unsweetened chocolate' and won (10 lines, v17). Never FDC's canned
    // wording, "solids and liquids" or "(liquid expressed …)".
    if (!queryTokens.contains('liquid') &&
        candidate.description
            .toLowerCase()
            .split(',')
            .any((segment) => segment.trim() == 'liquid')) {
      score -= 0.06;
    }
    // Reconstitutable-concentrate penalty (substring, query-gated). One dock is
    // enough — "bouillon cubes" is a single concept, not two errors.
    final descriptionLower = candidate.description.toLowerCase();
    final queryLower = query.toLowerCase();
    for (final marker in _concentrateMarkers) {
      if (descriptionLower.contains(marker) && !queryLower.contains(marker)) {
        score -= 0.25;
        break;
      }
    }
    // Meat-analog / prepared-dish penalty (whole-word, query-gated). A recipe's
    // raw ingredient is not a soy analog or a finished dish built from it. One
    // dock, base-form magnitude — a wrong food, not a modified form.
    final descriptionWords = _words(candidate.description);
    // 'sandwich' never docks a sandwich COOKIE: FDC files Oreos as
    // "Cookie, chocolate sandwich" (recorded 2026-09-08).
    final cookieRecord =
        descriptionWords.contains('cookie') ||
        descriptionWords.contains('cookies');
    // A marker the query itself names (any number: 'buns' names 'bun') is
    // the food, not a dish — and FDC files buns under "Rolls, hamburger…",
    // so bun and roll gate each other.
    final queryKeys = _keyTokens(query);
    bool queryNames(String marker) {
      final key = _keyWord(marker);
      if (queryWords.contains(marker) || queryKeys.contains(key)) {
        return true;
      }
      // 'carrot baby food' names FDC's "Babyfood, …" and "Baby Toddler …".
      if ((key == 'babyfood' || key == 'toddler') &&
          queryLower.contains('baby food')) {
        return true;
      }
      return (key == 'bun' && queryKeys.contains('roll')) ||
          (key == 'roll' && queryKeys.contains('bun'));
    }

    final wrongFood =
        _meatAnalogMarkers
            .followedBy(_dishMarkers)
            .followedBy(_compositeMarkers)
            .any(
              (marker) =>
                  descriptionWords.contains(marker) &&
                  !queryNames(marker) &&
                  !(cookieRecord && marker.startsWith('sandwich')),
            ) ||
        _compositePhrases.any(
          (phrase) =>
              descriptionLower.contains(phrase) && !queryLower.contains(phrase),
        ) ||
        // A salad named for the food — "Salmon salad", "Egg salad" — is a
        // dish of it; 'salad' alone is no marker ("Salad dressing,
        // mayonnaise" is mayonnaise). (Sparing a query that says 'salad'
        // changed no recorded answer: removed, refix round 2.)
        (head != null &&
            RegExp(
              '\\b${RegExp.escape(head)}s? salad\\b',
            ).hasMatch(descriptionLower));
    var docked = wrongFood;
    if (wrongFood) {
      score -= _wrongFoodDock;
    }
    if (descriptionTokens.any(_plainFormTokens.contains)) {
      score += 0.02;
    }
    // "Dry roasted" is how nuts are sold, not a cooking the line skipped.
    if (!cooked &&
        !RegExp('dry[- ]roasted').hasMatch(descriptionLower) &&
        (descriptionTokens.any(_cookStateTokens.contains) ||
            (candidate.dataType == 'Survey (FNDDS)' &&
                descriptionTokens.contains(_fnddsCooked)) ||
            descriptionLower.contains('from dried'))) {
      score -= _cookStateDock;
    }
    if (varietyDockOn) {
      for (final token in descriptionTokens) {
        if ((_varietyWords.contains(token) ||
                (token == 'white' && !descriptionTokens.contains('egg'))) &&
            !queryTokens.contains(token) &&
            _defaultVariety[head] != token &&
            (token != 'imported' ||
                domesticSegments.contains(
                  _importedCut(candidate.description),
                ))) {
          score -= _varietyDock;
        }
      }
    }
    // A bone-in cut is not the boneless record: the ranker read 'bone-in'
    // as the form word 'in', so "Chicken, thigh, boneless, skinless, raw"
    // counted for bone-in thighs (audit 1: 7 lines). "Meat only" is neither
    // bone-in nor skin-on: 2 whole bone-in turkey breasts (6,350 g) counted
    // on "Turkey, whole, breast, meat only, raw" (audit 3, A9). (A skin-on
    // line on a skinless record changed no line of the library, audit 4.)
    if ((queryLower.contains('bone-in') &&
            descriptionWords.contains('boneless')) ||
        ((queryLower.contains('bone-in') || queryLower.contains('skin-on')) &&
            !skinless &&
            descriptionLower.contains('meat only')) ||
        // A skinned line is not "meat and skin" ([removesSkin]): once the
        // connectors stopped costing precision, "whole chicken legs … skin
        // removed" (0150) tied with and took the skin-on leg (refix round 1).
        // A line that names the skin ("skin-on thighs, … skin removed",
        // 0461) keeps its skin-on pick.
        (skinless &&
            !allTokens.contains('skin') &&
            descriptionLower.contains('meat and skin'))) {
      score -= _cutDock;
    }
    final queryAnimals = queryTokens.intersection(_animals);
    if (queryAnimals.isNotEmpty &&
        descriptionTokens.intersection(queryAnimals).isEmpty &&
        descriptionTokens.any(_animals.contains)) {
      score -= _speciesDock;
      docked = true;
    }
    // The ingredient's head noun must be in the record. Docked uniformly
    // even when NO candidate carries it: that is exactly what stops 156 g of
    // "Lentils, dry" counting for 'dry sherry'. Never excludes a candidate —
    // the sheet still shows the top one, held in `check`.
    if (head != null &&
        (!_carriesHead(candidate.description, head) ||
            _leavesOf(candidate.description, head, queryLower) ||
            _hostVariety(candidate.description, head, headFiledFirst))) {
      score -= 0.30;
      docked = true;
    }
    // A brand the query did not name — a wrong food's worth: at −0.25 a
    // McFlurry "with OREO cookies" still counted at 0.63 for 'oreo cookies'.
    // Safe only WITH the head-noun dock: alone it handed "Soup, SWANSON,
    // beef broth" to a beef-and-mushroom soup.
    if (brandTokensOf(
      candidate.description,
      queryLower: queryLower,
    ).isNotEmpty) {
      score -= _wrongFoodDock;
      docked = true;
    }
    ranked.add(
      RankedCandidate(
        candidate: candidate,
        confidence: score.clamp(0.0, 1.0),
        docked: docked,
      ),
    );
  }
  // Two kinds of exact tie are broken toward the plainer record: the cut's
  // lean-and-fat record over "lean only" (the user's default for an
  // unqualified cut — 6 country-style rib lines tie 167895 with 168305 at
  // 0.5214, above the gate), and the record naming fewer cookings
  // ("Kielbasa, fully cooked, unheated" over
  // "…, grilled" at 0.79, 3 lines). v11, both fleets. Any other exact tie
  // still falls to FDC's order: 310 of the 1,818 cached
  // answers change their top pick when reversed ("bell pepper" green or
  // yellow at 0.97), a known ceiling. (Sparing a line that says "lean" or
  // names a cooking from either tie-break moved no line of the library and
  // no top pick of the recorded answers but the unsearched "90 percent lean
  // ground sirloin": removed, refix round 2.)
  int tieRank(RankedCandidate r) {
    final words = _words(r.candidate.description);
    return (words.contains('only') && words.contains('lean') ? 1 : 0) +
        words.where(_cookingWords.contains).length;
  }

  ranked.sort((a, b) {
    final byScore = b.confidence.compareTo(a.confidence);
    return byScore != 0 ? byScore : tieRank(a).compareTo(tieRank(b));
  });
  return ranked;
}

/// Foods FDC files varieties of under a food noun of their own: "Mushroom,
/// oyster" and "Mushroom, king oyster" are mushrooms. '24 oysters …' (1184,
/// Roasted Oysters on the Half Shell) ranked "Mushroom, oyster" 0.95 over
/// "Oysters, raw" 0.91 (v12 review, both fleets: the v12 entry claimed this
/// dock but never wrote it). A general rule — any record whose first
/// segment is another noun — moved other cached top picks; this set moves
/// only the oysters answer's (measured on the 1,859 answers of snapshot 11).
const Set<String> _varietyHosts = {'mushroom'};

/// Whether [description] is a [_varietyHosts] record ("Mushroom, oyster")
/// naming [head] only past its first segment while another record of the
/// answer files [head] first ([headFiledFirst]).
bool _hostVariety(String description, String head, bool headFiledFirst) {
  if (!headFiledFirst) {
    return false;
  }
  final first = _keyTokens(description.split(',').first);
  return first.any(_varietyHosts.contains) && !first.contains(head);
}

/// Words a macro-complete record lower in the ranking may add to the top
/// pick and still be the same food: a form, never another food.
///
/// ('regular', 'whole', 'plain' and 'dry' were here too: none changed a line
/// of the library, audit 4 P9.)
const Set<String> _fallbackFormTokens = {'nfs', 'raw', 'mature', 'seed'};

/// Whether [candidate] may stand in for the top pick [top] (which lacks
/// macros) on [query]: every word it adds beyond the top pick and the query
/// is a form word. The docked flag caught none of the 11 wrong stand-ins
/// ("Cabbage, napa, cooked", "Black bean salad", "Watermelon, rind") — none
/// was docked (audit 3).
bool sameFoodAsTop(String query, String top, String candidate) {
  // FDC's parentheticals are notes ("(Includes foods for USDA's Food
  // Distribution Program)", "(0% moisture)"), not the food.
  String own(String text) => text.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  return _tokens(own(candidate))
      .difference(_tokens(own(top)))
      .difference(_tokens(query))
      .every(
        (token) => _fallbackFormTokens.any((form) => _singular(form) == token),
      );
}

/// The rewrite table's keys. Every key must be a normalized item exactly as
/// [normalizeItem] produces it — a key the normalizer would rewrite first is
/// dead (pinned by a test): 'crushed red pepper' once sat in the table while
/// the line normalized to 'red pepper' and searched the vegetable.
Iterable<String> get queryRewriteKeys => _queryRewrites.keys;
