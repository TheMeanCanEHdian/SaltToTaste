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

/// Confidence below which an auto match is reported as needs-review.
const double lowConfidence = 0.5;

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

  /// Brine sugar ("for brining", or ¼ cup or more a step brines in): always
  /// review — how much a brine's sugar leaves on the meat nothing says
  /// (audit 3: 16 lines, 2,400 g; 22 with the brines whose salt is not a
  /// counted line).
  brineSugar,

  /// ¼ cup or more of salt no step brines in or rubs on: a salt bed, an ice
  /// bath, a dunk (Salt-Baked Potatoes, a gelato's ice bath). Always review.
  saltBath,

  /// A soak: "for soaking", or 4+ cups of buttermilk a step brines or soaks
  /// in.
  soak,

  /// Milk made into cheese (4+ cups, a whey or curds step): only the curds
  /// are eaten, in an amount nothing on the line says — always review.
  cheeseMilk;

  /// Whether [discardedMediaPolicy] decides how it counts; the others are
  /// always held for a person.
  bool get followsPolicy => this == fryingOil || this == brine || this == soak;
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

/// Every step text of [recipe], subsections included.
List<String> _stepsOf(Recipe recipe) => [
  for (final step in recipe.steps) step.text,
  for (final subsection in recipe.subsections)
    for (final step in subsection.steps ?? const <RecipeStep>[]) step.text,
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
  return null;
}

/// What an ENGINE write stores for [line] of [recipe] on [food]: the grams
/// and their source, and why the row is held out of the totals (null when
/// nothing holds it). [picked] is true when the engine chose the food from a
/// search (a person's food is never held for publishing nothing). [decided]
/// is true when the food is a person's decision on the line's key (inherited
/// or applied to all): the decision supersedes every engine reason but a
/// discarded medium, which a key-wide decision never saw.
({double? grams, String? source, String? hold}) engineOutcome(
  Recipe recipe,
  IngredientLine line,
  FdcFood food,
  GramResolution? resolution, {
  bool picked = false,
  bool decided = false,
  double? confidence,
}) {
  final normalized = normalizeItem(lineItemOf(line));
  final medium = discardedMediumOf(
    recipe,
    line,
    normalized,
    grams: resolution?.grams,
  );
  if (medium != null &&
      medium.followsPolicy &&
      discardedMediaPolicy == DiscardedMediaPolicy.zero) {
    // Only the first part of a "plus" line is the medium when a step eats
    // the second ([_eatenPlusPart]).
    final plus = _eatenPlusPart(recipe, line, headNounOf(normalized));
    final kept = plus == null
        ? null
        : resolveGrams(
            amounts: [plus.amount],
            food: food,
            normalizedItem: normalized,
          );
    return (
      grams: kept?.grams ?? 0,
      source: GramSource.discarded.name,
      hold: null,
    );
  }
  if (decided) {
    final zero = amountlessLinesZero && line.amounts.isEmpty;
    return (
      grams: zero ? 0 : resolution?.grams,
      source: zero ? GramSource.unmeasured.name : resolution?.source.name,
      hold: medium != null ? 'discarded_medium' : null,
    );
  }
  // A line that names no food goes to a person even when it has no amount
  // ("2 tablespoons juice", which the parser kept whole).
  final unnamed = picked && namesNoFood(line);
  if (amountlessLinesZero && line.amounts.isEmpty) {
    return (
      grams: 0,
      source: GramSource.unmeasured.name,
      hold: unnamed ? 'unnamed_food' : null,
    );
  }
  final plus = plusPartOf(line.raw);
  final hold = medium != null
      ? 'discarded_medium'
      : plus != null &&
            !plus.sameFood &&
            // A counted extra cut into wedges ("plus 1 lemon, cut into
            // wedges") is for serving, never in the dish, whichever fruit it
            // is. Other counted extras are eaten — lemon halves grilled and
            // squeezed into the dressing (0654), the whole egg in the batter
            // (0878) — so a person looks.
            !(plus.amount.measure == Measure.count &&
                RegExp(
                  r'\bplus\b.*\bwedges?\b',
                  caseSensitive: false,
                ).hasMatch(line.raw))
      // "2 teaspoons lemon zest plus 2 tablespoons juice": only the first
      // food was matched; counting it alone would drop the second silently.
      ? 'second_food'
      : picked && publishesNothing(food)
      ? 'no_nutrients'
      : unnamed
      ? 'unnamed_food'
      : picked &&
            !allowDriedForFresh &&
            driedForFresh(line.raw, food.description)
      ? 'dried_for_fresh'
      : picked && inBorderlineBand(confidence)
      ? 'borderline'
      : null;
  return (
    grams: resolution?.grams,
    source: resolution?.source.name,
    hold: hold,
  );
}

