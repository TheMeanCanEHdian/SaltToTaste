import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('nutrition');

/// Confidence below which an auto match is reported as needs-review
/// (salt_shared's [confidenceGate]; compared through [belowConfidenceGate]).
const double lowConfidence = confidenceGate;

/// Whether [food] reports all four macros (energy — any variant — fat,
/// carbs, protein). Vitamins may still be missing; macros are the floor
/// for a trustworthy label.
bool _macroComplete(FdcFood food) {
  final n = food.nutrientsPer100g;
  final hasEnergy =
      n.containsKey('208') || n.containsKey('957') || n.containsKey('958');
  return hasEnergy &&
      n.containsKey('204') &&
      n.containsKey('205') &&
      n.containsKey('203');
}

/// Whether [food] publishes no energy a total can trust: no energy
/// (208/957/958) and at least one of protein, fat (204 or NLEA 298) or
/// carbohydrate missing, so the Atwater fallback would count only part of
/// the food. Foundation "Pasta, dry, whole grain, spaghetti" (2759000)
/// publishes none (counted, it added 454 g and 0 kcal per line); "Beans,
/// Dry, Red (0% moisture)" (747431) publishes protein and fat but no
/// carbohydrate, and counted at 96 kcal per 100 g (audit 3). The engine
/// keeps its grams and holds the line (`no_nutrients`).
///
/// A record whose published macros already make up [_wholeMassMacros] g of
/// every 100 g has no room left for the missing ones: "Oil, olive, extra
/// virgin" (748608) publishes only fat, 93.7 g as 298, and is 843 kcal per
/// 100 g. Salt really is energy-free (Foundation 746775 "Salt, table,
/// iodized" publishes only minerals), so a salt record is never held.
bool publishesNothing(FdcFood food) {
  final n = food.nutrientsPer100g;
  if (['208', '957', '958'].any(n.containsKey) ||
      food.description.toLowerCase().startsWith('salt,')) {
    return false;
  }
  final macros = [n['203'], n['204'] ?? n['298'], n['205']];
  final published = macros.whereType<double>().fold<double>(0, (a, b) => a + b);
  return macros.contains(null) && published < _wholeMassMacros;
}

/// Grams of macros per 100 g that leave no room for a missing one.
const double _wholeMassMacros = 90;

/// Records whose NUTRIENTS the totals read from a sibling record of the same
/// food: Foundation "Cabbage, napa, leaf, destemmed, raw" (2727583)
/// publishes 9 nutrients and no energy, so 7 napa lines were held
/// `no_nutrients` (checkpoint 6), while SR 169979 "Cabbage, chinese
/// (pe-tsai), raw" is the same raw leaf. The line keeps its own food and
/// grams (and so its portions, [volumeSiblings]); only the per-100 g values
/// are the sibling's, and the basis names it ([gramBasisFor]). The
/// sibling is read from the caches — a search hit is enough — and fetched
/// once only when no cache holds it.
const Map<int, int> nutrientSiblings = {2727583: 169979};

/// A cooking medium the recipe throws away, found from the line and the
/// recipe's steps (audit 1 rank 12, audit 2: 19 counted frying-oil lines of
/// 400 g or more, 26.6 kg; 25 brine-salt lines; 2 buttermilk soaks; 2 lines
/// of milk curdled into cheese whose whey is drained).
enum DiscardedMedium {
  /// Deep-frying oil: "for (deep-)frying", or 400 g or more of
  /// oil/shortening/lard whatever the steps say ("3 cups vegetable oil" for
  /// orange beef; Easier French Fries never says fry). Audit 3: 29 counted
  /// lines, 41,017 g — a 4-cup rule found 21.
  fryingOil,

  /// Brine salt: "for brining", or 3 tablespoons or more with a step that
  /// brines in it — never a dry brine, a cure or a salt crust, which the
  /// meat keeps.
  brine,

  /// Brine sugar ("for brining", or ¼ cup or more a step brines in, or a
  /// co-solute of a submerge brine): zeroed like the brine's salt under the
  /// policy — the user's ruling R3, 2026-09-28 (it was always review: 22
  /// held lines, every one in a brine the food is lifted out of).
  brineSugar,

  /// ¼ cup or more of salt no step brines in or rubs on: a salt bed, an ice
  /// bath, a dunk (Salt-Baked Potatoes, a gelato's ice bath); and salt
  /// tossed with a vegetable and rinsed off ([_rinsedSalt], R2). Always
  /// review.
  saltBath,

  /// A soak: "for soaking", or 4+ cups of buttermilk a step brines or soaks
  /// in.
  soak,

  /// Milk made into cheese (4+ cups, a whey or curds step): only the curds
  /// are eaten, in an amount nothing on the line says — always review; so
  /// are the salt, acid and buttermilk put in it ([_intoCheeseMilk], R2).
  cheeseMilk,

  /// Salt or baking soda a step puts in boiling water that is then drained
  /// away from the food: pasta and noodle water, a blanching pot, 0778's
  /// baking-soda skinning bath (11,287 mg sodium a serving counted,
  /// checkpoint 6). How much the food keeps nothing says — always review,
  /// like a salt bath. Water the food absorbs, and a pot no step drains,
  /// count in full. A skimmer or slotted spoon empties a pot too — of its
  /// sugar as well (New York Bagels, 0810) — a divided line's WRITTEN share
  /// is held with the rest as its grams, and a brine the food then poaches
  /// in holds its co-solutes ([_brineCoSolute]) — the user's ruling R2,
  /// 2026-09-28.
  cookingWater;

  /// Whether [discardedMediaPolicy] decides how it counts; the others are
  /// always held for a person.
  bool get followsPolicy =>
      this == fryingOil || this == brine || this == brineSugar || this == soak;
}

/// How a discarded medium counts.
enum DiscardedMediaPolicy {
  /// 0 g, `gram_source: discarded`: resolved, adds nothing.
  zero,

  /// Keeps its grams and is held (`hold: discarded_medium`) for a person.
  review,
}

/// USER ANSWER #2 SWITCH (discarded-media policy). [DiscardedMediaPolicy.zero]
/// is the recommended default for frying oil, brine salt and soaks (absorbed
/// oil and retained salt are real but unmeasured — no source gives a
/// fraction); [DiscardedMediaPolicy.review] holds them for a person instead.
/// Brine sugar, a salt bath and cheese-making milk are always review.
const DiscardedMediaPolicy discardedMediaPolicy = DiscardedMediaPolicy.zero;

/// USER ANSWER #3 SWITCH (amount-less lines). True (the recommended default)
/// stores a matched line with no amount at all — "Lemon wedges, for
/// serving", "Vegetable oil spray", "Sugar" — as 0 g (`gram_source:
/// unmeasured`) with its food kept: resolved, outside the review queue (audit
/// 2: 172 such lines, 101 of them in no_grams). A weak match still sits in
/// `check`. False leaves them in `no_grams` for a person, as before.
const bool amountlessLinesZero = true;

/// Four cups, the threshold for buttermilk and milk quantities.
const double _fourCupsMl = 946;

/// Grams of oil/shortening/lard that only a deep fry uses.
const double _fryingGrams = 400;

/// A quarter cup, the threshold for brine sugar and a salt bath.
const double _quarterCupMl = 59;

/// Three tablespoons, the threshold for brine salt: a quart of shrimp or
/// pork-chop brine dissolves 3 tablespoons of table salt (audit 3: 35
/// brine-salt lines at 50 g or more).
const double _brineSaltMl = 44;

final RegExp _brineStep = RegExp(
  r'\bbrin(e|es|ed|ing)\b',
  caseSensitive: false,
);
final RegExp _kept = RegExp(
  // Not 'curing' or 'corned': Home-Corned Beef dissolves its salt and
  // curing salt in 4 quarts of water and rinses the brisket.
  r'\b(dry[- ]brin\w*|cures?|cured|salt[- ]crust)\b',
  caseSensitive: false,
);

/// The step texts of [recipe] itself — never a subsection's: a variation
/// or sub-recipe is out of the main totals (the user's ruling, 2026-09-27),
/// and its own pot and its own salt must not make a main line a medium
/// (v11, Sonnet: a variation's bare "Add the spaghetti and salt … Drain"
/// held the recipe's one seasoning salt as cooking water). Measured: no line
/// of the library moves, so the bound is pinned on a synthesized subsection
/// (a stated exception).
List<String> _stepsOf(Recipe recipe) => [
  for (final step in recipe.steps) step.text,
];

/// The second part of a discarded-medium "plus" line that a step uses
/// elsewhere, eaten: "1 cup plus 2 teaspoons table salt" with "remaining 2
/// teaspoons salt" in the rub (0246), "2 cups plus 1 tablespoon vegetable
/// oil" with "1 tablespoon of the oil" beaten into the eggs (0233). Null when
/// no step names its amount beside the food — the whole line is the medium
/// ("½ cup plus 2 tablespoons table salt" all dissolves in 0150's brine).
PlusPart? _eatenPlusPart(Recipe recipe, IngredientLine line, String? head) {
  final plus = plusPartOf(line.raw);
  if (plus == null || !plus.sameFood || head == null) {
    return null;
  }
  final amount = RegExp(
    '^[\\d$vulgarFractionChars/ -]+[a-z]+',
  ).firstMatch(plus.text.toLowerCase())?[0];
  if (amount == null) {
    return null;
  }
  final eaten = _stepsOf(recipe).any((step) {
    final text = step.toLowerCase();
    return text.contains(amount) && text.contains(head);
  });
  return eaten ? plus : null;
}

/// The [DiscardedMedium] [line] of [recipe] is, or null. [normalized] is the
/// line's normalized item and [grams] its resolved grams.
DiscardedMedium? discardedMediumOf(
  Recipe recipe,
  IngredientLine line,
  String normalized, {
  double? grams,
  bool bySentence = true,
}) {
  // The food the line names, not a word in it: 'without salt butter' is
  // butter, 'salt pork' is pork.
  final head = headNounOf(normalized);
  final raw = line.raw.toLowerCase();
  final ml = volumeMlOf(line.amounts) ?? 0;
  final steps = _stepsOf(recipe);
  bool stepSays(RegExp what, String word) => steps.any(
    (step) => what.hasMatch(step) && step.toLowerCase().contains(word),
  );
  // Shortening, lard, "for brining", "for soaking" and the dry-brine/cure
  // exclusion change no line of the library (audit 4 P9) but classify lines
  // typed through the API: a dry brine's salt stays on the meat, and the
  // brine rule below would read "dry-brine" as a brine.
  if (head == 'oil' || head == 'shortening' || head == 'lard') {
    if (RegExp('for (deep[- ]?)?frying').hasMatch(raw) ||
        (grams ?? 0) >= _fryingGrams) {
      return DiscardedMedium.fryingOil;
    }
    return null;
  }
  if (head == 'salt' || head == 'sugar') {
    if (steps.any(_kept.hasMatch) || _kept.hasMatch(recipe.title)) {
      return null;
    }
    if (raw.contains('for brining') ||
        (ml >= (head == 'salt' ? _brineSaltMl : _quarterCupMl) &&
            stepSays(_brineStep, head!))) {
      return head == 'salt'
          ? DiscardedMedium.brine
          : DiscardedMedium.brineSugar;
    }
    if (head == 'salt' &&
        bySentence &&
        (_dissolvedWithBrineSalt(recipe, line, normalized, steps) ||
            _dissolvedInWater(recipe, line, steps))) {
      return DiscardedMedium.brine;
    }
    // Sugar in the pot too: New York Bagels (0810) boils its bagels in "4
    // quarts water, sugar, and baking soda" and lifts them out with a wire
    // skimmer — the sugar leaves with the water, like the soda (R2).
    if (bySentence && _drainedWater(recipe, line, steps)) {
      return DiscardedMedium.cookingWater;
    }
    if (head == 'salt' && bySentence && _rinsedSalt(recipe, line, steps)) {
      return DiscardedMedium.saltBath;
    }
    if (bySentence && _intoCheeseMilk(recipe, line, head!, steps)) {
      return DiscardedMedium.cheeseMilk;
    }
    if (head == 'sugar' && bySentence) {
      final coSolute = _brineCoSolute(recipe, line, head!, steps);
      if (coSolute != null) {
        return coSolute;
      }
    }
    // A rub the meat keeps, like a dry brine: pork shoulder's overnight
    // salt-sugar rub, gravlax, a salted turkey.
    return head == 'salt' &&
            ml >= _quarterCupMl &&
            !stepSays(RegExp(r'\brub', caseSensitive: false), 'salt')
        ? DiscardedMedium.saltBath
        : null;
  }
  if (raw.contains('for soaking') ||
      (head == 'buttermilk' &&
          ml >= _fourCupsMl &&
          (stepSays(_brineStep, 'buttermilk') ||
              stepSays(
                RegExp(r'\bsoak', caseSensitive: false),
                'buttermilk',
              )))) {
    return DiscardedMedium.soak;
  }
  if (head == 'milk' &&
      ml >= _fourCupsMl &&
      steps.any(RegExp(r'\b(whey|curds?)\b', caseSensitive: false).hasMatch)) {
    return DiscardedMedium.cheeseMilk;
  }
  if (head == 'soda' && bySentence && _drainedWater(recipe, line, steps)) {
    return DiscardedMedium.cookingWater;
  }
  if (!bySentence) {
    return null;
  }
  if (head == null) {
    // "8 whole cloves" names no head noun — 'cloves' is how garlic is
    // counted — yet Oven-Roasted Pork Chops (0202) adds "the garlic, bay
    // leaves, cloves, and peppercorns" to its brine: the item's last word
    // is the food there ([_names] never reads it in "garlic cloves").
    return _brineCoSolute(recipe, line, normalized.split(' ').last, steps);
  }
  if (_intoCheeseMilk(recipe, line, head, steps)) {
    return DiscardedMedium.cheeseMilk;
  }
  return _brineCoSolute(recipe, line, head, steps);
}

/// The fraction of [line] its [_drainedMention]'s written pot share is
/// (1½ of 2 teaspoons: 0.75), or null when the whole line goes in the pot.
double? _potShareOf(Recipe recipe, IngredientLine line) {
  final share = _drainedMention(recipe, line, _stepsOf(recipe))?.share;
  final own = volumeMlOf(line.amounts);
  final part = share == null
      ? null
      : volumeMlOf(parseIngredientLine('$share salt').amounts);
  return own == null || part == null ? null : part / own;
}

/// The first line of [recipe] whose head noun is [head] — a recipe lists a
/// food where it is first used, so a second line of it ("1 cup buttermilk"
/// for Saag Paneer's sauce, after the cheese's 3 cups) is used later.
bool _firstOfItsHead(Recipe recipe, IngredientLine line, String head) =>
    identical(
      nutritionLines(recipe).firstWhere(
        (other) => headNounOf(normalizeItem(lineItemOf(other))) == head,
        orElse: () => line,
      ),
      line,
    );

