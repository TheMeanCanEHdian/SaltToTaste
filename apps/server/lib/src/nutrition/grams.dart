/// Amount → grams resolution, in confidence order: a weight amount converts
/// directly; a volume amount goes through the food's own household portions,
/// falling back to a built-in density table; a count goes through piece
/// portions or a piece-weight table.
library;

import 'dart:math' show pi;

import 'package:meta/meta.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

/// How a line's grams were determined (persisted; the UI explains it).
enum GramSource {
  /// A weight amount converted directly — the gold standard.
  weight,

  /// A volume amount through the matched food's own portion data.
  portion,

  /// A volume amount through the built-in density table (estimate).
  density,

  /// A count through portion/piece-weight data (estimate).
  piece,

  /// The user typed the grams by hand.
  override,

  /// A line with no amount at all ("Lemon wedges, for serving", "Vegetable
  /// oil spray"), counted as 0 g with its food still matched (the engine's
  /// `amountlessLinesZero`, user answer #3).
  unmeasured,

  /// A cooking medium the recipe discards — deep-frying oil, a brine, a
  /// buttermilk soak — counted as 0 g (the engine's discarded-media rule
  /// and its policy switch, engine.dart `discardedMediaPolicy`).
  discarded,

  /// A sub-recipe reference line (v41, the composite row): routed, its grams
  /// the child recipe's total grams × the line's share; held or a marinade,
  /// 0 g. Never a food row (`SaltDatabase.recipeGramSource`).
  recipe,
}

/// Grams per unit of weight.
const Map<String, double> _weightUnitGrams = {
  'gram': 1,
  'g': 1,
  'kilogram': 1000,
  'kg': 1000,
  'ounce': 28.3495,
  'oz': 28.3495,
  'pound': 453.592,
  'lb': 453.592,
};

/// "crushed saltines" ([_resolveGrams]: sized by the cracker).
final RegExp _crushedSaltines = RegExp(
  r'\bcrushed saltines?\b',
  caseSensitive: false,
);

/// v37 (Z2, Z7): a weight printed in a comma clause — "1 whole side salmon
/// fillet, about 3½ pounds, white belly fat trimmed" (Broiled Salmon with
/// Mustard and Crisp Dilled Crust), "1 center-cut beef tenderloin roast, 3
/// pounds trimmed weight, 12 to 13 inches long …" (Beef Wellington): the
/// only two corpus lines it reads (census of the 13,615 rows, 2026-10-04).
final RegExp _clauseWeight = RegExp(
  ',\\s*(?:about\\s+)?([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]*)'
  r'\s+(pounds?|ounces?)(?:\s+trimmed weight)?\s*(?:,|$)',
  caseSensitive: false,
);

/// v37 (Z7): a volume line's own count of its item — "4 teaspoons minced
/// anchovy fillets (about 8 fillets)" (Spaghetti Puttanesca, the corpus's
/// only volume line whose "(about N noun)" counts its own item) — read when
/// nothing else sizes the line ([_resolveLine]).
final RegExp _parenCount = RegExp(r'\(about (\d+) ([a-z]+)\)');

/// v37 (Z7): an envelope of yeast is 2¼ teaspoons — "1 envelope (2¼
/// teaspoons) instant or rapid-rise yeast" (Multigrain Bread; Sticky Buns
/// and Chicago-Style Deep-Dish Pizza print the same pair).
const double _yeastEnvelopeTeaspoons = 2.25;

/// "(31 to 40 per pound)": a bare count's own size ([_resolveGrams]).
final RegExp _perPound = RegExp(r'\((\d+) to (\d+) per pound\)');

/// Milliliters per unit of volume.
const Map<String, double> _volumeUnitMl = {
  'teaspoon': 4.92892,
  'tsp': 4.92892,
  'tablespoon': 14.7868,
  'tbsp': 14.7868,
  'fluid ounce': 29.5735,
  'cup': 236.588,
  'pint': 473.176,
  'quart': 946.353,
  'gallon': 3785.41,
  'milliliter': 1,
  'ml': 1,
  'liter': 1000,
  'l': 1000,
};

/// Kosher salt's g/ml ([_densities]). v62 (batch M64 R-D, prep49 design_v2
/// §2 M64): half of table salt's weight by volume — the corpus prints the
/// conversion ("1 tablespoon kosher salt or 1½ teaspoons table salt",
/// twice; 0091's "¾ cup salt" with "If using Diamond Crystal kosher salt,
/// increase the salt to 1½ cups"; 16 recipes name Diamond Crystal, 12 of
/// them saying they were developed with it) — on USDA SR 173468
/// "Salt, table"'s own '1 tsp' 6.0 g: 6.0 / 4.92892 × 0.5 = 0.60865 (3.0 g
/// a teaspoon). It was a round kitchen 0.72 (3.55 g a teaspoon), which
/// flake and coarse sea salt keep ([_flakeSaltDensity]).
/// ponytail: Diamond Crystal's figure; a Morton line (⅔ of table, 4.0 g a
/// teaspoon) reads it too — the corpus means Diamond.
const double _kosherSaltDensity = 0.60865;

/// Flake and coarse sea salt's g/ml ([packsLikeKosherSalt]): the round
/// kitchen figure kosher salt had until v62 — no FDC record or corpus print
/// sizes them.
const double _flakeSaltDensity = 0.72;

/// The basis suffix of a kosher salt line weighed at [_kosherSaltDensity].
const String _kosherSaltBasis =
    " · kosher salt at half table salt's weight by volume (the corpus's own "
    '"1 tablespoon kosher salt or 1½ teaspoons table salt"; USDA SR 173468 '
    "'1 tsp' 6.0 g)";

/// Density fallbacks (g/ml) for pantry staples, keyed by tokens matched
/// against the normalized item — used only when the matched food carries no
/// usable volume portion. Values are round kitchen figures, flagged as
/// estimates in the UI.
const List<(String, double)> _densities = [
  ('all-purpose flour', 0.51),
  ('bread flour', 0.52),
  ('cake flour', 0.46),
  ('whole-wheat flour', 0.54),
  ('flour', 0.51),
  ('granulated sugar', 0.85),
  ('brown sugar', 0.93),
  ('confectioners sugar', 0.51),
  ('powdered sugar', 0.51),
  ('sugar', 0.85),
  ('butter', 0.959),
  ('milk', 1.03),
  ('buttermilk', 1.03),
  ('heavy cream', 1.01),
  ('cream', 1.01),
  // Ice cream by volume is its record's own figure (168809 'cup (4 fl oz)'
  // 66 g for half a cup), never liquid cream's 1.01 or coffee's 1.0:
  // "2 pints coffee ice cream" (0905) counted 946 g (checkpoint 9).
  ('ice cream', 0.558),
  ('sour cream', 0.97),
  ('yogurt', 1.03),
  ('water', 1.0),
  ('oil', 0.92),
  ('honey', 1.42),
  ('maple syrup', 1.32),
  ('corn syrup', 1.38),
  ('molasses', 1.41),
  ('cocoa', 0.52),
  ('espresso powder', 0.43),
  ('instant coffee', 0.43),
  ('coffee powder', 0.43),
  // One path per record (Run 052 O8/S7): 'instant coffee' only modifies
  // "instant coffee powder"'s head, so the head-noun rule weighed that one
  // line by 171893's loose 'tsp' 1.0 g while its 14 instant-espresso
  // siblings on the same record keep the table's fine-powder 0.43 (2.12
  // g/tsp): the powder's own key keeps it on the table too.
  ('instant coffee powder', 0.43),
  // v31 (Q7 misc M2): "instant espresso" on the same record (171893) keeps
  // its 13 "instant espresso powder" siblings' figure, not the record's
  // loose 'tsp' 1.0 g.
  ('instant espresso', 0.43),
  ('brewed coffee', 1.0),
  ('coffee', 1.0),
  ('cornstarch', 0.54),
  ('cornmeal', 0.66),
  ('rice', 0.85),
  ('oats', 0.41),
  ('salt', 1.22),
  ('kosher salt', _kosherSaltDensity),
  ('baking powder', 0.92),
  ('baking soda', 0.93),
  ('yeast', 0.64),
  ('vanilla', 0.88),
  ('vinegar', 1.01),
  ('wine', 0.99),
  ('broth', 1.0),
  ('stock', 1.0),
  ('ketchup', 1.14),
  ('mayonnaise', 0.91),
  ('mustard', 1.05),
  ('soy sauce', 1.16),
  ('fish sauce', 1.2),
  ('peanut butter', 1.09),
  ('ginger', 0.54),
  ('tomato paste', 1.1),
  ('lemon juice', 1.03),
  ('lime juice', 1.03),
  ('sherry', 0.99),
  ('jam', 1.35),
  // FDC 169642 "Jellies" 'serving 1 tbsp' 21 g (÷ 14.787 mL), its only
  // portion the readers cannot use. Scoped to the corpus's jellies: a bare
  // 'jelly' reached "apricot preserves or hot pepper jelly" (v21 plan).
  ('apple jelly', 1.42),
  ('currant jelly', 1.42),
  ('jalapeno jelly', 1.42),
  ('breadcrumbs', 0.45),
  ('panko', 0.25),
  ('parmesan', 0.42),
  // APPROXIMATE ([_approximateDensities]): Pecorino Romano that says
  // neither grated nor shredded on the Parmesan figure above (its records'
  // cup is 'cheese' 0.47's; a grated or shredded line weighs the printed
  // [_printedHardCheese]), and ghee on oil's (FDC 171314's detail
  // publishes no portion).
  ('pecorino', 0.42),
  ('ghee', 0.92),
  ('cheese', 0.47),
  ('nuts', 0.55),
  ('chocolate chips', 0.72),
  // Ground spices & dried herbs (g/ml). FDC files these as "Spices, X" with
  // tsp/tbsp portions, but their measure unit is "undetermined" and the unit
  // sits in an amount-less description ("tsp") — so the portion matcher can't
  // use them and they fell through to nothing. Each density is BACK-DERIVED
  // from FDC's own 1-tsp gram weight (g ÷ 4.929 mL), so a volume estimate here
  // reproduces FDC's value. Keys are chosen to beat existing shorter entries by
  // length ("ground ginger" over fresh "ginger"; "dry mustard" over prepared
  // "mustard") and, for herbs with a fresh form, gated to "dried …" so a fresh
  // sprig isn't sized as fluffy dried leaf.
  ('black pepper', 0.47),
  ('white pepper', 0.49),
  ('cayenne', 0.37),
  ('paprika', 0.47),
  // APPROXIMATE ([_approximateDensities]): ground Aleppo pepper on
  // paprika's figure (FDC has no Aleppo record; its line counts ancho).
  ('aleppo pepper', 0.47),
  ('cumin', 0.43),
  ('cinnamon', 0.53),
  ('coriander', 0.37),
  ('nutmeg', 0.45),
  ('ground cloves', 0.43), // specific, so "garlic cloves" is untouched
  ('chili powder', 0.55),
  ('allspice', 0.39),
  ('ground ginger', 0.37), // beats fresh 'ginger' (0.54) by length
  ('cardamom', 0.41),
  ('turmeric', 0.61),
  ('curry powder', 0.41),
  ('ground fennel', 0.41),
  ('fennel seed', 0.41),
  ('dry mustard', 0.41), // beats prepared 'mustard' (1.05) by length
  ('ground mustard', 0.41),
  ('mustard powder', 0.41),
  ('garlic powder', 0.63),
  ('onion powder', 0.49),
  ('dried oregano', 0.20),
  ('dried thyme', 0.20),
  ('dried basil', 0.14),
  ('dried rosemary', 0.24),
  // Whole peppercorns (sweep accuracy batch): 'black pepper' (ground) sized
  // them. FDC 170931 "Spices, pepper, black" 'tsp, whole' = 2.9 g. No whole
  // MUSTARD seed entry: FDC's only record is ground (170929, tsp = 2.0 g).
  // Prepared 'mustard' (1.05) weighed them at 2.5x that record (Run 050),
  // so a seed takes its record's own portion ([_densityOf]) until a
  // whole-seed density is sourced.
  ('peppercorn', 0.59),
  ('black peppercorn', 0.59), // beats 'black pepper' (ground) by length
  // v31 (Q7, ruled 2026-10-03): anchovy paste at 6.7 g a teaspoon, the
  // mean of ATK's two printed equivalences — "Two minced anchovy fillets
  // can be used in place of the anchovy paste" (1 tsp, Modern Beef
  // Burgundy: 2 × 4 g) and "substitute 1½ teaspoons of anchovy paste for
  // the fillets" (2 fillets, Pan-Seared Thick-Cut Boneless Pork Chops:
  // 5.3 g/tsp) — on 2706232's '1 anchovy' 4 g; flagged
  // ([_approximateDensities]).
  ('anchovy paste', 6.7 / 4.92892),
  // v37 (the queue sweep, Z5): weights per volume ATK prints, each labelled
  // with its line ([_approximateDensities]). Frozen pearl onions, 113.4 g a
  // cup: "8 ounces (about 2 cups) frozen pearl onions" (Coq au Vin,
  // Slow-Cooker Beef Burgundy) and "7 ounces (about 1¾ cups)" (Beef
  // Burgundy) agree.
  ('pearl onion', 8 * 28.3495 / (2 * 236.588)),
  // "1 cup (7 ounces) lentils, rinsed and picked over" (Hearty Lentil
  // Soup). Red lentils sit on 174284, whose own cup portion sizes them.
  ('lentil', 7 * 28.3495 / 236.588),
  // "8 cups (40 ounces) strawberries, hulled" (Strawberry Shortcakes; "4
  // cups (20 ounces)" and "6 cups (30 ounces)" agree). The plural only: a
  // 'strawberry' key would outrank 'jam' in "strawberry jam".
  ('strawberries', 40 * 28.3495 / (8 * 236.588)),
  // "12 ounces cherry or grape tomatoes (about 2½ cups)" (Pasta with Pesto
  // alla Trapanese).
  ('grape tomato', 12 * 28.3495 / (2.5 * 236.588)),
  // Z6, flagged: "6 ounces cooked chicken, torn into 1-inch pieces (1
  // cup)" — the corpus's only cooked-poultry cup; a ¼-inch dice packs
  // denser. Keyed on the one line it sizes.
  ('cooked boneless turkey or chicken meat', 6 * 28.3495 / 236.588),
  // "1½ pounds Granny Smith apples, peeled, cored, and shredded (3 cups)"
  // (Cider-Glazed Apple Bundt Cake): a purchase weight, peel and core in.
  ('granny smith apple', 1.5 * 453.592 / (3 * 236.588)),
  // Z11, flagged: jarred roasted red peppers on FDC 168559 "Pimento,
  // canned" 'cup' 192 g — item-keyed, as 2258590 carries fresh peppers too.
  ('roasted red pepper', 192 / 236.588),
  // Z15, flagged: crushed tomatoes by volume on FDC 170054 "Tomato
  // products, canned, sauce" 'cup' 245 g (chili con carne's own "or plain
  // tomato sauce"); the record 2685581 publishes no volume portion.
  ('crushed tomato', 245 / 236.588),
  // v37 (S14, the owner's answer 2026-10-04): crème fraîche counts on FDC
  // 2346386 "Cream, heavy" (flagged, matcher.dart approximationRecords),
  // weighed at the table's 'heavy cream' figure above — the record
  // publishes no volume portion and 'cream' is not a word of the item.
  ('creme fraiche', 1.01),
  // v49 (M47 Q5, amends CP9's "tapioca starch on the tapioca pearl cup"):
  // ATK's own "3 ounces (¾ cup) tapioca starch" (the All-Purpose
  // Gluten-Free Flour Blend, spooned, not packed), 113.4 g a cup — ahead of
  // the stand-in pearl record's own cup (169717, 152 g: the denser form),
  // as every key outside [_recordFirstDensities] is.
  ('tapioca starch', 3 * 28.3495 / (0.75 * 236.588)),
  // v68 (batch M70, pF F1; the owner's Q11 standing rule: a label's grams
  // for a volume the line prints): powdered pectin on SR 168821 (no volume
  // portion) at the Sure-Jell label's "1/8 tsp (0.5g)" (Kraft Heinz, FDC
  // Branded 2596757, read at L49): 4 g a teaspoon. FDC holds no label of
  // the low/no-sugar box the lines name (R-2, two spellings, 2026-10-09);
  // the other makers' boxes read 3.2–4.0 g a teaspoon. Longer than 'sugar'
  // ("no-sugar-needed"), so they win ([_tableEntry]).
  ('fruit pectin', 4 / 4.92892),
  ('sure-jell', 4 / 4.92892),
];

/// The [_densities] keys that weigh on a stand-in's figure — flagged
/// approximations the user approved (v21, J2): a line sized by one says so
/// in its basis ("· approximate (paprika density)") — or a figure ATK
/// prints, named with its source (v31).
const Map<String, String> _approximateDensities = {
  // The label names the figure used: 'parmesan' 0.42, since v23 no longer
  // grated Parmesan's (0.24) — Run 054 O16.
  'pecorino': 'Parmesan density',
  'ghee': 'oil density',
  'aleppo pepper': 'paprika density',
  'anchovy paste': 'ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste',
  // v37 (Z5, Z6, Z11, Z15).
  'pearl onion': 'ATK: 8 ounces frozen pearl onions ≈ 2 cups',
  'lentil': 'ATK: 1 cup lentils = 7 ounces',
  'strawberries': 'ATK: 8 cups strawberries = 40 ounces',
  'grape tomato': 'ATK: 12 ounces cherry or grape tomatoes ≈ 2½ cups',
  'cooked boneless turkey or chicken meat':
      'ATK: 6 ounces cooked chicken, torn = 1 cup',
  'granny smith apple':
      'ATK: 1½ pounds Granny Smith apples, peeled, cored, shredded = 3 cups',
  'roasted red pepper': 'pimento density, FDC 168559 cup 192 g',
  'crushed tomato': 'tomato sauce density, FDC 170054 cup 245 g',
  // v37 (S14): crème fraîche at heavy cream's table figure.
  'creme fraiche': 'heavy cream density',
  // v49 (M47 Q5).
  'tapioca starch': "ATK's printed 3 ounces per ¾ cup",
  // v68 (M70, Q11).
  'fruit pectin': _sureJellLabel,
  'sure-jell': _sureJellLabel,
};

/// The Sure-Jell label the pectin densities read (v68, M70 — the owner's
/// Q11; R-2 found no label of the box the lines name).
const String _sureJellLabel =
    'Sure-Jell label (Kraft Heinz, FDC Branded 2596757; the regular box — '
    'FDC holds no label of the low/no-sugar box the line names; the other '
    "makers' boxes read 3.2–4.0 g per teaspoon): ⅛ teaspoon = 0.5 g";

/// v37: the [_densities] keys that size a line only when its record has no
/// volume figure of its own — a printed figure for a portion-less record,
/// never over a record's portion: 'lentil' read "1 cup dried red lentils"
/// at 198 g over 174284's own cup, 192 g (the replay).
const Set<String> _recordFirstDensities = {
  'pearl onion',
  'lentil',
  'strawberries',
  'grape tomato',
  'cooked boneless turkey or chicken meat',
  'granny smith apple',
  'roasted red pepper',
  'crushed tomato',
};

/// Grated and shredded Parmesan and Pecorino Romano weigh what the corpus
/// prints for them — the user's Q6 ruling (a weight ATK prints wins):
/// "1 ounce Parmesan cheese, grated (½ cup)" and every other grated pair
/// (20 Pecorino lines, every Parmesan one) is 28.35 g in 118.29 mL, 0.24
/// g/mL — the table's 0.42 overweighed every "¼ cup grated" line by 75%
/// (Run 053 O2/S1) — and every shredded pair is 3 ounces a cup, 0.36 g/mL
/// ("3 ounces Parmesan, shredded (1 cup)", "1½ ounces Parmesan cheese,
/// shredded (½ cup)", "2 ounces Parmesan cheese, shredded (⅔ cup)"). Only
/// a line that says which: a bare one keeps its key's figure. 'pecorino'
/// covers "Pecorino Romano"; no corpus line names Romano alone.
const Map<String, (double, String)> _printedHardCheese = {
  'grated': (28.35 / 118.29, '1 ounce = ½ cup'),
  'shredded': (3 * 28.35 / 236.59, '3 ounces = 1 cup'),
};
const Set<String> _printedHardCheeseKeys = {'parmesan', 'pecorino'};
final RegExp _hardCheeseForm = RegExp(r'\b(grated|shredded)\b');