/// USER ANSWER SWITCH (queue keys, audit 3 N5). True (the recommended
/// default) keys a line that names a second food ("zest plus 2 tablespoons
/// juice", "eggs plus 2 yolks") apart from the first food's lines, so a
/// decision on 'lemon zest' never reaches the 64 lines whose mass is mostly
/// juice. False keeps them in the first food's group (still held
/// `second_food`, so none counts on the first amount alone).
const bool secondFoodOwnKey = true;

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
            (word.endsWith('ed') &&
                !word.endsWith('eed') &&
                !word.endsWith('ead')),
      );
}

final RegExp _citrusWord = RegExp(
  r'\b(lemon|lime|orange|grapefruit|tangerine)s?\b',
);

/// The item text the matcher normalizes, searches and keys [line] by: its
/// parsed item — unless that is a lone qualifier, which reads on to the
/// next comma ("short, curly pasta" → 'short curly pasta'; 'fine-ground,
/// whole-grain yellow cornmeal'), or bare 'juice', which takes its fruit
/// from the line ("6 tablespoons juice (2 lemons)" → 'lemon juice'; it
/// searched Beet juice). A rewrite key is left to its rewrite ('short',
/// 'dark').
String lineItemOf(IngredientLine line) {
  final item = line.item ?? line.raw;
  final normalized = normalizeItem(item);
  if (normalized == 'juice') {
    final fruit = _citrusWord.firstMatch(line.raw.toLowerCase());
    return fruit == null ? item : '${fruit[1]} juice';
  }
  if (!_namesNoFood(normalized) ||
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
      return extended;
    }
  }
  return item;
}

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
String decisionItemOf(IngredientLine line) {
  final item = lineItemOf(line);
  final plus = plusPartOf(line.raw);
  if (!secondFoodOwnKey ||
      plus == null ||
      plus.sameFood ||
      plusPartOf(item) != null) {
    return item;
  }
  return '$item plus ${plus.text}';
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
  // The second food less what the first already names: "zest plus 1
  // tablespoon juice from 1 lemon" is 'lemon zest plus juice', like "lemon
  // zest plus 2 tablespoons juice".
  final named = first.split(' ').toSet();
  final words = itemKeyFor(
    parseIngredientLine(plus.text).item ?? '',
  ).split(' ');
  final own = [
    for (final word in words)
      if (!named.contains(word)) word,
  ];
  final second = (own.isEmpty ? words : own).join(' ');
  return second.isEmpty ? first : '$first plus $second';
}

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
  // scores and picks frozen at the matcher that wrote them.
  final payload = jsonEncode({
    'matcher': matcherVersion,
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
          db.upsertIngredientMatchIfUndecided(
            edited.copyWith(
              position: position,
              raw: line.raw,
              itemKey: key,
              grams: resolution?.grams,
              clearGrams: resolution == null,
              gramSource: resolution?.source.name,
              clearGramSource: resolution == null,
            ),
          );
          continue;
        }
      }
    }
    final seasoning = line.amounts.isEmpty && isSeasoningToTaste(normalized);
    final equipment = isNonFood(normalized);
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
    // A pick below the review gate is likely a wrong food: no detail is
    // fetched for its grams until a person confirms it.
    final (gramsFood, resolution) = await gramsFor(
      db,
      provider,
      food!,
      line,
      fetch: best.confidence >= lowConfidence,
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
bool _weightReadsPortions(String raw, GramResolution? withoutPortions) =>
    withoutPortions?.source == GramSource.weight &&
    ((edibleYieldOn && buysRefuse(raw)) || (cannedDrained && drainsCan(raw)));

/// [line]'s grams on [food], and the food they were read from. A search hit
/// (no fdc_food_cache row) is enough unless the grams may need FDC's
/// household portions — a volume or count amount, or a weight the edible
/// yield or a drained can scales; then the detail is fetched once and cached
/// — the only provider call. A 404 (superseded record) leaves the hit as
/// FDC's only record of the food, so it is cached as the food, as it always
/// was. A failed fetch for a yield or a drain keeps the printed weight (its
/// basis says no yield was applied) instead of failing the line.
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
  GramResolution? resolve(FdcFood on) => resolveGrams(
    amounts: line.amounts,
    food: on,
    // The grams tables match on the line's own words, not the key.
    normalizedItem: normalizeItem(lineItemOf(line)),
    raw: line.raw,
  );
  final resolution = resolve(food);
  final portions = _needsPortions(line.amounts, resolution);
  if (!fetch || (!portions && !_weightReadsPortions(line.raw, resolution))) {
    return (food, resolution);
  }
  final FdcFood? detail;
  try {
    detail = await _cachedFood(db, provider, food.fdcId);
  } on NutritionProviderException catch (error) {
    if (portions) {
      rethrow;
    }
    _log.warning('No detail for ${food.fdcId} (yield/drain): $error');
    return (food, resolution);
  }
  if (detail == null) {
    db.fdcFoodCachePut(food.fdcId, jsonEncode(food.toJson()));
    return (food, resolution);
  }
  return (detail, resolve(detail));
}

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
        (row.confidence < lowConfidence || row.hold != null)) {
      continue;
    }
    if (grams <= 0) {
      if (engineZero) {
        accounted += 1;
        contributing += 1;
      }
      continue;
    }
    final food =
        standIns[row.fdcId] ??
        knownFood(db, row.fdcId!, line: lines[row.position]) ??
        await _cachedFood(db, provider, row.fdcId!);
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
    // via the standard Atwater 4/9/4 factors — FDC's own computed-energy
    // fields do the same math.
    final hasEnergy =
        food.nutrientsPer100g.containsKey('208') ||
        food.nutrientsPer100g.containsKey('957') ||
        food.nutrientsPer100g.containsKey('958');
    if (!hasEnergy) {
      final protein = food.nutrientsPer100g['203'] ?? 0;
      // Fat as the nutrient sum reads it (nutrients.dart: 204, else NLEA
      // 298): Foundation "Oil, olive, extra virgin" (748608) publishes its fat
      // only as 298 and no energy, and counted 0 kcal on 144 sweep lines.
      final fat =
          food.nutrientsPer100g['204'] ?? food.nutrientsPer100g['298'] ?? 0;
      final carbs = food.nutrientsPer100g['205'] ?? 0;
      totals['energy'] =
          (totals['energy'] ?? 0) +
          (4 * protein + 9 * fat + 4 * carbs) * grams / 100;
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
String? gramBasisFor(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row,
) {
  if (row.grams == null) {
    return null;
  }
  if (row.gramSource == 'override') {
    return 'entered by hand';
  }
  if (row.gramSource == GramSource.discarded.name) {
    final plus = plusPartOf(line.raw);
    return row.grams! > 0 && plus != null
        ? 'discarded in cooking — only "plus ${plus.text}" counted'
        : 'discarded in cooking — counted as 0 g';
  }
  if (row.gramSource == GramSource.unmeasured.name && line.amounts.isEmpty) {
    return 'no amount on the line — counted as 0 g';
  }
  FdcFood? food;
  final fdcId = row.fdcId;
  if (fdcId != null) {
    final cached = db.fdcFoodCacheGet(fdcId);
    if (cached != null) {
      food = FdcFood.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    }
  }
  GramResolution? on(FdcFood? food) => resolveGrams(
    amounts: line.amounts,
    food: food,
    normalizedItem: normalizeItem(lineItemOf(line)),
    raw: line.raw,
  );
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
  return topSplit >= (topWhole ?? lowConfidence)
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
/// and the counts say exactly what landed.
Future<({int recipes, int lines, int failed})> applyDecisionToOthers(
  SaltDatabase db,
  NutritionProvider provider, {
  required String itemKey,
  required FdcFood decided,
  required ({String recipeId, int position}) excluding,
}) async {
  var food = decided;
  final byRecipe = <String, List<IngredientMatchRow>>{};
  for (final target in db.undecidedMatchesForItemKey(
    itemKey,
    excluding: excluding,
    fdcId: food.fdcId,
    belowConfidence: lowConfidence,
  )) {
    byRecipe.putIfAbsent(target.recipeId, () => []).add(target);
  }
  var recipes = 0;
  var lines = 0;
  var failed = 0;
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
        final written = db.upsertIngredientMatchIfUndecided(
          IngredientMatchRow(
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
          ),
        );
        if (written) {
          applied += 1;
        }
      }
      if (applied == 0) {
        continue;
      }
      await recomputeTotals(db, provider, found.recipe);
      recipes += 1;
      lines += applied;
      // A recipe that will not decode, or whose totals cannot recompute
      // (the provider failed), must not stop the rest — and must be counted.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      failed += 1;
      _log.warning('apply-to-all failed for ${entry.key}: $error');
    }
  }
  return (recipes: recipes, lines: lines, failed: failed);
}