/// Whether [head] (a key-form noun) is written in [text] as a word.
/// A head in -y is written -ies ("allspice berries", Home-Corned Beef,
/// 0091), and "garlic cloves" never names the spice 'clove'.
bool _names(String text, String head) {
  final word = RegExp.escape(head);
  final stem = RegExp.escape(head.substring(0, head.length - 1));
  final plural = head.endsWith('y') ? '(?:$word|${stem}ies)' : '$word(?:s|es)?';
  return RegExp('(?<!garlic )\\b$plural\\b').hasMatch(text);
}

/// A co-solute of a brine the food is submerged in and lifted out of — the
/// user's ruling R3, 2026-09-28: sugar and aromatics go to zero like the
/// brine's salt. The line's head is named, before the step's "submerg", in
/// a sentence naming the salt or opening "add": "Dissolve salt and sugar in
/// 1 quart cold water … Submerge shrimp in brine" (Ultimate Shrimp Scampi,
/// 0428); "Dissolve the salt, sugar, and paprika in the buttermilk … Add the
/// garlic and bay leaves, submerge the chicken in the brine" (Crispy Fried
/// Chicken, 0148); "Add the garlic, bay leaves, and crushed peppercorns"
/// (Roast Fresh Ham, 0249) — whether or not the brine's salt is a line of
/// its own ("Dissolve sugar and 1 tablespoon salt in 1 quart cold water",
/// Garlicky Shrimp, Tomato, and White Bean Stew, 0429, salts from "Salt and
/// pepper"). The submerged food is never one, nor what the submerge's own
/// sentence adds TO the brine ("Add cremini mushrooms and shiitake mushrooms
/// to brine, cover with plate or bowl to submerge", Roasted Mushrooms, 0688),
/// nor a second
/// line of the same food (the rub's garlic). A brine the food then POACHES
/// in is a cooking liquid ([DiscardedMedium.cookingWater], held — R2: Perfect
/// Poached Chicken Breasts, 0112, whisks soy sauce, sugar and garlic into
/// it). A dunk that leaves the liquid on the food (Grilled Cauliflower,
/// 0656: "dunk … do not dry") submerges nothing, and stays as it was.
DiscardedMedium? _brineCoSolute(
  Recipe recipe,
  IngredientLine line,
  String head,
  List<String> steps,
) => _brineCoSoluteMention(recipe, line, head, steps)?.medium;

/// The [_brineCoSolute] of [line] and the sentence naming it. Weighing the
/// food down submerges it too: Home-Corned Beef (0091) dissolves its salt,
/// sugar and curing salt in 4 quarts water, then "Add brisket, 3 garlic
/// cloves, 4 bay leaves, allspice berries, 1 tablespoon peppercorns, and
/// coriander seeds to brine. Weigh brisket down with plate" and later
/// removes it from the brine — what a sentence adds to the brine BEFORE the
/// submerge's own sentence is in it; the food is what is weighed down.
({DiscardedMedium medium, String sentence})? _brineCoSoluteMention(
  Recipe recipe,
  IngredientLine line,
  String head,
  List<String> steps,
) {
  if (!_firstOfItsHead(recipe, line, head)) {
    return null;
  }
  final marker = RegExp(r'submerg|\bweigh\w*\s+\w+\s+down\b');
  for (final step in steps) {
    final text = step.toLowerCase();
    final submerge = marker.firstMatch(text);
    if (submerge == null || !RegExp(r'\bbrine\b').hasMatch(text)) {
      continue;
    }
    final object = _sentenceAt(text, submerge.start);
    if (_names(object.substring(object.indexOf(submerge[0]!)), head)) {
      return null;
    }
    final sentences = text
        .substring(0, submerge.start)
        .split(RegExp(r'(?<=\.)\s+'));
    for (final (i, sentence) in sentences.indexed) {
      if (!_names(sentence, head) ||
          (i == sentences.length - 1 &&
              sentence.contains(RegExp(r'\bto (the )?brine\b'))) ||
          !(sentence.contains(RegExp(r'\bsalt\b')) ||
              sentence.trimLeft().startsWith('add'))) {
        continue;
      }
      final poached = RegExp(r'\bpoach').hasMatch(recipe.title.toLowerCase());
      return (
        medium: poached
            ? DiscardedMedium.cookingWater
            : head == 'sugar'
            ? DiscardedMedium.brineSugar
            : DiscardedMedium.brine,
        sentence: sentence,
      );
    }
  }
  return null;
}

/// The fraction of [line] a [_brineCoSoluteMention] writes as the brine's
/// share — "3 garlic cloves" of "6 garlic cloves, peeled", "1 tablespoon
/// peppercorns" of "2 tablespoons peppercorns" (0091: the rest go in the
/// pot with the brisket) — or null when the whole line goes in.
double? _brineShareOf(Recipe recipe, IngredientLine line, String? head) {
  if (head == null) {
    return null;
  }
  final sentence = _brineCoSoluteMention(
    recipe,
    line,
    head,
    _stepsOf(recipe),
  )?.sentence;
  final written = sentence == null
      ? null
      : RegExp(
          '([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]*\\s+'
          '(?:[a-z]+\\s+)?)${RegExp.escape(head)}',
        ).firstMatch(sentence)?[1];
  if (written == null) {
    return null;
  }
  final part = parseIngredientLine('$written${lineItemOf(line)}').amounts;
  final volume = volumeMlOf(line.amounts) != null;
  final own = volume ? volumeMlOf(line.amounts) : countOf(line.amounts);
  final share = volume ? volumeMlOf(part) : countOf(part);
  // Never more than the line: its grams are never negative.
  return own == null || share == null || share >= own ? null : share / own;
}

/// Whether [line] goes into the milk of a [DiscardedMedium.cheeseMilk] line
/// of [recipe] — its salt, its acid, its buttermilk: named in the step that
/// first names the milk, whose whey drains (the user's ruling R2: Saag
/// Paneer, 0563, "Whisk in buttermilk and salt … let curds drain"; Homemade
/// Ricotta, 0380, "Heat milk and salt", its lemon juice and vinegar). Held
/// with it: how much the curds keep nothing says.
bool _intoCheeseMilk(
  Recipe recipe,
  IngredientLine line,
  String head,
  List<String> steps,
) {
  if (!_firstOfItsHead(recipe, line, head)) {
    return false;
  }
  final cheese = nutritionLines(recipe).any((other) {
    final item = normalizeItem(lineItemOf(other));
    return headNounOf(item) == 'milk' &&
        discardedMediumOf(recipe, other, item, bySentence: false) ==
            DiscardedMedium.cheeseMilk;
  });
  if (!cheese) {
    return false;
  }
  final step = steps
      .map((s) => s.toLowerCase())
      .firstWhere((s) => RegExp(r'\bmilk\b').hasMatch(s), orElse: () => '');
  return _names(step, head);
}

/// Whether a step tosses [line]'s salt with a vegetable in a colander and
/// a rinse in that step washes it off (the user's ruling R2: Sesame-Lemon
/// Cucumber Salad, 0052, "Toss the cucumbers with the salt in a colander …
/// drain for 1 to 3 hours. Rinse and pat dry"). (A bowl, a rinse in the
/// next step, "do not rinse", requiring the word "toss" and requiring the
/// rinse AFTER the salt changed no line of the library: Bread-and-Butter
/// Pickles, 0664, tosses in a bowl and does not rinse.)
bool _rinsedSalt(Recipe recipe, IngredientLine line, List<String> steps) {
  for (final (:step, :at, share: _) in _ownMentions(recipe, line, steps)) {
    final text = steps[step].toLowerCase();
    final sentence = _sentenceAt(text, at);
    if (sentence.contains(RegExp(r'\bcolander\b')) &&
        RegExp(r'\brins').hasMatch(text)) {
      return true;
    }
  }
  return false;
}

/// The mentions of [line]'s own salt, baking soda or sugar in [steps]: each
/// step and the offset of a mention that is THIS line's — its amount written
/// before it ("Add pasta and 1 tablespoon salt" for "1 tablespoon salt"),
/// or a bare "salt" when no other line of [recipe] is salt ("Add the
/// noodles and salt") — or, for [drained] water, when the line is the one
/// salt line no step names with its amount and no volume makes a medium.
/// A step naming another amount ("Add 2 tablespoons salt" beside "¼
/// teaspoon table salt, plus salt for blanching") names a salt the line
/// does not measure, and so does a line that measures its
/// salt apart from the pot's: "1 teaspoon table salt, plus salt for cooking
/// lentils and bulgur" (1186). Salt pork is not salt. "1 teaspoon of the
/// salt" is a written amount too: Cincinnati Chili (0303) blanches its beef
/// in half of "2 teaspoons table salt, plus more to taste" and counts the
/// line in full. ("plus more", a kind of salt or a cup before the mention,
/// and requiring the other salt lines to be measured changed no line of the
/// library: removed, refix round 2.)
Iterable<({int step, int at, String? share})> _ownMentions(
  Recipe recipe,
  IngredientLine line,
  List<String> steps, {
  bool drained = false,
}) sync* {
  final raw = line.raw.toLowerCase();
  if (RegExp(r'\bplus salt\b').hasMatch(raw)) {
    return;
  }
  final own = headNounOf(normalizeItem(lineItemOf(line)));
  final kind = own == 'soda' || own == 'sugar' ? own! : 'salt';
  final word = RegExp(switch (kind) {
    'soda' => r'\bbaking soda\b',
    'sugar' => r'\bsugar\b',
    _ => r'\bsalt\b(?!\s+pork)',
  });
  final salts = [
    for (final other in nutritionLines(recipe))
      if (headNounOf(normalizeItem(lineItemOf(other))) == kind) other,
  ];
  final amount = RegExp(
    '([\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]*'
    r'(?:teaspoons?|tablespoons?))\s+(?:of the\s+)?$',
  );
  final mentions = [
    for (final (i, step) in steps.indexed)
      for (final mention in word.allMatches(step.toLowerCase()))
        (
          step: i,
          at: mention.start,
          written: amount
              .firstMatch(step.toLowerCase().substring(0, mention.start))?[1]
              ?.trim(),
        ),
  ];
  // In a recipe of several salt lines, a bare "salt" in cooking water
  // ([drained]) is the one salt line's that no step names with its amount
  // and no volume makes a medium: 0358 Spaghetti and Meatballs for a Crowd
  // names "1½ teaspoons salt" in its sauce, so "Add the pasta and salt" is
  // the 2 tablespoons'; 0461 Simplified Cassoulet's ½ cup is its brine, so
  // the beans' "salt" is the 1 teaspoon (v11, Opus). Never for a dissolve:
  // "Dissolve the salt and sugar in 2 gallons cold water … submerge" is the
  // brine line's own bare salt — read for any line, it zeroed 6 small table
  // salt lines of brined roasts as brine (measured, v11).
  final bare = [
    for (final other in salts)
      if (!mentions.any(
            (m) =>
                m.written != null &&
                other.raw.toLowerCase().startsWith(m.written!),
          ) &&
          discardedMediumOf(
                recipe,
                other,
                normalizeItem(lineItemOf(other)),
                bySentence: false,
              ) ==
              null)
        other,
  ];
  final ownsBare = salts.length == 1
      ? identical(salts.single, line)
      : drained && bare.length == 1 && identical(bare.single, line);
  // Several bare lines and as many bare mentions: a recipe lists a salt
  // where it is first used, so the nth mention is the nth line's (Biang
  // Biang Mian, 0376: "Whisk flour and salt" is the dough's ¾ teaspoon,
  // "bring water and salt to boil" the pot's tablespoon — the user's
  // ruling R2).
  final bareMentions = [
    for (final (i, m) in mentions.indexed)
      if (m.written == null) i,
  ];
  final nth = bare.indexWhere((other) => identical(other, line));
  final paired = drained && bareMentions.length == bare.length && nth >= 0
      ? bareMentions[nth]
      : null;
  for (final (i, (:step, :at, :written)) in mentions.indexed) {
    if (written != null ? raw.startsWith(written) : ownsBare || i == paired) {
      yield (step: step, at: at, share: null);
    } else if (drained && written != null && _isShare(line, written, salts)) {
      // The WRITTEN pot share of a divided line (the user's ruling R2,
      // 2026-09-28): "Add the remaining 1½ teaspoons salt and the macaroni
      // … Drain" (Stovetop Macaroni and Cheese, 0301, of "2 teaspoons table
      // salt"), "1 teaspoon of the salt" (Cincinnati Chili, 0303), "½
      // teaspoon salt" of "1¼ teaspoons table salt, divided" (Broccoli
      // Salad with Creamy Avocado Dressing, 1073).
      yield (step: step, at: at, share: written);
    }
  }
}

/// Whether [written] (an amount a step writes before its salt) is a smaller
/// share of [line] that no other of [salts] starts with. (Requiring the
/// line marked divided or the step's "of the" / "remaining" changed no line
/// of the library: removed, v13 refix.)
bool _isShare(IngredientLine line, String written, List<IngredientLine> salts) {
  final own = volumeMlOf(line.amounts);
  final part = volumeMlOf(parseIngredientLine('$written salt').amounts);
  if (own == null || part == null || part >= own) {
    return false;
  }
  return !salts.any((other) => other.raw.toLowerCase().startsWith(written));
}

/// The sentence of [text] holding offset [at].
String _sentenceAt(String text, int at) {
  final start = text.lastIndexOf(RegExp(r'\.\s'), at) + 1;
  final end = text.indexOf(RegExp(r'\.(\s|$)'), at);
  return text.substring(start, end < 0 ? text.length : end);
}

/// Whether a step puts [line]'s salt or baking soda ([_ownMentions]) in
/// water that boils — the step names the water before the mention or in
/// its sentence ("Bring 6 quarts water to a boil. Add the noodles and salt";
/// "bring 2 quarts water to boil in Dutch oven. Set colander in large bowl.
/// Add spaghetti and salt to pot", Foolproof Spaghetti Carbonara 0362,
/// where the water is two sentences back; requiring the sentence to open
/// with "add" changed no line of the library: removed, refix round 2) — and
/// a drain follows it, AFTER the mention in that step
/// or in the next ("Drain the noodles"; not "do not drain"): the water
/// leaves with its salt ([DiscardedMedium.cookingWater]).
bool _drainedWater(Recipe recipe, IngredientLine line, List<String> steps) =>
    _drainedMention(recipe, line, steps) != null;