/// Piece weights (grams each) for common counted items, keyed by tokens.
/// A key's weight is PER counted unit as the recipe counts it — for items
/// always counted a particular way that means per slice (bread, bacon), per
/// ear (corn), per bulb (fennel), etc. Estimates, flagged as such in the UI.
const List<(String, double)> _pieceWeights = [
  ('large eggs', 50),
  ('large egg', 50),
  ('egg yolks', 17),
  ('egg yolk', 17),
  ('egg whites', 33),
  ('egg white', 33),
  ('eggs', 50),
  ('egg', 50),
  ('garlic cloves', 3),
  ('garlic clove', 3),
  ('garlic', 3),
  ('onion', 110),
  ('shallot', 30),
  ('scallions', 15),
  ('scallion', 15),
  // The matcher's synonym turns scallions into green onions before this
  // table sees the line, and 'onion' (110 g) caught them: 16 counted lines
  // at 110 g each. FDC 2709794 "Onions, green, raw" '1 whole' = 15 g.
  ('green onions', 15),
  ('green onion', 15),
  ('lemon', 58),
  ('lime', 44),
  ('orange', 131),
  ('carrot', 61),
  ('celery rib', 40),
  ('celery', 40),
  ('bay leaves', 0.2),
  ('bay leaf', 0.2),
  ('tomato', 123),
  // v39 (C3, the owner's ruling Q9 (a)): SR 170457's own 'plum tomato' (and
  // 'Italian tomato') 62 g — a plum is no round 123 g tomato, and no small
  // plum is published ("2 small plum tomatoes" read 62 g each).
  ('plum tomato', 62),
  ('potato', 213),
  ('apple', 182),
  ('banana', 118),
  // Whole tokens anchored to the head noun (audit 3, N7): 'apple' sized
  // pineapples at 91/182 g, 'garlic' (a clove) garlic heads at 3 g, and
  // 'tomato' 20 cherry tomatoes at 2,460 g. FDC SR 169124 "Pineapple, raw"
  // '1 fruit' = 905 g; 170457 'cherry' = 17 g; a head is about 50 g.
  ('pineapple', 905),
  ('cherry tomato', 17),
  ('garlic head', 50),
  ('bell pepper', 119),
  // v21: the table's own bell pepper, apple and egg yolk figures under the
  // names the corpus counts them by ("1 small green pepper", "3 Fuji, Gala,
  // or Golden Delicious apples", "2 large yolks").
  ('green pepper', 119),
  ('fuji', 182),
  ('yolk', 17),
  ('jalapeno', 14),
  ('cinnamon stick', 3),
  // Whole vegetables/fruit FDC gives no usable per-item portion for (its
  // Foundation entries carry only a ~85 g reference-serving weight).
  ('avocado', 150),
  ('english cucumber', 300),
  ('cucumber', 300),
  // FDC SR 168409 "Cucumber, with peel, raw": small (6-3/8") 158 g, medium
  // 201 g; 300 is its large (8-1/4") — 'small' read as the 300 g one.
  ('small cucumber', 158),
  ('medium cucumber', 201),
  ('zucchini', 196),
  ('leek', 89),
  ('fennel bulb', 200),
  ('fennel', 200),
  ('poblano', 45),
  ('serrano', 6),
  ('thai chile', 2),
  // v30 (Q6, ruled: a weight ATK prints in the corpus where one exists): a
  // dried pod FDC weighs only as 168570's 0.5 g bird chile, flagged
  // ([_approximatePieces]). Keyed on the DRIED item, so a fresh chile and
  // "chipotle chile in adobo" never reach them.
  ('dried new mexican chile', 7.1),
  ('dried guajillo chile', 7.1),
  // v31 (Q6, ruled 2026-10-03; each flagged, [_approximatePieces]): the
  // dried chipotle by its corpus-printed volume; whole spices, lemongrass
  // and lasagna sheets by a reference or manufacturer figure. Every key is
  // the whole item phrase, so "chipotle chile in adobo", a garlic clove
  // ('whole clove' is never garlic) and lemongrass paste never reach one.
  ('dried chipotle chile', 4.6),
  ('peppercorn', 0.05),
  ('whole clove', 0.1),
  ('allspice berry', 0.1),
  // 'pods' is a count word to the head noun ("cardamom pods" is cardamom)
  // while a lone "pod" is the head: each spelling keys its own.
  ('cardamom pods', 0.2),
  ('cardamom pod', 0.2),
  ('coriander seed', 0.01),
  ('star anise pods', 0.5),
  ('star anise pod', 0.5),
  ('lemongrass', 10),
  ('lemongrass stalk', 10),
  ('lemon grass stalk', 10),
  // v44 (S5 a): "2 stalks lemon grass" (thai-green-curry's Green Curry
  // Paste) and "4 pods star anise" (the unit leaked into the item,
  // roast-fresh-ham's glaze) — the same figures under their own words.
  ('lemon grass', 10),
  ('pod star anise', 0.5),
  // The longer key wins: a no-boil sheet is thinner than a curly one.
  ('no-boil lasagna noodle', 17),
  ('lasagna noodle', 25),
  // v31 (Q7 misc, ruled): a cornichon by its corpus-printed volume, a
  // Cubanelle by its corpus-printed weight (the Q7 stand-in record, 169394
  // "Pepper, banana", weighs a medium one 46 g).
  ('cornichon', 3.2),
  ('cubanelle pepper', 99),
  ('eggplant', 300), // longer key than "egg", so it wins the substring match
  // Counted-in-slices/sheets staples (per counted unit).
  ('sandwich bread', 28),
  // v51 (M49 Q4 b, re-rules the unsourced 24 g of d614c2e): SR 168277
  // "Pork, cured, bacon, unprepared" weighs its own 'slice raw' 28 g (the
  // corpus's "1 ounce a slice", 28.35 g, agrees to 1.3 %); a thick-cut
  // slice is the corpus's printed one, the median of its three prints
  // ("10 ounces (about 8 slices)" 35.44 g, "6 ounces … (about 5 slices)"
  // 34.02, "5 ounces (about 3 slices)" 47.25), flagged
  // ([_approximatePieces]); SR 167869 "Canadian bacon, unprepared" weighs
  // '2 slices (6 per 6-oz pkg.)' 57 g. The longer key wins, so a
  // thick-cut or Canadian slice never reads the plain one.
  ('bacon', 28),
  ('thick-cut bacon', 35.44),
  ('canadian bacon', 28.5),
  ('corn tortilla', 26),
  ('tortilla', 26),
  ('hamburger bun', 52),
  // "4 hamburger rolls" (0576): SR 172796 "Rolls, hamburger or hotdog,
  // plain" gives its roll as 'roll 1 serving' = 44 g, a portion no step
  // reads (checkpoint 6: 208 g on a multigrain bun went to no grams).
  ('hamburger roll', 44),
  // v32 (the live step's check M4, met): "4 brioche buns" (crispy-fish-
  // sandwiches) on FNDDS 2707682 "Brioche", whose detail weighs a bun only
  // as "1 piece" 77 g — a portion [_portionServingWords] reads as a dish
  // serving, never one item (4 × 77 = 308 g; the check's 50–80 g a bun).
  ('brioche bun', 77),
  // v35: SR 169255 "Mushrooms, portabella, raw" weighs one as '1 piece
  // whole' 84 g — a portion [_portionServingWords] reads as a dish serving
  // (and its unit is null). Two keys: [_pieceLookup] anchors on the head
  // noun ("1 large portobello mushroom cap", "6–8 portobello mushrooms").
  ('portobello mushroom', 84),
  ('portobello mushroom cap', 84),
  // v38 (the live step's checks, met on the records' real portions; the
  // whole-item finder reads neither): SR 168434 "Mushrooms, brown, italian,
  // or crimini, raw" weighs one as 'piece whole' 20 g — 'piece' is a dish
  // serving word ("24 cremini mushrooms, trimmed"); SR 172718 "Cookies,
  // chocolate sandwich, with creme filling, regular" weighs '3 cookie' 36 g
  // — a count of three, never one item ("16 Oreo cookies"): 12 g a cookie.
  ('cremini mushroom', 20),
  ('oreo cookies', 12),
  // "6 burger buns" matched the right roll and had no grams (audit 4).
  ('burger bun', 52),
  ('english muffin', 60),
  ('graham cracker', 14),
  ('ladyfinger', 11),
  ('phyllo', 19), // per sheet
  ('phyllo sheet', 19), // 'sheet' is the head of "phyllo sheets"
  ('puff pastry', 245), // per sheet (a standard frozen sheet)
  ('vanilla bean', 4),
  // v37 (Z8): ATK's own DIY bitters sugar cubes in Champagne Cocktail — "¾
  // cup sugar" MAKES 64 CUBES — on 746784's 'cup' 188 g (2.2 g a cube).
  ('sugar cube', 2.2),
  // v37 (Z9, the owner's ruling 2026-10-04): "1½ pounds large sea scallops
  // (16 to 24 scallops)" (Pan-Seared Scallops with Wilted Spinach) — 680 g
  // over 20. The corpus also prints 30.2 g ("sold 10 to 20 per pound") and
  // 42.5 g ("1½ pounds … (about 16)").
  ('sea scallop', 34.0),
  // v37 (Z13): FDC 172802's own 'wrapper, wonton (3-1/2" square)' 8 g —
  // ATK: "gyoza-style wrappers and wonton wrappers both made terrific
  // potstickers" (Pork and Cabbage Dumplings); a round disc is smaller.
  ('gyoza wrapper', 8),
  // v49 (M47 Q12, re-rules v21 R09's "STAY DRY" under CP9 Q6): FNDDS
  // 2709239 "Kiwi fruit, raw" '1 fruit' 75 g — the corpus prints no kiwi
  // weight, and the lines sit on Foundation 2710831 (a 140 g racc only). A
  // cross-record piece weight, like a [volumeSiblings] row; a sized line
  // says the size is not published ([_unsizedPieces]). Each spelling keys
  // its own: the head noun of "kiwis" is not "kiwi".
  ('kiwis', 75),
  ('kiwi', 75),
  // v68 (batch M70, pF F6; the owner's Q11 standing rule: a label's grams
  // for a count the line prints): The Hershey Company's plain milk-chocolate
  // Kisses labels (FDC Branded, read at live step L49) print 41 g = 9 pieces
  // on five items (1642930, 1646330, 1643997, 1643992, 1644692) and 32 g =
  // 7 pieces on three 2023 ones (4.57 g, 0.3 % apart); 1198's "12-ounce bag
  // … a few left over" bounds 62 Kisses below 5.49 g each. The plural key,
  // as 'oreo cookies': the head noun is 'kisses'.
  ('hershey s kisses', 41 / 9),
];

/// v49 (M47 Q12): [_pieceWeights] keys whose figure is one unsized fruit —
/// a line naming a size in its head ("2 large kiwis, peeled, …") reads it,
/// flagged "approximate ({figure}; no {size} size published)".
const Map<String, String> _unsizedPieces = {
  'kiwis': 'one fruit, FNDDS 2709239: 75 g',
  'kiwi': 'one fruit, FNDDS 2709239: 75 g',
};

/// The [_pieceWeights] keys whose figure is ATK's printed weight, not
/// FDC's: a line sized by one says so in its basis ("· approximate (ATK: …)").
const Map<String, String> _approximatePieces = {
  // chili-con-carne: "3 medium New Mexican pods (about ¾ ounce)".
  'dried new mexican chile': 'ATK: 3 medium New Mexican pods ≈ ¾ ounce',
  // goan-pork-vindaloo: "4 large dried guajillo chiles … (about 1 ounce)".
  'dried guajillo chile': 'ATK: 4 large dried guajillo chiles ≈ 1 ounce',
  // pollo-en-mole-poblano: "½ dried chipotle chile … (scant tablespoon)" on
  // 168570's cup (37 g).
  'dried chipotle chile': 'ATK: ½ dried chipotle chile ≈ a scant tablespoon',
  // Reference figures for one whole dried piece (q6 §2).
  'peppercorn': 'reference figure: a whole peppercorn',
  'whole clove': 'reference figure: a whole clove',
  'allspice berry': 'reference figure: a whole allspice berry',
  'cardamom pods': 'reference figure: a green cardamom pod',
  'cardamom pod': 'reference figure: a green cardamom pod',
  'coriander seed': 'reference figure: a coriander seed',
  'star anise pods': 'reference figure: a whole star anise',
  'star anise pod': 'reference figure: a whole star anise',
  // "1 stalk ≈ 2 tablespoons minced" × 168573's tbsp 4.8 g (q6 §6).
  'lemongrass': 'reference figure: a stalk trimmed to its bottom 5–6 inches',
  'lemongrass stalk':
      'reference figure: a stalk trimmed to its bottom 5–6 inches',
  'lemon grass stalk':
      'reference figure: a stalk trimmed to its bottom 5–6 inches',
  'lemon grass': 'reference figure: a stalk trimmed to its bottom 5–6 inches',
  'pod star anise': 'reference figure: a whole star anise',
  // Barilla Oven-Ready Lasagne, the brand the corpus prefers: 9 oz (255 g),
  // "at least 15 sheets" (barilla.com no-boil FAQ); label 3 sheets = 51 g.
  'no-boil lasagna noodle':
      'Barilla: a 9-ounce box of at least 15 sheets; 3 sheets = 51 g',
  // Ronzoni No. 80 Lasagna (1 lb): label 2 pieces = 50 g (ronzoni.com).
  'lasagna noodle': 'Ronzoni: 2 pieces = 50 g dry',
  // austrian-style-potato-salad: "6 cornichons, minced (about 2
  // tablespoons)" on 2710078's cup (155 g).
  'cornichon': 'ATK: 6 cornichons ≈ 2 tablespoons minced',
  // eggs-piperade: "3 cubanelle peppers (3 to 4 ounces each)".
  'cubanelle pepper': 'ATK: a Cubanelle pepper ≈ 3 to 4 ounces',
  // v32: FNDDS 2707682 publishes '1 piece' 77 g and no bun portion; the
  // piece is read as one bun — an assumption, so the basis says so.
  'brioche bun': "FDC's 1-piece portion read as one bun",
  // v35: a whole portobello's portion, read as one stemmed cap whatever its
  // printed size.
  'portobello mushroom': "FDC's 'piece whole' portion read as one portobello",
  'portobello mushroom cap': "FDC's 'piece whole' portion read as one cap",
  // v38.
  'cremini mushroom': "FDC's 'piece whole' portion read as one cremini",
  // v37.
  'sugar cube': 'ATK: ¾ cup sugar makes 64 cubes',
  'sea scallop': 'ATK: 1½ pounds large sea scallops ≈ 16 to 24',
  'gyoza wrapper': "FDC's 3½-inch square wonton wrapper, ATK's substitute",
  // v51 (M49 Q4 b): the CP9 Q6 corpus-print class.
  'thick-cut bacon': "the corpus's printed thick-cut slice, median of three",
  // v68 (M70, Q11): the maker's label.
  'hershey s kisses':
      "Hershey's label: 9 pieces = 41 g (FDC Branded 1642930 and four more; "
      'three 2023 labels print 7 pieces = 32 g)',
};

/// v31 (Q6, ruled 2026-10-03): pieces FDC weighs by no length, sized by
/// the "(N-inch)" or "about N inches long" the line prints × a per-inch
/// figure ([_perInchGrams]), flagged with its source. Item word → (the
/// units it is counted in, g per inch, the record it must be on, label).
const Map<String, (Set<String>, double, String, String)> _perInch = {
  // "1 (1-inch) piece fresh ginger, grated (about 1 tablespoon)" (Roast
  // Fresh Ham; Strawberries and Grapes agrees): the table's ginger 0.54
  // g/mL × 1 tablespoon. Fresh root only: ground and crystallized ginger
  // sit on other records.
  'ginger': (
    {'', 'piece'},
    8,
    'ginger root',
    'ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon',
  ),
  // "10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup)"
  // (Crispy Orange Beef) on 169103's tbsp (6 g): 2.4 g a 3-inch strip.
  'orange zest': (
    {'strip'},
    0.8,
    'orange peel',
    'ATK: 10 (3-inch) strips orange peel ≈ ¼ cup',
  ),
  // The orange figure extended: 167749 lemon peel's portions equal it.
  'lemon zest': (
    {'strip'},
    0.8,
    'lemon peel',
    'the orange-peel strip figure, extended to lemon',
  ),
  // v37 (Z10): FDC 2707610's own '1 baguette (about 22" long)' 324 g, 14.73
  // g an inch ("1 (3-inch) piece baguette", Garlicky Shrimp with Buttered
  // Bread Crumbs).
  'baguette': (
    {'piece'},
    14.73, // 324 g ÷ 22 inches
    'bread, french',
    'FDC: 1 baguette (about 22" long) = 324 g',
  ),
  // v37 (S4, flagged — the line sits on ginger root by its rank-as item):
  // galangal at fresh ginger's figure above, ATK's own substitute ("If
  // galangal is unavailable, substitute fresh ginger", Guay Tiew Tom Yum
  // Goong).
  'galangal': (
    {'', 'piece'},
    8,
    'ginger root',
    "ginger's figure (ATK's substitute for galangal)",
  ),
};

/// v61 (M63 P10, the owner's ruling 2026-10-08, outcome B): a round counted
/// by its printed "(N-inch)" diameter on the record publishing the per-AREA
/// portion — FNDDS 2707616's own '1 surface inch' 2.0 g × π (N/2)² (an
/// 8-inch pita 100.53 g; [_perAreaGrams]), flagged "derived". Item word →
/// (the units it is counted in, g per square inch, the fdcId it must be on
/// — that record alone, never a description prefix: the other 'Bread,
/// pita…' records publish no surface inch and SR 174915 prints its own
/// 4" / 6½" pitas — label).
/// ponytail: pita only — prosciutto 2705879 and the FNDDS records
/// 2707997, 2708006–09, 2708750 and 2709129 print a surface inch too, but
/// no corpus "(N-inch)" count line sits on them; the flour tortilla 2707824
/// prints none (the "(N-inch) flour tortillas" sibling is a later item).
const Map<String, (Set<String>, double, int, String)> _perArea = {
  'pitas?': (
    {'', 'piece'},
    2.0,
    2707616,
    "derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the printed "
        "diameter's area",
  ),
};

/// "(4-inch)", "(1½-inch piece)", "about 3 inches long" — the printed
/// length [_perInch] scales by.
final RegExp _printedLength = RegExp(
  '\\(([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]*)-inch\\b|'
  '\\babout ([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]*) '
  r'inch(?:es)? long\b',
);

/// The grams of ONE counted piece of [normalizedItem] by its printed
/// length ([_perInch]) and its label, or null: the item names the key, the
/// line counts in one of its units, [food] is its record and [raw] prints
/// a length.
({double grams, double inches, double perInch, String label})? _perInchGrams(
  String normalizedItem,
  String? raw,
  String unit,
  FdcFood? food,
) {
  if (raw == null || food == null) {
    return null;
  }
  // v37 (Z3): a strip the corpus kept in the item ("3 (2-inch) strips
  // orange zest", Monkfish Tagine: the count 3, no unit) is counted in
  // strips all the same.
  final counted =
      unit.isEmpty && RegExp(r'\bstrips?\b').hasMatch(normalizedItem)
      ? 'strip'
      : unit;
  for (final MapEntry(:key, value: (units, perInch, record, label))
      in _perInch.entries) {
    if (!units.contains(counted) ||
        !RegExp('\\b$key\\b').hasMatch(normalizedItem) ||
        !food.description.toLowerCase().startsWith(record)) {
      continue;
    }
    final m = _printedLength.firstMatch(raw);
    final inches = m == null ? null : _quantityValue((m[1] ?? m[2]!).trim());
    return inches == null
        ? null
        : (
            grams: inches * perInch,
            inches: inches,
            perInch: perInch,
            label: label,
          );
  }
  return null;
}

/// The grams of ONE counted round of [normalizedItem] by its printed
/// "(N-inch)" diameter ([_perArea]) — never "about N inches long", a
/// length — with the diameter, its area and the figure's label, or null.
({double grams, double inches, double area, double perSqIn, String label})?
_perAreaGrams(String normalizedItem, String? raw, String unit, FdcFood? food) {
  if (raw == null || food == null) {
    return null;
  }
  for (final MapEntry(:key, value: (units, perSqIn, record, label))
      in _perArea.entries) {
    if (!units.contains(unit) ||
        !RegExp('\\b$key\\b').hasMatch(normalizedItem) ||
        food.fdcId != record) {
      continue;
    }
    final d = _printedLength.allMatches(raw).map((m) => m[1]).nonNulls;
    final inches = d.isEmpty ? null : _quantityValue(d.first.trim());
    if (inches == null) {
      return null;
    }
    final area = pi * (inches / 2) * (inches / 2);
    return (
      grams: area * perSqIn,
      inches: inches,
      area: area,
      perSqIn: perSqIn,
      label: label,
    );
  }
  return null;
}

/// v31 (Q6, ruled): scallions in a bunch — a reference count of 7 × the
/// piece table's FDC scallion (2709794 '1 whole' 15 g). Any other bunch
/// (herbs) keeps its skip.
const Map<String, int> _perBunch = {'green onion': 7, 'scallion': 7};

/// The grams of one counted [key] in the piece table ('egg' 50, 'egg yolk'
/// 17, 'egg white' 33), or null.
double? pieceWeightOf(String key) => _tableLookup(_pieceWeights, key);

/// SR records whose volume portions size a volume line on a record that
/// publishes none — a sibling's detail is read from the cache, or fetched
/// once when none holds it (engine.dart gramsFor) (checkpoint 5: 96 of 121
/// volume no_grams lines sat on portion-less Foundation records). The food
/// and its nutrients stay the line's; only the grams per volume come from
/// the sibling.
const Map<int, int> volumeSiblings = {
  // Onions, yellow / red, raw (Foundation: an edible onion and racc only) →
  // Onions, raw: "cup, chopped" 160 g, "tbsp chopped" 10 g.
  790646: 170000,
  790577: 170000,
  // Nuts, pistachio nuts, raw (Foundation, racc only) → dry roasted: "cup"
  // 123 g.
  2515379: 170185,
  // Nuts, coconut meat, dried (desiccated), not sweetened (an "oz" portion
  // only) → its sweetened shredded sibling: "cup, shredded" 93 g.
  170170: 168586,
  // Blueberries, raw (Foundation, racc only) → FNDDS "Blueberries, frozen":
  // "1 cup" 150 g. The 'or frozen blueberry' leak fix moved "1 cup fresh or
  // frozen blueberries" (0745) onto the raw record and Blueberry Pancakes
  // lost complete (checkpoint 6).
  2346411: 2709277,
  // Nuts, almonds, whole, raw (Foundation, no volume portion) → SR "Nuts,
  // almonds": "cup, whole" 143 g ('1¼ cups whole almonds', Almond Biscotti;
  // checkpoint 8).
  2346393: 170567,
  // Matcher v17 (checkpoint 8): Foundation records that publish a racc
  // portion only → their SR record's volume portions. Each sibling's detail
  // is fetched once, by the first volume line that needs it (the approved
  // requests).
  2346395: 170182, // Nuts, pecans, halves, raw → Nuts, pecans
  1104647: 169230, // Garlic, raw → Garlic, raw (SR)
  2346407: 169975, // Cabbage, green, raw → Cabbage, raw
  2258586: 170393, // Carrots, mature, raw → Carrots, raw
  2346405: 169988, // Celery, raw → Celery, raw (SR)
  1999632: 168462, // Spinach, baby → Spinach, raw
  2346388: 169248, // Lettuce, iceberg, raw → …iceberg (includes crisphead)
  // Cabbage, napa, leaf, destemmed, raw → Cabbage, chinese (pe-tsai), raw —
  // already its nutrient sibling (engine.dart nutrientSiblings).
  2727583: 169979,
  // v32 (the live step, 2026-10-03 — each detail read and its volume
  // portion checked): Tamarind (FNDDS, '1 tamarind' 2 g only) → Tamarinds,
  // raw, "cup, pulp" 120 g (tamarind paste ×2, tamarind juice
  // concentrate); Eggs, Grade A, Large, egg whole (Foundation, no portion)
  // → Egg, whole, raw, fresh, "cup (4.86 large eggs)" 243 g ("2
  // tablespoons beaten egg").
  2709269: 167763,
  748967: 171287,
  // v37 (Z10): Olives, green, Manzanilla, stuffed with pimiento (Foundation,
  // olive and racc portions only) → FNDDS "Olives, green" '1 cup' 135 g;
  // Peppers, jalapeno, seeded, raw (Foundation) → FNDDS "Peppers,
  // jalapenos" '1 cup' 150 g. Both details cached.
  332791: 2710089,
  2747661: 2710096,
  // v38 (the owner's live step, 2026-10-04 — each detail read and its cup
  // portion checked): Radicchio (Foundation) → SR "Radicchio, raw" 'cup,
  // shredded' 40 g; Cauliflower (Foundation) → SR "Cauliflower, raw" 'cup
  // chopped (1/2" pieces)' 107 g; canned chickpeas, sodium added (2644288,
  // no cup) → SR "…canned, drained, rinsed in tap water" 'cup drained,
  // rinsed' 152 g. Raw cashews STAY DRY: SR 170162 "Nuts, cashew nuts, raw"
  // publishes 'oz' 28.35 g only — no cup (the zero-request fallback,
  // 2707498 honey-roasted cup 130 g, flagged, is the owner's call).
  2747664: 168564,
  2685573: 169986,
  2644288: 173801,
  // 2515374: 170162,
  // v45 (option A's three seed details, snapshot 20): Foundation 2515380
  // "Seeds, pumpkin seeds (pepitas), raw" and 2515381 "Seeds, sunflower
  // seed, kernel, raw" publish a 30 g racc only, SR 170151 "Seeds, sesame
  // seeds, whole, roasted and toasted" an 'oz' only → the cups the main
  // library's seed lines already read: SR 169415 roasted pepitas 'cup'
  // 118 g, SR 170154 toasted sunflower kernels 'cup' 134 g, FNDDS 2707586
  // "Sesame seeds" '1 cup' 128 g (all cached).
  2515380: 169415,
  2515381: 170154,
  170151: 2707586,
};

/// v68 (batch M70, pE Q6; prep49 design_v2 §2 M70): records whose volume
/// portions name no cut → the SR sibling that prints a CHOPPED one. FNDDS
/// 2709780 "Basil, raw" ('1 cup' 24 g = SR's 'cup leaves, whole', '1
/// tablespoon' 3 g, its cut unstated) → SR 172232 "Basil, fresh" ('tbsp,
/// chopped' 5.3 g at amount 2: 2.65 g a tablespoon, 42.40 g a cup; the two
/// records print the same composition). A fine-cut volume line weighs on
/// the sibling's chopped portion ([fineCutWeighing]); the food and its
/// nutrients stay the line's; a whole, torn or shredded line keeps its own.
const Map<int, int> fineCutSiblings = {2709780: 172232};

/// [food] carrying only [sibling]'s chopped portions ([_choppedPortion]) —
/// what a fine-cut ([_fineCut], "minced" read as chopped since checkpoint
/// 5) volume line ([raw], [amounts]) on a [fineCutSiblings] record weighs
/// on, through the shipped resolver — and the basis note naming the
/// portion; null for any other line, or a sibling with no chopped portion.
({FdcFood food, String note})? fineCutWeighing(
  FdcFood food,
  FdcFood sibling,
  String raw,
  List<Amount> amounts,
) {
  final chopped = [
    for (final portion in sibling.portions)
      if (_choppedPortion.hasMatch((portion.description ?? '').toLowerCase()))
        portion,
  ];
  if (chopped.isEmpty ||
      volumeMlOf(amounts) == null ||
      !_fineCut.hasMatch(raw.toLowerCase())) {
    return null;
  }
  final cut = FdcFood(
    fdcId: food.fdcId,
    description: food.description,
    dataType: food.dataType,
    nutrientsPer100g: food.nutrientsPer100g,
    portions: chopped,
  );
  final perMl = _foodGramsPerMl(cut);
  if (perMl == null) {
    return null;
  }
  final perTbsp = perMl * _volumeUnitMl['tablespoon']!;
  final portion = chopped.first;
  final amount = _figure(portion.amount ?? 1);
  return (
    food: cut,
    note:
        'chopped: ${perTbsp.toStringAsFixed(2)} g per tablespoon — USDA SR '
        '${sibling.fdcId} "${sibling.description}" '
        "'${portion.description}' × $amount = "
        '${_figure(portion.gramWeight)} g',
  );
}

/// Descriptor words that mark a RUSTIC/artisan loaf — thick, dense, crusty —
/// distinct from soft sandwich bread (which keeps its 28 g/slice table entry).
/// FDC gives these breads no usable per-slice or per-loaf portion, and the flat
/// [_pieceWeights] table can't serve them: a recipe counts them BOTH ways
/// ("8 slices country bread", "1 loaf crusty bread"), which need different
/// weights, and its substring keys wouldn't match "country WHITE bread" anyway.
const Set<String> _rusticBreadWords = {
  'rustic',
  'country',
  'crusty',
  'artisan',
  'peasant',
  'sourdough',
  'ciabatta',
  'baguette',
  'french',
  'italian',
};

const Set<String> _sliceUnits = {'slice', 'slices'};
const Set<String> _loafUnits = {'loaf', 'loaves'};

/// Grams per counted unit for a rustic/artisan bread, by the unit the recipe
/// used: a thick artisan SLICE ≈ 50 g (ATK's own "(9 ounces)" for 5 slices is
/// ~51 g/slice), a whole LOAF ≈ 454 g (its standard "1 (1-pound) loaf"). Only
/// for the crusty/rustic breads above; returns null for soft sandwich bread
/// (handled by the piece table) and for any non-slice/loaf unit. An estimate,
/// flagged as such — and only a FALLBACK: a real FDC slice/loaf portion is
/// preferred (matched earlier in the count loop).
double? _rusticBreadGrams(String normalizedItem, String unit) {
  final looksBread =
      normalizedItem.contains('bread') ||
      normalizedItem.contains('ciabatta') ||
      normalizedItem.contains('baguette');
  if (!looksBread || !_rusticBreadWords.any(normalizedItem.contains)) {
    return null;
  }
  if (_loafUnits.contains(unit)) {
    return 454;
  }
  if (_sliceUnits.contains(unit)) {
    return 50;
  }
  return null;
}

