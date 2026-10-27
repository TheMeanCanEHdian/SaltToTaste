# Matcher version history (v1–v78)

Moved verbatim from the `///` doc comment on `matcherVersion` in
`apps/server/lib/src/nutrition/matcher.dart` in R4 of the simplification
series on 2026-10-27 (ledger item L8-1, the owner's Q3 ruling); only the
`/// ` prefix was removed. The numbers are `matcherVersion` values; entries
v47–v78 name the commit that shipped them (e.g. "v78 (the Matcher v81
commit …)"), v1–v46 name none. This file is closed: new history goes to
docs/API.md's "matcher vNN" sections, never here.

History: 1 = everything before 2026-09-07; 2 = diacritics folded, canned
crushed/diced tomatoes keep their form word, singular decision keys;
3 = the ranker requires the ingredient's head noun, docks composite and
branded records harder, 'juice from 1 lemon' normalizes to 'lemon juice',
and the rewrite table gained the spice/bacon/shrimp/sherry/beer/mustard/
pasta entries (design review D4, measured on the 2026-09-08 diagnostic
set: 19 of 31 confidently wrong foods fixed, 0 correct lines regressed);
4 = a second amount left in the item ("plus 2 tablespoons …", "or ¼
teaspoon dried") is dropped from the query and the key, equipment lines
are zeros, and the engine searches a cached "A or B" alternative alone and
reads a same-key sibling's cached answer (sweep audit, 2026-09-26);
5 = "A or <amount> B" keeps B (only the amount goes), a leading amount
before "juice from N lemons" no longer eats the juice, an empty cached
answer for A no longer splits "A or B", and a rewritten line never reads
its key-form sibling (sweep-batch review, 2026-09-26);
6 = the accuracy batch (sweep audits 1 and 2, 2026-09-26): whole-bird,
dish, product and kind-word rewrites, a species/variety/cut dock, count
nouns out of the ranker's coverage, the head noun read before "with"/
"on", "N percent" as "N%", an "A or B" split only on an answer naming A
(a stand-in A takes B), a negated word ("not sweetened") covers nothing,
and a lower record replaces the top pick for its macros only as the same
food in another form; audit 3 (ACCURACY-2) added a can on a legume line,
a cook-state and a meat-only dock, compound-head and kind-word rewrites,
and keys a line naming a second food apart — all within version 6;
7 = audit 4 and the v6 review (2026-09-27): chicken pieces, instant
yeast, Cornish hens, cherry tomatoes and curing salt rewritten, the
unsweetened-coconut target names "not sweetened", imported as a variety
word, 'cooked' as a cook state, instant as a modified form, "loosely
packed" drops the adverb, an oven bag is equipment, the
count-noun cap never leaves only a dish word, a cured meat for a fresh
line is held as dried-for-fresh, a lone qualifier reads on until a
segment names a food, and a second food's key comes from each part with
its amounts cut;
8 = checkpoint 5 (2026-09-27): coverage-only credits (chile→pepper,
zest→peel, spice qualifiers, descriptor words) with
literal precision, 'or'/'and' out of the ranker (switch), 'imported'
docked only beside a domestic record of its cut, 'white' docked only on
an egg, pods as count nouns, a dropped
word's leaked connector/measure cut from the key, prep-only comma
segments dropped, egg and citrus second-food keys tidied, and rewrites
for desiccated coconut, pancetta, panko, stout, madeira, tubetti, mezze
rigatoni, sukang maasim and cherry tomatoes;
9 = checkpoint 5 review (2026-09-27): a credited word leaves the
denominator only of a record carrying the head (a variety word only of
one naming no variety), the chile credit only on a hot pepper record, a
count noun that is an alternative's food kept, identity participles kept
in a comma-listed food, "3 or 4 limes" moved to the front, a fruitless
zest-plus-juice item keyed by the line's fruit, and egg-part keys food
first;
10 = checkpoint 6 (2026-09-27): a bare 'zest'/'peel' item searches and
keys the line's fruit ("1 (2-inch) strip zest from 1 lemon" is 'lemon
zest'), 'skinless' credited (not on a line that names no species) with
"Lomi salmon" and a salad named for the food ("Salmon salad") docked as
dishes, and rewrites for country-style ribs (to the raw record),
gorgonzola, arborio, 90% lean ground sirloin, andouille, kielbasa
sausage, the flagged asiago and allspice-berry approximations, and lime
zest (a bare 'peel' item is left alone: no line of the library is one —
this entry said it took the fruit too, corrected in v11);
11 = checkpoint 6 review (2026-09-28): a lean-only/lean-and-fat tie
goes to the lean-and-fat record and a cooked/uncooked one to the record
naming fewer cookings (other exact ties still follow FDC's order); lime zest
searches as lemon zest, "Lemon peel, raw" (a flagged approximation); the
water and dissolve rules read the recipe's own steps only, a dissolve
needs the salt as its object and a submerge, a bare "salt" in cooking
water is the one salt line no step names with its amount, a held
medium's eaten "plus" part is its grams; an amount-less line in the
shell is held (shell-on shrimp the line peels stays held: weighed with
its shells); the
staleness hash reads the steps and the title;
12 = checkpoint 7 (2026-09-28): the ranker strips "-es" only after s,
ch, sh or o ('whites' is 'white', not 'whit'), with the class word
"Spices," covering nothing, "puree" a base-form change, an "Alaska
Native" record docked and V8 covered by "vegetable"; "1 dozen" read as 12
and keyed without 'dozen'; a dangling "and" cut from a split line; the
segments before the food in "medium, firm, ripe tomatoes" read past,
'firm' dropped; rewrites for the shrimp size words, skin-on salmon,
pepperoncini, juice oranges, ripe avocado and bananas, chen pi (a flagged
approximation) and the halibut lines (pending one live search);
13 = the checkpoint-7 review and the user's rulings of 2026-09-28: the
oyster-mushroom dock written ([_varietyHosts]), "-es" off after x too (a
z loses its "s" alone — this entry said "and z", corrected in v14), a
dangling "or" cut like "and", a coated record a composite, fresh
oregano, sage, tarragon, marjoram and chervil counted on their dried
spice (a flagged approximation), and rewrites for center-cut skin-on
salmon and white chocolate chips; with it the engine's sub-recipe lines
(0 g, no food), the R2 held and R3 zeroed media and the below-gate sized
twin re-resolve every computed recipe;
14 = the Run 045 review, checkpoint 8 and the user's rulings Q1–Q4 of
2026-09-28: a second "or" makes a list of foods ("crushed saltines … or
quick oatmeal or … bread crumbs" is the saltines); with it the engine
rewrites its own rule rows, gates every write path by the sub-recipe
rule (a "1 recipe" line is one whatever its mark; a single-food "1
recipe X" counts its yield; a sub-recipe's eaten "plus" part counts), a
cheesecloth-bundled brine aromatic is zero, a skimmer leaves no liquid
the pot simmered dry or keeps, and a held medium stores only its eaten
part as grams; a fresh herb on its dried record counts a third of its
volume (its written dried amount; a leaf count 0 g); SR bare-noun
portions, an in-item weight and a bottle's printed volume are read; soda
rinsed off, a later drain, a court-bouillon, a dip, a drained pickle, a
poaching brine's salt and a dunk's sugar are held; and 26 rewrites of
checkpoint 8's cached-answer keys (thick-cut bacon … white baking chips);
15 = the Run 047 review: a repeated line takes the nth row of its text
(an engine row never takes another copy's decision), one weighed line
(a sub-recipe's eaten "plus" part) and one sub-recipe gate on every
write path — a confirm, a pick, an un-skip and an apply-to-all too — an
edited held medium keeps its hold, and an un-skip gives a held medium
back the engine's grams; flake and coarse sea salt weigh like kosher
salt, a sub-gram "pepper" portion weighs only a small dried chile, a
bare count's printed paren volume wins, an animal or adjective before a
list of foods is never split, and the detector and portion alternatives
no library line reached are gone; 16 = the Run 048 review: the pairing
laid out before any write (lines aligned with rows by text, one
transaction, no demotion), a held medium keeps a person's resolution
through an edit, a confirm and an un-skip, a pick and an apply-to-all
weigh the weighed line, only flake and coarse sea salt weigh like kosher
salt (plain and fine sea salt as table salt again), a volume paren
saying "each" is per item, and the guards other libraries' lines need
are back (a portion must lead with its unit, "do not drain" drains
nothing, an in-item ounce weight, a litre paren); 17 = checkpoint 8's
approved requests: rewrites of names FDC spells another way (baguette,
broccoli rabe, quick tapioca, St. Louis spareribs, pomegranate seeds,
milk chocolate, swordfish and tuna steaks, nonfat dry milk, pumpkin
purée, Nutella, water chestnuts, buttermilk powder) and of keys whose
record leads a cached answer, an unasked 'liquid' FORM segment docked as
a modified form, eight SR volume siblings, and a named whole item's
portion past the 250 g bare-count cap (grams.dart); 18 = checkpoint 9's
density guard (a density key matches as a word, 'ice cream' 0.558, dairy
powders, water chestnuts, ricotta, cream cheese and oil-packed tomatoes
on their record's own portion) and Run 049: flake and coarse sea salt
only as the line's own food (and its plus part, and more spellings), a
per-item volume paren the parse kept; 19 = Run 050's grams: a density
key that only modifies a compound ('cream of tartar', 'mustard seeds',
almond and apple butter) and a named nut ('nuts') on their record's
own portion, no drink's portion for its powder, a shredded or grated
portion for a shred, 'small' read from the item's own words, and
quantity words before a flake salt; 20 = Run 051's grams: a density key
that only modifies the item's head weighs on a record of the key's own
food by that record's volume portion (vanilla extract, cayenne pepper,
cocoa powder), sugar snap peas are no sugar, and a dried chile is small
by its item's own words; 21 = the v21 plan's zero-request rules: 82
rewrites onto cached answers, 51 rank-as items ([_rankAs]), filtered
water, banana leaf, and the grams rules (scoped jelly densities, flagged
stand-in densities, piece aliases, pint and quart parens, the bare
'fruit'/own-noun whole-item portion up to 350 g); 22 = the checkpoint 9
rulings: a starter's feeding flour, a fried food's dredge and a braise
kept only in part held (`starter_discard`, `coating`,
`partial_pour_away`), a rinsed dry cure 0 g discarded; 23 = Run 053's
rules and grams: grated Parmesan and Pecorino at the corpus's printed
0.24 g/mL, a dredge held when the DIRECTIONS fry it (not by the oil's
mass), a divided dredge's or braise's part used outside it eaten, a pick
keeping an eaten-in-part hold, `_asPrepared` only on a popcorn line, the
oil a held dredge fries in discarded by the same directions (not its
mass; a smaller first part a step names stays eaten), shredded Parmesan
at the corpus's printed 0.36 g/mL, and a "plus" part's printed weight
used over the density. 24 (Run 054): the step and line regexes linear on
hostile text (a sentence over 1,000 characters read as none — since
25 its first 1,000 are read), a
decided row's hold re-derived on every compute, and the oil, dredge,
_asPrepared and plus-part cheese rules of that run (v24's "a sentence
over 1,000 characters read as none" is superseded by 25's window). 25
(Run 055): RULE A — a decided row's every derived field (hold, grams
unless typed, their source) re-derived from the recipe on every
compute, PUT and GET; RULE B — a sentence belongs to the line that owns
it (a frying sentence binds by the oil's own amount or kind word with
its noun phrase following directly, oven heat is never frying heat, two
candidates held `ambiguous_medium`); RULE C — a detector costs O(text)
per recipe (a per-recipe step index, the first 1,000 characters of an
over-long sentence read, the matches GET memoised per key and raw); and
the grams change: `_asPrepared` on the measured head, a plus part's own
grated/shredded form. 26 (Run 056): RULE A — the derived write at the
row's current position, ONE "derivation unavailable" outcome on every
path, the totals' food fetch included (decision stored, derived fields
as last derived, the recipe stale, never a throw for one row), and an
amount-less decided line deriving no weight (a confirmed held one 0 g
`discarded`); RULE B for every frying fat (oil, shortening, lard, each
by its own noun), a binding key two lines share binding neither, lines
counted by position, every line the mass rule could zero a candidate
(a written weight of 400 g or more too; an amount-less "for
(pan-)frying" line), and frying heat as positive evidence from the
whole sentence in every temperature spelling; RULE C at the loop
level — what a rule derives per recipe or per food (mention owners,
amount writers, the sentences naming a food, the frying-oil owners)
derived once and shared, a line costing its own mentions, the
over-long-sentence notice logged once per recipe and content; the
grams change: a plus part's form read after its comma, and only a
one-word paren (or comma part) a modifier of the measured head (the v25
replay byte-identical). 27 (Run 057): RULE A as a ROW fact — each
decided row's `derived_seq` (migration 014) names the layout and inputs
its derived fields were computed for, and freshness is the stamp AND no
decided row underived (one SQL predicate every reader reads); a food FDC
no longer serves is the `food_gone` hold, derived; an outage leaves the
row underived (one request per row per pass, the job stopping with the
provider's reason); the totals cache-only; an apply-to-all target FDC
cannot weigh counted `unavailable`. RULE B — an appliance or method
word excludes only the temperature its own clause governs (never a
vessel — "baking sheet", "roasting pan" —, "roasted peppers", an oven
past a ";" or past a heat verb), the leads and heat verbs open (at, is,
reads, a temperature of, between … and, a range; maintain, keep, hold,
fry …) and every degree spelling (º, ˚, deg, Fahrenheit); the mass rule
read with no food (a written volume at its density, a written or
printed weight: the 48-ounce bottle zeroed on every path, the GET's
`held` and the compute one answer) and the candidacy on the same
reading (a printed-weight bottle, a "for (pan-)frying" line with any
amount); every medium
threshold in both unit families (a weight-written oil, dredge, brine salt
or soak at its density). RULE C — the naming index built on the second
head asked, inverted name and amount indexes for the dissolve and plus
readers. The grams change: a paren or comma part qualifies the popcorn
head when every word is a qualifier ("(unpopped kernels)" 96.5 g).
28 (Run 058): RULE B — a scope boundary is a clause MARK, never the
evidence's own word: a frying temperature's clause runs from the last
"; , — ( )" (a mark directly before a heat verb's participle opens
none: "in the smoker, holding it at 300"), so an appliance governs the
temperature its own verb heats ("an oven heated to 375", "until the
oven thermometer registers 375"); the governing words located once per
sentence, each temperature answered by a forward pointer (linear per
clause, `heatClauseChars`); a vessel never excludes (Dutch/French oven,
oven-safe/-proof, broiler/grill pan, broiler-/grill-safe); the fry range
kept at 300–399 °F, judged on the library's 400-degree sentences; the
medium thresholds read food-free densities for bread crumbs, a starch,
shortening and lard (0.87, FDC 173584/171401) — never a line's grams —
a same-food plus part in both unit families, and four cups exactly.
RULE A — "derived for" names every input a derivation reads: a
`food_gone` row re-read from the caches on every compute (no request;
derived again once a cache holds the food); the nutrient sibling
resolved where its food is (a 404'd sibling is the row's `food_gone`,
an engine candidate passed over; the separate prefetch deleted); a plain
recompute resolves a food no cache holds before it reads the totals;
two failure classes (`FailureScope`: GLOBAL stops the job, FOOD is the
row's — underived, counted, held `food_unavailable` at the third
compute); a pass that throws leaves no row marked derived; one action
table per hold (salt_shared `holdActions`) read by the PUT's gate and
the queue's SQL; migration 016 (`retry_count`, the search-cache food
index). Replay: no row moves (RULE A changes no landing).
RULE C — the naming inversion built by MEASURED amortisation (each food
scanned for alone — a pass per step for where its word starts, the
sentences of only the steps that have it — until the scans paid on the
recipe's index reach the inversion's measured cost: the reach and the
apply-to-all build none, the compute and matches GET of a cap recipe
build it once), the inversion linear per sentence (each word confirmed
at the word), the matches GET resolving each row's food once, one FDC
request per food per pass
(`onePass`: asked ids, 404s and failures remembered). Pairing: a run of
identical lines laid out in its own order (never branched on; exact
for the script's cost and the decisions kept). The app reads the same
action table (`holdActions`) for its buttons and copy, and the stale
banner names its cause (`stale_reason`). The closer: a detail outage
(FOOD failures on 3 distinct foods in a row within a pass) escalates to
GLOBAL, counting and holding none; the PUT's gate reads the stored hold
before a carried row's derivation; which holds a pick keeps is the
action table's. Replay: no row moves (RULE C and the pairing change no
landing).
29 (Run 059): RULE B — a frying temperature's clause starts at the
LATEST boundary at or before its lead: a clause mark, an "and"/"then"
opening a new verb phrase, or the fat's own mention; a mark or opener
whose phrase opens on a non-fry heat verb (its object unnamed: "in the
smoker, holding it at 300", "on the pizza stone and heat it at 350") is
none — the v28 participle exception deleted, so "…oven, heating the oil
to 350" and "Place a rack in the oven and heat the oil to 350" are the
oil's heat again; a lead's own "(" opens the clause, a boundary inside
a lead none. The hyphenated vessels (grill-pan, broiler-pan,
roasting-pan, baking-sheet/-dish) never exclude. The heat reading's
whole-sentence passes built once per sentence per index, shared by
every fat and caller, each read only as far as a check needs and the
governing words from the clause's start (`memo:heatReading`,
`heatClauseChars` counting every pass and pointer step). FDC's failure
table: an unreadable 200 on a detail is the food's (FOOD), a search 404
GLOBAL (no private exception escapes the provider), the network GLOBAL
even on a detail. Replay: no library row moves (the boundary changes
only typed sentences; the 78 corpus fat-and-temperature sentences and
all 13,615 oil/dredge readings identical to v28).
RULE A (the same release): a hold is RE-READ before it is enforced —
a cache-only derivation through `knownFood` at every compute, at the
PUT's gate and at the GET (a cache write that gains the food re-opens
the held rows); an ENGINE line's FOOD failure is its row's state
(counted, held `food_unavailable` at the third), never the pass's; the
outage escalation is counted across the JOB, spans two recipes and
never discards a row's count; a pass is in progress until its totals
are written (migration 017's owned count); the PUT judges every verb
and resolves only its own line's foods; the held write keeps its count
and the `all` scope asks a held food once; the hold families live in
the action table. Replay: no row moves (RULE A changes no landing).
RULE C (the same release): a cost unit IS the cost — a food named in
the steps is looked up over ONE word index per step (each word's start
and hash, built once), a lookup paying exactly the words it visits and
its confirms' characters (`namingPaid`), the inversion the word index
inverted, built at 12 × the words (Run 059 O9: v28's regex step pass
cost 0.1–9 ns a character as the words spelled). Pairing: a run of
twins is ONE ordered multiset — the search never chooses a twin, a run
keeps its decisions first, its surplus dropped where the fewest rows
move (ties from the end), laid in position order (400 twins, one edit:
10,000 layouts → ~800). Replay: no row moves.
30 = the rulings already made, built as table entries only: Q7's bone-in
parts (18 rank-as items onto their raw records at the printed gross
weight, labelled approximate; flap meat, turkey drumsticks/thighs and
leg quarters flagged approximations; "rib slabs" buys bone) and Q6's
corpus-printed pods (dried New Mexican and guajillo chiles 7.1 g each,
flagged). Replay: 24 rows move (20 bone-in, 4 chile), 17 recipes
complete. The fresh ham, the live step's details and searches wait,
commented where they will go.
31 = the CP10 rulings (2026-10-03), table entries plus the narrowest rule
each named recipe needed. Q6: fresh ginger and citrus zest strips by
their printed length (8 and 0.8 g an inch), the dried chipotle (4.6 g),
whole spices, lemongrass, lasagna sheets (Barilla 17 g, Ronzoni 25 g)
and a scallion bunch (7 × 15 g), each flagged with its source; star
anise on anise seed, flagged. Q7: the eight small groups, anchovy paste
(6.7 g a teaspoon), the misc mappings (Cubanelle 99 g, cornichon 3.2 g,
instant espresso at its siblings' 0.43), Spanish chorizo on 2706179 and
linguiça on the smoked pork link; a confit's duck fat is a frying medium;
a held breading's bread is held with its flour. The held-media rulings:
a poach whose liquid is poured away but a measured part is held
`partial_pour_away` (0488), a plus part eaten after the fat's last
discard counts (0042), and a fat fried by the verb alone is held
`ambiguous_medium` (0288, 0674, 0675). Replay: 191 rows move (A 49,
B 133, C 9), complete 847 → 939. The light sour cream, the brioche and
the dry-cured chorizo wait for the live step, commented.
32 = the live step's rules, enabled (12 details and 2 searches recorded
2026-10-03). Each dry entry enabled once its detail was read and its
check held: chicken leg quarters (172378, no refuse yield: gross,
approximate), oil-packed tuna (175157), sweetened cranberry juice
(171903), dried onions (170002), the fresh half ham (168226, no refuse
yield: gross, approximate), cooked wheat berries (169744, flagged),
jarred pimentos (168559), low-fat sour cream (173443), brioche buns
(2707682, sized by a 77 g piece figure from its "1 piece" portion, which
the finder alone reads as a dish serving), and the tamarind and egg
volume siblings (167763 "cup, pulp" 120 g; 171287 cup 243 g). One stays
dry, its check failed: the portobello cap (2003598 publishes a racc
portion only). Spanish-style chorizo moves
to a flagged "Salami, Italian, pork" (174603): FDC has no dry-cured
chorizo (the owner's decision).
33 = the dredge-reach ruling (2026-10-03): a reachable dredge (flour,
starch, crumbs, panko, ¼ cup or more, named in a dredge sentence) is
held `coating` in ANY cooking class whose directions leave an excess of
the coat — a sentence that shakes, removes or pats off the excess, never
a liquid's, never in a dough step — and still whenever the recipe fries
(the CP9 ruling, sufficient). A coat wholly eaten (a toss, a binder, a
crust pressed on with no excess sentence) stays counted. The bread a
held breading puts through the processor (a step, or the line itself)
is held with its flour when a sentence coats the food with the crumbs,
and so is a crumb or panko line (¼ cup or more) of a recipe that holds a
dredge when a sentence coats the food with crumbs (0416, 0117: the steps
name the panko as "the bread crumbs", "the panko mixture").
34 = the coat's other layers (the owner, 2026-10-03, "the narrow
version"): a nut, cheese, cracker, chip, cornflake or Melba toast line
(a quarter cup or more, or a count; the first line of its head) named in
a sentence that sets the coat out in its dish or names it with the
coat's crumbs is held `coating` with the dredge of a recipe that holds
one (L1: 0042, 0117, 0315 ×2, 0407, 0416, 0419), or of a recipe whose
directions leave an excess of the coat with no dredge line to hold (L2:
0150's Melba toast). A row with no food gets no hold (0198's cornflakes
stay no match). The four fried dredges with no excess sentence stay held
by the frying ruling (no change).
35 = the portobello caps (the owner spent two requests, 2026-10-04: the
search 'mushrooms portabella raw' and the detail of 169255): "1 large
portobello mushroom cap" and "6–8 portobello mushrooms" rank as SR
169255 "Mushrooms, portabella, raw" and count by its '1 piece whole'
84 g, flagged approximate (a whole mushroom read as one stemmed cap).
(No 36: v36 changed the engine's failure path only.)
37 = the queue sweep, part 1 (the planners' zero-request rows, the
owner's "go with your recommendations", 2026-10-04). Rank-as lifts onto
right cached records (pears, salmon, raisins, cheddar, orange juice and
zest, canning salt counted, nine 0 g lines' foods, a lemon twist's);
figures ATK prints (pearl onions, lentils, strawberries, grape tomatoes,
cooked chicken, shredded apple, a yeast envelope, a sugar cube, a sea
scallop) or FDC publishes (a gyoza wrapper on the wonton's, a baguette's
inch, the green-olive and jalapeño cups, roasted peppers on pimento's,
crushed tomatoes on tomato sauce's), each labelled with its source; a
comma-clause printed weight ("about 3½ pounds", "3 pounds trimmed
weight"), a volume line's own "(about 8 fillets)", "1 small pinch", a
dash on a record's tablespoon, an unparenthesised zest strip; a
continuation fragment is the line above's (engine). The S groups: foods
FDC has no record of on flagged stand-ins (mirin, gochujang, doenjang,
galangal, culantro, alcaparrado, nonpareils, five-spice, garam masala,
Sichuan and pink peppercorns, chipotle in adobo, white fish, mixed
herbs, crème fraîche at heavy cream's density). The class ruling: six
zero-nutrient flavouring items count 0 g on no food (engine;
[isZeroNutrientFlavouring]), yielding to a held medium. The request
groups built dry (LIVE STEP comments; 30 requests).

v38: the v37 request groups after the owner's live step (2026-10-04, 21
details and 5 searches), each enabled only where its check passed on the
record's real portions: bulgur, diastatic malt, roasted salted pepitas,
Oreos, turnip, romaine leaves, frisée on endive, cremini, ya cai
(flagged), and the radicchio, cauliflower and canned-chickpea volume
siblings. Dry with the portions FDC published: pectin, fennel fronds,
Morello cherries, xanthan gum, parsnips, kiwis, malted milk powder,
nori/gim, raw cashews; FDC has no record of candied ginger, freekeh or
whole farro (a person's lines).

v39: edible yields, part 1 (the owner's "go with your recommendations",
2026-10-05; prep39/plan.md §1–§2; zero requests). Meat (grams/engine):
a bone-in line weighed from a printed weight whose record publishes no
refuse reads its class's FDC yield, flagged (`boneInClassYields`,
revising CP6 #11 and #5: 109 lines); five shellfish lines whose grams
need no shell yield are counted, not held `in_shell` (`shellCounted`:
the per-item mussel and oyster, the live lobster's own "1 lobster", the
shrimp eaten shell and all); a skin-discarded thigh or leg moves to its
meat-only record at FDC's meat share (`skinDiscarded`, `skinShares`: 13
lines; breast and whole bird wait on the live step). Produce: canned
coconut milk on SR 170173 by rank-as (9 lines, unflagged); a small or
large onion, carrot or round tomato on its SR size portion and a plum
tomato at 170457's 62 g (grams: 118 lines); the prep-loss shapes, read
only on a printed weight with the word after the first top-level comma
— a counted banana by its record's "Peeled" portion (2 lines) and a
drained canned tomato whose juice is not reserved × ATK's 0.54, flagged
(28 lines).

v40: edible yields, part 2 — the live step's answers (the owner's 13
requests, 2026-10-05; snapshot 17), each enabled only on the plan's own
condition. A whole bird or pieces on 171447 whose recipe discards the
skin moves to SR 171052 (`_skinlessRecords`), read at its own
ready-to-cook yield 197 g a pound — the whole bird unflagged, pieces
flagged (grams: 5 lines). Clams bought in the shell by weight rank as SR
174214 and read its "lb (with shell)" shell yield, counted, no longer
held `in_shell` (6 lines). Not enabled, with the answer FDC gave
(docs/API.md): the breast share (171077 publishes no half breast), the
whole-turkey yield (no raw back or neck meat-and-skin record), mussels
(174216 publishes no shell portion), canned beans (no can size).

v41: the composite row (migration 018; the owner's 2026-10-05 rulings on
prep41/design_v3.md). (R1) a sub-recipe reference line routes to the
library recipe the parent's note names first (flagged a default when it
names several) or whose title it is exactly, counting the child's totals
× the line's share (`gram_source` recipe, no food; 13 lines); a reference
no library title answers is held `choose_recipe` (35), a reference
marinade `discarded_recipe` (3), a child itself made from a recipe
`nested_recipe`; sections, served-with, no-amount and no-share references
stay the 0 g rule row. (R2) rendered bacon, rule B1: a 168277 line whose
recipe lifts the meat out and pours off all but N of the fat counts as
cooked bacon 168322 × 0.403 plus the kept fat on 172345, one row with two
parts (13 lines). (R3) a reference rule row is neither accounted nor
contributing: its recipe reads partial (87 recipes leave complete).

v42: canned beans (the owner's 2026-10-06 ruling (b)). A can line
weighed by its printed weight on one of the six Foundation "drained and
rinsed" bean records counts its bean's drained share, FDC's own SR can
pair (chickpea 0.565, kidney 0.610, pinto 0.627; black, cannellini and
navy the median 0.610), flagged (`cannedBeanShares`); a line keeping the
liquid ("undrained", "do not drain", "liquid reserved", "with their
liquid") counts the can whole, "1 can drained, 1 can undrained" half the
cans at the share (grams: 19 lines).

v43: the USDA Agriculture Handbook 102 yields (the owner's 2026-10-06
rulings Y1–Y13, "go with your recommendations"; zero requests). Birds
(grams/engine): a bone-in chicken or turkey part reads the AH-102 raw
figure of the part the line names first (`ah102Parts`, `birdPartOf`):
chicken breast 584, thigh 586, drumstick 585, wing 590, the derived leg
(585–586) and pieces (584–586) by 583's carcass shares; turkey thigh
2598, leg 2596, leg quarter 2595, wings 2602 (fryer-roaster class) and
the whole turkey 78/85 × 2592 = 0.6515; the RECORD decides meat or meat
and skin (`ah102Records`, Y13), so a skin-discarded part reads its meat
figure in one step (Y12 retired the v39 skin-share stack, `skinShares`);
a skin-discarded breast moves to 2646170 (`_skinlessRecords`, Y3: the
five lines; "reserved cooked chicken" no longer vetoes the skin). Whole
chickens keep FDC's own ready-to-cook yields (Y4); the bone-in turkey
breast keeps the interim figure (Y7, deferred). Produce (grams, Y8): a
weight printed in the line's head on a `produceYields` record with the
prep word in its tail counts the AH-102 paring/trimming yield (potatoes
peeled 2018 · 81, apples peeled 17 · 78 / cored only 30 · 90, sweet
potatoes 2496 · 80, pears 1734 · 78, carrots 481 · 82, onions 1568 · 90,
leeks' white and light green parts 1412 · 44, savoy by head cabbage
440 · 93 (savoy is not printed), cauliflower 499 · 92, butternut
2459 · 84, zucchini 2446 · 93, summer squash 2444 · 95, strawberries
2473 · 94); never a count read, a
trailing prepared weight or "peels reserved" (104 lines). Scallions
(Y9): a counted scallion's "white parts only" × 0.37 (1575), "green
parts only" × 0.59 (derived, 1573/1575), of the whole scallion with
rootlets (6 lines). Meats (Y10, `ah102Meats`): spareribs 1925 · 58,
standing rib 238 · 82, fore shank 228 · 61 (a lean-only record),
lamb rack 1364 · 73 (measured unfrenched), lamb foreshank 1339 · 70,
cured spiral ham 1937 · 70, fresh ham shank half 0.78 (derived from
1930) replace the borrowed class figures (15 lines); FDC's own refuse
classes stay. Bacon B1 keeps 0.403 (Y11; re-ruled by v50).

v44: sections as children (prep43 design_v2 §2 v44, the owner's
2026-10-06 rulings S1–S15). A referenced section is a recipe of its own
keyed `<host id>#<exact title>` (migration 019): a reference to ONE own
section, or to another recipe's section exactly ONE host carries (N8),
routes to it at the share the line reads from the SECTION's yield; a
section with no ingredient lines is the `no_ingredients` rule row; an
unmarked line naming its own section (A9) reads one too, a bare 1 as
one recipe (S11); a "(recipes follow)" line held for a person lists its
own sections no other line routes to (rule PO). The section's stale
hash carries its yield. Rules (S6/S7, zero requests): "back pepper" and
an amount-less salt "for <purpose>" are seasoning (3 main rows), "warm
tap water" water, a lone "boneless" reads on to its food, the leaked
"fluid ounce(s)" items read their drink, a section's reserved parts and
pan drippings and its main recipe's reserved spice rub are 0 g rule
rows (two new notes), "green thai" J6's 'thai', a zest plus a COUNT of
oranges the oranges (746771); S5's 23 section reads onto cached answers.

v45: option A spent (the owner's live step, 2026-10-06; snapshot 20).
Three rank-as reads land the record each answer's check names — the
cola soft drink 2710541, imitation sour cream 2705617 (flagged), the
coconut-milk yogurt 2707569 (weighed by its own cup: 'coconut milk
yogurt' is not the dairy 'yogurt' key's food) — and the three seed
records that publish no volume portion read their siblings' cups
(grams.dart volumeSiblings: 2515380 → 169415, 2515381 → 170154,
170151 → 2707586).

v46: option A part 2 — the owner's 2026-10-07 rulings on the six
answers that failed their checks (zero requests): mascarpone on heavy
cream 2346386, potato starch on cornstarch 169698, brown rice flour on
white rice flour 790214 (flagged rank-as reads; the GF flour blend
completes), nutritional yeast flagged on 2710005, frozen cranberries and
frozen pineapple chunks rewritten to the plain fruit (171722, 2346398).

v47 (the Matcher v48 commit, batch M48 — the v47 commit's review fixes
moved no landing and kept 46; the owner's 2026-10-07 re-ruling of
checkpoint 9 Q5; zero requests): every printed weight RANGE reads its
midpoint — the hyphenated "(5- to 7-ounce)", the fraction "(8¾ to 10
ounces)", the en dash "(12–22 pounds …)" and a spaced "(3 ½- to
4-pound)" as the whole-number "(5 to 6-ounce)" and a bare "1½–2 pounds"
already did (grams.dart `_range`; the `rangeWeightsMidpoint` switch is
gone); reversed bounds keep the larger ("(14⅔ to 6½ ounces)", a corpus
typo); the basis names the range, "8 × 170 g (printed 5–7 oz, the
midpoint)", no approximation flag (186 main lines' grams, 14 more
lines' basis).

v48 (the Matcher v49 commit, batch M47 — records and published figures;
the owner's 2026-10-07 standing authorization, prep47 design_v2 §1 (B);
zero requests): shell-on shrimp at AH-102 item 2333 (0.81) and mussels
by weight moved to raw SR 174216 at item 1531 (0.29), flagged
(grams.dart `ah102Shells`, engine `_shellRecords`); kiwi 75 g a fruit
(FNDDS 2709239; a sized line flagged); a zest over a tablespoon plus
juice as two parts unless a step strains it (juice only), and a zest
plus a COUNT of lemons or limes the fruit; a can whose steps add it
"and their liquid" whole, and a kept-liquid can on its cached solids-
and-liquids record (175206, 175201, 175195; the half rule as two parts);
jarred hot cherry peppers read the pickled answer by rank-as (the Thai
chiles' raw-pepper read rank-as too), herbes de Provence on dried thyme
and halloumi on Monterey (flagged), frozen raspberries on 2709282, the
pasta e fagioli pasta on SR 169736 by rank-as (the owner's ruling), red
curry paste and Old Bay `no_match` with no record (`noFdcRecordItems`);
tapioca starch at ATK's 3 ounces per ¾ cup (flagged); nutrient siblings
for the pasta, leeks and rhubarb records (engine `nutrientSiblings`).

v49 (the Matcher v50 commit, batch M50 — discards and partial use; the
owner's 2026-10-07 standing authorization, prep47 design_v2 Q16, Q17,
Q18, Q20, Q21, Q7; zero requests; engine `DiscardedMedium`): a strain
that presses or discards its solids (or strains a stock or broth) counts
the aromatics, herbs, whole spices and zest strips in it 0 g, flagged —
never a ground spice, powder or paste, nor a line its own steps blend
smooth; cured pork and ground stock meat strained out or discarded count
0 g when a sentence skims, separates or pours off the pot's fat (or
blanches and drains the meat), else are held `discarded_medium`; a
whole-piece aromatic removed and discarded by name counts 0 g (only the
discarded pieces of a "1 of the lemons" or "1 bell pepper half" count
line, and never the "remaining N" part a line's own mention keeps out
of the strained pot or the discarded bundle); a printed part
kept counts the kept part (a remainder saved subtracted; a potato's
kept cooked weight to the raw record by FDC carbohydrate on SR 170033 /
170114; a food reserved or the rest discarded 0 g); a kept volume with
no weight, a dip or batter left in the bowl and a marinade the food is
lifted out of are counted as before and flagged.

v50 (the Matcher v51 commit, batch M49 — the bacon package and fat
poured off; the owner's 2026-10-07 standing authorization, prep47
design_v2 Q4 (b) and Q19 (a), re-ruling Y11's 0.403 and v40's "the
wider bacon lines a person's"; zero requests): rule B1's cooked yield
is USDA AH-102 item 1981 (bacon, sliced, all methods, 33 %), its
rendered fat 0.2555 g a raw gram by the same fat balance, flagged; a
bacon slice weighs 168277's own 28 g, a thick-cut one the corpus's
printed 35.44 g (flagged), a Canadian one 167869's 28.5 g; an oil
browned in a pan whose fat the steps pour down to a printed part counts
at most that part (in rule B1's bacon pan its R / (R + O) share, the
bacon's grease the rest), and a frying oil's "reserve N … discard the
remainder" is its kept part, counted with the part it is used for
outside the fry.

v51 (the Matcher v52 commit, batch M51 — references with no amount; the
owner's 2026-10-07 standing authorization, prep47 design_v2 Q8, Q8b,
Q9, Q22, re-ruling prep41 A3 (a) and CP3 for these lines; zero
requests; engine `resolveReference`): a reference line with no amount
that is optional, for serving, offers an "or", sits in a CONDIMENTS
group or names the dish its parent is made for (D7, with or without an
amount) is served with it — 0 g, accounted, never partial; any other
amount-less line reaching a child with lines counts one whole batch,
flagged; a reference WITH an amount to a prose variation (a section with
no lines) counts the base whose title shares the most words (the host on
a tie), flagged. A line WITH an amount reads no served-with marker and
no whole batch (the critic's F7 gate).

v52 (the Matcher v53 commit, batch M52 — coats and frying-oil uptake;
the owner's 2026-10-07 standing authorization, prep47 design_v2 Q2 (a),
Q3 (a) and Q24 (b), re-ruling checkpoint 9 Q2, the 2026-10-03 (night)
(1) "the four fried dredges stay held" and, for a coated food browned
in the oil, the 2026-10-03 R4 "shimmering stays non-evidence"; zero
requests; engine `_m52Plan`): a held dredge counts its share of a coat
budget sized from the coated food (k by the coat's shape from USDA
FNDDS fried and baked coated recipes' read `inputFoods`, the last cook
deciding), nut and cheese layers and sautéed dustings still held; a
zeroed frying oil counts what its fried food absorbs (u per food, read
or derived, flagged) on top of its kept part, capped at the line; an oil
of ¼ cup or more heated for a coated food browned in it is a frying oil
(five lines), and its food's crumbs a held coat.

v53 (the Matcher v54 commit — Q25, alcohol cooked off; the owner's
2026-10-07 standing authorization and Q-a..Q-h, prep47 design_q25_v2;
zero requests; engine `alcoholRetentionOf`): a counted row on one of the
sixteen alcohol records keeps its record and grams, and its ethanol
energy (the record's energy less Atwater 4/9/4 of its protein, fat and
carbohydrate) counts only the share the dish keeps — USDA Retention
Factors R6 5002–5009 by the cooking its own steps print (the minutes at
a range's low end, stirred in off the heat into a hot dish 5002 by Q-f,
flamed 5003, a stuffing rolled inside a rare roast not cooked by it);
the row's flag says so.

v54 (the Matcher v55 commit, batch M56 — meat records at the right
animal, cut and fat level; the owner's 2026-10-08 decisions Q1 (a), Q2
(i), Q3 (a), Q5 (a) and Q7 under the standing authorization, prep48
design_v2 §2 M56; zero requests): rank-as items land a strip roast and
boneless strip steaks on Foundation 2727572, blade steaks on beef 168707,
a beef brisket on the raw flat at 0" (168743; a printed ¼-inch cap says
it stands in) and the boneless center-cut pork loin roast on Foundation
2646168; a "separable lean only" top yields to its exact lean-and-fat
sibling in the same answer (engine `leanAndFatSibling`) unless the line
asks for lean; a printed trim moves a keyed record to the record at that
trim (engine `trimDepthRecords`: the rack 172641 → 174414 with its
AH-102 row, read with no detail; "fat caps removed" 2727572 → 171751).

v55 (the Matcher v56 commit, batch M57 — a strain of "the liquid" whose
solids nothing uses; prep48 design_v2 §2 M57 S1, critic F4 and F14, the
owner's Q19 NO; zero requests): engine `_strainAt` also reads "strain
(the) (braising|cooking|poaching) liquid" when no sentence from it to the
end names solids, vegetables, a blender, a food processor or a purée —
its aromatics, herbs and whole spices 0 g under M50 Q16 with the shipped
strained-solid flag; a rejected one continues the scan.

v56 (the Matcher v57 commit, batch M58 — a batter left in the bowl
joins the coat budget; prep48 design_v2 §2 M58 W + S + the negimaki
flag, the owner's Q8 and Q10 and critic F10 under the 2026-10-07
standing authorization; zero requests): engine `_m52Plan` counts the
lines a batter leaves in the bowl (`_batterInBowl`, the dip word
"batter") as coat parts at the coat's one f = min(1, B / Σ carbohydrate)
— never off a C5 budget; battered shrimp is C5 on its own FNDDS 2706364
and a battered haddock on 2706258 (15.38); the coat flag says "the
batter's excess", names a figure read on another food as a stand-in and
a batter read on a C1/C2 breading figure; a glaze the steps divide
between two bowls (negimaki) states the split, counted whole.

v57 (the Matcher v58 commit, batch M59 — the frying oil the steps keep
or rinse off, and a battered vegetable's uptake; prep48 design_v2 §2 M59
C + F1 + D, the owner's Q13 (b) and critic F1, F9 and F12 under the
2026-10-07 standing authorization; zero requests): "After frying,
reserve 2 tablespoons frying oil" is a frying oil's kept part when a
later sentence heats the reserved oil (engine `_Fat.reserveFrying`), the
uptake on top; a frying oil's part a sentence tosses with a food is not
eaten when later sentences of the same step drain and rinse (engine
`_rinsedOff`; no food is matched — the step stands in for the tossed
one); the fried cauliflower's read uptake scales to the
carbohydrate its ingredient group's batter holds against FNDDS
2710042's (c_b 0.40), flagged "derived".

v58 (the Matcher v59 commit, batch M60 — the bone-in turkey breast, a
peel written in the steps, bacon that drips; prep48 design_v2 §2 M60
Y + P7a + P7b, the owner's Q14 (a) and Q15 (a) and critic F8 and F15
under the 2026-10-07 standing authorization; zero requests): the
bone-in turkey breast 171093 reads a derived AH-102 figure (items 2591
and 2593: the breast's meat and skin, 87 % of its 33 of 43
breast-plus-rib parts, 66.8 %; the back not counted) instead of the
chicken's class figure; a produce weight whose tail names no prep word
takes the record's 'peeled' yield when a step sentence begins by paring
the item raw (engine `stepsPeelIn`: no smaller count, no earlier
sentence cooking it), flagged "the steps peel it"; bacon B1 leaves
unrendered that a step lays over or wraps round a food that then bakes,
roasts, grills or broils is B1's two parts with no fat kept (engine
`_baconDrips`), flagged "the fat drips off the food".

v59 (the Matcher v60 commit, batch M61 — fried doughs, fritters, rolls
and falafel take an uptake; prep48 design_v2 §2 M61, the owner's Q12 and
rulings R-a … R-e under the 2026-10-07 standing authorization; zero
requests): a frying oil no counted line is the fried food of counts the
uptake of the PRODUCT a frying sentence names (engine
`_friedProductOf`: batter, dough, pakoras, fritters, lumpia, egg or
spring rolls, falafel, doughnuts, struffoli) on its raw mix — the
counted rows of the oil line's ingredient group before it: FNDDS 2710066
"Pakora" 8.43 %, 2708702 "Egg roll, with beef and/or pork" 7.62 % (a
stand-in for lumpia), 2708024 "Fritter, plain" 23.32 % (a stand-in for a
cake dough), and two balances DERIVED from SR Legacy — 172758 (yeast
doughnuts, protein tracer) 16.72 %, 172455 "Falafel, home-prepared"
(carbohydrate tracer) 21.64 %.

v60 (the Matcher v61 commit, batch M62 — egg dips sized by the read wet
share, held-coat dips held, no crumb rule; prep48 design_v2 §2 M62 and
§1 Q9 with H as the owner's decision, the planner's E-w under the
2026-10-07 standing authorization; zero requests — FNDDS 2710785 read
at live step L): a coat's dip in an egg or buttermilk mixture whose
excess the steps leave in the bowl (engine `_dipsOf`, `_dipExcess`'s
first arm) counts the wet grams FNDDS 2710785 "Breading or batter as
ingredient in food" holds per gram of its carbohydrate (15 g egg and
120 g water in 287 g at 40.1 %: 1.17) times the carbohydrate the coat
counts, shared by the dip lines' grams, the coat's parts unchanged; the
dip of a coat held with no budget is held `coating` with it; a dip with
no coat keeps the "excess in the bowl" flag only.

v61 (the Matcher v62 commit, batch M63 — the 8-inch pita by FDC's
per-area portion, the crab cake's own oil, the sirloin stand-in flag,
the rack's retired hit read; prep48 design_v2 §2 M63 and §1 Q3, Q6,
Q11, Q16, the owner's rulings of 2026-10-08 under the 2026-10-07
standing authorization; zero requests — live step L's L3–L5 reads): a
pita counted by its printed "(N-inch)" diameter on FNDDS 2707616 weighs
the record's own '1 surface inch' 2 g × π (N/2)² (grams `_perArea`,
flagged "derived"); a fried crab absorbs FNDDS 2706549 "Crab, cake"'s
own oil, 5 g per 65 g crab (7.69 %), not the chicken breast's stand-in;
a top sirloin roast on the lean-only petite roast 173408 says it stands
in (no lean-and-fat petite roast exists in FDC); the rack's 174414 is
weighed on its cached detail (the M56 search-hit set retired).

v62 (the Matcher v63 commit, batch M64 — corpus prints; prep49
design_v2 §2 M64 and the owner's Q12 (a) under the standing
authorization; zero requests): kosher salt weighs half of table salt by
volume (grams `_kosherSaltDensity` 0.60865: the corpus's "1 tablespoon
kosher salt or 1½ teaspoons table salt" on SR 173468's '1 tsp' 6.0 g;
flake and coarse sea salt keep 0.72); a counted part set aside for
another use is subtracted ("Set aside 1 pear half and reserve for other
use": engine `_partialUseOf`'s `pieces` arm); "remove (the) bay leaf"
discards the bay leaf (engine `_discardClauses`' remove arm, bay only),
and an unflagged sub-gram piece prints its figure ("1 × 0.2 g each");
a pour-off cuts the last oil-naming sentence before it in any earlier
step (engine `_panOilAt`); a frying oil whose yield prints the oil out
("… AND ABOUT 1¾ CUPS FRIED SHALLOT OIL") counts the difference (engine
`_yieldOilEaten`); and "Using slotted spoon, remove solids from pot and
discard" strains the solids out (engine `_strainWord` /
`_strainedSolids`, H1: guay-tiew's lemongrass).

v63 (the Matcher v64 commit, batch M65 — matcher landings with the
record already cached; prep49 design_v2 §2 M65 and the owner's Q14 under
the standing authorization; zero requests): a volume line bought "from N
(W-ounce) jars|cans" weighs its volume, not one container (grams
`_fromContainers`), and the jarred Morellos land on SR 167769 "Cherries,
sour, canned, water pack, drained" (v38's R05, flagged); dried corn husks
are a wrapper ([isNonFood]); gel food dye is a zero flavouring; the kombu
line shows FNDDS 2709988 "Seaweed, dried" (flagged; still strained out
at 0 g); ricotta salata counts as SR 173420 "Cheese, feta", a flagged
stand-in whose sodium and fat the basis states.

v64 (the Matcher v65 commit, batch M66 — coat parts and dips; prep49
design_v2 §2 M66, the owner's Q5 (a) gated, Q7 (the one-way door,
accepted 2026-10-09) and Q8 (b); zero requests): a nut or cheese layer a
step names with a crumb joins the coat's parts at the one f (engine
`_layerInCrumb`; a cheese crust with a flour binder stays held); the dip
is sized off B, never the parts' Σ (C = B); a dip line's part a later
step writes ("remaining ¼ teaspoon zest") is eaten whole; a head two
dip-recipe lines share is told apart by each line's own word ("black",
"cayenne"); an egg dip with no coat beside it opens the budget where the
recipe shallow-fries the coated food and it has a shape (0415; a baked
or air-fried egg wash keeps the bowl flag); a C5 batter's basis names
the breading's carbohydrate it is matched by, and alcohol in a fried
batter says USDA prints no frying row.

v65 (the Matcher v66 commit, batch M67 — fried doughs; prep49 design_v2
§2 M67, the owner's Q9 (A2) and Q10 (a) under the standing authorization;
zero requests): a fried dough the steps roll to a sheet and cut counts
only the cut share — one step printing the sheet, the count of rounds and
the round cutter (engine `_cutShareOf`: 12 × 3-inch rounds from a 10 by
13-inch sheet, 65.25 %) — each dough line at that share of its whole
weight, `discarded`, and the uptake on the cut grams; a cake dough
(struffoli) takes 14.15 %, P3's carbohydrate balance on SR 174990
"Doughnuts, cake-type, plain (includes unsugared, old-fashioned)", the
one input FNDDS 2708063 lists, for 23.32 % on the fritter batter.

v66 (the Matcher v67 commit, batch M68 — the whole brisket at its printed
trim, the home-corned briskets flag-only; prep49 design_v2 §2 M68, the
owner's Q1 (a) for the whole cut and Q2 (c) for both corned recipes,
2026-10-09; zero requests): a whole brisket printing "fat trimmed to ¼
inch" moves off the lean-only 168607 to SR 168664 (whole, ⅛", lean and
fat — engine `trimDepthRecords`), flagged at ⅛" with its rendered fat
not deducted; a fresh flat in a recipe titled "corned beef" says the
rinsed cure's sodium is not counted (engine `trimStandInFlagOf`). The
flat's ¼-inch cap keeps the 0" record until L49.

v67 (the Matcher v68 commit, batch M69 — sautéed and vegetable coats;
prep49 design_v2 §2 M69, the owner's Q4 ruling (b) and Q6 (a), 2026-10-09;
zero requests): a held flour dredge on a THIN piece that is neither fried
nor baked after the coat (a step pounds it ⅛–½ inch thick, or its line
prints the thickness — engine `_thinPiece`) is C4 and counts at C2's read
3.18 (FNDDS 2705980) as the stand-in, the unused Veal Marsala read 7.82
named in the flag; with no meat beside a held coat, a coated eggplant
baked after the coat (C2, its one arm) sizes the coat at 7.93, read from
FNDDS 2710050's batter (engine `_coatedVegetable`; a fried one stays
held). The onion rings stay held (no sourced figure).

v68 (the Matcher v69 commit, batch M70 — the records read at live step
L49 and the zero-request giblets; prep49 design_v2 §2 M70, the owner's
Q1 flat (b′), Q11 and Q13 G2, 2026-10-09; zero requests): the
pomegranate brisket's ¼-inch flat on SR 173128 (⅛") with its braised
pair's energy share 67.6 % (engine `braisedEnergyShare`); the Giblet Pan
Gravy's reserved giblets weighed off the host's turkey (AH-102: 7/85 ×
6/10, engine `hostWeighedGiblets`) on the cached 171083 hit; yuca on SR
169985 "Cassava, raw" with FNDDS 2709565's read uptake 15 %; a Parmesan
rind on 170848, discarded whole; a chopped or minced basil volume on SR
172232's chopped portion (grams.dart `fineCutSiblings`); Hershey's
Kisses on 167587 at the label's 41 g per 9; powdered pectin on 168821
at the Sure-Jell label's 4 g a teaspoon.

v69 (the Matcher v71 commit, batch M71 — step prints: printed amounts,
strained solids, kept spoonfuls, frying media; prep50 design_v2 §2 M71,
decided under the 2026-10-07 standing authorization; zero requests): an
amount-less line the steps print an amount for counts that print on its
own record (engine `stepAmountGrams`, its group's labelled steps, three
guards); "Strain the vegetables and liquid … Press the solids … Discard
the vegetables" strains (engine `_strainAt`); a strain keeping "1
tablespoon of solids" counts that part, shared by the strained lines
(engine `_keptSolidsOf`); galangal is a strained aromatic; a fat whose
steps use only printed spoonfuls of "the reserved oil" counts those
(engine `_reservedUseOf`); bacon fat added to the frying oil joins the
medium (engine `_joinsFryingOil`); the lines whisked into a coat held
with no budget are held with it (engine `_coatPartsOf`; the gates read
the same from the part's side, `_coatOfPart`).

v70 (the Matcher v72 commit, batch M72 — records, yields and rendered
fat; prep50 design_v2 §2 M72, decided under the 2026-10-07 standing
authorization; zero requests): cooked white rice on FNDDS's plain cooked
record ([_rankAs]); a cassava root weighed as bought pared at AH-102 item
496's 74 % (grams.dart `_paredAsBought`); peaches peeled at item 1654's
76 % and Brussels sprouts trimmed at item 423's 90 % (grams.dart
`produceYields`); a braised cut keeps its USDA same-cut pair's share of
the energy AND the fat columns (engine `braisedKept`) only where its
steps print that the fat is not served (engine `_defatsLiquid`) — the
whole brisket's separator, and the boneless short ribs (170827 →
171223) where their steps skim.

v71 (the Matcher v73 commit, batch M73 — flags and flavourings; prep50
design_v2 §2 M73, decided under the 2026-10-07 standing authorization;
zero requests): makrut lime leaves and the Lapsang smoking tea are
zero-nutrient flavourings ([isZeroNutrientFlavouring]); Dijon and (by the
orchestrator's ruling R1, 2026-10-18) whole-grain mustard on prepared
yellow mustard, porcini on dried shiitake and an 8-inch lumpia sheet on
SR 172802's egg-roll wrapper say they are stand-ins (engine
`trimStandInFlagOf`); "raspberries and/or blackberries" reads the cached
raw raspberries ([_rankAs]).

v72 (the Matcher v74 commit, batch M74 — the brisket flats; prep50
design_v2 §2 M74, the owner's Q1, 2026-10-15; zero requests): a 0" flat
whose steps trim its fat to a printed depth ranks the ⅛-inch flat first
and keeps its braised pair's share with no skim (engine
`trimDepthRecord`, `_trimsFatTo`, `braisedKeptOf`); the 0" flat keeps
its own braised pair 168743 → 169440 where the steps skim the fat (engine
`braisedKept`).

v73 (the Matcher v76 commit, batch M76 — eaten foods below the gate;
prep50 design_v2 §2 M76, the owner's Q3 (a) and Q4 (a); zero requests):
an unmarked line whose item is the tail of one of the recipe's own
section titles and whose amount is that section's printed yield reads
the section (engine `yieldNamesOwnSection` — the tart's "1 pound pizza
dough" its own "Classic Pizza Dough", MAKES 1 POUND); kasseri on
provolone, flagged ([_rankAs], [approximationRecords], engine
`trimStandInFlagOf`).

v74 (the Matcher v77 commit, batch M77 — extra-virgin olive oil's energy;
prep50 design_v2 §2 M77, the owner's Q5 (a); zero requests): a row on
Foundation 748608 "Oil, olive, extra virgin" (fat only, no energy) reads
SR 171413 "Oil, olive, salad or cooking"'s nutrients — 884 kcal and 100 g
fat per 100 g, not Atwater's 843.3 — and keeps its own record and grams
(engine `nutrientSiblings`).

v75 (the Matcher v78 commit, batch M78 — the C4 recipes; prep50
design_v2 §2 M78, the owner's Q6 (c) and Q7 (c); zero requests): a
pressed nut or cheese crust no step names with a crumb counts its whole
line, flagged (engine `_crustFlag`); under C4, the sauté fat a step pours
off or wipes out keeps FNDDS 2705980's 2 g oil per 125.77 g raw breast
as FAT grams, shared by the heated lines' fat (engine `_panFatLines`,
`_panFatFlag`).

v76 (the Matcher v79 commit, batch M79 — records read in L50; prep50
design_v2 §2 M79 as the planner corrected it, the orchestrator's Q9 (a)
and Q10 (b′); zero requests; replayed on snapshot 28): crystallized
ginger on SR 167781 "Candied fruit", flagged, at a Branded label's ¼ cup
(30 g; grams `_densities`) — candied peel held; the seedless watermelon
through SR 167765's nutrients and cups (engine `nutrientSiblings`, grams
`volumeSiblings`); both racks of lamb on the domestic ⅛-inch rib 174377
(engine `trimDepthRecords`' appended "trimmed" entry, grams
`ah102Meats`), deducted at the dry-heat pair their steps print (engine
`dryHeatKept`, `_dryHeatOf`).

v77 (the Matcher v80 commit, batch M80 — coats read in L50; prep50
design_v2 §2 M80 as the planner corrected it, the orchestrator's Q11 (b)
and the crumb-crust k 12.12; zero requests; replayed on snapshot 28):
the oven-fried onion rings' coat sized on the onion at FNDDS 2710042's
fried cauliflower coat, 50.53, a flagged stand-in (engine
`_coatVegetables`, `_coatFigure`); a crumb crust on a baked chicken at
FNDDS 2706442 Chicken parmigiana's separate breading inputs, 12.12 — a
nut crust beside the crumbs flagged as its stand-in (engine
`_parmigiana`, `_coatFlag`). R-G1 (a fried batter's ethanol) not built.

v78 (the Matcher v81 commit — the fixes of dual-fleet review Run 065/066
on v47–v54; zero requests; replayed on snapshot 29): a stock's aromatics
strained out and discarded stay discarded when the soup re-adds the same
vegetable — the strain check reads only the mentions no line owns
(engine `_strainedOut`; 6 rows, −170.99 kcal); the rest move no corpus
row (the alcohol reader once per index, its stop reader linear, the
coated vegetable's coat line, the un-skip, the offer, the prep note's
hash, the bounded numerics).