/// The [_drainedWater] mention of [line]: its written pot share ([_isShare],
/// null when the line's whole amount goes in the pot), or null for none.
({String? share})? _drainedMention(
  Recipe recipe,
  IngredientLine line,
  List<String> steps,
) {
  final water = RegExp(r'\bwater\b');
  final drain = RegExp(r'(?<!not )\bdrain');
  // Sugar only in a pot a skimmer empties (New York Bagels, 0810): a drain
  // after it keeps the liquid (Austrian-Style Potato Salad, 0056, "reserving
  // the cooking liquid"), drains a jar (Bread-and-Butter Pickles, 0664) or
  // another pot (Brown Rice Bowls, 0104, whose sugar is a dressing's).
  final sugar = headNounOf(normalizeItem(lineItemOf(line))) == 'sugar';
  // A pot emptied with a skimmer or a slotted spoon leaves its water behind
  // like a drain (the user's ruling R2: Thick-Cut Sweet Potato Fries, 0318)
  // — in the next step only when its sentence or the one before it names
  // the water (Biang Biang Mian, 0376, "Add half of noodles to water and
  // cook … Using wire skimmer, transfer noodles"): Vegetable Bibimbap's
  // (0512) next step lifts carrots from a skillet with one, while its salt
  // boils in the rice's own water.
  final skimmer = RegExp(r'\b(skimmer|slotted spoon)\b');
  bool lifted(String text) => skimmer.allMatches(text).any((m) {
    final start = text.lastIndexOf(RegExp(r'\.\s'), m.start);
    final previous = start < 0
        ? 0
        : text.lastIndexOf(RegExp(r'\.\s'), start - 1) + 1;
    final end = text.indexOf(RegExp(r'\.(\s|$)'), m.start);
    return water.hasMatch(
      text.substring(previous, end < 0 ? text.length : end),
    );
  });
  for (final (:step, :at, :share) in _ownMentions(
    recipe,
    line,
    steps,
    drained: true,
  )) {
    final text = steps[step].toLowerCase();
    // Milk is no water: Saag Paneer's (0563) curds drain, but its salt went
    // in boiled milk. The water must be named BEFORE the end of the salt's
    // own sentence: a salt seasoned onto meat before a later pasta pot is
    // no cooking water — no corpus line has that shape, so the bound is
    // pinned on a synthesized one (a stated exception, review Run 043).
    final end = text.indexOf(RegExp(r'\.(\s|$)'), at);
    final inWater = water.hasMatch(end < 0 ? text : text.substring(0, end));
    if (!inWater || !text.contains(RegExp(r'\bboil'))) {
      continue;
    }
    final next = step + 1 < steps.length ? steps[step + 1].toLowerCase() : '';
    if ((!sugar &&
            (drain.hasMatch(text.substring(at)) || drain.hasMatch(next))) ||
        skimmer.hasMatch(text.substring(at)) ||
        lifted(next)) {
      return (share: share);
    }
  }
  return null;
}

/// Whether a step dissolves [line]'s salt ([_ownMentions]) in a measured
/// volume of water the food is then submerged in — a brine whatever its
/// volume or name: "Dissolve salt in 2½ quarts water in Dutch oven; place
/// ribs in pot so they are fully submerged" (0617: 2 tablespoons, under the
/// 3-tablespoon threshold, and never called a brine; checkpoint 6). The
/// salt is what the verb dissolves: the mention sits between "dissolv…" and
/// "in <amount>" in its own sentence — "Dissolve sugar in 2 cups warm
/// water, then whisk in the salt" dissolves the sugar — and the step says
/// "submerg": a dough's "Dissolve salt in 2 tablespoons warm water" is
/// eaten (v11, both fleets). No clause moves a line of the library
/// (every salt it dissolves in a written amount is 0617's or a brine by its
/// own volume), so each — the verb before the mention, the amount after
/// it, the submerge — is pinned on a synthesized line (stated exceptions).
/// (The unit after the amount — quarts, gallons or cups — and a "water"
/// after it changed no line of the library: removed, refix round 3; the
/// written amount stays — "in remaining 2 tablespoons warm water" is
/// a dough's, Easy Sandwich Bread 0807.)
bool _dissolvedInWater(
  Recipe recipe,
  IngredientLine line,
  List<String> steps,
) {
  // The verb keeps a whisked or simmered salt out ("Whisk together flour
  // and salt in 8-cup liquid measuring cup", Popovers 1109).
  final verb = RegExp(r'\bdissolv\w*\b');
  final into = RegExp('\\bin [\\d$vulgarFractionChars]');
  for (final (:step, :at, share: _) in _ownMentions(recipe, line, steps)) {
    final text = steps[step].toLowerCase();
    if (!text.contains('submerg')) {
      continue;
    }
    final start = text.lastIndexOf(RegExp(r'\.\s'), at) + 1;
    final sentence = _sentenceAt(text, at);
    final mention = at - start;
    if (verb.allMatches(sentence).any((v) => v.end <= mention) &&
        into.allMatches(sentence).any((i) => i.start > mention)) {
      return true;
    }
  }
  return false;
}

/// Whether a step dissolves [line] (a salt, [normalized]) in the SAME
/// sentence as another salt line of [recipe] that is brine by its volume:
/// "Dissolve salt, sugar, and curing salt in 4 quarts water" — 2 teaspoons
/// of curing salt are under the 3-tablespoon threshold but go in the same
/// discarded brine (0091 Home-Corned Beef: +583 mg sodium a serving counted,
/// checkpoint 5).
bool _dissolvedWithBrineSalt(
  Recipe recipe,
  IngredientLine line,
  String normalized,
  List<String> steps,
) {
  final words = normalized.split(' ');
  final own = words.skip(words.length > 2 ? words.length - 2 : 0).join(' ');
  final sentences = [
    for (final step in steps)
      for (final sentence in step.toLowerCase().split(RegExp(r'(?<=\.)\s+')))
        if (sentence.contains(RegExp(r'\bdissolv')) && sentence.contains(own))
          sentence.replaceFirst(own, ' '),
  ];
  if (sentences.isEmpty) {
    return false;
  }
  // (Another line is brine only when its head is salt, and a twin of the
  // line — the same text — is brine by volume exactly when the line is:
  // neither needs a check of its own, checkpoint 5 review.)
  for (final other in nutritionLines(recipe)) {
    if (identical(other, line)) {
      continue;
    }
    final item = normalizeItem(lineItemOf(other));
    if (!sentences.any((sentence) => sentence.contains(item)) ||
        discardedMediumOf(recipe, other, item, bySentence: false) !=
            DiscardedMedium.brine) {
      continue;
    }
    return true;
  }
  return false;
}

/// What an ENGINE write stores for [line] of [recipe] on [food]: the grams
/// and their source, and why the row is held out of the totals (null when
/// nothing holds it). [picked] is true when the engine chose the food from a
/// search (a person's food is never held for publishing nothing). [decided]
/// is true when the food is a person's decision on the line's key (inherited
/// or applied to all): the decision answers every FOOD hold (no_nutrients,
/// dried_for_fresh, cured_for_fresh, borderline, unnamed_food) but never a
/// LINE hold — a discarded medium, or a second food, which a decision on
/// the first food's key cannot count (checkpoint 5: one confirm on 'lemon
/// zest plus juice' counted 48 lines at the zest's grams), or shellfish
/// bought in the shell ([boughtInShell], `in_shell`), whose edible share no
/// food decision gives. A second food
/// [secondFoodRuleOf] resolves counts on its own record, held by nothing
/// ([citrus] and [eggs] are its switches).
({double? grams, String? source, String? hold}) engineOutcome(
  Recipe recipe,
  IngredientLine line,
  FdcFood food,
  GramResolution? resolved, {
  bool picked = false,
  bool decided = false,
  double? confidence,
  bool citrus = citrusJuiceRuleOn,
  bool eggs = eggPartsMassSumOn,
}) {
  final normalized = normalizeItem(lineItemOf(line));
  final medium = discardedMediumOf(
    recipe,
    line,
    normalized,
    grams: resolved?.grams,
  );
  // Only the first part of a "plus" line is the medium when a step eats
  // the second ([_eatenPlusPart]).
  final plus = medium == null
      ? null
      : _eatenPlusPart(recipe, line, headNounOf(normalized));
  // A divided line's written pot or brine share: the rest of the line is
  // eaten.
  final share = plus != null
      ? null
      : medium == DiscardedMedium.cookingWater
      ? _potShareOf(recipe, line)
      : medium == DiscardedMedium.brine || medium == DiscardedMedium.brineSugar
      ? _brineShareOf(recipe, line, headNounOf(normalized))
      : null;
  final kept = plus != null
      ? resolveGrams(
          amounts: [plus.amount],
          food: food,
          normalizedItem: normalized,
        )
      : share != null && resolved != null
      ? GramResolution(
          grams: resolved.grams * (1 - share),
          source: GramSource.discarded,
          basis: resolved.basis,
        )
      : null;
  if (medium != null &&
      medium.followsPolicy &&
      discardedMediaPolicy == DiscardedMediaPolicy.zero) {
    return (
      grams: kept?.grams ?? 0,
      source: GramSource.discarded.name,
      hold: null,
    );
  }
  // A HELD medium's eaten part is its grams too, held with the line: a
  // confirm counts that part, never the water's (0300 Classic Macaroni and
  // Cheese: "1 tablespoon plus 1 teaspoon table salt", 1 tablespoon in the
  // drained pasta water, "remaining 1 teaspoon salt" in the roux — v10 held
  // all 24 g, a confirm would count them; v11, Opus). How much of the water's
  // part the food keeps nothing says, so the line stays held for a person.
  final resolution = kept == null
      ? resolved
      : GramResolution(
          grams: kept.grams,
          source: GramSource.discarded,
          basis: kept.basis,
        );
  final rule = secondFoodRuleOf(line, citrus: citrus, eggs: eggs);
  if (rule != null && rule.fdcId == food.fdcId) {
    final resolved = rule.gramsOn(food);
    return (grams: resolved?.grams, source: resolved?.source.name, hold: null);
  }
  final secondFood = namesSecondFood(line.raw);
  // A LINE hold too: no food decision says how much of a shell is eaten.
  final inShell = boughtInShell(line.raw);
  // An amount-less line counts as 0 g — never one bought in the shell: 0 g
  // would read resolved (`counted`) and leave the queue, hold or no hold.
  // No corpus line buys shellfish without an amount, so the guard is pinned
  // on a synthesized one (a stated exception, v11).
  final zero = amountlessLinesZero && line.amounts.isEmpty && !inShell;
  if (decided) {
    return (
      grams: zero ? 0 : resolution?.grams,
      source: zero ? GramSource.unmeasured.name : resolution?.source.name,
      hold: medium != null
          ? 'discarded_medium'
          : secondFood
          ? 'second_food'
          : inShell
          ? 'in_shell'
          : null,
    );
  }
  // A line that names no food goes to a person even when it has no amount
  // ("2 tablespoons juice", which the parser kept whole).
  final unnamed = picked && namesNoFood(line);
  if (zero) {
    return (
      grams: 0,
      source: GramSource.unmeasured.name,
      hold: unnamed ? 'unnamed_food' : null,
    );
  }
  final fresh = picked && !allowDriedForFresh
      ? freshHoldOf(line.raw, food.description)
      : null;
  final hold = medium != null
      ? 'discarded_medium'
      // "2 large eggs plus 6 large yolks": only the first food was matched;
      // counting it alone would drop the second silently.
      : secondFood
      ? 'second_food'
      // Shellfish bought in the shell: no record publishes its edible share.
      : inShell
      ? 'in_shell'
      : picked &&
            publishesNothing(food) &&
            !nutrientSiblings.containsKey(food.fdcId)
      ? 'no_nutrients'
      : unnamed
      ? 'unnamed_food'
      : fresh ?? (picked && inBorderlineBand(confidence) ? 'borderline' : null);
  return (
    grams: resolution?.grams,
    source: resolution?.source.name,
    hold: hold,
  );
}

/// The note a [isSubRecipeReference] line is stored under.
const String subRecipeNote =
    'Sub-recipe — made from its own recipe, not counted in these totals';

/// Whether the line [raw] names a sub-recipe the recipe makes apart — "1
/// recipe Simple Tomato Sauce (recipe follows)" (Lighter Chicken Parmesan,
/// 0416), "10 cups Vanilla Frosting (recipe follows)" (Rainbow Cake, 1201),
/// "1 recipe Buttery Croutons (this page)": such a line is never counted on
/// a food (the user's ruling, 2026-09-27; v12 counted 8 of them, the
/// frosting at 2,082 g of a ready-to-eat one). The mark is "recipe(s)
/// follow(s)" in the line's first alternative, or "(… this page)" before
/// its first comma — "shrimp, peeled and deveined (see this page)" points
/// at a technique, not a recipe — or either anywhere on a line that opens
/// "<n> recipe" ("1 recipe flavored butter or vinaigrette (recipes
/// follow)"). A food offered first stays that food: "½ teaspoon table salt
/// or 1 recipe topping (recipes follow)" is the salt.
bool isSubRecipeReference(String raw) {
  final text = raw.toLowerCase();
  final follows = RegExp(r'\brecipes? follows?\b');
  final page = RegExp(r'\([^)]*\bthis page\b');
  if (RegExp(
    '^\\s*[\\d$vulgarFractionChars/ .-]+\\s*recipes?\\b',
  ).hasMatch(text)) {
    return follows.hasMatch(text) || page.hasMatch(text);
  }
  final first = text.split(RegExp(r'\s+or\s+')).first;
  return follows.hasMatch(first) || page.hasMatch(first.split(',').first);
}

/// Whether the [isSubRecipeReference] line [line] is a number of a food the
/// recipe prepares by the referenced technique rather than a batch of
/// something it makes: every amount a bare count, with no unit. "3
/// hard-cooked eggs (recipe follows)" (Wilted Spinach Salad, 0040), "4
/// Easy-Peel Hard-Cooked Eggs (this page)" (Gado-Gado, 1192) — v13 zeroed
/// 150 to 200 g of eggs each — not "1 recipe Easy-Peel Hard-Cooked Eggs"
/// (the unit `recipe`), "4 cups Cream Cheese Frosting", "4 ounces Simple
/// Syrup". Such a line is matched like any other (a pick below the gate is
/// held for review like any other); one its pick gives no grams stays the
/// 0 g sub-recipe — "8 Home-Fried Taco Shells (recipe follows)" (Ground
/// Beef Tacos, 0478) on "Taco shells, baked".
bool subRecipeCountsItsFood(IngredientLine line) =>
    line.amounts.isNotEmpty && line.amounts.every((a) => a.unit == null);