/// Result of a resolution attempt.
class GramResolution {
  /// Pairs the resolved grams with how they were determined.
  const GramResolution({
    required this.grams,
    required this.source,
    this.basis,
  });

  /// Resolved grams for the whole line.
  final double grams;

  /// How [grams] was determined.
  final GramSource source;

  /// A short, human-readable description of the INPUT the estimate ran
  /// against — so a reviewer can sanity-check it (e.g. "½ cup ≈ 118 mL" for a
  /// density estimate, or "8¾ ounces" for a direct weight). Null when there is
  /// nothing to show. Not stored; re-derived for display.
  final String? basis;
}

/// A figure as written: "8", "0.8", "1.5" (v31's per-inch and sub-gram
/// piece bases).
String _figure(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toString();

/// The amount as written, for a [GramResolution.basis] label ("½ cup", "2",
/// "pinch" — a quantity-less pinch wrote ' pinch', checkpoint 5).
String _amountText(Amount amount) {
  final unit = amount.unit;
  return (unit == null || unit.isEmpty
          ? amount.quantity
          : '${amount.quantity} $unit')
      .trim();
}

/// The grams of a parenthetical weight in [raw] (see [_parenWeight]).
double? parenWeightGrams(String raw) => _parenWeight(raw)?.grams;

double? _quantityValue(String quantity) =>
    parseQuantity(quantity) ?? _range(quantity)?.value;

final _rangePattern = RegExp(
  r'^\s*(\d+\s+\d+/\d+|\S+?)\s*(?:-|–|to)\s*(\d+\s+\d+/\d+|\S+)\s*$',
);

/// A range [quantity] — "4-6", "4 to 6", a mixed-number bound "1 1/2–2"
/// (0471's juice, checkpoint 6), "3–3 1/2" — read at its MIDPOINT, every
/// spelling (M48, re-ruling checkpoint 9 Q5's "upper bound in parentheses":
/// the auditors read the midpoint on 9 of 9 ranged lines), with its bounds
/// as printed ("5–7") for the basis. Reversed bounds keep the larger and
/// print nothing: "(14⅔ to 6½ ounces) bread flour" is a corpus typo for
/// 16½, and 6½ ounces is not 2⅔–3 cups. Null when not a range.
({double value, String? printed})? _range(String quantity) {
  final match = _rangePattern.firstMatch(quantity);
  final low = match == null ? null : parseQuantity(match[1]!);
  final high = match == null ? null : parseQuantity(match[2]!);
  if (low == null || high == null) {
    return null;
  }
  return low > high
      ? (value: low, printed: null)
      : (value: (low + high) / 2, printed: '${match![1]}–${match[2]}');
}

/// The printed bounds of a [quantity] read at a range's midpoint ("5–7"),
/// for the basis (M48); null for a single figure or reversed bounds.
String? _midpointBounds(String quantity) =>
    parseQuantity(quantity) == null ? _range(quantity)?.printed : null;

/// The line's volume in mL — its first volume amount — or null.
double? volumeMlOf(List<Amount> amounts) {
  for (final amount in _byPreference(amounts)) {
    final ml = _volumeUnitMl[(amount.unit ?? '').toLowerCase()];
    final quantity = _quantityValue(amount.quantity);
    if (amount.measure == Measure.volume && ml != null && quantity != null) {
      return quantity * ml;
    }
  }
  return null;
}

/// The line's weight in grams — its first weight amount — or null (as
/// [volumeMlOf] reads a volume).
double? weightGramsOf(List<Amount> amounts) {
  for (final amount in _byPreference(amounts)) {
    final perUnit = _weightUnitGrams[(amount.unit ?? '').toLowerCase()];
    final quantity = _quantityValue(amount.quantity);
    if (amount.measure == Measure.weight &&
        perUnit != null &&
        quantity != null) {
      return quantity * perUnit;
    }
  }
  return null;
}

/// The FIRST count amount's numeric value ("2 cans" -> 2), or null.
double? countOf(List<Amount> amounts) => _countQty(amounts);

double? _countQty(List<Amount> amounts) {
  for (final amount in amounts) {
    if (amount.measure == Measure.count) {
      final quantity = _quantityValue(amount.quantity);
      if (quantity != null) {
        return quantity;
      }
    }
  }
  return null;
}

/// Grams from the first weight printed in a raw parenthetical — the PER-unit
/// weight the amount parse missed. "(5 to 6-ounce)" -> 156 g, "(28-ounce)" ->
/// 794 g, "(about 8 ounces)" -> 227 g. Null when no parenthetical weight.
/// A weight printed in a raw parenthetical, and whether it reads PER counted
/// unit or as the line TOTAL.
///
/// Adjectival, before the food noun → per unit: "4 (5-ounce) breasts",
/// "2 (15-ounce) cans", "1 (1-pound) loaf" (and an explicit "(… each)").
/// Trailing, after the noun → total: "5 slices bread (9 ounces)",
/// "1 potato (about 8 ounces)". The distinction only changes the result when
/// the line is counted >1 — a trailing total was over-scaled by the count
/// before ("5 slices … (9 ounces)" read as 5×, a ~5× error).
/// A range reads its midpoint ([_range]) and names itself, "5–7 oz" (M48).
({double grams, bool perUnit, String? range})? _parenWeight(String raw) {
  // A bound: an ASCII mixed number "3 1/2", as the editor and other
  // libraries print it (without it "(3 1/2- to 4-pound)" read ½ to 4 at its
  // midpoint, M48 closer 2), else one token: "3½", "1/2", "4".
  final number = '(?:\\d+\\s+\\d+/\\d+|[\\d./$vulgarFractionChars]+)';
  final weight = RegExp(
    // Unicode fractions too: "(1¼- to 1½-pound)" Cornish hens read 80 g
    // through a per-item portion, "(3½-pound)" roasts nothing (audit 1). The
    // hyphen before "to" is part of the range: without it "(3½- to
    // 4-pound)" read only "4-pound". The en dash too (M48): "(12–22 pounds
    // gross weight)" read only "22 pounds".
    '($number(?:\\s*(?:-?\\s*to|-|–)\\s*$number)?)\\s*-?\\s*'
    r'(ounces?|oz|pounds?|lbs?|grams?|kilograms?|kg)\b',
    caseSensitive: false,
  );
  for (final paren in RegExp(r'\(([^)]*)\)').allMatches(raw)) {
    // A mixed number spaced "3 ½" is "3½" (M48: "(3 ½- to 4-pound)",
    // Pressure-Cooker Pot Roast, would read ½ to 4 at its midpoint).
    final inner = paren
        .group(1)!
        .replaceAllMapped(
          RegExp('(\\d)\\s+([$vulgarFractionChars])'),
          (m) => '${m[1]}${m[2]}',
        );
    final match = weight.firstMatch(inner);
    if (match == null) {
      continue;
    }
    // "3½- to 4" reads as "3½ to 4".
    final text = match.group(1)!.replaceAll(RegExp(r'-\s*to'), ' to');
    final quantity = _quantityValue(text);
    final unit = match.group(2)!.toLowerCase().replaceAll(RegExp(r's$'), '');
    final printed = _midpointBounds(text);
    final gramsPer = _weightUnitGrams[unit];
    if (quantity == null || gramsPer == null) {
      continue;
    }
    // Per unit iff the parenthetical is adjectival — nothing but the leading
    // count precedes it (no food noun, i.e. no letters) — or it says "each".
    final before = raw.substring(0, paren.start);
    final perUnit =
        inner.toLowerCase().contains('each') ||
        !RegExp('[a-z]', caseSensitive: false).hasMatch(before);
    return (
      grams: quantity * gramsPer,
      perUnit: perUnit,
      range: printed == null ? null : '$printed ${_unitShort[unit] ?? unit}',
    );
  }
  // The per-unit weight written in the item with no parenthesis: "1
  // 5-pound boneless pork butt roast" (Indoor Pulled Pork with Sweet and
  // Tangy Barbecue Sauce; checkpoint 8) — and in ounces, as other
  // libraries print a package ("1 15-ounce can chickpeas"; ATK always
  // parenthesizes it — kept for them, Run 048).
  final inItem = RegExp(
    '^\\s*[\\d$vulgarFractionChars/.]+\\s+([\\d$vulgarFractionChars/.]+)-'
    r'(ounces?|pounds?)\b',
    caseSensitive: false,
  ).firstMatch(raw);
  final quantity = inItem == null ? null : _quantityValue(inItem[1]!);
  if (quantity == null) {
    return null;
  }
  final unit = inItem![2]!.toLowerCase().replaceAll(RegExp(r's$'), '');
  return (
    grams: quantity * _weightUnitGrams[unit]!,
    perUnit: true,
    range: null,
  );
}

const _unitShort = {
  'ounce': 'oz',
  'pound': 'lb',
  'gram': 'g',
  'kilogram': 'kg',
};

/// The piece weight for [normalizedItem]: a key matches on WHOLE words
/// (key form), and its last word must be the item's head noun — 'apple' is
/// not in 'pineapple', and 'garlic' is not the food of 'mustard-garlic
/// butter'. The size and 'head' words normalizing strips are read back from
/// [raw] and the amount's [unit] ("1 garlic head", "1 small cucumber").
(String, double)? _pieceLookup(
  String normalizedItem,
  String? raw,
  String unit,
) {
  final alternatives = normalizedItem.split(' or ');
  final heads = {for (final item in alternatives) headNounOf(item)};
  final rawWords = (raw ?? '').toLowerCase().split(RegExp('[^a-z-]+'));
  final head =
      unit == 'head' || rawWords.contains('head') || rawWords.contains('heads');
  final sizes = [
    for (final size in const ['small', 'medium'])
      if (rawWords.contains(size)) size,
  ];
  // Each alternative as a run of key-form words, with the size before it and
  // 'head' after it: ' small cucumber ', ' whole garlic head '.
  final runs = [
    for (final item in alternatives)
      ' ${[
        ...sizes,
        ...item.split(' ').map(keyWordOf),
        if (head) 'head',
      ].join(' ')} ',
  ];
  (String, double)? best;
  for (final (key, value) in _pieceWeights) {
    final keyHead = headNounOf(key);
    // A chile is FDC's pepper: 'jalapeno chiles' is the jalapeno.
    final anchored = heads.contains(keyHead) || heads.contains('pepper');
    final run = ' ${key.split(' ').map(keyWordOf).join(' ')} ';
    if (anchored &&
        runs.any((words) => words.contains(run)) &&
        (best == null || key.length > best.$1.length)) {
      best = (key, value);
    }
  }
  // v39 (C1, the owner's ruling Q9 (a)): "small" or "large" in the item's
  // own words (not a paren, not after the first comma: "chopped medium",
  // "cut into large pieces") sizes an onion of any colour, a carrot or a
  // round tomato by the size portion of the SR record its medium figure is.
  final sized = best == null || raw == null ? null : _srSizePieces[best.$1];
  if (sized != null) {
    final words = _itemSizeWords(
      raw!.replaceAll(RegExp(r'\([^)]*\)'), ' '),
    ).split(RegExp('[^a-z-]+'));
    for (final MapEntry(key: size, value: grams) in sized.entries) {
      if (words.contains(size)) {
        return ('$size ${best!.$1}', grams);
      }
    }
  }
  return best;
}

/// The SR size portions of the piece table's medium onion (170000: small
/// 70 g, large 150 g), carrot (170393: small (5½" long) 50 g, large (7¼" to
/// 8½" long) 72 g) and round tomato (170457: small whole 91 g, large whole
/// 182 g) — FDC's own figures, so unflagged (v39 C1). Celery stays 40 g:
/// the corpus prints a small rib at 25–50 g, not SR's 17 g.
const Map<String, Map<String, double>> _srSizePieces = {
  'onion': {'small': 70, 'large': 150},
  'carrot': {'small': 50, 'large': 72},
  'tomato': {'small': 91, 'large': 182},
};

double? _tableLookup(
  List<(String, double)> table,
  String normalizedItem, {
  bool words = false,
}) => _tableEntry(table, normalizedItem, words: words)?.$2;

(String, double)? _tableEntry(
  List<(String, double)> table,
  String normalizedItem, {
  bool words = false,
}) {
  // Longest matching key wins, so "sour cream" beats "cream" regardless of
  // table order.
  (String, double)? best;
  for (final entry in table) {
    final key = entry.$1;
    if ((words
            ? _keyAsWord(key).hasMatch(normalizedItem)
            : normalizedItem.contains(key)) &&
        (best == null || key.length > best.$1.length)) {
      best = entry;
    }
  }
  return best;
}

/// The density of [normalizedItem] ([_densities]): a key matches as a word
/// (or its plural), so 'water' never sizes "watermelon" — except 'nuts',
/// the tail of a nut's own name ("walnuts"). "Unsalted" and "salted",
/// normalized to "without salt" and "with salt", are the food's state,
/// never the salt: 'salt' 1.22 counted "½ cup unsalted roasted peanuts" at
/// 144 g ('nuts' 0.55: 65 g). An item that is a compound of a key but not
/// the key's food ([_notTheKeysFood]) has none: its record's own volume
/// portion sizes it (checkpoint 9: 27 counted lines at up to twice their
/// mass), as has a key that only modifies a longer compound: "cream of
/// tartar" ('cream' 1.01 for its record's 'tsp' 3.0 g), "mustard seeds"
/// (prepared 'mustard' 1.05 for the seed's 'tbsp' 6.3 g; Run 050).
/// The g/mL [normalizedItem] weighs at by the table ([_densityOf]) — the
/// density a medium threshold's mass figure comes from (engine RULE B, v27:
/// "¼ cup" of oil is 54.4 g at 0.92), or null.
/// A head the table does not size falls to [_foodFreeDensities].
double? densityOf(String normalizedItem) =>
    (_densityOf(normalizedItem) ??
            _densityOf(normalizedItem, _foodFreeDensities))
        ?.$2;

/// The densities a reader with NO food reads ([densityOf]: the engine's
/// medium thresholds, RULE B) for the medium heads [_densities] does not
/// size — never a line's grams, which read its record's own portion
/// (RULE B, v28, Run 058 S6/S20: the corpus's "bread crumbs" and a starch
/// had no key, so "8 ounces plain dried bread crumbs" read 0 mL and was no
/// dredge, and shortening and lard read oil's 0.92). In [_densities] these
/// keys would preempt the records' own portions: replayed, 10 corpus rows
/// moved off their USDA portion — the shortening and lard lines onto a
/// rounded figure, "3 cups tapioca starch" 456 g → 383 g on cornstarch's.
/// Each figure is a record's: FDC 174928 "Bread, crumbs, dry, grated,
/// plain" 'cup' 108 g (0.46; 'breadcrumbs' 0.45 above), 173584
/// "Shortening, vegetable, household, composite" and 171401 "Lard" each
/// 'cup' 205 g (0.87), and any other starch (tapioca, potato) on 169698
/// "Cornstarch" 'cup' 128 g (0.54) — no starch record of its own is
/// cached.
const List<(String, double)> _foodFreeDensities = [
  ('bread crumbs', 0.45),
  ('starch', 0.54),
  ('shortening', 0.87),
  ('lard', 0.87),
];

(String, double)? _densityOf(
  String normalizedItem, [
  List<(String, double)> table = _densities,
]) {
  final item = normalizedItem.replaceAll(_saltState, ' ');
  if (_notTheKeysFood.hasMatch(item)) {
    return null;
  }
  final entry = _tableEntry(table, item, words: true);
  if (entry == null ||
      RegExp(
        '(?<![a-z])${RegExp.escape(entry.$1)}(?:e?s)?\\s+(?:of|seeds?)(?![a-z])',
      ).hasMatch(item)) {
    return null;
  }
  return entry;
}

final RegExp _saltState = RegExp(r'\bwith(?:out)? salt\b');

/// Whether the density [key] only modifies [normalizedItem]'s head noun
/// while [food] — the record — names the key's food: "vanilla extract",
/// "cayenne pepper", "cocoa powder", "mustard greens" on records of those
/// foods weigh by the record's own volume portion, not the key's figure
/// ('cocoa' 0.52 counted "¾ cup cocoa powder" at 92 g; its record's cup,
/// 86 g, is the corpus's own "1 cup (3 ounces)"; Run 051 E2). A key the
/// record does not name keeps its figure: "panko bread crumbs" on "Bread,
/// crumbs, dry, grated, plain" (0.25, not plain crumbs' 108 g a cup), "whole
/// black peppercorns" on a record of ground pepper.
bool _keyModifiesTheRecordsFood(
  String key,
  String normalizedItem,
  FdcFood food,
) {
  final keyHead = headNounOf(key);
  for (final alternative in normalizedItem.split(' or ')) {
    final head = headNounOf(alternative);
    if (head == null || head == keyHead) {
      return false;
    }
  }
  final record = food.description
      .toLowerCase()
      .split(RegExp('[^a-z]+'))
      .map(keyWordOf)
      .toSet();
  return key.split(' ').map(keyWordOf).every(record.contains);
}

final Map<String, RegExp> _keyWords = {};
RegExp _keyAsWord(String key) => _keyWords.putIfAbsent(
  key,
  () => RegExp(
    key == 'nuts'
        ? 'nuts(?![a-z])'
        : '(?<![a-z])${RegExp.escape(key)}(?:e?s)?(?![a-z])',
  ),
);

/// Items a density key names that are not that key's food: dairy powders
/// ('milk', 'buttermilk' 1.03 sized "½ cup plus ⅓ cup nonfat dry milk
/// powder" at 203 g, its record's cup 120 g), water chestnuts ('water'
/// 1.0; 'nuts' 0.55), ricotta and cream cheese ('cheese' 0.47 is grated
/// cheese: "3 cups part-skim ricotta cheese" at 334 g, its record's 741 g)
/// oil-packed sun-dried tomatoes ('oil' 0.92), and almond and apple butter
/// ('butter' 0.959 for their records' 1.08 and 1.15; Run 050), and sugar
/// snap peas ('sugar' 0.85 counted "2 cups sugar snap peas" at 402 g, its
/// record's "cup, whole" 126 g; Run 051 O7 — "Peas, edible-podded" names
/// no sugar, so [_keyModifiesTheRecordsFood] cannot tell), and coconut-milk
/// yogurt ('yogurt' 1.03 is dairy yogurt's; v45: 2707569's own '1 cup'
/// 226 g sizes it).
final RegExp _notTheKeysFood = RegExp(
  r'\b(dry milk|milk powder|buttermilk powder|water chestnut|ricotta|'
  'cream cheese|oil-packed|almond butter|apple butter|sugar snap|'
  'coconut milk yogurt)',
);

/// Whether [normalizedItem] names [food]'s own food by a word beyond the
/// generic 'nut' and a salt state: "without salt roasted peanuts" on
/// "Peanuts, all types, dry-roasted, without salt", not "nuts" on cashews.
bool _namesTheRecord(String normalizedItem, FdcFood food) {
  const generic = {'nut', 'with', 'without', 'salt'};
  final record = food.description
      .toLowerCase()
      .split(RegExp('[^a-z]+'))
      .map(keyWordOf)
      .toSet();
  return normalizedItem
      .split(RegExp('[^a-z]+'))
      .map(keyWordOf)
      .any(
        (word) =>
            word.length > 2 && !generic.contains(word) && record.contains(word),
      );
}

/// Whether [raw]'s food is a flake or coarse sea salt, which packs like
/// kosher salt, not like table salt (1.22 counted "2 tablespoons flake sea
/// salt", 0227, at 36 g, Run 047): no FDC record or corpus weight sizes
/// them, so kosher's old round figure stands ([_flakeSaltDensity], v62).
/// Read on the raw line — the normalized
/// item drops "coarse" ("2 teaspoons coarse sea salt, divided", 0805) — and
/// only for those: plain and fine sea salt weigh as table salt (Run 048: a
/// "sea salt" key took them to 3.5 g a teaspoon). The salt must be the
/// line's OWN food: nothing but its amounts before it, parentheticals
/// aside (Run 049: "3 tablespoons unsalted butter, melted, plus flaky sea
/// salt" weighed the butter at 0.72, as "1 teaspoon table salt (or 2
/// teaspoons flaky sea salt)" did the table salt) and quantity words
/// ([_quantityWords]).
bool packsLikeKosherSalt(String raw) {
  final text = raw.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), ' ');
  final salt = _packsLikeKosher.firstMatch(text);
  return salt != null &&
      text
          .substring(0, salt.start)
          .split(RegExp(r'\s+'))
          .every(
            (word) =>
                word.isEmpty ||
                word == 'plus' ||
                _quantityWords.contains(word) ||
                _volumeUnitMl.containsKey(word.replaceAll(RegExp(r's$'), '')) ||
                RegExp('^[\\d$vulgarFractionChars/.\u2013-]+\$').hasMatch(word),
          );
}

/// Quantity words a salt's amount may carry ("1 heaping tablespoon flaky
/// sea salt", "scant ½ teaspoon", Run 050): the amount's, not a food's.
const Set<String> _quantityWords = {
  'heaping',
  'heaped',
  'scant',
  'rounded',
  'generous',
  'level',
  'about',
};

/// Flake, flaky, flaked, coarse(-grind) and Maldon sea salt, and sea salt
/// flakes, in the salt's own words (Run 049: "flaky Maldon sea salt", "sea
/// salt flakes", "coarse-grind sea salt" weighed as table salt).
final RegExp _packsLikeKosher = RegExp(
  r'\b(?:(?:(?:flak(?:e|y|ed)|coarse(?:-grind)?|maldon)\s+)+sea\s+salt|'
  r'sea\s+salt\s+flakes)\b',
);

/// Leading nouns in a portion description that mean a VOLUME/WEIGHT serving
/// (or a package), not a single countable item — so a bare count never scales
/// off "1 cup" or "1 serving".
const Set<String> _portionServingWords = {
  'cup',
  'cups',
  'tablespoon',
  'tablespoons',
  'tbsp',
  'teaspoon',
  'teaspoons',
  'tsp',
  'ounce',
  'ounces',
  'oz',
  'fl',
  'fluid',
  'ml',
  'milliliter',
  'liter',
  'l',
  'gram',
  'grams',
  'g',
  'lb',
  'pound',
  'quart',
  'pint',
  'gallon',
  'slice',
  'slices',
  'cubic',
  'serving',
  'package',
  'packet',
  'can',
  'bottle',
  'jar',
  'container',
  // Composite-dish language, never how a single produce/bakery item is named:
  // "1 piece"/"1 portion" of a wrong-food dish match is not one ingredient.
  'piece',
  'pieces',
  'portion',
  // Package nouns ('sleeve' was here for '30 saltine crackers', audit 2: the
  // record's "1 cracker" portion now sizes it, no line moves, audit 4).
  'box',
  'bag',
  'loaf',
};

/// Grams for ONE whole item from a portion whose description reads like a
/// single countable unit ("1 whole", "1 medium", "1 regular ear", "1 bun") as
/// opposed to a volume/weight serving ("1 cup", "1 fl oz", "1 serving"). For a
/// bare count ("1 leek") when the amount names no unit. When the food lists
/// several sizes, prefers the medium/regular one (what an unsized recipe
/// count means). Ignores Foundation "reference amount" portions (their
/// description is empty), which are a serving weight, not a whole item.
///
/// A portion whose noun the item itself names wins over any size rank:
/// "1 cracker" for 'saltine crackers', whatever FDC lists first; of several
/// it names, the medium one ("leaf, medium" for '4 leaves Bibb lettuce').
///
/// SR Legacy writes a single item as amount 1 and a bare noun — "shell"
/// 12.9 g of "Taco shells, baked", "leaf" of Swiss chard, "medium" of a
/// Bosc pear, "pepper" of a dried chile — read as "1 shell" (checkpoint 8:
/// 23 no_grams lines on a cached portion the finder never read).
/// The nouns an SR bare-noun portion names one item by whatever the item —
/// the medium one and a whole fruit (the other sizes and "whole" sized no
/// line of the library: removed, v15).
const Set<String> _oneItemNouns = {'medium', 'fruit'};

/// A chile, whose SR record counts it as a "pepper" ("2 dried ancho
/// chiles" on "Peppers, ancho, dried": 17 g a pepper).
final RegExp _chile = RegExp(r'\bchil(e|es|i|ies)\b');

/// A small DRIED chile: one named by a variety sold dried, or one the line
/// calls small and dried — the only chiles a sub-gram "pepper" portion
/// (168570 "Peppers, hot chile, sun-dried", 0.5 g) can weigh. A Thai chile
/// is fresh in every corpus line: "1 Thai red chile" (Panang Beef Curry)
/// read 0.5 g for a ~2 g chile (Run 047); japonés and pequin name no corpus
/// chile of their own, and "árbol" is read as the normalized item's
/// "arbol" (a word boundary never falls before "á").
///
/// "Small" is read from the item's own words ([_itemSizeWords], as the
/// whole-item portion reads it), and "large" excludes it: "2 dried New
/// Mexican chiles, … flesh torn into small pieces" is no small chile
/// (Run 051 O6: 0.5 g a ~7 g pod).
bool _smallDriedChile(String text) =>
    RegExp(r'\b(arbol|bird)\b').hasMatch(text) ||
    (RegExp(r'\bsmall\b').hasMatch(text) &&
        !RegExp(r'\blarge\b').hasMatch(text) &&
        RegExp(r'\bdried\b').hasMatch(text));

/// The words of [raw] that size its item: those before its prep (after a
/// comma, or a cut written without one). "1 baguette, cut into small
/// cubes" and "2 large pita breads, cut into small wedges" are no small
/// ones (Run 050: the mini baguette's 152 g for 324 g); "1 small
/// baguette" is.
String _itemSizeWords(String? raw) {
  final text = (raw ?? '').toLowerCase().split(',').first;
  final prep = RegExp(
    r'\b(cut|torn|broken|sliced|chopped|diced|into)\b',
  ).firstMatch(text);
  return prep == null ? text : text.substring(0, prep.start);
}

double? _wholeItemPortionGrams(
  FdcFood food,
  String normalizedItem, {
  String? raw,
}) {
  final itemWords = normalizedItem.split(RegExp('[^a-z]+')).map(keyWordOf);
  final lineSmall = RegExp(r'\bsmall\b').hasMatch(_itemSizeWords(raw));
  double? best;
  var bestRank = -1;
  for (final portion in food.portions) {
    final description = (portion.description ?? '').toLowerCase().trim();
    // "1 mini baguette (about 9\" long)" names the baguette, a small one.
    final match =
        RegExp(
          r'^([\d][\d./\s]*)\s*(?:mini\s+)?([a-z]+)',
        ).firstMatch(description) ??
        (portion.amount == 1
            ? RegExp('^()([a-z]+)').firstMatch(description)
            : null);
    if (match == null) {
      continue;
    }
    final count = match.group(1)!.isEmpty
        ? 1
        : _quantityValue(match.group(1)!.trim());
    // Exactly one: "1 whole"/"1 medium" is a single item; "10 sprigs"/"4 large"
    // /"1/2 breast" is a multi-unit or partial serving, not one countable item.
    if (count != 1) {
      continue;
    }
    if (_portionServingWords.contains(match.group(2))) {
      continue;
    }
    final noun = match.group(2)!;
    // A single countable item a recipe writes as a BARE count is well under
    // 250 g (bigger ones — squash, cabbage — carry a unit or a printed
    // weight); a heavier "1 X" is a prepared-dish serving on a wrong-food
    // match ("1 piece" of "Lasagna, meatless" = 256 g), not one item —
    // unless a numbered portion's noun IS the item's own noun: "1 baguette
    // (about 22\" long)" 324 g on "Bread, French or Vienna" (v17). An SR
    // bare noun stays capped: "roast" 625 g sized "1 center-cut beef
    // tenderloin roast, 3 pounds trimmed weight" (Beef Wellington) 2x under.
    // A bare 'fruit' or own-noun portion up to 350 g is the item (v21 plan
    // G2/G3): 169910 Mangos 'fruit without refuse' 336 g ("2 mangos"),
    // 173619's 'leg, bone and skin removed' 265 g ("4 whole chicken legs").
    final ownNoun = itemWords.contains(keyWordOf(noun));
    final bare = match.group(1)!.isEmpty;
    if (portion.gramWeight > 250 &&
        !(ownNoun && !bare) &&
        !(bare && (noun == 'fruit' || ownNoun) && portion.gramWeight <= 350)) {
      continue;
    }
    final small = description.contains('small') || description.contains('mini');
    // A line that says small takes the record's small one ("1 small
    // baguette": the "1 mini baguette" 152 g), else the medium/regular.
    final size = lineSmall && small
        ? 3
        : description.contains('regular') || description.contains('medium')
        ? 2
        : (description.contains('large') || small ? 0 : 1);
    // ponytail: 168570 "Peppers, hot chile, sun-dried" weighs its "pepper" at
    // 0.5 g — a bird chile. A dried New Mexican or guajillo pod is ~7 g by the
    // corpus's own parens ("3 medium New Mexican pods (about ¾ ounce)"), so a
    // sub-gram pepper portion sizes only a small dried chile
    // ([_smallDriedChile]); the rest stay unweighed unless the piece table
    // sizes them first (v30: New Mexican and guajillo at ATK's printed 7.1 g)
    // (Run 047 verifier: 14× under, 3 false completes).
    // The guard holds for the whole "pepper" portion, whatever names it — a
    // "bell pepper" item names the noun itself (Run 047 critic).
    if (noun == 'pepper' &&
        portion.gramWeight < 1 &&
        !_smallDriedChile('${_itemSizeWords(raw)} $normalizedItem')) {
      continue;
    }
    final chile = noun == 'pepper' && _chile.hasMatch(normalizedItem);
    final named =
        normalizedItem.contains(noun) ||
        itemWords.contains(keyWordOf(noun)) ||
        chile;
    // A bare noun is one item only when it is the item's own noun, a size
    // or a whole fruit: "drumstick" 88 g is no "whole chicken leg", "dash"
    // no peppercorn, "NLEA serving" no plum (checkpoint 8 replay).
    if (match.group(1)!.isEmpty && !named && !_oneItemNouns.contains(noun)) {
      continue;
    }
    final rank = named ? 10 + size : size;
    if (rank > bestRank) {
      // count is 1 here, so the portion weight IS the per-item weight.
      bestRank = rank;
      best = portion.gramWeight;
    }
  }
  return best;
}

/// Count units that name a PACKAGE, not a whole food — their weight is the
/// package size, which comes from a printed weight (the parenthetical handled
/// earlier). Without one we cannot know it, so a whole-item table value
/// ("1 can diced tomatoes" ≠ one 123 g tomato) must not fill in; leave it null.
const Set<String> _containerUnits = {
  'can',
  'cans',
  'jar',
  'jars',
  'bottle',
  'bottles',
  'package',
  'packages',
  'packet',
  'packets',
  'envelope',
  'envelopes',
  'block',
  'blocks',
  'bar',
  'bars',
  'cube',
  'cubes',
  'container',
  'containers',
  'box',
  'boxes',
  'tube',
  'tubes',
  // A strip of zest or a wedge is a piece of the fruit, not the fruit: "12
  // (3-inch) strips lemon zest" counted 12 whole lemons (696 g). Without a
  // portion of its own the line goes to review. (The plural reads as
  // 'strip': 'strips' here moved no line, audit 4.)
  'strip',
  'wedge',
  'wedges',
};

/// A portion keyed by a STRUCTURED piece/each/whole/unit measure (some foods
/// carry a `unit=piece, amount=n` portion whose description has no leading
/// count). Structured only — NOT a description text match, so it cannot
/// re-admit a "1 piece" dish serving the whole-item finder already excluded.
double? _legacyPiecePortion(FdcFood food) {
  const units = {'piece', 'pieces', 'each', 'whole', 'unit', 'units'};
  for (final portion in food.portions) {
    if (!units.contains((portion.unit ?? '').toLowerCase())) {
      continue;
    }
    final amount = portion.amount ?? 1;
    if (amount <= 0) {
      continue;
    }
    final perItem = portion.gramWeight / amount;
    if (perItem > 250) {
      continue; // same single-item sanity bound as the whole-item finder
    }
    return perItem;
  }
  return null;
}

/// Grams-per-single-[unit] from the food's own portions, when one matches.
///
/// [bare] also reads SR Legacy's bare noun with no unit of its own for a
/// count unit ([_resolveGrams] asks after the piece table, whose hand-tuned
/// slice of bread or bacon it must not override).
double? _portionGramsPerUnit(FdcFood food, String unit, {bool bare = false}) {
  final wanted = unit.toLowerCase();
  for (final portion in food.portions) {
    final portionUnit = portion.unit ?? '';
    final description = (portion.description ?? '').toLowerCase();
    double? amount;
    if (portionUnit == wanted || portionUnit == '${wanted}s') {
      amount = portion.amount ?? 1;
    } else if (description.contains(wanted)) {
      // A description-only match ("0.25 cup, sifted") is trusted only when
      // the description leads with its own parseable amount — the structured
      // `amount` field belongs to the (non-matching) measure unit, so
      // defaulting to 1 here would silently mis-scale the weight.
      final leading = RegExp(r'^([\d][\d./\s]*)').firstMatch(description);
      final parsed = leading == null
          ? null
          : _quantityValue(leading.group(1)!.trim());
      // SR Legacy's bare noun with no unit of its own: "stick" 113 g of
      // "Butter, without salt" is one stick ('4 sticks unsalted butter',
      // Classic Yellow Layer Cake, 0884; checkpoint 8).
      // The unit must LEAD the description: a portion that merely contains
      // it ("cup, sliced", "cup, slices") is a cup, and weighed "2 slices
      // pears" as two cups, 280 g (Run 048; no corpus line reaches it —
      // restored for other libraries' lines).
      final named =
          bare &&
          parsed == null &&
          description.split(RegExp('[^a-z]+')).first == wanted;
      if (parsed == null && !named) {
        continue;
      }
      amount = parsed ?? portion.amount ?? 1;
    } else {
      continue;
    }
    if (amount <= 0) {
      continue;
    }
    return portion.gramWeight / amount;
  }
  return null;
}

/// Grams per mL from the food's OWN volume portions, for a volume line the
/// density table does not cover. SR Legacy writes a volume portion as
/// "tbsp"/"tsp"/"cup chopped" with the count in the structured amount (the
/// unit field is "undetermined", so [_portionGramsPerUnit] never matches
/// 'tablespoon' to it); FNDDS writes "1 cup". Audit 1: 190 no_grams lines on
/// the right food (parsley, black pepper, capers, thyme). Called AFTER the
/// density table, never before: food-first sized 26 kosher-salt lines ×1.71
/// on table salt's portion. A portion that names its volume only in
/// parentheses — 169599 gelatin's "envelope (1 tbsp)" = 7 g — is read when
/// no portion leads with one: the count there is the whole portion's, so the
/// structured amount is not applied (audit 3 refix: 30 gelatin lines).
///
/// Of several volume portions, one whose words the line shares wins ("cup
/// spaghetti" for a spaghetti line, "cup, sliced" for sliced almonds, "tbsp,
/// leaves" for tarragon leaves), else their median: SR 169736 "Pasta, dry,
/// enriched" lists cup shells 64 g first and spaghetti 91 g, penne 95 g
/// after — the first one sized '½ cup orzo' at 32 g (audit 4). [lineText] is
/// the raw line, whose prep words ('sliced', 'packed') name portions too.
///
/// [onlyUnit] reads that volume portion alone ('teaspoon': a pinch).
///
/// With no named portion, the median mixed incompatible forms (packed and
/// loose, leaves and ground: dried oregano 1.4 g a teaspoon for 'tsp,
/// leaves' 1.0 g): a portion in the line's own [lineUnit] is preferred, then
/// a default form ([_defaultForms]), and only then the median (checkpoint
/// 5).
double? _foodGramsPerMl(
  FdcFood food, [
  String lineText = '',
  String? onlyUnit,
  String? lineUnit,
]) {
  final itemWords = {
    for (final word in lineText.toLowerCase().split(RegExp('[^a-z]+')))
      if (word.length > 2 &&
          !_volumeAliases.containsKey(word) &&
          !_amountWords.contains(word))
        keyWordOf(word),
  };
  final perMl = <({double value, String unit, String description})>[];
  double? named;
  double? parenthesized;
  final whipped = lineText.toLowerCase().contains('whipped');
  for (final portion in food.portions) {
    final description = (portion.description ?? '').toLowerCase().trim();
    // Whipped is air: 173418's "tbsp, whipped" 10 g sized "2 tablespoons
    // cream cheese" at 24.5 g with its "tbsp" 14.5 g (checkpoint 9).
    if (!whipped && description.contains('whipped')) {
      continue;
    }
    final lead = RegExp(
      r'^([\d][\d./\s]*)?\s*([a-z]+)',
    ).firstMatch(description);
    var unit = _volumeAliases[(portion.unit ?? '').toLowerCase()];
    var amount = portion.amount;
    if (unit == null && lead != null) {
      unit = _volumeAliases[lead.group(2)];
      final count = lead.group(1);
      if (count != null) {
        amount = _quantityValue(count.trim());
      }
    }
    if (unit == null || amount == null || amount <= 0) {
      final paren = RegExp(
        r'\((\d[\d./\s]*?)\s*([a-z]+)',
      ).firstMatch(description);
      final inner = _volumeAliases[paren?.group(2)];
      final count = paren == null ? null : _quantityValue(paren.group(1)!);
      if (inner != null && count != null && count > 0) {
        parenthesized ??= portion.gramWeight / (count * _volumeUnitMl[inner]!);
      }
      continue;
    }
    final value = portion.gramWeight / (amount * _volumeUnitMl[unit]!);
    if (onlyUnit != null) {
      if (unit == onlyUnit) {
        return value;
      }
      continue;
    }
    perMl.add((value: value, unit: unit, description: description));
    final words = description.split(RegExp('[^a-z]+')).map(keyWordOf);
    if (named == null && words.any(itemWords.contains)) {
      named = value;
    }
  }
  if (named != null) {
    return named;
  }
  if (perMl.isEmpty) {
    return onlyUnit == null ? parenthesized : null;
  }
  final sameUnit = [
    for (final portion in perMl)
      if (portion.unit == lineUnit) portion,
  ];
  final pool = sameUnit.isEmpty ? perMl : sameUnit;
  // A shred no portion names reads the shredded or grated one: "2⅔ cups
  // shredded carrots" is 170393's 'cup grated' 110 g, "3 cups thinly sliced
  // green cabbage" 169975's 'cup, shredded' 70 g, not the medians' 122 g
  // and 79.5 g (Run 050).
  if (_shredCut.hasMatch(lineText.toLowerCase())) {
    for (final portion in pool) {
      if (_shredPortion.hasMatch(portion.description)) {
        return portion.value;
      }
    }
  }
  // A fine cut no portion names reads the chopped one: "¼ cup grated
  // onion" is 170000's 'cup, chopped' (160 g) as "4 tablespoons grated
  // onion" is its 'tbsp chopped' — the mean with 'cup, sliced' made a cup
  // 14% lighter than 16 tablespoons (checkpoint 5 review: 6 grated-onion
  // lines).
  if (_fineCut.hasMatch(lineText.toLowerCase())) {
    for (final portion in pool) {
      if (_choppedPortion.hasMatch(portion.description)) {
        return portion.value;
      }
    }
  }
  final spice = food.description.toLowerCase().startsWith('spices,');
  for (final form in spice ? _spiceDefaultForms : _defaultForms) {
    for (final portion in pool) {
      if (form.hasMatch(portion.description)) {
        return portion.value;
      }
    }
  }
  final values = [for (final portion in pool) portion.value]..sort();
  final mid = values.length ~/ 2;
  return values.length.isOdd
      ? values[mid]
      : (values[mid - 1] + values[mid]) / 2;
}

/// A line's shred ([_foodGramsPerMl]) and a portion of one. A thin slice
/// is a shred; a plain slice is not ("sliced carrots" are 170393's 'cup
/// strips or slices' 122 g, never its 'cup grated' 110 g).
final RegExp _shredCut = RegExp(
  r'\b(shredded|grated|thinly sliced|sliced (?:very )?thin)\b',
);
final RegExp _shredPortion = RegExp(r'\b(shredded|grated)\b');

/// A line's fine cut ([_foodGramsPerMl]).
final RegExp _fineCut = RegExp(r'\b(chopped|minced|diced|grated)\b');

/// A portion of a fine cut.
final RegExp _choppedPortion = RegExp(r'\b(chopped|minced|diced)\b');

/// The portion words that name a food's plain form when the line names
/// none, in order: loose, whole, dry ("cup (not packed)" 145 g of golden
/// raisins, not the median with "cup, packed"; a powder's "cup dry mix").
/// ('leaves' off a 'Spices,' record changed no line, refix round 1.)
final List<RegExp> _defaultForms = [
  RegExp('not packed'),
  RegExp(r'\bwhole\b'),
  RegExp(r'\bdry\b'),
];

/// A 'Spices,' record's plain form: a dried herb's leaves (oregano "tsp,
/// leaves" 1.0 g, not "tsp, ground" 1.8 g), else the ground spice (black
/// pepper "tsp, ground" 2.3 g, not "tsp, whole").
final List<RegExp> _spiceDefaultForms = [
  RegExp(r'\bleaves\b'),
  RegExp(r'\bground\b'),
];

/// Measure words a line and a portion share without naming a form.
const Set<String> _amountWords = {'ounce', 'ounces', 'fluid', 'about', 'plus'};

/// Portion spellings of a volume unit → the [_volumeUnitMl] key.
const Map<String, String> _volumeAliases = {
  'tbsp': 'tablespoon',
  'tbs': 'tablespoon',
  'tablespoon': 'tablespoon',
  'tablespoons': 'tablespoon',
  'tsp': 'teaspoon',
  'teaspoon': 'teaspoon',
  'teaspoons': 'teaspoon',
  'cup': 'cup',
  'cups': 'cup',
  'fl': 'fluid ounce',
  'pint': 'pint',
  'quart': 'quart',
};

/// The second amount of a "plus" line: "¾ cup plus 2 tablespoons vegetable
/// oil", "6 sprigs parsley, plus 2 teaspoons minced", "2 teaspoons lemon zest
/// plus 2 tablespoons juice", "2 large eggs plus 1 large yolk". The corpus
/// parse keeps only the first amount, so the second was dropped (audit 1:
/// 26 volume-plus lines, 1,243 g) or, naming another food, silently left out.
class PlusPart {
  /// Pairs the second amount with what it names.
  const PlusPart({
    required this.amount,
    required this.text,
    required this.sameFood,
    this.weighsTotal = false,
    String? form,
  }) : form = form ?? text;

  /// The second amount as parsed.
  final Amount amount;

  /// The second part as written ("2 tablespoons juice").
  final String text;

  /// The second part's own words through its end, its comma included —
  /// "2 cups, shredded" (the corpus's own spelling: "¼ cup grated Parmesan
  /// cheese plus 6 ounces, shredded", 0419) — where [text] stops at the
  /// comma: the form the part is in ([resolveGrams]; Run 056 O11/S12).
  final String form;

  /// Whether the second part names no food beyond the first part's (or the
  /// first part names none: "¼ cup plus 2 teaspoons olive oil").
  final bool sameFood;

  /// Whether a parenthesis after the second amount weighs the WHOLE line
  /// ("1 teaspoon plus 1⅛ cups (8 ounces) sugar"): the weight already is the
  /// total, so the second amount is never added to it.
  final bool weighsTotal;
}

/// Whether the key of [first] is the key of [second] with qualifiers before
/// it ('european-style without salt butter' / 'without salt butter'). Every
/// word counts, so a form word tells foods apart ('light brown sugar' /
/// 'granulated sugar'); a food after "in"/"with" is a component, not the
/// food ('chipotle chile in adobo sauce' / 'adobo sauce'). Count nouns and
/// fillers ('at room temperature') are not read.
bool _qualifiesSame(String? first, String? second) {
  List<String> words(String? item) => [
    for (final word in itemKeyFor(item ?? '').split(' '))
      if (word.isNotEmpty &&
          !isCountNoun(word) &&
          (word == 'and' || !_plusFiller.contains(word)))
        word,
  ];
  final a = words(first);
  final b = words(second);
  if (b.isEmpty || b.length >= a.length) {
    return false;
  }
  final at = a.length - b.length;
  for (var i = 0; i < b.length; i++) {
    if (a[at + i] != b[i]) {
      return false;
    }
  }
  return !const {'in', 'with', 'from', 'of', 'and', 'or'}.contains(a[at - 1]);
}

/// USER ANSWER #4 SWITCH (edible yield). True (the recommended default)
/// scales a weight on a bone-in cut, a whole bird or shellfish in the shell
/// by the edible yield FDC publishes for the matched record — its raw
/// "excluding refuse (yield from 1 raw chop, with refuse, weighing 151 g)"
/// portion (167833, a bone-in rib chop: 0.57) — and shows it in the basis.
/// FDC's nutrients are per 100 g EDIBLE, so the printed gross weight counted
/// bone as meat (audit 2: 59 counted lines, 143.7 kg). A record without such
/// a portion is left at the printed weight (no factor is guessed); false
/// turns the scaling off.
const bool edibleYieldOn = true;

/// A raw line that buys bone, a carcass or a shell by weight — the audit's
/// classifier (audit1/bone2.py). Boneless, ground and broth lines never are.
bool buysRefuse(String raw) {
  final line = raw.toLowerCase();
  // "1 pound lobster meat" (0292) is picked meat, as a boneless cut is (not
  // 0222's rib roast, "meat removed from bones" and tied back on). (Crab and
  // clam meat changed no line of the library: removed, refix round 2.)
  // v68 (M70, Q13): a section's "Reserved turkey giblets, …" is a part the
  // host already bought — weighed off its bird, never a purchase weight
  // (engine `hostWeighedGiblets`; no detail fetched for it).
  if (RegExp(
    r'^reserved\b|boneless|broth|stock|\bground\b|\blobster\s*meat\b',
  ).hasMatch(line)) {
    return false;
  }
  return RegExp(
    r'giblets|whole chicken|whole turkey\b|\) turkey\b|\bturkey \(|'
    'shoulder chops?|with or without bone|'
    'bone-in|standing rib|oxtails?|shanks?|racks? of|short ribs|spareribs|'
    // v30 (Q7): "3–4 beef rib slabs (… about 5 pounds total)" buys bone.
    'rib slabs?|'
    r'baby back|drumsticks?|wings?\b|leg quarters?|'
    r'clams|mussels|oysters|lobsters?|shell-on|in the shell|crabs?\b',
  ).hasMatch(line);
}

/// v39 (Y1, the owner's ruling 2026-10-05 on plan Q1 (a), revising CP6 #11
/// "meats and birds at gross weight" and #5 "turkeys gross"): the edible
/// yield of a bone-in cut whose MATCHED record publishes no refuse portion,
/// by the record's class, each figure an FDC portion (prep39/bonein.md §3).
/// Read only for a [buysRefuse] line weighed from a printed weight, after
/// the record's own refuse portion and the whole bird's ready-to-cook
/// yield ([edibleYieldOf]), and flagged approximate. Absent, so gross: 173403
/// (the line allows boneless) and 2705900 ham hocks (no figure).
const Map<int, ({String yieldOf, String from, double share})>
boneInClassYields = {
  // 168242's own refuse portion: 133 g of a 201 g chop, lean+fat (the
  // lean-only 167833's 0.570 also refuses the separable fat).
  167822: _porkChop,
  // 167895 country-style ribs: 128 g of a 196 g piece. (v43: the
  // spareribs 167853, the hams 168226 / 169177 and the standing rib 168675
  // read [ah102Meats].)
  168299: _porkRibs,
  // 167849 Boston butt blade steak: 288 g of 380 g.
  168367: _porkRoast,
  // 171447 "unit (yield from 1 lb ready-to-cook chicken)" 276 g of a pound
  // (the Cornish-hen chain, 336 of 567 g, 0.593, corroborates). v43: every
  // bird part of [ah102Records] reads [ah102Parts] first; these entries
  // remain only for a line the part read gives no figure (a whole chicken
  // on the class path, Y4).
  171447: _chicken, 2727566: _chicken, 2727567: _chicken, 2727568: _chicken,
  2727569: _chicken, 172378: _chicken, 2646171: _chicken, 173619: _chicken,
  // No turkey part figure exists: the chicken's. (v59, Y: the bone-in
  // breast 171093 reads [ah102Parts]' derived 'turkey breast'.)
  171533: _turkey, 171497: _turkey, 174518: _turkey,
  // INTERIM (Q1b): the chicken's. The live step (plan §3 requests 4–9,
  // 2026-10-05) found no turkey yield: per ready-to-cook pound the breast
  // 171093 is 146 g, the leg 171493 105 g, the wing 171495 33 g, but FDC
  // has no raw "meat and skin" back or neck — 171096 back and 171086 neck
  // are meat only with no share — so the parts (284 g = 0.626) are a
  // partial sum, not a bird's yield.
  171081: (
    yieldOf: 'a whole turkey (interim: the chicken figure)',
    from: '171447',
    share: _poultry,
  ),
  // No figure of their species: the median of the four above {0.608,
  // 0.653, 0.662, 0.758}, (128/196 + 133/201) / 2. (v43: the shank 169441,
  // the rack 172641 and the foreshank 172513 read [ah102Meats].)
  173405: _bony, 170827: _bony, 174875: _bony, 172648: _bony,
  // The record's OWN FNDDS "1 oz yields 16 g" (raw with bone → this cooked
  // food).
  2705843: (yieldOf: 'oxtails', from: '2705843', share: 16 / 28.349523125),
};

const double _poultry = 276 / 453.59237;
const _porkChop = (
  yieldOf: 'bone-in pork chops',
  from: '168242',
  share: 133 / 201,
);
const _porkRibs = (yieldOf: 'pork ribs', from: '167895', share: 128 / 196);
const _porkRoast = (
  yieldOf: 'a bone-in pork roast',
  from: '167849',
  share: 288 / 380,
);
const _chicken = (yieldOf: 'chicken parts', from: '171447', share: _poultry);
const _turkey = (
  yieldOf: 'turkey parts (the chicken figure)',
  from: '171447',
  share: _poultry,
);
const _bony = (
  yieldOf: 'bony beef, lamb and veal',
  from: '167895 and 168242 (the median)',
  share: (128 / 196 + 133 / 201) / 2,
);