/// The row a sub-recipe line is stored under: on no food, 0 g unmeasured.
IngredientMatchRow _subRecipeRow(
  Recipe recipe,
  int position,
  IngredientLine line,
  String key,
) => IngredientMatchRow(
  recipeId: recipe.id,
  position: position,
  raw: line.raw,
  itemKey: key,
  fdcId: null,
  description: subRecipeNote,
  dataType: null,
  confidence: 1,
  grams: 0,
  gramSource: GramSource.unmeasured.name,
  status: 'confirmed',
);

/// Whether the line [raw] names a second food the first food's record does
/// not cover ("2 large eggs plus 6 large yolks", "zest plus 2 tablespoons
/// juice"): the engine counts it by its [secondFoodRuleOf] or holds it
/// `second_food`, and a decision on its key reaches it never
/// ([decisionReach]). Read from the raw text alone, so the reach filters
/// stored rows with no recipe loaded.
bool namesSecondFood(String raw) {
  final plus = plusPartOf(raw);
  return plus != null &&
      !plus.sameFood &&
      // A counted extra cut into wedges ("plus 1 lemon, cut into wedges") is
      // for serving, never in the dish, whichever fruit it is. Other counted
      // extras are eaten — lemon halves grilled and squeezed into the
      // dressing (0654), the whole egg in the batter (0878) — so a person
      // looks.
      !(plus.amount.measure == Measure.count &&
          RegExp(r'\bplus\b.*\bwedges?\b', caseSensitive: false).hasMatch(raw));
}

/// USER ANSWER SWITCH (queue keys, audit 3 N5). True (the recommended
/// default) keys a line that names a second food ("zest plus 2 tablespoons
/// juice", "eggs plus 2 yolks") apart from the first food's lines, so a
/// decision on 'lemon zest' never reaches the 64 lines whose mass is mostly
/// juice. False keeps them in the first food's group (still held
/// `second_food`, so none counts on the first amount alone).
const bool secondFoodOwnKey = true;

/// USER QUESTION SWITCH (citrus second food, checkpoint 5). True (the
/// audit's recommendation) counts "1 teaspoon grated lemon zest plus 2
/// tablespoons juice" — a zest or peel of at most a tablespoon plus the SAME
/// fruit's juice, either part first — as the juice amount on the fruit's
/// juice record, the zest dropped (151 of 1,072 kcal over the library's 69
/// lines), instead of holding it `second_food`. False holds it.
const bool citrusJuiceRuleOn = true;

/// USER QUESTION SWITCH (egg parts, checkpoint 5). True (the audit's
/// recommendation) counts "2 large eggs plus 2 large yolks" (and eggs plus
/// whites, yolks plus whites) as the parts' summed piece weights (50 g egg,
/// 17 g yolk, 33 g white) on the whole-egg record: about 15% under the
/// parts' own records in energy, but no line counted at the first part's
/// grams. Lines led by a part ("5 large egg whites plus 1 large egg") stay
/// held: the whole-egg record misstates them most. False holds them all.
const bool eggPartsMassSumOn = true;

/// The juice record of each citrus fruit [citrusJuiceRuleOn] counts on.
const Map<String, int> _citrusJuice = {
  'lemon': 167747, // Lemon juice, raw
  'lime': 168156, // Lime juice, raw
  'orange': 169098, // Orange juice, raw
};

/// The whole-egg record [eggPartsMassSumOn] counts on: "Eggs, Grade A,
/// Large, egg whole" (Foundation).
const int _wholeEgg = 748967;

/// A tablespoon: the most zest [citrusJuiceRuleOn] drops.
const double _tablespoonMl = 14.7868;

/// A second-food line the engine counts on one record by rule: the record,
/// the words its score is ranked under, and the grams on it.
class SecondFoodRule {
  const SecondFoodRule._(this.fdcId, this.query, this._grams);

  /// The record the line counts on.
  final int fdcId;

  /// The words the record is ranked under for the row's confidence.
  final String query;

  final GramResolution? Function(FdcFood? food) _grams;

  /// The line's grams on [food] (the record [fdcId]; the egg sum needs none).
  GramResolution? gramsOn(FdcFood? food) => _grams(food);
}

/// The [SecondFoodRule] of [line], or null: a zest-plus-juice line under
/// [citrus], an eggs-plus-parts line under [eggs].
SecondFoodRule? secondFoodRuleOf(
  IngredientLine line, {
  bool citrus = citrusJuiceRuleOn,
  bool eggs = eggPartsMassSumOn,
}) {
  // Only a line that names a second food: the reach leaves out exactly
  // those ([decisionReach]), so a rule line is never offered.
  final at = RegExp(
    '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
    caseSensitive: false,
  ).firstMatch(line.raw);
  if (!namesSecondFood(line.raw) || at == null) {
    return null;
  }
  final plus = plusPartOf(line.raw)!;
  final firstText = line.raw.substring(0, at.start).toLowerCase();
  final citrusKey = RegExp(
    r'^(lemon|lime|orange) (zest|peel) plus juice$',
  ).firstMatch(lineKeyOf(line));
  if (citrus && citrusKey != null) {
    final zestFirst = RegExp(r'\b(zest|peel)\b').hasMatch(firstText);
    final lineVolume = line.amounts
        .where((amount) => amount.measure == Measure.volume)
        .firstOrNull;
    // A zest pared in strips and counted, with no volume of its own ("12
    // (3-inch) strips lemon zest plus 6 tablespoons juice", 0005; "1
    // tablespoon lemon juice …, plus 3 strips zest", 0851) is steeped or
    // candied, never a measure of grated peel: it drops like a small zest
    // (checkpoint 6). A strip line that gives the peel a volume ("10
    // (3-inch) strips orange peel … (¼ cup)", 0536) is read by the volume.
    bool strips(Amount amount) =>
        amount.measure == Measure.count &&
        RegExp(r'^strips?$').hasMatch(amount.unit ?? '');
    final juice = zestFirst ? plus.amount : lineVolume;
    final zest = zestFirst
        ? lineVolume ?? line.amounts.where(strips).firstOrNull
        : plus.amount;
    final zestMl = zest == null
        ? null
        : strips(zest)
        ? 0.0
        : volumeMlOf([zest]);
    if (juice == null ||
        volumeMlOf([juice]) == null ||
        zestMl == null ||
        zestMl > _tablespoonMl + 0.01) {
      return null;
    }
    final fruit = citrusKey[1]!;
    return SecondFoodRule._(_citrusJuice[fruit]!, '$fruit juice', (food) {
      final grams = resolveGrams(
        amounts: [juice],
        food: food,
        normalizedItem: '$fruit juice',
      );
      return grams == null
          ? null
          : GramResolution(
              grams: grams.grams,
              source: grams.source,
              basis: '${grams.basis} · juice only (the zest is dropped)',
            );
    });
  }
  String? part(String text) => RegExp(r'\byolks?\b').hasMatch(text)
      ? 'yolk'
      : RegExp(r'\bwhites?\b').hasMatch(text)
      ? 'white'
      : RegExp(r'\beggs?\b').hasMatch(text)
      ? 'egg'
      : null;
  final first = part(firstText);
  final second = part(plus.text.toLowerCase());
  final firstCount = countOf(line.amounts);
  final secondCount = countOf([plus.amount]);
  if (!eggs ||
      first == null ||
      second == null ||
      firstCount == null ||
      secondCount == null ||
      !const {'egg yolk', 'egg white', 'yolk white'}.contains(
        '$first $second',
      )) {
    return null;
  }
  String label(double count) => count == count.roundToDouble()
      ? count.toInt().toString()
      : count.toString();
  final firstGrams = pieceWeightOf(first == 'egg' ? 'egg' : 'egg $first')!;
  final secondGrams = pieceWeightOf('egg $second')!;
  return SecondFoodRule._(
    _wholeEgg,
    'egg',
    (_) => GramResolution(
      grams: firstCount * firstGrams + secondCount * secondGrams,
      source: GramSource.piece,
      basis:
          '${label(firstCount)} × ${firstGrams.round()} g $first + '
          '${label(secondCount)} × ${secondGrams.round()} g $second, '
          'summed on the whole egg',
    ),
  );
}

/// USER ANSWER SWITCH (the 0.52–0.54 band, audit 3 N9). True holds an
/// engine pick scored in [[_bandLow], [_bandHigh]) for a person
/// (`hold: borderline`): 41 of that band's 53 counted lines were wrong
/// foods, and the 12 right ones would wait for a confirm too. False (the
/// default until the user answers) counts them as before.
const bool holdBorderlineBand = false;
const double _bandLow = 0.52;
const double _bandHigh = 0.54;

/// Whether an engine pick scored [confidence] is held `borderline` under
/// the band switch [on] (default [holdBorderlineBand]).
bool inBorderlineBand(double? confidence, {bool on = holdBorderlineBand}) =>
    on &&
    confidence != null &&
    confidence >= _bandLow &&
    confidence < _bandHigh;

/// Lone words the parser leaves as the whole item when the corpus lists
/// qualifiers before the food ("3 cups unsweetened, shredded, desiccated
/// (dried) coconut" → 'unsweetened'); a participle ("toasted, skinned, and
/// chopped hazelnuts") is one too. 11 library lines, 6 counted on
/// Applesauce, red cabbage, a steak (audit 3, N4).
const Set<String> _loneAdjectives = {
  'red',
  'yellow',
  'green',
  'white',
  'plain',
  'ripe',
  'firm',
  'fine-ground',
  'lengthwise',
  'dry',
  // A cut direction, like 'lengthwise': "lengthwise, seeded, and sliced thin
  // on bias" continues the line above it (bun cha).
  'bias',
};

/// Words that join qualifiers without naming a food ("toasted, skinned, and
/// chopped").
const Set<String> _joiners = {'and', 'or', 'on', 'in'};

bool _namesNoFood(String normalized) {
  final words = normalized.split(' ');
  return words.isNotEmpty &&
      words.every(
        (word) =>
            _loneAdjectives.contains(word) ||
            _joiners.contains(word) ||
            _participle(word),
      );
}

final RegExp _citrusWord = RegExp(
  r'\b(lemon|lime|orange|grapefruit|tangerine)s?\b',
);

/// The item text the matcher normalizes, searches and keys [line] by: its
/// parsed item — unless that is a lone qualifier, which reads on to the
/// next comma ("short, curly pasta" → 'short curly pasta'; 'fine-ground,
/// whole-grain yellow cornmeal'), or bare 'juice' or 'zest', which takes
/// its fruit from the line ("6 tablespoons juice (2 lemons)" → 'lemon
/// juice'; it searched Beet juice). A rewrite key is left to its rewrite
/// ('short', 'dark'). With [dropPrep] false a prep-only segment is kept,
/// as before v8 — the reading a v7 decision's item text was stored under
/// (the boot re-key finds its line by it: `rekeyDecisions`).
String lineItemOf(IngredientLine line, {bool dropPrep = true}) {
  final item = line.item ?? line.raw;
  final normalized = normalizeItem(item);
  // A bare 'zest' too: Key Lime Pie's (0989) item "grated zest plus 1/2 cup
  // juice" keeps its fruit in the prep "from 3 or 4 limes" and searched
  // 'zest' (FDC: no hits) — its key already read the line's fruit
  // ([decisionItemOf]; checkpoint 6). (No line of the library is a bare
  // 'peel'.)
  if (normalized == 'juice' || normalized == 'zest') {
    final fruit = _citrusWord.firstMatch(line.raw.toLowerCase());
    return fruit == null ? item : '${fruit[1]} $normalized';
  }
  // A lone size word normalizes to nothing: "2 medium, firm, ripe tomatoes"
  // parsed its item as 'medium' and searched nothing (checkpoint 7: 4
  // no_match lines).
  if ((normalized.isNotEmpty && !_namesNoFood(normalized)) ||
      searchQueryFor(normalized) != normalized ||
      line.item == null) {
    return item;
  }
  final raw = line.raw.toLowerCase();
  final word = item.toLowerCase().trim().split(RegExp(r'\s+')).last;
  final at = raw.indexOf(RegExp('${RegExp.escape(word)}\\s*,'));
  if (at < 0) {
    return item;
  }
  // Segment by segment until one names a food: "red, yellow, or orange bell
  // peppers", "toasted, skinned, and chopped hazelnuts" (audit 4: 4 of the 6
  // lines the gate held read only one segment on). None does: the line goes
  // to a person on its own words — nothing new is searched.
  final parts = [for (final part in raw.substring(at).split(',')) part.trim()];
  for (var n = 2; n <= parts.length; n++) {
    final extended = parts.take(n).join(' ');
    if (!_namesNoFood(normalizeItem(extended))) {
      // A segment of prep words only ("toasted", "skinned", "patted dry",
      // "unsweetened") says how the food is handled: kept, it made
      // 'toasted skinned and hazelnut' a key and a live search (checkpoint
      // 5). A colour or variety segment stays ("red, yellow, or orange bell
      // peppers").
      // A firmness segment ("medium, firm, ripe tomatoes") says how firm,
      // never what: kept, the tomatoes keyed and searched 'firm ripe
      // tomatoes' beside 9 'ripe tomato' lines. (A size word stays, as in
      // 'medium onion': the key drops it.)
      return [
        for (final (i, part) in parts.take(n).indexed)
          if (i == n - 1 || !dropPrep || !(_prepOnly(part) || part == 'firm'))
            part,
      ].join(' ');
    }
  }
  return item;
}

/// Whether a comma segment (one [lineItemOf] read on past, so it names no
/// food) is prep words only: a participle among its words. (A segment
/// [normalizeItem] reduces to nothing, 'shredded', leaves the key as it is.)
bool _prepOnly(String segment) => normalizeItem(segment)
    .split(' ')
    .any(
      (word) =>
          _participle(word) &&
          !_loneAdjectives.contains(word) &&
          !_identityParticiples.contains(word),
    );

/// Participles that name a form the food is BOUGHT in, kept with it:
/// "roasted, salted pepitas" (1071) is roasted pepitas — its cached query —
/// and "unsweetened, shredded, desiccated (dried) coconut" (0831)
/// unsweetened coconut. Only 'roasted' and 'unsweetened' open a prep-only
/// segment in the library; the rest keep a recipe typed later with its food
/// — "1 cup sweetened, shredded coconut" stays 'sweetened coconut', its v7
/// key and cached rewrite (checkpoint 5 review). A word here says what the
/// food IS; a prep word (toasted, skinned, stemmed, chopped) says what the
/// cook does to it. Each word is one a real corpus line puts before its food
/// (pinned: the line with a comma after the word keys as the line does);
/// 'salted' and 'unsalted' need no entry — [normalizeItem] reads them as
/// 'with salt', no participle.
const Set<String> _identityParticiples = {
  'roasted',
  'unsweetened',
  'sweetened',
  'smoked',
  'dried',
  'cooked',
  'canned',
  'pickled',
  'candied',
  'crystallized',
  'blanched',
  'fried',
  'powdered',
  'unseasoned',
  'aged',
  'cracked',
};