/// v43 (the owner's 2026-10-06 rulings Y1–Y7, Y12, Y13): USDA Agriculture
/// Handbook 102 (1975), Table 1 raw boning data — a bone-in bird part's
/// edible yield of its printed weight, by `"<species> <part>"`: the
/// meat-and-skin figure, and the meat figure read IN ONE STEP when the
/// record is meat only ([ah102Records]; Y12 retired the v39 stack of the
/// bone yield × FDC SR's skin share 0.795 / 0.770). Each flag cites the
/// item and its range. Derived (no printed row; flagged "derived"): the
/// chicken LEG (thigh + drumstick, 585–586 by 583's carcass shares 19/17 —
/// no leg-quarter row exists, so a leg quarter's back is not in it) and
/// mixed PIECES (584–586 by 27/19/17). The turkey rows are the fryer-roaster
/// class (the only class boned); the whole turkey takes the dressing ratio
/// for birds of 12 lb and over (ready to cook without / with neck and
/// giblets, 78 of 85) × the carcass row 2592. Absent: the whole chicken
/// (Y4: FDC's own ready-to-cook 0.608 / 0.434 stay). v59 (M60 Y, the
/// owner's Q14 (a), closing Y7): the bone-in turkey BREAST is ATK's retail
/// cut — the breast with its upper back (rib) attached, which every recipe
/// cuts away or leaves uncarved — so its figure is DERIVED from 2591's
/// carcass shares (breast 33, rib 10) × 2593's breast meat and skin 87 % /
/// meat 78 %: the breast's part of the breast-plus-rib weight; the back is
/// not counted.
const Map<String, Ah102Part> ah102Parts = {
  'chicken breast': (
    skin: 0.74,
    skinFlag:
        'USDA AH-102 item 584: chicken breast, raw → meat and skin '
        '74 % (59–84)',
    meat: 0.65,
    meatFlag: 'USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77)',
  ),
  'chicken thigh': (
    skin: 0.70,
    skinFlag:
        'USDA AH-102 item 586: chicken thigh, raw → meat and skin '
        '70 % (63–81)',
    meat: 0.59,
    meatFlag: 'USDA AH-102 item 586: chicken thigh, raw → meat 59 % (48–68)',
  ),
  'chicken drumstick': (
    skin: 0.63,
    skinFlag:
        'USDA AH-102 item 585: chicken drumstick, raw → meat and skin '
        '63 % (50–75)',
    meat: 0.55,
    meatFlag:
        'USDA AH-102 item 585: chicken drumstick, raw → meat 55 % '
        '(44–69)',
  ),
  'chicken wing': (
    skin: 0.50,
    skinFlag:
        'USDA AH-102 item 590: chicken wing, raw → meat and skin '
        '50 % (41–60)',
    meat: 0.31,
    meatFlag: 'USDA AH-102 item 590: chicken wing, raw → meat 31 % (13–42)',
  ),
  'chicken leg': (
    skin: (70 * 19 + 63 * 17) / 36 / 100,
    skinFlag:
        "derived from USDA AH-102 items 585–586 by 583's carcass "
        'shares: leg (thigh + drumstick), raw → meat and skin 66.7 %; a leg '
        "quarter's back portion is not in this figure",
    meat: (59 * 19 + 55 * 17) / 36 / 100,
    meatFlag:
        "derived from USDA AH-102 items 585–586 by 583's carcass "
        'shares: leg (thigh + drumstick), raw → meat 57.1 %; a leg '
        "quarter's back portion is not in this figure",
  ),
  'chicken pieces': (
    skin: (74 * 27 + 70 * 19 + 63 * 17) / 63 / 100,
    skinFlag:
        "derived from USDA AH-102 items 584–586 by 583's carcass "
        'shares: pieces (breast, thigh, drumstick), raw → meat and skin '
        '69.8 %',
    meat: (65 * 27 + 59 * 19 + 55 * 17) / 63 / 100,
    meatFlag:
        "derived from USDA AH-102 items 584–586 by 583's carcass "
        'shares: pieces (breast, thigh, drumstick), raw → meat 60.5 %',
  ),
  'turkey whole': (
    skin: 78 / 85 * 0.71,
    skinFlag:
        'USDA AH-102 turkey dressing data, 12 lb and over (neck and '
        'giblets off 78 of 85); carcass → meat and skin, item 2592, '
        'fryer-roaster class, 71 % (67–75)',
    meat: 78 / 85 * 0.63,
    meatFlag:
        'USDA AH-102 turkey dressing data, 12 lb and over (neck and '
        'giblets off 78 of 85); carcass → meat, item 2592, fryer-roaster '
        'class, 63 % (59–65)',
  ),
  'turkey thigh': (
    skin: 0.82,
    skinFlag:
        'USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class '
        '→ meat and skin 82 % (77–85)',
    meat: 0.77,
    meatFlag:
        'USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class '
        '→ meat 77 % (76–80)',
  ),
  'turkey drumstick': (
    skin: 0.69,
    skinFlag:
        'USDA AH-102 item 2597: turkey drumstick, raw, fryer-roaster '
        'class → meat and skin 69 % (66–74)',
    meat: 0.65,
    meatFlag:
        'USDA AH-102 item 2597: turkey drumstick, raw, fryer-roaster '
        'class → meat 65 % (62–70)',
  ),
  'turkey leg': (
    skin: 0.75,
    skinFlag:
        'USDA AH-102 item 2596: turkey leg, raw, fryer-roaster class '
        '→ meat and skin 75 % (70–79)',
    meat: 0.71,
    meatFlag:
        'USDA AH-102 item 2596: turkey leg, raw, fryer-roaster class '
        '→ meat 71 % (66–74)',
  ),
  'turkey leg quarter': (
    skin: 0.71,
    skinFlag:
        'USDA AH-102 item 2595: turkey leg quarter, raw, fryer-roaster '
        'class → meat and skin 71 % (69–73)',
    meat: 0.64,
    meatFlag:
        'USDA AH-102 item 2595: turkey leg quarter, raw, fryer-roaster '
        'class → meat 64 % (62–65)',
  ),
  'turkey breast': (
    skin: 33 / 43 * 0.87,
    skinFlag:
        'derived from USDA AH-102 items 2591 and 2593, fryer-roaster class: '
        "a breast sold with its upper back (rib) attached — the breast's "
        'meat and skin, 87 % (85–89) of its 33 of 43 parts, 66.8 %; the back '
        'is not counted',
    meat: 33 / 43 * 0.78,
    meatFlag:
        'derived from USDA AH-102 items 2591 and 2593, fryer-roaster class: '
        "a breast sold with its upper back (rib) attached — the breast's "
        'meat, 78 % (77–81) of its 33 of 43 parts, 59.9 %; the back is not '
        'counted',
  ),
  'turkey wing': (
    skin: 0.61,
    skinFlag:
        'USDA AH-102 item 2602: turkey wing, raw, fryer-roaster class '
        '→ meat and skin 61 % (59–64)',
    meat: 0.43,
    meatFlag:
        'USDA AH-102 item 2602: turkey wing, raw, fryer-roaster class '
        '→ meat 43 % (42–45)',
  ),
};

/// One [ah102Parts] row: the meat-and-skin share and the meat share of a
/// part's printed weight, each with its flag.
typedef Ah102Part = ({
  double skin,
  String skinFlag,
  double meat,
  String meatFlag,
});

/// v43: the bird records [ah102Parts] reads, by species and composition —
/// the RECORD decides (Y13): a meat-only record reads the part's meat
/// figure, a meat-and-skin record meat and skin, whoever put the row there
/// (a person's pick of 2646171 for a thigh whose skin is eaten reads meat).
/// v59 (M60 Y): 171093, the bone-in turkey breast, meat and skin.
const Map<int, ({String species, bool meatOnly})> ah102Records = {
  171447: (species: 'chicken', meatOnly: false),
  2727566: (species: 'chicken', meatOnly: false),
  2727567: (species: 'chicken', meatOnly: false),
  2727568: (species: 'chicken', meatOnly: false),
  2727569: (species: 'chicken', meatOnly: false),
  172378: (species: 'chicken', meatOnly: false),
  2646171: (species: 'chicken', meatOnly: true),
  173619: (species: 'chicken', meatOnly: true),
  171052: (species: 'chicken', meatOnly: true),
  2646170: (species: 'chicken', meatOnly: true),
  171081: (species: 'turkey', meatOnly: false),
  171093: (species: 'turkey', meatOnly: false),
  171533: (species: 'turkey', meatOnly: false),
  174518: (species: 'turkey', meatOnly: true),
  171497: (species: 'turkey', meatOnly: true),
};

/// v43 (P4's part read): the bird part [raw] buys — "whole" (a whole-bird
/// line), then "pieces" (mixed parts; a turkey's "drumsticks and thighs" is
/// its "leg"), then the part the line names FIRST, parentheses aside (a
/// chicken leg quarter is the derived "leg"); a line naming none takes
/// [food]'s own part, else "whole".
String birdPartOf(String raw, FdcFood food) {
  if (_wholeBirdLine.hasMatch(raw)) return 'whole';
  final line = raw.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), '');
  if (RegExp(
    r'chicken (pieces|parts)\b|breasts? and/or leg quarters?',
  ).hasMatch(line)) {
    return 'pieces';
  }
  if (RegExp(
    'turkey (drumsticks? and thighs?|thighs? and drumsticks?)',
  ).hasMatch(line)) {
    return 'leg';
  }
  final turkey = ah102Records[food.fdcId]?.species == 'turkey';
  String? firstPart(String text) {
    (int, String)? first;
    for (final (part, word) in [
      (turkey ? 'leg quarter' : 'leg', 'leg quarters?'),
      ('leg', r'\blegs?\b'),
      ('breast', 'breasts?'),
      ('thigh', 'thighs?'),
      ('drumstick', 'drumsticks?'),
      ('wing', 'wings?'),
    ]) {
      final at = RegExp(word).firstMatch(text)?.start;
      if (at != null && (first == null || at < first.$1)) first = (at, part);
    }
    return first?.$2;
  }

  return firstPart(line) ??
      firstPart(food.description.toLowerCase()) ??
      'whole';
}

/// [food]'s [ah102Parts] yield for the bird part [raw] buys — the meat
/// figure on a meat-only record, else meat and skin — or null (not a bird
/// record of [ah102Records], or a part the handbook gives no figure for).
({double share, String flag})? ah102YieldOf(FdcFood food, String raw) {
  final record = ah102Records[food.fdcId];
  final part = record == null
      ? null
      : ah102Parts['${record.species} ${birdPartOf(raw, food)}'];
  if (part == null) return null;
  return record!.meatOnly
      ? (share: part.meat, flag: part.meatFlag)
      : (share: part.skin, flag: part.skinFlag);
}

/// v43 (the owner's 2026-10-06 ruling Y10): a bone-in beef, pork or lamb
/// record whose cut USDA AH-102 (1975) Table 1 names reads the handbook's
/// raw boning figure (lean and fat meat of the cut as bought) instead of a
/// borrowed [boneInClassYields] class, flagged with the item and its range.
/// The rack and the shank name the record the row does not describe; the
/// shank half is DERIVED (1 − bones; the printed row also trims the fat).
/// FDC's own refuse portions stay where a record has one of its own class
/// (168242 chops, 167849 butt, 167895 country ribs, oxtails); blade chops,
/// baby back ribs, short/back ribs, picnic, lamb shoulder chops, veal shank
/// and ham hocks have no row and keep theirs.
const Map<int, ({double share, String flag})> ah102Meats = {
  167853: (
    share: 0.58,
    flag:
        'USDA AH-102 item 1925: pork spareribs, raw → lean and fat meat '
        '58 % (43–71; bones 42)',
  ),
  168675: (
    share: 0.82,
    flag:
        'USDA AH-102 item 238: beef rib, retail ribs 11–12, raw → lean and '
        'fat meat 82 % (78–86; bones 18)',
  ),
  169441: (
    share: 0.61,
    flag:
        'USDA AH-102 item 228: beef shank, fore, raw → lean and fat meat '
        '61 % (59–62; bones 39); weighed on a lean-only record',
  ),
  172641: (
    share: 0.73,
    flag:
        'USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean '
        'and fat meat, slightly trimmed 73 % (61–88), as measured '
        'unfrenched; a frenched rack yields less',
  ),
  // v54 (batch M56 R3): the rack a printed trim depth moves to (engine
  // `trimDepthRecords`, 172641 → 174414) keeps 172641's AH-102 row
  // verbatim — the yield is record-keyed.
  174414: (
    share: 0.73,
    flag:
        'USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean '
        'and fat meat, slightly trimmed 73 % (61–88), as measured '
        'unfrenched; a frenched rack yields less',
  ),
  172513: (
    share: 0.70,
    flag:
        'USDA AH-102 item 1339: lamb foreleg (shank), choice, raw → lean '
        'and fat meat 70 % (bones 30; limited data)',
  ),
  169177: (
    share: 0.70,
    flag:
        'USDA AH-102 item 1937: cured ham, bone-in, rind-on, raw → lean and '
        'fat meat 70 % (60–78); the figure also removes rind 5 and excess '
        'fat 15 a spiral-sliced ham may no longer carry',
  ),
  168226: (
    share: 0.78,
    flag:
        'derived from USDA AH-102 item 1930: fresh ham shank half, raw → '
        'bones 22 %, so lean and fat meat 78 % (the printed row also trims '
        'the fat 18: lean 60 %)',
  ),
};

// LIVE STEP (plan §3 requests 1–3, spent by the owner 2026-10-05; the
// record): the whole bird and pieces ENABLED in v40 — the search "chicken
// broilers or fryers meat only raw" ranked SR 171052 first, whose detail
// publishes "unit (yield from 1 lb ready-to-cook chicken)" 197 g
// ([meatOnlyBroiler]; engine `skinlessRecords` 171447 → 171052: pressure-
// cooker-chicken-noodle-soup|8, moroccan-chicken-with-olives-and-lemon|8,
// grilled-lemon-chicken-with-rosemary|0 whole; pollo-en-mole-poblano-
// chicken-in-puebla-style-mole|15, tandoori-chicken|9 pieces, flagged).
// The breast NOT enabled: 171077 (request 1) publishes "oz" 113 g,
// "package" 926 g and "piece" 272 g — no half breast to set against
// 171474's "0.5 breast, bone removed" 145 g, so no share is formed and the
// five breast lines (hearty-chicken-noodle-soup|9, old-fashioned-slow-
// cooker-chicken-noodle-soup|12, french-style-chicken-and-stuffing-in-a-
// pot|15, tortilla-soup|3, white-chicken-chili|0) stayed at the bone yield
// until v43 (Y3) moved those that discard the skin to 2646170 at AH-102's
// breast meat share.
/// v40 (E1): SR 171052 "Chicken, broilers or fryers, meat only, raw", where
/// a skin-discarded whole bird or pieces on 171447 moves (engine
/// `skinlessRecords`): its "unit (yield from 1 lb ready-to-cook chicken)"
/// 197 g is the meat of a ready-to-cook pound (0.43; 171447's meat and skin
/// 276 g).
const int meatOnlyBroiler = 171052;

/// Whether [raw] buys shellfish IN THE SHELL: clams, mussels or oysters
/// scrubbed, live lobsters, shell-on shrimp. Shucked
/// shellfish, lobster meat and clam juice name none of those words (an
/// exclusion of "shucked", "meat" and "juice" changed no line of the
/// library: removed, refix round 1; so did "debearded" beside "scrubbed" —
/// every debearded line is scrubbed too: removed, v11). "1 pound large
/// shell-on shrimp …, peeled, deveined …, shells reserved" (0429) is held
/// too: its pound is weighed WITH the shells the cook peels off (Step 2
/// simmers them into stock and strains them out), and the user ruled
/// shellfish bought in the shell held (v11 refix: a "peeled" exclusion
/// counted it at the gross 453.59 g). ("Unpeeled" or "in the shell" shrimp
/// is no line of the library.)
/// No record FDC answered them with publishes an edible share (FNDDS "Clams,
/// raw", "Mussels", "Lobster"; SR "Crustaceans, shrimp, raw" has an ounce
/// only), so the engine holds such a line (`hold: in_shell`) rather than
/// count shell as meat — the user's ruling, checkpoint 6: 3 littleneck lines
/// had newly counted 1,361 g of shell, 5 mussel, 2 lobster and 2 shrimp
/// lines already did. The 18 lines of the library it holds: 6 clam, 6
/// mussel, 1 oyster (1184), 2 live-lobster and 3 shell-on shrimp lines (one
/// live-lobster line is a subsection's, never matched).
bool boughtInShell(String raw) {
  final line = raw.toLowerCase();
  return RegExp(r'\b(clams|mussels|oysters)\b').hasMatch(line) &&
          RegExp(r'\bscrubbed\b').hasMatch(line) ||
      RegExp(r'\blive lobsters?\b').hasMatch(line) ||
      RegExp(r'\bshell-on\b').hasMatch(line);
}

/// USER QUESTION SWITCH (whole birds, checkpoint 5). True (the audit's
/// recommendation) reads a whole-bird record's "unit (yield from 1 lb
/// ready-to-cook chicken)" portion as the edible yield of a WHOLE-bird line
/// (171447: 276 g → 0.608; 23 whole chickens counted 44,452 g gross), sizes
/// counted Cornish hens by the record's "bird" portion (171507: 336 g a hen,
/// printed 680 g), and labels pieces on the whole-bird record
/// approximate. Never a part record: 171093's turkey yield is the breast's
/// share of a turkey. False keeps the printed weights.
const bool wholeBirdYieldOn = true;

/// A line that buys a whole bird: "whole chicken", or a weighed bird ("1
/// (3½- to 4-pound) chicken, cut into 8 pieces", 0452). Neither form when
/// a part names what is bought: "4 whole chicken legs" buys legs
/// (checkpoint 5 review: the exclusion guarded only the weighed form). A
/// part after a comma is what the cook does to the bird: "1 (4-pound)
/// whole chicken, breast removed" (0002) is a whole chicken.
final RegExp _wholeBirdLine = RegExp(
  r'(?:\bwhole\s+|\)\s*)(chickens?|turkeys?)\b'
  r'(?!\s+(breasts?|thighs?|legs?|wings?|drumsticks?|parts|pieces)\b)',
  caseSensitive: false,
);

/// Whether [food] is a whole bird: no part named.
bool _wholeBirdRecord(FdcFood food) => !RegExp(
  r'\b(breast|thigh|leg|drumstick|wing|back|neck|giblets?|quarters?)\b',
).hasMatch(food.description.toLowerCase());

/// The record's "yield from 1 lb ready-to-cook <bird>" share, or null.
double? _readyToCookYield(FdcFood food) {
  for (final portion in food.portions) {
    final description = (portion.description ?? '').toLowerCase();
    if (description.contains('yield from 1 lb ready-to-cook')) {
      final share =
          portion.gramWeight /
          (portion.amount ?? 1) /
          _weightUnitGrams['pound']!;
      return share > 0 && share < 1 ? share : null;
    }
  }
  return null;
}

/// v40 (E2, plan Y2b — the live step's request 10): the basis label of a
/// shell yield ([_shellYield]); a line whose grams carry it is counted, not
/// held `in_shell` (engine `shellCounted`).
const String shellYieldLabel = 'USDA yield after shell removed';

/// v49 (M47 Q11, decided under the owner's 2026-10-07 standing
/// authorization): the shell yields FDC publishes for no record, from USDA
/// AH-102 (1975) Table 1 — the v43 source; both rows read on the page crops
/// (critic probe 12; .claude/diag/2026-10-06/ah102_produce_meat.md), keyed
/// by the raw record a weight bought in the shell ([boughtInShell]) sits on
/// (the mussel lines move there from FNDDS "Mussels", engine
/// `shellRecords`), each flagged with its item and range. The mussel flag
/// names the liquor (critic F19): every mussel recipe serves the cooking
/// liquid, which raw 174216 does not carry (item 1530, solids and liquor,
/// is 51 %).
const Map<int, ({double share, String flag})> ah102Shells = {
  175179: (
    share: 0.81,
    flag:
        'USDA AH-102 item 2333: shrimp, headless, in shell → shelled, '
        'deveined 81 % (77–82)',
  ),
  174216: (
    share: 0.29,
    flag:
        'USDA AH-102 item 1531: mussels, whole → drained solids, raw 29 % '
        '(25–33); the liquor in the pot is not counted',
  ),
};

/// [food]'s [ah102Shells] row, or null — never where the recipe eats the
/// shell ([shellEaten]: crispy salt-and-pepper shrimp, counted gross).
({double share, String flag})? _ah102ShellOf(FdcFood food, bool shellEaten) =>
    shellEaten ? null : ah102Shells[food.fdcId];

/// The share of a weight bought in the shell that is meat: SR 174214
/// "Mollusks, clam, mixed species, raw" publishes "lb (with shell), yield
/// after shell removed" 68 g (0.15 of a pound). That ONE shape, read by
/// equality — never the "with refuse, weighing N g" reader widened. v49:
/// else the record's [ah102Shells] row (shrimp 175179, mussels 174216),
/// unless [shellEaten]. Or null.
double? _shellYield(FdcFood food, {bool shellEaten = false}) {
  for (final portion in food.portions) {
    if ((portion.description ?? '').toLowerCase() ==
        'lb (with shell), yield after shell removed') {
      final share =
          portion.gramWeight /
          (portion.amount ?? 1) /
          _weightUnitGrams['pound']!;
      return share > 0 && share < 1 ? share : null;
    }
  }
  return _ah102ShellOf(food, shellEaten)?.share;
}

/// Whether [raw] counts Cornish game hens: a bird sold at one size, so the
/// record's average "bird" is the line's bird. A turkey is not: "Turkey,
/// whole, meat and skin, raw" (171081) has a 5,002 g "bird", and 12- to
/// 22-pound turkeys all read it (checkpoint-5 replay: 11 lines) — their
/// printed weight stands, pending the user.
bool countsGameHens(String raw) =>
    RegExp(r'\bgame hens?\b', caseSensitive: false).hasMatch(raw);

/// Whether [raw] buys live lobsters (v39, Y2): counted by the record's own
/// "1 lobster" portion, never their printed live weight.
bool buysLiveLobsters(String raw) =>
    RegExp(r'\blive lobsters?\b', caseSensitive: false).hasMatch(raw);

/// A counted bird on a record with a "bird" portion — only whole-bird
/// records publish one (171507, 171081) — the count and the edible grams of
/// one bird, or null. [unit] names another counted whole (v39: FNDDS's
/// "1 lobster").
({double count, double grams})? _birdGrams(
  FdcFood? food,
  List<Amount> amounts, [
  String unit = 'bird',
]) {
  final count = _countQty(amounts);
  if (food == null || count == null) {
    return null;
  }
  for (final portion in food.portions) {
    final amount = portion.amount ?? 1;
    if (RegExp('^(?:1 )?(?:$unit)\\b').hasMatch(
          (portion.description ?? '').trim(),
        ) &&
        amount > 0) {
      return (count: count, grams: portion.gramWeight / amount);
    }
  }
  return null;
}

String _countLabel(double count) => count == count.roundToDouble()
    ? count.toInt().toString()
    : count.toString();

/// The edible share of [food] as bought: FDC's own raw refuse portion
/// ("…excluding refuse (yield from 1 raw chop, with refuse, weighing 151
/// g)" = 86 g → 0.57), or its shell yield ([_shellYield], v40; v49 an
/// AH-102 row, never where the recipe eats the shell, [shellEaten]), or null
/// when the record publishes none. Under [wholeBird], a whole-bird line
/// ([raw]) on a whole-bird record also reads its ready-to-cook yield.
double? edibleYieldOf(
  FdcFood food, {
  String? raw,
  bool wholeBird = wholeBirdYieldOn,
  bool shellEaten = false,
}) {
  final share =
      _wholeBirdShare(food, raw, wholeBird) ??
      _shellYield(food, shellEaten: shellEaten);
  if (share != null) {
    return share;
  }
  final refuse = RegExp(
    r'yield from 1 raw .*with refuse, weighing ([\d.]+) ?g',
  );
  for (final portion in food.portions) {
    final gross = refuse.firstMatch((portion.description ?? '').toLowerCase());
    final weighing = gross == null ? null : double.tryParse(gross.group(1)!);
    if (weighing == null || weighing <= 0) {
      continue;
    }
    final edible = portion.gramWeight / (portion.amount ?? 1);
    if (edible > 0 && edible < weighing) {
      return edible / weighing;
    }
  }
  return null;
}

/// The ready-to-cook share [edibleYieldOf] reads for a whole-bird line
/// [raw] on a whole-bird record under [wholeBird], or null.
double? _wholeBirdShare(FdcFood food, String? raw, bool wholeBird) =>
    wholeBird &&
        raw != null &&
        _wholeBirdLine.hasMatch(raw) &&
        _wholeBirdRecord(food)
    ? _readyToCookYield(food)
    : null;

/// Words of a second part that name no food ("at room temperature",
/// "16 individual raspberries", "reserved").
const Set<String> _plusFiller = {
  'and',
  'at',
  'room',
  'temperature',
  'very',
  'cold',
  'individual',
  'reserved',
};

/// The [PlusPart] of [raw], or null: only a NUMBER right after "plus" is a
/// second amount ("plus extra for serving" is not), and a part that says
/// what it is for ("plus 2 Thai chiles, sliced thin, for serving") is an
/// optional extra, never part of the line. Memoised by text (Run 055 V1:
/// ~1 ms on a 1,000-character line, read several times per line by every
/// key, reach and rule — a matches GET of 160 such lines spent 1.5 s here).
PlusPart? plusPartOf(String raw) {
  // ponytail: whole-map clear past the cap; an LRU if a library outgrows it.
  if (_plusParts.length >= (memoCapForTest ?? 20000)) {
    _plusParts.clear();
  }
  return _plusParts.putIfAbsent(raw, () {
    plusPartReads++;
    return _plusPartOf(raw);
  });
}

final Map<String, PlusPart?> _plusParts = {};

/// The cap of every bounded process-wide memo (the plus parts here; in
/// engine.dart the step windows logged, the decision keys by line and by
/// text, the reach's holds by version, the compiled head patterns) in a
/// test: the pins fill one past it and read the first key again (Run 056
/// S21/O19: deleting any clear survived every test). Null in production.
int? memoCapForTest;

/// How many texts [plusPartOf] parsed since reset — what the tests pin its
/// memo by, never a clock.
@visibleForTesting
int plusPartReads = 0;

PlusPart? _plusPartOf(String raw) {
  // "(about 2 tablespoons plus 2 teaspoons)" restates the first amount. The
  // blanking keeps every position, so [raw] still shows where a paren was.
  final text = raw.replaceAllMapped(
    RegExp(r'\([^)]*\)'),
    (paren) => ' ' * paren[0]!.length,
  );
  final plus = RegExp(
    '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
    caseSensitive: false,
  ).firstMatch(text);
  if (plus == null) {
    return null;
  }
  var rest = text.substring(plus.end);
  final next = rest.toLowerCase().indexOf(' plus ');
  if (next >= 0) {
    rest = rest.substring(0, next);
  }
  if (RegExp(r'\bfor\b', caseSensitive: false).hasMatch(rest)) {
    return null;
  }
  // The amount and its food end at the first comma ("plus 4 tablespoons,
  // softened"); "2 additional tablespoons" is 2 tablespoons.
  final comma = rest.indexOf(',');
  final span = comma < 0 ? rest.length : comma;
  final part = rest
      .substring(0, span)
      .replaceAll(RegExp(r'\badditional\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final second = parseIngredientLine(part);
  if (second.amounts.isEmpty) {
    return null;
  }
  // The words that could name a food: not a count noun, not a participle
  // or adverb ("melted and cooled slightly"), not a filler.
  Set<String> foodWords(String? item) => {
    for (final word in itemKeyFor(item ?? '').split(' '))
      if (word.isNotEmpty &&
          !isCountNoun(word) &&
          !word.endsWith('ed') &&
          !word.endsWith('ly') &&
          !_plusFiller.contains(word))
        word,
  };
  final firstItem = parseIngredientLine(
    text.substring(0, plus.start).replaceAll(RegExp(r'\s+'), ' '),
  ).item;
  final firstWords = foodWords(firstItem);
  final secondWords = foodWords(second.item);
  return PlusPart(
    amount: second.amounts.first,
    text: part,
    // The same food both ways, not one part's words inside the other's:
    // "chipotle chile in adobo sauce plus 2 teaspoons adobo sauce" names the
    // sauce apart (the subset test summed it as the chile). A part that
    // names no food ("¼ cup plus 2 teaspoons olive oil", "plus ½
    // tablespoon, melted") is the other part's. The first part may qualify
    // the second's food: "European-style unsalted butter, very cold, plus 3
    // tablespoons unsalted butter" (0758) is butter both ways.
    sameFood:
        firstWords.isEmpty ||
        secondWords.isEmpty ||
        (firstWords.length == secondWords.length &&
            firstWords.containsAll(secondWords)) ||
        _qualifiesSame(firstItem, second.item),
    form: rest.replaceAll(RegExp(r'\s+'), ' ').trim(),
    // "½ cup (3½ ounces) plus 2 tablespoons sugar" weighs only the first.
    weighsTotal:
        raw.substring(plus.end, plus.end + span).contains('(') &&
        !raw.substring(0, plus.start).contains('('),
  );
}

/// A recipe's small measures → the FDC portion name that sizes them: FDC
/// has no "pinch", and a pinch is the same pinch of spice as its "dash".
const Map<String, String> _smallMeasures = {
  'pinch': 'dash',
  'pinches': 'dash',
  'dash': 'dash',
  'dashes': 'dash',
  'sprig': 'sprig',
  'sprigs': 'sprig',
};

/// USER QUESTION SWITCH (sprigs, audit 4 question 4). True (the default
/// until the user answers) counts a sprig the matched record gives no
/// "sprig" portion for as 0 g (`gram_source: unmeasured`, resolved): a sprig
/// of thyme or rosemary is steeped and fished out, or a garnish (58 no_grams
/// lines). False leaves it in `no_grams` for a person (or a per-herb
/// constant, if the user prefers one).
const bool sprigZeroOn = true;

/// A teaspoon over 16: a pinch or a dash when the record has no "dash"
/// portion of its own (audit 4: 66 pinch/dash lines sat in no_grams).
const double _pinchPerTeaspoon = 1 / 16;

/// Grams per unit of [amount] (its unit a [_smallMeasures] key) from the
/// food's portion whose description LEADS with that portion name (SR
/// "dash", "sprig" with the count in the structured amount; "10 sprigs"
/// with it in the text) — the
/// basis a USDA portion. A pinch or a dash without one is the food's own
/// teaspoon portion ÷ 16, and its basis says so: 67 of 130 pinch rows read
/// "USDA portion" for a portion FDC does not have (checkpoint 5).
({double grams, String basis})? _smallMeasureGrams(
  FdcFood food,
  Amount amount,
) {
  final unit = (amount.unit ?? '').toLowerCase();
  final wanted = _smallMeasures[unit];
  if (wanted == null) {
    return null;
  }
  final named = _namedPortionGrams(food, wanted);
  if (named != null) {
    return (grams: named, basis: '${_amountText(amount)} · USDA portion');
  }
  if (wanted != 'dash') {
    return null;
  }
  // v37 (Z12): a record with no teaspoon portion reads its tablespoon's
  // (FNDDS 2710093 "Hot pepper sauce" '1 tablespoon' 16 g: "Dash of hot
  // sauce", Easier Fried Chicken).
  final perTsp = _foodGramsPerMl(food, '', 'teaspoon');
  final perMl = perTsp ?? _foodGramsPerMl(food, '', 'tablespoon');
  return perMl == null
      ? null
      : (
          grams: perMl * _volumeUnitMl['teaspoon']! * _pinchPerTeaspoon,
          basis:
              '${_amountText(amount)} ≈ 1/16 tsp (USDA '
              '${perTsp == null ? 'tbsp' : 'tsp'} portion)',
        );
}

/// Grams of one [wanted] portion ('dash', 'sprig') the food names, or null.
double? _namedPortionGrams(FdcFood food, String wanted) {
  final named = RegExp('^(?:([\\d][\\d./\\s]*)\\s*)?${wanted}s?\\b');
  for (final portion in food.portions) {
    final match = named.firstMatch(
      (portion.description ?? '').toLowerCase().trim(),
    );
    if (match == null) {
      continue;
    }
    final count = match.group(1) == null
        ? portion.amount
        : _quantityValue(match.group(1)!.trim());
    if (count != null && count > 0) {
      return portion.gramWeight / count;
    }
  }
  return null;
}

/// Resolves one ingredient line to grams using its parsed [amounts], the
/// matched [food] (may be null), and the normalized item (for the fallback
/// tables). Null when nothing resolvable exists. A same-food second amount
/// ([plusPartOf]) is added: "¾ cup plus 2 tablespoons oil" is both.
///
/// [raw] is trimmed and its whitespace runs collapsed to one space HERE,
/// once, before any regex reads it: a person's line may be 1,000 characters
/// of spaces, and every read below sees the same normalized text (Run 055
/// D1: `_parsedUnit`'s lead was cubic in leading whitespace, 2 s a line).
GramResolution? resolveGrams({
  required List<Amount> amounts,
  required FdcFood? food,
  required String normalizedItem,
  String? raw,
  bool wholeBirdYield = wholeBirdYieldOn,
  bool kosherSalt = false,
  bool skinOff = false,
  String? skinKept,
  bool shellEaten = false,
  bool canLiquidEaten = false,
  bool stepsPeel = false,
}) => _resolveLine(
  amounts: amounts,
  food: food,
  normalizedItem: normalizedItem,
  raw: raw?.trim().replaceAll(_whitespaceRun, ' '),
  wholeBirdYield: wholeBirdYield,
  kosherSalt: kosherSalt,
  skinOff: skinOff,
  skinKept: skinKept,
  shellEaten: shellEaten,
  canLiquidEaten: canLiquidEaten,
  stepsPeel: stepsPeel,
);

GramResolution? _resolveLine({
  required List<Amount> amounts,
  required FdcFood? food,
  required String normalizedItem,
  required String? raw,
  required bool wholeBirdYield,
  required bool kosherSalt,
  required bool skinOff,
  required String? skinKept,
  required bool shellEaten,
  required bool canLiquidEaten,
  required bool stepsPeel,
}) {
  final parsed = raw == null
      ? amounts
      : _plusRestated(_withParsedUnits(amounts, raw), raw);
  // Read once on the raw line: the plus part is weighed without it (Run
  // 049: "1 tablespoon plus 1 teaspoon coarse sea salt" put the teaspoon
  // at table salt's 1.22).
  final kosher = kosherSalt || (raw != null && packsLikeKosherSalt(raw));
  final measured = _asPrepared(food, raw ?? normalizedItem);
  // The primary of a line with another food's weighed part is read on its
  // own text; it weighs nothing, the part's printed weight stands in.
  final other = raw == null ? null : _otherFoodPart(raw);
  final own = other?.own ?? raw;
  var first = _resolveGrams(
    amounts: parsed,
    food: measured,
    normalizedItem: normalizedItem,
    raw: own,
    kosher: kosher,
  );
  first ??= own == null
      ? null
      : _parenVolumeGrams(parsed, measured, normalizedItem, own);
  if (first == null && other != null) {
    first = _resolveGrams(
      amounts: [other.part],
      food: measured,
      normalizedItem: normalizedItem,
      kosher: kosher,
    );
  }
  // v37 (Z7): a volume line nothing sized, by its own "(about N noun)"
  // count of the item ([_parenCount]).
  final counted = first != null || own == null
      ? null
      : _parenCount.firstMatch(own);
  if (counted != null &&
      parsed.any((a) => a.measure == Measure.volume) &&
      normalizedItem
          .split(' ')
          .map(keyWordOf)
          .contains(keyWordOf(counted[2]!))) {
    final each = _resolveGrams(
      amounts: [
        Amount(measure: Measure.count, quantity: counted[1]!, primary: true),
      ],
      food: measured,
      normalizedItem: normalizedItem,
    );
    if (each != null) {
      first = GramResolution(
        grams: each.grams,
        source: each.source,
        basis: '${counted[0]} · ${each.basis}',
      );
    }
  }
  final bird =
      wholeBirdYield &&
          first?.source == GramSource.weight &&
          raw != null &&
          countsGameHens(raw)
      ? _birdGrams(food, parsed)
      : null;
  if (bird != null) {
    // A counted bird is the record's own edible bird, not the printed gross
    // weight: 4 Cornish hens are 4 × 336 g on 171507, not 4 × 680 g.
    return GramResolution(
      grams: bird.count * bird.grams,
      source: GramSource.piece,
      basis:
          '${_countLabel(bird.count)} × ${bird.grams.round()} g '
          '(USDA edible bird portion)',
    );
  }
  // v39 (Y2, plan Q3 (b)): a counted live lobster is the record's own "1
  // lobster" (FNDDS 2706349, 200 g, whatever its size), never its printed
  // live weight: 2 × 200 g, not 2 × 907 g of shell.
  final lobster =
      first?.source == GramSource.weight && raw != null && buysLiveLobsters(raw)
      ? _birdGrams(food, parsed, 'lobster')
      : null;
  if (lobster != null) {
    return GramResolution(
      grams: lobster.count * lobster.grams,
      source: GramSource.piece,
      basis:
          '${_countLabel(lobster.count)} × ${lobster.grams.round()} g · '
          "approximate (FDC's 1-lobster portion)",
    );
  }
  // v39 (A3, the owner's ruling Q6): a prep-loss word counts only on a
  // purchase weight — the printed weight, the word after the item, in the
  // line's tail ([_tailAfterComma]): "6 large very ripe bananas (about 2¼
  // pounds), peeled" is 6 × the record's own "Peeled" banana (1105314, 115
  // g), not 1,020.6 g of fruit and peel. A head word ("whole peeled
  // tomatoes") names a prepared product; a count read is edible already.
  final peeled =
      first?.source == GramSource.weight && raw != null && peeledAfterItem(raw)
      ? _birdGrams(food, parsed, 'Peeled')
      : null;
  if (peeled != null) {
    return GramResolution(
      grams: peeled.count * peeled.grams,
      source: GramSource.piece,
      basis:
          '${_countLabel(peeled.count)} × ${peeled.grams.round()} g '
          '(USDA "Peeled" portion)',
    );
  }
  final refuse =
      edibleYieldOn &&
      first?.source == GramSource.weight &&
      food != null &&
      raw != null &&
      buysRefuse(raw);
  final yieldFactor = refuse
      ? edibleYieldOf(
          food,
          raw: raw,
          wholeBird: wholeBirdYield,
          shellEaten: shellEaten,
        )
      : null;
  if (yieldFactor != null) {
    // A whole bird's share is the record's ready-to-cook yield, not a refuse
    // portion (checkpoint 6: the basis said "USDA refuse" for both).
    final readyToCook = _wholeBirdShare(food!, raw, wholeBirdYield) != null;
    // v40: a meat-only bird whose recipe keeps part of the skin (0637
    // "leaving skin on wings", the caller's `skinKeptPart`) — the plan's
    // flag names the part.
    final keptFlag =
        readyToCook &&
            skinOff &&
            skinKept != null &&
            food.fdcId == meatOnlyBroiler
        ? ' · approximate (skin discarded except the $skinKept; '
              "the bird's meat-only yield)"
        : '';
    // v49 (M47 Q11): an AH-102 shell row names its item, flagged.
    final shell = readyToCook ? null : _ah102ShellOf(food, shellEaten);
    first = GramResolution(
      grams: first!.grams * yieldFactor,
      source: first.source,
      basis: shell != null
          ? '${first.basis} × ${yieldFactor.toStringAsFixed(2)} edible · '
                'approximate (${shell.flag})'
          : '${first.basis} × ${yieldFactor.toStringAsFixed(2)} edible '
                '(${readyToCook
                    ? 'USDA ready-to-cook yield'
                    : _shellYield(food) != null
                    ? shellYieldLabel
                    : 'USDA refuse'})$keptFlag',
    );
  } else if (refuse) {
    // The record publishes no refuse portion: the bone (a whole turkey's,
    // a Foundation chicken part's, a lamb chop's; pieces on the whole-bird
    // record, whose yield is the whole bird's) is counted at the gross
    // weight — never a borrowed factor (FDC gives no turkey share; the
    // chicken 0.61 is not a turkey's) — and the basis says approximate: the
    // user's ruling, checkpoint 6. Only SR Legacy publishes refuse, so an
    // SR search hit whose detail was never fetched (no portions) says only
    // that no yield was read: its record may publish one. Shellfish in the
    // shell is labelled the same — held `in_shell`, and approximate once a
    // person's confirm counts it at its gross weight (v11).
    final noRefuse = food.dataType != 'SR Legacy' || food.portions.isNotEmpty;
    // v39 (Y1, the owner's ruling 2026-10-05, revising CP6 #11 and #5): a
    // record that publishes none reads its class's FDC figure, flagged —
    // never a whole bird's with [wholeBirdYield] off, which keeps whole
    // birds at their printed weight.
    final classed =
        noRefuse && (wholeBirdYield || !_wholeBirdLine.hasMatch(raw));
    // v43 (Y1–Y6, Y12, Y13): a bird part reads AH-102's figure for the part
    // the line buys, in one step, the record deciding meat or meat and skin
    // ([ah102YieldOf]) — pieces on the meat-only broiler 171052 too (v40's
    // whole-bird 0.43 retired); the v40 wing flag stays on the whole bird.
    final part = classed
        ? ah102YieldOf(food, raw) ?? ah102Meats[food.fdcId]
        : null;
    final byClass = classed && part == null
        ? boneInClassYields[food.fdcId]
        : null;
    first = part != null
        ? GramResolution(
            grams: first!.grams * part.share,
            source: first.source,
            basis:
                '${first.basis} × ${part.share.toStringAsFixed(2)} edible '
                '· approximate (${part.flag})',
          )
        : byClass != null
        ? GramResolution(
            grams: first!.grams * byClass.share,
            source: first.source,
            basis:
                '${first.basis} × ${byClass.share.toStringAsFixed(2)} edible '
                '· approximate (yield of ${byClass.yieldOf} from FDC '
                '${byClass.from})',
          )
        : GramResolution(
            grams: first!.grams,
            source: first.source,
            basis: noRefuse
                ? '${first.basis} · approximate (gross weight, no USDA refuse '
                      'portion)'
                : '${first.basis} · no edible yield read',
          );
  }
  // v43 (Y12, Y13): the skin is no longer a second step. The record
  // decides ([ah102Records]): a meat-only record — where the engine moves a
  // row whose recipe discards the skin (`skinOffFood`), or where a person
  // put it — reads the part's meat figure from the printed weight; v39's
  // stack (the bone yield × FDC SR's skin share, 0.795 thigh / 0.770 leg)
  // is retired. [skinOff] now only names the part a meat-only whole bird
  // keeps its skin on (the flag above).
  final drained = first?.source == GramSource.weight && raw != null
      ? drainedCanGrams(first!.grams, food, raw)
      : null;
  if (drained != null) {
    first = GramResolution(
      grams: drained,
      source: GramSource.weight,
      basis: '${first!.basis} · drained (USDA can portion)',
    );
  }
  // v39 (T1, the owner's ruling Q6 (a)): a canned tomato drained in the
  // tail with its juice not kept counts ATK's printed solids share, flagged.
  // A line that reserves juice puts it back later: untouched.
  if (first?.source == GramSource.weight &&
      raw != null &&
      _cannedTomatoRecords.contains(food?.fdcId) &&
      RegExp(r'\bdrained\b').hasMatch(_tailAfterComma(raw)) &&
      !RegExp(r'\breserved?\b', caseSensitive: false).hasMatch(raw)) {
    first = GramResolution(
      grams: first!.grams * drainedTomatoShare,
      source: first.source,
      basis:
          '${first.basis} × $drainedTomatoShare drained · approximate (ATK: '
          '2 (28-ounce) cans whole tomatoes, drained, give 3 cups juice)',
    );
  }
  // v42 (B, the owner's 2026-10-06 ruling (b)): a can of beans weighed by
  // its printed weight on a drained-and-rinsed record counts its bean's
  // drained share ([cannedBeanShares]) — unless the line keeps the liquid.
  // v49 (M47 Q14 (i)): so does one whose liquid the steps add
  // ([canLiquidEaten], the engine's step read) — on its solids-and-liquids
  // record where one is cached ([cannedBeanLiquids]), else said.
  final canLine =
      first?.source == GramSource.weight &&
      raw != null &&
      RegExp(r'\bcans?\b').hasMatch(raw.toLowerCase());
  final bean = canLine ? cannedBeanShares[food?.fdcId] : null;
  final added =
      canLine &&
      canLiquidEaten &&
      !_keepsBeanLiquid.hasMatch(raw.toLowerCase());
  if (bean != null) {
    final half = halvesCans(raw!);
    if (!keepsWholeCan(raw, liquidEaten: canLiquidEaten)) {
      final share = bean.share.toStringAsFixed(3);
      // v49 (M47 Q14 (ii)): the undrained can is its own part on the
      // solids-and-liquids record (engine `withParts`).
      final liquid = half && cannedBeanLiquids.containsKey(food?.fdcId)
          ? ' · the undrained can on its solids-and-liquids record'
          : '';
      first = GramResolution(
        grams: first!.grams * (half ? (1 + bean.share) / 2 : bean.share),
        source: first.source,
        basis:
            '${first.basis} × $share drained${half ? ' on half the cans' : ''} '
            '· approximate (drained weight: ${bean.from})$liquid',
      );
    } else if (added) {
      final flag = cannedBeanLiquids.containsKey(food?.fdcId)
          ? ''
          : _noLiquidRecord;
      first = GramResolution(
        grams: first!.grams,
        source: first.source,
        basis: '${first.basis} (the steps add the beans and their liquid)$flag',
      );
    }
  } else if (added && cannedBeanLiquids.containsValue(food?.fdcId)) {
    first = GramResolution(
      grams: first!.grams,
      source: first.source,
      basis: '${first.basis} (the steps add the beans and their liquid)',
    );
  }
  // v43 (Y8, the owner's 2026-10-06 ruling): a produce weight printed in
  // the line's HEAD with a prep word in its tail counts AH-102's prep yield
  // ([produceYields]); a count, a trailing prepared weight, "unpeeled" and
  // "¼ of peels reserved" never. v59 (M60 P7a): or a step pares it
  // ([stepsPeel], the engine's step read).
  final prep = first?.source == GramSource.weight && raw != null
      ? produceYieldOf(food, raw, stepsPeel: stepsPeel)
      : null;
  // v43 (Y9): a counted scallion's part words ([scallionPartOf]).
  final scallion = first?.source == GramSource.piece && raw != null
      ? scallionPartOf(food, raw)
      : null;
  final trim = prep ?? scallion;
  if (trim != null) {
    first = GramResolution(
      grams: first!.grams * trim.share,
      source: first.source,
      basis:
          '${first.basis} × ${trim.share.toStringAsFixed(2)} edible · '
          'approximate (${trim.flag})',
    );
  }
  final plus = raw == null || first == null ? null : plusPartOf(raw);
  // A counted extra of the same food ("plus 1 lemon, cut into wedges") is
  // for serving, not in the dish; only a measured second amount is added.
  if (plus == null ||
      !plus.sameFood ||
      plus.amount.measure == Measure.count ||
      (plus.weighsTotal && first!.source == GramSource.weight)) {
    return first;
  }
  // The part is the line's form too: "1 ounce Parmesan cheese, grated
  // (½ cup), plus 2 tablespoons" weighs its 2 tablespoons grated, 0.24
  // (Run 054 O10/S6: 0.42, read with no words) — unless the part names its
  // own: "¼ cup grated Parmesan cheese plus 2 cups shredded" weighs its 2
  // cups shredded, 0.36 (Run 055 O7: the line's first form, grated, read
  // them 57 g under) — after its comma too: "plus 2 cups, shredded" (Run
  // 056 O11/S12: the part's words stopped at the comma, 127.6 g for 184.3).
  final second = _resolveGrams(
    amounts: [plus.amount],
    food: measured,
    normalizedItem: normalizedItem,
    kosher: kosher,
    words: _hardCheeseForm.hasMatch(plus.form.toLowerCase()) ? plus.form : raw,
  );
  if (second == null) {
    return first;
  }
  return GramResolution(
    grams: first!.grams + second.grams,
    // "3 sprigs tarragon plus 1 teaspoon minced": the sprigs are 0 g, the
    // teaspoon is what the line measures.
    source: first.source == GramSource.unmeasured
        ? second.source
        : first.source,
    // v62 (M64 R-D): kosher salt's suffix closes the whole line ("2
    // tablespoon ≈ 30 mL + 2 teaspoons kosher salt · kosher salt at …").
    basis: first.basis?.endsWith(_kosherSaltBasis) ?? false
        ? '${first.basis!.replaceFirst(_kosherSaltBasis, '')} + '
              '${plus.text}$_kosherSaltBasis'
        : '${first.basis ?? ''} + ${plus.text}',
  );
}

/// [amounts] without an amount the parse took from a parenthesis after
/// "plus" (never the line's primary) when that "plus" part prints its own
/// weight: the parenthesis restates the part, which weighs what it prints
/// — "1 Parmesan cheese rind, plus 3 ounces Parmesan, shredded (1 cup)"
/// (0403) is the 3 ounces, 85.05 g, never 1 cup by a density (99.37 g). A
/// part of the same food is added after ([resolveGrams]). A part of
/// ANOTHER food is that food's restatement only: the line weighs its own
/// primary, and the part's printed weight stands in only when the primary
/// resolves to nothing (0403's rind) — Run 054 O9/S7: "2 tablespoons pine
/// nuts plus 1 ounce Parmesan, grated (½ cup)" weighed the pine-nut line
/// at the Parmesan's 28.35 g ([_otherFoodPart]).
List<Amount> _plusRestated(List<Amount> amounts, String raw) {
  final plus = plusPartOf(raw);
  final at =
      RegExp(
        '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
        caseSensitive: false,
      ).firstMatch(
        raw.replaceAllMapped(RegExp(r'\([^)]*\)'), (p) => ' ' * p[0]!.length),
      );
  if (plus == null || plus.amount.measure != Measure.weight || at == null) {
    return amounts;
  }
  final restated = [
    // "(about 2 cups; see note)" restates 2 cups. Every paren is read: one
    // before the "plus" parses as the primary's own amount, which
    // `amount.primary` keeps (Run 054 S13: the scope to after the "plus"
    // moved none of 13,615 corpus lines — deleted).
    for (final paren in RegExp(
      r'\((?:about\s+)?([^);]*)',
    ).allMatches(raw))
      ...parseIngredientLine(paren[1]!).amounts,
  ];
  return [
    for (final amount in amounts)
      if (amount.primary ||
          !restated.any(
            (r) => r.quantity == amount.quantity && r.unit == amount.unit,
          ))
        amount,
  ];
}