bool _participle(String word) =>
    word.endsWith('ed') && !word.endsWith('eed') && !word.endsWith('ead');

/// Whether [line] names no food the matcher can read: its item is still a
/// lone qualifier after [lineItemOf], or 'juice' of no named fruit. The
/// engine holds such a line (`hold: unnamed_food`) instead of counting the
/// qualifier's best record ("Applesauce, unsweetened" for coconut).
bool namesNoFood(IngredientLine line) {
  final normalized = normalizeItem(lineItemOf(line));
  return normalized == 'juice' || _namesNoFood(normalized);
}

/// The text a person's decision on [line] is stored under
/// (`ingredient_decisions.item`): [lineItemOf], with a second food's part
/// when [secondFoodOwnKey] keys it apart and the item lost it ("(3-inch)
/// lemon zest" of "12 (3-inch) strips lemon zest plus 6 tablespoons juice").
/// [dropPrep] as [lineItemOf]'s.
String decisionItemOf(IngredientLine line, {bool dropPrep = true}) {
  var item = lineItemOf(line, dropPrep: dropPrep);
  final plus = plusPartOf(line.raw);
  if (!secondFoodOwnKey || plus == null || plus.sameFood) {
    return item;
  }
  // A zest the item leaves fruitless takes its fruit from the line, as bare
  // 'juice' does ([lineItemOf]): Key Lime Pie's (0989) item is "grated zest
  // plus 1/2 cup juice", its fruit only in the prep "from 3 or 4 limes" — it
  // keyed 'zest plus juice' (checkpoint 5 review).
  final fruit = _citrusWord.firstMatch(line.raw.toLowerCase());
  if (fruit != null &&
      !_citrusWord.hasMatch(item.toLowerCase()) &&
      RegExp(r'\b(zest|peel)\b').hasMatch(item.toLowerCase())) {
    item = '${fruit[1]} $item';
  }
  return plusPartOf(item) != null ? item : '$item plus ${plus.text}';
}

/// A number as the corpus writes one: "8", "1½", "1/2".
final String _number = '[\\d$vulgarFractionChars][\\d$vulgarFractionChars/.]*';

/// The decision key of an item text: [itemKeyFor], and — for a line that
/// names a second food, under [secondFoodOwnKey] — that food's key after
/// "plus" ('lemon zest plus juice'). One function for lines and stored
/// decisions, so a re-key after a matcher change lands on the same key.
String decisionKeyFor(String itemText) {
  final key = itemKeyFor(itemText);
  final plus = secondFoodOwnKey ? plusPartOf(itemText) : null;
  if (key.isEmpty || plus == null || plus.sameFood) {
    return key;
  }
  // The first food is keyed from its own part, amounts cut: the whole text
  // leaked the second amount into it ('egg 2 yolk plus yolk', 'orange peel
  // cup juice plus juice' — audit 4: 118 held lines under 30 keys). A fruit
  // the text names only at its tail ("zest plus 1 tablespoon juice from 1
  // lemon") still leads it, as normalizeItem moves it.
  final blanked = itemText.replaceAllMapped(
    RegExp(r'\([^)]*\)'),
    (paren) => ' ' * paren[0]!.length,
  );
  final at = RegExp(
    '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
    caseSensitive: false,
  ).firstMatch(blanked)!.start;
  // B's own amount in the first part's "A or B" goes with its count noun
  // ("epazote or 8 to 10 sprigs fresh cilantro" — normalizeItem cuts a
  // leaked amount only before a measure word).
  var first = itemKeyFor(
    itemText
        .substring(0, at)
        .replaceAllMapped(
          RegExp(
            '\\bor\\s+$_number(?:\\s*(?:-|to)\\s*$_number)?'
            r'\s+(\S+)',
            caseSensitive: false,
          ),
          (m) => isCountNoun(m[1]!.toLowerCase()) ? 'or' : m[0]!,
        ),
  );
  final lead = key.split(' ').first;
  if (_citrusWord.hasMatch(lead) && !first.split(' ').contains(lead)) {
    first = '$lead $first'.trim();
  }
  if (first.isEmpty) {
    first = key;
  }
  // "2 large whole eggs plus 2 large egg yolks" is 'egg plus yolk', like
  // "2 large eggs plus 2 large yolks" (checkpoint 5).
  first = first.replaceAll(RegExp(r'\bwhole (?=egg\b)'), '');
  // The second food less what the first already names: "zest plus 1
  // tablespoon juice from 1 lemon" is 'lemon zest plus juice', like "lemon
  // zest plus 2 tablespoons juice" — and less what it is done with ("1
  // large white beaten with pinch salt").
  final named = first.split(' ').toSet();
  var words = itemKeyFor(
    parseIngredientLine(plus.text).item ?? '',
  ).split(' ');
  final withAt = words.indexOf('with');
  if (withAt > 0) {
    words = words.sublist(0, withAt);
  }
  final own = [
    for (final word in words)
      if (!named.contains(word)) word,
  ];
  final second = (own.isEmpty ? words : own).join(' ');
  if (second.isEmpty) {
    return first;
  }
  // One key for either order: "½ cup juice plus 2½ teaspoons grated zest"
  // is 'lemon zest plus juice' too.
  final juiceFirst = RegExp(
    r'^(lemon|lime|orange) juice$',
  ).firstMatch(first);
  if (juiceFirst != null && (second == 'zest' || second == 'peel')) {
    return '${juiceFirst[1]} $second plus juice';
  }
  // Egg parts too, the whole egg first, then the yolk: "5 large egg whites
  // plus 1 large egg" (0878) is 'egg plus white' like "2 large eggs, plus 1
  // large white" (0841), and "7 large egg yolks plus 2 large whole eggs"
  // (0994) 'egg plus yolk' (checkpoint 5 review: 'egg white plus egg',
  // 'egg yolk plus whole').
  final parts = [_eggParts[first], _eggParts[second]];
  if (parts.every((part) => part != null) && parts[0] != parts[1]) {
    final sorted = parts.cast<String>()..sort();
    return switch (sorted) {
      ['egg', final other] => 'egg plus $other',
      _ => 'egg yolk plus white',
    };
  }
  return '$first plus $second';
}

/// The egg part a key's side names, for [decisionKeyFor]'s one order.
const Map<String, String> _eggParts = {
  'egg': 'egg',
  'whole': 'egg',
  'whole egg': 'egg',
  'egg yolk': 'yolk',
  'yolk': 'yolk',
  'egg white': 'white',
  'white': 'white',
};

/// The decision key of [line].
String lineKeyOf(IngredientLine line) => decisionKeyFor(decisionItemOf(line));

/// The flattened, positioned ingredient lines nutrition works over.
List<IngredientLine> nutritionLines(Recipe recipe) => [
  for (final group in recipe.ingredients)
    for (final line in group.items) line,
];