/// A "plus" part of ANOTHER food that prints its weight and whose
/// parenthesis restates it ([_plusRestated]): the part, and the line's own
/// text before the "plus" — what the primary is weighed on, so the part's
/// parenthesis never sizes it (step 1c read 0403's "(1 cup)" for the rind);
/// else null.
({Amount part, String own})? _otherFoodPart(String raw) {
  final plus = plusPartOf(raw);
  final at = RegExp(r'\bplus\b[^(]*\(', caseSensitive: false).firstMatch(raw);
  return plus == null ||
          plus.sameFood ||
          plus.amount.measure != Measure.weight ||
          at == null
      ? null
      : (part: plus.amount, own: raw.substring(0, at.start));
}

/// [food] without the portion that measures what it is made FROM, on a
/// line that names the PREPARED form: 2708216 Popcorn's "1 cup, unpopped,
/// yields" 193 g is what a cup of kernels makes, and sized "1 cup lightly
/// salted popcorn" (Red Snapper Ceviche) 13.8x over its "1 cup, popped"
/// 14 g (v21 closer). Only a popcorn line, and only on a record with a
/// popped portion to read instead (v23, Run 053 O3): a line measuring the
/// kernels ("½ cup popcorn kernels", "unpopped") keeps the yields portion
/// — the popped mass those kernels make, which this record's nutrients are
/// for — and so does every other food's own yields portion (a gelatin
/// package's 540 g, a coconut's 206 g), which v22 stripped for any line.
///
/// The MEASURED head decides (Run 054 O8: any "kernel" in the line kept
/// the yields cup for "8 cups popped popcorn (from ⅓ cup kernels)", 1,544
/// g for 112): what the amount measures, never where it came from
/// ([_measuredHead]). Kettle and caramel corn are popped.
FdcFood? _asPrepared(FdcFood? food, String line) {
  final head = _measuredHead(line.toLowerCase());
  if (food == null ||
      !RegExp(
        r'\bpop(?:corn|ped)\b|\b(?:kettle|caramel) corn\b',
      ).hasMatch(head) ||
      RegExp(r'\b(?:unpopped|kernel)').hasMatch(head)) {
    return food;
  }
  final unpopped = RegExp(r'\bunpopped\b');
  final kept = [
    for (final portion in food.portions)
      if (!unpopped.hasMatch((portion.description ?? '').toLowerCase()))
        portion,
  ];
  return kept.length == food.portions.length ||
          !kept.any(
            (p) => RegExp(
              r'\bpopped\b',
            ).hasMatch((p.description ?? '').toLowerCase()),
          )
      ? food
      : FdcFood(
          fdcId: food.fdcId,
          description: food.description,
          dataType: food.dataType,
          nutrientsPer100g: food.nutrientsPer100g,
          portions: kept,
        );
}

/// The words of [text] (a lower-cased line) its amount measures — the
/// item's noun phrase (Run 055 O6/S9: v24 cut the line at its FIRST paren,
/// so "6 cups (1 bag) popped popcorn" lost its "popped" and weighed 1,158 g
/// for 84, and "½ cup popcorn (unpopped)" lost its "unpopped", 7 g for
/// 96.5): a paren — and a comma part after the first — QUALIFIES the head
/// and is read as a modifier when every word of it is a qualifier
/// ([_qualifies]: "(unpopped)", "(unpopped kernels)", "(raw kernels)",
/// "(dry, unpopped)", ", unpopped kernels"); any other is a note on the
/// line and is dropped — one that sizes or sources the amount ("(1 bag)",
/// "(from ⅓ cup kernels)", "(about)") or a part removed, discarded or
/// reserved ("(unpopped kernels discarded)", "(old maids and kernels
/// removed)", Run 056 O10: read as a modifier, its "unpopped" restored the
/// 193 g kernel cup to a popped line, 13.8×). An unclosed paren is dropped
/// to the end, and the line is cut at a "from" outside a paren ("popped
/// popcorn from ⅓ cup kernels"). One pass.
String _measuredHead(String text) {
  final out = StringBuffer();
  var open = -1;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (open < 0 && c == '(') {
      open = i;
    } else if (open >= 0 && c == ')') {
      final inner = text.substring(open + 1, i);
      if (_qualifies(inner)) {
        out.write(' $inner ');
      }
      open = -1;
    } else if (open < 0) {
      out.write(c);
    }
  }
  // A comma part is read by the same rule: ", unpopped kernels" qualifies,
  // ", unpopped kernels discarded" is a note.
  final parts = out.toString().split(',');
  final head = [
    parts.first,
    for (final part in parts.skip(1))
      if (_qualifies(part)) part,
  ].join(',');
  final from = RegExp(r'\bfrom\b').firstMatch(head);
  return from == null ? head : head.substring(0, from.start);
}

/// Whether a paren or comma [part] qualifies the measured head
/// ([_measuredHead]): every word of it is a qualifier of what the
/// amount measures ([_qualifierWords]) — by vocabulary, not by count (Run
/// 057 S6/O8/O13: v26 read any part of two or more words as a note, so "½
/// cup popcorn (unpopped kernels)" weighed as popped, 96.5 g → 7.0 g). A
/// number, a "from", or a removal or reservation verb ("discarded",
/// "removed", "reserved", "for another use") is never a qualifier: such a
/// part is a note.
bool _qualifies(String part) {
  final words = _partWord.allMatches(part).map((m) => m[0]!).toList();
  return words.every(_qualifierWords.contains);
}

/// The words that say what a popcorn amount measures ([_qualifies]).
const Set<String> _qualifierWords = {
  'unpopped',
  'popped',
  'air-popped',
  'kernel',
  'kernels',
  'raw',
  'dry',
  'plain',
  'yellow',
  'white',
};

/// A word of a paren or comma part, hyphens kept ("air-popped"), a number
/// or a fraction a word of its own ([_qualifies]).
final RegExp _partWord = RegExp(
  '[a-z]+(?:-[a-z]+)*|[\\d$vulgarFractionChars]+',
);

/// A count unit sized by the volume printed before it, when the count
/// finds no grams: "1 (750-ml) bottle red Burgundy or Pinot Noir" (Modern
/// Beef Burgundy) is 750 mL on the wine's own portions (checkpoint 8).
GramResolution? _parenVolumeGrams(
  List<Amount> amounts,
  FdcFood? food,
  String normalizedItem,
  String raw,
) {
  final printed = RegExp(
    r'\((\d[\d.]*)[-\s]?(ml|milliliters?|liters?)\)',
    caseSensitive: false,
  ).firstMatch(raw);
  final count = _countQty(amounts);
  if (printed == null || count == null) {
    return null;
  }
  // "(1-liter) bottle": no ATK line prints litres; other libraries do
  // (Run 048).
  final ml =
      count *
      double.parse(printed[1]!) *
      (printed[2]!.toLowerCase().startsWith('l') ? 1000 : 1);
  return _resolveGrams(
    amounts: [
      Amount(
        measure: Measure.volume,
        quantity: ml == ml.roundToDouble() ? '${ml.toInt()}' : '$ml',
        unit: 'ml',
        primary: true,
      ),
    ],
    food: food,
    normalizedItem: normalizedItem,
  );
}

/// The volume a raw parenthetical prints for the whole line — "(about 2
/// cups; optional)", "(½ cup plus 3 tablespoons)", both parts: Champagne
/// Cocktail's "5½ fluid ounces (½ cup plus 3 tablespoons) champagne",
/// stored as the bare count 5½, read 990 g as 5½ "punch" servings — as an
/// amount; null for none. A paren that says "each", or an adjectival one
/// (nothing but the count before it), prints ONE item's volume, as
/// [_parenWeight] reads a weight: "2 ripe pears, sliced (about 1 cup each)"
/// is [count] cups (Run 048; no corpus line prints one — kept for other
/// libraries), null with no count. [perItemOnly]: null for a total. Pints
/// and quarts too, hyphenated as a container's size: "2 (1-pint) containers
/// coffee ice cream" is 2 pints (Baked Alaska; v21 plan G4).
Amount? _parenVolume(String raw, double? count, {bool perItemOnly = false}) {
  final q = '([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ .]*?)';
  const u = r'[\s-]*(cups?|tablespoons?|teaspoons?|pints?|quarts?)\b';
  final match = RegExp(
    '\\((?:about\\s+)?$q$u(?:\\s+plus\\s+$q$u)?',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  final close = raw.indexOf(')', match.start);
  final perUnit =
      raw
          .substring(match.start, close < 0 ? raw.length : close)
          .toLowerCase()
          .contains(RegExp(r'\beach\b')) ||
      !RegExp('[a-z]', caseSensitive: false).hasMatch(
        raw.substring(0, match.start),
      );
  final times = perUnit ? count : 1.0;
  if (times == null || (perItemOnly && !perUnit)) {
    return null;
  }
  String unit(String word) => word.toLowerCase().replaceAll(RegExp(r's$'), '');
  if (match[3] == null && times == 1) {
    return Amount(
      measure: Measure.volume,
      quantity: match[1]!.trim(),
      unit: unit(match[2]!),
      primary: true,
    );
  }
  double? ml(String quantity, String word) {
    final n = _quantityValue(quantity.trim());
    return n == null ? null : n * _volumeUnitMl[unit(word)]!;
  }

  final first = ml(match[1]!, match[2]!);
  final second = match[3] == null ? 0.0 : ml(match[3]!, match[4]!);
  return first == null || second == null
      ? null
      : Amount(
          measure: Measure.volume,
          quantity: ((first + second) * times).toStringAsFixed(0),
          unit: 'ml',
          primary: true,
        );
}

/// A line that opens with a quantity and a volume unit.
final RegExp _lostVolumeUnit = RegExp(
  '^\\s*[\\d$vulgarFractionChars/.-][\\d$vulgarFractionChars/ .-]*'
  r'(cups?|tablespoons?|teaspoons?)\b',
  caseSensitive: false,
);

/// A line that opens with a quantity, a size and a sprig: "2 small sprigs
/// fresh rosemary" parsed as the bare count 2 (checkpoint 5: 5 no_grams
/// lines) — or a pinch (v37, Z12: "1 small pinch saffron", Espinacas con
/// Garbanzos, the corpus's only one, is one pinch).
final RegExp _sizedSprig = RegExp(
  '^\\s*[\\d$vulgarFractionChars/.-][\\d$vulgarFractionChars/ .-]*'
  r'(small|medium|large)\s+(sprig|pinch)(?:s|es)?\b',
  caseSensitive: false,
);

/// [amounts] with a unit the corpus parse lost read back from [raw]: the
/// bare count of "3 tablespoons plus 1½ teaspoons peanut or vegetable oil"
/// (the "plus … or" parse, 5 no_grams lines) is 3 tablespoons, and "2 small
/// sprigs" is 2 sprigs. Only when the raw's leading number is the amount's.
List<Amount> _withParsedUnits(List<Amount> amounts, String raw) => [
  for (final amount in amounts)
    if (amount.measure != Measure.count || (amount.unit ?? '').isNotEmpty)
      amount
    else
      _parsedUnit(amount, raw) ?? amount,
];

final _whitespaceRun = RegExp(r'\s+');

/// [_parsedUnit] on a raw no entry normalized (the regex's own pin).
@visibleForTesting
Amount? parsedUnitForTest(Amount amount, String raw) =>
    _parsedUnit(amount, raw);

Amount? _parsedUnit(Amount amount, String raw) {
  // The number run's class has no space and its words are joined by
  // " +": nothing in it overlaps the anchors' \s* (the lazy run with a space
  // in its class was cubic in leading whitespace — Run 055 D1).
  final lead = RegExp(
    '^\\s*([\\d$vulgarFractionChars/.-]+(?: +[\\d$vulgarFractionChars/.-]+)*)'
    r'\s*[a-z]',
    caseSensitive: false,
  ).firstMatch(raw);
  final quantity = _quantityValue(amount.quantity);
  // "1 dozen mussels" (Paella, 0105) parsed as a count of 1: a dozen is 12,
  // as the yield parser reads it ([parseYieldCount]) — for the amount the
  // raw's LEADING number is, as below: a second bare count on the line is
  // no dozen. No corpus line has a second count or a later "dozen", so both
  // guards are pinned on synthesized lines (stated exceptions, v13).
  final dozen = RegExp(
    '^\\s*([\\d$vulgarFractionChars/.-]+(?: +[\\d$vulgarFractionChars/.-]+)*)'
    r'\s*dozen\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (dozen != null &&
      quantity != null &&
      _quantityValue(dozen.group(1)!.trim()) == quantity) {
    final n = quantity * 12;
    return Amount(
      measure: Measure.count,
      quantity: n == n.roundToDouble() ? '${n.toInt()}' : '$n',
      approximate: amount.approximate,
      primary: amount.primary,
    );
  }
  if (lead == null ||
      quantity == null ||
      _quantityValue(lead.group(1)!.trim()) != quantity) {
    return null;
  }
  final volume = _lostVolumeUnit.firstMatch(raw)?.group(1);
  final unit = volume != null
      ? _volumeAliases[volume.toLowerCase()] ??
            volume.toLowerCase().replaceAll(RegExp(r's$'), '')
      : _sizedSprig.firstMatch(raw)?.group(2)?.toLowerCase();
  return unit == null
      ? null
      : Amount(
          measure: volume != null ? Measure.volume : Measure.count,
          quantity: amount.quantity,
          unit: unit,
          approximate: amount.approximate,
          primary: amount.primary,
        );
}

/// USER ANSWER SWITCH (canned beans, audit 3). True (the default) counts a
/// can or jar the line drains or rinses at its DRAINED weight: the printed
/// net weight × the drained share the food's own USDA portion gives ("can
/// (12.5 oz), drained" = 321 g of 354 g: 0.91 for oil-packed tuna, 173708)
/// — never that portion's can size in place of the line's ("2 (6½-ounce)
/// jars"). False counts the net weight. Only a record whose drained portion
/// names its can size changes anything; the canned-bean records are pending
/// live detail fetches, so until then their net weight stands.
const bool cannedDrained = true;

/// The solids share of a drained can of tomatoes (v39 T1): ATK prints "2
/// (28-ounce) cans whole tomatoes …, drained, 3 cups juice reserved"
/// (Ultimate Cream of Tomato Soup) — 3 cups of juice by SR's juice cup out
/// of 1,587.6 g leaves 0.54.
const double drainedTomatoShare = 0.54;

/// A canned bean's drained share (v42, the owner's 2026-10-06 ruling (b)),
/// keyed by the Foundation "canned, sodium added, drained and rinsed" record
/// its can lines sit on: FDC's own SR can pair, drained ÷ whole, to 3 dp
/// (chickpea 173800 "can drained" 253 g of 175206 "can (total can
/// contents)" 448 g; kidney 174285 "can drained solids" 266 g of 175195
/// "can" 436 g; pinto 174286 277 g of 175201 "can" 442 g). Black,
/// cannellini and navy have no pair: the three pairs' median
/// ([cannedBeanMedian]). The rinsed kidney record 175243 publishes a cup
/// only, so rinsing adds no factor.
const Map<int, ({double share, String from})> cannedBeanShares = {
  2644288: (share: 0.565, from: "FDC's canned chickpea pair, 253 g of 448 g"),
  2644289: (
    share: 0.610,
    from: "FDC's canned kidney bean pair, 266 g of 436 g",
  ),
  2644292: (share: 0.627, from: "FDC's canned pinto bean pair, 277 g of 442 g"),
  2644285: _beanMedian,
  2644287: _beanMedian,
  2644286: _beanMedian,
};

/// The median of the three canned-bean pairs' shares (0.565, 0.610, 0.627).
const double cannedBeanMedian = 0.610;

const _beanMedian = (
  share: cannedBeanMedian,
  from: "the median of FDC's three canned-bean pairs, 0.610",
);

/// A canned-bean line that keeps the can's liquid: the can counts whole.
final RegExp _keepsBeanLiquid = RegExp(
  r'\b(?:undrained|do not drain|liquid reserved|with their liquid)\b',
);

/// v49 (M47 Q14 (ii), critic F6 — the record the 2026-10-06 ruling's "keeps
/// the can whole" left unruled): the canned "solids and liquids" record of
/// a drained-and-rinsed can record ([cannedBeanShares]), the food as a line
/// that keeps the liquid uses it — the SR can pairs' whole-can halves, each
/// a cached detail: chickpeas 175206, pinto 175201, kidney 175195. A can
/// kept whole moves there (engine `skinOffFood`), the undrained can of the
/// half rule is a part there (engine `withParts`), grams unchanged, no
/// flag. Black, cannellini and navy have none cached (SR 173747 "Beans,
/// navy, mature seeds, canned" names no state: not read).
const Map<int, int> cannedBeanLiquids = {
  2644288: 175206,
  2644292: 175201,
  2644289: 175195,
};

/// The flag of a can kept whole on a drained-and-rinsed record with no
/// solids-and-liquids twin ([cannedBeanLiquids]; v49, M47 Q14: navy).
const String _noLiquidRecord =
    ' · approximate (no solids-and-liquids record for this bean: the '
    'drained-and-rinsed record for the whole can)';

/// Whether [raw] keeps 1 can drained and 1 undrained (the half rule, v42).
bool halvesCans(String raw) => RegExp(
  r'\b1 can drained\b.*\b1 can (?:left )?undrained\b',
).hasMatch(raw.toLowerCase());

/// Whether the can of [raw] counts whole: the line keeps its liquid
/// ([_keepsBeanLiquid]) — or (v49, M47 Q14 (i)) names no drain or rinse
/// word while the steps add it with its liquid ([liquidEaten]) — and is not
/// the half rule ([halvesCans]).
bool keepsWholeCan(String raw, {bool liquidEaten = false}) {
  final text = raw.toLowerCase();
  return !halvesCans(text) &&
      (_keepsBeanLiquid.hasMatch(text) ||
          liquidEaten && !RegExp(r'\b(drained|rinsed)\b').hasMatch(text));
}

/// The canned-tomato records every drained canned-tomato line sits on
/// (Foundation 333281 diced, 2685578 whole; neither publishes drained
/// solids).
const Set<int> _cannedTomatoRecords = {333281, 2685578};

/// [raw]'s tail after its first top-level comma (one outside a paren),
/// lower-cased; '' for none. A prep-loss word applies only here (v39 A3,
/// T1): "6 large very ripe bananas (about 2¼ pounds), peeled".
String _tailAfterComma(String raw) {
  final at = _topLevelComma(raw);
  return at < 0 ? '' : raw.substring(at + 1).toLowerCase();
}

/// [raw] before its first top-level comma ([_topLevelComma]); all of it
/// with none — where a size word sizes the item ("2 large kiwis, …"), never
/// "cut into large pieces".
String _headBeforeComma(String raw) {
  final at = _topLevelComma(raw);
  return at < 0 ? raw : raw.substring(0, at);
}

/// The index of [raw]'s first comma outside a paren, or -1.
int _topLevelComma(String raw) {
  var depth = 0;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == '(') {
      depth++;
    } else if (c == ')' && depth > 0) {
      depth--;
    } else if (c == ',' && depth == 0) {
      return i;
    }
  }
  return -1;
}

/// v43 (Y8, the owner's 2026-10-06 ruling): USDA AH-102 (1975) Table 1
/// paring and trimming yields, by the produce record the row sits on: the
/// tail words that name the prep (word-bounded, first match wins), the
/// share and its flag (item, the printed stage, the all-samples average and
/// range — no Granny Smith or Yukon Gold row exists). Read by
/// [produceYieldOf].
const Map<int, List<({String words, double share, String flag})>>
produceYields = {
  2346401: _potato,
  2346402: _potato,
  2346403: _potato,
  1750342: _apple,
  168202: _apple,
  2709215: _apple,
  168482: [
    (
      words: 'peeled',
      share: 0.80,
      flag:
          'USDA AH-102 item 2496: sweetpotatoes, raw whole → hand or machine '
          'pared 80 % (69–91)',
    ),
  ],
  167778: _pear,
  746773: _pear,
  2258586: [
    (
      words: 'peeled',
      share: 0.82,
      flag:
          'USDA AH-102 item 481: carrots without tops, raw → hand-scraped '
          'root 82 % (58–93)',
    ),
  ],
  1104962: [
    (
      words: 'peeled',
      share: 0.90,
      flag:
          'USDA AH-102 item 1568: onions, mature, all samples, raw whole → '
          'peeled 90 % (50–99)',
    ),
  ],
  2709935: [
    (
      words: 'white and light green parts?',
      share: 0.44,
      flag:
          'USDA AH-102 item 1412: leeks, raw → bulb and lower leaf 44 % '
          '(35–58)',
    ),
  ],
  170388: [
    (
      words: 'cored|trimmed',
      share: 0.93,
      flag:
          'USDA AH-102 item 440: cabbage, whole head, green, red or white '
          '(savoy not printed), raw → ready to cook, without core 93 % '
          '(91–96)',
    ),
  ],
  2685573: [
    (
      words: 'cored|trimmed',
      share: 0.92,
      flag:
          'USDA AH-102 item 499: cauliflower, raw whole head → fully '
          'trimmed, head or flowerbud 92 % (83–100)',
    ),
  ],
  2685570: [
    (
      words: 'peeled',
      share: 0.84,
      flag:
          'USDA AH-102 item 2459: butternut squash, raw whole → flesh 84 % '
          '(75–88)',
    ),
  ],
  2685568: [
    (
      words: 'trimmed',
      share: 0.93,
      flag:
          'USDA AH-102 item 2446: zucchini, raw whole → flesh and skin 93 % '
          '(86–98; ends 7)',
    ),
  ],
  2685569: [
    (
      words: 'trimmed',
      share: 0.95,
      flag:
          'USDA AH-102 item 2444: summer squash, all samples, raw whole → '
          'flesh and skin 95 % (84–99)',
    ),
  ],
  2346409: [
    (
      words: 'hulled|stemmed',
      share: 0.94,
      flag:
          'USDA AH-102 item 2473: strawberries, good quality, raw → flesh '
          '94 % (86–99)',
    ),
  ],
};
const _potato = [
  (
    words: 'peeled',
    share: 0.81,
    flag:
        'USDA AH-102 item 2018: potatoes, raw whole, all samples → pared '
        '81 % (61–94)',
  ),
];
const _apple = [
  (
    words: 'peeled',
    share: 0.78,
    flag:
        'USDA AH-102 item 17: apples, all cultivars, raw whole → flesh, '
        'pared and cored 78 % (60–87)',
  ),
  (
    words: 'cored',
    share: 0.90,
    flag:
        'USDA AH-102 item 30: apples, all cultivars, raw whole → cored only '
        '90 % (84–94)',
  ),
];
const _pear = [
  (
    words: 'peeled',
    share: 0.78,
    flag:
        'USDA AH-102 item 1734: pears, raw whole → pared, cored flesh 78 % '
        '(40–88)',
  ),
];

/// [food]'s [produceYields] figure for [raw]: only when the line prints a
/// weight in its HEAD (before its first top-level comma — the complement of
/// [_tailAfterComma]; "2 carrots, peeled … (3 ounces)" weighs a prepared
/// cup, not a purchase) and names the prep word in its tail; never when it
/// keeps peels ("¼ of peels reserved"). v59 (M60 P7a, pre-Q18): a tail
/// naming no prep word reads the record's 'peeled' figure when
/// [stepsPeel] (the engine's `stepsPeelIn`: a step pares the raw item),
/// its flag saying so. Null otherwise.
({double share, String flag})? produceYieldOf(
  FdcFood? food,
  String raw, {
  bool stepsPeel = false,
}) {
  final figures = produceYields[food?.fdcId];
  if (figures == null ||
      RegExp(r'\bpeels? reserved\b', caseSensitive: false).hasMatch(raw)) {
    return null;
  }
  final at = _topLevelComma(raw);
  final head = (at < 0 ? raw : raw.substring(0, at)).toLowerCase();
  final tail = _tailAfterComma(raw);
  if (!RegExp(r'\b(?:pounds?|ounces?|lbs?|oz)\b').hasMatch(head)) {
    return null;
  }
  for (final figure in figures) {
    final m = RegExp('\\b(?:${figure.words})\\b').firstMatch(tail);
    if (m != null) {
      return m[0]!.contains('part') && _otherPartUsed(tail, m.end)
          ? null
          : (share: figure.share, flag: figure.flag);
    }
  }
  // A line that says "unpeeled" keeps the peel whatever a step says (Y8's
  // "never").
  if (!stepsPeel ||
      RegExp(r'\bunpeeled\b', caseSensitive: false).hasMatch(raw)) {
    return null;
  }
  final peeled = figures.where((f) => f.words == 'peeled').firstOrNull;
  return peeled == null
      ? null
      : (share: peeled.share, flag: '${peeled.flag}; the steps peel it');
}

/// Whether [tail], after a part clause ending at [end], names a leek's or
/// scallion's other part as used too — "1½ pounds leeks, white and light
/// green parts halved …; 3 cups coarsely chopped dark green parts" eats the
/// whole leek, so no part yield applies (v43 closer 2). Read after a part
/// clause only, never after a prep word ("peeled").
bool _otherPartUsed(String tail, int end) => RegExp(
  r'\b(?:green|white) parts?\b|\bgreens\b',
).hasMatch(tail.substring(end));

/// v43 (Y9, the owner's 2026-10-06 ruling): a counted scallion (FNDDS
/// 2709794, '1 whole' 15 g) whose tail BEGINS "white parts only" or "green
/// parts only" counts AH-102's part of the WHOLE scallion with its rootlets
/// (the printed base; 37/96 if FNDDS's whole is trimmed is not known). Not
/// "white and light green parts only" nor "dark green parts only" (no
/// figure is printed for them); never a carrot or an onion.
({double share, String flag})? scallionPartOf(FdcFood? food, String raw) {
  if (food?.fdcId != 2709794) return null;
  final tail = _tailAfterComma(raw);
  final m = RegExp(r'^\s*(white|green) parts? only\b').firstMatch(tail);
  final part = m == null || _otherPartUsed(tail, m.end) ? null : m[1];
  return switch (part) {
    'white' => (
      share: 0.37,
      flag:
          'USDA AH-102 item 1575: white part 37 % (22–50) of the whole '
          'scallion with rootlets',
    ),
    'green' => (
      share: 0.59,
      flag:
          'derived from USDA AH-102 items 1573 and 1575: green tops and '
          'rootlets 63 % (50–78) less rootlets 4 % = 59 % of the whole '
          'scallion with rootlets',
    ),
    _ => null,
  };
}

/// Whether [raw] says "peeled" after its item ([_tailAfterComma]) — a
/// purchase weight's prep loss (v39 A3).
bool peeledAfterItem(String raw) =>
    RegExp(r'\bpeeled\b').hasMatch(_tailAfterComma(raw));

/// Whether [raw] drains or rinses a can or jar ([cannedDrained] reads the
/// food's drained portion for it).
bool drainsCan(String raw) {
  final text = raw.toLowerCase();
  return RegExp(r'\b(cans?|jars?)\b').hasMatch(text) &&
      RegExp(r'\b(drained|rinsed)\b').hasMatch(text) &&
      !RegExp(r'\b(undrained|do not drain)\b').hasMatch(text);
}

/// The [net] printed grams of [raw]'s cans or jars at their drained weight
/// on [food], or null — under the switch [on] (default [cannedDrained]).
double? drainedCanGrams(
  double net,
  FdcFood? food,
  String raw, {
  bool on = cannedDrained,
}) {
  if (!on || food == null || !drainsCan(raw)) {
    return null;
  }
  final sized = RegExp(r'\(([\d.]+)\s*oz\)');
  for (final portion in food.portions) {
    final name = (portion.description ?? '').toLowerCase();
    final ounces = double.tryParse(sized.firstMatch(name)?[1] ?? '');
    if (!RegExp(r'\b(can|jar)\b').hasMatch(name) ||
        !name.contains('drained') ||
        ounces == null ||
        ounces <= 0) {
      continue;
    }
    final share =
        portion.gramWeight /
        (portion.amount ?? 1) /
        (ounces * _weightUnitGrams['ounce']!);
    if (share > 0 && share < 1) {
      return net * share;
    }
  }
  return null;
}

/// "from 4 (24-ounce) jars": the containers a measured volume came from
/// ([_resolveGrams] step 1b). One corpus line (0949's Morellos).
final _fromContainers = RegExp(
  r'\bfrom\s+\d+\s*\([^()]*-ounce\)\s*(?:jars?|cans?)\b',
  caseSensitive: false,
);

GramResolution? _resolveGrams({
  required List<Amount> amounts,
  required FdcFood? food,
  required String normalizedItem,
  String? raw,
  bool kosher = false,
  String? words,
}) {
  // 1. Any weight amount converts directly — including the secondary of a
  //    dual "1¾ cups (8¾ ounces)" pair, which is exactly why ATK prints it.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.weight) {
      continue;
    }
    final quantity = _quantityValue(amount.quantity);
    final perUnit = _weightUnitGrams[(amount.unit ?? '').toLowerCase()];
    if (quantity != null && perUnit != null) {
      final midpoint = _midpointBounds(amount.quantity) != null;
      return GramResolution(
        grams: quantity * perUnit,
        source: GramSource.weight,
        basis:
            'from ${_amountText(amount)}${midpoint ? ' (the midpoint)' : ''}',
      );
    }
  }

  // 1b. A weight printed in a raw PARENTHETICAL that the amount parse dropped
  //     ("4 (5 to 6-ounce) chicken breasts", "2 (15-ounce) cans", "1 russet
  //     potato (about 8 ounces)"). It reads PER counted unit, so scale by the
  //     count; with no count it is the line total. Still the gold-standard
  //     weight source — preferred over piece/density estimates below.
  if (raw != null) {
    // v63 (M65 F5): a line measured by VOLUME first and bought "from N
    // (W-ounce) jars|cans" prints the container it came from, not the
    // measure — "8 cups jarred Morello cherries from 4 (24-ounce) jars,
    // drained" read one jar (680.39 g) and weighs its 8 cups.
    final paren =
        amounts.firstOrNull?.measure == Measure.volume &&
            _fromContainers.hasMatch(raw)
        ? null
        : _parenWeight(raw);
    if (paren != null) {
      final count = _countQty(amounts);
      // A per-unit weight scales by the count; a trailing total is the line as
      // written (scaling it by the count is the ~5× "N slices … (X oz)" bug).
      final scaled = paren.perUnit && count != null && count > 1;
      final grams = scaled ? paren.grams * count : paren.grams;
      final range = paren.range;
      final countLabel = count == null
          ? null
          : (count == count.roundToDouble()
                ? count.toInt().toString()
                : count.toString());
      return GramResolution(
        grams: grams,
        source: GramSource.weight,
        // M48: a range names itself — "8 × 170 g (printed 5–7 oz, the
        // midpoint)", "from the printed weight (12–14 lb, the midpoint)".
        basis: scaled
            ? '$countLabel × ${paren.grams.round()} g (printed '
                  '${range == null ? 'weight' : '$range, the midpoint'})'
            : 'from the printed weight'
                  '${range == null ? '' : ' ($range, the midpoint)'}',
      );
    }
    // 1b'. v37 (Z2, Z7): ONE item whose weight the line prints in a comma
    //      clause, not a paren ([_clauseWeight]).
    final clause = _clauseWeight.firstMatch(raw);
    final perUnit = clause == null
        ? null
        : _weightUnitGrams[clause[2]!.toLowerCase().replaceAll(
            RegExp(r's$'),
            '',
          )];
    final weight = clause == null ? null : _quantityValue(clause[1]!.trim());
    if (perUnit != null &&
        weight != null &&
        _countQty(amounts) == 1 &&
        amounts.every((a) => (a.unit ?? '').isEmpty)) {
      return GramResolution(
        grams: weight * perUnit,
        source: GramSource.weight,
        basis: 'from the printed weight',
      );
    }
  }

  // 1c. A bare count whose parenthetical prints the line's VOLUME is that
  //     volume, as a printed weight is, when the food sizes it: "4–6 Swiss
  //     chard leaves, ribs removed, torn into 1-inch pieces (about 2 cups;
  //     optional)" (Hearty Chicken Noodle Soup) is 2 cups, 72 g — never 5
  //     whole leaves with their stalks, 240 g (Run 047).
  //     A per-item paren the parse KEPT as the line's volume amount — "2
  //     (about 1 cup) ripe pears, sliced" is the count 2 and 1 cup — is
  //     one item's volume too, as the one the parse drops (Run 049: step 2
  //     read the line at 1 cup; no corpus line prints one).
  final kept = amounts.any((a) => a.measure == Measure.volume);
  final printed = raw == null
      ? null
      : _parenVolume(raw, _countQty(amounts), perItemOnly: kept);
  // (Requiring the count unit-less, or any amount at all — an amount-less
  // line counts 0 g — changed no line of the library: not asked.)
  if (printed != null && amounts.every((a) => a.measure != Measure.weight)) {
    final volume = _resolveGrams(
      amounts: [printed],
      food: food,
      normalizedItem: normalizedItem,
      kosher: kosher,
    );
    if (volume != null) {
      return volume;
    }
  }

  // 2. Volume through the food's portions, then the density table.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.volume) {
      continue;
    }
    final quantity = _quantityValue(amount.quantity);
    final unit = (amount.unit ?? '').toLowerCase();
    final ml = _volumeUnitMl[unit];
    if (quantity == null || ml == null) {
      continue;
    }
    // Crushed saltines by the corpus's own count — "⅔ cup crushed saltines
    // (about 16)" (Meatloaf with Brown Sugar-Ketchup Glaze, 0306): 24 a cup
    // on the record's "1 cracker" portion. Its "1 cup, NFS" is whole
    // crackers: Glazed All-Beef Meatloaf's (0305) ⅔ cup read 33 g, the
    // count 48 g (v12 review, Opus).
    final cracker =
        food != null && raw != null && _crushedSaltines.hasMatch(raw)
        ? _namedPortionGrams(food, 'cracker')
        : null;
    if (cracker != null) {
      final crackers = quantity * ml / _volumeUnitMl['cup']! * 24;
      return GramResolution(
        grams: crackers * cracker,
        source: GramSource.portion,
        basis:
            '${_amountText(amount)} ≈ ${crackers.round()} crackers · USDA '
            'cracker portion',
      );
    }
    // A powder on a record of the drink made from it reads only its dry
    // portions: 174867 "..., powder, prepared with whole milk" weighed "3
    // tablespoons malted milk powder" on its 'cup (8 fl oz)' 265 g of the
    // drink (Run 050); 171874's 'cup dry mix' 98 g sizes its powder.
    final volumeFood =
        food != null &&
            food.description.toLowerCase().contains('prepared with') &&
            RegExp(r'\bpowder\b').hasMatch(normalizedItem)
        ? FdcFood(
            fdcId: food.fdcId,
            description: food.description,
            dataType: food.dataType,
            nutrientsPer100g: food.nutrientsPer100g,
            portions: [
              for (final portion in food.portions)
                if (RegExp(
                  r'\bdry\b',
                ).hasMatch((portion.description ?? '').toLowerCase()))
                  portion,
            ],
          )
        : food;
    final entry = kosher ? null : _densityOf(normalizedItem);
    // Grated or shredded hard cheese weighs the corpus's printed figure
    // WHATEVER the record — before the record's own cup (Run 054 Sonnet
    // critic 2: an FNDDS-style '1 cup' portion read "¼ cup grated Parmesan"
    // at 25 g).
    final form = entry != null && _printedHardCheeseKeys.contains(entry.$1)
        ? _hardCheeseForm
              .firstMatch((words ?? raw ?? normalizedItem).toLowerCase())
              ?.group(1)
        : null;
    final printed = form == null ? null : _printedHardCheese[form];
    if (volumeFood != null && printed == null) {
      final perUnit = _portionGramsPerUnit(volumeFood, unit);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.portion,
          basis: '${_amountText(amount)} · USDA portion',
        );
      }
    }
    final ownVolume = volumeFood == null
        ? null
        : _foodGramsPerMl(
            volumeFood,
            raw ?? normalizedItem,
            null,
            _volumeAliases[unit],
          );
    // 'nuts' is any nut: a record of the nut the item names weighs it by its
    // own cup ("½ cup unsalted roasted peanuts" on 173806 'cup' 146 g, not
    // 0.55's 65 g; Run 050).
    final density = kosher
        ? _flakeSaltDensity
        : printed != null
        ? printed.$1
        : entry != null &&
              ownVolume != null &&
              (_recordFirstDensities.contains(entry.$1) ||
                  (entry.$1 == 'nuts'
                      ? _namesTheRecord(normalizedItem, volumeFood!)
                      : _keyModifiesTheRecordsFood(
                          entry.$1,
                          normalizedItem,
                          volumeFood!,
                        )))
        ? null
        : entry?.$2;
    if (density != null) {
      // The corpus prints shredded Parmesan only: shredded Pecorino weighs
      // on it, flagged.
      final standIn = kosher
          ? null
          : form == 'shredded' && entry?.$1 == 'pecorino'
          ? 'shredded Parmesan density'
          : printed != null
          ? null
          : _approximateDensities[entry?.$1];
      return GramResolution(
        grams: quantity * ml * density,
        source: GramSource.density,
        basis:
            '${_amountText(amount)} ≈ ${(quantity * ml).round()} mL'
            '${printed == null ? '' : " · $form, at ATK's printed "}'
            '${printed?.$2 ?? ''}'
            '${standIn == null ? '' : ' · approximate ($standIn)'}'
            '${entry?.$1 == 'kosher salt' ? _kosherSaltBasis : ''}',
      );
    }
    final perMl = ownVolume;
    if (perMl != null) {
      return GramResolution(
        grams: quantity * ml * perMl,
        source: GramSource.portion,
        basis: '${_amountText(amount)} · USDA portion',
      );
    }
  }

  // 3. Counts through piece portions / the piece table.
  for (final amount in _byPreference(amounts)) {
    if (amount.measure != Measure.count) {
      continue;
    }
    final amountUnit = (amount.unit ?? '').toLowerCase();
    // "Pinch cayenne pepper" parses with an empty quantity: one pinch.
    final quantity =
        _quantityValue(amount.quantity) ??
        (amount.quantity.trim().isEmpty &&
                _smallMeasures.containsKey(amountUnit)
            ? 1
            : null);
    if (quantity == null) {
      continue;
    }
    // A unit the parse lost: "½ cup plus 1 tablespoon half-and-half or milk"
    // came through as the bare count ½ and was sized as half a piece (7.5 g,
    // Strawberry Shortcakes; audit 3). No grams beats a wrong count.
    if (amountUnit.isEmpty && raw != null && _lostVolumeUnit.hasMatch(raw)) {
      continue;
    }
    // A pinch, a dash, a sprig: the food's own FDC portion of that name
    // ("dash" 0.1 g of black pepper, 0.4 g of salt; "sprig" of parsley), the
    // count in its structured amount (user answer #3's second half).
    final small = food == null ? null : _smallMeasureGrams(food, amount);
    if (small != null) {
      return GramResolution(
        grams: quantity * small.grams,
        source: GramSource.piece,
        basis: small.basis,
      );
    }
    if (sprigZeroOn && _smallMeasures[amountUnit] == 'sprig') {
      return GramResolution(
        grams: 0,
        source: GramSource.unmeasured,
        basis:
            '${_amountText(amount)} — a sprig is not measured, counted as '
            '0 g',
      );
    }

    // A bare count the line sizes itself: "18 medium-large shrimp (31 to 40
    // per pound)" (Vietnamese Summer Rolls, 0510) is 18 at 35.5 a pound,
    // 230 g — the shrimp record's only portion is 3 ounces (v12 review, Opus
    // critic).
    final perPound = raw == null ? null : _perPound.firstMatch(raw);
    if (perPound != null) {
      final each =
          _weightUnitGrams['pound']! /
          ((int.parse(perPound[1]!) + int.parse(perPound[2]!)) / 2);
      return GramResolution(
        grams: quantity * each,
        source: GramSource.piece,
        basis:
            '${_amountText(amount)} × ${each.round()} g each '
            '(${perPound[1]} to ${perPound[2]} per pound)',
      );
    }

    // v37 (Z7): an envelope of yeast, weighed as its 2¼ teaspoons.
    if ((amountUnit == 'envelope' || amountUnit == 'envelopes') &&
        RegExp(r'\byeast\b').hasMatch(normalizedItem)) {
      final teaspoons = quantity * _yeastEnvelopeTeaspoons;
      final volume = _resolveGrams(
        amounts: [
          Amount(
            measure: Measure.volume,
            quantity: '$teaspoons',
            unit: 'teaspoon',
            primary: true,
          ),
        ],
        food: food,
        normalizedItem: normalizedItem,
      );
      if (volume != null) {
        return GramResolution(
          grams: volume.grams,
          source: volume.source,
          basis:
              '${_amountText(amount)} ≈ ${_figure(teaspoons)} teaspoon '
              '(ATK: 1 envelope = 2¼ teaspoons) · ${volume.basis}',
        );
      }
    }

    // 3a. The amount's OWN unit against the food's portions — "6 ears corn",
    //     "1 head lettuce": the recipe named the unit, so it is authoritative.
    if (food != null && amountUnit.isNotEmpty) {
      final perUnit = _portionGramsPerUnit(food, amountUnit);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.piece,
          basis: '${_amountText(amount)} · USDA portion',
        );
      }
    }

    // 3a.5 Rustic/artisan bread the flat piece table can't serve — its weight
    //      depends on the UNIT (thick slice vs whole loaf), not just the name.
    //      After 3a so a real FDC slice/loaf portion still wins.
    final breadGrams = _rusticBreadGrams(normalizedItem, amountUnit);
    if (breadGrams != null) {
      return GramResolution(
        grams: quantity * breadGrams,
        source: GramSource.piece,
        basis: '${_amountText(amount)} × ${breadGrams.round()} g each',
      );
    }

    // 3a.6 A piece by its printed length ([_perInch], v31): a "(4-inch)
    //      piece ginger", "2 (2-inch) strips lemon zest" — a strip is a
    //      container unit to the piece table below (never the whole fruit).
    //      v61 (M63 P10): a round by its printed diameter ([_perArea]): "4
    //      (8-inch) pita breads".
    final round = _perAreaGrams(normalizedItem, raw, amountUnit, food);
    if (round != null) {
      return GramResolution(
        grams: quantity * round.grams,
        source: GramSource.piece,
        basis:
            '${_amountText(amount)} × ${round.grams.toStringAsFixed(2)} g '
            'each (${_figure(round.inches)}-inch round: '
            '${round.area.toStringAsFixed(2)} sq in × '
            '${_figure(round.perSqIn)} g per surface inch) · approximate '
            '(${round.label}, π × ${_figure(round.inches / 2)}²)',
      );
    }
    final inch = _perInchGrams(normalizedItem, raw, amountUnit, food);
    if (inch != null) {
      return GramResolution(
        grams: quantity * inch.grams,
        source: GramSource.piece,
        basis:
            '${_amountText(amount)} × ${_figure(inch.inches)} inch × '
            '${_figure(inch.perInch)} g per inch · approximate '
            '(${inch.label})',
      );
    }

    // 3b. The curated piece table — hand-tuned to ATK's meaning, so it beats a
    //     fuzzy whole-item portion (a "graham cracker" is the 14 g rectangle,
    //     not FDC's ambiguous per-cracker serving). Skipped for a container
    //     count with no printed size — a whole-item weight is not a can.
    //     Skipped too for a bunch: every entry is per piece, and '2 bunches
    //     scallions' read as 2 scallions (30 g) — a bunch of scallions is
    //     [_perBunch] of them (v31).
    final bunch = amountUnit == 'bunch'
        ? _tableEntry([
            for (final MapEntry(:key, :value) in _perBunch.entries)
              (key, value.toDouble()),
          ], normalizedItem)
        : null;
    final piece = bunch != null
        ? _pieceLookup(bunch.$1, null, '')
        : _containerUnits.contains(amountUnit) || amountUnit == 'bunch'
        ? null
        : _pieceLookup(normalizedItem, raw, amountUnit);
    if (piece != null && bunch != null) {
      final each = bunch.$2.round();
      return GramResolution(
        grams: quantity * each * piece.$2,
        source: GramSource.piece,
        basis:
            '${_amountText(amount)} × $each × ${piece.$2.round()} g each · '
            'approximate (reference figure: $each scallions a bunch)',
      );
    }
    if (piece != null) {
      final (key, pieceWeight) = piece;
      final size = _unsizedPieces[key] == null || raw == null
          ? null
          : RegExp(
              r'\b(small|medium|large)\b',
            ).firstMatch(_headBeforeComma(raw).toLowerCase())?[1];
      final printed =
          _approximatePieces[key] ??
          (size == null
              ? null
              : '${_unsizedPieces[key]}; no $size size published');
      // A sub-gram piece says all its decimals, flagged or not (v62, M64
      // R4b: the bay leaf printed "1 × 0 g each" on 0.2 g); a flagged one
      // under 10 g one ("3.2", "7.1"); every other piece its rounded grams
      // — but a slice of 10 g or more that is no whole gram says its own
      // (v51: the Canadian bacon's "28.5", the thick-cut "35.44"), so the
      // count times it is the grams.
      final each =
          pieceWeight < 1 ||
              (pieceWeight >= 10 && pieceWeight != pieceWeight.round())
          ? _figure(pieceWeight)
          : printed == null || pieceWeight >= 10
          ? '${pieceWeight.round()}'
          : pieceWeight.toStringAsFixed(1);
      return GramResolution(
        grams: quantity * pieceWeight,
        source: GramSource.piece,
        basis:
            '${_amountText(amount)} × $each g each'
            '${printed == null ? '' : ' · approximate ($printed)'}',
      );
    }

    // 3b.5 The unit an SR bare noun names ("stick" of butter).
    final bareUnit = food == null || amountUnit.isEmpty
        ? null
        : _portionGramsPerUnit(food, amountUnit, bare: true);
    if (bareUnit != null) {
      return GramResolution(
        grams: quantity * bareUnit,
        source: GramSource.piece,
        basis: '${_amountText(amount)} · USDA portion',
      );
    }

    // 3c. A BARE count on an uncovered item: the food's own whole-item weight,
    //     then the legacy generic-piece portion. Last, because it is the
    //     fuzziest — a wrong-food match can carry a large "1 serving" portion.
    //     Only for bare counts: if the recipe named a unit ("1 bunch parsley")
    //     that 3a could not match, guessing off an unrelated "1 sprig" is worse
    //     than leaving the line for review.
    if (food != null && amountUnit.isEmpty) {
      final perUnit =
          _wholeItemPortionGrams(food, normalizedItem, raw: raw) ??
          _legacyPiecePortion(food);
      if (perUnit != null) {
        return GramResolution(
          grams: quantity * perUnit,
          source: GramSource.piece,
          basis: '${_amountText(amount)} · USDA per-item weight',
        );
      }
    }
  }
  return null;
}

/// Primary amount first, then the rest in written order.
Iterable<Amount> _byPreference(List<Amount> amounts) sync* {
  for (final amount in amounts) {
    if (amount.primary) {
      yield amount;
    }
  }
  for (final amount in amounts) {
    if (!amount.primary) {
      yield amount;
    }
  }
}

/// The line's first amount that names a unit, as written ("4 stick", "1
/// piece") — what the fix sheet's "The line says …" quotes and what
/// [portionFill] sizes; null when no amount names one.
Amount? unitAmountOf(List<Amount> amounts) {
  for (final amount in amounts) {
    if ((amount.unit ?? '').trim().isNotEmpty) {
      return amount;
    }
  }
  return null;
}

/// The line's amount as written: [unitAmountOf] as text ("4 stick"), else
/// its first amount, a bare count ("8" for "8 large sea scallops" — a count
/// is an amount the person converts to grams, Run 046); null when the line
/// gives no amount at all. [portionFill] still sizes the unit amount only.
String? lineAmountText(List<Amount> amounts) {
  final amount = unitAmountOf(amounts) ?? amounts.firstOrNull;
  final text = amount == null ? '' : _amountText(amount);
  return text.isEmpty ? null : text;
}

/// A unit or portion word in one spelling: a volume alias's unit
/// ("tbsp" → "tablespoon"), else the word less a plural "s".
String _unitWord(String word) {
  final lower = word.toLowerCase().trim();
  final alias = _volumeAliases[lower];
  if (alias != null) {
    return alias;
  }
  // Both sides go through here, so a short word ending in s strips alike.
  return lower.endsWith('s') ? lower.substring(0, lower.length - 1) : lower;
}

/// The grams the line's unit amount ([unitAmountOf] of [amounts]) weighs on
/// [portion] when the portion NAMES that unit — its structured unit, or the
/// first word of its description after any count ("stick", "tbsp" for a
/// tablespoon, "slices (1\" dia)" for a slice): "4 stick" on "stick" 113 g
/// is 452 g. Null when the portion names another unit, or the line has no
/// unit amount. The fix sheet's tap-to-fill chips (never a stored gram:
/// a person taps it).
double? portionFill(FdcPortion portion, List<Amount> amounts) {
  final amount = unitAmountOf(amounts);
  final quantity = amount == null ? null : _quantityValue(amount.quantity);
  if (amount == null || quantity == null || quantity <= 0) {
    return null;
  }
  final description = (portion.description ?? '').toLowerCase().trim();
  final leading = RegExp(r'^([\d][\d./\s]*)').firstMatch(description);
  // FDC's "undetermined" unit arrives as null (fdc_provider), and a leading
  // count holds no letters: the description's first word is the unit's.
  final unit = (portion.unit ?? '').toLowerCase();
  final word = unit.isNotEmpty
      ? unit
      : RegExp('[a-z]+').firstMatch(description)?.group(0) ?? '';
  if (word.isEmpty || _unitWord(word) != _unitWord(amount.unit!)) {
    return null;
  }
  final per = leading == null
      ? (portion.amount ?? 1)
      : (_quantityValue(leading.group(1)!.trim()) ?? 0);
  return per <= 0 ? null : quantity * portion.gramWeight / per;
}