/// Hash of everything nutrition depends on — when it changes, stored
/// results are stale.
String ingredientsHashOf(Recipe recipe) {
  // The matcher version is part of it: a bump makes every computed recipe
  // stale, so the stale sweep re-resolves its engine rows instead of leaving
  // scores and picks frozen at the matcher that wrote them. So are the
  // recipe's own steps and its title, which the discarded-media rules read
  // ([discardedMediumOf]): a steps-only edit adding or removing a drain
  // left the hold and the totals frozen, never stale (v11, Opus critic).
  final payload = jsonEncode({
    'matcher': matcherVersion,
    'title': recipe.title,
    'steps': [for (final step in recipe.steps) step.text],
    'lines': [
      for (final line in nutritionLines(recipe))
        {
          'raw': line.raw,
          'item': line.item,
          'amounts': [for (final amount in line.amounts) amount.toMap()],
        },
    ],
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

/// Matches every ingredient line of [recipe] against FDC and computes the
/// per-serving totals. Existing user decisions (confirmed / overridden /
/// skipped rows whose raw text is unchanged) are preserved; only `auto`
/// and changed rows are re-resolved.
Future<void> matchAndCompute(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
) async {
  final lines = nutritionLines(recipe);
  final existingRows = db.ingredientMatchesFor(recipe.id);
  final existing = {for (final row in existingRows) row.position: row};
  // Decided rows by their text, in position order. Rows are keyed by
  // POSITION, so an edit above a decided line (insert, delete, reorder)
  // moved the line out from under its row and the decision was lost —
  // reproduced on the Bundt cake, survey 2026-09-04. A moved line is found
  // here by its text and its row travels with it. A list per text, not a
  // map: 80 corpus recipes repeat a raw line, and the nth line keeps the
  // nth row.
  final decidedByRaw = <String, List<IngredientMatchRow>>{};
  for (final row in existingRows) {
    if (_isDecided(row)) {
      decidedByRaw.putIfAbsent(row.raw, () => []).add(row);
    }
  }
  // Decided rows whose exact text is GONE from the recipe: the line was
  // edited (an amount changed), possibly moved too. Such a row may be
  // re-attached by ingredient key — but only when the recipe still holds
  // as many lines of that ingredient as it held rows, i.e. an edit, not a
  // delete-and-add. Never by position alone: after a shift the row at a
  // line's old position can belong to a DIFFERENT line of the same
  // ingredient, and a skip copied onto it would silently drop that line
  // from the label (review, 2026-09-07).
  final newRaws = {for (final line in lines) line.raw};
  final orphansByKey = <String, List<IngredientMatchRow>>{};
  final oldKeyCounts = <String, int>{};
  for (final row in existingRows) {
    final rowKey = row.itemKey;
    if (rowKey == null || rowKey.isEmpty) {
      continue;
    }
    oldKeyCounts.update(rowKey, (n) => n + 1, ifAbsent: () => 1);
    if (_isDecided(row) && !newRaws.contains(row.raw)) {
      orphansByKey.putIfAbsent(rowKey, () => []).add(row);
    }
  }
  // Foods built from a search hit this compute (see the candidate loop):
  // the totals read them here, since they are not in fdc_food_cache.
  final standIns = <int, FdcFood>{};
  final newKeyCounts = <String, int>{};
  for (final line in lines) {
    final lineKey = lineKeyOf(line);
    if (lineKey.isNotEmpty) {
      newKeyCounts.update(lineKey, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  for (final (position, line) in lines.indexed) {
    final kept = existing[position];
    // A human decided this row; their call stands. `unmatched` is NOT a
    // decision — it is the engine's own "FDC had nothing", and a sweep exists
    // precisely to retry those once FDC gains data or the matcher improves.
    // (A cached empty search answer still short-circuits it, so the retry is
    // free but only helps once the normalised query or the cache changes.)
    if (kept != null && kept.raw == line.raw && _isDecided(kept)) {
      decidedByRaw[line.raw]?.remove(kept);
      continue;
    }

    final normalized = normalizeItem(lineItemOf(line));
    // The query keeps the line's own words; the KEY a decision is stored and
    // reused under is the singular form, so "onion" and "onions" are one.
    final key = lineKeyOf(line);

    // The line moved: a decided row for exactly this text sits at another
    // position. Bring it here, decision and all; its old position is either
    // rewritten by the line now there or dropped past the end.
    final moved = decidedByRaw[line.raw];
    if (moved != null && moved.isNotEmpty) {
      final row = moved.removeAt(0);
      db.upsertIngredientMatchIfUndecided(
        row.copyWith(position: position, itemKey: key),
      );
      continue;
    }

    // A decided line whose amount was edited (and possibly moved): its
    // text is gone, but the recipe still holds the same number of lines of
    // that ingredient. The food and the status stand, the grams are
    // re-derived for the new amount (a weight typed for the old amount no
    // longer applies); a skip stays a skip.
    // (A decided row kept at THIS position cannot be this line's own — a
    // same-text row was kept above — so it never blocks a re-attachment.)
    final orphans = orphansByKey[key];
    if (orphans != null &&
        orphans.isNotEmpty &&
        oldKeyCounts[key] == newKeyCounts[key]) {
      final edited = orphans.removeAt(0);
      if (edited.status == 'skipped') {
        db.upsertIngredientMatchIfUndecided(
          edited.copyWith(position: position, raw: line.raw, itemKey: key),
        );
        continue;
      }
      if (edited.fdcId != null) {
        final known = await _decidedFood(db, provider, edited.fdcId!, line);
        if (known != null) {
          final (food, resolution) = await gramsFor(db, provider, known, line);
          if (_foodFromCache(db, food.fdcId) == null) {
            standIns[food.fdcId] = food;
          }
          // The same outcome as a fresh compute on a decided food: a
          // discarded medium stays at 0 g however its amount changed
          // (Run 041's Opus critic: "3 cups" typed over "2 cups vegetable
          // oil for frying" counted the whole oil).
          final outcome = engineOutcome(
            recipe,
            line,
            food,
            resolution,
            decided: true,
          );
          db.upsertIngredientMatchIfUndecided(
            edited.copyWith(
              position: position,
              raw: line.raw,
              itemKey: key,
              grams: outcome.grams,
              clearGrams: outcome.grams == null,
              gramSource: outcome.source,
              clearGramSource: outcome.source == null,
            ),
          );
          continue;
        }
      }
    }
    final seasoning = line.amounts.isEmpty && isSeasoningToTaste(normalized);
    final equipment = isNonFood(normalized);
    // A sub-recipe the recipe makes apart stays out of the totals, on no
    // food, 0 g unmeasured (the user's ruling, 2026-09-27) — unless it is a
    // count of the food itself ([subRecipeCountsItsFood]).
    final subRecipe = isSubRecipeReference(line.raw);
    if (subRecipe && !subRecipeCountsItsFood(line)) {
      db.upsertIngredientMatchIfUndecided(
        _subRecipeRow(recipe, position, line, key),
      );
      continue;
    }
    if (normalized.isEmpty ||
        isWaterLike(normalized) ||
        seasoning ||
        equipment) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: normalized.isEmpty
              ? 'Nothing searchable in this line'
              : seasoning
              ? 'Seasoning to taste — no measurable amount'
              : equipment
              ? 'Equipment — not food, counts as zero'
              : 'Water/ice — counts as zero',
          dataType: null,
          confidence: 1,
          grams: null,
          gramSource: null,
          status: normalized.isEmpty ? 'unmatched' : 'confirmed',
        ),
      );
      continue;
    }

    // A second food the engine counts by rule ([secondFoodRuleOf]): the
    // line's own record, ahead of any key decision — a decision names the
    // first food only.
    final byRule = await ruleRowFor(db, provider, recipe, position, line);
    if (byRule != null) {
      if (_foodFromCache(db, byRule.food.fdcId) == null) {
        standIns[byRule.food.fdcId] = byRule.food;
      }
      db.upsertIngredientMatchIfUndecided(byRule.row);
      continue;
    }

    // A person already decided this ingredient (in any recipe, even one
    // since deleted): their food travels, with grams from THIS line's
    // amounts. Still `auto` (an engine write), so a decision made here later
    // still wins, and the review queue treats it as counted — confidence 1
    // says a person chose it.
    final prior = db.decisionFor(key);
    if (prior != null && prior.fdcId != null) {
      final known = await _decidedFood(db, provider, prior.fdcId!, line);
      if (known != null) {
        final (food, resolution) = await gramsFor(db, provider, known, line);
        if (_foodFromCache(db, food.fdcId) == null) {
          standIns[food.fdcId] = food;
        }
        final outcome = engineOutcome(
          recipe,
          line,
          food,
          resolution,
          decided: true,
        );
        db.upsertIngredientMatchIfUndecided(
          IngredientMatchRow(
            recipeId: recipe.id,
            position: position,
            raw: line.raw,
            itemKey: key,
            fdcId: food.fdcId,
            description: food.description,
            dataType: food.dataType,
            confidence: 1,
            grams: outcome.grams,
            gramSource: outcome.source,
            status: 'auto',
            hold: outcome.hold,
          ),
        );
        continue;
      }
    }

    final search = lineSearchFor(db, normalized, key);
    final candidates = await _cachedSearch(db, provider, search.answer);
    final ranked = rankCandidates(
      search.query,
      candidates,
      canned: namesCannedLegume(line.raw, normalized),
      skinOn: impliesSkinOn(line.raw, normalized),
      skinless: removesSkin(line.raw),
    );
    if (ranked.isEmpty) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: 'No FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      continue;
    }

    // Candidate selection handles two real FDC quirks: the detail
    // endpoint 404s for superseded records (the search payload's own
    // nutrient list stands in), and some records omit whole macros
    // (Foundation butter publishes no energy or saturated fat at all) —
    // a macro-complete record slightly lower in the ranking beats an
    // incomplete one at the top.
    //
    // The detail is fetched only when it adds something: a search hit
    // already carries the food's nutrients — the detail's values, rounded to
    // fewer digits (54 of the 70 recorded fixture foods differ somewhere, all
    // under 1%; pinned in nutrition_sweep_audit_test) — so the hit itself is
    // the food until the grams need FDC's household portions. A cached
    // detail is still preferred whenever one is held. That stand-in is held in
    // [standIns] for this compute's totals and NEVER written to
    // fdc_food_cache — a portion-less row there would starve every later
    // volume line of its portions. 92 of the sweep's first 227 detail fetches
    // fed only weight-sourced lines.
    RankedCandidate? best;
    FdcFood? food;
    RankedCandidate? fallbackCandidate;
    FdcFood? fallbackFood;
    for (final (rank, candidate) in ranked.take(3).indexed) {
      // The top pick stands even when docked (the sheet shows it, held by its
      // score); a record below it replaces it for its macros only when it is
      // the same food in another form.
      if (rank > 0 &&
          !sameFoodAsTop(
            search.query,
            ranked.first.candidate.description,
            candidate.candidate.description,
          )) {
        continue;
      }
      final id = candidate.candidate.fdcId;
      final hasNutrients =
          candidate.candidate.nutrientsPer100g?.isNotEmpty ?? false;
      final resolved =
          _foodFromCache(db, id) ??
          (hasNutrients
              ? candidate.candidate.toFood()
              : await _cachedFood(db, provider, id));
      if (resolved == null) {
        continue;
      }
      if (_macroComplete(resolved)) {
        best = candidate;
        food = resolved;
        break;
      }
      fallbackCandidate ??= candidate;
      fallbackFood ??= resolved;
    }
    if (best == null && fallbackCandidate != null) {
      best = fallbackCandidate;
      food = fallbackFood;
    }
    if (best == null) {
      db.upsertIngredientMatchIfUndecided(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: 'No fetchable FoodData Central match',
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        ),
      );
      continue;
    }
    // A pick below the review gate fetches no detail, so an uncached one
    // has no portions: a lower record of the same food whose detail IS
    // cached and sizes the line takes the row instead ([belowGateSizedTwin]).
    final twin = belowGateSizedTwin(db, line, search.query, ranked, best);
    if (twin != null) {
      best = twin.candidate;
      food = twin.food;
    }
    // A pick below the review gate is likely a wrong food: no detail is
    // fetched for its grams until a person confirms it.
    final (gramsFood, resolution) = await gramsFor(
      db,
      provider,
      food!,
      line,
      fetch: !belowConfidenceGate(best.confidence),
    );
    if (_foodFromCache(db, gramsFood.fdcId) == null) {
      standIns[gramsFood.fdcId] = gramsFood;
    }
    final outcome = engineOutcome(
      recipe,
      line,
      gramsFood,
      resolution,
      picked: true,
      confidence: best.confidence,
    );
    // A count of the food the engine cannot weigh is the sub-recipe still.
    if (subRecipe && outcome.grams == null) {
      db.upsertIngredientMatchIfUndecided(
        _subRecipeRow(recipe, position, line, key),
      );
      continue;
    }
    db.upsertIngredientMatchIfUndecided(
      IngredientMatchRow(
        recipeId: recipe.id,
        position: position,
        raw: line.raw,
        itemKey: key,
        fdcId: best.candidate.fdcId,
        description: best.candidate.description,
        dataType: best.candidate.dataType,
        confidence: best.confidence,
        grams: outcome.grams,
        gramSource: outcome.source,
        status: 'auto',
        hold: outcome.hold,
      ),
    );
  }

  // Lines removed by an edit leave orphan rows behind.
  db.deleteIngredientMatchesFrom(recipe.id, lines.length);

  await recomputeTotals(
    db,
    provider,
    recipe,
    freshMatch: true,
    standIns: standIns,
  );
}

/// A record ranked just below [best] — the same food in another form
/// ([sameFoodAsTop]) — to take a below-gate pick's row when [best]'s detail
/// is uncached and gives [line] no grams while the twin's cached detail
/// does. "½ cup pomegranate seeds" (Barley Salad with Pomegranate, 0718)
/// and "1 cup pomegranate seeds" (Braised Brisket with Pomegranate, 0224):
/// v12's stem lifted SR "Pomegranates, raw" (169134, 0.495, never fetched)
/// over FNDDS "Pomegranate, raw" (2709267, 0.485, cup portion cached), and
/// both lines lost their 87.5 g and 175 g (v12 review, Opus). Both stay
/// below the gate, in `check`. Null when nothing qualifies.
({RankedCandidate candidate, FdcFood food})? belowGateSizedTwin(
  SaltDatabase db,
  IngredientLine line,
  String query,
  List<RankedCandidate> ranked,
  RankedCandidate best,
) {
  if (!belowConfidenceGate(best.confidence) ||
      _foodFromCache(db, best.candidate.fdcId) != null ||
      lineGrams(db, line, best.candidate.toFood()) != null) {
    return null;
  }
  // (Only the top three changed no line of the library: removed, v13 refix.)
  for (final candidate in ranked) {
    if (identical(candidate, best) ||
        !sameFoodAsTop(
          query,
          best.candidate.description,
          candidate.candidate.description,
        )) {
      continue;
    }
    final cached = _foodFromCache(db, candidate.candidate.fdcId);
    if (cached != null &&
        _macroComplete(cached) &&
        lineGrams(db, line, cached) != null) {
      return (candidate: candidate, food: cached);
    }
  }
  return null;
}

/// The engine row of [line] (position [position] of [recipe]) when its
/// [secondFoodRuleOf] counts it: on the rule's record, ranked under the
/// rule's words, with the rule's grams — what a fresh compute writes, and
/// what an un-skip of an engine row moves to. Null when no rule applies, or
/// FDC has no such record; a provider failure fetching it propagates.
Future<({IngredientMatchRow row, FdcFood food})?> ruleRowFor(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  int position,
  IngredientLine line,
) async {
  final rule = secondFoodRuleOf(line);
  if (rule == null) {
    return null;
  }
  final target =
      knownFood(db, rule.fdcId, line: line) ??
      await _cachedFood(db, provider, rule.fdcId);
  if (target == null) {
    return null;
  }
  final outcome = engineOutcome(recipe, line, target, null, picked: true);
  return (
    food: target,
    row: IngredientMatchRow(
      recipeId: recipe.id,
      position: position,
      raw: line.raw,
      itemKey: lineKeyOf(line),
      fdcId: target.fdcId,
      description: target.description,
      dataType: target.dataType,
      confidence: rankCandidates(rule.query, [
        FdcCandidate(
          fdcId: target.fdcId,
          description: target.description,
          dataType: target.dataType,
        ),
      ]).first.confidence,
      grams: outcome.grams,
      gramSource: outcome.source,
      status: 'auto',
      hold: outcome.hold,
    ),
  );
}

/// Whether [resolveGrams] may read the food's portions for these [amounts]
/// past the weight steps: only for a volume or a count amount. A resolution
/// computed on a portion-less food is therefore final there when it came
/// from a weight, or when the line has neither.
bool _needsPortions(List<Amount> amounts, GramResolution? withoutPortions) =>
    withoutPortions?.source != GramSource.weight &&
    amounts.any(
      (amount) =>
          amount.measure == Measure.volume || amount.measure == Measure.count,
    );

/// Whether a WEIGHT resolution reads the food's portions after all: the
/// edible yield of a line that buys refuse, the drained weight of a can.
///
/// Only SR Legacy publishes refuse, drained-can and bird portions: 12 of the
/// 15 detail fetches the sweep made for them changed no grams, all on
/// Foundation and FNDDS records (checkpoint 5).
bool _weightReadsPortions(
  String raw,
  FdcFood food,
  GramResolution? withoutPortions,
) =>
    withoutPortions?.source == GramSource.weight &&
    food.dataType == 'SR Legacy' &&
    ((edibleYieldOn && buysRefuse(raw)) ||
        (cannedDrained && drainsCan(raw)) ||
        (wholeBirdYieldOn && countsGameHens(raw)));

/// [line]'s grams on [food], and the food they were read from. A search hit
/// (no fdc_food_cache row) is enough unless the grams may need FDC's
/// household portions — a volume or count amount, or a weight the edible
/// yield or a drained can scales; then the detail is fetched once and cached
/// — the only provider call. A 404 (superseded record) leaves the hit as
/// FDC's only record of the food, so it is cached as the food, as it always
/// was. A failed fetch fails the compute, a yield's or a drain's too: kept
/// at the printed weight, a bone-in pork chop was stored counted at 1.76×
/// its edible grams with the recipe's hash current, so no sweep fetched the
/// yield again (checkpoint 5 review). Failed, the recipe stays stale and
/// the next sweep retries it, as it does a failed search.
///
/// With [fetch] false (an engine pick below [lowConfidence], likely a wrong
/// food: audit 4 found 8 of 10 such fetches served one) nothing is asked:
/// the grams are what the hit gives, resolved in full when a person confirms.
/// Every caller passes the cached detail when there is one ([knownFood], the
/// engine's pick), so a hit here has none.
Future<(FdcFood, GramResolution?)> gramsFor(
  SaltDatabase db,
  NutritionProvider provider,
  FdcFood food,
  IngredientLine line, {
  bool fetch = true,
}) async {
  GramResolution? resolve(FdcFood on) => lineGrams(db, line, on);
  final resolution = resolve(food);
  final portions = _needsPortions(line.amounts, resolution);
  if (!fetch ||
      (!portions && !_weightReadsPortions(line.raw, food, resolution))) {
    return (food, resolution);
  }
  final detail = await _cachedFood(db, provider, food.fdcId);
  if (detail == null) {
    db.fdcFoodCachePut(food.fdcId, jsonEncode(food.toJson()));
    return (food, resolution);
  }
  final withDetail = resolve(detail);
  // A volume the record cannot size is read from its SR sibling
  // ([lineGrams]): its detail is fetched once, like the food's own.
  final sibling = volumeSiblings[detail.fdcId];
  if (withDetail == null &&
      sibling != null &&
      _foodFromCache(db, sibling) == null &&
      volumeMlOf(line.amounts) != null) {
    await _cachedFood(db, provider, sibling);
    return (detail, resolve(detail));
  }
  return (detail, withDetail);
}

/// [line]'s grams on [food] ([resolveGrams] on the line's own words) — and,
/// when that finds none for a volume line on a record in [volumeSiblings],
/// the same amounts on the sibling's cached portions (no request; the
/// basis names the sibling). The food stays [food].
GramResolution? lineGrams(
  SaltDatabase db,
  IngredientLine line,
  FdcFood? food,
) {
  // The grams tables match on the line's own words, not the key.
  final normalized = normalizeItem(lineItemOf(line));
  GramResolution? on(FdcFood? record) => resolveGrams(
    amounts: line.amounts,
    food: record,
    normalizedItem: normalized,
    raw: line.raw,
  );
  final own = on(food);
  final siblingId = food == null ? null : volumeSiblings[food.fdcId];
  if (own != null || siblingId == null || volumeMlOf(line.amounts) == null) {
    return own;
  }
  final sibling = _foodFromCache(db, siblingId);
  final grams = sibling == null ? null : on(sibling);
  return grams == null
      ? null
      : GramResolution(
          grams: grams.grams,
          source: grams.source,
          basis: '${grams.basis} of "${sibling!.description}"',
        );
}

/// The review bucket of [row] (salt_shared's one rule).
MatchBucket _bucketOf(IngredientMatchRow row) => matchBucketFor(
  status: row.status,
  fdcId: row.fdcId,
  grams: row.grams,
  confidence: row.confidence,
  hold: row.hold,
  gramSource: row.gramSource,
);

/// A person's call on a row: anything but the engine's own `auto` and
/// `unmatched`.
bool _isDecided(IngredientMatchRow row) =>
    row.status != 'auto' && row.status != 'unmatched';

/// Recomputes the stored per-serving totals from the persisted matches —
/// instant (food details come from the cache; no searches). [standIns] are
/// the foods a fresh match built from search hits (never cached); a later
/// recompute reads a food no cache row holds from the line's cached search
/// hit, and asks FDC only when neither holds it — so a serving-basis change
/// or a decision still recomputes with no key set or the hourly budget
/// spent (the normal state while a bulk sweep runs).
Future<void> recomputeTotals(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe, {
  int? servingBasis,
  bool freshMatch = false,
  Map<int, FdcFood> standIns = const {},
}) async {
  final lines = nutritionLines(recipe);
  // Rows beyond the current line count are orphans from an edit — they
  // must not contribute (matchAndCompute deletes them; a recompute
  // between the edit and the next full match must ignore them).
  final matches = db
      .ingredientMatchesFor(recipe.id)
      .where((row) => row.position < lines.length)
      .toList();
  final stored = db.nutritionFor(recipe.id);
  // Servings first; then the recipe's YIELD count as an editable default so
  // 'MAKES ABOUT 16 LARGE COOKIES' still lands per-cookie rather than
  // reporting one 16-cookie batch as a serving. A yield is not a serving
  // count (that is why it never reaches Recipe.serves) — it is only a
  // better starting basis than the whole batch, and the admin can override.
  var basis =
      servingBasis ??
      stored?.servingBasis ??
      recipe.serves?.min ??
      parseYieldCount(recipe.servings)?.min ??
      1;
  if (basis < 1) {
    basis = 1; // Hand-edited YAML can carry serves 0.
  }

  final totals = <String, double>{};
  var totalGrams = 0.0;
  var contributing = 0;
  var accounted = 0;
  for (final row in matches) {
    if (row.status == 'skipped') {
      accounted += 1;
      continue;
    }
    if (row.fdcId == null) {
      // Water-like confirmed rows count as fully accounted zeros.
      if (row.status == 'confirmed') {
        accounted += 1;
        contributing += 1;
      }
      continue;
    }
    final grams = row.grams;
    if (grams == null) {
      continue;
    }
    // A discarded medium (frying oil, a brine) or a line with no amount is
    // the engine's resolved 0 g, whatever its score or hold (the same
    // precedence as matchBucketFor): the line is accounted and adds nothing.
    // A line that names no food is held: its 0 g may drop a real amount.
    // The eaten part of a "plus" medium ("1 cup plus 2 teaspoons table salt",
    // the 2 teaspoons rubbed on the pork) counts like any line.
    final engineZero =
        grams <= 0 &&
        row.hold != 'unnamed_food' &&
        (row.gramSource == GramSource.discarded.name ||
            row.gramSource == GramSource.unmeasured.name);
    // Held for review: a low-confidence auto match is likely the WRONG food,
    // so it stays out of the totals — a bad match must never silently feed the
    // label. It still surfaces in the review sheet ("check match"); confirming
    // or re-picking it (status leaves 'auto') opts it back in. The recipe also
    // stays "partial" until then, since the line is not yet accounted. A
    // [IngredientMatchRow.hold] reason holds a row the same way.
    if (!engineZero &&
        row.status == 'auto' &&
        (belowConfidenceGate(row.confidence) || row.hold != null)) {
      continue;
    }
    if (grams <= 0) {
      if (engineZero) {
        accounted += 1;
        contributing += 1;
      }
      continue;
    }
    final own =
        standIns[row.fdcId] ??
        knownFood(db, row.fdcId!, line: lines[row.position]) ??
        await _cachedFood(db, provider, row.fdcId!);
    final sibling = nutrientSiblings[row.fdcId];
    final food = sibling == null || own == null
        ? own
        : standIns[sibling] ??
              knownFood(db, sibling) ??
              await _cachedFood(db, provider, sibling);
    if (food == null) {
      continue;
    }
    accounted += 1;
    contributing += 1;
    totalGrams += grams;
    for (final def in nutrientDefs) {
      for (final number in def.fdcNumbers) {
        final per100 = food.nutrientsPer100g[number];
        if (per100 != null) {
          totals[def.key] = (totals[def.key] ?? 0) + per100 * grams / 100;
          break;
        }
      }
    }
    // A record without any published energy still contributes calories
    // via the standard Atwater 4/9/4 factors ([kcalPer100g]) — FDC's own
    // computed-energy fields do the same math.
    final hasEnergy = nutrientDefs.first.fdcNumbers.any(
      food.nutrientsPer100g.containsKey,
    );
    if (!hasEnergy) {
      totals['energy'] =
          (totals['energy'] ?? 0) + kcalPer100g(food) * grams / 100;
    }
  }

  final perServing = <String, Map<String, Object?>>{};
  for (final def in nutrientDefs) {
    final total = totals[def.key];
    if (total == null) {
      continue;
    }
    final amount = total / basis;
    perServing[def.key] = {
      'label': def.label,
      'amount': double.parse(amount.toStringAsFixed(2)),
      'unit': def.unit,
      if (def.dailyValue != null)
        'dv_percent': double.parse(
          (amount / def.dailyValue! * 100).toStringAsFixed(1),
        ),
    };
  }

  final calories = perServing['energy']?['amount'] as double?;
  final status = accounted >= lines.length ? 'complete' : 'partial';
  // Only a full re-match may stamp the current recipe's hash — a plain
  // recompute (serving basis, match override) after an ingredient edit
  // must keep reporting `stale` until the admin recomputes for real.
  final hash = freshMatch
      ? ingredientsHashOf(recipe)
      : (stored?.ingredientsHash ?? ingredientsHashOf(recipe));
  db.upsertRecipeNutrition(
    recipeId: recipe.id,
    servingBasis: basis,
    caloriesPerServing: calories,
    nutrientsJson: jsonEncode(perServing),
    totalGrams: double.parse(totalGrams.toStringAsFixed(1)),
    matchedCount: contributing > lines.length ? lines.length : contributing,
    totalCount: lines.length,
    status: status,
    ingredientsHash: hash,
  );
  _log.info(
    'Nutrition for ${recipe.id}: $status, '
    '$contributing/${lines.length} lines, '
    '${calories?.toStringAsFixed(0) ?? '?'} kcal/serving (basis $basis)',
  );
}

/// What [basis] divides a recipe's totals by: `per_batch` when it is 1 —
/// the whole batch ("MAKES 1 LOAF", no servings at all, or an admin's 1) —
/// unless the recipe's [servings] yield is ONE single portion
/// ([singlePortionYields]: "MAKES 1 OMELET", "MAKES 1 COCKTAIL", "MAKES 1 TO
/// 16 EGGS"; never "MAKES 12 SANDWICHES"), whose one is a real serving
/// (the user's ruling, 2026-09-28).
/// Any larger basis divides the batch: by a serves count, or by a MAKES
/// yield count ([recomputeTotals]), where a "serving" is one of the yield —
/// one of "MAKES TWO 9-INCH PIZZAS", not the batch (refix round 1: the first
/// rule, basis 2 or less with no serves count, labelled 29 such basis-2
/// recipes per batch). `per_serving` otherwise.
String basisKindOf(int basis, {String? servings}) =>
    basis == 1 && !_singlePortionYield(servings) ? 'per_batch' : 'per_serving';

/// Yield nouns that are one portion, not a batch: the ruling's list, which
/// covers every single-portion noun the corpus's MAKES-1 yields show
/// (snapshot 11, 28 recipes at a basis of 1: COCKTAIL, OMELET and "1 TO 16
/// EGGS"; the rest are loaves, quarts, pies, tarts, crusts, a square and a
/// quarter cup of dressing — batches).
const Set<String> singlePortionYields = {
  'omelet',
  'cocktail',
  'sandwich',
  'egg',
  'drink',
};

/// Whether the yield of [servings] — up to its first comma or semicolon, so
/// "MAKES ABOUT 2 CUPS, ENOUGH FOR 4 SANDWICHES" is cups — is ONE portion:
/// its count is 1 ("1", "one"; "MAKES 1 TO 16 EGGS" starts at one) and its
/// head noun, the clause's last word, is a [singlePortionYields] noun,
/// singular or plural. "MAKES 12 SANDWICHES" is a batch of twelve (an
/// admin's 1 then divides by nothing), and "MAKES 32 SANDWICH COOKIES" is
/// cookies (refix round 2).
bool _singlePortionYield(String? servings) {
  final clause = (servings ?? '').split(RegExp('[,;]')).first.toLowerCase();
  final count = RegExp(r'\d+|\bone\b').firstMatch(clause)?[0];
  final head = RegExp('[a-z]+').allMatches(clause).lastOrNull?[0];
  if ((count != '1' && count != 'one') || head == null) {
    return false;
  }
  return singlePortionYields.contains(head) ||
      (head.endsWith('s') &&
          singlePortionYields.contains(head.substring(0, head.length - 1))) ||
      (head.endsWith('es') &&
          singlePortionYields.contains(head.substring(0, head.length - 2)));
}

/// Re-ranked candidates for one line. With [cacheOnly] (the GET path —
/// any authenticated user) the search cache is the sole source: a read
/// must never spend the FDC request budget or block on the rate limiter.
Future<List<RankedCandidate>> candidatesForLine(
  SaltDatabase db,
  NutritionProvider provider,
  IngredientLine line, {
  bool cacheOnly = false,
}) async {
  final normalized = normalizeItem(lineItemOf(line));
  if (normalized.isEmpty || isWaterLike(normalized) || isNonFood(normalized)) {
    return const [];
  }
  final search = lineSearchFor(
    db,
    normalized,
    lineKeyOf(line),
  );
  final List<FdcCandidate> candidates;
  if (cacheOnly) {
    final cached = db.fdcSearchCacheGet(search.answer);
    if (cached == null) {
      return const [];
    }
    candidates = [
      for (final entry in jsonDecode(cached) as List<dynamic>)
        FdcCandidate.fromJson(entry as Map<String, dynamic>),
    ];
  } else {
    candidates = await _cachedSearch(db, provider, search.answer);
  }
  return rankCandidates(
    search.query,
    candidates,
    canned: namesCannedLegume(line.raw, normalized),
    skinOn: impliesSkinOn(line.raw, normalized),
    skinless: removesSkin(line.raw),
  ).take(8).toList();
}

/// Ranked candidates for an ADMIN-SUPPLIED search term — the review sheet's
/// manual re-pick, for when none of the auto-found candidates fit (the
/// matcher searched the wrong words, e.g. "minced oregano" -> ham).
///
/// Unlike [candidatesForLine]'s cache-only GET path this MAY spend the FDC
/// request budget on a cache miss, which is why its route is admin-only. The
/// term is normalized so it shares the matcher's cache keys and ranking.
Future<List<RankedCandidate>> searchCandidates(
  SaltDatabase db,
  NutritionProvider provider,
  String query, {
  bool fresh = false,
}) async {
  final normalized = normalizeItem(query);
  if (normalized.isEmpty) {
    return const [];
  }
  final rewritten = searchQueryFor(normalized);
  final candidates = await _cachedSearch(db, provider, rewritten, fresh: fresh);
  return rankCandidates(rewritten, candidates).take(8).toList();
}

/// A short, human-readable description of what the stored grams were computed
/// against — e.g. "½ cup ≈ 118 mL" for a density estimate, "8¾ ounces" for a
/// direct weight — so a reviewer can sanity-check a volume/piece estimate.
///
/// Cache-only (the food comes from the local cache, never a fresh FDC call),
/// so it is safe on the member-callable matches GET. Null when the line has no
/// amount, or when the grams were entered by hand. Re-derived rather than
/// stored; deterministic, so it matches the stored grams for the common case.
///
/// A food that is a flagged approximation ([isApproximation]) says so after
/// the basis: "4 ounces · approximation (counted as Pork, cured, bacon,
/// unprepared)".
String? gramBasisFor(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row,
) {
  final basis = _gramBasis(db, line, row);
  final approximation =
      basis != null &&
      isApproximation(
        item: normalizeItem(lineItemOf(line)),
        raw: line.raw,
        fdcId: row.fdcId,
        description: row.description,
      );
  return approximation
      ? '$basis · approximation (counted as ${row.description})'
      : basis;
}

String? _gramBasis(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row,
) {
  if (row.grams == null) {
    return null;
  }
  final fdcId = row.fdcId;
  // A record whose nutrients are a sibling's says so ([nutrientSiblings]),
  // whoever gave the grams: the totals read the sibling's for a hand-entered
  // weight too (v11, Opus critic).
  final sibling = fdcId == null ? null : nutrientSiblings[fdcId];
  final nutrientsOf = sibling == null
      ? ''
      : ' · nutrients of "${knownFood(db, sibling)?.description ?? sibling}"';
  if (row.gramSource == 'override') {
    return 'entered by hand$nutrientsOf';
  }
  if (row.gramSource == GramSource.discarded.name) {
    final plus = plusPartOf(line.raw);
    return row.grams! <= 0
        ? 'discarded in cooking — counted as 0 g'
        : plus != null
        ? 'discarded in cooking — only "plus ${plus.text}" counted'
        : 'discarded in cooking — only the part the recipe keeps counted';
  }
  if (row.gramSource == GramSource.unmeasured.name &&
      row.fdcId == null &&
      isSubRecipeReference(line.raw)) {
    return 'a sub-recipe — counted as 0 g';
  }
  if (row.gramSource == GramSource.unmeasured.name && line.amounts.isEmpty) {
    return 'no amount on the line — counted as 0 g';
  }
  // The food's cached detail, else its cached search hit — as the engine
  // resolved the grams on: with neither, a counted bone-in line read a plain
  // "from 4 pound", its approximate label lost for want of a detail no
  // compute fetches for a Foundation or FNDDS weight line (v11, Opus:
  // braised oxtails, 2705843).
  final food = fdcId == null ? null : knownFood(db, fdcId, line: line);
  final rule = secondFoodRuleOf(line);
  if (rule != null && rule.fdcId == fdcId) {
    final byRule = rule.gramsOn(food);
    if (byRule != null && (byRule.grams - row.grams!).abs() <= 0.05) {
      return byRule.basis;
    }
  }
  GramResolution? on(FdcFood? food) {
    final grams = lineGrams(db, line, food);
    return grams == null || nutrientsOf.isEmpty
        ? grams
        : GramResolution(
            grams: grams.grams,
            source: grams.source,
            basis: '${grams.basis ?? ''}$nutrientsOf',
          );
  }

  final now = on(food);
  // Stored grams resolved on a search hit (no portions) before the detail
  // was cached: the basis is the hit's, never a yield or a portion the
  // stored grams never had.
  if (food != null && now != null && (now.grams - row.grams!).abs() > 0.05) {
    final hit = on(
      FdcFood(
        fdcId: food.fdcId,
        description: food.description,
        dataType: food.dataType,
        nutrientsPer100g: food.nutrientsPer100g,
        portions: const [],
      ),
    );
    if (hit != null && (hit.grams - row.grams!).abs() <= 0.05) {
      return hit.basis;
    }
  }
  return now?.basis;
}

Future<List<FdcCandidate>> _cachedSearch(
  SaltDatabase db,
  NutritionProvider provider,
  String query, {
  bool fresh = false,
}) async {
  // [fresh]: a person asked for a live answer — skip the cache and replace
  // the stored row, so the next compute sees the newer answer too.
  final cached = fresh ? null : db.fdcSearchCacheGet(query);
  if (cached != null) {
    return [
      for (final entry in jsonDecode(cached) as List<dynamic>)
        FdcCandidate.fromJson(entry as Map<String, dynamic>),
    ];
  }
  final results = await provider.search(query);
  // A live answer with NO hits must not evict a stored one that had some:
  // the cache never expires and an empty row is a hit, so one no-hits reply
  // would blank every line with this item — and the compute path — for
  // good. (A provider error already throws before this write; this is the
  // 200-with-no-foods case.) The caller still gets the live answer.
  if (fresh && results.isEmpty) {
    final stored = db.fdcSearchCacheGet(query);
    if (stored != null && stored != '[]') {
      return results;
    }
  }
  db.fdcSearchCachePut(
    query,
    jsonEncode([for (final candidate in results) candidate.toJson()]),
  );
  return results;
}

/// Which cached search answers a line, and the words that rank it: `query`
/// ranks the candidates; `answer` is the fdc_search_cache row that holds them
/// — and, when it holds nothing yet, the words FDC is asked. They differ in
/// one case: a line whose own words were never searched reads the answer
/// stored under its KEY's words ("pork tenderloins" reads "pork tenderloin":
/// 56 of 56 such cached pairs ranked the same top food, sweep audit
/// 2026-09-26), still ranked under its own words. An "A or B" line whose A is
/// a known query searches A alone ([leftAlternative]).
({String query, String answer}) lineSearchFor(
  SaltDatabase db,
  String normalized,
  String key,
) {
  // An EMPTY stored answer is FDC saying it has no food for A ("pancetta"):
  // not a known query — the whole phrase still gets searched. (A test that
  // A's answer names A was here too; with the relative guard below it
  // changed no line of the library, audit 4 P4/P9. 'dry vermouth', whose
  // junk answer once split "dry vermouth or dry white wine", is a stand-in.)
  final left = leftAlternative(normalized, (query) {
    final answer = db.fdcSearchCacheGet(query);
    return answer != null && answer != '[]';
  });
  final query = searchQueryFor(normalized);
  final sibling = searchQueryFor(key);
  // A rewritten line never reads its key's answer: for "red pepper flakes"
  // the key 'red pepper flake' is the raw phrase the rewrite exists to avoid
  // (FDC answers it with bell peppers).
  final whole =
      query == normalized &&
          sibling != query &&
          db.fdcSearchCacheEntry(query) == null &&
          db.fdcSearchCacheEntry(sibling) != null
      ? (query: query, answer: sibling)
      : (query: query, answer: query);
  if (left == null) {
    return whole;
  }
  // The relative guard: A replaces the whole phrase only when it ranks at
  // least as well — the naming test alone kept 6 of the 12 splits that lost
  // (5 vermouth, 2 vinegars, kosher salt, lemon wedges; audit 3). With no
  // stored answer for the phrase, A must itself pass the review gate, or
  // the phrase is searched. A rewrite target not yet asked stands.
  final split = searchQueryFor(left);
  final topSplit = _topCachedConfidence(db, split, split);
  if (topSplit == null) {
    return (query: split, answer: split);
  }
  final topWhole = _topCachedConfidence(db, whole.query, whole.answer);
  return topSplit >= (topWhole ?? confidenceGateFloor)
      ? (query: split, answer: split)
      : whole;
}

/// The top confidence of the stored answer [answer] ranked under [query];
/// null when no answer is stored.
double? _topCachedConfidence(SaltDatabase db, String query, String answer) {
  final stored = db.fdcSearchCacheGet(answer);
  if (stored == null) {
    return null;
  }
  final ranked = rankCandidates(query, [
    for (final entry in jsonDecode(stored) as List<dynamic>)
      FdcCandidate.fromJson(entry as Map<String, dynamic>),
  ]);
  return ranked.isEmpty ? 0 : ranked.first.confidence;
}

/// Food detail from the cache alone; null when it holds none.
FdcFood? _foodFromCache(SaltDatabase db, int fdcId) {
  final cached = db.fdcFoodCacheGet(fdcId);
  return cached == null
      ? null
      : FdcFood.fromJson(jsonDecode(cached) as Map<String, dynamic>);
}

/// The calories 100 g of [food] counts, as the totals count them: its first
/// published energy (208, then the Atwater 957/958), else 4/9/4 from its
/// protein, fat and carbohydrate — what the fix sheet shows beside a match
/// with no amount yet ("80 kcal per 100 g"), and what the totals add for a
/// record with no energy. Fat as the nutrient sum reads it (nutrients.dart:
/// 204, else NLEA 298): Foundation "Oil, olive, extra virgin" (748608)
/// publishes its fat only as 298 and no energy, and counted 0 kcal on 144
/// sweep lines.
double kcalPer100g(FdcFood food) {
  final n = food.nutrientsPer100g;
  for (final number in nutrientDefs.first.fdcNumbers) {
    final kcal = n[number];
    if (kcal != null) {
      return kcal;
    }
  }
  return 4 * (n['203'] ?? 0) +
      9 * (n['204'] ?? n['298'] ?? 0) +
      4 * (n['205'] ?? 0);
}

/// A food with NO provider call: the detail in fdc_food_cache, else the
/// search hit a lazy compute stood in with (or FDC's only record of a
/// superseded, 404 food) — read from [line]'s cached answer when given, and
/// else from any cached answer that holds it. The fallback matters: which
/// answer a line reads depends on what is cached NOW ([lineSearchFor]), not
/// on what was cached when the row was matched, and a food decided on one
/// line is recomputed on others. A hit is never cached as the food: a
/// portion-less row in fdc_food_cache would starve every later volume line
/// of its portions. Null when no cache holds it.
FdcFood? knownFood(SaltDatabase db, int fdcId, {IngredientLine? line}) {
  final cached = _foodFromCache(db, fdcId);
  if (cached != null) {
    return cached;
  }
  final own = line == null
      ? null
      : db.fdcSearchCacheGet(
          lineSearchFor(
            db,
            normalizeItem(lineItemOf(line)),
            lineKeyOf(line),
          ).answer,
        );
  FdcFood? hitIn(String answer) {
    for (final entry in jsonDecode(answer) as List<dynamic>) {
      final hit = FdcCandidate.fromJson(entry as Map<String, dynamic>);
      if (hit.fdcId == fdcId && (hit.nutrientsPer100g?.isNotEmpty ?? false)) {
        return hit.toFood();
      }
    }
    return null;
  }

  // The own answer first: the other answers are an unindexed scan of the
  // whole search cache, paid only when the line's own answer lacks the food.
  final fromOwn = own == null ? null : hitIn(own);
  if (fromOwn != null) {
    return fromOwn;
  }
  for (final answer in db.fdcSearchCacheHolding(fdcId)) {
    final food = hitIn(answer);
    if (food != null) {
      return food;
    }
  }
  return null;
}

/// A decided food for [line] with no search: [knownFood] (cache only), else
/// the detail from FDC. A superseded food whose detail 404s is known only
/// from a cached hit, so asking FDC first would drop the decision.
Future<FdcFood?> _decidedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
  IngredientLine line,
) async =>
    knownFood(db, fdcId, line: line) ?? await _cachedFood(db, provider, fdcId);

/// Food detail through the cache; null when FDC has no such id.
Future<FdcFood?> _cachedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) async {
  final cached = db.fdcFoodCacheGet(fdcId);
  if (cached != null) {
    return FdcFood.fromJson(jsonDecode(cached) as Map<String, dynamic>);
  }
  final food = await provider.food(fdcId);
  if (food != null) {
    db.fdcFoodCachePut(fdcId, jsonEncode(food.toJson()));
  }
  return food;
}

/// Public cache-aware food lookup (the match-override endpoint needs it).
Future<FdcFood?> cachedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) => _cachedFood(db, provider, fdcId);

/// The rows a decision on [itemKey] made on the line [excluding] lands on
/// — what `others` / `others_lines` count and exactly what
/// [applyDecisionToOthers] writes: [SaltDatabase.undecidedMatchesForItemKey]
/// (a different food at any score, [fdcId] only below [lowConfidence] or
/// held by a food hold, never a line-held row; with no [fdcId] every
/// undecided row) less every row a line hold would hold once it took the
/// food: a line that names a second food ([namesSecondFood]) — its rule
/// counts it on its own record, or it is held `second_food` whatever food
/// the key gives it — shellfish bought in the shell ([boughtInShell], held
/// `in_shell` on any food), and an unmatched line that is a held discarded
/// medium (an unmatched brine sugar). No decision on the key moves either
/// (checkpoint 5 review: the offer counted 43 rule rows and the apply
/// landed 0; an unmatched second-food line was reported applied).
List<IngredientMatchRow> decisionReach(
  SaltDatabase db,
  String itemKey, {
  required ({String recipeId, int position}) excluding,
  int? fdcId,
}) => [
  for (final row in db.undecidedMatchesForItemKey(
    itemKey,
    excluding: excluding,
    fdcId: fdcId,
    belowConfidence: confidenceGateFloor,
  ))
    if (!namesSecondFood(row.raw) &&
        !boughtInShell(row.raw) &&
        !_heldMediumOnceMatched(db, row))
      row,
];

/// Whether the unmatched [row] is a discarded medium the engine would hold
/// (`discarded_medium`) once it had a food. A matched one already carries
/// the hold; only an unmatched row (rare: 51 in the library) reads its
/// recipe here.
bool _heldMediumOnceMatched(SaltDatabase db, IngredientMatchRow row) {
  if (row.fdcId != null) {
    return false;
  }
  final recipe = db.recipeByIdOrSlug(row.recipeId)?.recipe;
  final lines = recipe == null
      ? const <IngredientLine>[]
      : nutritionLines(recipe);
  if (row.position >= lines.length || lines[row.position].raw != row.raw) {
    return false;
  }
  final line = lines[row.position];
  final medium = discardedMediumOf(
    recipe!,
    line,
    normalizeItem(lineItemOf(line)),
  );
  return medium != null &&
      !(medium.followsPolicy &&
          discardedMediaPolicy == DiscardedMediaPolicy.zero);
}

/// Lands [decided] — a person's decision on [itemKey] made on the line
/// [excluding] — on every other undecided line with that item (other
/// recipes, and the same recipe's other lines), each with grams from its own
/// amounts, then recomputes those recipes' totals.
///
/// A line already on that food is a target only while its score is below
/// [lowConfidence] — the flagged threshold: rewritten at confidence 1 it
/// leaves the `check` bucket, which is what a confirm on a group whose
/// siblings share the engine's pick is for. A sibling already on that food
/// at or above the threshold is counted (or short only an amount) and is
/// skipped: it waits on nothing this decision can give it.
///
/// The rows are written as `auto` at confidence 1 — machine propagation of
/// a human decision, exactly like inheritance at compute time — NOT as a
/// human status: a status of `overridden` would shield them from every
/// later propagation, so a wrong pick applied to 456 recipes could never be
/// corrected in bulk. As `auto` rows they are reached again by a corrective
/// apply-to-all and re-inherited from the newest decision at the next
/// sweep, while a decision a person makes on any of them still stands.
///
/// A decision already made on a target line stands: the write is guarded
/// at the statement, and a guarded-out write is not counted. A row whose
/// recipe no longer has that line, or whose text changed, is left for the
/// next compute. A recipe that fails — its document will not decode, or the
/// provider fails while its totals recompute — is logged, counted in
/// `failed`, and does not stop the rest; what was already written stays,
/// and the counts say exactly what landed: `lines` counts the rows whose
/// review bucket changed or that took the decided food — the rows
/// [decisionReach] offered, less those skipped or guarded out — `recipes`
/// the recipes holding one, and `completed` those of them whose stored
/// status turned `complete` with this apply (what the queue's `finishes`
/// promised; the receipt reconciles against it), `completedRecipes` their
/// ids. A reached recipe that was complete already (a different-food pick
/// reaches counted lines) is not counted: it was finished before.
Future<
  ({
    int recipes,
    int lines,
    int failed,
    int completed,
    List<String> completedRecipes,
  })
>
applyDecisionToOthers(
  SaltDatabase db,
  NutritionProvider provider, {
  required String itemKey,
  required FdcFood decided,
  required ({String recipeId, int position}) excluding,
}) async {
  var food = decided;
  final byRecipe = <String, List<IngredientMatchRow>>{};
  for (final target in decisionReach(
    db,
    itemKey,
    excluding: excluding,
    fdcId: food.fdcId,
  )) {
    byRecipe.putIfAbsent(target.recipeId, () => []).add(target);
  }
  var recipes = 0;
  var lines = 0;
  var failed = 0;
  final completed = <String>[];
  for (final entry in byRecipe.entries) {
    try {
      final found = db.recipeByIdOrSlug(entry.key);
      if (found == null) {
        continue; // Deleted meanwhile; its rows cascaded away.
      }
      final recipeLines = nutritionLines(found.recipe);
      var applied = 0;
      for (final target in entry.value) {
        if (target.position >= recipeLines.length) {
          continue;
        }
        final line = recipeLines[target.position];
        if (line.raw != target.raw) {
          continue; // The line changed since that row was written.
        }
        // A search hit stands in until a target needs portions; then the
        // detail is fetched once and serves every later target.
        final GramResolution? resolution;
        (food, resolution) = await gramsFor(db, provider, food, line);
        final outcome = engineOutcome(
          found.recipe,
          line,
          food,
          resolution,
          decided: true,
        );
        final row = IngredientMatchRow(
          recipeId: found.recipe.id,
          position: target.position,
          raw: line.raw,
          itemKey: itemKey,
          fdcId: food.fdcId,
          description: food.description,
          dataType: food.dataType,
          confidence: 1,
          grams: outcome.grams,
          gramSource: outcome.source,
          status: 'auto',
          hold: outcome.hold,
        );
        if (!db.upsertIngredientMatchIfUndecided(row)) {
          continue;
        }
        // Applied = the row's bucket changed, or it took the decided food —
        // a line left short of an amount on it too ("2 (2-inch) strips lemon
        // zest" stays no_grams on "Lemon, raw"): the offer counted it, and
        // the decision reached it (checkpoint 5 review). A row a line hold
        // would re-hold is not reached at all ([decisionReach]).
        if (_bucketOf(row) != _bucketOf(target) || target.fdcId != food.fdcId) {
          applied += 1;
        }
      }
      // A write that moved no bucket and no counted food moved no total.
      if (applied == 0) {
        continue;
      }
      final before = db.nutritionFor(found.recipe.id)?.status;
      await recomputeTotals(db, provider, found.recipe);
      recipes += 1;
      lines += applied;
      if (before != 'complete' &&
          db.nutritionFor(found.recipe.id)?.status == 'complete') {
        completed.add(found.recipe.id);
      }
      // A recipe that will not decode, or whose totals cannot recompute
      // (the provider failed), must not stop the rest — and must be counted.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      failed += 1;
      _log.warning('apply-to-all failed for ${entry.key}: $error');
    }
  }
  return (
    recipes: recipes,
    lines: lines,
    failed: failed,
    completed: completed.length,
    completedRecipes: completed,
  );
}
