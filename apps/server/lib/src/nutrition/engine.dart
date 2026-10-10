import 'dart:convert';
import 'dart:math' show max, min, pi;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
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
///
/// v49 (M47 Q15 iv, critic F14): Foundation 2758998 "Pasta, dry, enriched,
/// spaghetti" publishes minerals only (no energy, no macros) → SR 169736
/// "Pasta, dry, enriched" (371 kcal). v49 (M47 Q13): FNDDS's cooked-state
/// "Leeks" 2709935 (88 kcal, fat added) and "Rhubarb" 2709268 (73 kcal,
/// sugar-cooked) on raw lines → SR 169246 "Leeks, (bulb and lower
/// leaf-portion), raw" (61) and SR 167758 "Rhubarb, raw" (21), both details
/// cached by the M53 live step; the grams and the AH-102 leek yield stay
/// keyed on the line's own record.
const Map<int, int> nutrientSiblings = {
  2727583: 169979,
  2758998: 169736,
  2709935: 169246,
  2709268: 167758,
};

/// A cooking medium the recipe throws away, found from the line and the
/// recipe's steps (audit 1 rank 12, audit 2: 19 counted frying-oil lines of
/// 400 g or more, 26.6 kg; 25 brine-salt lines; 2 buttermilk soaks; 2 lines
/// of milk curdled into cheese whose whey is drained).
enum DiscardedMedium {
  /// Deep-frying oil: "for (deep-)frying", or 400 g or more of
  /// oil/shortening/lard whatever the steps say ("3 cups vegetable oil" for
  /// orange beef; Easier French Fries never says fry). Audit 3: 29 counted
  /// lines, 41,017 g — a 4-cup rule found 21.
  /// Read from the directions too ([_oilOwnersOf], RULE B): an oil of ¼
  /// cup or more a sentence it owns heats to a frying temperature,
  /// discards or pours off all but a part of, or the one such oil of a
  /// fried food's held dredge — a part poured off "all but" is kept and
  /// counted ([_keptFryingOil]); v53 (M52, Q3 a): plus the oil its fried
  /// food absorbs ([_m52Plan]); (Q24 b) an oil heated for a coated food
  /// browned in it ([_shallowFries]).
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
  /// bath, a dunk (Salt-Baked Potatoes, a gelato's ice bath) and the sugar
  /// dunked with it; salt tossed with a vegetable and rinsed off, and baking
  /// soda a food is rinsed of ([_rinsedSalt], R2); a dip the food drips
  /// back into, a pickle drained off ([_drainedAway]). Always review.
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
  cookingWater,

  /// A sourdough starter's feeding flour (the user's ruling Q1, 2026-10-01):
  /// every feeding keeps a little starter and discards the rest ("Measure
  /// out ¼ cup … starter …; discard remaining starter", Sourdough Starter,
  /// 0799, counted 9½ cups of flour), so how much of a line ends in the kept
  /// starter nothing says. Every non-water line ([_feedsStarter]). Held
  /// (`starter_discard`).
  starterDiscard,

  /// Flour, starch or crumbs a food is dredged in, the excess shaken off or
  /// left in the dish (the user's ruling Q2, 2026-10-01: Crispy Fried
  /// Chicken, 0148, counted 567 g of flour; since v33, the dredge-reach
  /// ruling, in any cooking class whose directions leave an excess) —
  /// [_dredge]. A batter the food is folded into is eaten whole and is not
  /// one. Held (`coating`); v53 (M52, Q2 a): the engine's row counts its
  /// share of a coat budget sized from the coated food ([_m52Plan]); since
  /// v67 (M69) a sautéed dusting of a thin piece (C4) and a coated eggplant
  /// baked after the coat (C2) count too — a thick piece's dusting, a fried
  /// coated eggplant, any other coated vegetable and a cheese crust stay held.
  coating,

  /// A line of a cooking liquid strained after the braise of which a step
  /// keeps only a written part ("Pour 1 cup defatted cooking liquid", the
  /// rest unused: Mahogany Chicken Thighs, 0129; the user's ruling Q4,
  /// 2026-10-01) — [keptLiquidOf]. Held (`partial_pour_away`); the kept
  /// part is the row's `hold_note`.
  partialPourAway,

  /// An oil of ¼ cup or more a frying, discard or pour-off sentence (or a
  /// fried food's dredge) could be about while another such oil line could
  /// too — no word of the sentence names which ([_oilOwnersOf], RULE B,
  /// Run 055 S2/O1: a typed aioli or dressing beside a fry was zeroed).
  /// Held (`ambiguous_medium`); the sentence is the row's `hold_note`.
  ambiguousMedium,

  /// v50 (Q16, D1): an aromatic, herb, whole spice or zest strip a step
  /// strains out with the solids ("Strain … pressing on the solids";
  /// "strain the broth"), and cured pork or ground stock meat strained out
  /// of a pot whose fat a sentence skims, separates or pours off (Q17, F4)
  /// — [_strainedOut]. Follows the policy: 0 g, flagged "approximate
  /// (strained out and discarded — what it gives the liquid is not
  /// counted)" (the owner's 2026-10-07 amendment of the 2026-09-28 "held"
  /// ruling, design_v2 Q16).
  strainedSolid,

  /// v50 (Q18, D2): a whole-piece aromatic a step removes and discards by
  /// name ("Remove and discard the bay leaves"; a celery bundle, onion
  /// halves, a garlic head, lemons from a cavity), only the discarded
  /// pieces of a count line ([_discardedShareOf], F12), and cured pork so
  /// discarded from a skimmed pot (Q17) — [_discardedByName]. Follows the
  /// policy: 0 g, "removed and discarded (step N)".
  removedAromatic,

  /// v50 (Q17; critic F4): cured pork or ground stock meat a step strains
  /// out or discards while no sentence skims, separates or pours off the
  /// pot's fat — its rendered fat stays in the dish, in a share no source
  /// gives ("discard salt pork, leaving fat in pot"). Held
  /// (`discarded_medium`), as the 2026-10-01 rulings hold an unwritten
  /// eaten part.
  fatKept,

  /// v50 (Q20, D4): a line the steps keep a printed part of — the
  /// remainder saved for another use subtracted, a potato's kept COOKED
  /// weight converted to the raw record by FDC carbohydrate — or reserve
  /// or discard whole ([_partialUseOf]). Follows the policy: the kept part
  /// counted (`discarded`, as a frying oil's kept part), 0 g when none.
  partialUse;

  /// Whether [discardedMediaPolicy] decides how it counts; the others are
  /// always held for a person.
  bool get followsPolicy =>
      this == fryingOil ||
      this == brine ||
      this == brineSugar ||
      this == soak ||
      this == strainedSolid ||
      this == removedAromatic ||
      this == partialUse;

  /// The `hold` a row of this medium is stored under.
  String get hold => switch (this) {
    starterDiscard => 'starter_discard',
    coating => 'coating',
    partialPourAway => 'partial_pour_away',
    ambiguousMedium => 'ambiguous_medium',
    _ => 'discarded_medium',
  };
}

/// USER SWITCH (the ruling Q2, 2026-10-01): the share of a
/// [DiscardedMedium.coating] line a dredged food keeps. Null (no source
/// publishes an adherence figure and the user has set none) holds every
/// such line for a person; a fraction would count that share of the
/// line's grams instead, never a figure the user did not set.
/// ponytail: the counted share carries no "approximate" basis flag yet;
/// add it with the first fraction.
const double? coatingFraction = null;

/// How a discarded medium counts.
enum DiscardedMediaPolicy {
  /// 0 g, `gram_source: discarded`: resolved, adds nothing.
  zero,

  /// Held (`hold: discarded_medium`) for a person, storing only its eaten
  /// part as grams — none when no part is written (matcher v14).
  review,
}

/// USER ANSWER #2 SWITCH (discarded-media policy). [DiscardedMediaPolicy.zero]
/// is the recommended default for frying oil, brine salt and soaks (absorbed
/// oil and retained salt are real but unmeasured — no source gives a
/// fraction); [DiscardedMediaPolicy.review] holds them for a person instead.
/// A salt bath, cheese-making milk and drained cooking water are always
/// review; brine sugar follows the policy like the brine's salt (the user's
/// ruling R3, 2026-09-28).
const DiscardedMediaPolicy discardedMediaPolicy = DiscardedMediaPolicy.zero;

/// USER ANSWER #3 SWITCH (amount-less lines). True (the recommended default)
/// stores a matched line with no amount at all — "Lemon wedges, for
/// serving", "Vegetable oil spray", "Sugar" — as 0 g (`gram_source:
/// unmeasured`) with its food kept: resolved, outside the review queue (audit
/// 2: 172 such lines, 101 of them in no_grams). A weak match still sits in
/// `check`. False leaves them in `no_grams` for a person, as before.
const bool amountlessLinesZero = true;

/// Four cups, the threshold for buttermilk and milk quantities: exactly a
/// written "4 cups" ([volumeMlOf]: 4 × 236.588), so "4 cups" sits ON the
/// boundary and each rule's `>=` is pinned (v28, Run 058 S20: at 946 the 4
/// cups were 0.352 mL past it, and 947 or `>` moved nothing). A quart
/// (946.353 mL) is past it; no line of the library measures between.
const double _fourCupsMl = 236.588 * 4;

/// Grams of oil/shortening/lard that only a deep fry uses.
const double _fryingGrams = 400;

/// A quarter cup, the threshold for brine sugar and a salt bath.
/// Exactly a written ¼ cup's volume ([volumeMlOf]: 0.25 × 236.588), so a
/// "¼ cup" line sits ON the boundary and the `>=` of every rule reading it
/// is pinned (Run 054 S13: at 59 the ¼ cup was 0.147 mL past it, and `>`
/// for `>=` moved nothing). No line of the library measures between.
const double _quarterCupMl = 236.588 / 4;

/// Three tablespoons, the threshold for brine salt: a quart of shrimp or
/// pork-chop brine dissolves 3 tablespoons of table salt (audit 3: 35
/// brine-salt lines at 50 g or more).
const double _brineSaltMl = 44;

final RegExp _brineStep = RegExp(
  r'\bbrin(e|es|ed|ing)\b',
  caseSensitive: false,
);

/// A step that rubs, soaks, or drains whey ([discardedMediumOf]).
final RegExp _rubStep = RegExp(r'\brub', caseSensitive: false);
final RegExp _soakStep = RegExp(r'\bsoak', caseSensitive: false);
final RegExp _wheyStep = RegExp(r'\b(whey|curds?)\b', caseSensitive: false);

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
/// Read through the recipe's [_StepIndex], so each sentence is windowed.
List<String> _stepsOf(Recipe recipe) => _stepIndexOf(recipe).raw;

/// RULE C (v25, Run 055 I3/S4/O2/O3/S5/S7/S18): what the detectors read of
/// [recipe]'s steps, built ONCE per Recipe instance (immutable, so the
/// instance is the key, as [_headsOf]) and read by every detector: the
/// step texts and their lower case, the sentences of each step, the
/// sentence breaks of each step (a mention's sentence found by binary
/// search, never a scan of the step from it), the matches of a pattern in
/// a step (located once; a lookup from a mention is a binary search), and
/// what a detector derives from the steps alone (memoised by key, never
/// recomputed per line or per mention). A detector's cost is O(total text)
/// per recipe, end to end.
_StepIndex _stepIndexOf(Recipe recipe) =>
    _stepIndexes[recipe] ??= _StepIndex(recipe);

final Expando<_StepIndex> _stepIndexes = Expando();

/// The sentence split every detector reads: after a period, before
/// whitespace.
final RegExp _sentenceBreak = RegExp(r'(?<=\.)\s+');

/// A period that ends a sentence before more text (`_sentenceAt`'s
/// `\.\s`).
final RegExp _sentenceEnd = RegExp(r'\.(?=\s)');

/// How many [_StepIndex]es were built, the sentences they indexed and the
/// mentions they located — the pins' counts (Run 055 S16: a memo no pin
/// counts can be deleted with every test green).
@visibleForTesting
final stepIndexCounts = <String, int>{};

/// Every [_StepIndex.memo] derived afresh on every read — the memo
/// exactness oracle's reference (v27, Run 057 S9: a key that drops a
/// coordinate the derivation reads answers a later caller from an earlier
/// caller's derivation, and no COUNT pin can see it; the oracle compares
/// every answer with the memos on, in two orders, against this).
@visibleForTesting
bool memoOffForTest = false;

void _count(String what, [int n = 1]) =>
    stepIndexCounts[what] = (stepIndexCounts[what] ?? 0) + n;

class _StepIndex {
  _StepIndex(Recipe recipe)
    : raw = [for (final step in recipe.steps) _windowed(step.text)] {
    _count('indexes');
    _logWindows(recipe, raw);
  }

  /// Each step's text, every sentence windowed ([_windowed]).
  final List<String> raw;

  /// [raw], lower-cased once.
  late final List<String> lower = () {
    _count('lower');
    return [for (final step in raw) step.toLowerCase()];
  }();

  /// The sentences of each step of [lower].
  late final List<List<String>> sentences = [
    for (final step in lower) step.split(_sentenceBreak),
  ]..forEach((s) => _count('sentences', s.length));

  /// Every sentence of every step, in order.
  late final List<String> allSentences = () {
    _count('allSentences');
    return [for (final s in sentences) ...s];
  }();

  final Map<int, List<int>> _ends = {};

  /// Each line's own mention groups ([_ownsOf]), by line identity.
  final Expando<({String kind, List<String?> groups, int? paired, double? ml})>
  owns = Expando();

  /// Each line's own mention groups in cooking water ([_ownsOf]).
  final Expando<({String kind, List<String?> groups, int? paired, double? ml})>
  drainedOwns = Expando();
  final Map<(RegExp, int), List<Match>> _hits = {};
  final Map<Object, Object?> _memo = {};

  /// What this index's per-head scans ([naming]) have paid, in words
  /// visited (a confirm's characters each one more) — the naming
  /// inversion's amortiser ([_naming], [_inversionCost]).
  int namingPaid = 0;

  /// Each step's words ([_Words]), read once per step.
  late final List<_Words> words = [
    for (final (i, step) in lower.indexed) _Words(step, sentences[i]),
  ]..forEach((w) => _count('words', w.keys.length));

  /// How many words [words] holds: one per-head scan's cost.
  late final int wordCount = words.fold(0, (n, w) => n + w.keys.length);

  /// The first plus line [_eatenPlusPart] was asked about: its names read
  /// by their own scans; the second distinct line builds the inverted
  /// index (`#plusIndex`).
  String? firstPlusRaw;

  /// What [compute] derives from the steps alone, once per [key] — each
  /// derivation counted by its family ([_family]: `memo:fries`,
  /// `memo:naming`, …), so a memo whose key loses its exactness, or a
  /// detector that stops reading its memo, fails a COUNT pin, never only a
  /// clock (RULE C, v26, Run 056 S14/O15/S20). A record key names EVERY
  /// coordinate its derivation reads, each enumerated beside it ("Key:")
  /// and each pinned by a drop-one-coordinate mutant (v27, Run 057 S9:
  /// nutrition_v27_memo_keys_test.dart compares every answer with the
  /// memos on, in both line orders, against [memoOffForTest]).
  T memo<T>(Object key, T Function() compute) {
    if (memoOffForTest) {
      return compute();
    }
    if (_memo.containsKey(key)) {
      return _memo[key] as T;
    }
    _count('memo:${_family(key)}');
    return _memo[key] = compute();
  }

  /// The offsets of [step]'s sentence-ending periods ([_sentenceEnd]).
  List<int> _endsOf(int step) => _ends[step] ??= () {
    _count('ends');
    return [for (final m in _sentenceEnd.allMatches(lower[step])) m.start];
  }();

  /// The bounds of the sentence of [step] holding offset [at] — from after
  /// the period before it to its own period (excluded) — and its index in
  /// [sentences]. A binary search over the step's periods.
  ({int start, int end, int index}) sentenceAt(int step, int at) {
    final ends = _endsOf(step);
    final text = lower[step];
    final before = _firstAfter(ends, at, (e) => e, strict: true);
    final index = _firstAfter(ends, at, (e) => e);
    final end = index < ends.length
        ? ends[index]
        : text.endsWith('.') && text.length - 1 >= at
        ? text.length - 1
        : text.length;
    return (
      start: before == 0 ? 0 : ends[before - 1] + 1,
      end: end,
      index: index,
    );
  }

  /// The matches of [pattern] in [step]'s [lower], located once.
  List<Match> hits(RegExp pattern, int step) => _hits[(pattern, step)] ??= () {
    _count('hits');
    return pattern.allMatches(lower[step]).toList();
  }();

  /// The first match of [pattern] in [step] starting at or after [at].
  Match? firstFrom(RegExp pattern, int step, int at) {
    final all = hits(pattern, step);
    final i = _firstAfter(all, at, (m) => m.start);
    return i < all.length ? all[i] : null;
  }

  /// Where a sentence names [head] ([_names]) — (step, sentence) — once
  /// per head, whichever lines share it. An EXACT-COST lookup (RULE C v29,
  /// Run 059 O9: v28's `\b<lead>` regex pass ran 0.1 ns a character over
  /// corpus steps and 9 over words sharing the head's prefix, while the
  /// amortiser charged both alike): every word of every step ([words]) is
  /// visited once and its key compared with the keys of the head's lead
  /// words ([_leadsOf]) — an int compare, whatever the words spell — and a
  /// key that agrees is confirmed AT the word ([_namedFrom]). What it pays
  /// is [namingPaid]: each word visited, and each confirm the characters
  /// of the forms it compares. A head opening on no word character (no
  /// lead word) reads each sentence with [_names] (`namingReads`).
  // Key: head — the food each sentence is searched for.
  List<(int, int)> naming(String head) => memo(('naming', head), () {
    if (head.isEmpty) {
      return const [];
    }
    final at = <(int, int)>[];
    final leads = _leadsOf(head);
    if (leads.isEmpty) {
      for (final (i, step) in sentences.indexed) {
        _count('namingReads', step.length);
        for (final (j, s) in step.indexed) {
          namingPaid += s.length;
          if (_names(s, head)) {
            at.add((i, j));
          }
        }
      }
      return at;
    }
    // At most three lead words; an absent one keyed -1, no word's key.
    final k0 = _keyOf(leads[0]);
    final k1 = leads.length > 1 ? _keyOf(leads[1]) : -1;
    final k2 = leads.length > 2 ? _keyOf(leads[2]) : -1;
    final forms = _formsOf(head);
    final confirm = forms.fold(0, (n, f) => n + f.length);
    for (final (i, w) in words.indexed) {
      final keys = w.keys;
      namingPaid += keys.length;
      for (var k = 0; k < keys.length; k++) {
        final key = keys[k];
        if (key != k0 && key != k1 && key != k2) {
          continue;
        }
        namingPaid += confirm;
        final j = _namedFrom(w, w.starts[k], forms);
        if (j >= 0) {
          if (at.isEmpty || at.last != (i, j)) {
            at.add((i, j));
          }
        }
      }
    }
    return at;
  });

  /// The sentence at [at] ([naming]).
  String sentence((int, int) at) => sentences[at.$1][at.$2];

  /// Whether a match of [pattern] in [step] starts in [from, [to]).
  bool startsIn(RegExp pattern, int step, int from, [int? to]) {
    final first = firstFrom(pattern, step, from);
    return first != null && (to == null || first.start < to);
  }
}

/// Where a sentence of [recipe] names [head] ([_names]) — (step,
/// sentence), in order. RULE C (v26, Run 056 S9: a recipe of 400 distinct
/// foods scanned every sentence once per head, 2.5–11 s at the caps): the
/// steps' words are indexed once ([_StepIndex.words], O(text)); a head is
/// looked up by its own scan over them ([_StepIndex.naming], a word
/// visited is an int compare) or, once built, by the word index inverted
/// ([_namedByInversion], its own words only). A head opening on no word
/// character is read by sentence ([_names]).
///
/// The inversion is built by MEASURED amortisation (v28 closer, Run 058
/// O4/S8; its unit EXACT in v29, Run 059 O9): a head is scanned for alone
/// until what this index's per-head scans have paid
/// ([_StepIndex.namingPaid], words visited and confirm characters) reaches
/// the inversion's own, [_inversionCost] per word of the steps; then the
/// inversion is built, once, and every later head read from it. The
/// boundary: the scan whose paid units reach exactly
/// `_inversionCost × words` is the last one (`<`: the next head builds —
/// pinned by a run of heads no step names, each paying exactly the words).
/// So the scans a reader pays before the build exceed the build by at most
/// one scan (within about twice the cheaper choice, times the
/// measurement's spread): a reach that asks a cap recipe 8 heads (0149's
/// ten shared lines) never builds it; a compute or matches GET of the cap
/// recipe itself (400 heads) builds it within its first dozen heads.
List<(int, int)> _naming(Recipe recipe, String head) {
  final index = _stepIndexOf(recipe);
  final leads = _leadsOf(head);
  if (leads.isEmpty ||
      !index._memo.containsKey(#namingAll) &&
          index.namingPaid < _inversionCost * index.wordCount) {
    return index.naming(head);
  }
  return _namedByInversion(index, head, leads);
}

/// Where a sentence of [index] names [head] by the word index inverted
/// (`#namingAll`, built once): its [leads]' words looked up, each confirmed
/// at the word ([_namedFrom]) — what the per-head scan finds
/// ([_StepIndex.naming]), at the cost of the head's own words.
List<(int, int)> _namedByInversion(
  _StepIndex index,
  String head,
  List<String> leads,
) {
  // The word index inverted: each key's words, (step << 20 | word) in
  // order — every word read once, whatever the heads.
  final inverted = index.memo(#namingAll, () {
    final all = <int, List<int>>{};
    for (final (i, w) in index.words.indexed) {
      final keys = w.keys;
      for (var k = 0; k < keys.length; k++) {
        (all[keys[k]] ??= []).add(i << 20 | k);
      }
    }
    return all;
  });
  // Key: head — the food each sentence is searched for.
  return index.memo(('named', head), () {
    final words = [
      for (final lead in leads) ...?inverted[_keyOf(lead)],
    ]..sort();
    final forms = _formsOf(head);
    final at = <(int, int)>[];
    for (final p in words) {
      final i = p >> 20;
      final w = index.words[i];
      final start = w.starts[p & 0xFFFFF];
      final j = _namedFrom(w, start, forms);
      if (j >= 0) {
        if (at.isEmpty || at.last != (i, j)) {
          at.add((i, j));
        }
      }
    }
    return at;
  });
}

/// The naming inversion's cost — the word index inverted, every word read
/// once ([_naming]) — in per-head scan units: one word visited
/// ([_StepIndex.naming]). Measured (v29, JIT, 3 rounds each;
/// fix29/rulec): a word visited 0.95–1.0 ns at the caps and 2.1 over the
/// whole corpus (1,198 recipes, 335,066 words); the inversion 7.1–8.9 ns a
/// word at the caps (0149's fillers, the reach shape, Run 059 O9's 40- and
/// 900-character prefix words alike) and 29–31 over the corpus (small
/// recipes: a list per distinct word). In scans: 7.5–9.4 at the caps, 14–15
/// over the corpus; 12 lies within 1.6× of every measurement, so the build
/// comes within a small factor of the moment it pays — whatever the words
/// spell (v28's unit, a step-pass character, cost 0.1 ns over corpus text
/// and 9 over words sharing a head's prefix).
const int _inversionCost = 12;

/// Where each of [patterns] FIRST occurs in each of [texts] — (text,
/// start), in text order; a pattern found in no text is absent. The
/// inverted name index of the substring readers ([_dissolvedWithBrineSalt]'s
/// salts, [_eatenPlusPart]'s amounts): ONE pass over the texts whatever
/// the patterns (Aho–Corasick: a trie of the patterns and its failure
/// links; at each character the patterns ending there are read down the
/// dictionary links, and a node already read in this text ends the walk,
/// its links read with it), so O(text + patterns + the pairs found) —
/// never patterns × text (RULE C, v27, Run 057 S4/S12/S7: 200 distinct
/// salts × 199 brine salts, 104 s a GET; 400 distinct plus amounts, a
/// second per compute). Counted ([stepIndexCounts] `occurrenceScans`, one
/// per text read).
Map<String, List<(int, int)>> _occurrences(
  List<String> texts,
  Iterable<String> patterns,
) {
  // One pattern: the native `indexOf` per text (the trie walk reads a map
  // per character, ~8 ms over a cap recipe's steps; the v27 closer, the
  // verifier's D11 — a one-line reader's own names, [_eatenPlusPart]).
  if (patterns.length == 1) {
    final p = patterns.first;
    final at = <(int, int)>[];
    for (final (t, text) in texts.indexed) {
      _count('occurrenceScans');
      final i = text.indexOf(p);
      if (i >= 0) {
        at.add((t, i));
      }
    }
    return {if (at.isNotEmpty) p: at};
  }
  // The trie: node << 16 | code unit → node (code units are 16 bits).
  final next = <int, int>{};
  final children = <List<int>>[[]];
  final word = <String?>[null];
  final depth = [0];
  final found = <String, List<(int, int)>>{};
  for (final p in patterns) {
    if (p.isEmpty) {
      // As `contains('')`: at the start of every text.
      found[p] = [for (var t = 0; t < texts.length; t++) (t, 0)];
      continue;
    }
    var node = 0;
    for (final c in p.codeUnits) {
      final key = node << 16 | c;
      var to = next[key];
      if (to == null) {
        next[key] = to = word.length;
        children[node].add(c);
        children.add([]);
        word.add(null);
        depth.add(depth[node] + 1);
      }
      node = to;
    }
    word[node] = p;
  }
  // Failure links breadth first; [out]: the nearest node on a node's
  // failure chain (itself first) that ends a pattern, or -1.
  final fail = List.filled(word.length, 0);
  final out = List.filled(word.length, -1);
  final queue = [0];
  for (var q = 0; q < queue.length; q++) {
    final u = queue[q];
    for (final c in children[u]) {
      final v = next[u << 16 | c]!;
      var to = 0;
      if (u != 0) {
        for (var f = fail[u]; ; f = fail[f]) {
          final hit = next[f << 16 | c];
          if (hit != null || f == 0) {
            to = hit ?? 0;
            break;
          }
        }
      }
      fail[v] = to;
      out[v] = word[v] != null ? v : out[to];
      queue.add(v);
    }
  }
  final seen = List.filled(word.length, -1);
  for (final (t, text) in texts.indexed) {
    _count('occurrenceScans');
    var node = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      for (;;) {
        final to = next[node << 16 | c];
        if (to != null) {
          node = to;
          break;
        }
        if (node == 0) {
          break;
        }
        node = fail[node];
      }
      for (var w = out[node]; w >= 0 && seen[w] != t; w = out[fail[w]]) {
        seen[w] = t;
        (found[word[w]!] ??= []).add((t, i + 1 - depth[w]));
      }
    }
  }
  return found;
}

/// [_naming], for the pins.
@visibleForTesting
List<(int, int)> namingForTest(Recipe recipe, String head) =>
    _naming(recipe, head);

/// [_StepIndex.naming] — the per-head scan, never the inversion — for the
/// pins.
@visibleForTesting
List<(int, int)> namingByScanForTest(Recipe recipe, String head) =>
    _stepIndexOf(recipe).naming(head);

/// [_namedByInversion] — the inversion, never the per-head scan — for the
/// pins.
@visibleForTesting
List<(int, int)> namingByInversionForTest(Recipe recipe, String head) {
  final leads = _leadsOf(head);
  return leads.isEmpty
      ? const []
      : _namedByInversion(_stepIndexOf(recipe), head, leads);
}

/// The words of [recipe]'s steps ([_StepIndex.wordCount]), for the pins.
@visibleForTesting
int wordCountForTest(Recipe recipe) => _stepIndexOf(recipe).wordCount;

/// What [recipe]'s per-head scans have paid ([_StepIndex.namingPaid]), for
/// the pins.
@visibleForTesting
int namingPaidForTest(Recipe recipe) => _stepIndexOf(recipe).namingPaid;

/// [_wordHeadsOf], for the pins.
@visibleForTesting
Set<String> wordHeadsForTest(Recipe recipe) => _wordHeadsOf(recipe);

/// [_occurrences], for the semantic pin (Run 058 O11/S19).
@visibleForTesting
Map<String, List<(int, int)>> occurrencesForTest(
  List<String> texts,
  Iterable<String> patterns,
) => _occurrences(texts, patterns);

/// The heads of [recipe] a sentence is searched for by word ([_wordsOf]):
/// each line's head noun — or its item's last word when it has none, as
/// [discardedMediumOf] reads "8 whole cloves" — written in word characters
/// only, the words [_wordsOf] finds (its `\w+` words are [_names]' `\b`).
Set<String> _wordHeadsOf(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#wordHeads, () {
      final heads = _headsOf(recipe);
      return {
        for (final (i, line) in nutritionLines(recipe).indexed)
          if (heads[i] ?? normalizeItem(lineItemOf(line)).split(' ').last
              case final head when _wordOnly.hasMatch(head))
            head,
      };
    });

final RegExp _wordOnly = RegExp(r'^[a-z0-9]+$');

/// A memo key's family: a symbol's name, or a record key's first field.
String _family(Object key) => switch (key) {
  (final Object? f, _) => '$f',
  (final Object? f, _, _) => '$f',
  (final Object? f, _, _, _) => '$f',
  (final Object? f, _, _, _, _) => '$f',
  final Symbol s => '$s'.replaceAll(RegExp(r'^Symbol\("|"\)$'), ''),
  _ => '$key',
};

/// The index of the first of [sorted] whose [key] is at or after [at]
/// (after it, [strict]).
int _firstAfter<T>(
  List<T> sorted,
  int at,
  int Function(T) key, {
  bool strict = false,
}) {
  var lo = 0;
  var hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    final k = key(sorted[mid]);
    if (k < at || (strict && k == at)) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// A step's [text] as the detectors read it: a sentence longer than
/// [maxScannedSentence] is read for its first [maxScannedSentence]
/// characters (its period kept, so the next sentence stays its own) and
/// the rest ignored — logged ([_logWindows]), never a silently disabled
/// rule (Run 055 S7: v24 read such a sentence as none, so a step typed
/// without full stops lost every step rule). The corpus's longest
/// sentence is 371 characters: no corpus step changes.
String _windowed(String text) {
  if (text.length <= maxScannedSentence) {
    return text;
  }
  final out = StringBuffer();
  var cut = false;
  var from = 0;
  for (final m in [..._sentenceBreak.allMatches(text), null]) {
    final sentence = text.substring(from, m?.start ?? text.length);
    if (sentence.length > maxScannedSentence) {
      cut = true;
      out.write(sentence.substring(0, maxScannedSentence));
      if (sentence.endsWith('.')) {
        out.write('.');
      }
    } else {
      out.write(sentence);
    }
    if (m != null) {
      out.write(m[0]);
      from = m.end;
    }
  }
  return cut ? out.toString() : text;
}

/// Logs each step of [recipe] [_windowed] cut ([raw] differs from its
/// text) — ONCE per recipe id and step content (RULE C, v26, Run 056
/// O7/S6/S11: logged on every index build, a member's matches GET wrote
/// 120 records into the store that keeps the sign-in audit lines). The
/// set is bounded, cleared whole past [_windowsLoggedCap] (a re-log after
/// a clear, never an unbounded set); keyed by the steps' hash, so a
/// collision can only skip a notice, never a rule.
void _logWindows(Recipe recipe, List<String> raw) {
  final cut = [
    for (final (i, step) in recipe.steps.indexed)
      if (!identical(raw[i], step.text)) i,
  ];
  if (cut.isEmpty) {
    return;
  }
  if (_windowsLogged.length >= _cap(_windowsLoggedCap)) {
    _windowsLogged.clear();
  }
  if (!_windowsLogged.add((recipe.id, Object.hashAll(raw)))) {
    return;
  }
  for (final i in cut) {
    _count('windowLogs');
    _log.info(
      'recipe ${recipe.id}: step ${i + 1} has a sentence over '
      '$maxScannedSentence characters; the nutrition rules read its first '
      '$maxScannedSentence',
    );
  }
}

final Set<(String, int)> _windowsLogged = {};
const _windowsLoggedCap = 20000;

/// [cap], or every process-wide memo's cap in a test ([memoCapForTest]).
int _cap(int cap) => memoCapForTest ?? cap;

/// The second part of a discarded-medium "plus" line that a step uses
/// elsewhere, eaten: "1 cup plus 2 teaspoons table salt" with "remaining 2
/// teaspoons salt" in the rub (0246), "2 cups plus 1 tablespoon vegetable
/// oil" with "1 tablespoon of the oil" beaten into the eggs (0233). Null when
/// no step names its amount beside the food — the whole line is the medium
/// ("½ cup plus 2 tablespoons table salt" all dissolves in 0150's brine).
/// The FIRST part is the eaten one when the second is not named and a step
/// names it, the smaller part: "1 tablespoon plus ¾ cup vegetable oil"
/// beats "1 tablespoon of the oil" into the eggs and fries in the rest
/// (0114; any medium alike — "2 teaspoons plus 1 cup table salt" with a
/// rub of "2 teaspoons salt" — no other library line reaches it).
PlusPart? _eatenPlusPart(Recipe recipe, IngredientLine line, String? head) {
  final plus = plusPartOf(line.raw);
  if (plus == null || !plus.sameFood || head == null) {
    return null;
  }
  // Once per (amount, head) and recipe (RULE C, v26: every plus line
  // re-read every step), each answer read off ONE inverted index of the
  // steps — where every plus line's amounts and head first occur in each
  // ([_occurrences]; v27, Run 057 S7: one scan of every step per DISTINCT
  // amount, 400 '2 cups plus k teaspoons' lines a second per compute) —
  // and a step naming both found by merging two lists of steps.
  // The index is paid by the caller that amortises it (RULE C, as
  // [_naming]'s): the FIRST plus line asked about scans for its own names
  // alone, so a one-line reader — a single-line PUT, the reach — pays
  // O(its names); the second distinct line builds the index every later
  // line reads (v27 closer, the verifier's D11: plus-real's one-line PUT
  // paid the whole recipe's index, +24 ms over 4a1c58e).
  final index = _stepIndexOf(recipe);
  final (:searched, :steps) =
      (index.firstPlusRaw ??= line.raw) == line.raw &&
          !index._memo.containsKey(#plusIndex)
      ? (searched: const <String>{}, steps: const <String, List<(int, int)>>{})
      : index.memo(#plusIndex, () {
          final searched = <String>{};
          for (final other in nutritionLines(recipe)) {
            if (plusPartOf(other.raw) case final p? when p.sameFood) {
              searched.addAll([
                ?_plusLead(p.text),
                ?_plusLead(other.raw),
                ?headNounOf(normalizeItem(lineItemOf(other))),
              ]);
            }
          }
          return (
            searched: searched,
            steps: _occurrences(index.lower, searched),
          );
        });
  List<(int, int)> stepsOf(String name) => searched.contains(name)
      ? steps[name] ?? const []
      : index.memo(
              // Key: name — the one name scanned for.
              ('plusSteps', name),
              () => _occurrences(index.lower, [name]),
            )[name] ??
            const [];
  bool named(String? amount) =>
      amount != null &&
      // Key: amount and head — the two names a step must hold.
      index.memo(('plusNamed', amount, head), () {
        final a = stepsOf(amount);
        final h = stepsOf(head);
        for (var i = 0, j = 0; i < a.length && j < h.length;) {
          if (a[i].$1 == h[j].$1) {
            return true;
          }
          a[i].$1 < h[j].$1 ? i++ : j++;
        }
        return false;
      });
  final first = line.amounts.firstOrNull;
  final written = _plusLead(line.raw);
  // Two volumes compared, never a default for a missing one (Run 054 S13:
  // the `?? infinity` / `?? 0` arms were unpinnable values).
  final firstMl = first == null ? null : volumeMlOf([first]);
  final plusMl = volumeMlOf([plus.amount]);
  final smallFirst = firstMl != null && plusMl != null && firstMl < plusMl;
  // A small first part a step names is the eaten one even when the steps
  // name the large part too (v31: 0675's "1 teaspoon plus ½ cup vegetable
  // oil" sautés the corn in the teaspoon and fries in "the remaining ½
  // cup").
  // Not when the sentence naming it sets a dredge's coat out in its dish
  // (v33: 0206's "Place ¼ cup of the flour in a pie plate" is the dredge;
  // "the remaining 6 tablespoons flour" whisked into the egg is eaten).
  if (smallFirst && named(written) && !_setsOut(recipe, written!, head)) {
    return PlusPart(amount: first!, text: written, sameFood: true);
  }
  if (named(_plusLead(plus.text))) {
    return plus;
  }
  // v31 (the owner's R4 ruling on 0042): a plus part the steps eat in
  // pieces after the fat's last discard — "Discard the oil …" then "Heat 1
  // tablespoon more oil … add the remaining 1 tablespoon oil" (¾ cup plus
  // 2 tablespoons vegetable oil): the pieces total the plus part.
  final after = plusMl == null ? null : _eatenAfterDiscard(recipe, head);
  return after != null && (after - plusMl!).abs() < 0.5 ? plus : null;
}

/// v57 (M59 F1, critic F1; CP9's rinsed cure, 0 g): whether the steps
/// rinse a frying fat's eaten [part] ([_eatenPlusPart]) off its food — the
/// sentence naming the part tosses it ("toss with ¼ cup of the oil") and
/// LATER sentences of the same step drain and rinse ("drain the potatoes
/// into a large mesh strainer … Rinse well under cold running water", 0255
/// Fish and Chips). A rinse before the toss keeps the part. No food is
/// matched: the step stands in for the tossed one (closer 1, V1-D1 — 0255's
/// rinse sentence names no food, its drain "potatoes" where the toss names
/// "fries").
/// ponytail: a step that tosses one food in the oil and drains and rinses
/// ANOTHER after it zeroes the part (no corpus step does); bind the drain to
/// the tossed food's line when one must keep it.
bool _rinsedOff(Recipe recipe, PlusPart part, String head) {
  final amount = _plusLead(part.text);
  final fat = _fats[head];
  if (amount == null || fat == null) {
    return false;
  }
  for (final sentences in _stepIndexOf(recipe).sentences) {
    for (final (i, s) in sentences.indexed) {
      if (s.contains(amount) && fat.word.hasMatch(s) && _toss.hasMatch(s)) {
        final later = sentences.skip(i + 1);
        if (later.any(_drainWord.hasMatch) && later.any(_rinseWord.hasMatch)) {
          return true;
        }
      }
    }
  }
  return false;
}

final RegExp _toss = RegExp(r'\btoss\b');

/// Whether a sentence of [recipe] sets [amount] of [head] out as a dredge's
/// coat ([_setsOutTheCoat], [_eatenPlusPart]). Once per amount and head.
bool _setsOut(Recipe recipe, String amount, String head) =>
    // Key: amount and head — the two names the sentence must hold.
    _stepIndexOf(recipe).memo(('setsOut', amount, head), () {
      return _stepIndexOf(recipe).allSentences.any(
        (s) =>
            s.contains(amount) &&
            s.contains(head) &&
            _setsOutTheCoat.hasMatch(s),
      );
    });

/// A sentence setting a dredge's coat out in its dish ([_setsOut]): "in a
/// pie plate" (0206, 0254), a shallow (baking) dish.
final RegExp _setsOutTheCoat = RegExp(
  r'\b(?:pie plate|shallow (?:baking )?dish)\b',
);

/// The volume (mL) of [head] fat [recipe]'s sentences add after its LAST
/// discard ("1 tablespoon more oil", "the remaining 1 tablespoon oil") —
/// [_eatenPlusPart] — or null when no sentence discards it or none adds
/// any after. Once per recipe and head.
double? _eatenAfterDiscard(Recipe recipe, String head) {
  final fat = _fats[head];
  if (fat == null) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // Key: head — the fat discarded and added.
  return index.memo(('eatenAfterDiscard', head), () {
    final all = index.allSentences;
    final last = all.lastIndexWhere(fat.discards.hasMatch);
    if (last < 0) {
      return null;
    }
    final adds = RegExp(
      '($_amountRun)\\s*(teaspoons?|tablespoons?|cups?)\\s+(?:more\\s+)?'
      '${RegExp.escape(head)}\\b',
    );
    var ml = 0.0;
    for (final s in all.skip(last + 1)) {
      for (final m in adds.allMatches(s)) {
        ml +=
            volumeMlOf(parseIngredientLine('${m[1]}${m[2]} $head').amounts) ??
            0;
      }
    }
    return ml > 0 ? ml : null;
  });
}

/// A plus line part's written amount as [_eatenPlusPart] looks for it in
/// the steps: its number run and the word after it ("2 teaspoons").
String? _plusLead(String part) => _plusLeadPattern.firstMatch(
  part.toLowerCase(),
)?[0];

final RegExp _plusLeadPattern = RegExp(
  '^[\\d$vulgarFractionChars/ -]+[a-z]+',
);

/// The scan WINDOW of one sentence ([_windowed]; Run 054 Sonnet critic 1,
/// Run 055 S7): the discarded-medium rules read the first this many
/// characters of a longer sentence and ignore the rest, and a log says so.
/// The corpus's longest is 371 characters (0241 Garlic-Studded Roast Pork
/// Loin, measured 2026-10-01).
const maxScannedSentence = 1000;

/// A written amount's number run as the rules' regexes read it — "1 1/2 ",
/// "½ " — BOUNDED (Run 054 Sonnet critic 1): an unbounded `[\d½/ ]*` before
/// a `\s` re-scanned every start of a long "1 1 1 …" run (n = 8,000 took
/// 3.3 s on one GET); at most 13 characters, each start costs a constant.
final String _amountRun =
    '[\\d$vulgarFractionChars][\\d$vulgarFractionChars/ ]{0,12}';

/// Whether a step of [steps] keeps a little sourdough starter and discards
/// the rest — a feeding ([DiscardedMedium.starterDiscard], Q1). Measured:
/// Sourdough Starter (0799) is the one recipe of the library whose steps
/// say it; every other "discard" (fat, solids, dough scraps, whey) names no
/// starter.
bool _feedsStarter(List<String> steps) => steps.any(
  RegExp(
    r'\bdiscard (?:the )?remaining starter\b',
    caseSensitive: false,
  ).hasMatch,
);

/// The head nouns of a dredge: flour, starch, crumbs (the ruling's words;
/// 'cornmeal' and 'meal' reached no line and were deleted, v23 — a typed
/// "1 cup cornmeal" catfish dredge counts whole).
const Set<String> _dredgeHeads = {
  'flour',
  'cornstarch',
  'starch',
  'crumb',
  'panko',
};

/// Whether a line ([raw]) is a [DiscardedMedium.coating] (Q2): its text
/// says "for dredging" / "for coating", or ¼ cup or more of flour, starch
/// or crumbs (either unit family, [_mediumMl]: 30.2 g of flour) a step
/// names in a dredge — "dredge … in the flour", "shake off excess flour",
/// or set out in a shallow dish for the food to be coated in (Crispy Fried
/// Chicken, 0148; Chicken Schnitzel, 0116, its flour and its crumbs) — in
/// a recipe that FRIES ([_fries]; the CP9 ruling, kept as a sufficient
/// condition) or whose directions LEAVE AN EXCESS of the coat
/// ([_leavesExcess]; the owner's dredge-reach ruling, 2026-10-03, v33: a
/// sautéed piccata, a baked Kiev). A batter is eaten whole and is none:
/// Buffalo Cauliflower Bites (0672) sprinkle the cornstarch over the wet
/// florets and fold until coated. The quarter cup keeps a sauce's
/// thickener off (0304's 3 tablespoons of gravy flour, 0525's 1 tablespoon
/// plus 2 teaspoons of cornstarch). A coat wholly eaten — a toss, a binder,
/// a crust pressed on with no excess sentence — in a recipe that does not
/// fry stays counted (0414 Chicken Marsala, 0115 Katsu, 0287 Salmon Cakes).
bool _dredge(
  Recipe recipe,
  String raw,
  String? head,
  double Function() ml,
  List<String> steps,
) {
  if (!_dredgeHeads.contains(head)) {
    return false;
  }
  if (RegExp(r'\bfor (dredging|coating)\b').hasMatch(raw)) {
    return true;
  }
  if (ml() < _quarterCupMl || !(_fries(recipe) || _leavesExcess(recipe))) {
    return false;
  }
  // Once per head (RULE C, v26, Run 056 O6/S9: re-scanned per line, 380
  // lines 3.1 s).
  final index = _stepIndexOf(recipe);
  // Key: head — the dredge food its sentences name.
  return index.memo(('dredgeNamed', head), () {
    return _naming(
      recipe,
      head!,
    ).any((at) => _dredgeSentence.hasMatch(index.sentence(at)));
  });
}

/// Whether [recipe]'s directions leave an EXCESS of a dry coat behind
/// ([_dredge], v33; the owner's ruling 2026-10-03 on the dredge survey,
/// `.claude/diag/2026-10-01/prep30/dredge.md`): a sentence that shakes,
/// removes or pats off the excess — "dredge in the flour, shaking off the
/// excess" (0148, 0122), "Shake excess flour from each steak" (0304),
/// "shaking gently to remove excess" (0415, 1133), "Using pastry brush,
/// remove excess cornstarch" (0257), "Thoroughly pat off the excess
/// cornstarch mixture" (0235) — the excess the coat or nothing, never a
/// liquid ("allowing the excess to drip off": no removal verb; "blot the
/// excess oil", "wipe off the excess salt": not the coat). Not in a step
/// that shapes a DOUGH ("roll it in your palms to coat with flour, shaking
/// off the excess", 0792 Rustic Dinner Rolls; "brush … each dough round …
/// to remove any excess flour", 0806 Pita): a dusting, not a dredge. A coat
/// set out in a shallow dish alone is no excess: 0115 Katsu, 0415 Best
/// Chicken Parmesan, 0287 Salmon Cakes, 0289 Best Crab Cakes and 0414
/// Chicken Marsala set theirs out and the survey reads each wholly eaten.
/// Reproduces the survey's Y/N on all 47 in-scope recipes. Once per recipe.
bool _leavesExcess(Recipe recipe) => _stepIndexOf(recipe).memo(
  #leavesExcess,
  () {
    final index = _stepIndexOf(recipe);
    return index.sentences.indexed.any(
      (e) =>
          e.$2.any(_excessOfTheCoat.hasMatch) &&
          !_dough.hasMatch(index.lower[e.$1]),
    );
  },
);

/// [_leavesExcess] for the tests (the survey's 47-recipe reproduction).
@visibleForTesting
bool leavesExcessForTest(Recipe recipe) => _leavesExcess(recipe);

/// A removal verb, then the excess of the coat or of nothing named
/// ([_leavesExcess]).
final RegExp _excessOfTheCoat = RegExp(
  r'\b(?:shak|remov|pat)\w*\b[^.]*?\bexcess\b(?=$|[^\w\s]|\s+(?:and|then|'
  r'flour|cornstarch|starch|bread|crumbs?|panko|coating)\b)',
);

final RegExp _dough = RegExp(r'\bdough');

/// A sentence that dredges a food in a line ([_dredge]).
final RegExp _dredgeSentence = RegExp(
  r'\bdredg|\bexcess\b|\bshallow dish\b',
);

/// Whether [recipe] deep-, shallow- or pan-fries, read from its DIRECTIONS,
/// never the oil's mass (Run 053 O7/S5: a 400 g threshold left 0149 Easier
/// Fried Chicken, 381 g, counted while 1133 Francese, with less, was held):
/// a step sentence says fry as a VERB ([_fryVerb]: "fry until deep golden
/// brown", 0148; "pan-fry", 0288), heats the oil to a frying temperature
/// ([_Fat.heatsToFry], every frying fat of [_fats]: "heat over
/// medium-high heat to 375 degrees", 0149; never an oven's "bake at 375
/// degrees"), or discards the oil the food
/// cooked in ("Discard the oil in the skillet", 0198) — or a line is "for
/// (deep) frying" ([_forFrying]; 1133's oils). A sauté keeps its fat in the
/// pan (piccata, meunière) and a baked dredge has no such step: both stay
/// outside the ruling until the user rules on them.
bool _fries(Recipe recipe) => _stepIndexOf(recipe).memo(
  #fries,
  () =>
      nutritionLines(
        recipe,
      ).any((other) => _forFrying.hasMatch(other.raw.toLowerCase())) ||
      _stepIndexOf(recipe).allSentences.any(
        (s) =>
            _fryVerb.hasMatch(s) ||
            _fats.values.any(
              (fat) =>
                  fat.heatsToFry(s, () => _heatReading(recipe, s)) ||
                  fat.discards.hasMatch(s),
            ),
      ) ||
      _shallowFries(recipe),
);

/// v53 (M52 Q24 b, critic F1; RE-RULES the 2026-10-03 R4 "shimmering/
/// smoking stays non-evidence" for this one shape): whether [recipe]
/// SHALLOW-FRIES a food it coats — after a sentence coating or dredging a
/// food in a flour, starch or crumb ([_coatsAFood]) a sentence heats the
/// oil ([_heatsTheOil]): a quarter cup or more of it as written, or, with
/// no amount written, a recipe whose oil line the mass rule could zero
/// ([_couldZero]); and one of that step's next three sentences browns
/// ("cook … until … golden brown"; "pan-fry until … browned"): 0118's
/// "Heat the remaining ¾ cup oil …", 0115's "Heat ¼ cup oil and small
/// pinch of panko …", 0287's and 0288's "Heat (the) oil …". A sauté's
/// "Heat 2 tablespoons oil" (0415 marsala, 0418 piccata) is none. Reads
/// no line's hold ([_dredge] reads [_fries]). Once per recipe.
bool _shallowFries(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#shallowFries, () {
      final heads = _headsOf(recipe);
      if (!nutritionLines(recipe).indexed.any(
        (e) =>
            heads[e.$1] == 'oil' && e.$2.amounts.isNotEmpty && _couldZero(e.$2),
      )) {
        return false;
      }
      var coated = false;
      for (final sentences in _stepIndexOf(recipe).sentences) {
        for (final (j, s) in sentences.indexed) {
          if (!coated) {
            coated = _coatsAFood.hasMatch(s);
            continue;
          }
          final heat = _heatsTheOil.firstMatch(s);
          if (heat == null) {
            continue;
          }
          final written = heat[1];
          if (written != null &&
              (volumeMlOf(parseIngredientLine('$written oil').amounts) ?? 0) <
                  _quarterCupMl) {
            continue;
          }
          if (sentences.skip(j + 1).take(3).any(_browns.hasMatch)) {
            return true;
          }
        }
      }
      return false;
    });

/// A sentence coating or dredging a food in a flour, starch or crumb
/// ([_shallowFries]).
final RegExp _coatsAFood = RegExp(
  r'\b(?:dredg|coat)\w*\b[^.]*\b(?:flour|cornstarch|starch|crumbs?|panko)\b',
);

/// A sentence heating the oil, its amount as written if any
/// ([_shallowFries]): "heat the remaining ¾ cup oil", "heat oil".
final RegExp _heatsTheOil = RegExp(
  r'\bheat (?:the )?(?:remaining )?'
  '(?:([\\d$vulgarFractionChars][\\d/⁄ $vulgarFractionChars]{0,8}'
  ' (?:cups?|tablespoons?|teaspoons?)) (?:more )?(?:of )?(?:the )?)?'
  r'(?:[a-z-]+ )?oil\b',
);

/// A sentence that browns ([_shallowFries]).
final RegExp _browns = RegExp(r'\bbrown');

/// Where [recipe]'s first frying-VERB sentence is ([_fryVerb]) — (step,
/// sentence) — or null, once per recipe ([_oilOwnersOf], v31).
(int, int)? _fryVerbAt(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#fryVerbAt, () {
      for (final (i, sentences) in _stepIndexOf(recipe).sentences.indexed) {
        for (final (j, s) in sentences.indexed) {
          if (_fryVerb.hasMatch(s)) {
            return (i, j);
          }
        }
      }
      return null;
    });

/// [_fries] for the tests (Run 054 O2/S2: the 13 corpus recipes that say
/// "fry" and do not fry in oil).
@visibleForTesting
bool friesForTest(Recipe recipe) => _fries(recipe);

/// A line's "for frying" / "for deep frying" / "for deep-frying" — ONE
/// signal for the dredge ([_fries]) and the oil ([discardedMediumOf]) (Run
/// 054 Sonnet critic 3: v23 narrowed the dredge's to "for frying" while the
/// oil's kept "deep", so 0116 Schnitzel's oil retyped "for deep frying"
/// was frying oil beside an unheld dredge).
final RegExp _forFrying = RegExp(r'\bfor (?:deep[- ]?)?frying\b');

/// "fry" as a frying VERB (Run 054 O2/S2: `\bfry\b` read 13 corpus recipes
/// that fry nothing in oil as frying). Not the stir-fry (0540, 0542) or an
/// oven-fry (0122) — another word hyphened before it — not a noun ("each
/// fry" of 0705's oven fries; a "deep-fry thermometer", 0148/0304/0525),
/// not an optional note that OPENS its sentence ("To pan-fry, increase
/// water", 0506 — an infinitive inside a sentence fries: "Continue to fry,
/// tilting skillet", 0248, Run 055 D2), not a negation ("garlic should not
/// actively fry", 1131), and not bacon or prosciutto fried in their own
/// fat ("fry the bacon", 0024, 0034, 0040, 0205, 0451, 0461, 0495; "add
/// the prosciutto and fry", 0040) or rice toasted for a pilaf ("add the
/// rice and fry", 0500). "pan-fry" (0288's crab cakes), "deep-fry" and
/// "shallow-fry" are fries in oil. The stir-fry, air-fry, oven-fry and a
/// dry fry spelled with a space are none either, nor a fry a sentence
/// negates ("do not fry", "don't fry", "never fry"; Run 055 S3 — typed
/// through the API: no corpus step says them). Each exclusion is a
/// lookaround of bounded length: linear.
final RegExp _fryVerb = RegExp(
  r'(?<![\w-])(?<!\b(?:each|actively|prosciutto and|rice and|stir|air|oven|'
  "dry|not|never|don't|don’t) )(?<!^to )"
  r'(?:(?:pan|deep|shallow)-)?fry\b(?! the bacon\b| thermometer\b)',
);

/// The frying fats — the heads [discardedMediumOf]'s mass rule knows (RULE
/// B, v26, Run 056 O3: v25's signals read the literal word "oil", so a
/// typed "Heat the shortening in a Dutch oven to 375 degrees" counted the
/// cup whole where v24 read it frying fat). Every frying signal of a
/// sentence reads its line's OWN fat noun ([_Fat]); [_fries] reads each.
final Map<String, _Fat> _fats = {
  for (final head in const ['oil', 'shortening', 'lard']) head: _Fat(head),
};

/// One frying fat's sentence patterns, compiled once ([_fats]).
class _Fat {
  _Fat(String head)
    : word = RegExp('\\b$head\\b'),
      temperature = RegExp('\\b$head temperature\\b'),
      discards = RegExp('\\bdiscard (?:the )?$head\\b'),
      pourOffAllBut = RegExp(
        r'\bpour off all but '
        '($_amountRun(?:teaspoons?|tablespoons?|cups?))\\s+$head\\b',
      ),
      reserveRest = RegExp(
        r'\breserve '
        '($_amountRun(?:teaspoons?|tablespoons?|cups?))\\s+$head\\b'
        r'[^.;]{0,60}?\bdiscard the remainder\b',
      ),
      reserveFrying = RegExp(
        r'\breserve '
        '($_amountRun(?:teaspoons?|tablespoons?|cups?))\\s+(?:frying )?'
        '$head\\b',
      ),
      heatsReserved = RegExp('\\bheat (?:the )?reserved $head\\b'),
      head = head;

  final String head;

  /// The fat's noun ("oil", "lard").
  final RegExp word;

  /// "oil temperature of about 325 degrees" (0148), "maintain oil
  /// temperature between 350 and 375 degrees" (1081).
  final RegExp temperature;

  /// A sentence discarding the fat a food cooked in ("Discard the oil in
  /// the skillet", 0198; "discard oil", 1133).
  final RegExp discards;

  /// "pour off all but 2 tablespoons oil" (1193): the written part kept.
  /// Only this form: "Pour off the oil and reserve" (0523 Nasi Goreng) keeps
  /// it all, counted (Run 055 O14).
  final RegExp pourOffAllBut;

  /// v51 (M49 Q19 a, P1 D3a): "Reserve 1 tablespoon oil from the skillet
  /// and discard the remainder" (0215 Horseradish-Crusted Beef Tenderloin's
  /// fried potato oil, counted whole before: 233 g): the written part kept,
  /// read as a pour-off ([pourOffAllBut]).
  final RegExp reserveRest;

  /// v57 (M59 C): "After frying, reserve 2 tablespoons frying oil." (0279
  /// Crispy Salt and Pepper Shrimp, 0536 Crispy Orange Beef) — a kept part
  /// only where a LATER sentence heats it ([heatsReserved]: "Heat reserved
  /// oil in 12-inch skillet"), the consumer "discard the remainder" stands
  /// in for ([_oilOwnersOf]); 0661's "Reserve 3 tablespoons oil mixture" is
  /// brushed on, never heated.
  final RegExp reserveFrying;

  /// "Heat reserved oil" — a later sentence cooking in [reserveFrying]'s
  /// part.
  final RegExp heatsReserved;

  /// The kept part a pour-off sentence [s] writes, any form — the third
  /// ([reserveFrying]) only when a later sentence heats it ([reused]).
  RegExpMatch? keptPart(String s, {bool reused = false}) =>
      pourOffAllBut.firstMatch(s) ??
      reserveRest.firstMatch(s) ??
      (reused ? reserveFrying.firstMatch(s) : null);

  /// Whether sentence [s] (lower case) heats this fat to a frying
  /// temperature — POSITIVE evidence, the exclusion SCOPED (RULE B, v27,
  /// Run 057 S2/O4/O5: v26 excluded a temperature for an oven or bake word
  /// ANYWHERE in the sentence, so "drain on a baking sheet", "baking soda"
  /// or "roasted peanut" beside a real fry counted the oil whole, and its
  /// closed lead list missed "reads 350", "at 350", "between 350 and 375",
  /// "350–375"). A temperature ([_fryingTemperature]) is excluded only when
  /// an appliance or method GOVERNS it:
  /// - its CLAUSE — from the LATEST boundary at or before it (RULE B, v29:
  ///   a clause mark ; , — ( ), an "and"/"then" opening a new verb phrase,
  ///   or the fat's own mention ([_HeatReading.boundaries], [_HeatReading.
  ///   fatOf]); never the evidence's own heat verb, v28) — names, anywhere
  ///   before it
  ///   ([_Governing]), an appliance ([_appliances]: an oven, a broiler, a
  ///   grill, an air fryer, a smoker, a slow cooker, a pizza stone, a
  ///   toaster, convection — never a vessel: a Dutch or French oven, an
  ///   oven-safe/-proof pan, a broiler or grill pan) or a method verb
  ///   leading it ([_methodVerbs] then at/to/in: "bake at 375", "heat them
  ///   on the grill to 375"; "baked in", "roasted at" — never an adjective,
  ///   "roasted peppers", nor a vessel: "baking sheet/dish/pan",
  ///   "roasting pan/rack", nor "baking powder/soda"), or
  /// - the words right after it do ([_governedAfter]: "375 degrees in the
  ///   oven", "a 350 degree oven", "to 375 degrees and bake", "and keep
  ///   baking").
  /// Then it is frying heat when "the <fat> temperature" comes before it
  /// ("maintain oil temperature of 325 degrees", 0570), or when the fat's
  /// noun comes before it, it has a lead ([_leadBefore])
  /// and a heat verb ([_heatVerbWords]: heat, reheat, bring, warm, return,
  /// reach, register, read, maintain, keep, hold, fry, deep-fry,
  /// pan-fry) starts in its verb phrase — after the last "and"/"then"
  /// that opens a new one ([_newVerbPhrase]: "Heat the oil and cook the
  /// pitas at 375" is the pitas' heat) and at or before the lead: "Heat
  /// oil in large Dutch oven over medium-high heat to 375 degrees" (0690),
  /// "Return oil to 350 degrees" (0491), "until it registers 375 degrees"
  /// (0233), "when the oil reaches 385 degrees" (0511), "until shimmering
  /// but not smoking (350 degrees)" (0689), "Fry the potatoes in oil at
  /// 350 degrees". A temperature with neither ("toast at 350 degrees") is a
  /// setting, not the fat's heat.
  /// Measured 2026-10-02: each of the library's 67 sentences naming oil
  /// with a 3xx-degree temperature reads true (every one a fry). A sentence
  /// heating oil "until shimmering" or "smoking" with no temperature is no
  /// frying signal: it is a sauté's or a sear's ("until just smoking",
  /// 0450). The range stays 300–399 °F (160–200 °C), judged on the library
  /// (v28, Run 058 O3): 300–450 would read the six corpus sentences naming
  /// a fat with 400–450 °F as written — 0511's and 0672's 400-degree fries
  /// true (their oils already zeroed by the mass rule) — but 0672's
  /// unattributed "Add oil … to 400 degrees" would then hold its eaten
  /// "¼ cup coconut oil" (the buffalo sauce, counted today) as
  /// ambiguous_medium. Linear: one pass per pattern over the (windowed)
  /// sentence whatever its temperatures (`heatClauseChars`), the words
  /// after a temperature bounded.
  ///
  /// A sentence with no [_temperatureDigits] run is never frying heat and
  /// costs one scan; only the rest pay the full check, each counted
  /// (`heatChecks`; the verifier's D2, v26: 32,250 "Stir 3 teaspoons oil
  /// into the sauce." sentences paid ~7 µs each, +300 ms on a member's
  /// matches GET at the caps).
  bool heatsToFry(String s, [_HeatReading Function()? reading]) {
    if (!_temperatureDigits.hasMatch(s)) {
      return false;
    }
    _count('heatChecks');
    // Every whole-sentence pass is the sentence's, read once per index and
    // shared by every fat and caller ([_HeatReading]); a check reads it with
    // one forward pointer per list (a temperature's clause start only moves
    // forward), each pass only as far as the check needs.
    final r = reading == null ? _HeatReading(s) : reading();
    final (:mentions, :own) = r.fatOf(this);
    if (!mentions.has(0)) {
      return false;
    }
    final fat = mentions.items.first;
    _GoverningCursor? governing;
    var verb = 0;
    var bound = 0;
    var said = 0;
    var cut = 0;
    var join = 0;
    var read = 0;
    for (var i = 0; r.temperatures.has(i); i++) {
      final (lead, digits, end) = r.temperatures.items[i];
      // Where the temperature, its lead included, starts.
      final at = lead < 0 ? digits : lead;
      final ownBefore = own >= 0 && own < at;
      if (!ownBefore && (lead < 0 || fat >= at)) {
        continue;
      }
      final verbs = r.verbs.upTo(digits);
      while (verb < verbs.length && verbs[verb].$2 <= digits) {
        verb++;
        read++;
      }
      // The clause holding the temperature starts at the LATEST boundary at
      // or before its lead ([_HeatReading.boundaries]: a clause mark or an
      // "and"/"then" opening a new verb phrase, never one opening on the
      // evidence's own heat verb) or the fat's own mention (RULE B, v29,
      // Run 059 O7/S9: v28 cut only at a mark, so "Place a rack in the oven
      // and heat the oil to 350" or "…oven, heating the oil to 350" gave
      // the oven the fat's own temperature; the participle exception is
      // deleted — a phrase opening on any non-fry heat verb continues its
      // clause, and the fat's mention inside it is the boundary). A lead's
      // own "(" opens the clause ("beside the oven (350 degrees)"); a
      // boundary inside a lead ("between 350 and 375") none. An appliance
      // or a method governs it only from inside, before it (after it is
      // [_governedAfter]'s).
      final bounds = r.boundaries.upTo(at);
      while (bound < bounds.length && bounds[bound].$1 <= at) {
        final (p, isCut, opener) = bounds[bound++];
        cut = isCut ? p : cut;
        join = opener ? p : join;
        read++;
      }
      final named = mentions.upTo(at);
      while (said < named.length && named[said] + head.length <= at) {
        said++;
        read++;
      }
      final start = s.codeUnitAt(at) == 0x28
          ? at + 1
          : max(cut, said == 0 ? 0 : named[said - 1] + head.length);
      governing ??= _GoverningCursor(r.governingFrom(start));
      if (governing.governs(start, digits) ||
          _governedAfter.matchAsPrefix(s, end) != null) {
        continue;
      }
      if (ownBefore) {
        _count('heatClauseChars', read);
        return true;
      }
      // The last heat verb starting at or before the lead (it may be the
      // lead itself: "when the oil reaches 385"), in the lead's verb phrase.
      var last = verb;
      while (last > 0 && verbs[last - 1].$1 > at) {
        last--;
        read++;
      }
      if (last > 0 && verbs[last - 1].$1 >= join) {
        _count('heatClauseChars', read);
        return true;
      }
    }
    _count('heatClauseChars', read);
    return false;
  }
}

/// Where the whole word [w] starts in [s] (`\bw\b`), each — a plain
/// search with a boundary check (the regex's scan cost a sentence ~0.5 µs
/// more: the verifier's D11, v27).
Iterable<int> _wordStarts(String s, String w) sync* {
  for (var i = s.indexOf(w); i >= 0; i = s.indexOf(w, i + 1)) {
    final end = i + w.length;
    if ((i == 0 || !_isWordUnit(s.codeUnitAt(i - 1))) &&
        (end == s.length || !_isWordUnit(s.codeUnitAt(end)))) {
      yield i;
    }
  }
}

/// A regex `\w` code unit: a-z, A-Z, 0-9, _.
bool _isWordUnit(int c) =>
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5f;

/// The plain text every [_Fat.temperature] match contains — its prefilter.
const String _temperatureWords = ' temperature';

/// A frying temperature in every spelling a recipe writes (Run 056 Opus
/// critic 2; Run 057 S13): 300–399 Fahrenheit as "350 degrees" (so "350
/// degrees F" and "350 degrees Fahrenheit"), "350 degree", "350 deg",
/// "350 deg. F", "350 Fahrenheit", "350°F", "350° F", "350 °F", "350°",
/// "350F" — the degree sign typed as °, º or ˚ — and the Celsius frying
/// range 160–200 as "180°C", "180° C", "180 °C", "180 degrees C",
/// "180 degrees Celsius", "180 deg C", "180 Celsius" or "180C" — never
/// "350 for" or "180 cups" (no letter may follow). Group 1 is the lead
/// that makes it the fat's heat ([_Fat.heatsToFry]): "to", "until",
/// "register(s/ed)", "reach(es/ed)", "read(s)", "is", "at", "a temperature
/// of", "(", "between 350 and", a range's first end ("350–", "350-"; "350
/// to" is "to") — each with an "about", "around", "approximately",
/// "approx." or "roughly" between.
final RegExp _fryingTemperature = RegExp(
  '(?<![\\w.])(?:3\\d\\d\\s?(?:$_degree\\s?f?|f|fahrenheit)'
  '|(?:1[6-9]\\d|200)\\s?(?:$_degree\\s?(?:celsius|c)|c|celsius))(?![a-z])',
);

/// A [_fryingTemperature]'s lead, ending right before its digits: ONE
/// lookbehind tried at the digits ([_leadStart]), read backwards over the
/// lead alone — never a scan of the text before the temperature trying a
/// lead at every position (v27 closer, the verifier's D11: that scan was
/// ~1.5 µs of every frying sentence, the oil shapes' PUT +100 ms). Group 1
/// is the whole lead, so it starts its length before the digits.
final RegExp _leadBefore = RegExp(
  r'(?<=((?:\bto|\buntil|\bregister(?:s|ed)?|\breach(?:es|ed)?|\breads?|\bis'
  r'|\bat|\ba temperature of|\('
  '|\\bbetween\\s{1,3}$_about\\d{3}\\s?$_degree?\\s{0,3}and'
  '|(?<![\\w.])\\d{3}\\s?$_degree?\\s{0,3}[–-])'
  '\\s{0,3}$_about))',
);

/// Where the lead of the temperature whose digits start at [at] starts in
/// [s] ([_leadBefore]), or -1.
int _leadStart(String s, int at) {
  final m = _leadBefore.matchAsPrefix(s, at);
  return m == null ? -1 : at - m[1]!.length;
}

/// A degree written as a sign (°, º, ˚), "deg", "deg." or "degree(s)" —
/// [_fryingTemperature]'s unit.
const String _degree = r'(?:[°º˚]|deg(?:rees?|\.)?)';

/// An "about" before a temperature ([_fryingTemperature]).
const String _about =
    r'(?:(?:about|around|approximately|approx\.?|roughly)\s{1,3})?';

/// The digits every [_fryingTemperature] spelling starts with — three in a
/// row (3xx Fahrenheit, 160–200 Celsius): the prefilter of
/// [_Fat.heatsToFry]. Keep it in step with that pattern.
final RegExp _temperatureDigits = RegExp(r'\d\d\d');

/// A verb heating the fat ([_Fat.heatsToFry]); "heat" the noun ("over
/// medium heat to 375 degrees") reads the same way. A fry is one unless an
/// air fryer, a stir-fry or an oven-fry ([_HeatVerbs]).
const Set<String> _heatVerbWords = {
  'heat',
  'heats',
  'heated',
  'heating',
  'reheat',
  'reheats',
  'reheated',
  'reheating',
  'bring',
  'brings',
  'bringing',
  'brought',
  'warm',
  'warms',
  'warmed',
  'warming',
  'return',
  'returns',
  'returned',
  'returning',
  'reach',
  'reaches',
  'reached',
  'reaching',
  'register',
  'registers',
  'registered',
  'registering',
  'read',
  'reads',
  'reading',
  'maintain',
  'maintains',
  'maintained',
  'maintaining',
  'keep',
  'keeps',
  'keeping',
  'kept',
  'hold',
  'holds',
  'holding',
  'held',
  'fry',
  'fries',
  'fried',
  'frying',
};

/// The [_heatVerbWords] of a sentence (lower case) as (start, end), read
/// LAZILY ([upTo]) — whole words (`\b…\b`), a fry not one after "air",
/// "stir" or "oven" and one space or hyphen. A word scan with a set lookup
/// (v27 closer, the verifier's D11: the 14-way alternation scanned ~65 ns
/// a character, ~2 µs of every frying sentence), a word whose first letter
/// starts no heat verb never cut out.
class _HeatVerbs {
  _HeatVerbs(this.s);

  final String s;
  final List<(int, int)> items = [];
  var _i = 0;

  /// [items], holding every heat verb starting at or before [p]; the
  /// characters scanned counted (`heatClauseChars`).
  List<(int, int)> upTo(int p) {
    final from = _i;
    while (_i < s.length && _i <= p) {
      _i = _word(_i);
    }
    if (_i > from) {
      _count('heatClauseChars', _i - from);
    }
    return items;
  }

  /// Reads the word (or the one other character) at [start]; returns
  /// where the next starts.
  int _word(int start) {
    if (!_isWordUnit(s.codeUnitAt(start))) {
      return start + 1;
    }
    var i = start;
    while (i < s.length && _isWordUnit(s.codeUnitAt(i))) {
      i++;
    }
    if (i - start < 3 ||
        i - start > 11 ||
        !_heatVerbInitials.contains(s.codeUnitAt(start))) {
      return i;
    }
    final word = s.substring(start, i);
    if (!_heatVerbWords.contains(word)) {
      return i;
    }
    if (word.startsWith('fr') && start >= 2) {
      final sep = s.codeUnitAt(start - 1);
      var p = start - 1;
      while (p > 0 && _isWordUnit(s.codeUnitAt(p - 1))) {
        p--;
      }
      if ((sep == 0x20 || sep == 0x2d) &&
          const {'air', 'stir', 'oven'}.contains(s.substring(p, start - 1))) {
        return i;
      }
    }
    items.add((start, i));
    return i;
  }
}

/// The first letters of [_heatVerbWords].
final Set<int> _heatVerbInitials = {
  for (final w in _heatVerbWords) w.codeUnitAt(0),
};

/// One whole-sentence pass of a [_HeatReading], read LAZILY: its items are
/// fetched only as far as a check asks, once per sentence whatever the
/// fats and callers, and the characters it has reached are counted
/// (`heatClauseChars`) — a sentence that answers at its first temperature
/// pays its prefix (v27 read a lead window and one clause; v28 read the
/// whole sentence four times per fat per caller: Run 059 S15).
class _Pass<T> {
  _Pass(this._length, Iterable<T> items, this._endOf) : _it = items.iterator;

  final int _length;
  final Iterator<T> _it;
  final int Function(T) _endOf;
  final List<T> items = [];
  var _reached = 0;
  var _done = false;

  /// [items], holding every item that ends at or before [p].
  List<T> upTo(int p) {
    while (!_done && _reached <= p) {
      _next();
    }
    return items;
  }

  /// Whether item [i] exists, fetching up to it.
  bool has(int i) {
    while (!_done && items.length <= i) {
      _next();
    }
    return i < items.length;
  }

  void _next() {
    final more = _it.moveNext();
    if (more) {
      items.add(_it.current);
    } else {
      _done = true;
    }
    final to = more ? _endOf(_it.current) : _length;
    if (to > _reached) {
      _count('heatClauseChars', to - _reached);
      _reached = to;
    }
  }
}

/// One sentence's heat reading — every whole-sentence pass of
/// [_Fat.heatsToFry], ONE per sentence per [_StepIndex], shared by every
/// fat and every caller (RULE B, v29, Run 059 S15 / Sonnet critic 2: v28
/// rebuilt its four lists per fat per caller, 2–4× v27 on a long sentence
/// of one temperature). Each pass is a [_Pass], read as far as a check
/// needs; the governing words are read from the clause's start
/// ([governingFrom]).
class _HeatReading {
  _HeatReading(this.s);

  final String s;

  /// Each frying temperature ([_fryingTemperature]): its lead's start
  /// ([_leadStart], -1 for none), its digits, its end.
  late final _Pass<(int, int, int)> temperatures = _Pass(
    s.length,
    _fryingTemperature
        .allMatches(s)
        .map((d) => (_leadStart(s, d.start), d.start, d.end)),
    (t) => t.$3,
  );

  /// The heat verbs ([_HeatVerbs]).
  late final _HeatVerbs verbs = _HeatVerbs(s);

  /// Where a clause may start, in order: (offset, a cut, an opener).
  /// After a clause mark or a new verb phrase's "and"/"then"
  /// ([_clauseBoundary]); a CUT unless the phrase opening there starts with
  /// a heat verb other than a fry (after an "and" or "then"), the
  /// evidence's own word, its object unnamed: "in the smoker, holding it at
  /// 300", "on the pizza stone and heat it at 350" stay the appliance's
  /// clause, while "warm in the oven and fry the rest at 350" is the
  /// fat's. The fat's own mention is the other boundary ([fatOf]): ",
  /// heating the oil to 350" is the oil's. An opener also starts the
  /// evidence's verb phrase ([_newVerbPhrase]).
  late final _Pass<(int, bool, bool)> boundaries = _Pass(
    s.length,
    _boundariesIn(),
    (b) => b.$1,
  );

  Iterable<(int, bool, bool)> _boundariesIn() sync* {
    var v = 0;
    for (final m in _clauseBoundary.allMatches(s)) {
      final opener = m[1] != null;
      var p = m.end;
      while (p < s.length && s.codeUnitAt(p) == 0x20) {
        p++;
      }
      if (!opener) {
        final next = _newVerbPhrase.matchAsPrefix(s, p);
        if (next != null) {
          p = next.end;
        }
      }
      final heat = verbs.upTo(p);
      while (v < heat.length && heat[v].$1 < p) {
        v++;
        _count('heatClauseChars');
      }
      // A fry verb's phrase is the fat's own (nothing else fries: the
      // air-, oven- and stir-fry are no fry, [_HeatVerbs]).
      final cut = v >= heat.length || heat[v].$1 != p || s.startsWith('fr', p);
      yield (m.end, cut, opener);
    }
  }

  _Governing? _governing;

  /// The governing words from [start] on — the earliest clause start a
  /// check has asked for: a later start reads the same scan, an earlier one
  /// (another fat's clause) rescans from it (at most once per fat).
  _Governing governingFrom(int start) {
    final g = _governing;
    if (g != null && g.from <= start) {
      return g;
    }
    return _governing = _Governing(s, start);
  }

  final Map<String, ({_Pass<int> mentions, int own})> _fats = {};

  /// Where [fat]'s noun starts, each whole word ([_Fat.word]), and its
  /// "<fat> temperature" ([_Fat.temperature], -1 for none).
  ({_Pass<int> mentions, int own}) fatOf(_Fat fat) => _fats[fat.head] ??= (
    mentions: _Pass(
      s.length,
      _wordStarts(s, fat.head),
      (at) => at + fat.head.length,
    ),
    // A plain `contains` first: the regex costs a scan of the sentence.
    own: s.contains(_temperatureWords) ? _ownAt(s, fat) : -1,
  );
}

/// Where [fat]'s "<fat> temperature" starts in [s] (counted).
int _ownAt(String s, _Fat fat) {
  _count('heatClauseChars', s.length);
  return s.indexOf(fat.temperature);
}

/// A clause mark ([_HeatReading.boundaries]: ; , — ( )) or, group 1, an
/// "and" or "then" opening a new verb phrase ([_newVerbPhrase]) — one pass.
final RegExp _clauseBoundary = RegExp(
  '[;,—()]|(${_newVerbPhrase.pattern})',
);

/// An "and" or "then" opening a new verb phrase ([_Fat.heatsToFry]): not
/// before an article ("the oil and the butter"). The "and" of "between 350
/// and 375" is inside its temperature's lead, after the lead's start.
final RegExp _newVerbPhrase = RegExp(
  r'\b(?:and|then)\s+(?!(?:the|a|an|its)\b)',
);

/// A heat that is not a fat's ([_Fat.heatsToFry]): an oven, a broiler, a
/// grill, an air fryer, a smoker, a slow cooker, a pizza stone, a toaster,
/// a convection setting — never a VESSEL a fat fries in (RULE B, v28, Run
/// 058 S7 and S31(b), the deferred class): a Dutch or French oven
/// ("Dutch-oven" too), an oven-safe, oven safe, oven-proof or oven proof
/// pan ("ovenproof" and "ovensafe" are no "oven"), a broiler or grill pan,
/// a broiler-, grill-safe or -proof pan; the method words' vessels ("baking
/// sheet/pan/dish", "roasting pan", "broiling pan") are [_methodVerbs']; a
/// "sheet pan" or "pizza pan" names no appliance.
/// Each starts with `\b` ([_governingWord] factors it out).
const List<String> _applianceWords = [
  r'\boven\b(?<!(?:dutch|french)[- ]oven)(?![- ]?(?:safe|proof)\b)',
  r'\bbroiler\b(?![- ]?(?:safe|proof)\b|(?:\s+|-)pans?\b)',
  r'\bgrill\b(?![- ]?(?:safe|proof)\b|(?:\s+|-)pans?\b)',
  r'\bair[- ]?fr',
  r'\bsmoker\b',
  r'\bslow[- ]cooker\b',
  r'\bpizza stone\b',
  r'\btoaster\b',
  r'\bconvection\b',
];
final String _appliances = _applianceWords.join('|');

/// A method verb that leads its own temperature ([_Governing]); never
/// one naming a vessel — "baking sheet/dish/pan", "roasting pan/rack",
/// "broiling pan" (a roasting pan over two burners fries: the verifier's
/// D8, v27) — nor "baking powder/soda".
const String _methodVerbs =
    r'\b(?:bak(?:e|es|ing)|roast(?:s|ing)?|broil(?:s|ing)?)\b'
    r'(?!(?:\s+|-)(?:sheet|powder|soda|dish|pan|rack|tray)s?\b)';

/// Every word that can govern a temperature, in ONE pattern ([_Governing]):
/// group 1 an appliance ([_appliances]), group 2 a method's past participle
/// directly leading ("baked in", "roasted at" — never an adjective,
/// "roasted peppers"), group 3 a method verb ([_methodVerbs]), group 4 a
/// method's lead (at, to, in).
/// Every alternative starts at a word start: the `\b` is factored out
/// (one test per position, not one per alternative: 2.3 → 1.8 µs over
/// 0690's frying sentence).
final RegExp _governingWord = RegExp(
  '\\b(?:(${[for (final a in _applianceWords) a.substring(2)].join('|')})'
  r'|((?:bak|roast|broil|grill)ed\s+(?:at|to|in)\b)'
  '|(${_methodVerbs.substring(2)})'
  r'|((?:at|to|in)\b))',
);

/// The words of one sentence that can govern a temperature
/// ([_governingWord]), located ONCE (RULE B, v28, Run 058 S5/S9: v27 read
/// the clause's text again for each temperature, quadratic in a sentence of
/// many temperatures — "to 350° to 350° …" 1.2 ms where v26 took 0.15).
/// [_GoverningCursor.governs] answers each temperature from the lists with
/// one forward pointer per list (a clause's start and end only move
/// forward). Read lazily from [from] (v29, Run 059 S15: the earliest clause
/// start asked, as v27 read only the clause) up to the temperature, the
/// characters reached counted (`heatClauseChars`).
class _Governing {
  _Governing(this.s, this.from)
    : _it = _governingWord.allMatches(s, from).iterator,
      _reached = from;

  final String s;

  /// Where the scan starts: the clause start it was asked for.
  final int from;
  final Iterator<Match> _it;
  int _reached;
  var _done = false;
  final _appliance = <(int, int)>[];
  final _past = <(int, int)>[];
  final _method = <(int, int)>[];
  final _lead = <(int, int)>[];

  /// Reads the words ending at or before [p] (and the next), counting the
  /// characters reached (`heatClauseChars`).
  void upTo(int p) {
    while (!_done && _reached <= p) {
      final more = _it.moveNext();
      var to = s.length;
      if (more) {
        final m = _it.current;
        (m[1] != null
                ? _appliance
                : m[2] != null
                ? _past
                : m[3] != null
                ? _method
                : _lead)
            .add((m.start, m.end));
        to = m.end;
      } else {
        _done = true;
      }
      if (to > _reached) {
        _count('heatClauseChars', to - _reached);
        _reached = to;
      }
    }
  }
}

/// One check's forward pointers over a sentence's [_Governing] lists — the
/// lists are the sentence's, shared ([_HeatReading]); the pointers the
/// check's.
class _GoverningCursor {
  _GoverningCursor(this._g);

  final _Governing _g;
  var _a = 0;
  var _p = 0;
  var _m = 0;
  var _l = 0;

  /// Whether the clause text from [start] to [end] (a temperature's digits)
  /// names an appliance, a method's past participle leading, or a method
  /// verb its lead follows ("bake … at"). [start] and [end] never decrease
  /// from one call to the next.
  bool governs(int start, int end) {
    _g.upTo(end);
    final _Governing(:_appliance, :_past, :_method, :_lead) = _g;
    var read = 0;
    while (_a < _appliance.length && _appliance[_a].$1 < start) {
      _a++;
      read++;
    }
    while (_p < _past.length && _past[_p].$1 < start) {
      _p++;
      read++;
    }
    while (_m < _method.length && _method[_m].$1 < start) {
      _m++;
      read++;
    }
    var governed =
        (_a < _appliance.length && _appliance[_a].$2 <= end) ||
        (_p < _past.length && _past[_p].$2 <= end);
    // A lead starts after its verb, so one before [end] means the verb is.
    if (!governed && _m < _method.length) {
      final after = _method[_m].$2;
      while (_l < _lead.length && _lead[_l].$1 < after) {
        _l++;
        read++;
      }
      governed = _l < _lead.length && _lead[_l].$2 <= end;
    }
    if (read > 0) {
      _count('heatClauseChars', read);
    }
    return governed;
  }
}

/// The words right after a temperature that make it an appliance's or a
/// method's ([_Fat.heatsToFry]): "in the oven", "under the broiler", "on
/// a pizza stone" (three words at most between, inside the temperature's
/// clause: a word is never a heat verb — "to 375 degrees in pot and reheat
/// oven" is the oven's own clause, the verifier's D8, v27 — and a clause
/// mark ends the words), a bare "oven" ("a 350 degree oven"), "and bake",
/// "then roast", "and keep baking".
final RegExp _governedAfter = RegExp(
  r'\s{0,3}(?:fahrenheit\s{0,3})?'
  r'(?:(?:(?:in|on|under|inside)\s+'
  '(?:(?!(?:${_heatVerbWords.join('|')})\\b)[\\w-]+\\s+){0,3}?)?(?:'
  '$_appliances'
  r')|(?:and\s+(?:then\s+)?|then\s+)(?:(?:keep|continue)\s+)?'
  '$_methodVerbs)',
);

/// [_Fat.heatsToFry] for the tests: [sentence] as written, [head] a fat.
@visibleForTesting
bool heatsFatToFryForTest(String sentence, String head) =>
    _fats[head]?.heatsToFry(sentence.toLowerCase()) ?? false;

/// [_Fat.heatsToFry] of each of [heads] on ONE shared reading of
/// [sentence], in order — the per-sentence memo's sharing, for the tests.
@visibleForTesting
List<bool> heatsFatsToFryForTest(String sentence, List<String> heads) {
  final s = sentence.toLowerCase();
  final r = _HeatReading(s);
  return [for (final h in heads) _fats[h]!.heatsToFry(s, () => r)];
}

/// The heat reading of sentence [s] of [recipe]'s steps, once per index
/// ([_HeatReading]).
_HeatReading _heatReading(Recipe recipe, String s) =>
    _stepIndexOf(recipe).memo(('heatReading', s), () => _HeatReading(s));

/// What the frying sentences of a recipe say of each of its oil lines
/// ([_oilOwnersOf]): the sentences a line owns, or the sentence it shares
/// with another line (`ambiguous`).
typedef _OilOwner = ({String? pourOff, String? ambiguous});

/// The fat lines of [head] (by raw) that [recipe]'s frying evidence
/// belongs to — ONE rule for every frying fat ([_fats]: oil, shortening,
/// lard; any other head owns nothing) and every line of it (RULE B, Run 055
/// S1/S2/O1: v24 read any sentence naming "oil" as every ≥ ¼-cup oil
/// line's own, so a typed dressing or aioli beside a fry was zeroed and a
/// kept part counted once per oil line). The evidence: a sentence heating
/// the fat to a frying temperature ([_Fat.heatsToFry]), discarding it
/// ([_Fat.discards]) or pouring off all but a kept part
/// ([_Fat.pourOffAllBut]) — each read with the line's OWN fat noun (Run 056
/// O3) — and a fried food's held dredge ([_dredge], which names no fat). A
/// sentence belongs to a line that it names by its own written amount
/// ("Heat 3 cups oil") or by a word of its kind ("Heat the peanut oil"
/// beside an olive oil), the fat's noun phrase following directly
/// ([_oilPhraseFollows]). A binding key — an amount or a kind word — two
/// lines share binds NEITHER (Run 056 O2/S3: a shared "¾ cup" bound both
/// lines, both zeroed), and lines are counted by POSITION, so two identical
/// raws are two lines. A smaller line's sentence fries no other line. A
/// sentence that names none belongs to the one frying CANDIDATE — every
/// line the mass rule could zero ([_couldZero], RULE B v27: ¼ cup or more
/// in either unit family, its "plus" part included, a resolved
/// [_fryingGrams] or more — "1 (48-ounce) bottle" — or a "for (pan-)
/// frying" label with any amount or none: "Vegetable oil, for pan-frying",
/// 0357; an amount-less line weighs nothing and is never zeroed or held
/// by a sentence) — or to the one such candidate a sentence
/// named; with two or more it could be either's, and each is held for a
/// person (`ambiguous_medium`, the sentence its `hold_note`) rather than
/// zeroed (a heat or discard sentence beside two NAMED fried fats adds
/// nothing, and is not held). Two identical raws read the same: the map is
/// by raw. Once per recipe and head.
Map<String, _OilOwner> _oilOwnersOf(Recipe recipe, String head) {
  final fat = _fats[head];
  if (fat == null) {
    return const <String, _OilOwner>{};
  }
  final index = _stepIndexOf(recipe);
  // Key: head — the fat: its lines, its noun and its patterns ([_fats]).
  return index.memo(('oilOwners', head), () {
    final heads = _headsOf(recipe);
    final lines = [
      for (final (i, l) in nutritionLines(recipe).indexed)
        if (heads[i] == head) l,
    ];
    // Positions in [lines] with an amount the mass rule could zero.
    final big = [
      for (final (i, l) in lines.indexed)
        if (l.amounts.isNotEmpty && _couldZero(l)) i,
    ];
    if (big.isEmpty) {
      return const <String, _OilOwner>{};
    }
    // The binding words, looked up per word of a sentence (RULE C: never
    // every line's pattern over every sentence): each line's written
    // amount and kind words — a key two lines share binds neither.
    final keyOf = [for (final l in lines) _amountKey(_amountText(l) ?? '')];
    final kindsOf = [for (final l in lines) _kindWords(l, head)];
    final byAmount = <String, Set<int>>{};
    final byKind = <String, Set<int>>{};
    for (final (i, key) in keyOf.indexed) {
      if (key != null) {
        (byAmount[key] ??= {}).add(i);
      }
      for (final w in kindsOf[i]) {
        (byKind[w] ??= {}).add(i);
      }
    }
    byAmount.removeWhere((_, at) => at.length > 1);
    byKind.removeWhere((_, at) => at.length > 1);
    // Every kind word of every line: the words allowed between an amount
    // (or a kind word) and the fat's noun in a binding sentence.
    final kinds = {for (final k in kindsOf) ...k};
    // RULE C (v26, Run 056 O8: each frying sentence was appended to every
    // line it binds — 36,000 sentences × 400 lines of one amount, ~1 s a
    // GET): a sentence binds GROUPS — an amount ('a:') or a kind word
    // ('k:') — and each group's first binding and first pour-off are read
    // once; a line owns what its groups bound (below).
    final bound = <String, int>{};
    final pours = <String, (int, String)>{};
    var order = 0;
    final unbound = <((int, int)?, bool)>[];
    // v57 (M59 C): a sentence after [at] heats the reserved fat.
    bool reused((int, int) at) => [
      ...index.sentences[at.$1].skip(at.$2 + 1),
      for (final step in index.sentences.skip(at.$1 + 1)) ...step,
    ].any(fat.heatsReserved.hasMatch);
    for (final at in _naming(recipe, head)) {
      final s = index.sentence(at);
      final pourOff =
          fat.keptPart(s) != null ||
          (fat.reserveFrying.hasMatch(s) && reused(at));
      if (!pourOff &&
          !fat.heatsToFry(s, () => _heatReading(recipe, s)) &&
          !fat.discards.hasMatch(s)) {
        continue;
      }
      // A pour-off's kept part names no line's amount ("all but 2
      // tablespoons oil" beside a 2-tablespoon sesame oil).
      final said = pourOff
          ? s
                .replaceAll(fat.pourOffAllBut, '')
                .replaceAll(fat.reserveRest, '')
                .replaceAll(fat.reserveFrying, '')
          : s;
      // Only the fat's own amount or kind word: its noun phrase must
      // FOLLOW directly ([_oilPhraseFollows]; Run 055 V3: "Stir 2
      // tablespoons lime juice …, then heat the oil" bound the fry to a
      // 2-tablespoon oil line; its close V3b: "2 tablespoons butter to the
      // oil" still did, through a 30-character window).
      bool follows(Match m) => _oilPhraseFollows(said, m.end, kinds, head);
      final groups = {
        for (final m in _writtenAmount.allMatches(said))
          if (_amountKey(m[0]!) case final key?
              when byAmount.containsKey(key) && follows(m))
            'a:$key',
        for (final m in _kindWord.allMatches(said))
          if (byKind.containsKey(m[0]) && follows(m)) 'k:${m[0]}',
      };
      if (groups.isEmpty) {
        unbound.add((at, pourOff));
      }
      for (final group in groups) {
        bound.putIfAbsent(group, () => order);
        if (pourOff) {
          pours.putIfAbsent(group, () => (order, s));
        }
      }
      order++;
    }
    // Each line's groups: its amount and its kind words no other line
    // shares. A line any of its groups bound is owned; the first of their
    // pour-offs, in sentence order, is the part it keeps.
    final owned = <int, String?>{};
    final firstPour = <int, int>{};
    for (final (i, key) in keyOf.indexed) {
      for (final g in [
        if (key != null && byAmount.containsKey(key)) 'a:$key',
        for (final w in kindsOf[i])
          if (byKind.containsKey(w)) 'k:$w',
      ]) {
        if (!bound.containsKey(g)) {
          continue;
        }
        owned.putIfAbsent(i, () => null);
        if (pours[g] case (
          final at,
          final sentence,
        ) when at < (firstPour[i] ?? order)) {
          firstPour[i] = at;
          owned[i] = sentence;
        }
      }
    }
    // v31 (the owner's R4 ruling, 2026-10-03): a fat no sentence of its
    // own fries — none names it with a frying heat, a discard or a pour-off
    // — in a recipe whose evidence is the fry VERB ("pan-fry until the
    // outsides are crisp", 0288; "Fry until golden brown", 0674, 0675) is a
    // shallow fry the food soaks some of up: each candidate is held for a
    // person, the verb's sentence its note — never zeroed by a dredge
    // (0288's flour) nor counted whole. Not when the mass rule already
    // zeroes a line of the fat: the verb is that oil's (0672 Buffalo
    // Cauliflower Bites fries in "1–2 quarts peanut or vegetable oil"; its
    // "¼ cup coconut oil" is the sauce, eaten).
    // v53 (M52 Q24 b): a coated food browned in the oil is fried in it
    // ([_shallowFries]) — never held for the verb.
    final verb = order == 0 && !lines.any(_massZeroes) && !_shallowFries(recipe)
        ? _fryVerbAt(recipe)
        : null;
    if (verb == null &&
        _fries(recipe) &&
        (_dredgedIn(recipe) || _shallowFries(recipe))) {
      unbound.add((null, false));
    }
    // Who could own a sentence that names no line: the frying candidates
    // (above) — the ones a sentence named if any; a smaller line a
    // sentence names keeps only that sentence. Sets, never a list scan per
    // line (RULE C, v26, Run 056 O8/S9).
    final bigs = big.toSet();
    final candidates = [
      ...big,
      for (final (i, l) in lines.indexed)
        if (!bigs.contains(i) &&
            l.amounts.isEmpty &&
            _labelledFrying.hasMatch(l.raw))
          i,
    ];
    final candidate = candidates.toSet();
    final named = [
      for (final i in owned.keys)
        if (candidate.contains(i)) i,
    ];
    final could = named.isNotEmpty ? named : candidates;
    final ambiguous = <int, String>{};
    if (verb != null) {
      final note = '"${_rawSentence(index, verb)}"';
      for (final i in candidates) {
        ambiguous[i] = note;
      }
    } else if (could.length == 1) {
      // The one candidate owns them all, after its bound sentences: its
      // first pour-off stands, else the first of theirs.
      final single = could.single;
      for (final (at, pourOff) in unbound) {
        if (!owned.containsKey(single)) {
          owned[single] = null;
        }
        if (owned[single] == null && pourOff) {
          owned[single] = index.sentence(at!);
        }
      }
    } else {
      // The FIRST such sentence is each candidate's note: attached once,
      // never once per unbound sentence per candidate (RULE C, v26, Run
      // 056 O8/S9: 36,000 frying sentences × 400 candidates).
      for (final (at, pourOff) in unbound) {
        if (named.isEmpty || pourOff) {
          final note = at == null
              ? 'a fried food is dredged in a step'
              : '"${_rawSentence(index, at)}"';
          for (final i in could) {
            ambiguous[i] = note;
          }
          break;
        }
      }
    }
    return {
      for (final i in {...owned.keys, ...ambiguous.keys})
        if (bigs.contains(i))
          lines[i].raw: (pourOff: owned[i], ambiguous: ambiguous[i]),
    };
  });
}

/// The words of [line]'s oil kind, before its [head] ("extra-virgin
/// olive", "toasted sesame", "peanut or vegetable") — [_oilOwnersOf].
Set<String> _kindWords(IngredientLine line, String head) {
  final item = lineItemOf(line).toLowerCase();
  final at = item.indexOf(RegExp('\\b${RegExp.escape(head)}\\b'));
  return {
    for (final w in RegExp('[a-z][a-z-]*').allMatches(
      at < 0 ? '' : item.substring(0, at),
    ))
      if (!const {'or', 'and', 'of', 'the', 'a'}.contains(w[0])) w[0]!,
  };
}

/// Whether the fat's noun phrase follows [from] in [sentence] directly:
/// zero or more of "of", "the", "a" and the recipe's own kind words of the
/// fat ([kinds]: vegetable, olive, peanut, …), then the fat's noun [head]
/// ("oil", "shortening", "lard" — [_fats]). "2 tablespoons oil",
/// "¾ cup of the vegetable oil" bind; "2 tablespoons butter to the oil" and
/// "2 tablespoons lime juice into the oil" do not — another food's word
/// stands between ([_oilOwnersOf]). Linear: at most eight words read.
bool _oilPhraseFollows(
  String sentence,
  int from,
  Set<String> kinds,
  String head,
) {
  var at = from;
  for (var words = 0; words < 8; words++) {
    final m = _kindWord.matchAsPrefix(sentence, _skipSpaces(sentence, at));
    if (m == null) {
      return false;
    }
    final w = m[0]!;
    if (w == head) {
      return true;
    }
    if (w != 'of' && w != 'the' && w != 'a' && !kinds.contains(w)) {
      return false;
    }
    at = m.end;
  }
  return false;
}

int _skipSpaces(String s, int from) {
  var at = from;
  while (at < s.length && s.codeUnitAt(at) == 0x20) {
    at++;
  }
  return at;
}

/// [line]'s written amount, as a step would name it ("3 cups", "¾ cup"),
/// or null — the raw before its item ([_oilOwnersOf]).
String? _amountText(IngredientLine line) {
  if (line.amounts.isEmpty) {
    return null;
  }
  final raw = line.raw.toLowerCase();
  final at = raw.indexOf(lineItemOf(line).toLowerCase());
  final amount = at <= 0 ? '' : raw.substring(0, at).trim();
  return amount.isEmpty ? null : amount;
}

/// An amount as a step writes it ("3 cups", "1¾ cups") — [_amountKey].
/// Every run bounded: linear in the sentence.
final RegExp _writtenAmount = RegExp(
  '(?<![\\w/⁄.$vulgarFractionChars-])[\\d$vulgarFractionChars]'
  '[\\d/⁄.$vulgarFractionChars]{0,8}'
  '(?:[\\s-][\\d/⁄.$vulgarFractionChars]{1,8})?'
  r'\s{1,3}[a-z]{1,20}',
);

/// A word of a sentence ([_oilOwnersOf]'s kind lookup).
final RegExp _kindWord = RegExp('[a-z][a-z-]*');

/// [amount]'s lookup key when the whole text is one [_writtenAmount] — spaces
/// collapsed, a plural unit singular — else null.
String? _amountKey(String amount) {
  final text = amount.toLowerCase().trim();
  final run = _writtenAmount.matchAsPrefix(text);
  if (run == null || run.end != text.length) {
    return null;
  }
  final key = text.replaceAll(RegExp(r'\s+'), ' ');
  return key.endsWith('s') ? key.substring(0, key.length - 1) : key;
}

/// The sentence at [at] as written (for a `hold_note`). No memo: since
/// the note is attached once per [_oilOwnersOf] derivation (RULE C, v26,
/// Run 056 O8), this runs once per recipe and head, so a memo bounded
/// nothing (the verifier's survivor: deleting it left every test green).
/// Each split is counted (`rawSentences`).
String _rawSentence(_StepIndex index, (int, int) at) {
  _count('rawSentences');
  final sentences = index.raw[at.$1].split(_sentenceBreak);
  return at.$2 < sentences.length
      ? sentences[at.$2].trim()
      : index.sentence(at).trim();
}

/// An oil line written for frying, any kind ("for pan-frying", "for deep
/// frying") — [_oilOwnersOf].
final RegExp _labelledFrying = RegExp(
  r'\bfor (?:pan-|shallow-|deep[- ]?)?fry',
  caseSensitive: false,
);

/// Whether [recipe]'s bread line [raw] is the crumbs of its held breading
/// (v31, B4; every held dredge since v33, D2): the recipe holds a dredge
/// ([_dredgedIn]), the bread is processed — a step puts it through the
/// processor ("Process the dry bread in a food processor to very fine
/// crumbs", 0233 Pork Schnitzel; "pulse the bread in a food processor to
/// coarse crumbs", 0206; "Add half of the bread to a food processor and
/// pulse", 0122 Kiev) or the line itself says so ("4 slices … bread,
/// pulsed in a food processor to coarse crumbs and dried", 0118) — and
/// the crumbs form the coat: a dredge sentence sets them out ("Transfer
/// the bread crumbs to a shallow dish") or a sentence coats the food with
/// them ("Coat all sides of the chop with the bread-crumb mixture", 0206,
/// 0254, 0407, 0122). The flour was held while the crumbs of the same coat
/// counted (140 g, 84 g). A coat part that is not bread or a dredge head —
/// nuts, cheese, Melba toast, saltines, potato chips, cornflakes — is
/// [_coatLayer]'s (v34). The step tests once per recipe.
bool _crumbsForTheCoat(Recipe recipe, String raw) {
  final index = _stepIndexOf(recipe);
  return _dredgedIn(recipe) &&
      index.memo(#crumbsForTheCoat, () {
        return index.allSentences.any(
          (s) =>
              (s.contains('crumbs') && _dredgeSentence.hasMatch(s)) ||
              _coatsWithCrumbs.hasMatch(s),
        );
      }) &&
      (_processesBread(raw) ||
          index.memo(#processesBread, () {
            return index.allSentences.any(_processesBread);
          }));
}

/// A text naming bread and the food processor ([_crumbsForTheCoat]).
bool _processesBread(String text) =>
    text.contains('bread') && _processor.hasMatch(text);

final RegExp _processor = RegExp(r'\bprocess');

/// A sentence coating a food with crumbs ([_crumbsForTheCoat],
/// [_crumbLineOfTheCoat]).
final RegExp _coatsWithCrumbs = RegExp(r'\bcoat\w*\b[^.]*\bcrumb');

/// Whether a crumb or panko line ([head]; the dredge heads, at the same
/// quarter cup) is the crumbs of [recipe]'s held breading (D2, v33 closer):
/// the recipe holds a dredge ([_dredgedIn]) and a sentence coats the food
/// with crumbs. [_dredge] finds a line only through a sentence naming its
/// own head, and the steps call these crumbs by another name — "1½ cups
/// panko" coated as "the bread crumbs" (0416 Lighter Chicken Parmesan:
/// "Lightly dredge the cutlets in the flour, shaking off the excess …
/// Finally, coat both sides of the chicken with the bread crumbs"), "1 cup
/// panko bread crumbs" set out as "the panko mixture" (0117 Nut-Crusted:
/// "Coat all sides of the breast with the panko mixture, pressing gently so
/// that the crumbs adhere") — so the flour was held while the panko of the
/// same coat counted. Once per recipe.
bool _crumbLineOfTheCoat(
  Recipe recipe,
  String? head,
  double Function() ml,
) {
  if ((head != 'crumb' && head != 'panko') || ml() < _quarterCupMl) {
    return false;
  }
  final index = _stepIndexOf(recipe);
  return _dredgedIn(recipe) &&
      index.memo(#coatsWithCrumbs, () {
        return index.allSentences.any(_coatsWithCrumbs.hasMatch);
      });
}

/// Whether [line] is another LAYER of [recipe]'s coat — nuts, cheese,
/// crackers, chips, cornflakes, Melba toast beside the flour and crumbs
/// (v34, the owner's ruling 2026-10-03 on v33's follow-up, "the narrow
/// version"): a head of [_coatLayerHeads] the guard sizes as more than a
/// pinch ([_layerSized]), named — by its head, or by the kind word its item
/// carries ("parmesan", "saltine": the steps never say "cheese" or
/// "crackers" there) — in a sentence that sets the coat out in its shallow
/// dish or names it with the crumbs ([_layerOfTheCoat]): "Pulse the
/// saltines and chips together …; place in a separate shallow baking dish"
/// (0315), "Whisk ¼ cup of the flour and the ¼ cup grated Parmesan together
/// in a shallow dish" (0419), "add the bread crumbs and ground almonds and
/// cook" (0117), "Process the almonds in a food processor to fine crumbs"
/// (0042), "Transfer the crumbs to a pie plate and stir in the Parmesan"
/// (0407), "Drizzle the oil over the Melba toast crumbs in a pie plate or
/// shallow dish" (0150). L1: the recipe holds a dredge ([_dredgedIn],
/// v33's gate as it stands). L2: or its directions leave an excess of the
/// coat ([_leavesExcess]) — 0150's Melba coat has no flour line to hold,
/// and "Gently shake off the excess" leaves part of it in the dish. Only
/// the first line of its head: the steps name a second one the same way,
/// and a recipe lists a food where it is first used (0407's "1 ounce
/// Parmesan" topping after the coat's 2 ounces, [_firstOfItsHead]). A
/// cheese in a filling no coat sentence names (0118, which holds a dredge),
/// a binder (0000 meatballs) or a sauce (0300), nuts in a filling (0957
/// strudel), chips on the side (0820), a crust no step leaves
/// an excess of (0415, 0041, 0258) stay counted. A row with no food gets no
/// hold — only [engineOutcome] writes one, on a row with a food: 0198's
/// cornflakes, which this reading reaches, stay no match.
bool _coatLayer(
  Recipe recipe,
  IngredientLine line,
  String? head,
  double Function() ml,
  String normalized,
) {
  if (!_coatLayerHeads.contains(head) ||
      !_layerSized(line, ml) ||
      !_firstOfItsHead(recipe, line, head!)) {
    return false;
  }
  final index = _stepIndexOf(recipe);
  return _layerWords(head, normalized).any(
        (word) => _naming(
          recipe,
          word,
        ).any((at) => _layerOfTheCoat.hasMatch(index.sentence(at))),
      ) &&
      (_dredgedIn(recipe) || _leavesExcess(recipe));
}

/// The words a step names a coat layer by ([_coatLayer]): its [head], or
/// the kind word its [normalized] item carries ("parmesan", "saltine": the
/// steps never say "cheese" or "crackers" there).
List<String> _layerWords(String head, String normalized) => [
  head,
  for (final kind in const ['parmesan', 'saltine'])
    if (normalized.contains(kind)) kind,
];

/// v65 (M66 R3, the owner's Q5 (a) GATED, critic F4): whether the coat
/// layer at [position] of [recipe] — a nut or cheese line the coat holds —
/// is MIXED INTO a crumb: one step sentence names both the layer
/// ([_layerWords], [_naming]) and a crumb ([_crumbWord]) — "Process the
/// almonds in a food processor to fine crumbs" (0042; its "Toss the nuts
/// with the panko" is not read: 'nuts' is no layer word), "add the bread
/// crumbs and ground almonds" (0117), "Spread the bread crumbs … ; when
/// cool, stir in the Parmesan" (0416). Then the layer is a part of
/// [_m52Plan]'s budget at the one f; else it stays held — a cheese CRUST
/// with a flour binder (0419: "Combine the 2 cups shredded Parmesan and
/// remaining 1 tablespoon flour") is not the record's breading.
/// ponytail: one sentence must name both — a crumb named only in another
/// sentence of the mixing step leaves the layer held (no corpus recipe);
/// widen to the step if one appears. And a layer ground "to … crumbs"
/// passes whatever it is then mixed with — the nut's OWN crumbs, not a
/// bread crumb (0042 passes only so): a nut layer with a flour-only binder
/// would join the budget too (no corpus recipe); read the crumb outside the
/// "to … crumbs" phrase if one appears.
bool _layerInCrumb(Recipe recipe, int position) {
  final head = _headsOf(recipe)[position];
  if (head == null) {
    return false;
  }
  final index = _stepIndexOf(recipe);
  return _layerWords(
    head,
    normalizeItem(lineItemOf(nutritionLines(recipe)[position])),
  ).any(
    (word) => _naming(
      recipe,
      word,
    ).any((at) => _crumbWord.hasMatch(index.sentence(at))),
  );
}

/// A crumb a coat layer is mixed into ([_layerInCrumb]).
final RegExp _crumbWord = RegExp(
  r'\b(?:bread crumbs|panko|crumbs|crackers)\b',
);

/// The coat's parts outside [_dredgeHeads] ([_coatLayer]).
const Set<String> _coatLayerHeads = {
  'almond',
  'pecan',
  'walnut',
  'pistachio',
  'hazelnut',
  'cashew',
  'peanut',
  'macadamia',
  'nut',
  'cheese',
  'cracker',
  'chip',
  'cornflake',
  'toast',
};

/// A sentence that sets the coat out in its dish or names the layer with
/// the coat's crumbs ([_coatLayer]).
final RegExp _layerOfTheCoat = RegExp(
  r'\bshallow (?:baking )?dish\b|\bcrumbs\b',
);

/// Whether [line] is more than a pinch of a coat layer ([_coatLayer]): a
/// quarter cup or more by volume — or by weight where the density table
/// reads one ([_mediumMl]) — or, with neither, a count ("30 saltine
/// crackers", "1 box (about 5 ounces) plain Melba toast"). A tablespoon or
/// two of Parmesan tossed with the crumbs (0206) is not reached.
bool _layerSized(IngredientLine line, double Function() ml) {
  if (line.amounts.isEmpty) {
    return false;
  }
  final v = ml();
  return v >= _quarterCupMl || (v == 0 && volumeMlOf(line.amounts) == null);
}

/// Whether [recipe] holds a dredge ([_dredge]) — once per recipe.
bool _dredgedIn(Recipe recipe) => _stepIndexOf(recipe).memo(#dredged, () {
  final heads = _headsOf(recipe);
  final steps = _stepIndexOf(recipe).raw;
  return nutritionLines(recipe).indexed.any(
    (e) => _dredge(
      recipe,
      e.$2.raw.toLowerCase(),
      heads[e.$1],
      () => _mediumMl(e.$2, normalizeItem(lineItemOf(e.$2))),
      steps,
    ),
  );
});

/// [line]'s place in [_oilOwnersOf]: frying oil its own sentences fry,
/// discard or pour off ([DiscardedMedium.fryingOil]), one that shares a
/// sentence with another oil line ([DiscardedMedium.ambiguousMedium]), or
/// null. Measured on the library (2026-10-02): the lines v24 read fried
/// alone (0491's and 1193's beyond the oils already frying), none held.
DiscardedMedium? _oilBySentence(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  final owner = head == null ? null : _oilOwnersOf(recipe, head)[line.raw];
  return owner == null
      ? null
      : owner.ambiguous != null
      ? DiscardedMedium.ambiguousMedium
      : DiscardedMedium.fryingOil;
}

/// An oil line's volume in both unit families ([_mediumMl]; shortening and
/// lard at their FDC 0.87, a fat item the table refuses at oil's), its
/// same-food "plus" part included ("1 tablespoon plus ¾ cup vegetable oil",
/// 0114) in both unit families too (v28, Run 058 S20: v27 read the part's
/// volume only, so "2 tablespoons plus 8 ounces vegetable oil" was 29.6
/// mL) — never another food's.
double _oilMl(IngredientLine line) {
  final plus = plusPartOf(line.raw);
  final normalized = normalizeItem(lineItemOf(line));
  return _mediumMl(line, normalized, fat: true) +
      (plus != null && plus.sameFood
          ? _mediumMl(
              IngredientLine(raw: '', item: line.item, amounts: [plus.amount]),
              normalized,
              fat: true,
            )
          : 0);
}

/// Whether the mass rule ([discardedMediumOf]) could zero the frying-fat
/// [line] — ONE reading for [_oilOwnersOf]'s candidacy and the mass rule
/// (RULE B, v27, Run 057 S3/O6 and Sonnet critics 1/2: candidacy read
/// parsed amounts while the rule read resolved grams, so "1 (48-ounce)
/// bottle vegetable oil" or "3 tablespoons vegetable oil, for frying" was
/// zeroed but no candidate, and the aioli beside it was zeroed alone): a
/// "for (pan-/deep-)frying" label ([_labelledFrying], any amount), or ¼
/// cup or more in EITHER unit family ([_oilMl]: ¼ cup = 59.1 mL ≈ 54.4 g
/// of oil at 0.92 g/mL, so "8 ounces vegetable oil" reads like "1 cup",
/// and every line the mass rule's resolved [_fryingGrams] zeroes — 435 mL
/// at that density, "1 (48-ounce) bottle" 1,361 g — is one).
///
/// The mass rule ([_massZeroes]) reads the SAME food-free quantity
/// ([_mediumMl]) and lies inside this by construction — its 400 g is ¼ cup
/// or more at any fat's density (435 mL of oil), its "for (deep) frying" a
/// [_labelledFrying] label — so no term repeats it here (the closer's
/// mutant of one was equivalent). v27 closer, the verifier's D3: the rule
/// read the CALLER's resolved grams, so a reader with none — the matches
/// GET's `held`, the reach, an un-skip ([heldMediumLine]) — held "1
/// (48-ounce) bottle vegetable oil" beside an aioli while the compute
/// zeroed it.
bool _couldZero(IngredientLine line) =>
    _labelledFrying.hasMatch(line.raw) || _oilMl(line) >= _quarterCupMl;

/// The frying-fat mass rule ([discardedMediumOf]): a "for (deep) frying"
/// line ([_forFrying]) or [_fryingGrams] or more of the fat — its grams
/// read with NO food, as every reader can ([_mediumMl]: a written volume
/// at its item's table density (shortening and lard 0.87, v28), oil's 0.92
/// for a fat item the table refuses ("oil-packed sun-dried tomato oil") —
/// 400 g = 435 mL of oil; else a written or printed weight,
/// [_freeGrams]: "1 (48-ounce) bottle" 1,361 g, "24 ounces" 680 g), so the
/// compute, the GET, the reach and the un-skip read ONE answer. The line's
/// own amount, never its "plus" part (the eaten part, [_eatenPlusPart]).
bool _massZeroes(IngredientLine line, [String? normalized]) {
  final item = normalized ?? normalizeItem(lineItemOf(line));
  final density = densityOf(item) ?? densityOf('oil')!;
  return _forFrying.hasMatch(line.raw.toLowerCase()) ||
      _mediumMl(line, item, fat: true) * density >= _fryingGrams;
}

/// [line]'s grams with no food, as the gram rule resolves them
/// ([resolveGrams]: a written weight, a printed paren weight by its count
/// — "1 (48-ounce) bottle" 1,361 g — or a table density), or null.
double? _freeGrams(IngredientLine line, String normalized) =>
    line.amounts.isEmpty
    ? null
    : resolveGrams(
        amounts: line.amounts,
        food: null,
        normalizedItem: normalized,
        raw: line.raw,
      )?.grams;

/// A medium line's volume in BOTH unit families (RULE B, v27, Sonnet
/// critic 1: every medium threshold read `volumeMlOf` only, so a line
/// written by weight skipped them all): its written volume, else its
/// grams ([_freeGrams]) at its item's density ([densityOf]; a frying
/// [fat] item the table refuses at oil's 0.92). Each threshold's mass
/// figure is its volume at that density: ¼ cup of oil 54.4 g, of flour
/// 30.2 g (0.51), of panko 14.8 g (0.25), of bread crumbs 26.6 g (0.45),
/// of a starch 31.9 g (0.54), of sugar 50.3 g (0.85); the
/// brine salt's 44 mL 53.7 g of table salt (1.22), 26.8 g of kosher
/// (0.60865, v62); four cups of milk or buttermilk 974 g (1.03). 0 when it has
/// neither.
double _mediumMl(IngredientLine line, String normalized, {bool fat = false}) {
  final ml = volumeMlOf(line.amounts);
  if (ml != null || line.amounts.isEmpty) {
    return ml ?? 0;
  }
  final density = densityOf(normalized) ?? (fat ? densityOf('oil') : null);
  final grams = density == null ? null : _freeGrams(line, normalized);
  return grams == null ? 0 : grams / density!;
}

/// The part of a frying oil a sentence it OWNS ([_oilOwnersOf]) keeps in
/// the pan and the dish eats — "Carefully pour off all but 2 tablespoons
/// oil from pan. Add chile mixture to oil left in pan" (1193 Crispy
/// Tempeh, Run 054 O1's verifier: 0 g would be the opposite error) —
/// counted as a plus line's eaten part is ([engineOutcome]); else the part
/// a printed oil yield leaves the food ([_yieldOilEaten], v62); null when
/// neither keeps one.
Amount? _keptFryingOil(Recipe recipe, IngredientLine line) {
  final item = lineItemOf(line);
  // The line's first owned pour-off, found once per recipe and head
  // ([_oilOwnersOf]); parsed once per line text (RULE C, v26, Run 056 O8:
  // its owned sentences walked per line per call).
  // Key: raw — the owners are by raw; item — the head and the kept part's
  // parse.
  return _stepIndexOf(recipe).memo(('keptOil', line.raw, item), () {
    final head = headNounOf(normalizeItem(item));
    final pourOff = head == null
        ? null
        : _oilOwnersOf(recipe, head)[line.raw]?.pourOff;
    final kept = pourOff == null
        ? null
        : _fats[head]!.keptPart(pourOff, reused: true);
    return kept == null
        ? _yieldOilEaten(recipe, line)
        : parseIngredientLine('${kept[1]} $item').amounts.firstOrNull;
  });
}

/// v62 (batch M64, prep49 pE R1, the owner's Q12 (a)): a frying oil the
/// recipe's yield prints as a product — "MAKES ABOUT 1½ CUPS FRIED
/// SHALLOTS AND ABOUT 1¾ CUPS FRIED SHALLOT OIL" beside "2 cups vegetable
/// oil" (Fried Shallots and Fried Shallot Oil, 0053) — leaves the food the
/// difference of the two printed volumes (¼ cup), in the unit of the
/// line's volume amount ([_volumeAmountOf]); null when the yield prints no
/// oil or no less than the line.
/// ponytail: one yield in the corpus prints an oil product; its "about"
/// volume rounds to ⅛ cup (±28 g) — stated in [_yieldOilFlag].
Amount? _yieldOilEaten(Recipe recipe, IngredientLine line) {
  final printed = _yieldOil.firstMatch(recipe.servings?.toLowerCase() ?? '');
  final q = printed == null
      ? null
      : volumeMlOf(
          parseIngredientLine('${printed[1]} ${printed[2]} oil').amounts,
        );
  final own = _volumeAmountOf(line);
  final ml = own == null ? null : volumeMlOf([own]);
  final quantity = own == null ? null : parseQuantity(own.quantity);
  if (q == null || ml == null || quantity == null || q >= ml) {
    return null;
  }
  return Amount(
    measure: Measure.volume,
    quantity: '${quantity * (ml - q) / ml}',
    unit: own!.unit,
  );
}

/// The amount [volumeMlOf] measures of [line] — a primary amount first —
/// or null: a weight-first line, "16 ounces (2 cups) vegetable oil" (a
/// STATED synthesized pin), subtracts from its 2 cups (closer 2: its first
/// amount, 16 ounces, took the cups' arithmetic and weighed 0 g).
Amount? _volumeAmountOf(IngredientLine line) => [
  for (final a in line.amounts)
    if (a.primary) a,
  for (final a in line.amounts)
    if (!a.primary) a,
].where((a) => volumeMlOf([a]) != null).firstOrNull;

final RegExp _yieldOil = RegExp(
  '\\band about ($_amountRun)\\s*(teaspoons?|tablespoons?|cups?)\\b'
  r'(?:\s+fried\b)?([^.]*?)\boil\b',
);

/// The food a yield prints before its oil ("… 1½ cups fried shallots"),
/// less "fried".
final RegExp _yieldFood = RegExp(
  r'(?:\b(?:teaspoons?|tablespoons?|cups?)\s+)?(?:fried\s+)?'
  r'([a-z]+(?:\s+[a-z]+)*)\s*$',
);

/// The part [_keptFryingOil] keeps of a frying oil by [_yieldOilEaten] —
/// no owned pour-off keeps one — or null. It is ALL the oil the food, the
/// pan and the towel keep (closer 3, verifier 3 D1/D2: never a pour-off's
/// pan residual beside the food's uptake, [_m52Plan]; named in the basis
/// beside a plus part, [_gramBasis]).
Amount? _yieldKept(Recipe recipe, IngredientLine line) =>
    _keptFryingOilText(recipe, line) == null
    ? _yieldOilEaten(recipe, line)
    : null;

/// The flag suffix of a frying oil whose kept part is [_yieldKept], else
/// ''.
String _yieldOilFlagOf(Recipe? recipe, IngredientLine line) {
  final eaten = recipe == null ? null : _yieldKept(recipe, line);
  return eaten == null ||
          discardedMediumOf(recipe!, line, normalizeItem(lineItemOf(line))) !=
              DiscardedMedium.fryingOil
      ? ''
      : ' · ${_yieldOilFlag(recipe, line, eaten)}';
}

/// The flag of a frying oil counted by [_yieldOilEaten] (critic F7), built
/// from the prints it subtracts (closer 2, verifier 2 D1: a constant named
/// 0053's figures for any yield): the line's volume in, the yield's "about"
/// volume out as the oil it names, the [eaten] difference in the line's
/// unit kept by the food the yield names (else "the food"), the pan and —
/// when a step names one — the towel. 0053 renders §2's F7 text byte for
/// byte (nutrition_v63_test's `_yieldFlag`).
String _yieldOilFlag(Recipe recipe, IngredientLine line, Amount eaten) {
  final servings = recipe.servings!.toLowerCase();
  final printed = _yieldOil.firstMatch(servings)!;
  final food = _yieldFood.firstMatch(servings.substring(0, printed.start));
  final oil = '${printed[3]!.trim()} oil'.trim();
  final towel = recipe.steps.any((s) => s.text.toLowerCase().contains('towel'));
  String volume(Amount a) {
    // The eaten part is a double's text, in exponent form below 1e-6,
    // which parseQuantity refuses.
    final n = double.tryParse(a.quantity) ?? parseQuantity(a.quantity)!;
    return '${shareText(n)} ${a.unit}${n > 1 ? 's' : ''}';
  }

  return "approximate (the difference of the yield's printed volumes: "
      '${volume(_volumeAmountOf(line)!)} in, about ${printed[1]!.trim()} '
      '${printed[2]} out as $oil — the '
      '${volume(eaten)} the ${food?[1] ?? 'food'}'
      '${towel ? ', the pan and the towel' : ' and the pan'} keep counted as '
      'eaten)';
}

/// The part [_keptFryingOil] reads, as the pour-off writes it ("1
/// tablespoon") — for the basis — or null.
String? _keptFryingOilText(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  final pourOff = head == null || !_fats.containsKey(head)
      ? null
      : _oilOwnersOf(recipe, head)[line.raw]?.pourOff;
  return pourOff == null
      ? null
      : _fats[head]!.keptPart(pourOff, reused: true)?[1];
}

/// v51 (M49 Q19, critic F13): the food a frying oil's kept-part pour-off
/// ([_keptFryingOil]) fried — a sentence of the pour-off's step, before
/// it, that names the oil and a food line ("Transfer the potatoes and
/// remaining 1 cup oil to the skillet. … Reserve 1 tablespoon oil from the
/// skillet and discard the remainder", 0215): that line's head ('potato'),
/// else null (1193's tempeh is fried a step before its pour-off). The MARK
/// M52 reads to add the food's frying uptake on top of the kept part; no
/// grams move on it here.
String? keptOilFries(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  final pourOff = head == null || _keptFryingOil(recipe, line) == null
      ? null
      : _oilOwnersOf(recipe, head)[line.raw]?.pourOff;
  if (pourOff == null) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  final heads = _headsOf(recipe);
  for (final sentences in index.sentences) {
    final at = sentences.indexOf(pourOff);
    if (at < 0) {
      continue;
    }
    for (final s in sentences.take(at)) {
      if (!_fats[head]!.word.hasMatch(s)) {
        continue;
      }
      for (final food in heads) {
        if (food != null && food != head && _names(s, food)) {
          return food;
        }
      }
    }
    return null;
  }
  return null;
}

/// v51 (M49 Q19 a, P1 D3a): a pour-off of the PAN's fat down to a printed
/// part — "Pour off all but 1 teaspoon fat from the skillet" (0088),
/// "Discard all but 1 teaspoon fat from the pot", "drain off all but",
/// "pour out all but", "pour off and discard all but 2 teaspoons fat".
final RegExp _pourOffAllButFat = RegExp(
  r'\b(?:pour off|pour out|spoon off|drain off|discard|remove and discard)\s+'
  r'(?:all\s+)?(?:but|except)\s+(?:about\s+)?'
  '($_baconN)\\s+(teaspoons?|tablespoons?|cups?)\\s+(?:of\\s+)?'
  r'(?:the\s+)?(?:rendered\s+)?(?:[a-z]+\s+)?(?:fat|oil|drippings|grease)\b',
);

/// A sentence that puts an oil in a pan over the heat ([_panOilAt]).
final RegExp _panOil = RegExp(
  r'\b(?:heat|cook|pot|saucepan|dutch oven|skillet|wok)\b',
);

/// The first sentence of [recipe]'s steps that pours the pan's fat down to
/// a printed part ([_pourOffAllButFat]) — where it is, the part as written
/// ("1 teaspoon") and parsed — or null; once per recipe.
({int step, int sentence, String text, Amount kept})? _pourOffFatAt(
  Recipe recipe,
) => _stepIndexOf(recipe).memo(#pourOffFat, () {
  final index = _stepIndexOf(recipe);
  for (final (i, sentences) in index.sentences.indexed) {
    for (final (j, s) in sentences.indexed) {
      // A substring test first: the regex never scans a sentence without it.
      if (!s.contains(' but ') && !s.contains(' except ')) {
        continue;
      }
      if (_pourOffAllButFat.firstMatch(s) case final m?) {
        final kept = _keptAmount(m[1]!, m[2]!);
        return (step: i, sentence: j, text: '${m[1]} ${m[2]}', kept: kept);
      }
    }
  }
  return null;
});

/// The oil line [recipe] browns in the pan a pour-off at [at] (step,
/// sentence) cuts down, and its part in the pan — or null. The LAST
/// sentence naming oil before the pour-off — any earlier sentence (v62,
/// batch M64 F9: the v51 window of its step or the step before left
/// crispy-skinned chicken breasts' step-3 "Place breasts, skin side down,
/// in oil" outside a step-5 pour-off) — puts it in a pan ([_panOil]) and
/// names ONE oil
/// line: the only one with an amount, or by a kind word only it has right
/// before "oil" ("Heat vegetable oil" beside a relish's "¼ cup
/// extra-virgin olive oil", 0228 — the relish is no browning oil; 0124
/// Chicken Marbella's "Heat oil" names neither its paste's oil nor its
/// own, so neither is cut). The part in the pan is that sentence's written
/// amount ("Heat 2 teaspoons of the oil", Skillet Jambalaya: its other 3
/// teaspoons go in after the pour-off), else the whole line.
({IngredientLine line, Amount? part})? _panOilAt(
  Recipe recipe,
  (int, int) at,
) =>
    // Key: at — the pour-off sentence, the window's end.
    _stepIndexOf(recipe).memo(('panOil', at), () {
      final index = _stepIndexOf(recipe);
      final heads = _headsOf(recipe);
      final lines = nutritionLines(recipe);
      final oils = [
        for (final (i, l) in lines.indexed)
          if (heads[i] == 'oil' && l.amounts.isNotEmpty) l,
      ];
      if (oils.isEmpty) {
        return null;
      }
      final mentions = _naming(recipe, 'oil').where((m) => _before(m, at));
      if (mentions.isEmpty) {
        return null;
      }
      final s = index.sentence(mentions.last);
      if (!_panOil.hasMatch(s)) {
        return null;
      }
      final kinds = [for (final l in oils) _kindWords(l, 'oil')];
      final named = oils.length == 1
          ? oils
          : [
              for (final (i, l) in oils.indexed)
                if (kinds[i].any(
                  (w) =>
                      !kinds.indexed.any(
                        (o) => o.$1 != i && o.$2.contains(w),
                      ) &&
                      RegExp(
                        '\\b${RegExp.escape(w)}(?:\\s+[a-z-]+){0,2}\\s+oil\\b',
                      ).hasMatch(s),
                ))
                  l,
            ];
      if (named.length != 1) {
        return null;
      }
      final part = RegExp(
        '($_amountRun(?:teaspoons?|tablespoons?|cups?))\\s+(?:of\\s+)?'
        r'(?:the\s+)?(?:[a-z-]+\s+)?oil\b',
      ).firstMatch(s);
      return (
        line: named.single,
        part: part == null
            ? null
            : parseIngredientLine('${part[1]} oil').amounts.firstOrNull,
      );
    });

/// v51 (M49 Q19 a): the browning oil [line] is when [recipe]'s first
/// pour-off of the pan's fat ([_pourOffFatAt]) cuts it ([_panOilAt]): the
/// printed part kept, as written and parsed, and the oil's part in the pan.
({String text, Amount kept, Amount? part})? _keptBrowningOil(
  Recipe recipe,
  IngredientLine line,
) {
  final at = line.amounts.isEmpty ? null : _pourOffFatAt(recipe);
  final pan = at == null ? null : _panOilAt(recipe, (at.step, at.sentence));
  return pan == null || pan.line.raw != line.raw
      ? null
      : (text: at!.text, kept: at.kept, part: pan.part);
}

/// v51 (M49 Q19 a, with P4's split): what an oil [line] (resolved at
/// [resolved] on [food]) keeps of a pan the steps pour down to a printed
/// part — null when no pour-off cuts it. In rule B1's bacon pan
/// ([_baconPanOf]) the kept fat is shared: the oil keeps kept × O / (R +
/// O) of it, R the bacon's rendered fat, O the oil ([withRenderedBacon]
/// keeps the rest). Else the oil counts at most the kept part
/// ([_keptBrowningOil]). Either way its part outside the pan stays whole.
GramResolution? _keptInPan(
  Recipe recipe,
  IngredientLine line,
  FdcFood food,
  String normalized,
  GramResolution resolved,
) {
  if (line.amounts.isEmpty || headNounOf(normalized) != 'oil') {
    return null;
  }
  double? weigh(Amount amount) => resolveGrams(
    amounts: [amount],
    food: food,
    normalizedItem: normalized,
  )?.grams;
  final bacon = _baconPanOf(recipe);
  final shared = bacon != null && bacon.oil.raw == line.raw;
  final browning = shared ? null : _keptBrowningOil(recipe, line);
  if (!shared && browning == null) {
    return null;
  }
  final part = shared ? bacon.part : browning!.part;
  final inPan = part == null
      ? resolved.grams
      : min(resolved.grams, weigh(part) ?? resolved.grams);
  final keeps = shared ? _baconPanOilShare(bacon) : weigh(browning!.kept);
  if (keeps == null || keeps >= inPan) {
    return null;
  }
  return GramResolution(
    grams: resolved.grams - inPan + keeps,
    source: GramSource.discarded,
    basis: resolved.basis,
  );
}

/// The basis of an oil row [_keptInPan] cut: "1 teaspoon kept (the steps
/// pour off the rest)"; in rule B1's bacon pan "2 tablespoons kept with the
/// bacon grease (the steps pour off the rest)".
String? _keptInPanBasis(Recipe recipe, IngredientLine line) {
  final bacon = _baconPanOf(recipe);
  if (bacon != null && bacon.oil.raw == line.raw) {
    return '${bacon.text} kept with the bacon grease '
        '(the steps pour off the rest)';
  }
  final browning = _keptBrowningOil(recipe, line);
  return browning == null
      ? null
      : '${browning.text} kept (the steps pour off the rest)';
}

/// The written part of a strained braising liquid a step keeps — "1 cup
/// defatted cooking liquid" (Mahogany Chicken Thighs, 0129), "½ cup
/// reserved defatted liquid" (Indoor Pulled Chicken, 0129) — when [line] is
/// in that liquid ([DiscardedMedium.partialPourAway], Q4), else null. The
/// liquid is the sentence before the strain that names the line and opens
/// "whisk" or "bring", the food added ("add", "arrange") in the next
/// sentence ("Arrange chicken … in soy mixture", "Add chicken"); a step
/// using the "remaining" liquid keeps it all. A pot the food simmers in
/// from the start (0491 brings the pork, onion and water to a simmer
/// together) makes no such liquid.
String? keptLiquidOf(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  if (head == null || !_firstOfItsHead(recipe, line, head)) {
    return null;
  }
  final braise = _braiseOf(recipe);
  return braise != null && braise.openers.any((s) => _names(s, head))
      ? braise.kept
      : null;
}

/// What [keptLiquidOf] reads of [recipe]'s steps alone, once per recipe
/// ([_StepIndex]; Run 055 S16): the strained braise's kept liquid as written
/// and the sentences that make the liquid (opening "whisk" or "bring", the
/// food added in the next) before the strain — null when no step strains
/// one or a step uses the "remaining" liquid. Read by sentence, each
/// windowed: never one regex run over every step joined (Run 054 Sonnet
/// critic 1).
({String kept, List<String> openers})? _braiseOf(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#braise, () {
      final index = _stepIndexOf(recipe);
      final strain = _strainOf(recipe);
      if (strain < 0) {
        return _pourAwayOf(recipe);
      }
      // Both readers need the word: a substring test first.
      final after = index.sentences
          .skip(strain)
          .expand((s) => s)
          .where((s) => s.contains('liquid'));
      final keptIn = RegExp(
        '$_amountRun\\s*'
        r'cups?\s+(?:(?:reserved|defatted)\s+)*(?:cooking\s+)?liquid\b',
      );
      final kept = after.map(keptIn.firstMatch).nonNulls.firstOrNull;
      final remaining = RegExp(r'\bremaining (?:\w+ )?(?:cooking )?liquid\b');
      if (kept == null || after.any(remaining.hasMatch)) {
        return null;
      }
      final opens = RegExp(r'^(whisk|bring)\b');
      final adds = RegExp(r'^(add|arrange)\b');
      return (
        kept: kept[0]!,
        openers: [
          for (final sentences in index.sentences.take(strain))
            for (final (i, s) in sentences.indexed)
              if (i + 1 < sentences.length &&
                  opens.hasMatch(s.trimLeft()) &&
                  adds.hasMatch(sentences[i + 1].trimLeft()))
                s,
        ],
      );
    });

/// A poach whose liquid is poured away but a measured part (v31, the
/// owner's R4 ruling on 0488 Enchiladas Verdes): "Remove ¼ cup liquid from
/// the saucepan and set aside; discard the remaining liquid." The kept part
/// as written, and the sentences of that step before it — what simmers in
/// the liquid ("Heat 2 teaspoons of the oil …; add the onion", "Add 2
/// teaspoons of the garlic and the cumin", "stir in the broth"); the food
/// lifted out ("Transfer the chicken") is named by none of its lines'
/// heads. Null when no sentence pours one away, or a later one uses a
/// "remaining" liquid. Once per recipe ([_braiseOf]).
({String kept, List<String> openers})? _pourAwayOf(Recipe recipe) {
  final at = _pourAwayAt(recipe);
  if (at == null) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  final sentences = index.sentences[at.$1];
  final remaining = RegExp(r'\bremaining (?:\w+ )?(?:cooking )?liquid\b');
  final later = [
    ...sentences.skip(at.$2 + 1),
    ...index.sentences.skip(at.$1 + 1).expand((s) => s),
  ];
  return later.any(remaining.hasMatch)
      ? null
      : (
          kept: _poursAway.firstMatch(sentences[at.$2])![1]!,
          openers: sentences.take(at.$2).toList(),
        );
}

/// Where [_pourAwayOf]'s sentence is — (step, sentence) — or null, once
/// per recipe.
(int, int)? _pourAwayAt(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#pourAway, () {
      final index = _stepIndexOf(recipe);
      for (final (i, sentences) in index.sentences.indexed) {
        for (final (j, s) in sentences.indexed) {
          if (s.contains('discard') && _poursAway.hasMatch(s)) {
            return (i, j);
          }
        }
      }
      return null;
    });

final RegExp _poursAway = RegExp(
  '\\bremove ($_amountRun\\s*cups? (?:cooking )?liquid)\\b[^.]*'
  r'\bdiscard (?:the )?remaining (?:cooking )?liquid\b',
);

/// The first step of [recipe] that strains a braise's liquid
/// ([keptLiquidOf]), or -1 — read by windowed sentence (Run 054: the
/// `[^.]*` run over a whole 10,000-character step re-scanned from every
/// "cooking liquid through", 1.1 s on one compute; the run never crossed a
/// period, so a sentence holds every match it found), once per recipe.
int _strainOf(Recipe recipe) => _stepIndexOf(recipe).memo(
  #strain,
  () => _stepIndexOf(
    recipe,
  ).sentences.indexWhere((s) => s.any(_strainsLiquid.hasMatch)),
);

final RegExp _strainsLiquid = RegExp(
  r'\bcooking liquid through\b[^.]*\bstrainer\b',
);

/// The part of a held [DiscardedMedium.coating] or
/// [DiscardedMedium.partialPourAway] line a step uses OUTSIDE the medium,
/// eaten (Run 053 O9): "Sprinkle cubes with 1 teaspoon flour" (1133
/// Francese's ¾ cup, divided: the butter is whisked into the sauce), the
/// "remaining 1 teaspoon liquid smoke" added to the pot after the strain
/// (0129 Indoor Pulled Chicken's tablespoon, divided). The medium is every
/// step with a dredge sentence, or every step before the braise's strain. Held
/// with the line as a plus line's eaten part is ([engineOutcome]), and
/// named in its `hold_note` ([holdNoteOf]) as written ("1 teaspoon
/// flour"); null when no step writes such a part. [ownHead]: the line's
/// own head when [head] is its item's last word instead ([_m52Plan]'s dip
/// fallback) — the writers then widen to match ([_amountWritersOf]).
({Amount amount, String text})? _eatenOutsideMedium(
  Recipe recipe,
  IngredientLine line,
  String? head,
  DiscardedMedium? medium, {
  int after = -1,
  String? ownHead,
}) {
  if (head == null ||
      (medium != DiscardedMedium.coating &&
          medium != DiscardedMedium.partialPourAway)) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // A poured-away poach's medium is its step ([_pourAwayOf]): the parts
  // eaten are written after it.
  final pourAway = medium == DiscardedMedium.partialPourAway
      ? _pourAwayAt(recipe)
      : null;
  final from = medium != DiscardedMedium.partialPourAway
      ? 0
      : _strainOf(recipe) >= 0 || pourAway == null
      ? _strainOf(recipe)
      : pourAway.$1 + 1;
  // The amounts written before the head outside the medium, once per
  // head and medium: each line of the head reads the list, never the steps.
  // Key: head — the mention pattern; medium — the first step read (the strain)
  // and the dredge-step filter.
  final written = index.memo(('eaten', head, medium), () {
    final mention = RegExp(
      '($_amountRun\\s+(?:[a-z]+\\s+){1,2})${RegExp.escape(head)}\\b',
    );
    // Which steps dredge, once per recipe.
    final dredges = index.memo(#dredges, () {
      return [
        for (final s in index.sentences) s.any(_dredgeSentence.hasMatch),
      ];
    });
    final steps = index.sentences.length;
    return [
      for (final (i, sentences) in index.sentences.indexed.skip(
        from < 0 ? steps : from,
      ))
        // A step that sets up or does the dredge is the medium's, all of
        // it: 0198's "remaining ⅓ cup cornstarch" goes into the cornflake
        // crumbs the chops are coated in, a sentence after its "shallow
        // dish".
        if (medium != DiscardedMedium.coating || !dredges[i])
          for (final sentence in sentences)
            // The head is written in any sentence the mention reads: a
            // substring test first, so the amount run never scans a
            // sentence without it.
            if (sentence.contains(head))
              if (mention.firstMatch(sentence) case final match?) (i, match),
    ];
  });
  // The mention is THIS line's only when no other line of its ingredient
  // writes that amount (Run 054 O7: 1133's "¾ cup flour, divided" split
  // into "¾ cup" and "1 teaspoon" flour lines kept "Sprinkle cubes with 1
  // teaspoon flour" as the dredge's eaten part too — the teaspoon counted
  // twice). RULE C (v26, Run 056 S5/S7: each line parsed every mention and
  // scanned every line per mention — a legal 400-line dredge recipe ~123 s
  // per GET): the mentions parsed ONCE per head and medium, each amount's
  // mentions and the unwritten ones indexed in order, and each amount's
  // lines found once per head — a line's answer is three binary searches.
  // v65 (M66 R2): a dip's line reads only the mentions in the steps after
  // its dip's ([after]) — never the mixing step before it, which writes
  // the dip's own amounts ("2 tablespoons hot sauce", 1185): the same
  // lists from that step on, so every dip step shares one parse.
  // Key: head and medium — [written]'s, and the parse's head.
  final parts = index.memo(('eatenParts', head, medium), () {
    final parsed =
        <({int step, (String, String?) amount, Amount part, String text})>[];
    final amounts = <(String, String?)>{};
    for (final (step, match) in written) {
      _count('eatenParses');
      final part = parseIngredientLine(
        '${match[1]}$head',
      ).amounts.firstOrNull;
      if (part != null) {
        amounts.add((part.quantity, part.unit));
        parsed.add((
          step: step,
          amount: (part.quantity, part.unit),
          part: part,
          text: match[0]!,
        ));
      }
    }
    return (parsed: parsed, amounts: amounts);
  });
  final writers = _amountWritersOf(recipe, head, ownHead);
  bool free((String, String?) amount) => switch (writers[amount]) {
    null => true,
    final lines => lines.length == 1 && identical(lines.single, line),
  };
  // The mentions read: those from step [after] + 1 on.
  final at = _firstAfter(parts.parsed, after + 1, (p) => p.step);
  // The first of [mentions] (indexes into [parts], ascending) read, or null.
  int? firstRead(List<int> mentions) {
    final k = _firstAfter(mentions, at, (i) => i);
    return k < mentions.length ? mentions[k] : null;
  }

  ({Amount amount, String text}) partAt(int i) =>
      (amount: parts.parsed[i].part, text: parts.parsed[i].text);
  // The first mention of an amount no line writes, or this line's own
  // amount when it is the only line writing it and is written first.
  final unwritten = firstRead(
    index.memo(
      // Key: head and medium — [parts]'s; head and ownHead — the writers.
      ('eatenUnwritten', head, medium, ownHead),
      () => [
        for (final (i, p) in parts.parsed.indexed)
          if (writers[p.amount] == null) i,
      ],
    ),
  );
  final own = line.amounts.firstOrNull;
  final mine = own == null ? null : (own.quantity, own.unit);
  if (mine != null && parts.amounts.contains(mine) && free(mine)) {
    final order = index.memo(
      // Key: head and medium — [parts]'s.
      ('eatenOrder', head, medium),
      () {
        final byAmount = <(String, String?), List<int>>{};
        for (final (i, p) in parts.parsed.indexed) {
          (byAmount[p.amount] ??= []).add(i);
        }
        return byAmount;
      },
    );
    final first = order[mine] == null ? null : firstRead(order[mine]!);
    if (first != null && (unwritten == null || first < unwritten)) {
      return partAt(first);
    }
  }
  return unwritten == null ? null : partAt(unwritten);
}

/// Each first amount (quantity, unit) the lines of [head] in [recipe]
/// write, and the lines writing it (by identity) — once per head
/// ([_eatenOutsideMedium]). v65 closer 1 (D1): with [ownHead], [head] is a
/// dip line's item's LAST word ("zest" of "grated zest from 1 orange",
/// "eggs" of "large eggs" — no line's head), and the writers are also every
/// line whose item ends in it and every line of [ownHead]: a mention
/// another line writes ("Whisk 2 large eggs into the dressing" beside a
/// second "2 large eggs" line) is never the dip line's (Run 054 O7).
Map<(String, String?), Set<IngredientLine>> _amountWritersOf(
  Recipe recipe,
  String head, [
  String? ownHead,
  // Key: head and ownHead — the lines of them.
]) => _stepIndexOf(recipe).memo(('amountWriters', head, ownHead), () {
  final heads = _headsOf(recipe);
  final lasts = ownHead == null ? null : _lastWordsOf(recipe);
  final writers = <(String, String?), Set<IngredientLine>>{};
  for (final (i, line) in nutritionLines(recipe).indexed) {
    final first = line.amounts.firstOrNull;
    if (first != null &&
        (heads[i] == head ||
            lasts != null && (heads[i] == ownHead || lasts[i] == head))) {
      (writers[(first.quantity, first.unit)] ??= Set.identity()).add(line);
    }
  }
  return writers;
});

/// Each of [recipe]'s [nutritionLines]' normalized item's last word, once
/// per recipe ([_amountWritersOf]).
List<String> _lastWordsOf(Recipe recipe) => _stepIndexOf(recipe).memo(
  #lastWords,
  () => [
    for (final line in nutritionLines(recipe))
      normalizeItem(lineItemOf(line)).split(' ').last,
  ],
);

/// The `hold_note` of [line]'s [hold] — what a reviewer needs to judge it,
/// in words: a `partial_pour_away`'s kept liquid ([keptLiquidOf]), and a
/// divided `coating` or `partial_pour_away` line's part eaten outside the
/// medium ([_eatenOutsideMedium]) — its grams, held until a confirm counts
/// them — and an `ambiguous_medium` line's sentence ([_oilOwnersOf]); else
/// null.
String? holdNoteOf(Recipe recipe, IngredientLine line, String? hold) {
  if (hold == 'ambiguous_medium') {
    final head = headNounOf(normalizeItem(lineItemOf(line)));
    final said = head == null
        ? null
        : _oilOwnersOf(recipe, head)[line.raw]?.ambiguous;
    return said;
  }
  // v60 (M62 H): a dip held with its coat — the dip sentence.
  if (hold == 'coating') {
    final position = nutritionLines(
      recipe,
    ).indexWhere((l) => identical(l, line));
    if (_dipsOf(recipe)[position] case final dip?) {
      return dip.text;
    }
  }
  final medium = switch (hold) {
    'coating' => DiscardedMedium.coating,
    'partial_pour_away' => DiscardedMedium.partialPourAway,
    _ => null,
  };
  if (medium == null) {
    return null;
  }
  final kept = medium == DiscardedMedium.partialPourAway
      ? keptLiquidOf(recipe, line)
      : null;
  final eaten = _eatenOutsideMedium(
    recipe,
    line,
    headNounOf(normalizeItem(lineItemOf(line))),
    medium,
  )?.text;
  final outside = eaten == null
      ? null
      : '$eaten is used outside the '
            '${medium == DiscardedMedium.coating ? 'dredge' : 'braise'}, eaten';
  return kept == null || outside == null ? kept ?? outside : '$kept; $outside';
}

/// Whether a [head] salt or sugar is a dry cure a step rubs on and a later
/// sentence rinses off the food — "Rub each side evenly with salt mixture
/// … Refrigerate for 5 to 7 days … Rinse brisket and pat it dry"
/// (New England–Style Home-Corned Beef, 0090): 0 g discarded like a brine's
/// salt (the user's ruling Q3, 2026-10-01). A dry brine whose EXCESS is
/// rinsed off stays on the meat (Roast Salted Turkey, 0168: "Rinse off any
/// excess salt"), and so does a rub no step rinses (a barbecue rub).
/// The rinse is read once per recipe (Run 055 S4: v24 re-split every later
/// step for each "rub" sentence, 39 s on 40 legal steps): the LAST
/// sentence rinsing the food, and a rub before it.
bool _rinsedCure(Recipe recipe, String head) {
  final index = _stepIndexOf(recipe);
  final rinse = index.memo(#lastRinse, () {
    for (var i = index.sentences.length - 1; i >= 0; i--) {
      final sentences = index.sentences[i];
      for (var j = sentences.length - 1; j >= 0; j--) {
        final t = sentences[j];
        if (t.trimLeft().startsWith('rinse') && !t.contains('excess')) {
          return (i, j);
        }
      }
    }
    return null;
  });
  // Once per head, the pattern compiled once (RULE C, v26, Run 056 S9: a
  // RegExp built per sentence per line).
  return rinse != null &&
      // Key: head — the food rubbed before the rinse.
      index.memo(('rinsedCure', head), () {
        return _naming(recipe, head).any(
          (at) =>
              (at.$1 < rinse.$1 || (at.$1 == rinse.$1 && at.$2 < rinse.$2)) &&
              _rub.hasMatch(index.sentence(at)),
        );
      });
}

final RegExp _rub = RegExp(r'\brub');

/// The [DiscardedMedium] [line] of [recipe] is, or null. [normalized] is the
/// line's normalized item. Read from the line and the steps alone — no
/// food, no resolved grams ([_massZeroes]): every caller gets one answer.
DiscardedMedium? discardedMediumOf(
  Recipe recipe,
  IngredientLine line,
  String normalized, {
  bool bySentence = true,
}) {
  // The food the line names, not a word in it: 'without salt butter' is
  // butter, 'salt pork' is pork.
  final head = headNounOf(normalized);
  final raw = line.raw.toLowerCase();
  // Both unit families ([_mediumMl]), read only when a threshold asks.
  late final ml = _mediumMl(line, normalized);
  final index = _stepIndexOf(recipe);
  final steps = index.raw;
  // Once per recipe for each pattern and word, whichever lines ask.
  bool stepSays(RegExp what, String word) =>
      // Key: what — the step pattern; word — the food it must name.
      index.memo(('says', what, word), () {
        return steps.indexed.any(
          (e) => what.hasMatch(e.$2) && index.lower[e.$1].contains(word),
        );
      });
  // The checkpoint 9 rulings read from the steps (Q1, Q2, Q4): by sentence
  // only, and never the water.
  if (bySentence && head != 'water') {
    if (index.memo(#starter, () => _feedsStarter(steps))) {
      return DiscardedMedium.starterDiscard;
    }
    if (_dredge(recipe, raw, head, () => ml, steps) ||
        (head == 'bread' && _crumbsForTheCoat(recipe, raw)) ||
        _crumbLineOfTheCoat(recipe, head, () => ml) ||
        _coatLayer(recipe, line, head, () => ml, normalized)) {
      return DiscardedMedium.coating;
    }
    if (keptLiquidOf(recipe, line) != null) {
      return DiscardedMedium.partialPourAway;
    }
  }
  // Shortening, lard, "for brining", "for soaking" and the dry-brine/cure
  // exclusion change no line of the library (audit 4 P9) but classify lines
  // typed through the API: a dry brine's salt stays on the meat, and the
  // brine rule below would read "dry-brine" as a brine.
  // v31 (Q7 fats, ruled): a 'fat' line too — "6 cups duck fat, chicken
  // fat, or vegetable oil for confit" (0451) is the confit's medium, not
  // 1,230 g eaten; a smaller fat line no sentence fries stays counted.
  if (head == 'oil' ||
      head == 'shortening' ||
      head == 'lard' ||
      head == 'fat') {
    if (_massZeroes(line, normalized)) {
      return DiscardedMedium.fryingOil;
    }
    return bySentence ? _oilBySentence(recipe, line) : null;
  }
  if (head == 'salt' || head == 'sugar') {
    // A cure rinsed off goes with the rinse, whatever the recipe calls it
    // (Q3).
    if (bySentence && _rinsedCure(recipe, head!)) {
      return head == 'salt'
          ? DiscardedMedium.brine
          : DiscardedMedium.brineSugar;
    }
    if (index.memo(#kept, () => steps.any(_kept.hasMatch)) ||
        _kept.hasMatch(recipe.title)) {
      return null;
    }
    if (raw.contains('for brining') ||
        (ml >= (head == 'salt' ? _brineSaltMl : _quarterCupMl) &&
            stepSays(_brineStep, head!))) {
      // A brine the food then poaches in is its cooking liquid, as for the
      // brine's co-solutes (Perfect Poached Chicken Breasts, 0112: its salt
      // was zeroed while its soy sauce was held; checkpoint 8).
      return _poached(recipe)
          ? DiscardedMedium.cookingWater
          : head == 'salt'
          ? DiscardedMedium.brine
          : DiscardedMedium.brineSugar;
    }
    // Sugar dunked with a salt-bath salt goes with it (Grilled
    // Cauliflower, 0656: "Whisk 2 cups water, salt, and sugar … gently dunk
    // in salt-sugar mixture"; checkpoint 8).
    if (head == 'sugar' && bySentence && _dunkedWithSalt(recipe, steps)) {
      return DiscardedMedium.saltBath;
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
    final away = bySentence ? _drainedAway(recipe, line, head!, steps) : null;
    if (away != null) {
      return away;
    }
    // A rub the meat keeps, like a dry brine: pork shoulder's overnight
    // salt-sugar rub, gravlax, a salted turkey.
    return head == 'salt' && ml >= _quarterCupMl && !stepSays(_rubStep, 'salt')
        ? DiscardedMedium.saltBath
        : null;
  }
  if (raw.contains('for soaking') ||
      (head == 'buttermilk' &&
          ml >= _fourCupsMl &&
          (stepSays(_brineStep, 'buttermilk') ||
              stepSays(
                _soakStep,
                'buttermilk',
              )))) {
    return DiscardedMedium.soak;
  }
  if (head == 'milk' &&
      ml >= _fourCupsMl &&
      index.memo(#whey, () => steps.any(_wheyStep.hasMatch))) {
    return DiscardedMedium.cheeseMilk;
  }
  if (head == 'soda' && bySentence && _drainedWater(recipe, line, steps)) {
    return DiscardedMedium.cookingWater;
  }
  if (head == 'soda' && bySentence && _rinsedSalt(recipe, line, steps)) {
    return DiscardedMedium.saltBath;
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
  return _brineCoSolute(recipe, line, head, steps) ??
      _drainedAway(recipe, line, head, steps) ??
      // v50 (M50): what a strain, a discard by name or a printed part
      // kept leaves of the line — after every shipped reader (the lentil
      // salad's drained pot stays `discarded_medium`).
      _strainedOut(recipe, line, head) ??
      _discardedByName(recipe, line, head)?.medium ??
      (_partialUseOf(recipe, line, head) == null
          ? null
          : DiscardedMedium.partialUse);
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
bool _firstOfItsHead(Recipe recipe, IngredientLine line, String head) {
  final at = _headsOf(recipe).indexOf(head);
  return at < 0 || identical(nutritionLines(recipe)[at], line);
}

/// The head noun of each of [recipe]'s [nutritionLines], read once per
/// Recipe instance (Run 054 S4/O4: every detector of every line re-derived
/// every line's head — a reached recipe's lines cost O(lines²) per GET).
/// A Recipe is immutable, so the instance is the key.
List<String?> _headsOf(Recipe recipe) => _heads[recipe] ??= () {
  _count('heads');
  return [
    for (final line in nutritionLines(recipe))
      headNounOf(normalizeItem(lineItemOf(line))),
  ];
}();

final Expando<List<String?>> _heads = Expando();

/// Whether [head] (a key-form noun) is written in [text] as a word.
/// A head in -y is written -ies ("allspice berries", Home-Corned Beef,
/// 0091), and "garlic cloves" never names the spice 'clove'. An empty
/// [head] (a line with nothing searchable, "(about ¾ cup)" in Hearty
/// Minestrone, 0028) names nothing: it crashed a pick on such a line in a
/// recipe that brines (Run 045).
bool _names(String text, String head) {
  if (head.isEmpty) {
    return false;
  }
  namesScans++;
  return _namesPattern(head).hasMatch(text);
}

/// [_names]' pattern for a non-empty [head]: compiled once per head (Run
/// 054 S4: one compile per sentence per line); cleared past 4,096 heads,
/// so member text never grows it unbounded.
RegExp _namesPattern(String head) {
  if (_namesOf.length > _cap(4096)) {
    _namesOf.clear();
  }
  return _namesOf.putIfAbsent(head, () {
    _count('names');
    final word = RegExp.escape(head);
    final stem = RegExp.escape(head.substring(0, head.length - 1));
    final plural = head.endsWith('y')
        ? '(?:$word|${stem}ies)'
        : '$word(?:s|es)?';
    return RegExp('(?<!garlic )\\b$plural\\b');
  });
}

final Map<String, RegExp> _namesOf = {};

/// The forms [_names] reads as [head]: the head, its "s" or "es" plural —
/// or, for a head ending in "y", its "-ies" one ([_namesPattern]).
List<String> _formsOf(String head) => head.endsWith('y')
    ? [head, '${head.substring(0, head.length - 1)}ies']
    : [head, '${head}s', '${head}es'];

/// The words a [_names] match of [head] starts with, as [_Words] reads
/// them: a word-only head's forms ([_formsOf]) are whole words; a head
/// with another character in it ("half-and-half") starts with its leading
/// word run, a whole word too (the character after it is no word
/// character, in the head and so in the text). Empty for a head opening
/// on no word character.
List<String> _leadsOf(String head) {
  var n = 0;
  while (n < head.length && _isWordUnit(head.codeUnitAt(n))) {
    n++;
  }
  return n == head.length ? _formsOf(head) : [if (n > 0) head.substring(0, n)];
}

/// The sentence of [w] naming a head ([_names]) by a match starting at the
/// word start [start], or -1: one of the head's [forms] ([_formsOf])
/// written there, ending at a word boundary (`\b` past the text's end: after
/// a word character only), within one sentence, not after "garlic " (a
/// sentence break never ends in "garlic ": it follows a period).
int _namedFrom(_Words w, int start, List<String> forms) {
  final text = w.text;
  if (start >= 7 && text.startsWith('garlic ', start - 7)) {
    return -1;
  }
  for (final f in forms) {
    final end = start + f.length;
    if (text.startsWith(f, start) &&
        _isWordUnit(text.codeUnitAt(end - 1)) !=
            (end < text.length && _isWordUnit(text.codeUnitAt(end)))) {
      final j = w.sentenceOf(start);
      if (w.sentenceOf(end - 1) == j) {
        return j;
      }
    }
  }
  return -1;
}

/// A word's key: a hash of its code units — equal words, equal keys; a key
/// that agrees is confirmed at the word ([_namedFrom]).
int _keyOf(String word) {
  var key = 0;
  for (var i = 0; i < word.length; i++) {
    key = (key * 31 + word.codeUnitAt(i)) & 0x3FFFFFFF;
  }
  return key;
}

/// A step's words — every maximal `\w` run, [_names]' `\b…\b` word — each
/// one's start and key ([_keyOf]), and where its sentences (the step
/// split at [_sentenceBreak]) start: one pass over the step, O(text),
/// whatever it spells.
final class _Words {
  _Words(this.text, List<String> sentences) {
    // A sentence after a break opens on its first character past the
    // break's whitespace (the break is greedy, so that character is none
    // of it); the last one, after a final break, may be empty.
    var at = 0;
    for (final (j, s) in sentences.indexed) {
      if (j > 0) {
        if (s.isEmpty) {
          at = text.length;
        } else {
          final first = s.codeUnitAt(0);
          while (text.codeUnitAt(at) != first) {
            at++;
          }
        }
        breaks.add(at);
      }
      at += s.length;
    }
    // Into the shared scratch buffers, then copied to size (v29 closer,
    // the verifier's D8: growable lists cost 2.6 ms over the capped steps,
    // the scratch 1.3 — a PUT's one-head read paid the difference).
    final len = text.length;
    if (_scratchKeys.length <= len >> 1) {
      _scratchKeys = Int32List((len >> 1) + 1);
      _scratchStarts = Int32List((len >> 1) + 1);
    }
    final keys = _scratchKeys;
    final starts = _scratchStarts;
    var n = 0;
    for (var i = 0; i < len;) {
      var c = text.codeUnitAt(i);
      if (!_isWordUnit(c)) {
        i++;
        continue;
      }
      starts[n] = i;
      var key = 0;
      do {
        key = (key * 31 + c) & 0x3FFFFFFF;
      } while (++i < len && _isWordUnit(c = text.codeUnitAt(i)));
      keys[n++] = key;
    }
    this.keys = keys.sublist(0, n);
    this.starts = starts.sublist(0, n);
  }

  /// [_Words]' scratch (a word is at least one character and a separator
  /// follows each but the last: at most half the text, rounded up).
  static Int32List _scratchKeys = Int32List(0);
  static Int32List _scratchStarts = Int32List(0);

  final String text;

  /// Where each sentence after the first starts.
  final List<int> breaks = [];
  late final Int32List keys;
  late final Int32List starts;

  /// The index of the sentence holding offset [at] (a word's, never a
  /// break's): the breaks ending at or before it.
  int sentenceOf(int at) => _firstAfter(breaks, at, (e) => e, strict: true);
}

/// How many [_names] scans ran since reset — what the tests pin the
/// inversion's per-word reading by (RULE C v28: no rescan per word found).
@visibleForTesting
int namesScans = 0;

final Expando<bool> _makesCheese = Expando();

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
  // Each brine step's submerge, read once per recipe: the submerge's own
  // sentence from the marker on, and the sentences before the marker.
  final index = _stepIndexOf(recipe);
  final brines = index.memo(#brines, () {
    final marker = RegExp(r'submerg|\bweigh\w*\s+\w+\s+down\b');
    return [
      for (final (i, text) in index.lower.indexed)
        if (marker.firstMatch(text) case final submerge?
            when RegExp(r'\bbrine\b').hasMatch(text))
          (
            object: _sentenceAt(index, i, submerge.start),
            word: submerge[0]!,
            before: text.substring(0, submerge.start).split(_sentenceBreak),
          ),
    ];
  });
  // Whether sentence [i] of a brine's [sentences] can name a co-solute,
  // whatever the head.
  bool opens(List<String> sentences, int i) =>
      !(i == sentences.length - 1 && sentences[i].contains(_toBrine)) &&
      (sentences[i].contains(_saltWord) ||
          sentences[i].trimLeft().startsWith('add'));
  // RULE C (v26, Run 056 S9: every head re-read every brine sentence —
  // 400 distinct foods, ~11 s at the caps): each brine's sentences read
  // ONCE for every head of the recipe they name ([_wordHeadsOf]) — the
  // heads its submerge names, and the first sentence naming each.
  final words = _wordHeadsOf(recipe).contains(head)
      ? index.memo(#brineWords, () {
          return [
            for (final (:object, :word, :before) in brines)
              (
                submerged: _wordsOf(
                  object.substring(object.indexOf(word)),
                  _wordHeadsOf(recipe).contains,
                ).toSet(),
                first: () {
                  final first = <String, int>{};
                  for (final (i, sentence) in before.indexed) {
                    if (opens(before, i)) {
                      for (final h in _wordsOf(
                        sentence,
                        _wordHeadsOf(recipe).contains,
                      )) {
                        first.putIfAbsent(h, () => i);
                      }
                    }
                  }
                  return first;
                }(),
              ),
          ];
        })
      : null;
  for (final (b, (:object, :word, :before)) in brines.indexed) {
    final int? at;
    if (words != null) {
      if (words[b].submerged.contains(head)) {
        return null;
      }
      at = words[b].first[head];
    } else {
      if (_names(object.substring(object.indexOf(word)), head)) {
        return null;
      }
      at = _firstWhere(
        before.length,
        (i) => _names(before[i], head) && opens(before, i),
      );
    }
    if (at case final i?) {
      final sentence = before[i];
      return (
        medium: _poached(recipe)
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

final RegExp _toBrine = RegExp(r'\bto (the )?brine\b');
final RegExp _saltWord = RegExp(r'\bsalt\b');

/// The first of 0 … [n] - 1 [test] holds for, or null.
int? _firstWhere(int n, bool Function(int) test) {
  for (var i = 0; i < n; i++) {
    if (test(i)) {
      return i;
    }
  }
  return null;
}

/// Whether [recipe] poaches (its title says so): its brine is the liquid
/// the food cooks in.
bool _poached(Recipe recipe) =>
    RegExp(r'\bpoach').hasMatch(recipe.title.toLowerCase());

/// Whether a salt line of [recipe] is a [DiscardedMedium.saltBath] whose
/// own mention's sentence names the sugar too.
/// Once per recipe: it names no line of its own.
bool _dunkedWithSalt(Recipe recipe, List<String> steps) =>
    _stepIndexOf(recipe).memo(#dunked, () {
      final index = _stepIndexOf(recipe);
      return nutritionLines(recipe).any((salt) {
        final item = normalizeItem(lineItemOf(salt));
        // Read once per sentence, whichever mentions share it.
        return headNounOf(item) == 'salt' &&
            _firstOwn(recipe, salt, #sugarBeside, (step, at) {
                  final k = index.sentenceAt(step, at).index;
                  return index.memo(
                        // Key: step and k — the sentence (its step, its index
                        // there).
                        ('sugarBeside', step, k),
                        () => _names(_sentenceAt(index, step, at), 'sugar'),
                      )
                      ? true
                      : null;
                }) !=
                null &&
            discardedMediumOf(recipe, salt, item) == DiscardedMedium.saltBath;
      });
    });

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
          '($_amountRun\\s+(?:[a-z]+\\s+)?)${RegExp.escape(head)}',
        ).firstMatch(sentence)?[1];
  if (written == null || _bundled(recipe, head)) {
    return null;
  }
  final part = parseIngredientLine('$written${lineItemOf(line)}').amounts;
  final volume = volumeMlOf(line.amounts) != null;
  final own = volume ? volumeMlOf(line.amounts) : countOf(line.amounts);
  final share = volume ? volumeMlOf(part) : countOf(part);
  // Never more than the line: its grams are never negative.
  return own == null || share == null || share >= own ? null : share / own;
}

/// A liquid the food is put in and then parted from — checkpoint 8: the
/// court-bouillon of Shrimp Salad (0286: "Combine the shrimp, ¼ cup of the
/// lemon juice, … sugar, and 1 teaspoon salt with 2 cups cold water …
/// cook the shrimp", then "Drain the shrimp into a colander and discard
/// the lemon halves, herbs, and spices"), a milk dip the squid is lifted
/// from (Rhode Island–Style Fried Calamari, 1084: "Whisk milk and salt
/// together … allowing excess milk mixture to drip back into bowl") and a
/// quick pickle drained off its slaw (Carne Deshebrada, 0481: "whisk
/// vinegar, water, sugar, and salt in large bowl … Add cabbage … Drain
/// slaw"). The line is mentioned — its salt or sugar as [_ownsOf]
/// reads it, another food by the nth line of its head at the
/// nth mention (list order, the A13 assumption) — in a sentence that
/// combines, whisks or dissolves; later in that step a sentence
/// drips back the mixture it names, or drains anything after an "add … toss"
/// — or, in that step or the next, drains a food that sentence names and
/// discards. The drained food is never one, nor a sprig line (0 g already).
/// Cooked after the mention: cooking water; else a salt bath. Held either
/// way. (A soda's own mentions, "simmer" or "boil" for cooked, and a "not"
/// before the drain changed no line of the library: removed, v15.)
DiscardedMedium? _drainedAway(
  Recipe recipe,
  IngredientLine line,
  String head,
  List<String> steps,
) {
  if (line.amounts.any((a) => a.unit == 'sprig')) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // What each later sentence does is read once per recipe ([_Parting]),
  // and a mention finds the first that parts the food from the liquid by
  // lookup — never a rescan of the rest of its step per mention (Run 055
  // S4/O9).
  final parting = index.memo(#parting, () {
    return [for (final s in index.sentences) _Parting(s)];
  });
  // The sentence [k] of [step] a mention stands in: how it parts the food
  // from the liquid, or null.
  DiscardedMedium? parted(int step, int k, String sentence) {
    if (!_mixes.hasMatch(sentence)) {
      return null;
    }
    final own = parting[step];
    final n = own.keys.length;
    final next = step + 1 < parting.length ? parting[step + 1] : null;
    // A position: an own sentence j after the mention's is j, a sentence j
    // of the next step is n + j.
    int? first;
    void consider(int? p) {
      if (p != null && (first == null || p < first!)) {
        first = p;
      }
    }

    for (final w in _wordsOf(
      sentence,
      (w) =>
          own.dripped.containsKey(w) ||
          own.discarded.containsKey(w) ||
          (next?.discarded.containsKey(w) ?? false),
    )) {
      // The mixture the mention names drips back, in its step.
      consider(_firstAbove(own.dripped[w], k));
      // A food the mention names is drained and discarded, in its step or
      // the next.
      if (w != head) {
        consider(_firstAbove(own.discarded[w], k));
        final there = next?.discarded[w];
        consider(there == null ? null : n + there.first);
      }
    }
    // Anything else drained after an "add … toss" in its step.
    final toss = _firstAbove(own.tosses, k);
    if (toss != null) {
      consider(_firstAbove(own.drainedBut(head), toss));
    }
    final p = first;
    if (p != null) {
      final cooked = p < n
          ? own.cooks(k + 1, p + 1)
          : own.cooks(k + 1, n) || next!.cooks(0, p - n + 1);
      return cooked ? DiscardedMedium.cookingWater : DiscardedMedium.saltBath;
    }
    return null;
  }

  if (head == 'salt' || head == 'sugar') {
    // The line's first own mention whose sentence parts it — each
    // sentence read once per recipe, however many mentions and lines
    // share it ([_firstOwn]).
    return _firstOwn(recipe, line, (#drainedAway, head), (step, at) {
      final (:start, :end, index: k) = index.sentenceAt(step, at);
      return index.memo(
        // Key: head — never parted from itself; step and k — the sentence.
        ('parted', head, step, k),
        () => parted(step, k, index.lower[step].substring(start, end)),
      );
    })?.value;
  }
  final heads = _headsOf(recipe);
  final same = [
    for (final (i, other) in nutritionLines(recipe).indexed)
      if (heads[i] == head) other,
  ];
  final all = _naming(recipe, head);
  final nth = same.indexWhere((other) => identical(other, line));
  return nth >= 0 && nth < all.length
      ? parted(all[nth].$1, all[nth].$2, index.sentence(all[nth]))
      : null;
}

/// A mention's sentence that combines, whisks or dissolves ([_drainedAway]).
final RegExp _mixes = RegExp(r'\b(combine|whisk|dissolve)');

/// The first of [sorted] above [k], or null.
int? _firstAbove(List<int>? sorted, int k) {
  if (sorted == null) {
    return null;
  }
  final i = _firstAfter(sorted, k, (j) => j, strict: true);
  return i < sorted.length ? sorted[i] : null;
}

/// What each sentence of a step does for [_drainedAway], read once: it
/// cooks; the mixture it drips back ("excess milk mixture to drip back",
/// 1084); the food it drains ("Drain slaw"; not "do not drain", Run 048) by
/// its key word, and whether it discards; whether it adds and tosses.
class _Parting {
  _Parting(List<String> sentences) {
    final drain = RegExp(r'(?<!not )\bdrain\s+(?:the\s+)?([a-z]+)');
    final drip = RegExp(r'excess (\w+) mixture to drip back');
    var cooked = 0;
    cookSum.add(0);
    for (final (j, s) in sentences.indexed) {
      cooked += RegExp(r'\bcook').hasMatch(s) ? 1 : 0;
      cookSum.add(cooked);
      if (drip.firstMatch(s)?[1] case final word?) {
        (dripped[word] ??= []).add(j);
      }
      final key = switch (drain.firstMatch(s)?[1]) {
        final word? => keyWordOf(word),
        null => null,
      };
      keys.add(key);
      if (key != null && s.contains('discard')) {
        (discarded[key] ??= []).add(j);
      }
      if (s.trimLeft().startsWith('add ') && s.contains('toss')) {
        tosses.add(j);
      }
    }
  }

  final List<int> cookSum = [];
  final Map<String, List<int>> dripped = {};
  final Map<String, List<int>> discarded = {};
  final List<int> tosses = [];
  final List<String?> keys = [];
  final Map<String, List<int>> _drainedBut = {};

  /// Whether a sentence in [from, [to]) cooks.
  bool cooks(int from, int to) => cookSum[to] > cookSum[from];

  /// The sentences draining a food other than [head], once per head.
  List<int> drainedBut(String head) => _drainedBut[head] ??= [
    for (final (j, key) in keys.indexed)
      if (key != null && key != head) j,
  ];
}

// v50 (batch M50, prep47 design_v2 §1 Q16, Q17, Q18, Q20, Q21, Q7; §2
// "M50"; the owner's 2026-10-07 standing authorization; zero requests):
// what the steps strain out, remove and discard, keep a printed part of,
// leave in the bowl, or lift out of a marinade — read from the steps alone,
// each sentence family once per recipe ([_StepIndex.memo]).

/// Q16 (D1): the first sentence of [recipe] that strains a liquid and
/// presses or discards its solids ("Strain … pressing on the solids",
/// "… ; discard solids", a next sentence opening "Discard … solids") or
/// strains a stock or broth (the widening) — (step, sentence) — or null:
/// none, or the first such strain is of a purée, a soup, a custard or a
/// batter, whose solids are a food that is eaten (creamy pea soup).
/// v56 (batch M57, prep48 design_v2 §2 M57 S1; critic F4, F14): a strain
/// of "the (braising|cooking|poaching) liquid" ([_strainsTheLiquid])
/// counts too, only when no sentence from it to the end names solids,
/// vegetables, a blender, a food processor or a purée ([_solidsUsedLater]
/// — the pot roasts blend them, the oxtails return them); one that does
/// CONTINUES the scan (F14: never null — a later pressing strain is still
/// found). No purée/soup skip of its own: "strain the cooking liquid into
/// the soup" strains the aromatics out; a purée is in the guard.
(int, int)? _strainAt(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#strainAt, () {
      final index = _stepIndexOf(recipe);
      final all = index.sentences;
      for (final (i, sentences) in all.indexed) {
        for (final (j, s) in sentences.indexed) {
          if (!_strainWord.hasMatch(s)) {
            continue;
          }
          final next = j + 1 < sentences.length
              ? sentences[j + 1]
              : all.skip(i + 1).expand((s) => s).firstOrNull;
          final discardsNext =
              next != null &&
              next.trimLeft().startsWith('discard') &&
              next.contains('solids');
          // Closer 1 (V1-D3): a strain whose next sentence keeps some of
          // the solids ("Measure 1 tablespoon of solids and 1 tablespoon of
          // oil into large bowl", grilled potatoes) discards none whole.
          if (next != null &&
              !next.contains('discard') &&
              _keepsSolids.hasMatch(next)) {
            continue;
          }
          if (_strainedSolids.hasMatch(s) || discardsNext) {
            return _pureeStrain.hasMatch(s) ? null : (i, j);
          }
          if (_strainsTheLiquid.hasMatch(s) &&
              ![
                ...sentences.skip(j),
                ...all.skip(i + 1).expand((s) => s),
              ].any(_solidsUsedLater.hasMatch)) {
            return (i, j);
          }
        }
      }
      return null;
    });

// v62 (M64 H1): "Using slotted spoon, remove solids from pot and discard"
// (guay-tiew tom yum goong) strains with no "strain".
final RegExp _strainWord = RegExp(
  r'\bstrain|\bremove (?:the )?solids\b[^.]*\bdiscard',
);
final RegExp _keepsSolids = RegExp(
  r'\b(?:measure|reserve|transfer|return)\w*\b[^.]*\bsolids\b',
);
final RegExp _strainedSolids = RegExp(
  r'\bstrain (?:the )?(?:stock|broth)\b|\bpress(?:ing)? (?:firmly )?on '
  r'(?:the )?solids|\bdiscard(?:ing)? (?:the |any )?(?:spent )?solids|'
  r'\bsolids in (?:the )?strainer|'
  r'\bremove (?:the )?solids\b[^.]*\bdiscard',
);
final RegExp _pureeStrain = RegExp(
  r'pur[eé]e|\bsoup\b|custard|mixture into|batter',
);
final RegExp _strainsTheLiquid = RegExp(
  r'\bstrain (?:the )?(?:braising |cooking |poaching )?liquid\b',
);
final RegExp _solidsUsedLater = RegExp(
  r'\bsolids\b|\bvegetables\b|blender|food processor|pur[eé]e',
);

/// Q16's classes a strain zeroes ([_strainedOut]), by head noun: aromatic
/// vegetables, herbs, whole spices and peppercorns, kombu. A zest or peel
/// strip is its citrus head with "zest" or "peel" on the line.
const Set<String> _strainedHeads = {
  ..._vegetableHeads,
  'bay', 'thyme', 'rosemary', 'sage', 'parsley', 'cilantro', 'dill',
  'tarragon', 'mint', 'basil', 'oregano', //
  'peppercorn', 'cinnamon', 'anise', 'pod', 'clove', 'coriander', 'cumin',
  'allspice', 'juniper', 'cardamom', 'kombu', 'bonito', 'pi',
};

/// The aromatic vegetables a strain zeroes ([_strainedHeads]).
const Set<String> _vegetableHeads = {
  'onion',
  'shallot',
  'carrot',
  'celery',
  'garlic',
  'leek',
  'ginger',
  'lemongrass',
  'scallion',
  'chile',
  'jalapeno',
  'mushroom',
};

/// Citrus heads whose zest or peel strips a strain zeroes ([_strainedOut]).
const Set<String> _zestHeads = {'lemon', 'lime', 'orange'};

/// Cured pork (Q17): its rendered fat stays in the pot unless a sentence
/// skims, separates or pours it off ([_fatSkimmed]).
final RegExp _curedPork = RegExp(
  r'\b(?:salt pork|bacon|pancetta|prosciutto|ham hock|chorizo)\b',
);

/// Ground meat simmered in a stock (F4): the stock-meat class.
const Set<String> _stockMeatHeads = {
  'beef',
  'pork',
  'chicken',
  'turkey',
  'lamb',
  'veal',
};

/// A ground spice, a powder or a paste passes the strainer with the liquid
/// (critic F3: braised brisket's "1½ teaspoons ground cardamom", audit L214
/// OK at 3 g) — never zeroed as a solid.
final RegExp _passesStrainer = RegExp(r'\b(?:ground|powder|paste)\b');

/// A vessel that is not the strained pot (D1's vessel guard): a mention in
/// a sentence naming one and no pot word is not in the pot.
final RegExp _otherVessel = RegExp(
  r'\bbowl\b|\bmixer\b|food processor|\bblender\b',
);
final RegExp _potWord = RegExp(
  r'\bpot\b|saucepan|dutch oven|skillet|roasting pan',
);

final RegExp _onSheet = RegExp(r'\bsheet\b');

/// A sentence lifting the cooked vegetables out of the pot (V1-D1).
final RegExp _liftsVegetables = RegExp(
  r'\b(?:transfer|remove|lift)\w*\s+(?:the\s+)?vegetables\s+(?:to|onto)\b',
);
final RegExp _vegetablesWord = RegExp(r'\bvegetables\b');

/// "Add the vegetable mixture": a later sentence that carries a processor's
/// lines into the pot (the Sauce Base).
final RegExp _addsMixture = RegExp(r'\badd (?:the )?(?:\w+ )?mixture\b');

/// A sentence that blends a food smooth or into a paste (F3's line
/// history: cochinita pibil's garlic, spices and onion).
final RegExp _blendsSmooth = RegExp(
  'until smooth|smooth paste|into a paste|to a paste|pur[eé]e',
);

/// A sentence that skims, separates or pours off the pot's fat (Q17, F4).
final RegExp _skimsFat = RegExp(
  r'\bskim\w*\b[^.]*\bfat\b|\bfat separator\b|'
  r'\b(?:pour|spoon|drain)\w* off\b[^.]*\b(?:fat|grease)\b',
);

/// Whether each sentence of [recipe]'s steps is inside a parenthesis — a
/// make-ahead note ("(Broth can be refrigerated for up to 3 days. Skim off
/// fat before reheating.)", italian-wedding-soup), never the method.
List<List<bool>> _parenthetical(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#parenthetical, () {
      return [
        for (final sentences in _stepIndexOf(recipe).sentences)
          () {
            var depth = 0;
            return [
              for (final s in sentences)
                () {
                  final inside = depth > 0 || s.trimLeft().startsWith('(');
                  depth += '('.allMatches(s).length - ')'.allMatches(s).length;
                  if (depth < 0) {
                    depth = 0;
                  }
                  return inside;
                }(),
            ];
          }(),
      ];
    });

/// Q17 / F4: whether a sentence of [recipe] (outside a parenthesis) skims,
/// separates or pours off the fat. ponytail: the whole recipe (or section)
/// is the pot — no recipe of the library strains two pots of which only one
/// is skimmed; read the pot's own vessel if one does.
bool _fatSkimmed(Recipe recipe) => _stepIndexOf(recipe).memo(#fatSkimmed, () {
  final index = _stepIndexOf(recipe);
  final inside = _parenthetical(recipe);
  for (final (i, sentences) in index.sentences.indexed) {
    for (final (j, s) in sentences.indexed) {
      if (!inside[i][j] && _skimsFat.hasMatch(s)) {
        return true;
      }
    }
  }
  return false;
});

/// The sentences of each step that blend a food smooth ([_blendsSmooth]),
/// in order, once per recipe.
List<List<int>> _smoothSentences(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#smooth, () {
      return [
        for (final sentences in _stepIndexOf(recipe).sentences)
          [
            for (final (j, s) in sentences.indexed)
              if (_blendsSmooth.hasMatch(s)) j,
          ],
      ];
    });

/// Whether (step, sentence) [a] stands before [b].
bool _before((int, int) a, (int, int) b) =>
    a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2);

/// Where a sentence of [recipe] names [head] as a FOOD ([_naming]) — never
/// only as the word before a broth, stock, juice or fat ("beef broth",
/// "lemon juice", "bacon fat"): the wedding soup's "Add chicken broth, beef
/// broth, and water" is no mention of its meatball beef (A13 would assign
/// it the second beef line).
List<(int, int)> _foodNaming(Recipe recipe, String head) {
  final index = _stepIndexOf(recipe);
  // Key: head — the food each sentence is searched for.
  return index.memo(('foodNaming', head), () {
    return [
      for (final at in _naming(recipe, head))
        if (_names(index.sentence(at).replaceAll(_liquidOf, ' '), head)) at,
    ];
  });
}

final RegExp _liquidOf = RegExp(
  r'\b\w+\s+(?:broth|stock|bouillon|juices?|fat|drippings)\b',
);

/// The line's mentions as A13 assigns them ([_drainedAway]) over
/// [_foodNaming]: the nth line of its head ↔ the nth mention, and the
/// mentions past the last line's — never another line's own.
List<(int, int)> _ownMentions(
  Recipe recipe,
  IngredientLine line,
  String head,
) {
  final heads = _headsOf(recipe);
  final lines = nutritionLines(recipe);
  var nth = -1;
  var same = 0;
  for (final (i, h) in heads.indexed) {
    if (h == head) {
      if (identical(lines[i], line)) {
        nth = same;
      }
      same++;
    }
  }
  final all = _foodNaming(recipe, head);
  return nth < 0 || nth >= all.length
      ? const []
      : [all[nth], ...all.skip(same)];
}

/// Q16 (D1) and Q17: what [recipe]'s strain ([_strainAt]) does to [line]
/// (head [head]) — null when the line is not in the strained liquid or not
/// a solid it keeps: [DiscardedMedium.strainedSolid] (0 g, the policy) for
/// an aromatic, herb, whole spice or zest strip ([_strainedHeads]), and for
/// cured pork or ground stock meat whose fat a sentence skims, separates or
/// pours off ([_fatSkimmed]; stock meat also when blanched and drained,
/// the pho's beef); [DiscardedMedium.fatKept] (held) for cured pork or stock
/// meat whose fat no sentence takes off (Q17; critic F4: the wedding soup's
/// meat). The line is in the liquid when its nth mention (A13,
/// [_ownMentions]) stands before the strain and no sentence after it names
/// its head again (a discard aside): a food named after the strain goes back
/// into the dish (the Calvados chops' apples). Kept: a ground spice, powder
/// or paste ([_passesStrainer], F3); a line a sentence of its own history
/// blends smooth or into a paste ([_blendsSmooth], F3: cochinita pibil); a
/// mention in a bowl, mixer, processor or blender with no pot word, unless
/// a later "add the … mixture" in the pot carries it there (the Sauce
/// Base); a mention in the step of a strain opening "meanwhile" (a second
/// pot: the butternut risotto's onions); a mention on a baking sheet when
/// the strain's step strains another pot (best roast chicken's carrots);
/// an amount-less line.
DiscardedMedium? _strainedOut(
  Recipe recipe,
  IngredientLine line,
  String head,
) {
  final at = _strainAt(recipe);
  if (at == null || line.amounts.isEmpty) {
    return null;
  }
  final raw = line.raw.toLowerCase();
  final cured = _curedPork.hasMatch(raw);
  final meat =
      !cured && _stockMeatHeads.contains(head) && raw.contains(_groundWord);
  final solid =
      !cured &&
      !meat &&
      (_strainedHeads.contains(head) ||
          // A zest strip — never a zest-plus-juice line (its juice is
          // eaten: M47's two parts).
          (_zestHeads.contains(head) &&
              _zestWord.hasMatch(raw) &&
              !raw.contains('juice'))) &&
      !_passesStrainer.hasMatch(raw);
  if (!cured && !meat && !solid) {
    return null;
  }
  final mine = _ownMentions(recipe, line, head);
  if (mine.isEmpty || !_before(mine.first, at)) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // Key: head — a food named after the strain (a discard sentence aside).
  // Closer 1 (V1-D4): the mixture the strain sentence itself strains
  // ("Strain garlic-lemon mixture through fine-mesh strainer", ultracreamy
  // hummus) is the strained liquid when named again ("Process garlic-lemon
  // mixture"), never the garlic back — a mixture the strain does not name
  // may hold kept solids (grilled potatoes' "reserved garlic-oil mixture").
  final strained = [
    for (final m in _strainedMixture.allMatches(index.sentence(at))) m[0]!,
  ];
  final returned = index.memo(('namedAfterStrain', head), () {
    return _foodNaming(recipe, head).any(
      (m) =>
          _before(at, m) &&
          !index.sentence(m).trimLeft().startsWith('discard') &&
          _names(
            strained.fold(
              index.sentence(m),
              (t, x) => t.replaceAll(x, ' '),
            ),
            head,
          ),
    );
  });
  if (returned) {
    return null;
  }
  final nth = index.sentence(mine.first);
  // Closer 1 (V1-D1): a vegetable a sentence lifts out of the pot before
  // the strain ("Using slotted spoon, transfer vegetables to serving
  // platter", french-style chicken and stuffing's carrots) is served,
  // never strained — unless its own mention sets it apart from "the
  // vegetables" ("Sprinkle peppercorns, garlic … over vegetables": the
  // garlic stays in the pot and is strained).
  if (_vegetableHeads.contains(head) &&
      !_vegetablesWord.hasMatch(nth) &&
      index
          .memo(#liftsVegetables, () {
            return [
              for (final (i, sentences) in index.sentences.indexed)
                for (final (j, s) in sentences.indexed)
                  if (_liftsVegetables.hasMatch(s)) (i, j),
            ];
          })
          .any((p) => _before(mine.first, p) && _before(p, at))) {
    return null;
  }
  // A baking sheet is the pot only when the strain's own step names no
  // other: best roast chicken strains the skillet's sauce ("Add water to
  // skillet") while its carrots roast on a sheet; the butterflied lamb
  // strains the sheet's own pan juices.
  if (_onSheet.hasMatch(nth) &&
      !_potWord.hasMatch(nth) &&
      index.memo(#strainsAnotherPot, () {
        final step = index.sentences[at.$1].take(at.$2 + 1).join(' ');
        return _potWord.hasMatch(step) && !_onSheet.hasMatch(step);
      })) {
    return null;
  }
  if (_otherVessel.hasMatch(nth) && !_potWord.hasMatch(nth)) {
    final carries = index.memo(#addsMixture, () {
      return [
        for (final (i, sentences) in index.sentences.indexed)
          for (final (j, s) in sentences.indexed)
            if (_addsMixture.hasMatch(s) &&
                (!_otherVessel.hasMatch(s) || _potWord.hasMatch(s)))
              (i, j),
      ];
    });
    // The carrying sentence is in the pot itself (the wedding soup's "Add
    // bread mixture, beef, and oregano; mix … scraping down bowl" stays in
    // the mixer).
    if (!carries.any((p) => _before(mine.first, p) && _before(p, at))) {
      return null;
    }
  }
  if (mine.first.$1 == at.$1 &&
      index.sentence(at).trimLeft().startsWith('meanwhile')) {
    return null;
  }
  if (solid) {
    final smooth = _smoothSentences(recipe);
    for (final m in mine) {
      if (!_before(m, at)) {
        break;
      }
      final js = smooth[m.$1];
      final k = _firstAfter(js, m.$2, (j) => j);
      if (k < js.length && (m.$1 != at.$1 || js[k] < at.$2)) {
        return null;
      }
    }
    return DiscardedMedium.strainedSolid;
  }
  // Key: head — blanched and drained before the strain (the pho's beef).
  final drained =
      meat &&
      index.memo(('drainedBeforeStrain', head), () {
        return _foodNaming(recipe, head).any(
          (m) => _before(m, at) && _drainWord.hasMatch(index.sentence(m)),
        );
      });
  return _fatSkimmed(recipe) || drained
      ? DiscardedMedium.strainedSolid
      : DiscardedMedium.fatKept;
}

final RegExp _groundWord = RegExp(r'\bground\b');
final RegExp _strainedMixture = RegExp(r'\b\w+(?:-\w+)+\s+mixture\b');
final RegExp _zestWord = RegExp(r'\b(?:zest|peel)\b');

/// Q18 (D2): every clause of [recipe]'s steps that discards named foods
/// ("(remove and) discard (the) <noun list>", "…, discarding celery
/// bundle") — its (step, sentence), the noun list as written (cut at the
/// first preposition or verb), and whether it is the "remaining" form (Q20
/// (iii): the rest of a food) — once per recipe. v62 (batch M64 R4): a
/// "remove (the) <noun list>" clause too ([_removeOf], `removes`), with
/// or without a "discard" after it — read for the bay leaf only
/// ([_discardedByName]): "Remove the bay leaf from the sauce and discard"
/// (pasta with creamy tomato sauce), "remove bay leaves" (hearty beef
/// stew).
List<({int step, int sentence, String objects, bool remaining, bool removes})>
_discardClauses(Recipe recipe) => _stepIndexOf(recipe).memo(#discards, () {
  final index = _stepIndexOf(recipe);
  return [
    for (final (i, sentences) in index.sentences.indexed)
      for (final (j, s) in sentences.indexed)
        for (final (verb, removes) in [
          if (s.contains('discard')) (_discardOf, false),
          if (s.contains('remove')) (_removeOf, true),
        ])
          for (final m in verb.allMatches(s))
            // The noun list is the last group of either verb.
            if (m[m.groupCount]!.substring(
                  0,
                  _objectEnd.firstMatch(m[m.groupCount]!)?.start ??
                      m[m.groupCount]!.length,
                )
                case final objects
                // "Discard all but 3 tablespoons of the rendered bacon
                // fat": the fat poured off (M49's D3), never the food it
                // names.
                when !_fatObject.hasMatch(objects))
              (
                step: i,
                sentence: j,
                objects: objects,
                remaining: !removes && m[1] != null,
                removes: removes,
              ),
  ];
});

final RegExp _discardOf = RegExp(
  r'\bdiscard(?:ing)?\s+(?:the\s+)?((?:any\s+)?remaining\s+)?([^.;:(]*)',
);
// The noun list stops at the next "remove", which starts its own clause
// ("Remove stew from oven and remove bay leaves", hearty beef and vegetable
// stew) — consumed, so a sentence is read once (RULE C).
final RegExp _removeOf = RegExp(
  r'\bremove\s+(?:the\s+)?((?:(?!\bremove\b)[^.;:(])*)',
);
final RegExp _fatObject = RegExp(
  r'^(?:all but|any|excess)\b|\b(?:fat|oil|grease|drippings|liquid)\b',
);
final RegExp _objectEnd = RegExp(
  r'\b(?:from|in|into|with|to|onto|on|off|then|leaving|before|after)\b|'
  r'(?:,|\band)\s*(?:stir|season|serve|ladle|transfer|toss|let|return|'
  'add|pour|place|allow|continue|cook|cut|sprinkle|skim|spoon|remove|use|'
  r'then|whisk|fold|squeeze|set)\b',
);

/// Q18's whole-piece aromatics (D2), by head: bay, a cinnamon stick, star
/// anise, kombu, an herb or cilantro bundle, onion halves or rounds, a
/// garlic head or crushed cloves, bell-pepper halves, a celery bundle,
/// citrus in a cavity — and v68 (M70, pF F3) a cheese rind simmered and
/// discarded ("Discard the bay leaf and Parmesan rind"; a line that also
/// shreds the cheese is cut fine, never zeroed: [_cutFine]).
const Set<String> _wholePieceHeads = {
  'rind',
  'bay',
  'cinnamon',
  'anise',
  'pod',
  'kombu',
  'cilantro',
  'thyme',
  'rosemary',
  'sage',
  'parsley',
  'oregano',
  'onion',
  'garlic',
  'pepper',
  'celery',
  'lemon',
  'lime',
  'orange',
};

/// A line partly or wholly cut fine: its cut part is eaten ("2 medium
/// onions, 1 quartered and 1 chopped fine"), so a discard never zeroes it.
final RegExp _cutFine = RegExp(
  r'\b(?:minced|chopped|diced|grated|crumbled|shredded)\b|sliced thin|'
  'thinly sliced',
);

/// Q18 (D2) and Q17: [line] (head [head]) removed and discarded by name —
/// the clause's step, and the medium: [DiscardedMedium.removedAromatic]
/// (0 g, the policy) for a whole-piece aromatic ([_wholePieceHeads], never
/// one cut fine, ground or a paste; citrus only from a cavity), for an
/// aromatic or whole spice a sentence ties into a bundle a later sentence
/// removes or discards (the farmhouse soup's "remove herb bundle"), and
/// for cured pork whose pot's fat a sentence takes off ([_fatSkimmed]);
/// [DiscardedMedium.fatKept] (held) for cured pork whose fat stays
/// (milk-braised pork loin: "discard salt pork, leaving fat in pot"). The
/// clause names the head and stands at or after the line's nth mention
/// (A13). Null otherwise.
({DiscardedMedium medium, int step})? _discardedByName(
  Recipe recipe,
  IngredientLine line,
  String head,
) {
  if (line.amounts.isEmpty) {
    return null;
  }
  final raw = line.raw.toLowerCase();
  final cured = _curedPork.hasMatch(raw);
  final whole = !_cutFine.hasMatch(raw) && !_passesStrainer.hasMatch(raw);
  if (!cured &&
      (!whole ||
          !(_wholePieceHeads.contains(head) ||
              _strainedHeads.contains(head)))) {
    return null;
  }
  final mine = _ownMentions(recipe, line, head);
  if (mine.isEmpty) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // A bundle tied up and then removed or discarded ("Using kitchen twine,
  // tie together parsley sprigs, thyme sprigs, and bay leaf" … "remove herb
  // bundle", the farmhouse soup, audit L232; a cheesecloth spice bundle):
  // the lines its tying sentence (tie, twine) names before it — never one
  // a later "Add cheesecloth bundle, oxtails, … mushrooms" names. Once per
  // recipe.
  final bundles = index.memo(#bundles, () {
    return [
      for (final (i, sentences) in index.sentences.indexed)
        for (final (j, s) in sentences.indexed)
          if (_removesBundle.hasMatch(s)) (i, j),
    ];
  });
  for (final at in bundles) {
    // Never a citrus line: its juice is eaten ("12 (3-inch) strips lemon
    // zest plus 6 tablespoons juice", avgolemono's spice bundle).
    if (!cured &&
        !_zestHeads.contains(head) &&
        _before(mine.first, at) &&
        _tiesBundle.hasMatch(index.sentence(mine.first))) {
      return (medium: DiscardedMedium.removedAromatic, step: at.$1);
    }
  }
  if (!cured && !_wholePieceHeads.contains(head)) {
    return null;
  }
  for (final c in _discardClauses(recipe)) {
    final at = (c.step, c.sentence);
    // v62 (M64 R4): a "remove" clause zeroes the bay leaf only — every
    // other whole piece a step removes may be removed to be used (the
    // stuffed peppers lifted from the pot, a garlic head squeezed into the
    // butter, the poached salmon's lemons).
    if (c.remaining ||
        (c.removes && head != 'bay') ||
        _before(at, mine.first) ||
        !_names(c.objects, head) ||
        (_zestHeads.contains(head) && !index.sentence(at).contains('cavity'))) {
      continue;
    }
    return (
      medium: !cured || _fatSkimmed(recipe)
          ? DiscardedMedium.removedAromatic
          : DiscardedMedium.fatKept,
      step: c.step,
    );
  }
  return null;
}

/// The share of [line] (head [head]) its [medium] takes and that part as
/// the basis prints it ("1 of 2"), or null when the whole line goes:
/// - the line's own "remaining N <unit> <head>" part ([_remainingPartOf]);
/// - F12, a COUNT line [_discardedByName] discards when the steps take "N
///   of the <head>" (classic roast lemon chicken: "Cut 1 of the lemons …
///   in the cavity", "Discard the lemons", "Halve the remaining lemon") or
///   "N <head> half / quarter" (closer 1, V1-D2: cuban black beans' "1
///   bell pepper half, 1 onion half" in the beans' pot, "Cut the remaining
///   peppers and onion") before the discard and use "the remaining <head>"
///   after it — N ÷ (the count × the pieces of each).
({double share, String part})? _discardedShareOf(
  Recipe recipe,
  IngredientLine line,
  String head,
  DiscardedMedium medium,
) {
  final own = _remainingPartOf(recipe, line, head, medium);
  if (own != null || medium != DiscardedMedium.removedAromatic) {
    return own;
  }
  final count = countOf(line.amounts);
  final named = _discardedByName(recipe, line, head);
  if (count == null || named == null) {
    return null;
  }
  final index = _stepIndexOf(recipe);
  // Key: head — the partition's words; step — the discard's step.
  final (taken, remaining) = index.memo(('partition', head, named.step), () {
    (double, int)? taken;
    var remaining = false;
    for (final (i, sentences) in index.sentences.indexed) {
      for (final s in sentences) {
        for (final m in _nOfThe.allMatches(s)) {
          if (i <= named.step && _names(m[2]!, head)) {
            taken ??= (double.tryParse(m[1]!) ?? _numberWords[m[1]!]!, 1);
          }
        }
        for (final m in _nPieces.allMatches(s)) {
          if (i <= named.step &&
              _names(m[2]!, head) &&
              !_cutInto.hasMatch(m[2]!)) {
            taken ??= (
              double.tryParse(m[1]!) ?? _numberWords[m[1]!]!,
              m[3]!.startsWith('q') ? 4 : 2,
            );
          }
        }
        for (final m in _theRemaining.allMatches(s)) {
          if (i >= named.step && _names(m[1]!, head)) {
            remaining = true;
          }
        }
      }
    }
    return (taken, remaining);
  });
  if (taken == null || !remaining) {
    return null;
  }
  final (n, pieces) = taken;
  final whole = count * pieces;
  return n < whole
      ? (
          share: n / whole,
          part: pieces == 1
              ? '${_fmtCount(n)} of ${_fmtCount(count)}'
              : '${_fmtCount(n)} of ${_fmtCount(whole)} '
                    '${pieces == 2 ? 'halves' : 'quarters'}',
        )
      : null;
}

/// Closer 1 (V1-D3): a part of [line] (head [head]) its own mention
/// ([_ownMentions]) prints as "remaining N [<unit>] … <head>" — the share
/// [medium] takes and that part as the basis prints it, or null. A strained
/// solid whose remaining part stands in another vessel (a bowl, no pot
/// word) before the strain keeps it (poached salmon: "Scatter 2 tablespoons
/// of the shallot" in the poaching liquid, "combine the remaining 2
/// tablespoons shallot … in a medium bowl" — 2 of 4 tablespoons strained);
/// a removed aromatic whose remaining part a sentence ties into the
/// discarded bundle loses only that part (drunken beans: "Pick leaves from
/// 20 cilantro sprigs", "tie remaining 10 cilantro sprigs and reserved
/// stems into bundle" — 10 of 30 discarded).
({double share, String part})? _remainingPartOf(
  Recipe recipe,
  IngredientLine line,
  String head,
  DiscardedMedium medium,
) {
  final index = _stepIndexOf(recipe);
  final parts = index.memo(#remainingParts, () {
    return [
      for (final (i, sentences) in index.sentences.indexed)
        for (final (j, s) in sentences.indexed)
          for (final m in _remainingN.allMatches(s)) (at: (i, j), match: m),
    ];
  });
  if (parts.isEmpty) {
    return null;
  }
  final mine = _ownMentions(recipe, line, head);
  final strain = _strainAt(recipe);
  for (final (:at, :match) in parts) {
    if (!mine.contains(at) || !_names(match[3]!, head)) {
      continue;
    }
    final s = index.sentence(at);
    final kept = switch (medium) {
      DiscardedMedium.strainedSolid
          when strain != null &&
              _before(at, strain) &&
              _otherVessel.hasMatch(s) &&
              !_potWord.hasMatch(s) =>
        true,
      DiscardedMedium.removedAromatic when _tiesBundle.hasMatch(s) => false,
      _ => null,
    };
    final unit = match[2];
    final one = unit == null
        ? 1.0
        : volumeMlOf(parseIngredientLine('1 $unit x').amounts);
    final whole = unit == null
        ? countOf(line.amounts)
        : volumeMlOf(line.amounts);
    final part = unit == null
        ? countOf(parseIngredientLine('${match[1]} x').amounts)
        : volumeMlOf(parseIngredientLine('${match[1]} $unit x').amounts);
    if (kept == null ||
        one == null ||
        whole == null ||
        part == null ||
        part >= whole) {
      continue;
    }
    final gone = kept ? whole - part : part;
    return (
      share: gone / whole,
      part:
          '${_fmtCount(gone / one)} of ${_fmtCount(whole / one)}'
          '${unit == null ? '' : ' $unit'}',
    );
  }
  return null;
}

final RegExp _remainingN = RegExp(
  '\\bremaining\\s+($_amountRun)\\s*(tablespoons?|teaspoons?|cups?)?\\s*'
  r'((?:[a-z]+\s+){0,2}[a-z]+)',
);

final RegExp _removesBundle = RegExp(
  r'\b(?:remove|discard)\w*\s+(?:the\s+)?(?:\w+\s+)?bundles?\b',
);
final RegExp _tiesBundle = RegExp(r'\bti(?:e|ed|es)\b|\btwine\b');

final RegExp _nOfThe = RegExp(r'\b(\d+|one|two|three|four) of the (\w+)');
// "the remaining peppers and onion" (cuban black beans) names both.
final RegExp _theRemaining = RegExp(r'\bthe remaining ((?:\w+\s+){0,3}\w+)');
final RegExp _nPieces = RegExp(
  r'\b(\d+|one|two|three|four)\s+((?:[a-z]+\s+){0,2}?[a-z]+)\s+'
  r'(halves|half|quarters?)\b',
);
// "Cut 1 lemon in half" is one whole lemon, never a half.
final RegExp _cutInto = RegExp(r'\b(?:in|into)$');
const Map<String, double> _numberWords = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
};

/// What [_partialUseOf] reads of a line (Q20).
typedef _PartialUse = ({
  String kind,
  int step,
  double? share,
  double? cookedGrams,
  ({int fdcId, double carbs, String state})? cookedRecord,
  String printed,
  bool pieces,
});

/// The grams [partial] keeps of a line [resolved] weighs on [food] (Q20):
/// the line less the remainder saved; a potato's kept cooked weight at the
/// raw record's grams by FDC carbohydrate (its `cookedRecord`'s over
/// [food]'s, never more than the line); none (0 g) for a food
/// reserved or discarded whole.
GramResolution? _partialKept(
  _PartialUse partial,
  GramResolution resolved,
  FdcFood food,
) {
  final carbs = food.nutrientsPer100g['205'] ?? 0;
  final grams = switch (partial.kind) {
    'remainder' => resolved.grams * (1 - partial.share!),
    'cooked' =>
      carbs > 0
          ? min(
              resolved.grams,
              partial.cookedGrams! * partial.cookedRecord!.carbs / carbs,
            )
          : resolved.grams,
    _ => null,
  };
  return grams == null
      ? null
      : GramResolution(
          grams: grams,
          source: GramSource.discarded,
          basis: resolved.basis,
        );
}

/// Q20 (D4): a printed part of [line] (head [head]) the steps keep, the
/// rest reserved or discarded — the step, and what is kept:
/// - `remainder` (i): "Save the remaining 6 tablespoons butter for another
///   use" — `share` the part not used (6 of 16 tablespoons); v62 (batch
///   M64 P10, `pieces`): a counted part set aside — "Peel, halve, and
///   core pears. Set aside 1 pear half and reserve for other use" (pear-
///   walnut upside-down cake) — `share` N halves (quarters) of the line's
///   count × 2 (× 4): 1 of 6;
/// - `cooked` (ii): a potato kept by a printed COOKED weight — "Transfer 3
///   cups (16 ounces) warm potatoes" (gnocchi), "Measure 1 very firmly
///   packed cup potatoes" with the prep note's "1 very firmly packed cup
///   (½ pound) of mash" (buns) — `cookedGrams` of the `cookedRecord`'s
///   flesh (baked: SR 170033, boiled: SR 170114), converted to the raw
///   record by FDC carbohydrate in [engineOutcome] (critic F18: riced flesh
///   on a flesh-only record);
/// - `reserved` / `rest` (iii): a whole food reserved for another use
///   ("transfer the wings to a dinner plate to reserve for another use") or
///   the rest of it discarded ("Discard remaining beer and can") — 0 g.
/// A kept VOLUME with no printed weight (iv) is no part here: it is
/// counted whole and flagged ([_keptVolumeOf]). Null otherwise.
_PartialUse? _partialUseOf(Recipe recipe, IngredientLine line, String head) {
  if (line.amounts.isEmpty) {
    return null;
  }
  _PartialUse use(
    String kind,
    int step, {
    double? share,
    double? cookedGrams,
    ({int fdcId, double carbs, String state})? cookedRecord,
    String printed = '',
    bool pieces = false,
  }) => (
    kind: kind,
    step: step,
    share: share,
    cookedGrams: cookedGrams,
    cookedRecord: cookedRecord,
    printed: printed,
    pieces: pieces,
  );
  final index = _stepIndexOf(recipe);
  if (head == 'potato') {
    for (final (:step, sentence: _, :match) in _sentencesMatching(
      recipe,
      #keptCooked,
      _keptCooked,
    )) {
      final printed =
          match[3] ??
          RegExp(
            '${RegExp.escape(match[2] ?? '')}cups?\\s+\\(([^)]*)\\)',
          ).firstMatch((recipe.prepNotes ?? '').toLowerCase())?[1];
      final grams = printed == null
          ? null
          : weightGramsOf(parseIngredientLine('$printed x').amounts);
      final before = index.lower.take(step + 1).join(' ');
      final record = _bakes.hasMatch(before)
          ? _bakedFlesh
          : _boils.hasMatch(before)
          ? _boiledFlesh
          : null;
      if (grams != null && record != null) {
        return use(
          'cooked',
          step,
          cookedGrams: grams,
          cookedRecord: record,
          printed: printed!,
        );
      }
    }
  }
  for (final (:step, sentence: _, :match) in _sentencesMatching(
    recipe,
    #savesRemainder,
    _savesRemainder,
  )) {
    if (!_names(match[3]!, head)) {
      continue;
    }
    final part = parseIngredientLine('${match[1]} ${match[2]} x').amounts;
    final byVolume = volumeMlOf(line.amounts) != null;
    final own = byVolume
        ? volumeMlOf(line.amounts)
        : weightGramsOf(line.amounts);
    final saved = byVolume ? volumeMlOf(part) : weightGramsOf(part);
    if (own != null && saved != null && saved < own) {
      return use(
        'remainder',
        step,
        share: saved / own,
        printed: '${match[1]!.trim()} ${match[2]}',
      );
    }
  }
  // v62 (M64 P10): never by widening [_reservedWhole] — "Set aside 1 pear
  // half" is no [_partOnly] sentence, so the whole line would go.
  final count = countOf(line.amounts);
  for (final (:step, sentence: _, :match) in _sentencesMatching(
    recipe,
    #setsAsidePieces,
    _setsAsidePieces,
  )) {
    final n = double.tryParse(match[1]!) ?? _numberWords[match[1]!]!;
    final each = match[3]!.startsWith('q') ? 4 : 2;
    if (count != null && _names(match[2]!, head) && n < count * each) {
      return use(
        'remainder',
        step,
        share: n / (count * each),
        printed: '${match[1]} ${match[2]} ${match[3]}',
        pieces: true,
      );
    }
  }
  if (_keptVolumeOf(recipe, line, head) != null) {
    return null;
  }
  for (final (:step, :sentence, match: _) in _sentencesMatching(
    recipe,
    #reservedWhole,
    _reservedWhole,
  )) {
    if (!_partOnly.hasMatch(sentence) && _names(sentence, head)) {
      return use('reserved', step);
    }
  }
  for (final c in _discardClauses(recipe)) {
    if (c.remaining && _names(c.objects, head)) {
      return use('rest', c.step);
    }
  }
  return null;
}

final RegExp _keptCooked = RegExp(
  '\\b(?:transfer|measure)\\s+($_amountRun)\\s*'
  r'((?:very\s+)?(?:firmly\s+|lightly\s+)?packed\s+)?cups?\s+'
  r'(?:\(([^)]*)\)\s+)?(?:warm\s+|cooked\s+|riced\s+|mashed\s+)?potato',
);
final RegExp _bakes = RegExp(r'\bbake');
final RegExp _boils = RegExp(r'\b(?:boil|simmer)');

/// SR 170033 "Potatoes, baked, flesh, without salt": 21.6 g carbohydrate
/// per 100 g (a cached search hit, critic F18 — the riced flesh, never the
/// flesh-and-skin 170030).
const ({int fdcId, double carbs, String state}) _bakedFlesh = (
  fdcId: 170033,
  carbs: 21.6,
  state: 'baked',
);

/// SR 170114 "Potatoes, boiled, cooked in skin, flesh, with salt": 20.1 g
/// carbohydrate per 100 g (a cached search hit; P1 D4b's buns figure).
const ({int fdcId, double carbs, String state}) _boiledFlesh = (
  fdcId: 170114,
  carbs: 20.1,
  state: 'boiled',
);

final RegExp _savesRemainder = RegExp(
  '\\b(?:save|reserve)\\s+(?:the\\s+)?remaining\\s+($_amountRun)\\s*'
  r'(tablespoons?|teaspoons?|cups?|ounces?|pounds?|sticks?)\s+'
  r'([^.;]*?)\s*for another use',
);
final RegExp _reservedWhole = RegExp(r'\breserve for another use\b');
final RegExp _setsAsidePieces = RegExp(
  r'\bset aside (\d+|one|two|three|four) ((?:[a-z]+\s+){0,2}?[a-z]+)\s+'
  r'(halves|half|quarters?)\s+(?:and reserve\s+)?for (?:an)?other use\b',
);
final RegExp _partOnly = RegExp(r'\bremain|\bexcess\b|\bany\b');

/// Q20 (iv): a kept VOLUME of [line]'s food with no printed weight —
/// "Measure 1⅓ cups lightly packed potato; discard the remaining potato"
/// (deep-dish pizza), "Measure out 1 cup bread crumbs … (set aside
/// remainder for another use)" — the volume as written, on a line not
/// itself measured by volume; null otherwise. Counted whole, flagged "the
/// steps keep only {volume} of it" (no source weighs a riced potato or a
/// fresh crumb by the cup).
String? _keptVolumeOf(Recipe recipe, IngredientLine line, String head) {
  if (volumeMlOf(line.amounts) != null) {
    return null;
  }
  // The word before the item's head ("dried porcini mushroom": porcini).
  final words = normalizeItem(lineItemOf(line)).split(' ');
  final modifier = words.length < 2 ? null : words[words.length - 2];
  for (final (step: _, sentence: s, match: m) in _sentencesMatching(
    recipe,
    #measuresOut,
    _measuresOut,
  )) {
    if (_restAside.hasMatch(s) &&
        (_names(m[2]!, head) ||
            // Closer 1 (V1-D4): "Measure out 2 teaspoons porcini powder"
            // names "⅛ ounce dried porcini mushrooms" by its own word.
            (modifier != null && _names(m[2]!, modifier)))) {
      return m[1];
    }
  }
  return null;
}

/// Each sentence of [recipe]'s steps [pattern] matches — its step, the
/// sentence and its first match — once per recipe under [key] (one pattern
/// per key; RULE C: a line reads the few matches, never the steps).
List<({int step, String sentence, Match match})> _sentencesMatching(
  Recipe recipe,
  Symbol key,
  RegExp pattern,
) => _stepIndexOf(recipe).memo(key, () {
  return [
    for (final (i, sentences) in _stepIndexOf(recipe).sentences.indexed)
      for (final s in sentences)
        if (pattern.firstMatch(s) case final m?)
          (step: i, sentence: s, match: m),
  ];
});

final RegExp _measuresOut = RegExp(
  '\\bmeasure\\s+(?:out\\s+)?($_amountRun\\s*'
  r'(?:cups?|tablespoons?|teaspoons?))\s+((?:\w+\s+){0,3}\w+)',
);
final RegExp _restAside = RegExp(
  r'\b(?:discard|reserve|set aside)\s+(?:the\s+)?(?:any\s+)?remain(?:ing|der)',
);

/// The positions of [recipe]'s lines whose nth mention (A13) stands in one
/// of [at]'s sentences.
Set<int> _linesNamedIn(Recipe recipe, Set<(int, int)> at) {
  final heads = _headsOf(recipe);
  final seen = <String, int>{};
  final out = <int>{};
  for (final (i, head) in heads.indexed) {
    if (head == null) {
      continue;
    }
    final nth = seen[head] = (seen[head] ?? -1) + 1;
    final all = _naming(recipe, head);
    if (nth < all.length && at.contains(all[nth])) {
      out.add(i);
    }
  }
  return out;
}

/// Q21 (D5): the positions of [recipe]'s lines a dip, batter, glaze or egg
/// wash leaves an excess of in the bowl — "Scrape off excess chocolate"
/// (the macaroons), "allowing the excess batter to drip off", "let the
/// excess egg run off", "(you won't need all of it)", "Discard remaining
/// glaze" — counted whole and flagged; once per recipe. A food word
/// (chocolate, egg) flags its own lines; a mixture word (batter, glaze,
/// coating, dough) the lines a whisk, combine, stir, beat, mix or sift
/// sentence names in the dip's step or the step before it (never one
/// putting the food in the mixture or coating it), with the making step of
/// a "<line head> mixture" those sentences continue (fish-and-chips' flour
/// mixture, closer 1) and, for a glaze, the step that reduces it (negimaki).
/// ponytail: a glaze whose liquid is mixed steps before its reduction
/// stays unflagged (the spareribs' braising liquid); follow the liquid's
/// own name back if a flag must reach it.
/// v56 (M58): each position maps to the dip words that reached it — a
/// batter's lines join the coat budget ([_m52Plan]), a glaze the steps
/// divide between two bowls states the split ([m50FlagOf]).
Map<int, Set<String>> _leftInBowl(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#leftInBowl, () {
      final index = _stepIndexOf(recipe);
      final heads = _headsOf(recipe);
      final out = <int, Set<String>>{};
      for (final (i, sentences) in index.sentences.indexed) {
        for (final (j, s) in sentences.indexed) {
          final m = _dipExcess.firstMatch(s);
          // v60 (M62 E): a dip in an egg or buttermilk mixture is
          // [_dipsOf]'s (its lines are the mixture's, never every line of
          // the food word).
          final word = m == null || m[1] != null
              ? null
              : m[2] ?? m[3] ?? _dipWord.firstMatch(s)?[1];
          if (word == null) {
            continue;
          }
          if (word == 'chocolate' || word == 'egg') {
            for (final (k, head) in heads.indexed) {
              if (head == word) {
                (out[k] ??= {}).add(word);
              }
            }
            continue;
          }
          // A making sentence of step [a], never one dipping the food in
          // it ("Place half of wings in batter and stir to coat").
          Set<(int, int)> making(int a) => {
            for (final (b, t) in index.sentences[a].indexed)
              if ((a < i || b < j) &&
                  _mixVerb.hasMatch(t) &&
                  !t.contains('in $word') &&
                  !t.contains('in the $word') &&
                  !t.contains('to coat'))
                (a, b),
          };
          final made = {
            for (var a = i > 0 ? i - 1 : 0; a <= i; a++) ...making(a),
          };
          // Closer 1 (V1-D5): the batter a window sentence continues from
          // an earlier mixture ("Add 1¼ cups of the beer to the flour
          // mixture in the mixing bowl", fish-and-chips' step 4) joins that
          // mixture's making step (step 2's flour … baking powder, audit
          // L206); a glaze joins the step that reduces it ("cook until
          // slightly syrupy and reduced to ½ cup", negimaki).
          for (final p in [...made]) {
            for (final x in _mixtureOf.allMatches(index.sentence(p))) {
              if (!heads.contains(x[1])) {
                continue;
              }
              for (var a = 0; a < p.$1; a++) {
                if (index.sentences[a].any(
                  (t) => _mixVerb.hasMatch(t) && _names(t, x[1]!),
                )) {
                  made.addAll(making(a));
                  break;
                }
              }
            }
          }
          if (word == 'glaze') {
            for (var a = i; a >= 0; a--) {
              if (index.sentences[a].any(_reducesGlaze.hasMatch)) {
                made.addAll(making(a));
                break;
              }
            }
          }
          for (final k in _linesNamedIn(recipe, made)) {
            (out[k] ??= {}).add(word);
          }
        }
      }
      for (final k in _dipsOf(recipe).keys) {
        (out[k] ??= {}).add('dip');
      }
      return out;
    });

/// v60 (M62 E, Q9): the lines of an egg or buttermilk dip whose excess the
/// steps leave in the bowl — "Dip in the egg mixture, allowing the excess
/// to drip off" ([_dipExcess]'s first arm) — each with the dip sentence as
/// written (an H row's `hold_note`, [holdNoteOf]) and where it is, (step,
/// sentence) (v65, M66 R2: a part a LATER step writes is eaten outside the
/// dip, [_m52Plan]); once per recipe. A line
/// is the dip's when a mixing sentence ([_mixVerb]) naming the dip's base
/// word (egg, buttermilk) BEFORE the dip names it: its A13 mention
/// ([_linesNamedIn]'s nth), or any mention of a head no other line shares
/// ("3 large eggs, beaten" — chicken-kiev's first 'egg' mention sets out
/// the plates); its sentence the first dip after that mention. Never a line
/// the steps use as a medium ([discardedMediumOf]: the coat's parts, a
/// frying oil's kept part). Equal to each dip's own made set unioned (each
/// is a prefix of the base's mixing sentences, A13 and the clause monotone
/// in it), read once per base (RULE C: never a scan per dip).
/// v65 (M66 R3', pC R3 — the v60 ponytail's upgrade path): a head two or
/// more lines share names each line by its OWN word — the token right
/// before the head in its item, one word, never "and"/"or", written in
/// no other line of that head ("ground black pepper": black; "cayenne
/// pepper": cayenne) — at every sentence writing it (0117's "beat the
/// eggs, mustard, and black pepper" is |12's, not the first pepper line's;
/// 0315's bare "cayenne" is |5's); a line with none rides A13's order.
/// ponytail: one token, and a line WITH an own word is named only where
/// that word is written — a mixing sentence calling it by its bare head
/// ("the salt, pepper, and cayenne") names it no longer (v64's A13 nth
/// did); only a line with no own word (told apart by a word further from
/// its head, or by none) rides A13's nth mention. No A13 fallback for an
/// own-word line: 0117|8 cayenne, its word only in the crumb sentence,
/// would take the egg sentence's "black pepper" back. Read a bare-head
/// mention no sibling's own word claims if a pin ever needs it.
Map<int, ({String text, (int, int) at})> _dipsOf(
  Recipe recipe,
) => _stepIndexOf(recipe).memo(#dips, () {
  final index = _stepIndexOf(recipe);
  bool before((int, int) a, (int, int) b) =>
      a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2);
  final dips = <RegExp, List<(int, int)>>{};
  for (final (i, sentences) in index.sentences.indexed) {
    for (final (j, s) in sentences.indexed) {
      if (_dipExcess.firstMatch(s)?[1] case final noun?) {
        (dips[noun.startsWith('buttermilk') ? _buttermilkWord : _eggWord] ??=
                [])
            .add((i, j));
      }
    }
  }
  if (dips.isEmpty) {
    return const <int, ({String text, (int, int) at})>{};
  }
  final heads = _headsOf(recipe);
  final lines = nutritionLines(recipe);
  final count = <String, int>{};
  for (final head in heads.nonNulls) {
    count[head] = (count[head] ?? 0) + 1;
  }
  // v65 (M66 R3'): each shared head's lines' words, and in how many of
  // them each word stands — once, O(the lines' words).
  final words = <int, List<String>>{};
  final shared = <String, Map<String, int>>{};
  for (final (j, head) in heads.indexed) {
    if (head != null && count[head]! > 1) {
      final w = words[j] = normalizeItem(lineItemOf(lines[j])).split(' ');
      final tally = shared[head] ??= {};
      for (final x in w.toSet()) {
        tally[x] = (tally[x] ?? 0) + 1;
      }
    }
  }
  // Line [k]'s own word: the one before its head, in no other line of it.
  String? ownWord(int k, String head) {
    final w = words[k]!;
    final h = w.lastIndexWhere((x) => _names(x, head));
    final word = h < 1 ? null : w[h - 1];
    return word == null ||
            !_wordOnly.hasMatch(word) ||
            word == 'and' ||
            word == 'or' ||
            shared[head]![word] != 1
        ? null
        : word;
  }

  final at = <int, (int, int)>{};
  for (final MapEntry(key: base, value: dipped) in dips.entries) {
    final made = <(int, int), bool>{};
    bool mixes((int, int) p) => made[p] ??= () {
      final t = index.sentence(p);
      return _mixVerb.hasMatch(t) && base.hasMatch(t);
    }();
    final seen = <String, int>{};
    for (final (k, head) in heads.indexed) {
      if (head == null) {
        continue;
      }
      final nth = seen[head] = (seen[head] ?? -1) + 1;
      final own = count[head] == 1 ? null : ownWord(k, head);
      final all = _naming(recipe, own ?? head);
      final mentions = count[head] == 1 || own != null
          ? all
          : nth < all.length
          ? [all[nth]]
          : const <(int, int)>[];
      for (final p in mentions) {
        if (!before(p, dipped.last)) {
          break;
        }
        if (mixes(p)) {
          final dip = dipped.firstWhere((d) => before(p, d));
          if (at[k] == null || before(dip, at[k]!)) {
            at[k] = dip;
          }
          break;
        }
      }
    }
  }
  final split = <int, List<String>>{};
  return {
    for (final MapEntry(key: k, value: dip) in at.entries)
      if (discardedMediumOf(
            recipe,
            lines[k],
            normalizeItem(lineItemOf(lines[k])),
          ) ==
          null)
        k: (
          text: () {
            final raw = split[dip.$1] ??= () {
              _count('rawSentences');
              return index.raw[dip.$1].split(_sentenceBreak);
            }();
            return dip.$2 < raw.length
                ? raw[dip.$2].trim()
                : index.sentence(dip).trim();
          }(),
          at: dip,
        ),
  };
});

/// v56 (M58 W): the positions of [recipe]'s lines a batter leaves in the
/// bowl ([_leftInBowl] through the dip word "batter").
Set<int> _batterInBowl(Recipe recipe) => {
  for (final MapEntry(:key, :value) in _leftInBowl(recipe).entries)
    if (value.contains('batter')) key,
};

final RegExp _dipExcess = RegExp(
  // v60 (M62 E): a dip, coat or dredge in an egg or buttermilk mixture with
  // "excess" anywhere in its sentence — first, and from the sentence's
  // start, so it wins wherever it matches (the mixtures before the bare
  // nouns: "egg mixture" never reads as "egg").
  r'^(?=.*excess).*?\b(?:dip|coat|dredg)\w*\b[^.]*?\b(?:in|into|with) '
  r'(?:the )?(egg(?: white)? mixture|buttermilk mixture|egg whites?|eggs?)\b|'
  r'\b(?:scrap|shak|let|allow)\w*\b[^.]*\bexcess (chocolate|batter|glaze|'
  r'egg|coating)\b|\bdiscard (?:the )?remaining (glaze|dough)\b|'
  r'\blet the excess run off|won.t need all of it',
);
final RegExp _eggWord = RegExp(r'\beggs?\b');
final RegExp _buttermilkWord = RegExp(r'\bbuttermilk\b');
final RegExp _dipWord = RegExp(r'\b(chocolate|batter|glaze|egg|coating)');
final RegExp _mixVerb = RegExp(r'\b(?:whisk|combine|stir|beat|mix|sift)');
final RegExp _mixtureOf = RegExp(r'\b(\w+) mixture\b');
final RegExp _reducesGlaze = RegExp(r'\bsyrupy\b|\breduced to\b');

/// Q7 (D6): the positions of [recipe]'s lines of a marinade the food is
/// lifted out of — "Remove chicken from marinade and wipe off excess",
/// "Remove chicken from bag, allowing excess marinade to drip off", "Lift
/// chicken from marinade" — counted as the standing ruling counts them
/// (2026-09-28: "a marinade's food stays counted"), flagged; once per
/// recipe. The marinade is the lines the first step's whisk, combine,
/// process or blend sentences name (before the removal). Never a marinade
/// the steps cook into a sauce ("transfer marinade to small saucepan", the
/// mojo) or keep ("leaving any marinade that sticks", the Thai hens), and
/// never one no step lifts the food from (beef satay, R06: its meat is
/// skewered from the bowl — no sentence removes it). A marinade made by
/// "Process all ingredients in blender" (the rosemary beef kebabs) is the
/// first ingredient group of a recipe that has more than one (closer 1).
Set<int> _liftedFromMarinade(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#liftedFromMarinade, () {
      final index = _stepIndexOf(recipe);
      // "marinade", "marinate", "marinating".
      if (!index.lower.any((s) => s.contains('marina'))) {
        return const <int>{};
      }
      for (final (i, sentences) in index.sentences.indexed) {
        for (final s in sentences) {
          if (!_liftsOut.hasMatch(s) || _keepsMarinade.hasMatch(s)) {
            continue;
          }
          for (final (a, made) in index.sentences.take(i + 1).indexed) {
            final mixes = {
              for (final (b, t) in made.indexed)
                if (_marinadeMix.hasMatch(t)) (a, b),
            };
            if (mixes.isNotEmpty) {
              final named = _linesNamedIn(recipe, mixes);
              // Closer 1 (V1-D5): "Process all ingredients in blender"
              // (the rosemary beef kebabs) is the first ingredient group
              // of a recipe that has more than one.
              return named.isEmpty &&
                      recipe.ingredients.length > 1 &&
                      mixes.any(
                        (p) => index.sentence(p).contains('all ingredients'),
                      )
                  ? {
                      for (
                        var k = 0;
                        k < recipe.ingredients.first.items.length;
                        k++
                      )
                        k,
                    }
                  : named;
            }
          }
          return const <int>{};
        }
      }
      return const <int>{};
    });

final RegExp _liftsOut = RegExp(
  r'\b(?:remove|lift)\b[^.]*\bfrom (?:the )?(?:marinade|bag)\b|'
  r'\bexcess marinade to drip',
);
final RegExp _keepsMarinade = RegExp(
  r'\btransfer\w* (?:the )?marinade\b|\bleaving (?:any )?marinade\b',
);
final RegExp _marinadeMix = RegExp(r'\b(?:whisk|combine|process|blend)');

/// The basis flags of v50 on a counted [line] of [recipe]: Q20 (iv) a
/// kept volume, Q21 a dip left in the bowl, Q7 a marinade lifted from —
/// joined with " · ", or null.
String? m50FlagOf(Recipe recipe, IngredientLine line) {
  final position = nutritionLines(recipe).indexWhere((l) => identical(l, line));
  if (position < 0) {
    return null;
  }
  final head = _headsOf(recipe)[position];
  final kept = head == null ? null : _keptVolumeOf(recipe, line, head);
  final flags = [
    if (kept != null) 'approximate (the steps keep only $kept of it)',
    if (_leftInBowl(recipe)[position] case final words?)
      words.contains('glaze') && _splitsGlaze(recipe)
          ? _splitGlazeFlag
          : _leftInBowlFlag,
    if (_liftedFromMarinade(recipe).contains(position)) _marinadeFlag,
  ];
  return flags.isEmpty ? null : flags.join(' · ');
}

/// The basis of a v50 row counted 0 g or a kept part (`discarded`): what
/// the step did to the line, and its flag. Null for any other medium. A
/// counted part set aside (v62, M64 P10) keeps its line's own [weighing]
/// before it ("3 × 227 g (printed weight) × 0.78 edible · approximate (…;
/// the steps peel it) · 1 pear half saved for another use (step 2) — only
/// the rest counted").
String? _m50DiscardedBasis(
  Recipe recipe,
  IngredientLine line, {
  required String? Function() weighing,
}) {
  final normalized = normalizeItem(lineItemOf(line));
  final head = headNounOf(normalized);
  if (head == null) {
    return null;
  }
  final medium = discardedMediumOf(recipe, line, normalized);
  if (medium == DiscardedMedium.strainedSolid) {
    final part = _discardedShareOf(recipe, line, head, medium!)?.part;
    return 'discarded in cooking${part == null ? ' — counted as 0 g' : ': '
                  '$part — only the rest counted'} · approximate (strained '
        'out and discarded — what it gives the liquid is not counted)';
  }
  if (medium == DiscardedMedium.removedAromatic) {
    final step = _discardedByName(recipe, line, head)!.step + 1;
    final part = _discardedShareOf(recipe, line, head, medium!)?.part;
    return part == null
        ? 'removed and discarded (step $step) — counted as 0 g'
        : 'removed and discarded (step $step): $part — only the rest '
              'counted';
  }
  if (medium != DiscardedMedium.partialUse) {
    return null;
  }
  final use = _partialUseOf(recipe, line, head)!;
  final step = use.step + 1;
  final saved =
      '${use.pieces ? '' : 'the remaining '}${use.printed} saved for '
      'another use (step $step) — only the rest counted';
  return switch (use.kind) {
    'remainder' => [if (use.pieces) ?weighing(), saved].join(' · '),
    'cooked' =>
      'from ${use.printed} cooked (step $step) · approximate (the steps '
          'keep ${use.printed} of the ${use.cookedRecord!.state} potato; its '
          "raw weight by FDC's carbohydrate, ${use.cookedRecord!.fdcId})",
    'reserved' => 'reserved for another use (step $step) — counted as 0 g',
    _ => 'the rest discarded (step $step) — counted as 0 g',
  };
}

const String _leftInBowlFlag =
    'approximate (the steps leave an excess of it in the bowl — how much '
    'is eaten is not written)';

/// v56 (M58, Q10): a glaze the steps divide between two bowls — one served,
/// the other brushed on and its rest discarded (negimaki) — is counted
/// whole (Q21 (a)); its flag states the printed split.
const String _splitGlazeFlag =
    'approximate (the steps divide the glaze evenly between two bowls — '
    'one half served, the other brushed on and its rest discarded; counted '
    'whole)';

/// Whether [recipe]'s steps divide a glaze evenly between two bowls.
bool _splitsGlaze(Recipe recipe) => _stepIndexOf(
  recipe,
).allSentences.any((s) => s.contains('divide evenly between two bowls'));
const String _marinadeFlag =
    'approximate (lifted out of its marinade — how much clings is not '
    'written)';

String _fmtCount(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Whether a step ties [head] into cheesecloth: Home-Corned Beef (0091)
/// puts its "remaining 3 garlic cloves, remaining 2 bay leaves, and
/// remaining 1 tablespoon peppercorns in center of cheesecloth and tie into
/// bundle" — a spice bundle simmered with the brisket and lifted out, so
/// the rest of a brine aromatic is not eaten either and the whole line is
/// zero (Run 045: v13 counted the rest).
bool _bundled(Recipe recipe, String head) {
  final index = _stepIndexOf(recipe);
  return _naming(
    recipe,
    head,
  ).any((at) => index.sentence(at).contains('cheesecloth'));
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
  // Whether the recipe makes cheese: once per Recipe instance ([_headsOf]).
  final cheese = _makesCheese[recipe] ??= () {
    _count('cheese');
    return nutritionLines(recipe).any((other) {
      final item = normalizeItem(lineItemOf(other));
      return headNounOf(item) == 'milk' &&
          discardedMediumOf(recipe, other, item, bySentence: false) ==
              DiscardedMedium.cheeseMilk;
    });
  }();
  if (!cheese) {
    return false;
  }
  final index = _stepIndexOf(recipe);
  final step = index.memo(
    #milkStep,
    () => index.lower.firstWhere(
      (s) => RegExp(r'\bmilk\b').hasMatch(s),
      orElse: () => '',
    ),
  );
  return _names(step, head);
}

/// Whether a step tosses [line]'s salt with a vegetable in a colander and
/// a rinse in that step washes it off (the user's ruling R2: Sesame-Lemon
/// Cucumber Salad, 0052, "Toss the cucumbers with the salt in a colander …
/// drain for 1 to 3 hours. Rinse and pat dry") — or wipes its excess off
/// (the user's ruling Q3, 2026-09-28: Eggplant Parmesan, 0407, "Press
/// firmly on each slice … then wipe off the excess salt"; v13 counted it).
/// (A bowl, a rinse in the
/// next step, "do not rinse", requiring the word "toss" and requiring the
/// rinse AFTER the salt changed no line of the library: Bread-and-Butter
/// Pickles, 0664, tosses in a bowl and does not rinse.)
///
/// Baking soda a food sits in and is rinsed of, in that step or the next,
/// is washed off too — a velveting soak (checkpoint 8: "Combine pork with ½
/// cup cold water and baking soda in bowl. Let sit … 15 minutes" then
/// "Rinse pork in cold water", Sichuan Stir-Fried Pork in Garlic Sauce,
/// 0540; the rinse in the same step, 0553 and 0558).
bool _rinsedSalt(Recipe recipe, IngredientLine line, List<String> steps) {
  final soda = headNounOf(normalizeItem(lineItemOf(line))) == 'soda';
  // Each mention looks up the step's matches, located once per recipe
  // ([_StepIndex]; Run 055 O9: a rescan of the step per mention).
  final index = _stepIndexOf(recipe);
  // Read per mention of the kind (soda is its own kind), never the line.
  return _firstOwn(recipe, line, #rinsedSalt, (step, at) {
        if (soda) {
          return index.startsIn(_rinseWord, step, at) ||
                  (step + 1 < steps.length &&
                      index.hits(_rinseWord, step + 1).isNotEmpty)
              ? true
              : null;
        }
        final (:start, :end, index: _) = index.sentenceAt(step, at);
        return index.startsIn(_colander, step, start, end) &&
                index.hits(_rinsesOrWipes, step).isNotEmpty
            ? true
            : null;
      }) !=
      null;
}

final RegExp _rinseWord = RegExp(r'\brinse\b');
final RegExp _colander = RegExp(r'\bcolander\b');
final RegExp _rinsesOrWipes = RegExp(r'\brins|\bwipe off the excess salt\b');

/// The mentions of [line]'s own salt, baking soda or sugar in the steps: each
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
///
///
/// RULE C at the loop level (v26, Run 056 S8: every line walked every
/// mention of its kind — 400 salt lines on a legal 120-step recipe, ~25 s
/// per compute and per GET): a line owns WHOLE groups of the recipe's
/// mentions ([_mentionsOf]'s `groups`, built in one pass) — the written
/// amounts its raw starts with, the bare ones when it owns them, its
/// paired bare mention, and in cooking water ([drained]) the written pot
/// shares ([_sharesOf]) smaller than it — read once per line (by
/// identity), never by walking the mentions.
({String kind, List<String?> groups, int? paired, double? ml}) _ownsOf(
  Recipe recipe,
  IngredientLine line,
  bool drained,
) {
  final index = _stepIndexOf(recipe);
  final memo = drained ? index.drainedOwns : index.owns;
  return memo[line] ??= () {
    _count('lineMentions');
    final raw = line.raw.toLowerCase();
    final head = headNounOf(normalizeItem(lineItemOf(line)));
    final kind = head == 'soda' || head == 'sugar' ? head! : 'salt';
    if (_plusSalt.hasMatch(raw)) {
      return (kind: kind, groups: const <String?>[], paired: null, ml: null);
    }
    final (:salts, :bare, :bareMentions, :groups, :lengths, mentions: _) =
        _mentionsOf(recipe, kind);
    final ownsBare = salts.length == 1
        ? identical(salts.single, line)
        : drained && bare.length == 1 && identical(bare.single, line);
    final nth = bare.indexWhere((other) => identical(other, line));
    return (
      kind: kind,
      groups: [
        for (final n in lengths)
          if (raw.length >= n && groups.containsKey(raw.substring(0, n)))
            raw.substring(0, n),
        if (ownsBare && groups.containsKey(null)) null,
      ],
      paired:
          !ownsBare && drained && bareMentions.length == bare.length && nth >= 0
          ? bareMentions[nth]
          : null,
      ml: drained ? volumeMlOf(line.amounts) : null,
    );
  }();
}

final RegExp _plusSalt = RegExp(r'\bplus salt\b');

/// The written pot shares of [kind]: each amount a step writes before it
/// that no line of the kind starts with, by its volume (ascending) — a
/// line's share is one smaller than the line ([_firstOwn]). Once per
/// recipe and kind. (Requiring the line marked divided or the step's "of
/// the" / "remaining" changed no line of the library: removed, v13 refix.)
List<({double part, String written})> _sharesOf(Recipe recipe, String kind) =>
    // Key: kind — the mentions and lines read.
    _stepIndexOf(recipe).memo(('shares', kind), () {
      final (:salts, :groups, :lengths, mentions: _, bare: _, bareMentions: _) =
          _mentionsOf(recipe, kind);
      final claimed = {
        for (final lower in salts.map((l) => l.raw.toLowerCase()))
          for (final n in lengths)
            if (lower.length >= n) lower.substring(0, n),
      };
      return [
        for (final written in groups.keys.nonNulls)
          if (!claimed.contains(written))
            if (volumeMlOf(parseIngredientLine('$written salt').amounts)
                case final part?)
              (part: part, written: written),
      ]..sort((a, b) => a.part.compareTo(b.part));
    });

/// [line]'s FIRST own mention ([_ownsOf], in text order) whose [read] is
/// not null: its value and its written pot share (null when the line's
/// own). [read] reads the mention and the kind alone, never the line, so
/// each group's first answer is found once per recipe and [family] — every
/// mention read at most once per family, whatever the line count.
({T value, String? share})? _firstOwn<T extends Object>(
  Recipe recipe,
  IngredientLine line,
  Object family,
  T? Function(int step, int at) read, {
  bool drained = false,
}) {
  final index = _stepIndexOf(recipe);
  final (:kind, :groups, :paired, :ml) = _ownsOf(recipe, line, drained);
  final mentions = _mentionsOf(recipe, kind).mentions;
  T? readAt(int i) {
    _count('mentionVisits');
    return read(mentions[i].step, mentions[i].at);
  }

  // The first of [group] that reads, once per family.
  (int, T)? firstIn(String? group) =>
      // Key: family — the reader; kind and group — the mentions read.
      index.memo(('firstOwn', family, kind, group), () {
        for (final i in _mentionsOf(recipe, kind).groups[group]!) {
          if (readAt(i) case final value?) {
            return (i, value);
          }
        }
        return null;
      });
  (int, T, String?)? best;
  void consider((int, T)? found, String? share) {
    if (found != null && (best == null || found.$1 < best!.$1)) {
      best = (found.$1, found.$2, share);
    }
  }

  for (final group in groups) {
    consider(firstIn(group), null);
  }
  if (paired != null) {
    consider(switch (readAt(paired)) {
      final value? => (paired, value),
      null => null,
    }, null);
  }
  if (ml != null) {
    // The shares smaller than the line, by volume: the earliest of the
    // first [n] is a prefix minimum, once per family.
    final shares = _sharesOf(recipe, kind);
    final n = _firstAfter(shares, 0, (s) => s.part < ml ? -1 : 1);
    // Key: family — the reader (only #drainedMention reads shares today: an
    // equivalent mutant, kept so a second reader never reads its prefix); kind
    // — the shares.
    final prefix = index.memo(('firstShare', family, kind), () {
      (int, T, String)? least;
      return [
        for (final s in shares)
          least = switch (firstIn(s.written)) {
            final f? when least == null || f.$1 < least.$1 => (
              f.$1,
              f.$2,
              s.written,
            ),
            _ => least,
          },
      ];
    });
    // A share the line also owns ([groups]) is its own: equal positions
    // keep the own reading.
    if (n > 0) {
      if (prefix[n - 1] case (final at, final value, final written)) {
        consider((at, value), written);
      }
    }
  }
  return switch (best) {
    (_, final value, final share) => (value: value, share: share),
    null => null,
  };
}

/// The mentions of a [kind] of [recipe] ([_ownsOf]) — each step, the
/// offset and the amount written before it — the [kind]'s lines, the bare
/// ones among them and the bare mentions: located ONCE per recipe and kind
/// ([_StepIndex]; Run 055 S4/O9: every line re-located every mention, and
/// every bare line re-read every mention).
({
  List<({int step, int at, String? written})> mentions,
  List<IngredientLine> salts,
  List<IngredientLine> bare,
  List<int> bareMentions,
  Map<String?, List<int>> groups,
  Set<int> lengths,
})
_mentionsOf(Recipe recipe, String kind) =>
    // Key: kind — the word located.
    _stepIndexOf(recipe).memo(('mentions', kind), () {
      final word = RegExp(switch (kind) {
        'soda' => r'\bbaking soda\b',
        'sugar' => r'\bsugar\b',
        _ => r'\bsalt\b(?!\s+pork)',
      });
      final salts = [
        for (final (i, other) in nutritionLines(recipe).indexed)
          if (_headsOf(recipe)[i] == kind) other,
      ];
      // Bounded ([_amountRun]) and read on the 64 characters before the
      // mention only (Run 054: an unbounded run re-scanned the whole step
      // prefix from every start, once per mention).
      final amount = RegExp(
        '($_amountRun(?:teaspoons?|tablespoons?))\\s+(?:of the\\s+)?\$',
      );
      final mentions = [
        for (final (i, step) in _stepIndexOf(recipe).lower.indexed)
          for (final mention in word.allMatches(step))
            (
              step: i,
              at: mention.start,
              written: amount
                  .firstMatch(
                    step.substring(
                      mention.start < 64 ? 0 : mention.start - 64,
                      mention.start,
                    ),
                  )?[1]
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
      _count('mentions', mentions.length);
      // The written amounts, read by prefix length: a line starts with one of
      // them in O(lengths), never a scan of every mention per line.
      final written = {
        for (final m in mentions)
          if (m.written case final w?) w,
      };
      final lengths = {for (final w in written) w.length};
      bool startsWritten(String raw) => lengths.any(
        (n) => raw.length >= n && written.contains(raw.substring(0, n)),
      );
      final bare = [
        for (final other in salts)
          if (!startsWritten(other.raw.toLowerCase()) &&
              discardedMediumOf(
                    recipe,
                    other,
                    normalizeItem(lineItemOf(other)),
                    bySentence: false,
                  ) ==
                  null)
            other,
      ];
      // Several bare lines and as many bare mentions: a recipe lists a salt
      // where it is first used, so the nth mention is the nth line's — an
      // assumption, never checked against the text: steps that used them in
      // another order would pair them crosswise (Run 045, argued; pinned on a
      // reversed synthesized recipe) (Biang
      // Biang Mian, 0376: "Whisk flour and salt" is the dough's ¾ teaspoon,
      // "bring water and salt to boil" the pot's tablespoon — the user's
      // ruling R2).
      final bareMentions = [
        for (final (i, m) in mentions.indexed)
          if (m.written == null) i,
      ];
      // The mentions by the amount written before them (null: bare), in
      // order — what a line owns is whole groups ([_ownsOf]).
      final groups = <String?, List<int>>{};
      for (final (i, m) in mentions.indexed) {
        (groups[m.written] ??= []).add(i);
      }
      return (
        mentions: mentions,
        salts: salts,
        bare: bare,
        bareMentions: bareMentions,
        groups: groups,
        lengths: lengths,
      );
    });

/// The sentence of step [step] holding offset [at] — from after the period
/// before it to its own period (excluded) — found by binary search over
/// the step's periods ([_StepIndex.sentenceAt]; Run 055 O2: two regex
/// scans of the whole step per mention, quadratic on a period-free step).
String _sentenceAt(_StepIndex index, int step, int at) {
  final (:start, :end, index: _) = index.sentenceAt(step, at);
  return index.lower[step].substring(start, end);
}

/// Whether a step puts [line]'s salt or baking soda ([_ownsOf]) in
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

/// The [_drainedWater] mention of [line]: its written pot share ([_sharesOf],
/// null when the line's whole amount goes in the pot), or null for none.
({String? share})? _drainedMention(
  Recipe recipe,
  IngredientLine line,
  List<String> steps,
) {
  // Every lookup below is a binary search over a step's matches, located
  // once per recipe ([_StepIndex]; Run 055 O2/O3: each mention re-scanned
  // its step, its next step and every later step).
  final index = _stepIndexOf(recipe);
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
  // The liquid must stay behind (Run 045, Opus): a pot simmered dry BEFORE
  // the skimmer ("simmer until water evaporates … Using slotted spoon,
  // transfer beef", Cuban Shredded Beef's shape, 0226), or one the step
  // keeps AFTER it (the liquid reserved, or ladled over the food), leaves
  // its salt or sugar with the food. No corpus salt, soda or sugar line has
  // either shape: each is pinned on a synthesized line (stated exceptions).
  // ("absorb" beside "evaporat" changed no line: removed, v15.)
  final steps = index.lower.length;
  bool hasNext(int step) => step + 1 < steps;
  // Read per mention of the kind (sugar is its own kind), never the line.
  final found = _firstOwn(recipe, line, #drainedMention, drained: true, (
    step,
    at,
  ) {
    // Milk is no water: Saag Paneer's (0563) curds drain, but its salt went
    // in boiled milk. The water must be named BEFORE the end of the salt's
    // own sentence: a salt seasoned onto meat before a later pasta pot is
    // no cooking water — no corpus line has that shape, so the bound is
    // pinned on a synthesized one (a stated exception, review Run 043).
    final (:start, :end, index: _) = index.sentenceAt(step, at);
    if (!index.startsIn(_water, step, 0, end) ||
        index.hits(_boil, step).isEmpty) {
      return null;
    }
    // Or any later step drains a food the boil's sentence names: "Combine
    // chickpeas, baking soda, and 6 cups water … bring to boil", then two
    // steps on "Drain chickpeas in colander" (Ultracreamy Hummus, 0572;
    // checkpoint 8) — read from the step each drained food is last drained
    // in, once per recipe, never a scan of the later steps per mention.
    // Once per sentence, by its step AND start (Run 056 Opus critic 1: by
    // the start alone, every step's first sentence shared one answer —
    // 0572's soda lost its cooking water to one prepended step).
    // Key: step and start — the sentence.
    bool later() => index.memo(('drainedLater', step, start), () {
      final drained = _lastDrainedOf(index);
      return _wordsOf(
        index.lower[step].substring(start, end),
        (w) => (drained[w] ?? -1) >= step + 2,
      ).isNotEmpty;
    });
    if (!sugar &&
        (index.startsIn(_drainWord, step, at) ||
            (hasNext(step) && index.hits(_drainWord, step + 1).isNotEmpty) ||
            later())) {
      return true;
    }
    // The liquid must stay behind (above): no "evaporat" before the
    // skimmer, no "reserv"/"ladle" after it.
    final own = index.firstFrom(_skimmer, step, at);
    if (own != null &&
        !index.startsIn(_evaporat, step, at, own.start) &&
        !index.startsIn(_reservOrLadle, step, own.start) &&
        !(hasNext(step) && index.hits(_reservOrLadle, step + 1).isNotEmpty)) {
      return true;
    }
    final after = own == null && hasNext(step) && _lifted(index, step + 1)
        ? index.hits(_skimmer, step + 1).first
        : null;
    if (after != null &&
        !index.startsIn(_evaporat, step, at) &&
        !index.startsIn(_evaporat, step + 1, 0, after.start) &&
        !index.startsIn(_reservOrLadle, step + 1, after.start)) {
      return true;
    }
    return null;
  });
  return found == null ? null : (share: found.share);
}

final RegExp _water = RegExp(r'\bwater\b');
final RegExp _word = RegExp(r'\w+');
final RegExp _boil = RegExp(r'\bboil');
final RegExp _drainWord = RegExp(r'(?<!not )\bdrain');
final RegExp _skimmer = RegExp(r'\b(skimmer|slotted spoon)\b');
final RegExp _evaporat = RegExp(r'\bevaporat');
final RegExp _reservOrLadle = RegExp(r'\b(reserv|ladle)');

/// Whether a skimmer of step [step] lifts from water its sentence or the
/// one before it names ([_drainedMention]), once per step.
// Key: step — the step read.
bool _lifted(_StepIndex index, int step) => index.memo(('lifted', step), () {
  _count('lifted');
  return index.hits(_skimmer, step).any((m) {
    final ends = index._endsOf(step);
    final before = _firstAfter(ends, m.start, (e) => e);
    final previous = before < 2 ? 0 : ends[before - 2] + 1;
    final (start: _, :end, index: _) = index.sentenceAt(step, m.start);
    return index.startsIn(_water, step, previous, end);
  });
});

/// The step each food is LAST drained in ("Drain the chickpeas"; not "do
/// not drain"), by its key word ([keyWordOf]) — once per recipe.
Map<String, int> _lastDrainedOf(_StepIndex index) => index.memo(#drained, () {
  _count('drained');
  final drained = RegExp(r'(?<!not )\bdrain\s+(?:the\s+)?([a-z]+)');
  return {
    for (final (i, text) in index.lower.indexed)
      for (final m in drained.allMatches(text)) keyWordOf(m[1]!): i,
  };
});

/// The [wanted] key words [_names] finds [sentence] naming: each word as
/// written, less a plural "s" or "es", or "-ies" read "-y". A lookup per
/// word of the sentence, never one per candidate word of the recipe — and
/// each confirmed AT the word ([_namedAt]), never by a rescan of the
/// sentence per word found (RULE C v28, Run 058 O4: a 1,000-character
/// sentence naming 60 heads was rescanned 60 times, the inversion ~35× one
/// head's scan). The same set as `{c : wanted(c) && _names(sentence, c)}`
/// over the words' forms (pinned on every corpus sentence and on seeded
/// random texts: nutrition_v28_rule_c_test.dart).
Iterable<String> _wordsOf(
  String sentence,
  bool Function(String) wanted,
) sync* {
  final found = <String>{};
  for (final m in _word.allMatches(sentence)) {
    final t = m[0]!;
    // [_names]' `(?<!garlic )`: this occurrence names nothing.
    if (m.start >= 7 && sentence.startsWith('garlic ', m.start - 7)) {
      continue;
    }
    for (final c in [
      t,
      if (t.endsWith('s')) t.substring(0, t.length - 1),
      if (t.endsWith('es')) t.substring(0, t.length - 2),
      if (t.endsWith('ies')) '${t.substring(0, t.length - 3)}y',
    ]) {
      if (c.isNotEmpty &&
          !found.contains(c) &&
          _namedAt(t, c) &&
          wanted(c) &&
          found.add(c)) {
        yield c;
      }
    }
  }
}

/// Whether the whole word [t] is a form [_names] reads as [head]: the head,
/// its "s" or "es" plural — or, for a head ending in "y", its "-ies" one
/// (`\b…\b` around a `\w+` word: the match is the whole word).
bool _namedAt(String t, String head) => head.endsWith('y')
    ? t == head || t == '${head.substring(0, head.length - 1)}ies'
    : t == head || t == '${head}s' || t == '${head}es';

/// [_wordsOf] and [_names], for the semantic pin.
@visibleForTesting
Iterable<String> wordsOfForTest(String s, bool Function(String) wanted) =>
    _wordsOf(s, wanted);

/// [_names], for the semantic pin.
@visibleForTesting
bool namesForTest(String text, String head) => _names(text, head);

/// Whether a step dissolves [line]'s salt ([_ownsOf]) in a measured
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
  // Read in the mention's own sentence by binary search over the step's
  // matches, located once per recipe ([_StepIndex]; Run 055 O9).
  final index = _stepIndexOf(recipe);
  return _firstOwn(recipe, line, #dissolvedInWater, (step, at) {
        if (index.hits(_submerg, step).isEmpty) {
          return null;
        }
        final (:start, :end, index: _) = index.sentenceAt(step, at);
        final verb = index.firstFrom(_dissolvVerb, step, start);
        return verb != null &&
                verb.end <= at &&
                index.startsIn(_inAmount, step, at + 1, end)
            ? true
            : null;
      }) !=
      null;
}

final RegExp _submerg = RegExp('submerg');
final RegExp _dissolvVerb = RegExp(r'\bdissolv\w*\b');
final RegExp _inAmount = RegExp('\\bin [\\d$vulgarFractionChars]');

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
  final own = _ownSalt(normalized);
  // The dissolving sentences, once per recipe.
  final index = _stepIndexOf(recipe);
  final dissolving = index.memo(#dissolving, () {
    final dissolv = RegExp(r'\bdissolv');
    return [
      for (final s in index.allSentences)
        if (dissolv.hasMatch(s)) s,
    ];
  });
  // (Another line is brine only when its head is salt, and a twin of the
  // line — the same text — is brine by volume exactly when the line is:
  // neither needs a check of its own, checkpoint 5 review.)
  // RULE C (v26): the lines brine by volume found ONCE per recipe —
  // never every line's every sentence per line (measured: 400 salt lines
  // on 120 legal steps of "Dissolve the salt in the water." ran past
  // 120 s, 400 × 399 × 36,000 substring scans).
  final brined = index.memo(#brinedByVolume, () {
    return [
      for (final other in nutritionLines(recipe))
        if (normalizeItem(lineItemOf(other)) case final item
            when discardedMediumOf(recipe, other, item, bySentence: false) ==
                DiscardedMedium.brine)
          (line: other, item: item),
    ];
  });
  if (brined.every((b) => identical(b.line, line))) {
    return false;
  }
  // RULE C (v27, Run 057 S4/S12: the v26 answer per (salt, brine item)
  // scanned each salt's sentences once per brine item — 200 distinct salts
  // × 199 brine salts, 40,000 memo entries and 104 s a GET): ONE inverted
  // index over the dissolving sentences — where each line's salt and each
  // brine item first occurs in each ([_occurrences]) — then each salt's
  // answer reads its own sentences' brine items, never a pair loop.
  final brineItems = {for (final b in brined) b.item};
  final (:searched, :names) = index.memo(#dissolveIndex, () {
    final searched = {
      ...brineItems,
      for (final other in nutritionLines(recipe))
        _ownSalt(normalizeItem(lineItemOf(other))),
    };
    return (searched: searched, names: _occurrences(dissolving, searched));
  });
  // The brine items each dissolving sentence names: (item, first start).
  final itemsIn = index.memo(#dissolveItems, () {
    final at = <int, List<(String, int)>>{};
    for (final item in brineItems) {
      for (final (k, start) in names[item] ?? const <(int, int)>[]) {
        (at[k] ??= []).add((item, start));
      }
    }
    return at;
  });
  // A brine item the line's own salt is dissolved with: one written in a
  // sentence naming the salt, outside the salt's first mention there (the
  // mention is the line's, not a second salt's: "Dissolve the kosher salt"
  // is no brine "salt" beside a "kosher salt" line). The first two found,
  // once per salt — a brine item is the line's own only when the line is
  // its one brine line, so two answer every line.
  // Key: own — the line's salt (the brine items are the recipe's, one set).
  final found = index.memo(('dissolvedWith', own), () {
    final with_ = <String>{};
    for (final (k, p)
        in searched.contains(own)
            ? names[own] ?? const <(int, int)>[]
            : index.memo(
                    // Key: own — the salt scanned for.
                    ('dissolvingWith', own),
                    () => _occurrences(dissolving, [own]),
                  )[own] ??
                  const <(int, int)>[]) {
      final sentence = dissolving[k];
      for (final (item, first) in itemsIn[k] ?? const <(String, int)>[]) {
        if (!with_.contains(item) &&
            (first + item.length <= p ||
                first >= p + own.length ||
                sentence.contains(item, p + own.length)) &&
            with_.add(item) &&
            with_.length > 1) {
          return with_;
        }
      }
    }
    return with_;
  });
  return found.any(
    (item) => brined.any((b) => b.item == item && !identical(b.line, line)),
  );
}

/// The salt a line names, as [_dissolvedWithBrineSalt] reads its
/// sentences: the last two words of its normalized item ("kosher salt").
String _ownSalt(String normalized) {
  final words = normalized.split(' ');
  return words.skip(words.length > 2 ? words.length - 2 : 0).join(' ');
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
  double? coating = coatingFraction,
}) {
  final normalized = normalizeItem(lineItemOf(line));
  final medium = discardedMediumOf(
    recipe,
    line,
    normalized,
  );
  // Only the first part of a "plus" line is the medium when a step eats
  // the second ([_eatenPlusPart]).
  final plus = medium == null
      ? null
      : _eatenPlusPart(recipe, line, headNounOf(normalized));
  // A divided dredge's or braise's part used outside the medium, eaten.
  final divided = plus != null
      ? null
      : _eatenOutsideMedium(recipe, line, headNounOf(normalized), medium);
  // A divided line's written pot or brine share: the rest of the line is
  // eaten.
  final share = plus != null || divided != null
      ? null
      : medium == DiscardedMedium.cookingWater
      ? _potShareOf(recipe, line)
      : medium == DiscardedMedium.brine || medium == DiscardedMedium.brineSugar
      ? _brineShareOf(recipe, line, headNounOf(normalized))
      // v50 (F12; closer 1 V1-D2, V1-D3): only the discarded part.
      : medium == DiscardedMedium.removedAromatic ||
            medium == DiscardedMedium.strainedSolid
      ? _discardedShareOf(
          recipe,
          line,
          headNounOf(normalized)!,
          medium!,
        )?.share
      : null;
  // v50 (Q20): a printed part kept ([_partialUseOf]).
  final partial = medium == DiscardedMedium.partialUse
      ? _partialUseOf(recipe, line, headNounOf(normalized)!)
      : null;
  // A frying oil's part kept in the pan and eaten ([_keptFryingOil]).
  final keptOil = medium == DiscardedMedium.fryingOil
      ? _keptFryingOil(recipe, line)
      : null;
  // v57 (M59 F1): a frying oil's part the steps rinse off is not eaten.
  final rinsed =
      medium == DiscardedMedium.fryingOil &&
      plus != null &&
      _rinsedOff(recipe, plus, headNounOf(normalized)!);
  final eatenPart =
      (rinsed ? null : plus?.amount) ?? divided?.amount ?? keptOil;
  GramResolution? weigh(Amount amount) => resolveGrams(
    amounts: [amount],
    food: food,
    normalizedItem: normalized,
    kosherSalt: packsLikeKosherSalt(line.raw),
  );
  final eaten = eatenPart == null ? null : weigh(eatenPart);
  // v51 (M49 Q19, P1 D3a): a frying oil's kept part is eaten as well as
  // its part used outside the fry — "Toss the bread crumbs with 2
  // teaspoons of the oil … Reserve 1 tablespoon oil from the skillet and
  // discard the remainder" (0215): 2 teaspoons + 1 tablespoon.
  final alsoKept = keptOil == null || identical(eatenPart, keptOil)
      ? null
      : weigh(keptOil);
  final kept = eaten != null
      ? alsoKept == null
            ? eaten
            : GramResolution(
                grams: eaten.grams + alsoKept.grams,
                source: eaten.source,
                basis: eaten.basis,
              )
      : share != null && resolved != null
      ? GramResolution(
          grams: resolved.grams * (1 - share),
          source: GramSource.discarded,
          basis: resolved.basis,
        )
      : partial != null && resolved != null
      ? _partialKept(partial, resolved, food)
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
  // A dredge counts the share [coatingFraction] says, once the user sets
  // one; until then it is held like any medium below.
  if (medium == DiscardedMedium.coating && coating != null) {
    return (
      grams: resolved == null ? null : resolved.grams * coating,
      source: resolved?.source.name,
      hold: null,
    );
  }
  // A HELD medium's eaten part is its grams too, held with the line: a
  // confirm counts that part, never the water's (0300 Classic Macaroni and
  // Cheese: "1 tablespoon plus 1 teaspoon table salt", 1 tablespoon in the
  // drained pasta water, "remaining 1 teaspoon salt" in the roux — v10 held
  // all 24 g, a confirm would count them; v11, Opus). How much of the water's
  // part the food keeps nothing says, so the line stays held for a person.
  // A held medium with no eaten part written stores NO grams — never the
  // whole poured-away line (checkpoint 8: 35 of 41 held rows carried it,
  // 8,366 g, and a confirm counted it; the user's ruling, 2026-09-28): a
  // confirm writes 0 g poured away unless a person types the eaten grams
  // (applyMatchOverride).
  final resolution = kept != null
      ? GramResolution(
          grams: kept.grams,
          source: GramSource.discarded,
          basis: kept.basis,
        )
      : medium != null
      ? null
      // v51 (M49 Q19): an oil the steps pour down to a printed part.
      : resolved == null
      ? null
      : _keptInPan(recipe, line, food, normalized, resolved) ?? resolved;
  final rule = secondFoodRuleOf(
    line,
    citrus: citrus,
    eggs: eggs,
    recipe: recipe,
  );
  if (rule != null && rule.fdcId == food.fdcId) {
    final resolved = rule.gramsOn(food);
    return (grams: resolved?.grams, source: resolved?.source.name, hold: null);
  }
  final secondFood = namesSecondFood(line.raw);
  // A LINE hold too: no food decision says how much of a shell is eaten —
  // unless the grams already are what is eaten ([shellCounted], v39 Y2).
  final inShell = boughtInShell(line.raw) && !shellCounted(recipe, resolution);
  // An amount-less line counts as 0 g — never one bought in the shell: 0 g
  // would read resolved (`counted`) and leave the queue, hold or no hold.
  // No corpus line buys shellfish without an amount, so the guard is pinned
  // on a synthesized one (a stated exception, v11). v68 (M70, Q13 G2): nor
  // one its grams are WEIGHED for with no amount — the reserved giblets off
  // the host's bird ([hostWeighedGiblets], the only such reader).
  final zero =
      amountlessLinesZero &&
      line.amounts.isEmpty &&
      !inShell &&
      resolution?.source != GramSource.weight;
  if (decided) {
    return (
      grams: zero ? 0 : resolution?.grams,
      source: zero ? GramSource.unmeasured.name : resolution?.source.name,
      hold: medium != null
          ? medium.hold
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
      ? medium.hold
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

/// v39 (Y2, the owner's ruling 2026-10-05 on plan Q3 (b)): a line bought
/// in the shell ([boughtInShell]) whose grams need no shell yield, counted
/// rather than held `in_shell`: a per-item read ([GramSource.piece]) — the
/// FNDDS "1 mussel" and "1 oyster" 15 g are the meat, and a live lobster's
/// count reads the record's own "1 lobster" 200 g (flagged) — or shrimp
/// the recipe says are "eaten shell and all" (crispy salt-and-pepper
/// shrimp's prep note: the gross weight is what is eaten, flagged
/// approximate). v40 (E2): a clam line bought by weight whose grams carry
/// FDC's shell yield ([shellYieldLabel]: 174214's "lb (with shell)" 68 g).
/// v49 (M47 Q11): a shrimp or mussel line bought by weight whose grams carry
/// its AH-102 shell row ([ah102Shells]: shrimp 2333, mussels 1531). Oysters,
/// lobsters and the clams on other records stay held.
bool shellCounted(Recipe recipe, GramResolution? resolution) {
  final basis = resolution?.basis ?? '';
  return resolution?.source == GramSource.piece ||
      basis.contains('($shellYieldLabel)') ||
      ah102Shells.values.any((row) => basis.contains('(${row.flag})')) ||
      shellEatenIn(recipe);
}

/// Whether [recipe] says its shellfish are "eaten shell and all" (crispy
/// salt-and-pepper shrimp's prep note): the gross weight is what is eaten.
bool shellEatenIn(Recipe recipe) => RegExp(
  r'\beaten shells? and all\b',
).hasMatch((recipe.prepNotes ?? '').toLowerCase());

/// v39 (Y3, the owner's ruling 2026-10-05 on plan Q4 (b)): the meat-only
/// record a skin-discarded thigh or leg row moves to ([skinDiscarded]).
/// v40 (E1, the live step): a whole bird or pieces on 171447 moves to SR
/// 171052 ([meatOnlyBroiler]). v43 (Y3): a breast on 2727569 moves to
/// Foundation 2646170 (boneless skinless breast, cached). Each is weighed
/// there by its composition ([ah102Records], Y12/Y13: the part's AH-102
/// meat figure in one step; a whole bird its ready-to-cook yield).
const Map<int, int> skinlessRecords = {
  2727567: 2646171,
  172378: 173619,
  171447: meatOnlyBroiler,
  2727569: 2646170,
};

/// v49 (M47 Q11): the raw record a weight of shellfish bought in the shell
/// ([boughtInShell]) moves to from a cooked-meat one, weighed there at its
/// AH-102 shell row ([ah102Shells]): FNDDS 2706350 "Mussels" (cooked meat,
/// "1 mussel" 15 g) → SR 174216 "Mollusks, mussel, blue, raw" (cached,
/// second in the 'mussels' answer). Record-keyed, as [skinlessRecords]: a
/// count ("1 dozen mussels", paella) stays on the FNDDS meat portion.
const Map<int, int> shellRecords = {2706350: 174216};

/// [eaten]'s food and grams once the skin is off: an auto row on a
/// skin-on record of [skinlessRecords] — the engine's pick, or a person's
/// decision carried here from another line — whose line, weighed from a
/// printed weight, buys refuse in a recipe that discards the skin
/// ([skinDiscarded]) moves to the meat-only record (cached; else its detail
/// fetched once), weighed there at the meat share — or (v49) one on a
/// cooked-meat record of [shellRecords] whose weight is bought in the shell
/// moves to the raw record, weighed there at its AH-102 shell row — or
/// (v49, M47 Q14 (ii)) a can of beans kept whole ([keepsWholeCan]) on a
/// drained-and-rinsed record moves to its cached solids-and-liquids record
/// ([cannedBeanLiquids]), grams unchanged. Else [food] and [resolution] as
/// they are. Never a person's own row on this
/// line: it shows the food they chose.
Future<(FdcFood, GramResolution?)> skinOffFood(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  IngredientLine eaten,
  FdcFood food,
  GramResolution? resolution,
) async {
  final skinless = skinlessRecords[food.fdcId];
  final shelled = shellRecords[food.fdcId];
  final beanLiquid = cannedBeanLiquids[food.fdcId];
  final weighed = resolution?.source == GramSource.weight;
  // v49 (M47 Q11): or a weight bought in the shell, to its raw record.
  final target =
      skinless != null &&
          weighed &&
          buysRefuse(eaten.raw) &&
          skinDiscarded(recipe, eaten)
      ? skinless
      : shelled != null && weighed && boughtInShell(eaten.raw)
      ? shelled
      : beanLiquid != null &&
            weighed &&
            keepsWholeCan(
              eaten.raw,
              liquidEaten: canLiquidEatenIn(recipe, eaten),
            )
      ? beanLiquid
      : null;
  final meatOnly = target == null
      ? null
      : await _cachedFood(db, provider, target);
  return meatOnly == null
      ? (food, resolution)
      : (meatOnly, lineGrams(db, eaten, meatOnly, recipe: recipe));
}

/// The record a decision on [fdcId] names for [line]'s ingredient: on a
/// meat-only record of [skinlessRecords] in a recipe that discards the
/// skin of a cut bought with it, the SKIN-ON record bought — so a Confirm
/// of a moved row (or apply_to_all) never carries the skinless food, nor
/// its meat share, to a line whose skin is eaten; each line that discards
/// it moves again ([skinOffFood]). v49: on the raw record of
/// [shellRecords] for a line bought in the shell, the record bought (a
/// count — paella's dozen mussels — stays on it). Else [fdcId].
int? decisionRecordOf(Recipe recipe, IngredientLine line, int? fdcId) {
  for (final MapEntry(key: skinOn, value: meatOnly)
      in skinlessRecords.entries) {
    if (meatOnly == fdcId &&
        buysRefuse(line.raw) &&
        skinDiscarded(recipe, line)) {
      return skinOn;
    }
  }
  // v49: the record bought for a line the shell move put on the raw one,
  // or the can move on the solids-and-liquids one.
  for (final MapEntry(key: bought, value: raw) in shellRecords.entries) {
    if (raw == fdcId && boughtInShell(line.raw)) {
      return bought;
    }
  }
  for (final MapEntry(key: bought, value: liquid)
      in cannedBeanLiquids.entries) {
    if (liquid == fdcId &&
        keepsWholeCan(
          line.raw,
          liquidEaten: canLiquidEatenIn(recipe, line),
        )) {
      return bought;
    }
  }
  return fdcId;
}

/// v49 (M47 Q14 (i), the owner's 2026-10-07 standing authorization;
/// amends the 2026-10-06 canned-bean ruling): whether [recipe]'s steps add
/// [line]'s can WITH its liquid — a sentence naming the line's head noun
/// then "and|with their|its liquid" ("Add remaining 2 cups water, beans and
/// their liquid", best ground beef chili; "Stir in cannellini beans and
/// their liquid", soupe au pistou). Only a can line.
bool canLiquidEatenIn(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  if (head == null || !RegExp(r'\bcans?\b').hasMatch(line.raw.toLowerCase())) {
    return false;
  }
  final said = RegExp(
    '\\b${RegExp.escape(head)}(?:e?s)?\\s+(?:and|with)\\s+(?:their|its)\\s+liquid\\b',
  );
  return recipe.steps.any((step) => said.hasMatch(step.text.toLowerCase()));
}

/// v59 (M60 P7a, prep48 design_v2 §2; pre-Q18): whether [recipe]'s steps
/// pare [line]'s item raw — a sentence that BEGINS with the paring act
/// ("Peel, halve, and core pears."; "Using sharp vegetable peeler or chef's
/// knife, remove skin … from squash"), names the line's head noun, prints
/// no count of it smaller than the line's ("Peel, core, and cut 1 apple"
/// pares one of 7 apples; a line printing no count has none to compare, so
/// any printed count holds it back), and follows no sentence that cooks it
/// (the mashed potatoes are peeled after the simmer — AH-102 prints no
/// cooked-pare row). [produceYieldOf] reads it only when the line's tail
/// names no prep word. The noun is named as every detector names a head
/// ([_names]: a "-y" head by its "-ies" plural, never after "garlic ") and
/// counted in the same forms ([_formsOf]).
bool stepsPeelIn(Recipe recipe, IngredientLine line) {
  final head = headNounOf(normalizeItem(lineItemOf(line)));
  if (head == null) {
    return false;
  }
  final count = [
    for (final a in line.amounts)
      if (a.measure == Measure.count) parseQuantity(a.quantity),
  ].firstOrNull;
  final pared = _paredIn(recipe, head);
  return pared.always ||
      (count != null && pared.most != null && pared.most! >= count);
}

/// [stepsPeelIn]'s reading of [head], whatever the line's count: in step
/// order, up to the first sentence naming it that cooks, a paring sentence
/// naming it with no count of it pares every line (`always`); one printing
/// counts pares a line of at most the largest (`most`). Once per head
/// (RULE C, v59 verifier 2 D2: every sentence re-read per line, 400 lines
/// 17.7 s a compute at the caps): the head's sentences found by the step
/// index ([_naming], O(text) over all heads), each sentence's acts read
/// once ([_peelActs]).
({bool always, double? most}) _paredIn(Recipe recipe, String head) {
  final index = _stepIndexOf(recipe);
  // Key: head — the noun named and counted.
  return index.memo(('paredIn', head), () {
    final acts = _peelActs(index);
    final counted = RegExp(
      '(?<![\\w$vulgarFractionChars])($_baconN)\\s+(?:[a-z-]+\\s+){0,2}?'
      '\\b(?:${_formsOf(head).map(RegExp.escape).join('|')})\\b',
    );
    double? most;
    for (final at in _naming(recipe, head)) {
      final act = acts[at.$1][at.$2];
      if (act & 1 != 0) {
        final n = counted.firstMatch(index.sentence(at))?[1];
        if (n == null) {
          return (always: true, most: most);
        }
        final printed = parseQuantity(_nWords[n] ?? n);
        if (printed != null && (most == null || printed > most)) {
          most = printed;
        }
      }
      if (act & 2 != 0) {
        break;
      }
    }
    return (always: false, most: most);
  });
}

/// Each sentence's P7a acts by (step, sentence) — 1 it pares
/// ([_paresRaw]), 2 it cooks ([_cooksItem]) — read once per recipe.
List<List<int>> _peelActs(_StepIndex index) => index.memo(#peelActs, () {
  return [
    for (final step in index.sentences)
      [
        for (final s in step)
          (_paresRaw.hasMatch(s) ? 1 : 0) | (_cooksItem.hasMatch(s) ? 2 : 0),
      ],
  ];
});

/// P7a's paring act at the start of a sentence ([stepsPeelIn]).
final RegExp _paresRaw = RegExp(
  r'^\s*(?:using [^,]+,\s*)?(?:peel|pare|remove (?:the )?skin)\b',
);

/// P7a's guard: a sentence that cooks (with the item named) ([stepsPeelIn]).
final RegExp _cooksItem = RegExp(
  r'\b(?:boil|simmer|steam|roast|bake|baking|microwav|cook)\w*',
);

/// Whether [recipe] discards the skin of [line]'s cut: the line says "skin
/// removed" or "skinned", or a step sentence removes or discards the skin
/// ("remove and discard the browned chicken skin", "discard skin", "peel
/// skin off") and no sentence of the recipe naming the skin reserves it,
/// sets it aside, lays it back, stretches it, takes it "if desired" or
/// from the "tapered" pieces only (plan Q4: the skin is eaten, or only
/// partly gone). v40: a sentence that takes the skin "from the <part>" —
/// a breast, thigh, leg, wing or drumstick — counts only for a line whose
/// item names that part: Classic Chicken Noodle Soup (0002) discards "the
/// skin and bones from the breast pieces" of its whole bird, the rest of
/// the bird strained out with the stock (prep39/skin_render.md: outside
/// the narrow signal); Chicken Provençal's "from the chicken thighs" and
/// Barbecued Pulled Chicken's "from chicken legs" still trip their lines.
/// v43 (Y3): "reserved (cooked) chicken" names the meat kept, not the
/// skin, so it never vetoes: Hearty Chicken Noodle Soup (0002) "remove the
/// skin and bones from the reserved cooked chicken and discard" trips.
bool skinDiscarded(Recipe recipe, IngredientLine line) {
  if (RegExp(
    r'\bskin removed\b|\bskinned\b',
  ).hasMatch(line.raw.toLowerCase())) {
    return true;
  }
  final item = (line.item ?? line.raw).toLowerCase();
  // The sentences naming the skin, read once per recipe (v60 closer 2: once
  // per LINE, 399 frying oils' grams read every sentence of the caps, 1.4 s).
  final skin = _stepIndexOf(recipe).memo(
    #skinSentences,
    () => [
      for (final sentence in _stepIndexOf(recipe).allSentences)
        if (RegExp(r'\bskin\b').hasMatch(sentence)) sentence,
    ],
  );
  return !skin.any(_skinKept.hasMatch) &&
      skin.any((sentence) => _skinOffFor(item, sentence));
}

bool _skinOffFor(String item, String sentence) {
  final part = _skinPart.firstMatch(sentence)?.group(1);
  return _skinOff.hasMatch(sentence) && (part == null || item.contains(part));
}

/// v40: the part a tripping skin-off sentence of [recipe] keeps its skin on
/// — "peel skin off chicken, leaving skin on wings" (Grilled Lemon Chicken
/// with Rosemary, 0637) → "wings" — or null (the whole skin removed, or no
/// trip). The grams path flags the meat-only whole bird with it
/// (prep39/plan.md: "keeps its wing skin, which the flag names").
String? skinKeptPart(Recipe recipe, IngredientLine line) {
  if (!skinDiscarded(recipe, line)) return null;
  final item = (line.item ?? line.raw).toLowerCase();
  for (final sentence in _stepIndexOf(recipe).allSentences) {
    if (!_skinOffFor(item, sentence)) continue;
    final part = _skinLeftOn.firstMatch(sentence)?.group(1);
    if (part != null) return part;
  }
  return null;
}

final RegExp _skinLeftOn = RegExp(
  r'\blea(?:ve|ving)\s+(?:the\s+)?skin\s+on\s+(?:the\s+)?([a-z]+)',
);

final RegExp _skinPart = RegExp(
  r'\bskin\b.*?\bfrom\s+(?:the\s+)?(?:[a-z-]+\s+){0,2}?'
  '(breast|thigh|leg|wing|drumstick)',
);

final RegExp _skinOff = RegExp(
  r'\b(?:remove|discard|discarding)\s+(?:and\s+discard\s+)?(?:the\s+)?'
  r'(?:browned\s+)?(?:chicken\s+)?skin\b|\bpeel\s+skin\s+off\b',
);

final RegExp _skinKept = RegExp(
  r'\breserve(?!d\s+(?:cooked\s+)?chicken\b)|\bset aside\b|\blay\b.{0,30}\bback\b|\bstretch|'
  r'\bif desired\b|\btapered\b',
);

/// The note a [isSubRecipeReference] line is stored under.
final String subRecipeNote = engineRuleNotes[0];

/// Whether the line [raw] names a sub-recipe the recipe makes apart — "1
/// recipe Simple Tomato Sauce (recipe follows)" (Lighter Chicken Parmesan,
/// 0416), "10 cups Vanilla Frosting (recipe follows)" (Rainbow Cake, 1201),
/// "1 recipe Buttery Croutons (this page)": such a line is never counted on
/// a food (the user's ruling, 2026-09-27; v12 counted 8 of them, the
/// frosting at 2,082 g of a ready-to-eat one). The mark is "recipe(s)
/// follow(s)" in the line's first alternative, or "this page" before its
/// first comma — "shrimp, peeled and deveined (see this page)" points at a
/// technique, not a recipe. A line that opens "<n> recipe" is one whatever
/// it says after (v14: "1 recipe double-crust pie dough", Perfect Poached
/// Eggs in Salade Lyonnaise, 0434 — every such corpus line's amount is the
/// unit `recipe`). A food offered first stays that food: "½ teaspoon table
/// salt or 1 recipe topping (recipes follow)" is the salt. (Requiring the
/// "this page" in a parenthesis changed no line of the library — every one
/// is: removed, v14.)
bool isSubRecipeReference(String raw) {
  final text = raw.toLowerCase();
  if (RegExp(
    '^\\s*[\\d$vulgarFractionChars/.-][\\d$vulgarFractionChars/ .-]*recipes?\\b',
  ).hasMatch(text)) {
    return true;
  }
  final follows = RegExp(r'\brecipes? follows?\b');
  final first = text.split(RegExp(r'(?<!\s)\s+or\s+')).first;
  return follows.hasMatch(first) ||
      RegExp(r'\bthis page\b').hasMatch(first.split(',').first);
}

/// Whether [line] of [recipe] reads a sub-recipe (v44, A9 a, P1 §2.7): a
/// marked reference ([isSubRecipeReference]) or an UNMARKED line naming one
/// of the recipe's own sections ([namesOwnSection]) — the recipe-aware gate
/// the sub-recipe rule, the stale hash, the sweep's parent test, the nested
/// checks and the basis read.
bool isReferenceIn(Recipe recipe, IngredientLine line) =>
    isSubRecipeReference(line.raw) || namesOwnSection(recipe, line);

/// Whether the unmarked [line] of [recipe] names one of its OWN sections
/// that lists ingredient lines (v44, A9 a): its reference item equals the
/// section's title as the resolver compares them ("2 tablespoons harissa"
/// on red-lentil-kibbeh's "Harissa", "⅓ cup Black Olive Tapenade", "1 Vegan
/// Cilantro Sauce") — never a bare count other than 1 ("12 (6-inch) corn
/// tortillas, warmed" stays its food, as "8 Home-Fried Taco Shells" does)
/// and never a line with no amount. Equality only: the looser
/// own-section forms reach variations of the line's own food ("2 cups
/// couscous" → "Couscous with Dates and Pistachios").
bool namesOwnSection(Recipe recipe, IngredientLine line) {
  if (recipe.subsections.isEmpty ||
      line.amounts.isEmpty ||
      isSubRecipeReference(line.raw)) {
    return false;
  }
  if (line.amounts.every((a) => a.unit == null) &&
      (line.amounts.length != 1 ||
          line.amounts.single.quantity.trim() != '1')) {
    return false;
  }
  final item = referenceItemOf(line);
  return recipe.subsections.any(
    (sub) =>
        _refNorm(sub.title ?? '') == item &&
        (sub.ingredients ?? const <IngredientGroup>[]).any(
          (group) => group.items.isNotEmpty,
        ),
  );
}

/// The subsection of [recipe] a sub-recipe [line] references: the one whose
/// title opens the line's item ("Easy-Peel Hard-Cooked Eggs (recipe
/// follows)", "Crispy Onions"). Null for none.
Subsection? _referencedSubsection(Recipe recipe, IngredientLine line) {
  final item = (line.item ?? '').toLowerCase();
  for (final sub in recipe.subsections) {
    final title = (sub.title ?? '').toLowerCase();
    if (title.isNotEmpty && item.startsWith(title)) {
      return sub;
    }
  }
  return null;
}

/// The amounts of the one ingredient line of the single-food subsection
/// "1 recipe X" references — counted only when they are a bare count, as
/// [subRecipeCountsItsFood] then reads them on the line — the user's ruling Q1,
/// 2026-09-28: "1 recipe Easy-Peel Hard-Cooked Eggs (recipe follows)" (Curry
/// Deviled Eggs, 0731) is the subsection's "6 large eggs", counted on the
/// line's own pick (300 g of hard-boiled egg; v13 zeroed it). The only such
/// subsection of the library; every other "1 recipe X" makes several foods
/// and stays 0 g. The line keeps its raw text (and so its key); only its
/// amounts are the subsection's ([nutritionLines]).
List<Amount>? _singleFoodYield(Recipe recipe, IngredientLine line) {
  final amounts = line.amounts;
  if (amounts.length != 1 ||
      amounts.single.unit != 'recipe' ||
      amounts.single.quantity.trim() != '1') {
    return null;
  }
  final items = [
    for (final group
        in _referencedSubsection(recipe, line)?.ingredients ??
            const <IngredientGroup>[])
      ...group.items,
  ];
  return items.length == 1 ? items.single.amounts : null;
}

/// The eaten "plus" part of a sub-recipe [line] of [recipe], as the line
/// the engine matches and weighs: "1 recipe Crispy Onions, plus 3
/// tablespoons reserved oil (recipe follows)" (Mujaddara, 0711) — the
/// reserved oil is the referenced subsection's own line of that food ("1½
/// cups vegetable oil"), so the part is 3 tablespoons of vegetable oil
/// (checkpoint 8: v13 dropped it with the onions). The only such line of the
/// library. Null otherwise.
IngredientLine? subRecipePlusLine(Recipe recipe, IngredientLine line) {
  final plus = plusPartOf(line.raw);
  if (plus == null || !isSubRecipeReference(line.raw)) {
    return null;
  }
  final text = plus.text.replaceAll(RegExp(r'(?<!\s)\s*\([^)]*\)'), '');
  final part = parseIngredientLine(text).item;
  final head = part == null ? null : headNounOf(normalizeItem(part));
  if (head == null) {
    return null;
  }
  for (final group
      in _referencedSubsection(recipe, line)?.ingredients ??
          const <IngredientGroup>[]) {
    for (final own in group.items) {
      final item = normalizeItem(lineItemOf(own));
      if (headNounOf(item) == head) {
        return IngredientLine(
          raw: text,
          item: item,
          amounts: [plus.amount],
        );
      }
    }
  }
  return null;
}

/// The line every path matches, weighs and queries for [line] of [recipe]:
/// a sub-recipe reference's eaten "plus" part ([subRecipePlusLine]) when it
/// has one, else the food alternative after its " or " when that carries an
/// amount ([foodAlternativeOf], v41 A10 a: a person's food pick on such a
/// line is weighed there), else [line] itself — the compute, a person's
/// confirm, pick and
/// un-skip, the matches GET's candidates, amount and portions, and the
/// stale hash and an apply-to-all alike (Run 047: a re-pick on Mujaddara's
/// plus line, 0711, weighed "1 recipe Crispy Onions" as one onion — 110 g
/// of oil for 42 — and an un-skip held it `second_food`).
IngredientLine weighedLine(Recipe recipe, IngredientLine line) =>
    subRecipePlusLine(recipe, line) ?? foodAlternativeOf(line) ?? line;

/// The sub-recipe rule, the one gate every writer calls: the 0 g row
/// [line] (position [position] of [recipe]) is stored as, or null when the
/// line is matched and counted like any other. Before a food ([onFood]
/// false): a reference with no eaten "plus" part that is no bare count of
/// its food. On a food: any reference its food gives no [grams] — unless
/// those grams say nothing about the food ([sized] false: a pick below the
/// gate whose detail was never fetched stays that held pick, in `check`).
/// Written by the compute's every path, a person's confirm, pick and
/// un-skip, and an apply-to-all (Run 047: an apply-to-all landed a marked
/// count as a no-grams row the compute zeroes).
IngredientMatchRow? subRecipeRowFor(
  Recipe recipe,
  int position,
  IngredientLine line, {
  bool onFood = false,
  double? grams,
  bool sized = true,
}) {
  if (!isReferenceIn(recipe, line)) {
    return null;
  }
  final zero = onFood
      ? grams == null && sized
      : subRecipePlusLine(recipe, line) == null &&
            // An A9 line's bare 1 is one recipe, never a count of its food.
            (!subRecipeCountsItsFood(line) || !isSubRecipeReference(line.raw));
  return zero ? _subRecipeRow(recipe, position, line, lineKeyOf(line)) : null;
}

/// Whether the [isSubRecipeReference] line [line] is a number of a food the
/// recipe prepares by the referenced technique rather than a batch of
/// something it makes: every amount a bare count, with no unit. "3
/// hard-cooked eggs (recipe follows)" (Wilted Spinach Salad, 0040), "4
/// Easy-Peel Hard-Cooked Eggs (this page)" (Gado-Gado, 1192) — v13 zeroed
/// 150 to 200 g of eggs each — not "1 recipe Easy-Peel Hard-Cooked Eggs"
/// (the unit `recipe`), "4 cups Cream Cheese Frosting", "4 ounces Simple
/// Syrup". Such a line is matched like any other (a pick below the gate is
/// held for review like any other) — "8 Home-Fried Taco Shells (recipe
/// follows)" (Ground Beef Tacos, 0478) is 8 × the "shell" of "Taco shells,
/// baked" — and one whose food gives no grams stays the 0 g sub-recipe
/// ([subRecipeRowFor]).
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
// ---------------------------------------------------------------------------
// v41: the composite row (design_v3 §2.2; the owner's 2026-10-05 rulings).
// ---------------------------------------------------------------------------

/// What a sub-recipe reference line resolves to ([resolveReference]).
enum ReferenceKind {
  /// Counted from a library recipe ([ReferenceResolution.childId]).
  routed,

  /// The library recipe is itself made from a recipe (depth 1): held
  /// `nested_recipe`.
  nested,

  /// No library recipe answers it: held `choose_recipe`.
  held,

  /// A marinade (the item's words): held `discarded_recipe`, poured away.
  marinade,

  /// A section that lists no ingredient lines (v44: every section WITH
  /// lines routes as a child; [ReferenceResolution.noIngredients]): the 0 g
  /// rule row.
  section,

  /// The parent is made FOR the child (D7, "… for Pan-Seared Steaks"):
  /// served with it, not made from it — the 0 g rule row.
  servedWith,

  /// The line has no amount: the 0 g rule row.
  noAmount,

  /// A library recipe answers it but no share reads from its yield: the 0 g
  /// rule row.
  noShare,

  /// A SECTION's line naming its own host (v47, F7 — Run 061 S4: "1 recipe
  /// Yeasted Doughnuts (this page)" in its Boston Cream Doughnuts): the
  /// variation is made on the host, never FROM it — the 0 g rule row with
  /// no child, so a host line routed to the section (held `nested_recipe`)
  /// and the section's line never stamp each other in a cycle.
  self,
}

/// A library recipe as the resolver's title index lists it.
typedef LibraryTitle = ({String id, String slug, String title});

/// [resolveReference]'s answer.
class ReferenceResolution {
  /// Builds one.
  const ReferenceResolution(
    this.kind, {
    this.childId,
    this.share,
    this.named = 0,
    this.missing = false,
    this.similar = const [],
    this.section,
    this.noIngredients = false,
    this.variation,
  });

  /// What the line resolves to.
  final ReferenceKind kind;

  /// The child recipe (routed, nested, no share).
  final String? childId;

  /// The share of the child the line counts (routed).
  final double? share;

  /// How many library titles the parent's note names (a routed default is
  /// flagged when it names two or more).
  final int named;

  /// A held line's reason: no candidate at all (`missing`) rather than
  /// several (`generic`) — the GET's copy variant.
  final bool missing;

  /// Library titles holding every word of the item, listed for a person
  /// (never routed; F12): fewest extra words first, at most 5.
  final List<LibraryTitle> similar;

  /// The section a section reference names (its host's id and title).
  final ({String host, String title})? section;

  /// A [ReferenceKind.section] answer whose section lists no ingredient
  /// lines (v44, S13 `no_ingredients`): a prose variation of its host,
  /// counted nowhere — the 0 g rule row.
  final bool noIngredients;

  /// v52 (M51 Q9, rule PV): the prose section (no ingredient lines) the
  /// line names when it is counted as its BASE ([childId]) instead — its
  /// host and title. The parent's hash folds it ([proseSectionsReadBy]),
  /// the row carries [pvFlagOf]'s flag. Null on every other answer.
  final ({String host, String title})? variation;
}

/// How many times a [ResolverMemo] read the library's title or section
/// index (the cost pin, F14: at most two per request or compute).
@visibleForTesting
int resolverIndexReads = 0;

/// How many times a [ResolverMemo] read a child recipe's `recipe_nutrition`
/// row (the cost pin, F14: one per composite row per compute).
@visibleForTesting
int childNutritionReads = 0;

/// The library's titles and sections, read ONCE per request or compute
/// (F14, the [ReachMemo] precedent): two statements, never a decode of
/// every document.
class ResolverMemo {
  /// A memo over [db].
  ResolverMemo(this.db);

  /// The database the indexes are read from.
  final SaltDatabase db;

  /// Library titles by normalised title, in id order.
  late final Map<String, List<LibraryTitle>> titles = () {
    resolverIndexReads++;
    final out = <String, List<LibraryTitle>>{};
    for (final entry in db.recipeTitleIndex()) {
      (out[_refNorm(entry.title)] ??= []).add(entry);
    }
    return out;
  }();

  /// Every recipe's subsection titles, by normalised title.
  late final Map<String, List<({String host, String title})>> sections = () {
    resolverIndexReads++;
    final out = <String, List<({String host, String title})>>{};
    for (final entry in db.subsectionTitleIndex()) {
      (out[_refNorm(entry.title)] ??= []).add(entry);
    }
    return out;
  }();

  final Map<String, RecipeNutritionRow?> _children = {};

  final Map<String, Recipe?> _hosts = {};

  /// The section keys holding a stamp: the CHILD sections a fix sheet may
  /// list from another host (v44, S14 a; N4: the child set as stored — "a
  /// section key with a `recipe_nutrition` row", one statement per memo, so
  /// a child not swept yet is not listed until its sweep).
  late final Set<String> computedSections = db
      .sectionKeysWithNutrition()
      .toSet();

  /// [_m52Plan] on each recipe's rows as stored (by position, beside it),
  /// run ONCE per memo (v60 closer 2, verify2 D1: the matches GET re-ran it
  /// for every row, O(oils²) at the editor caps; closer 3, verify3 D1: and
  /// for every confirmed coat or oil row, [_m52OnConfirm]). Only a request
  /// that writes no row hands its memo to [gramBasisFor] and [derivedFor]'s
  /// `m52Memo` (the matches GET).
  final Map<
    Recipe,
    ({Map<int, IngredientMatchRow> rows, Map<int, _M52Row> plan, String key})
  >
  _m52Plans = Map.identity();

  /// The compute's [_m52Plan] per recipe (v61 closer 1, verify1 D1), one for
  /// its coat block's confirms and one for its frying oils' (`fryer`): the
  /// [_m52Key] of the row list it was read on and the FDC cache writes then
  /// ([SaltDatabase.fdcCacheWrites]) — a confirm answers from it while both
  /// still hold ([_m52OnConfirm]'s `pass`). A memo whose life spans row
  /// writes: each lookup re-reads the rows.
  final Map<
    Recipe,
    Map<bool, ({String key, int writes, Map<int, _M52Row> plan})>
  >
  _m52Pass = Map.identity();

  /// Host recipe [id] as stored, decoded at most ONCE per memo (R5).
  Recipe? hostRecipe(String id) =>
      _hosts.putIfAbsent(id, () => db.recipeByIdOrSlug(id)?.recipe);

  /// The child recipe [id]'s stored totals, read ONCE per request or
  /// compute (F14): the row the compute writes and the totals it counts
  /// read the same child (no write to it can land between them in one
  /// compute: a recipe is never its own child).
  RecipeNutritionRow? childNutrition(String id) =>
      _children.putIfAbsent(id, () {
        childNutritionReads++;
        return db.nutritionFor(id);
      });
}

/// The recipe nutrition reads under [key] (matcher v44, migration 019): a
/// recipe id (or slug) as stored, or a section key ([sectionKeyOf]) — the
/// host's subsection of exactly that title as a recipe of its own
/// ([sectionRecipeOf]) with the host's source; null when the host or the
/// title is gone. EVERY nutrition path loads a row's, a child's or a job's
/// id through here, never [SaltDatabase.recipeByIdOrSlug] (which serves
/// favorites, images and notes, and must refuse a key).
({Recipe recipe, String sourceSlug})? nutritionRecipeOf(
  SaltDatabase db,
  String key,
) {
  final host = hostOf(key);
  if (host == key) {
    return db.recipeByIdOrSlug(key);
  }
  final found = db.recipeByIdOrSlug(host);
  if (found == null || found.recipe.id != host) {
    return null;
  }
  final section = sectionOf(found.recipe, key);
  return section == null
      ? null
      : (recipe: section, sourceSlug: found.sourceSlug);
}

/// [nutritionRecipeOf] over a document already read: [doc] is the stored
/// JSON of [key]'s host ([SaltDatabase.recipesWithNutrition] pairs a
/// section's stamp with its host's doc).
Recipe? nutritionRecipeFromDoc(String key, String doc) {
  final recipe = RecipeMapper.fromMap(jsonDecode(doc) as Map<String, dynamic>);
  return hostOf(key) == key ? recipe : sectionOf(recipe, key);
}

/// The section of [host] the key [key] names (its exact title), as a
/// recipe ([sectionRecipeOf]); null for none.
Recipe? sectionOf(Recipe host, String key) {
  final title = key.substring(hostOf(key).length + 1);
  for (final sub in host.subsections) {
    if (sub.title == title) {
      return sectionRecipeOf(host, sub);
    }
  }
  return null;
}

/// [host]'s titled subsection [sub] as a recipe of its own (v44, P1 §2.2):
/// keyed [sectionKeyOf], its own title, notes, yield, STEPS (a section
/// stores its own method or none — R20) and lines, no subsections.
/// Memoised per host instance and title, so its lines stay [identical]
/// ([nutritionLines]).
Recipe sectionRecipeOf(Recipe host, Subsection sub) =>
    (_sections[host] ??= {})[sub.title!] ??= host.copyWith(
      id: sectionKeyOf(host.id, sub.title!),
      title: sub.title,
      prepNotes: sub.prepNotes,
      servings: sub.servings,
      steps: sub.steps ?? const [],
      ingredients: sub.ingredients ?? const [],
      subsections: const [],
    );

final Expando<Map<String, Recipe>> _sections = Expando();

/// The section keys [recipe] makes children — the PER-RECIPE child set the
/// per-recipe job computes first: its lines' ([routedSectionKeysOf]) and,
/// v47 (F1), every section a PERSON's row of it picks
/// ([pickedSectionKeysOf]). The library-wide set (the bulk sweep's order,
/// stale scope and garbage collection) is the same two halves over the
/// whole library (bulk_job's `bulkScope`).
Set<String> sectionChildKeysOf(
  SaltDatabase db,
  Recipe recipe,
  ResolverMemo memo,
) => {
  ...pickedSectionKeysOf(db, recipeId: recipe.id),
  ...routedSectionKeysOf(db, recipe, memo),
};

/// The section keys [recipe]'s MAIN lines make children (v44, design_v2
/// S2 (a), P1 §2.1): a reference line the sub-recipe rule zeroes (never one
/// a food rule counts — [subRecipeRowFor] null: curry-deviled-eggs|0,
/// gado-gado|17, ground-beef-tacos|15, mujaddara|7) whose resolution names
/// a section with ingredient lines. Read through [memo] (one per scope or
/// compute). The pick-own candidates (rule PO) and the A9 lines join it
/// here.
Set<String> routedSectionKeysOf(
  SaltDatabase db,
  Recipe recipe,
  ResolverMemo memo,
) {
  final keys = <String>{};
  for (final (i, line) in nutritionLines(recipe).indexed) {
    if (subRecipeRowFor(recipe, i, line) == null) {
      continue;
    }
    // Rule PO's candidates are children too (a person may pick one).
    for (final title
        in pickOwnSections(db, recipe, line, memo) ?? const <String>[]) {
      keys.add(sectionKeyOf(recipe.id, title));
    }
    final found = resolveReference(db, recipe, line, memo);
    final key = switch (found.section) {
      (:final host, :final title) => sectionKeyOf(host, title),
      null => found.childId,
    };
    if (key == null || hostOf(key) == key) {
      continue;
    }
    final host = key.startsWith('${recipe.id}#')
        ? recipe
        : memo.hostRecipe(hostOf(key));
    final section = host == null ? null : sectionOf(host, key);
    if (section != null && nutritionLines(section).isNotEmpty) {
      keys.add(key);
    }
  }
  return keys;
}

/// v47 (F1, Run 061 S1/S2, Run 062 O1/O5): the section keys a person's
/// decided row picks ([SaltDatabase.decidedSectionPicks] — of [recipeId]'s
/// rows, else the library's) whose host still carries the title
/// ([nutritionRecipeOf]; S15's dropped keys stay dropped). A pick keeps its
/// section a CHILD whether or not a main line routes there: the bulk GC
/// never collects its stamp, the sweeps order and select it, the
/// per-recipe job computes it first — else the parent read a gone stamp,
/// underived for good, and its re-pick was refused.
Set<String> pickedSectionKeysOf(SaltDatabase db, {String? recipeId}) => {
  for (final key in db.decidedSectionPicks(recipeId: recipeId))
    if (nutritionRecipeOf(db, key) != null) key,
};

/// A title or item as the resolver compares them: accents folded,
/// punctuation a space, lowercase ("double-crust" is two words).
String _refNorm(String text) => foldAccents(
  text.toLowerCase(),
).replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

Set<String> _refWords(String normalized) =>
    normalized.isEmpty ? const {} : normalized.split(' ').toSet();

/// The item a reference line names: its parsed item with every
/// parenthetical (an unclosed one too), the tail after its first comma, the
/// reference marks and a leading "1 recipe" removed, normalised.
String referenceItemOf(IngredientLine line) => _refNorm(_referenceText(line));

/// The reference a line names as the line writes it (v41, the matches GET's
/// `child.name`): [referenceItemOf]'s cuts, the case and punctuation kept,
/// the spaces collapsed ("Rustic Tart Dough", "double-crust pie dough").
String referenceNameOf(IngredientLine line) =>
    _referenceText(line).replaceAll(RegExp(r'\s+'), ' ').trim();

String _referenceText(IngredientLine line) => (line.item ?? line.raw)
    .replaceAll(RegExp(r'\([^()]*\)?'), '')
    .replaceAll(RegExp(r'\(.*$'), '')
    .split(',')
    .first
    .replaceFirst(RegExp(r'^\s*\d+\s+recipes?\s+'), '')
    .replaceAll(
      RegExp(
        r'\bsee this page\b|\bthis page\b|\brecipes? follows?\b',
        caseSensitive: false,
      ),
      '',
    );

/// "Thai Chili Jam (Nam Prik Pao)" ← "Nam Prik Pao (Thai Chili Jam)".
final RegExp _trailingParen = RegExp(r'^(.*?)\s*\((.*)\)\s*$');

/// Whether this recipe's section [title] is the one the reference [item]
/// names: equal, the item starts with it (the shipped rule), it starts with
/// the item and a space ("Fried Shallots and Fried Shallot Oil"), or its
/// trailing parenthetical is the item (reversed: "Nam Prik Pao (Thai Chili
/// Jam)").
bool _ownSectionNames(String title, String item) {
  final normalized = _refNorm(title);
  if (normalized.isEmpty) {
    return false;
  }
  final reversed = _trailingParen.firstMatch(title);
  return normalized == item ||
      item.startsWith(normalized) ||
      normalized.startsWith('$item ') ||
      (reversed != null && _refNorm(reversed[2]!) == item);
}

/// Resolves the sub-recipe reference [line] of [recipe] (design_v3 §2.2
/// item 2, the ruled order; first hit wins): no amount → a marinade → ONE
/// own section (its title equals the item, the item starts with it, its
/// parenthetical equals the item, or it starts with the item and a space;
/// D11: under "recipes follow" too; v47 F6: of several, the ONE whose
/// title equals the item) → the first library title the parent's
/// note names ("(this page)" in the note; titles of two or more words
/// holding every word of the item, by position, the longest of a span) →
/// the library title equal to the item (unless the parent is made FOR it,
/// D7) → another recipe's section → held. Self is never a candidate; a
/// section's line naming its own host is `self` (v47, F7). A
/// child made from a recipe itself is `nested` (depth 1); one whose yield
/// reads no share is `noShare`.
///
/// v52 (M51, prep47 design_v2 Q8, Q9, Q22; the owner's 2026-10-07 standing
/// authorization; re-rules prep41 A3 (a) and CP3 for these lines). A line
/// with NO amount (and only such a line — critic F7: the ten marked
/// references WITH an amount, guay-tiew-tom-yum-goong|15's "(optional)"
/// jam among them, keep the ruled practice and stay counted): rule SW, a
/// served-with marker ([servedWithMarked]) → `servedWith` (the 0 g rule
/// row, counted accounted by [recomputeTotals]); else rule WB, the order
/// above reaching a child with lines that is not nested → `routed` at
/// share 1.0, one whole batch ([wbFlag]); anything else stays `noAmount`.
/// Rule PV, every line: an answer naming a section with no ingredient
/// lines routes to its base ([_proseBase]) when one shares a title word.
ReferenceResolution resolveReference(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
) {
  final amountless = line.amounts.isEmpty;
  if (amountless && servedWithMarked(recipe, line)) {
    return const ReferenceResolution(ReferenceKind.servedWith);
  }
  var found = _resolveInOrder(db, recipe, line, memo);
  if (found case ReferenceResolution(
    noIngredients: true,
    section: final prose?,
  )) {
    found = _proseBase(recipe, line, memo, prose) ?? found;
  }
  // D7's shipped title rule answers `servedWith` in the order itself.
  return amountless &&
          found.kind != ReferenceKind.servedWith &&
          (found.kind != ReferenceKind.routed || found.variation != null)
      ? const ReferenceResolution(ReferenceKind.noAmount)
      : found;
}

/// Rule SW's markers (v52, M51 Q8; P5 §3) on an amount-less reference
/// [line] of [recipe]: "optional", "for serving", an alternative after
/// " or " (the split [isSubRecipeReference] reads) or an ingredient group
/// headed CONDIMENTS. The fifth, D7's title rule (Q8b: the parent "… for
/// {item}"), is the shipped order's own `servedWith` answer, kept for such
/// a line by [resolveReference]. Read only for a line with no amount.
bool servedWithMarked(Recipe recipe, IngredientLine line) {
  final text = line.raw.toLowerCase();
  return RegExp(r'\boptional\b').hasMatch(text) ||
      text.contains('for serving') ||
      RegExp(r'(?<!\s)\s+or\s+').hasMatch(text) ||
      recipe.ingredients.any(
        (group) =>
            group.group?.trim().toUpperCase() == 'CONDIMENTS' &&
            group.items.any((own) => own.raw == line.raw),
      );
}

/// Rule PV (v52, M51 Q9; P5 §3): the BASE a reference naming the prose
/// section [prose] (no ingredient lines) counts — of the section's host
/// (when it lists lines and is neither [recipe] nor its host) and the
/// host's sections that list lines (never the prose one, never [recipe]),
/// the one whose title shares the most words with the prose section's
/// ([_refNorm]); the host on a tie (fresh-plum-ginger-pie|0 → 0976's own
/// "Foolproof All-Butter Dough for Double-Crust Pie", 6 words;
/// lemon-meringue-pie|0 → 0972's "Basic Single-Crust Pie Dough", 4 words
/// against the host's 3), else the first such section. Null when no
/// candidate shares a word, or the base reads no `routed` share (the
/// `no_ingredients` row stays).
ReferenceResolution? _proseBase(
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
  ({String host, String title}) prose,
) {
  final host = prose.host == recipe.id ? recipe : memo.hostRecipe(prose.host);
  if (host == null) {
    return null;
  }
  final words = _refWords(_refNorm(prose.title));
  int shared(String title) =>
      _refWords(_refNorm(title)).intersection(words).length;
  final hostScore =
      host.id != recipe.id &&
          host.id != hostOf(recipe.id) &&
          nutritionLines(host).isNotEmpty
      ? shared(host.title)
      : 0;
  Subsection? best;
  var bestScore = 0;
  for (final sub in host.subsections) {
    final title = sub.title;
    if (title == null ||
        title == prose.title ||
        sectionKeyOf(host.id, title) == recipe.id ||
        nutritionLines(sectionRecipeOf(host, sub)).isEmpty) {
      continue;
    }
    if (shared(title) > bestScore) {
      best = sub;
      bestScore = shared(title);
    }
  }
  if (hostScore == 0 && bestScore == 0) {
    return null;
  }
  final tail = hostScore >= bestScore
      ? _childTail(line, host)
      : _childTail(
          line,
          sectionRecipeOf(host, best!),
          section: best.title,
          host: host.id,
        );
  return tail.kind != ReferenceKind.routed
      ? null
      : ReferenceResolution(
          ReferenceKind.routed,
          childId: tail.childId,
          share: tail.share,
          section: tail.section,
          variation: prose,
        );
}

/// [resolveReference]'s shipped order (v41–v47), every line.
ReferenceResolution _resolveInOrder(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
) {
  final item = referenceItemOf(line);
  final itemWords = _refWords(item);
  if (itemWords.contains('marinade')) {
    return const ReferenceResolution(ReferenceKind.marinade);
  }
  final own = [
    for (final sub in recipe.subsections)
      if (sub.title case final title? when _ownSectionNames(title, item)) title,
  ];
  // v47 (F6, Run 061 S3): the own section whose title IS the item wins over
  // the looser forms' siblings ("2 tablespoons harissa" is "Harissa", never
  // held beside a "Harissa Yogurt").
  final exactOwn = [
    for (final title in own)
      if (_refNorm(title) == item) title,
  ];
  if (own.length == 1 || exactOwn.length == 1) {
    final title = own.length == 1 ? own.single : exactOwn.single;
    final key = sectionKeyOf(recipe.id, title);
    return _childTail(line, sectionOf(recipe, key)!, section: title);
  }
  final titles = memo.titles;
  final named = noteNamedTitles(recipe, item, memo);
  final exact = [
    for (final e in titles[item] ?? const <LibraryTitle>[])
      if (e.id != recipe.id) e,
  ];
  final LibraryTitle child;
  if (named.isNotEmpty) {
    child = named.first;
  } else if (exact.isNotEmpty) {
    if (' ${_refNorm(recipe.title)}'.contains(' for $item')) {
      return const ReferenceResolution(ReferenceKind.servedWith);
    }
    child = exact.first;
  } else {
    final plural = RegExp(r'\brecipes follow\b').hasMatch(
      line.raw.toLowerCase(),
    );
    final other = [
      for (final s
          in memo.sections[item] ?? const <({String host, String title})>[])
        if (s.host != recipe.id) s,
    ];
    // v44 (N8): another recipe's section routes only when exactly ONE host
    // carries the title under the resolver's normalised key — "Spice Rub"
    // is two recipes' own section, never a guess between them (held, listed).
    if (other.length == 1 && !plural) {
      final (:host, :title) = other.single;
      final section = switch (memo.hostRecipe(host)) {
        final found? => sectionOf(found, sectionKeyOf(host, title)),
        null => null,
      };
      if (section == null) {
        return const ReferenceResolution(ReferenceKind.held, missing: true);
      }
      return _childTail(line, section, section: title, host: host);
    }
    final similar = similarTitles(recipe, item, memo);
    final sectionsAlike = [
      for (final MapEntry(key: normalized, value: entries)
          in memo.sections.entries)
        if (itemWords.isNotEmpty &&
            itemWords.every(_refWords(normalized).contains))
          for (final s in entries)
            if (s.host != recipe.id) s,
    ];
    final last = item.split(' ').last;
    final ownAlike = [
      for (final sub in recipe.subsections)
        if (_refWords(_refNorm(sub.title ?? '')) case final words
            when words.any(itemWords.contains) && words.contains(last))
          sub,
    ];
    final libraryAlike = [
      for (final MapEntry(key: normalized, value: entries) in titles.entries)
        if (itemWords.isNotEmpty &&
            normalized != item &&
            itemWords.every(_refWords(normalized).contains))
          for (final e in entries)
            if (e.id != recipe.id) e,
    ];
    final candidates =
        ownAlike.length + libraryAlike.length + sectionsAlike.length;
    return ReferenceResolution(
      ReferenceKind.held,
      missing: !plural && candidates < 2 && own.length <= 1,
      similar: similar,
    );
  }
  // v47 (F7): a section's line naming its own host (a recipe's own id is
  // never a candidate; a section's host is).
  if (child.id == hostOf(recipe.id)) {
    return const ReferenceResolution(ReferenceKind.self);
  }
  final found = nutritionRecipeOf(db, child.id)?.recipe;
  if (found == null) {
    return const ReferenceResolution(ReferenceKind.held, missing: true);
  }
  return _childTail(line, found, named: named.length);
}

/// The tail every resolved child runs (v41's library tail; v44 a section's
/// too, design_v2 §2 v44.2): a SECTION with no ingredient lines is the
/// `no_ingredients` rule row (S13: lemon-meringue-pie|0's prose dough); a
/// child made from a recipe is `nested` (depth 1); else the share
/// [parseShare] reads from the line against the CHILD's own yield (a
/// section's `servings`, never its host's) — `routed`, or `noShare`. An
/// A9 line's bare count of exactly 1 reads one recipe (S11); v52 (M51 Q22,
/// rule WB) a line with no amount reads one whole batch, 1.0, of a child
/// with lines (a lineless library recipe — latin-flan, best-baked-potatoes —
/// reads `noShare`, so [resolveReference] keeps `noAmount`; it keeps the
/// batch only for a line no served-with marker reads). A child not
/// computed yet routes all the same: its parent's engine row reads its
/// recipe stale until the child's stamp lands (v41 F6), never a fetch.
ReferenceResolution _childTail(
  IngredientLine line,
  Recipe child, {
  int named = 0,
  String? section,
  String? host,
}) {
  final at = section == null
      ? null
      : (host: host ?? hostOf(child.id), title: section);
  if (section != null && nutritionLines(child).isEmpty) {
    return ReferenceResolution(
      ReferenceKind.section,
      section: at,
      noIngredients: true,
    );
  }
  if (nutritionLines(child).any((l) => isReferenceIn(child, l))) {
    return ReferenceResolution(
      ReferenceKind.nested,
      childId: child.id,
      section: at,
    );
  }
  final share =
      parseShare(line.raw, line.amounts, child.servings) ??
      (section != null &&
              !isSubRecipeReference(line.raw) &&
              line.amounts.length == 1 &&
              line.amounts.single.unit == null &&
              line.amounts.single.quantity.trim() == '1'
          ? 1.0
          : null) ??
      (line.amounts.isEmpty && nutritionLines(child).isNotEmpty ? 1.0 : null);
  return ReferenceResolution(
    share == null ? ReferenceKind.noShare : ReferenceKind.routed,
    childId: child.id,
    share: share,
    named: named,
    section: at,
  );
}

/// The library titles [recipe]'s prep note names for the reference [item],
/// in the note's order (design_v3 §2.2 item 2): only a note that says
/// "this page"; a title of two or more words, never [recipe] itself,
/// holding every word of the item; a title inside a longer one at the same
/// span is the longer one's. The first is the route; two or more flag it.
List<LibraryTitle> noteNamedTitles(
  Recipe recipe,
  String item,
  ResolverMemo memo,
) {
  final note = _refNorm(recipe.prepNotes ?? '');
  if (!note.contains('this page')) {
    return const [];
  }
  final itemWords = _refWords(item);
  final hits = <(int, String, LibraryTitle)>[];
  for (final MapEntry(key: normalized, value: entries) in memo.titles.entries) {
    final self = entries.every((e) => e.id == recipe.id);
    if (self || normalized.split(' ').length < 2) {
      continue;
    }
    final at = note.indexOf(normalized);
    if (at >= 0 && itemWords.every(_refWords(normalized).contains)) {
      hits.add((at, normalized, entries.firstWhere((e) => e.id != recipe.id)));
    }
  }
  hits.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return [
    for (final h in hits)
      if (!hits.any(
        (g) =>
            !identical(g, h) &&
            g.$1 <= h.$1 &&
            h.$1 + h.$2.length <= g.$1 + g.$2.length &&
            g.$2.length > h.$2.length,
      ))
        h.$3,
  ];
}

/// Library titles holding every word of [item] (never a section, never
/// [recipe] itself, never a title its note names or that equals the item),
/// fewest extra words first, then by normalised title; at most 5 (F12).
List<LibraryTitle> similarTitles(
  Recipe recipe,
  String item,
  ResolverMemo memo,
) {
  final itemWords = _refWords(item);
  final note = _refNorm(recipe.prepNotes ?? '');
  final out = <(int, String, LibraryTitle)>[];
  for (final MapEntry(key: normalized, value: entries) in memo.titles.entries) {
    final words = _refWords(normalized);
    if (itemWords.isEmpty ||
        normalized == item ||
        !itemWords.every(words.contains) ||
        (note.contains('this page') &&
            normalized.split(' ').length >= 2 &&
            note.contains(normalized))) {
      continue;
    }
    for (final e in entries) {
      if (e.id != recipe.id) {
        out.add((words.length - itemWords.length, normalized, e));
      }
    }
  }
  out.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return [for (final e in out.take(5)) e.$3];
}

/// The row a sub-recipe reference [line] (position [position] of [recipe])
/// is stored under (design_v3 §2.2 item 3): routed — `auto`, no food, no
/// description, confidence 1, `gram_source` recipe, the child's total grams
/// × the share and the child, its share and its stamp (`computed_at`);
/// held (`choose_recipe`, `nested_recipe` — which keeps its child and stamp
/// — `discarded_recipe`) — `auto`, 0 g, recipe, the hold; any other —
/// today's 0 g rule row ([subRecipeNote], S13).
IngredientMatchRow referenceRowFor(
  SaltDatabase db,
  Recipe recipe,
  int position,
  IngredientLine line,
  ResolverMemo memo,
) {
  final found = resolveReference(db, recipe, line, memo);
  final child = found.childId == null
      ? null
      : memo.childNutrition(found.childId!);
  IngredientMatchRow row(String? hold, {double? grams}) => IngredientMatchRow(
    recipeId: recipe.id,
    position: position,
    raw: line.raw,
    itemKey: lineKeyOf(line),
    fdcId: null,
    description: null,
    dataType: null,
    confidence: 1,
    grams: grams,
    gramSource: GramSource.recipe.name,
    status: 'auto',
    hold: hold,
    childRecipeId: hold == null || hold == nestedRecipeHold
        ? found.childId
        : null,
    childShare: hold == null ? found.share : null,
    childStamp: hold == null || hold == nestedRecipeHold
        ? child?.computedAt
        : null,
  );
  return switch (found.kind) {
    ReferenceKind.routed => row(
      null,
      grams: child?.totalGrams == null
          ? null
          : child!.totalGrams! * found.share!,
    ),
    ReferenceKind.nested => row(nestedRecipeHold, grams: 0),
    ReferenceKind.held => row(chooseRecipeHold, grams: 0),
    ReferenceKind.marinade => row(discardedRecipeHold, grams: 0),
    _ => _subRecipeRow(recipe, position, line, lineKeyOf(line)),
  };
}

/// The v41 hold codes of a reference line ([holdActions]).
const String chooseRecipeHold = 'choose_recipe';

/// A child recipe itself made from a recipe (depth 1).
const String nestedRecipeHold = 'nested_recipe';

/// A reference marinade, poured away (A5 a).
const String discardedRecipeHold = 'discarded_recipe';

/// The food alternative a reference line offers after its first " or " —
/// the split [isSubRecipeReference] reads — when it carries an AMOUNT
/// (A10 a): "1 recipe Basic Spice Rub for Pork Chops (recipe follows) or 2
/// teaspoons pepper" is 2 teaspoons of pepper; "… or lemon wedges, for
/// serving" is none. A person's food pick on the line is weighed on it.
IngredientLine? foodAlternativeOf(IngredientLine line) {
  if (!isSubRecipeReference(line.raw)) {
    return null;
  }
  final split = RegExp(
    r'(?<!\s)\s+or\s+',
    caseSensitive: false,
  ).firstMatch(line.raw);
  if (split == null) {
    return null;
  }
  final text = line.raw.substring(split.end);
  final parsed = parseIngredientLine(text);
  return parsed.amounts.isEmpty
      ? null
      : IngredientLine(
          raw: text,
          item: parsed.item,
          prep: parsed.prep,
          amounts: parsed.amounts,
        );
}

// ---------------------------------------------------------------------------
// Q25 (v54, matcherVersion 53; prep47 design_q25_v2, the owner's Q-a..Q-h):
// alcohol
// cooked off. ENERGY ONLY — a row's record, grams, status, bucket, hold,
// child and parts never move; nothing is stored: derived at compute from the
// recipe's steps (already in the ingredients hash), read by the totals
// ([recomputeTotals]) and the row's flag ([compositeFlagOf]).
// ---------------------------------------------------------------------------

/// Q25: the sixteen alcohol records (stage 1 §1) — record-keyed, as
/// [approximationRecords] and [nutrientSiblings]: FNDDS wine white, red,
/// rosé, rice and dessert sweet, beer, brandy, liqueur, vodka, tequila, rum,
/// whiskey; SR wine dessert dry, Pinot Noir, Riesling and sake. A 17th
/// (light beer, coffee liqueur, vanilla extract — Q-d) counts its full
/// energy until added: the safe side.
const Map<int, String> alcoholRecords = {
  2710689: 'wine',
  2710688: 'wine',
  175112: 'wine',
  2710692: 'wine',
  174835: 'wine',
  2710690: 'wine',
  2710691: 'wine',
  173200: 'wine',
  2710616: 'beer',
  167723: 'sake',
  2710699: 'brandy',
  2710623: 'liqueur',
  2710704: 'vodka',
  2710705: 'tequila',
  2710703: 'rum',
  2710700: 'whiskey',
};

/// [record]'s ethanol kcal per 100 g (design_q25_v2 §1.1 (A)): its energy
/// less the Atwater energy of its protein, fat and carbohydrate (4/9/4,
/// FDC 203/204/205 as cached) — 6.82–7.01 kcal per g of the raw details'
/// ethanol (FDC 221, never read: the cache keeps none), exact at 100 % and
/// never negative (208 − 7 × 221 would leave a spirit −2.80 kcal of
/// non-ethanol energy).
double ethanolKcalPer100g(FdcFood record) {
  final n = record.nutrientsPer100g;
  final energy = [
    for (final number in nutrientDefs.first.fdcNumbers) ?n[number],
  ].firstOrNull;
  if (energy == null) {
    return 0;
  }
  final rest = 4 * (n['203'] ?? 0) + 9 * (n['204'] ?? 0) + 4 * (n['205'] ?? 0);
  return max(0, energy - rest);
}

/// What Q25 reads of an alcohol line: the share of its ethanol the dish
/// keeps (`kept`, %), the USDA codes read (`code`, '+'-joined for a split,
/// '' at 100 %), the shape (`rule`) and the row's flag text (`flag`, null
/// at 100 %).
typedef AlcoholReading = ({
  double kept,
  String code,
  String rule,
  String? flag,
});

/// The share of [line]'s ethanol [recipe]'s dish keeps (USDA Table of
/// Nutrient Retention Factors, Release 6, group 14) and the flag it prints,
/// or null — not one of the [alcoholRecords], not a counted record row (a
/// skipped, held or 0 g row, a routed row, a parts row), or 100 %. A
/// person's typed grams are reduced the same way: retention applies to
/// whatever grams count and never changes them (design §8, critic 12).
AlcoholReading? alcoholRetentionOf(
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row,
) {
  final fdcId = row.fdcId;
  final grams = row.grams;
  if (fdcId == null ||
      !alcoholRecords.containsKey(fdcId) ||
      row.childRecipeId != null ||
      row.parts != null ||
      row.status == 'skipped' ||
      grams == null ||
      grams <= 0 ||
      noRecordHolds.contains(row.hold) ||
      (row.status == 'auto' &&
          (belowConfidenceGate(row.confidence) || row.hold != null))) {
    return null;
  }
  final reading = alcoholReadingOf(recipe, row.position, fdcId);
  return reading.kept >= 100 ? null : reading;
}

/// [alcoholRetentionOf]'s reading of the line at [position] on the record
/// [fdcId], whatever the row — the gate's and the pins' reader. Once per
/// line (RULE C, critic 10): Key: position — the line read (its head, its
/// amounts, its group); fdcId — its record's class word (R1).
AlcoholReading alcoholReadingOf(Recipe recipe, int position, int fdcId) =>
    _stepIndexOf(recipe).memo(
      ('alcohol', position, fdcId),
      () => _alcoholRead(recipe, position, fdcId),
    );

/// USDA R6 group 14 ("Alcohol, ethyl" retained, retn06.pdf p. 12): stirred
/// in and baked or simmered at least `minutes` (5004–5009). Under 15
/// minutes the table prints no stirred-and-heated row: 5002 (85 %, Q-a).
const List<({int minutes, int kept, String code})> _alcoholBands = [
  (minutes: 150, kept: 5, code: '5009'),
  (minutes: 120, kept: 10, code: '5008'),
  (minutes: 90, kept: 20, code: '5007'),
  (minutes: 60, kept: 25, code: '5006'),
  (minutes: 30, kept: 35, code: '5005'),
  (minutes: 15, kept: 40, code: '5004'),
];

/// One use of an alcohol line as read: kept %, the USDA code, the shape,
/// the minutes read (whole, the low end) and how the flag words it — the
/// whole row (`words`, after "alcohol") and a part of a split (`part`, after
/// the part's amount: design §5's split form, no figure's suffix, D4).
typedef _AlcoholUse = ({
  double kept,
  String code,
  String rule,
  int minutes,
  String words,
  String part,
});

/// A use heated [minutes] (stirred in, simmered or baked): its band. Under
/// one printed minute (a sauce tossed "30 seconds") it is 5002's own row,
/// boil-off — never "cooked 0 min" (closer1 D3).
_AlcoholUse _alcoholTimed(double minutes, {bool flamed = false}) {
  if (!flamed && minutes < 1) {
    return _alcoholBoilOff;
  }
  final whole = minutes.floor();
  for (final band in _alcoholBands) {
    if (whole >= band.minutes) {
      final kept = flamed && band.kept > 75 ? 75 : band.kept;
      return (
        kept: kept.toDouble(),
        code: band.code,
        rule: flamed ? 'flambe+time' : 'timed:$whole',
        minutes: whole,
        words: flamed
            ? 'flamed, then cooked $whole min keeps $kept %'
            : band.kept == 5
            ? "cooked $whole min keeps 5 %, the table's 2½-hour figure"
            : 'cooked $whole min keeps $kept %',
        part: flamed
            ? 'flamed, then cooked $whole min keeps $kept %'
            : 'cooked $whole min keeps $kept %',
      );
    }
  }
  return flamed
      ? (
          kept: 75,
          code: '5003',
          rule: 'flambe',
          minutes: whole,
          words: 'flamed keeps 75 %',
          part: 'flamed keeps 75 %',
        )
      : (
          kept: 85,
          code: '5002',
          rule: 'timed:$whole',
          minutes: whole,
          words:
              'cooked $whole min keeps 85 %, the stirred-into-hot-liquid '
              'figure',
          part: 'cooked $whole min keeps 85 %',
        );
}

const _AlcoholUse _alcoholBoilOff = (
  kept: 85,
  code: '5002',
  rule: 'boil_off',
  minutes: 0,
  words: 'stirred into hot liquid keeps 85 %',
  part: 'stirred into hot liquid keeps 85 %',
);

const _AlcoholUse _alcoholUntimed = (
  kept: 85,
  code: '5002',
  rule: 'heated_untimed',
  minutes: 0,
  words: 'heated, time not printed, keeps 85 %',
  part: 'heated, time not printed, keeps 85 %',
);

/// Q-f (the owner): stirred in OFF the heat into a hot dish IS USDA 5002
/// "ALC BEV, STIRRED INTO HOT LIQ" (85 %). The whole row prints 5002's own
/// approved text (§5, boil-off); a part of a split, §5's approved split
/// form "{part} stirred in off the heat keeps …" at Q-f's 85 (closer1 D5).
const _AlcoholUse _alcoholOffHeat = (
  kept: 85,
  code: '5002',
  rule: 'off_heat',
  minutes: 0,
  words: 'stirred into hot liquid keeps 85 %',
  part: 'stirred in off the heat keeps 85 %',
);

_AlcoholUse _alcoholKept(String rule) => (
  kept: 100,
  code: '',
  rule: rule,
  minutes: 0,
  words: '',
  part: 'keeps 100 %',
);

/// One sentence of a recipe's steps as Q25 reads it: its step, its index in
/// [_StepIndex.sentences], its lower-cased text with every parenthesis
/// removed, whether it is no text at all (all parenthesis) and whether it
/// is a side task — a sentence opening "Meanwhile" or "While", an optional
/// one ("If soccarat is desired"), or any sentence of a step that opens
/// so (critic 5).
typedef _AlcoholSentence = ({
  int step,
  int index,
  String text,
  bool empty,
  bool side,
  bool sideStep,
  double? altBake,
});

/// A printed alternative bake ("(To serve right away, bake as directed in
/// step 7, reducing the baking time to 12 to 15 minutes.)", 0939): the
/// shorter alternative (design §2), read from the parenthesis it sits in.
final RegExp _alcoholAltBake = RegExp(
  r'\breduc\w* the (baking|cooking) time to [^.;)]*\bminutes\b',
);

/// A side task's opening clause ("While gratin bakes, ", "Meanwhile, ").
final RegExp _alcoholSideClause = RegExp(
  r'^(meanwhile|while\b[^,]*|if\b[^,]*)(,\s*|\s+)',
);

final RegExp _alcoholSideOpening = RegExp(
  r'^(meanwhile|while)\b|^if\b[^.;]*\b(desired|using|you like|preferred)\b',
);

/// [recipe]'s sentences ([_StepIndex.sentences], every step in order), the
/// parentheses dropped (critic 5: "(Check the chicken after 15 minutes)"
/// is no time the wine cooks). Once per recipe.
List<_AlcoholSentence> _alcoholSentencesOf(Recipe recipe) {
  final index = _stepIndexOf(recipe);
  return index.memo(#alcoholSentences, () {
    final out = <_AlcoholSentence>[];
    for (final (i, step) in index.sentences.indexed) {
      var depth = 0;
      final texts = <String>[];
      final alts = <double?>[];
      for (final sentence in step) {
        final kept = StringBuffer();
        final dropped = StringBuffer();
        for (final c in sentence.split('')) {
          if (c == '(') {
            depth++;
          } else if (c == ')') {
            depth = depth > 0 ? depth - 1 : 0;
          } else if (depth == 0) {
            kept.write(c);
          } else {
            dropped.write(c);
          }
        }
        texts.add(kept.toString().replaceAll(RegExp(r'\s+'), ' ').trim());
        alts.add(switch (_alcoholAltBake.firstMatch(dropped.toString())) {
          final m? => _alcoholMinutesIn(m[0]!),
          null => null,
        });
      }
      final sideStep =
          texts.isNotEmpty && _alcoholSideOpening.hasMatch(texts.first);
      for (final (j, text) in texts.indexed) {
        out.add((
          step: i,
          index: j,
          text: text,
          empty: text.length < 3,
          side: _alcoholSideOpening.hasMatch(text),
          sideStep: sideStep,
          altBake: alts[j],
        ));
      }
    }
    return out;
  });
}

/// Q25's OWN heat vocabulary (critic 1: never the frying set
/// [_heatVerbWords], which holds no simmer, boil, cook or bake and fires on
/// register, read, keep and hold): a cooking verb, "bring … to a boil", a
/// pan with browned bits to scrape, a pan set over a flame.
final RegExp _alcoholHeat = RegExp(
  r'\b(simmer\w*|boil\w*|cook(s|ed|ing)?|bak(e|es|ed|ing)|brais\w*|'
  r'roasting|^roast|(?<!\b(the|a|each|of|whole) )roast(ed)?'
  r'(?=,| (until|for|uncovered|covered|at|the|it)\b)|'
  r'reduc(e|es|ed|ing)|evaporat\w*|saut[eé]\w*|'
  r'broil(s|ed|ing)?|steam(s|ed|ing)?|stir-fr\w*|microwav\w*|'
  r'fr(y|ies|ied|ying))\b|'
  r'\bbring\b[^.;]*?\bto (a |the )?(boil|simmer)|browned bits|'
  r'\bover (low|medium|high|medium-low|medium-high)( |-)?(high |low )?heat\b',
);

/// What [_alcoholHeat] must not read as cooking (critic 5, verb position):
/// a utensil or a liquid named for its use, and a past participle before
/// its noun ("cooked rice", "the reduced wine").
final RegExp _alcoholNotHeat = RegExp(
  r'\b(baking (sheets?|dish(es)?|pans?|powder|soda|stones?|steels?|paper|'
  'mats?)|cooking (spray|liquid|water|time|grate|wine)|roasting pans?|'
  'frying pans?|(slow|pressure)[- ]cookers?|cooker|reduced[- ]sodium|'
  r'reduc\w* (the )?(mixer )?speed|preheat\w*\b[^.;]*|'
  '(cooked|baked|roasted|fried|steamed|boiled|braised|reduced|sautéed|'
  'sauteed|broiled|simmered) (?!through|until|and|in|on|for|at|over|with|to|'
  'uncovered|covered|or|then|about|halfway)[a-z]+)',
);

bool _alcoholHeats(String text) =>
    _alcoholHeat.hasMatch(text.replaceAll(_alcoholNotHeat, ' '));

/// A flame (critic 2): read in the adding sentence and the next two of its
/// step, before the off-heat arm.
final RegExp _alcoholIgnites = RegExp(
  r'\bignit|\bflamb|\blight (a )?(long )?match|\blit (a )?(long )?match',
);

/// Off the heat (decision 3, Q-f).
final RegExp _alcoholOffHeatWords = RegExp(
  r'\boff (the )?heat\b|\bremove[^.;]*\bfrom (the )?heat\b',
);

/// The vessel back on the heat or into the oven or the slow cooker
/// (critic 2, 4).
final RegExp _alcoholReturns = RegExp(
  r'\breturn\b[^.;]*\bto (the )?([a-z-]+ )?(heat|oven|burner)\b|'
  r'\bcontinue to (cook|bake|roast|simmer)\b|'
  r'\bset\b[^.;]*\bover\b[^.;]*heat|\b(to|in|into) (the )?oven\b|'
  r'\bslow[- ]cooker\b|\b(cook|bring|simmer|heat)\b[^.;]*\bover '
  r'(low|medium|high|medium-low|medium-high)( |-)?(high |low )?heat\b',
);

/// A run's end (critic 5, verb position), by kind: `final` (served),
/// `removal` (off the heat, out of the oven: a later return takes it back,
/// critic 4), `wait` (cooled, chilled, left to stand, set aside: a cold
/// premix waits so before its heat) and `out` (strained, poured off, the
/// liquid or the food moved out).
final RegExp _alcoholStops = RegExp(
  r'(?<final>\bserve\b)|'
  r'(?<removal>\boff (the )?heat\b|\bremove\b[^.;]*\bfrom (the )?'
  r'(heat|oven|grill)\b)|'
  r'(?<wait>\b(let|allow)\b[^.;]*\b(cool|stand|rest|sit|settle)\b|'
  r'\bcool (for|slightly|completely|to)\b|^cool\b|\brefrigerat\w*|'
  r'\bchill\b|\bfreez\w*|\bset aside\b|\bkeep warm\b)|'
  r'(?<out>\bstrain\b|\bthrough (a )?fine-mesh\b|'
  r'\btransfer (the )?(sauce|mixture|liquid|braising liquid|stock|broth|'
  r'gravy|soup|reduction|syrup|glaze)\b[^.;]* to (a |the )?([\w-]+ )*?'
  '(bowl|container|measuring cup|jar|fat separator|serving|platter|'
  r'gravy boat|pitcher|blender)\b|'
  r'\b(transfer|place|stack)\b[^.;]*\b(to|on|onto) (a |the )?([\w-]+ )*'
  '(wire rack|paper towels?|paper bag|(?<!pie )plate|platter|cutting board|'
  'carving board))',
);

String _alcoholStopKind(RegExpMatch m) => m.namedGroup('final') != null
    ? 'final'
    : m.namedGroup('removal') != null
    ? 'removal'
    : m.namedGroup('wait') != null
    ? 'wait'
    : 'out';

/// A vessel a sentence names, by kind.
final RegExp _alcoholVessel = RegExp(
  r'\b(dutch oven|stockpot|skillet|saucepan|roasting pan|baking dish|'
  'gratin dish|casserole|wok|slow[- ]cooker|multicooker|pot|pan|dish|'
  'bowl|measuring cup|liquid measure|blender|food processor|processor|'
  'baking sheet|sheet pan|container|bag|ramekins?|pie plate|mixer|'
  r'fat separator)\b',
);

String _alcoholVesselKind(String v) => switch (v) {
  'dutch oven' || 'stockpot' => 'pot',
  'fat separator' => 'separator',
  'baking dish' || 'gratin dish' || 'casserole' || 'pie plate' => 'dish',
  'slow-cooker' => 'slow cooker',
  'food processor' => 'processor',
  'baking sheet' || 'sheet pan' => 'sheet',
  'liquid measure' => 'measuring cup',
  'ramekin' => 'ramekins',
  _ => v,
};

/// A cold vessel named by what is in it ("the bowl with the pureed
/// chicken").
final RegExp _alcoholColdVessel = RegExp(
  r'\b(bowl|measuring cup|container) (with|containing) (?<rest>[^.;,]*)',
);

/// The vessels a cold mix is made in (R4, R6): never on the heat.
const Set<String> _alcoholColdVessels = {
  'separator',
  'bowl',
  'measuring cup',
  'blender',
  'processor',
  'container',
  'bag',
  'mixer',
};

/// The kinds of vessel [text] names; a now-empty, clean, second or
/// separate one is `other|<kind>` (never the line's, closer1 D3: but the
/// line put there goes with it, "transfer the pork to a clean bowl").
Set<String> _alcoholVesselsIn(String text) => {
  for (final m in _alcoholVessel.allMatches(text))
    if (text.substring(max(0, m.start - 40), m.start) case final before)
      RegExp(
            '(now-empty|again-empty|clean|cooled|second|third|fourth|'
            r'separate|another)( [\w-]+){0,3} $',
          ).hasMatch(before)
          ? 'other|${_alcoholVesselKind(m[0]!)}'
          : RegExp(r'\ban? $').hasMatch(before)
          ? 'other|${_alcoholVesselKind(m[0]!)}'
          : [
              ?RegExp(
                r'\b(small|medium|large|\d+-inch) ([\w-]+ ){0,2}$',
              ).firstMatch(before)?[1],
              _alcoholVesselKind(m[0]!),
            ].join('|'),
};

/// Whether the vessels [a] and [b] are one: the same kind (a bare "pan"
/// any cooking vessel), and the same size when both print one.
bool _alcoholSameVessel(String a, String b) {
  if (a.startsWith('other|') || b.startsWith('other|')) {
    return a == b;
  }
  final x = a.split('|');
  final y = b.split('|');
  final kindX = x.last;
  final kindY = y.last;
  const cooking = {
    'roasting pan',
    'pot',
    'skillet',
    'saucepan',
    'pan',
    'wok',
    'dish',
    'slow cooker',
    'multicooker',
    'sheet',
    'ramekins',
  };
  final kinds =
      kindX == kindY ||
      (kindX == 'pan' && cooking.contains(kindY)) ||
      (kindY == 'pan' && cooking.contains(kindX));
  return kinds && (x.length == 1 || y.length == 1 || x.first == y.first);
}

/// A printed duration: a number (a vulgar fraction, a range read at its LOW
/// end, critic 3) and its unit.
final RegExp _alcoholDuration = RegExp(
  r'(?<pre>every|after|up to)?\s*(?:about\s+)?'
  '(?<n>\\d+\\s*[$vulgarFractionChars]?|[$vulgarFractionChars]|an?)\\s*'
  '(?<u1>seconds?|minutes?|hours?)?'
  '(?:\\s*(?:to|-|–)\\s*(?:\\d+\\s*[$vulgarFractionChars]?|'
  '[$vulgarFractionChars]))?'
  r'\s*(?<u>seconds?|minutes?|hours?)\b'
  r'(?<more>\s*(?:and\s*)?\d+\s*minutes?)?'
  r'(?<side>\s*(per|for each|on each) side)?',
);

/// An optional clause ("; if necessary, simmer until slightly thickened, 1
/// to 2 minutes", 0125): its minutes are not read (design R3).
final RegExp _alcoholOptional = RegExp(
  r'(^|[;,] )if (necessary|needed|desired)\b',
);

/// The minutes [text] prints: each duration at its low end, "per side"
/// twice; a nested "after N minutes", an "every N minutes" and an "up to"
/// none, but a sentence OPENING "After 1 hour" is the elapsed time of the
/// cook before it (0084); an alternative — after ", or", or "N minutes
/// for X or M minutes for Y" — the SHORTER (P16).
double _alcoholMinutesIn(String text) {
  double? least;
  final asked = _alcoholOptional.firstMatch(text)?.start;
  for (final alternative in text.substring(0, asked).split(', or ')) {
    var total = 0.0;
    double? last;
    var lastEnd = 0;
    for (final m in _alcoholDuration.allMatches(alternative)) {
      final pre = m.namedGroup('pre');
      if (pre != null && !(pre == 'after' && m.start == 0)) {
        continue;
      }
      final n = m.namedGroup('n')!.trim();
      final value = n.startsWith('a') ? 1.0 : parseQuantity(n) ?? 0;
      final unit = m.namedGroup('u1') ?? m.namedGroup('u')!;
      var minutes = unit.startsWith('second')
          ? value / 60
          : unit.startsWith('hour')
          ? value * 60
          : value;
      if (m.namedGroup('more') case final more?) {
        minutes += double.parse(RegExp(r'\d+').firstMatch(more)![0]!);
      }
      if (m.namedGroup('side') != null) {
        minutes *= 2;
      }
      final between = alternative.substring(lastEnd, m.start);
      if (last != null &&
          RegExp(r'\bor\b').hasMatch(between) &&
          !between.contains(RegExp('[;.]'))) {
        if (minutes < last) {
          total += minutes - last;
          last = minutes;
        }
      } else {
        total += minutes;
        last = minutes;
      }
      lastEnd = m.end;
    }
    if (total > 0 && (least == null || total < least)) {
      least = total;
    }
  }
  return least ?? 0;
}

/// What a run follows of a line (R3, R6): its name, the words of its adding
/// sentence ("soy" for a "soy mixture"), and the vessel it is in.
typedef _AlcoholTrail = ({
  String name,
  Set<String> words,
  String? vessel,
  Set<String> foods,
  Set<String> vocab,
});

/// A sentence that puts something into a vessel or over a food.
final RegExp _alcoholPutsIn = RegExp(
  r'\b(return|add|stir|whisk|pour|spread|spoon|bring|transfer|combine|'
  r'toss|nestle|place|arrange|top|layer|ladle|turn|dip)\w*\b',
);

/// Whether [text] names the line [t] follows SPECIFICALLY: its name, its
/// group's word, a food it was poured over, or a "<word> mixture" of its
/// adding sentence — never a bare "liquid" or "sauce".
bool _alcoholNamesOwn(String text, _AlcoholTrail t) =>
    _alcoholOwnMention(text, t.name) ||
    _alcoholHeadsIn(
      text,
      t.foods,
    ).any((f) => _alcoholOwnMention(text, f)) ||
    RegExp(r'\b([a-z]+)([ -])([a-z]+ )?mixture\b')
        .allMatches(text)
        .any(
          (m) => m[2] == '-'
              // "garlic-shallot mixture": both words, never "garlic" alone
              // from the line's "chili-garlic sauce" (0544; closer1 D3)
              ? t.words.contains(m[1]) && t.words.contains(m[3]?.trim())
              : switch (m[3]?.trim()) {
                  // "soy sauce mixture": the word next to "mixture", or the one
                  // before it — never across "and" ("very soft and mixture is
                  // reduced", 0986; closer1 D3)
                  final y? =>
                    t.words.contains(y) ||
                        t.foods.contains(y) ||
                        (!const {
                              'and',
                              'or',
                              'the',
                              'with',
                              'of',
                              'is',
                              'are',
                            }.contains(y) &&
                            (t.words.contains(m[1]) || t.foods.contains(m[1]))),
                  null => t.words.contains(m[1]) || t.foods.contains(m[1]),
                },
        );

/// Whether [text] names [word] as the trail's own portion — never "the
/// remaining 4 teaspoons garlic" or "3 tablespoons of the cognac", another
/// portion of it, nor "the stuffing ingredients" (all of a group's).
bool _alcoholOwnMention(String text, String word) =>
    // the first mention decides: "add remaining ¼ cup broth and cook …
    // until broth evaporates" is the other portion throughout (1138)
    RegExp('\\b${RegExp.escape(word)}').allMatches(text).take(1).any((m) {
      final before = text.substring(max(0, m.start - 60), m.start);
      return !_alcoholRemainingBefore.hasMatch(before) &&
          !_alcoholAmountBefore.hasMatch(before) &&
          // "the stuffing ingredients": the group's, not this line (0448)
          !RegExp(r'^\w* ingredients\b').hasMatch(text.substring(m.end));
    });

/// A sentence putting a liquid word somewhere — the verb's own object, in
/// one clause ("Return liquid to pot"; never "… cook, until liquid has
/// evaporated").
final RegExp _alcoholPutsLiquid = RegExp(
  r'\b(return|add|stir|whisk|pour|spread|spoon|bring|transfer|combine|'
  r'toss|nestle|place|arrange|top|layer|ladle|scrape)\w*\b[^,.;]*?'
  '((?<!mushroom |porcini |clam |soaking |tomato )'
  r'\b(liquid|jus|marinade|reduction|glaze|batter|filling|contents)\b|'
  r'\bthe mixture\b|'
  '(?<!soy |fish |hot |oyster |hoisin |worcestershire |chili |tomato |'
  r'barbecue |dipping |tartar )\bsauce\b)',
);

/// While a cold mix waits in its bowl, a put of "the … mixture" or "paste"
/// is it (the only mix made: "spread cheese mixture evenly over slices").
final RegExp _alcoholPutsMixture = RegExp(
  r'\b(return|add|stir|whisk|pour|spread|spoon|transfer|scrape)\w*\b'
  r'[^,.;]*?\b((?<what>[a-z]+) )?(mixture|paste)\b',
);

/// A pour with no object named: the mix just made ("Pour around fish").
final RegExp _alcoholPoursIt = RegExp(
  r'^(pour|drizzle|spoon)\s+(it\s+)?(evenly\s+)?(over|around|into|onto)\b|'
  // "Whisk sauce to recombine. Add to skillet and cook" (0532)
  r'^add (it )?to\b',
);

/// The vessel a sentence puts something into ("… to the Dutch oven", "in
/// large saucepan"): `to`/`into` moves, `in` places.
final RegExp _alcoholIntoVessel = RegExp(
  r'\b(?<prep>to|into|in|on)\s+(a |the )?(?<what>([\w-]+ ){0,3}?'
  '(dutch oven|stockpot|skillet|saucepan|roasting pan|baking dish|'
  'gratin dish|casserole|wok|slow[- ]cooker( insert)?|multicooker|pot|pan|'
  'dish|bowl|measuring cup|liquid measure|blender|food processor|'
  'processor|container|bag|ramekins?|pie plate|mixer|baking sheet|'
  r'fat separator))\b',
);

/// Whether the vessel [v] is the trail's.
bool _alcoholIsTrailVessel(String v, _AlcoholTrail t) => t.vessel == null
    ? !v.startsWith('other|') && !_alcoholCold(v)
    : _alcoholSameVessel(v, t.vessel!);

/// Whether the vessel [v] is one a cold mix is made in (a bowl, a measuring
/// cup — a clean one too): never on the heat.
bool _alcoholCold(String? v) =>
    v != null && _alcoholColdVessels.contains(v.split('|').last);

/// Whether the removal at sentence [at] is taken back before a hard stop:
/// "Remove the pot from the oven. … return the pot to the oven" (0005).
bool _alcoholReturnsAfter(List<_AlcoholSentence> s, int at, int from) {
  for (var i = at; i < s.length && i <= at + 6; i++) {
    if (s[i].empty) {
      continue;
    }
    final text = i == at ? s[i].text.substring(from) : s[i].text;
    if (_alcoholReturns.hasMatch(text)) {
      return true;
    }
    if (i > at &&
        _alcoholStops
            .allMatches(text)
            .any(
              (m) => _alcoholStopKind(m) != 'removal',
            )) {
      return false;
    }
  }
  return false;
}

/// Whether the vessel at sentence [at] is already on the heat: the nearest
/// earlier read sentence of its step or the one before heats it with no
/// stop after.
bool _alcoholCarried(List<_AlcoholSentence> s, int at) {
  for (var i = at - 1; i >= 0 && s[i].step >= s[at].step - 1; i--) {
    final text = s[i].text;
    if (s[i].empty ||
        s[i].side ||
        (s[i].sideStep && s[i].step != s[at].step) ||
        _alcoholMicrowave.hasMatch(text)) {
      continue;
    }
    final stops = _alcoholStops.allMatches(text).map((m) => m.start);
    final heats = _alcoholHeat
        .allMatches(text.replaceAll(_alcoholNotHeat, ' '))
        .map((m) => m.start);
    if (stops.isEmpty && heats.isEmpty) {
      continue;
    }
    return heats.isNotEmpty &&
        (stops.isEmpty || heats.reduce(max) > stops.reduce(max));
  }
  return false;
}

/// A microwave heats its own bowl, never the line's pot.
final RegExp _alcoholMicrowave = RegExp(r'\bmicrowave');

/// The vessel the line added at sentence [at] goes into: the vessel the
/// sentence names, else the nearest earlier one of its step or the one
/// before; [near]: the sentence and the one before it only.
String? _alcoholVesselAt(
  List<_AlcoholSentence> s,
  int at, {
  bool near = false,
}) {
  for (
    var i = at;
    i >= 0 && s[i].step >= s[at].step - 1 && (!near || i >= at - 1);
    i--
  ) {
    if (near && s[i].step != s[at].step) {
      break;
    }
    final vessels = [
      for (final v in _alcoholVesselsIn(s[i].text))
        if (!v.startsWith('other|')) v else if (i == at) v.substring(6),
    ];
    if (vessels.isNotEmpty) {
      return vessels.first;
    }
  }
  return null;
}

/// A broil browns a surface: no stirred row is baked or simmered so
/// (R6 5004–5009 "BKD/SIMMRD"); its minutes are not read.
final RegExp _alcoholBroil = RegExp(r'\bbroil');

/// A run's reading: the minutes printed while the line is on the heat, of
/// them the oven's (`ovenMinutes`, what a not-stirred pour-over is baked),
/// whether it met heat at all, whether a heat ran "until" a doneness with
/// no time (`until`: heated, untimed) and whether a stop came within two
/// sentences of the heat's start (`closes`: boil-off, critic 9).
typedef _AlcoholRunRead = ({
  double minutes,
  double ovenMinutes,
  bool heated,
  bool sealed,
  bool until,
  bool closes,
});

/// Water heating another vessel ("a saucepan filled with 1 inch of barely
/// simmering water"; the pasta's "boiling water"; "hot running water").
final RegExp _alcoholHeatedWater = RegExp(
  r'\b(simmering|boiling|salted|hot running|running) water\b',
);

/// A heat run until a doneness, no time printed ("roast until … registers
/// 160 degrees", "cook until evaporated"): heated, untimed (critic 9).
final RegExp _alcoholUntilHeat = RegExp(
  r'\b(cook|simmer|boil|bake|roast|brais|reduc|fry|fried|saut|broil|steam)'
  r'\w*\b[^.;]*?\buntil\b',
);

/// A sealed pressure cooker (§2): its minutes are not read, and a line
/// heated only so keeps 100 %.
final RegExp _alcoholSeals = RegExp(r'\block (the )?lid\b|\bpressure[- ]cook');
final RegExp _alcoholUnseals = RegExp(
  r'\b(quick-release|release (the )?pressure|natural(ly)? release)',
);

/// R3: the minutes the line added at sentence [at] (from its offset
/// [from]) stays on the heat. [onHeat]: the vessel is on the heat; else
/// the timer starts at the first heat in the line's vessel (a cold mix
/// waits — chilled, set aside — until then, critic 7). The run follows the
/// line: a sentence putting its name, a liquid word or a "<word> mixture"
/// of its adding sentence to or into a vessel moves it there; a sentence
/// putting something in another vessel is a side task, as is the rest of
/// its step until the line's vessel is named again (critic 5); side
/// sentences and parentheses are skipped. Every read sentence's printed
/// durations count until a stop: a removal a later return takes back goes
/// on (critic 4); otherwise the run follows the line's liquid to the first
/// later sentence that puts it somewhere and goes on from there, the timer
/// at its next heat; a dish served ends it.
_AlcoholRunRead _alcoholRun(
  List<_AlcoholSentence> s,
  int at,
  int from,
  _AlcoholTrail start, {
  required bool onHeat,
  bool follow = true,
}) {
  var started = onHeat;
  var place = (trail: start, aside: false, here: start.vessel);
  final batter = start.foods.any(_alcoholBatter.hasMatch);
  var total = 0.0;
  var leaves = false;
  double? altBake;
  var ovenTotal = 0.0;
  var heated = started;
  var until = false;
  var heatAt = started ? at : null;
  int? stopAt;
  var sealed = false;
  var underPressure = false;
  var step = s[at].step;
  _AlcoholRunRead read() => (
    minutes: total,
    ovenMinutes: ovenTotal,
    heated: heated,
    sealed: sealed,
    until: until,
    closes: switch ((heatAt, stopAt)) {
      (final h?, final t?) => t <= h + 2,
      _ => false,
    },
  );
  // The words of the sentences read since the adding one: a "<word>
  // mixture" made of them is another mix.
  // (closer1 D3: the words of every sentence before the adding one too,
  // singular as well, but never the adding sentence's own — "the mushroom
  // mixture" is the mushrooms' (0448), "the water mixture" the line's.)
  Set<String> wordsIn(String t) => {
    for (final w in RegExp('[a-z]+').allMatches(t)) ...{
      w[0]!,
      _alcoholSingular(w[0]!),
    },
  };
  final seen = <String>{
    for (final x in s.take(at)) ...wordsIn(x.text),
  }.difference(wordsIn(s[at].text));
  for (var i = at; i < s.length; i++) {
    final x = s[i];
    if (x.step != step) {
      place = (trail: place.trail, aside: false, here: place.trail.vessel);
      step = x.step;
    }
    if (x.altBake case final alt?) {
      altBake = alt;
    }
    if (x.empty) {
      continue;
    }
    // A side task ("While gratin bakes, combine panko … in bowl";
    // "Meanwhile, bring 4 quarts water to a boil in a large pot") is read
    // without its opening clause: one that puts the line takes it there
    // ("While the chicken rests, whisk the mustard into the cooking
    // liquid"); any other starts a side task the step's later sentences
    // stay in until the line or its vessel comes back (closer1 D3: never
    // the whole step, 0699, 0361, 0448).
    final sideTask = i != at && x.side;
    final text = i == at
        ? x.text.substring(from)
        : sideTask
        ? x.text.replaceFirst(_alcoholSideClause, '')
        : x.text;
    if (sideTask &&
        !(_alcoholPutsIn.hasMatch(text) &&
            (_alcoholNamesOwn(text, place.trail) ||
                _alcoholPutsLiquid.hasMatch(text)))) {
      seen.addAll([
        for (final w in RegExp('[a-z]+').allMatches(text)) ...[
          w[0]!,
          _alcoholSingular(w[0]!),
        ],
      ]);
      place = (
        trail: place.trail,
        aside: true,
        here: _alcoholContext(text, place, waiting: !started).here,
      );
      continue;
    }
    if (i != at) {
      final was = place.trail.vessel;
      place = _alcoholContext(text, place, waiting: !started, seen: seen);
      seen.addAll([
        for (final w in RegExp('[a-z]+').allMatches(text)) ...[
          w[0]!,
          _alcoholSingular(w[0]!),
        ],
      ]);
      if (place.aside) {
        continue;
      }
      // What the line's vessel takes while it is in it names a later
      // "<word> mixture" of it ("Add reserved tomato juice and simmer …
      // stir in reserved tomato juice mixture", 0347; closer1 D3).
      if (started && _alcoholPutsIn.hasMatch(text)) {
        final t = place.trail;
        place = (
          trail: (
            name: t.name,
            words: {...t.words, ..._alcoholMixWords(text)},
            vessel: t.vessel,
            foods: t.foods,
            vocab: t.vocab,
          ),
          aside: false,
          here: place.here,
        );
      }
      final now = place.trail.vessel;
      if (now != was && now != null) {
        // Moved into a bowl, a measuring cup (closer1 D3): off the heat,
        // waiting; put into a pot already on the heat: its timer starts.
        if (_alcoholCold(now)) {
          // … after the minutes this sentence prints before the move
          // ("scrape … until eggs just form cohesive mass, 1 to 2 minutes;
          // transfer to clean bowl", 1145)
          leaves = started;
        } else if (!started &&
            _alcoholStovetop.contains(now.split('|').last) &&
            _alcoholCarried(s, i)) {
          started = heated = true;
          heatAt ??= i;
        }
      }
    }
    // A cold mix waiting for its heat is not stopped by a rest, a chill or
    // a move ("Transfer the dough pieces to a plate … refrigerate").
    final stops = [
      for (final m in _alcoholStops.allMatches(text))
        if (started ||
            _alcoholStopKind(m) == 'final' ||
            _alcoholStopKind(m) == 'removal')
          m,
    ];
    final stop = stops.firstOrNull;
    final upTo = stop == null ? text : text.substring(0, stop.start);
    // D1 ruling (closer1): a stuffing rolled or wrapped inside a roast is
    // not cooked by the roast — the roasts that do so print a rare to
    // medium-rare doneness (85 °F, 120 °F), so the run ends where the
    // cooled mixture is rolled in (1129 beef-wellington|14, 0216|7).
    if (!started && heated && _alcoholRolledIn.hasMatch(upTo)) {
      return read();
    }
    if (!started &&
        _alcoholHeats(upTo) &&
        // a dough or batter waiting starts at its own bake, fry or cook —
        // never another food put on to cook beside it ("Add remaining
        // strawberries to rhubarb liquid and cook …", 0986; closer1 D3)
        (!batter ||
            _alcoholBakes.hasMatch(upTo) ||
            _alcoholNamesOwn(upTo, place.trail) ||
            !RegExp(r'^(add|return|transfer|place|pour)\b').hasMatch(upTo))) {
      started = heated = true;
      heatAt ??= i;
    }
    if (started &&
        _alcoholUntilHeat.hasMatch(
          upTo
              .replaceAll(_alcoholNotHeat, ' ')
              .replaceAll(_alcoholHeatedWater, ' '),
        )) {
      until = true;
    }
    if (_alcoholSeals.hasMatch(upTo)) {
      underPressure = sealed = true;
    }
    if (_alcoholUnseals.hasMatch(upTo)) {
      underPressure = false;
    }
    double minutesIn(String t) {
      if (!started ||
          underPressure ||
          _alcoholBroil.hasMatch(t) && !_alcoholOven.hasMatch(t)) {
        return 0;
      }
      return _alcoholMinutesIn(t);
    }

    void count(String t) {
      var m = minutesIn(t);
      if (altBake case final alt? when m > alt && _alcoholOven.hasMatch(t)) {
        m = alt;
      }
      total += m;
      if (_alcoholOven.hasMatch(t)) {
        ovenTotal += m;
      }
    }

    count(upTo);
    if (leaves) {
      leaves = false;
      started = false;
      continue;
    }
    if (stop == null) {
      continue;
    }
    if (heatAt != null) {
      stopAt ??= i;
    }
    final kind = _alcoholStopKind(stop);
    if (kind == 'removal' &&
        _alcoholReturnsAfter(s, i, i == at ? from + stop.end : stop.end)) {
      count(text.substring(stop.end));
      continue;
    }
    if (kind == 'final' || !started) {
      return read();
    }
    // Strained INTO a vessel (closer1 D3): the line goes there, named as
    // the step names it, and waits for that vessel's heat ("Strain the
    // mixture through a fine-mesh strainer set over a small saucepan …
    // Place the saucepan over medium-high heat", 0184; "Strain stock …
    // set over bowl … Slowly whisk in stock", 1076).
    if (_alcoholStrainInto.firstMatch(text) case final m?) {
      if (_alcoholVesselsIn(m.namedGroup('v')!).firstOrNull case final v?) {
        final t = place.trail;
        final what = m.namedGroup('what')!.split(' ').last;
        place = (
          trail: (
            name: t.name,
            words: t.words,
            vessel: v,
            foods: {
              if (what != 'mixture') ...{what, _alcoholSingular(what)},
            },
            vocab: t.vocab,
          ),
          aside: false,
          here: v,
        );
        started = false;
        continue;
      }
    }
    // The liquid followed (R6): the first later sentence that puts it.
    final next = follow ? _alcoholFollows(s, i, place.trail) : null;
    if (next == null) {
      return read();
    }
    i = next.at - 1;
    place = (trail: next.trail, aside: false, here: next.trail.vessel);
    started = _alcoholHeats(s[next.at].text) || _alcoholCarried(s, next.at);
    heated = heated || started;
    if (started) {
      heatAt ??= next.at;
    }
    step = s[next.at].step;
  }
  return read();
}

/// A roast rolled or wrapped round a stuffing (the D1 ruling).
final RegExp _alcoholRolledIn = RegExp(
  r'\b(roll|wrap)\w*\b[^.;]*\b(roast|beef|tenderloin)\b',
);

/// A strain into a vessel: what is strained and where it goes.
final RegExp _alcoholStrainInto = RegExp(
  r'\bstrain (the )?(?<what>[a-z]+( [a-z]+)?) through\b[^.;]*?'
  r'\b(over|into|in) (a |the )?(?<v>([\w-]+ ){0,2}(saucepan|pot|skillet|'
  r'bowl|measuring cup|liquid measure|container|dutch oven|pan))\b',
);

/// The run's place: the trail, whether the sentence read is a side task,
/// and the vessel the step is working in.
typedef _AlcoholPlace = ({_AlcoholTrail trail, bool aside, String? here});

/// The place after reading [text] (R3, R6, critic 5): a sentence putting
/// the line — its name, a liquid word, a "<word> mixture" of its adding
/// sentence, a food it was poured over — to or into a vessel (or into the
/// vessel the step works in) moves it there; one putting something in or
/// into another vessel starts a side task, as does any sentence while a
/// cold mix waits in its bowl ([waiting]); one naming the line's vessel
/// ends it.
_AlcoholPlace _alcoholContext(
  String text,
  _AlcoholPlace at, {
  required bool waiting,
  Set<String> seen = const {},
}) {
  final trail = at.trail;
  final dests = [
    for (final m in _alcoholIntoVessel.allMatches(text))
      if (_alcoholVesselsIn(m.namedGroup('what')!).firstOrNull case final v?)
        if (m.namedGroup('prep') != 'on' || v.endsWith('sheet'))
          (prep: m.namedGroup('prep')!, vessel: v, end: m.end),
  ];
  final into = [
    for (final d in dests)
      if (!d.vessel.startsWith('other|')) d,
  ];
  final coldMix =
      waiting &&
      trail.vessel != null &&
      _alcoholColdVessels.contains(trail.vessel!.split('|').last);
  final named = _alcoholVesselsIn(
    text,
  ).where((v) => !v.startsWith('other|'));
  final namedOther = _alcoholVesselsIn(
    text,
  ).where((v) => v.startsWith('other|'));
  final here = into.lastOrNull?.vessel ?? named.lastOrNull ?? at.here;
  // The pasta pot's boiling water, a tap's running water: another vessel
  // ("Add noodles to boiling water … Rinse under hot running water … for
  // 1 minute", 1087; closer1 D3).
  if (_alcoholOtherWater.hasMatch(text) &&
      !_alcoholOwnMention(text, trail.name)) {
    return (trail: trail, aside: true, here: 'other|pot');
  }
  // A premix whisked again in its bowl stays where it is ("Whisk mushroom
  // liquid mixture to recombine", 0542; closer1 D3).
  if (text.contains('recombine') && !text.contains(' add')) {
    return (trail: trail, aside: false, here: trail.vessel ?? here);
  }
  if ((_alcoholNamesOwn(text, trail) && _alcoholPutsIn.hasMatch(text)) ||
      // the line's food, just cooked, moved on ("Cook … about 1 minute
      // longer. Transfer to bowl.", 0532; closer1 D3)
      (!waiting && RegExp(r'^transfer (it |them )?to\b').hasMatch(text)) ||
      _alcoholPutsLiquid.hasMatch(text) ||
      _alcoholPoursIt.hasMatch(text) ||
      (coldMix &&
          _alcoholPutsMixture
              .allMatches(text)
              .any(
                (m) => switch (m.namedGroup('what')) {
                  final w? => trail.words.contains(w) || !seen.contains(w),
                  null => true,
                },
              ))) {
    // Food put into the line itself ("transfer to batter, tossing gently
    // to coat") joins it where it is.
    if (into.isEmpty &&
        RegExp(
          r'\b(to|into|in) (the )?([a-z]+ )?(batter|marinade|mixture|dough)\b'
          '(?!-)',
        ).hasMatch(text)) {
      return (
        trail: (
          name: trail.name,
          words: trail.words,
          vessel: trail.vessel,
          foods: {
            ...trail.foods,
            ..._alcoholFoodsIn(text, trail),
            // "dip 1 piece of fish in the batter" (0255; closer1 D3)
            ..._alcoholCoatedIn(text),
          },
          vocab: trail.vocab,
        ),
        aside: false,
        here: trail.vessel ?? here,
      );
    }
    // Into the frying oil after the last vessel named ("…drip back into
    // bowl; add to hot oil"): the pot on the heat, unnamed.
    final oil = RegExp(r'\b(to|into) (the )?(hot )?oil\b').allMatches(text);
    if (oil.isNotEmpty && into.every((m) => m.end < oil.last.start)) {
      return (
        trail: (
          name: trail.name,
          words: trail.words,
          vessel: null,
          foods: {...trail.foods, ..._alcoholFoodsIn(text, trail)},
          vocab: trail.vocab,
        ),
        aside: false,
        here: null,
      );
    }
    // A new vessel the line is put into goes with it ("Transfer the pork to
    // a clean bowl", closer1 D3).
    final to =
        dests.where((m) => m.prep == 'to' || m.prep == 'into').lastOrNull ??
        into.lastOrNull;
    final cold =
        trail.vessel != null &&
        _alcoholColdVessels.contains(trail.vessel!.split('|').last);
    // A new food added to the waiting mix ("Add pork and toss to coat",
    // 0540) leaves the line in its bowl; the line's own food added
    // ("Add chicken and spread into even layer", 0528) or the mix poured
    // or spread over a food goes with it, its vessel unknown (closer1 D3).
    final target =
        to?.vessel ??
        (here != null && here != trail.vessel
            ? here
            : cold &&
                  !(RegExp(r'^(add|toss|stir)\b').hasMatch(text) &&
                      (text.contains('coat') || !_alcoholNamesOwn(text, trail)))
            ? null
            : trail.vessel);
    final food = switch (to == null
        ? null
        : RegExp(
            r'^\s+with (the )?([a-z-]+ )?([a-z]+)',
          ).firstMatch(text.substring(to.end))?[3]) {
      // never "with the flour mixture" (0255)
      'mixture' => null,
      final w => w,
    };
    // The line moved by its own name into a bowl ("Transfer the wine to a
    // small bowl and set aside", 0448) leaves the foods and the group it
    // was with: they no longer name it (closer1 D3).
    final apart =
        _alcoholCold(target) &&
        _alcoholOwnMention(text, trail.name) &&
        RegExp(r'\bset aside\b|\breserv').hasMatch(text);
    return (
      trail: (
        name: trail.name,
        words: {...trail.words, ..._alcoholMixWords(text)},
        vessel: target,
        foods: apart
            ? {?food}
            : {
                ...trail.foods,
                ?food,
                ..._alcoholFoodsIn(text, trail),
                ..._alcoholCoatedIn(text),
              },
        vocab: trail.vocab,
      ),
      aside: false,
      here: target,
    );
  }
  if (into.every((m) => _alcoholIsTrailVessel(m.vessel, trail)) &&
      trail.vessel != null &&
      // A bowl named by another mix in it is that mix's ("transfer the
      // mushroom mixture to the bowl with the pureed chicken", 0448), the
      // line's own only when it names the line ("strainer over bowl
      // containing soy sauce mixture", 1178; closer1 D3).
      !_alcoholColdVessel
          .allMatches(text)
          .any((m) => !_alcoholNamesOwn(m.namedGroup('rest')!, trail)) &&
      // A bare "pan" in a side task is the side task's ("simmer, shaking
      // the pan occasionally", 0457; closer1 D3).
      !(at.aside && named.every((v) => v == 'pan')) &&
      named.any((v) => _alcoholSameVessel(v, trail.vessel!))) {
    // Food added to the line's vessel joins it ("Add potatoes to skillet").
    return (
      trail: _alcoholPutsIn.hasMatch(text)
          ? (
              name: trail.name,
              words: {...trail.words, ..._alcoholMixWords(text)},
              vessel: trail.vessel,
              foods: {...trail.foods, ..._alcoholFoodsIn(text, trail)},
              vocab: trail.vocab,
            )
          : trail,
      aside: false,
      here: trail.vessel,
    );
  }
  if (waiting &&
      trail.vessel != null &&
      _alcoholColdVessels.contains(trail.vessel!.split('|').last)) {
    // A food tossed in the waiting mix, no other vessel named, takes it on
    // ("Transfer meat to bowl with rice wine mixture … Toss chicken to
    // coat", 0513; closer1 D3).
    final coated = _alcoholCoatedIn(text);
    if (coated.isNotEmpty && named.isEmpty && namedOther.isEmpty) {
      return (
        trail: (
          name: trail.name,
          words: trail.words,
          vessel: trail.vessel,
          foods: {...trail.foods, ...coated},
          vocab: trail.vocab,
        ),
        aside: false,
        here: trail.vessel,
      );
    }
    return (trail: trail, aside: true, here: here);
  }
  if (_alcoholNamesOwn(text, trail)) {
    return (trail: trail, aside: false, here: here);
  }
  // Another vessel worked in — a now-empty, clean or second one ("Heat oil
  // in now-empty skillet", "Return again-empty skillet to medium heat"):
  // a side task until the line comes back (closer1 D3).
  if (namedOther.isNotEmpty &&
      !named.any((v) => _alcoholIsTrailVessel(v, trail))) {
    return (trail: trail, aside: true, here: namedOther.last);
  }
  final other = into
      .where((m) => !_alcoholIsTrailVessel(m.vessel, trail))
      .lastOrNull;
  // The line's dish set on a baking sheet goes into the oven with it
  // ("Unwrap the frozen ramekins and spread them out on a baking sheet",
  // 0939; "Place pie on rimmed baking sheet", 0194; closer1 D3).
  if (other != null &&
      other.prep == 'on' &&
      other.vessel.endsWith('sheet') &&
      const {'dish', 'ramekins'}.contains(trail.vessel?.split('|').last)) {
    return (trail: trail, aside: false, here: trail.vessel);
  }
  if (other != null) {
    return (trail: trail, aside: true, here: other.vessel);
  }
  // A line in a vessel not yet named: the first cooking vessel food is put
  // in is it, the food with it ("arrange meatballs in pot", 1093).
  if (trail.vessel == null &&
      // (closer1 D3: never a cold mix still waiting — "add amaretto mixture
      // and continue to beat … bring cream and corn syrup to simmer in
      // small saucepan" heats the ganache, 0906)
      !waiting &&
      into.isNotEmpty &&
      _alcoholPutsIn.hasMatch(text)) {
    return (
      trail: (
        name: trail.name,
        words: trail.words,
        vessel: into.last.vessel,
        foods: {...trail.foods, ..._alcoholFoodsIn(text, trail)},
        vocab: trail.vocab,
      ),
      aside: false,
      here: into.last.vessel,
    );
  }
  if (named.any(
    (v) =>
        !(at.aside && v == 'pan') &&
        // a cold mix waiting where it was poured is in a dish, never a
        // pot on a burner ("bring cream … to simmer in small saucepan",
        // 0906; closer1 D3)
        !(waiting &&
            trail.vessel == null &&
            _alcoholStovetop.contains(v.split('|').last)) &&
        _alcoholIsTrailVessel(v, trail),
  )) {
    return (trail: trail, aside: false, here: trail.vessel ?? here);
  }
  // A side task in a bowl ends at the first heat in no other vessel: "Whisk
  // cornstarch … in small bowl. Stir cornstarch slurry into soup, return to
  // simmer, and cook … 2 minutes" (0018, closer1 D3).
  if (at.aside &&
      _alcoholCold(at.here) &&
      !_alcoholCold(trail.vessel) &&
      named.isEmpty &&
      namedOther.isEmpty &&
      !_alcoholMicrowave.hasMatch(text) &&
      _alcoholHeats(text)) {
    return (trail: trail, aside: false, here: trail.vessel);
  }
  return (trail: trail, aside: at.aside, here: here);
}

/// The words a sentence that puts the line somewhere, or puts something
/// into its vessel, adds to what a later "<word> mixture" of it is named by
/// ("transfer ¾ cup cooking liquid, almonds … to blender. … Return almond
/// mixture to skillet", 0126; "Add reserved tomato juice … stir in reserved
/// tomato juice mixture", 0347; closer1 D3).
Set<String> _alcoholMixWords(String text) => {
  for (final w in RegExp('[a-z]+').allMatches(text))
    if (!_alcoholPutsIn.hasMatch(w[0]!)) ...{w[0]!, _alcoholSingular(w[0]!)},
}.difference(_alcoholCommonWords);

/// The ingredients [text] names (the trail's `vocab`), singular too.
Set<String> _alcoholFoodsIn(String text, _AlcoholTrail t) =>
    _alcoholHeadsIn(text, t.vocab);

/// The food [text] tosses or coats with the line, named however the step
/// names it ("gently toss the chunks with …", "toss until beef is evenly
/// coated", closer1 D3), singular too.
Set<String> _alcoholCoatedIn(String text) => {
  for (final m in _alcoholCoats.allMatches(text))
    if (m.namedGroup('a') ??
            m.namedGroup('b') ??
            m.namedGroup('c') ??
            m.namedGroup('d') ??
            m.namedGroup('e') ??
            m.namedGroup('f')
        case final w?)
      if (!_alcoholCommonWords.contains(w)) ...{w, _alcoholSingular(w)},
};

/// The vessels on a burner: a line put into one already hot starts its
/// timer there (a sheet, a dish or a pie plate waits for its bake).
const Set<String> _alcoholStovetop = {
  'pot',
  'skillet',
  'saucepan',
  'pan',
  'wok',
  'roasting pan',
};

final RegExp _alcoholCoats = RegExp(
  r'\b(toss|coat|marinat|rub)\w*\s+(the\s+|\d+\s+)*'
  r'((?!\w*ly\b|but\b)[a-z-]+\s+){0,2}?'
  r'(?<a>(?!\w*ly\b)[a-z]+)\s+(with|in|to coat)\b|'
  r'\buntil (the )?(?<b>[a-z]+) (is|are) (evenly |well |thoroughly )?coated\b|'
  r'\bdip\w*\s+(\d+\s+)?(pieces?\s+of\s+)?(the\s+)?(?<c>[a-z]+)\s+in\b|'
  r'\badd (the )?(?<d>[a-z]+) and toss\b|'
  r'\b(add|pour)\b[^,.;]*?\bto (the )?(?<e>[a-z]+), (stir|toss)\w* to coat\b|'
  r'\bto (the )?(?<f>[a-z]+) mixture\b',
);

/// Water another vessel holds.
final RegExp _alcoholOtherWater = RegExp(
  r'\b(to|into|in) (the )?(salted )?(boiling|simmering) water\b|'
  r'\bunder (hot |cold )?running water\b',
);

/// Nouns a food word before them only modifies.
const Set<String> _alcoholModified = {
  'liquid',
  'juice',
  'juices',
  'broth',
  'stock',
  'water',
  'sauce',
  'oil',
  'fat',
  'zest',
  'powder',
};

/// The foods of [vocab] [text] names as a noun phrase's head — "24 peach
/// wedges": wedges, never peach; "chicken, soy sauce": chicken (closer1
/// D3: "peach chunks" is not the "peach wedges" a line soaks).
Set<String> _alcoholHeadsIn(String text, Set<String> vocab) {
  final words = RegExp('[a-z]+').allMatches(text).toList();
  bool known(String w) =>
      vocab.contains(w) || vocab.contains(_alcoholSingular(w));
  return {
    for (final (i, w) in words.indexed)
      if (known(w[0]!) &&
          !(i + 1 < words.length &&
              RegExp(r'^[ -]+$').hasMatch(
                text.substring(w.end, words[i + 1].start),
              ) &&
              (known(words[i + 1][0]!) ||
                  // "mushroom liquid", "orange juice": a modifier (0542)
                  _alcoholModified.contains(words[i + 1][0]))))
        for (final f in {w[0]!, _alcoholSingular(w[0]!)})
          if (vocab.contains(f)) f,
  };
}

/// The first sentence after [at] that puts [start]'s liquid somewhere (its
/// name, a liquid word, a "<word> mixture" of its adding sentence, or its
/// vessel with something added) outside a side task, and the trail there —
/// or null: none before the dish is served.
({int at, _AlcoholTrail trail})? _alcoholFollows(
  List<_AlcoholSentence> s,
  int at,
  _AlcoholTrail start,
) {
  var place = (trail: start, aside: false, here: start.vessel);
  var step = s[at].step;
  for (var k = at + 1; k < s.length; k++) {
    final x = s[k];
    if (x.step != step) {
      place = (trail: place.trail, aside: false, here: place.trail.vessel);
      step = x.step;
    }
    if (x.empty) {
      continue;
    }
    final text = x.side ? x.text.replaceFirst(_alcoholSideClause, '') : x.text;
    if (x.side &&
        !(_alcoholPutsIn.hasMatch(text) &&
            (_alcoholNamesOwn(text, place.trail) ||
                _alcoholPutsLiquid.hasMatch(text)))) {
      continue;
    }
    final serves = _alcoholStops
        .allMatches(text)
        .where((m) => _alcoholStopKind(m) == 'final')
        .firstOrNull;
    final upTo = serves == null ? text : text.substring(0, serves.start);
    final before = place.trail;
    place = _alcoholContext(upTo, place, waiting: false);
    if (!place.aside &&
        _alcoholPutsIn.hasMatch(upTo) &&
        (_alcoholNamesOwn(upTo, before) ||
            _alcoholPutsLiquid.hasMatch(upTo) ||
            // (a batter or a dough leaves with its food: never followed
            // by its pan alone — the crepes' skillet takes the next sauce,
            // 0960; closer1 D3)
            (before.vessel != null &&
                !before.foods.any(_alcoholBatter.hasMatch) &&
                _alcoholVesselsIn(upTo).any(
                  (v) =>
                      v.split('|').last == before.vessel!.split('|').last &&
                      _alcoholSameVessel(v, before.vessel!),
                )))) {
      return (at: k, trail: place.trail);
    }
    if (serves != null) {
      return null;
    }
  }
  return null;
}

/// R5 (critic 8, bound objects): a line a mass rule owns — a marinade
/// scraped or lifted off, a liquid drained and discarded, a stock kept for
/// another use.
final RegExp _alcoholHandOff = RegExp(
  r'\b(scrape|wipe)s? (off )?(the |any )?(miso|marinade|excess|\w+ mixture)\b'
  r'[^.;]*\b(from|off)\b|\bdab\b[^.;]*\bmarinade|'
  r'\bdrain(ed)? (off )?and discard|\breserv(e|ing) (the )?(stock|liquid|'
  r'broth) for another use|\bdrain (the )?\w+ and pat\b[^.;]*\bdry|'
  r'\b(lift|remove) (the )?\w+ from (the )?marinade|'
  r'\b(letting|allowing) (any )?excess (marinade )?(to )?drip|'
  r'\bmeasure out\b[^.;]*\bmarinade',
);

/// The beer can a chicken stands on (Q20, Q-h): a mass ruling's.
final RegExp _alcoholBeerCan = RegExp(
  r'\bover (the )?(beer )?can\b|\bbeer can\b',
);

/// What a dough or a batter is cooked by (R4).
final RegExp _alcoholBakes = RegExp(r'\b(bak|fr[yi]|steam|broil|roast)\w*');

/// R4: a batter, dough or filling.
final RegExp _alcoholBatter = RegExp(r'\b(batter|dough|filling)\b');

final RegExp _alcoholStirs = RegExp(r'\b(stir|whisk|scrap)\w*');

final RegExp _alcoholOven = RegExp(r'\b(oven|bake|baked|roast)\b');

/// The liquids a line's pot is filled with ("add broth and Parmesan rind
/// … Return broth to simmer", 0403): the trail answers to them.
const Set<String> _alcoholLiquids = {'broth', 'stock', 'cream', 'milk'};

/// Words a premix's later sentence is not linked by (R6).
const Set<String> _alcoholCommonWords = {
  'the',
  'and',
  'with',
  'into',
  'to',
  'in',
  'of',
  'a',
  'an',
  'until',
  'add',
  'stir',
  'whisk',
  'combine',
  'together',
  'bowl',
  'small',
  'medium',
  'large',
  'set',
  'aside',
  'toss',
  'remaining',
  'teaspoon',
  'teaspoons',
  'tablespoon',
  'tablespoons',
  'cup',
  'cups',
  'salt',
  'pepper',
  'water',
  'oil',
  'sugar',
  'mix',
  'well',
  'for',
  'or',
  'at',
  'least',
  'up',
  'minutes',
  'minute',
  'hour',
  'hours',
  'let',
  'about',
  'over',
  'from',
  'then',
  'each',
  'all',
  'pot',
  'pan',
  'skillet',
  'saucepan',
  'dish',
  'sauce',
};

/// The ingredient groups that are a mix, read by their word when a line
/// shares its name with another (R1).
const Set<String> _alcoholMixGroups = {
  'sauce',
  'glaze',
  'marinade',
  'dressing',
  'syrup',
  'vinaigrette',
  'gravy',
};

/// [word] in the singular ("cherries": cherry, "shanks": shank).
String _alcoholSingular(String word) => word.endsWith('ies')
    ? '${word.substring(0, word.length - 3)}y'
    : word.endsWith('oes')
    ? word.substring(0, word.length - 2)
    : word.endsWith('s') && !word.endsWith('ss')
    ? word.substring(0, word.length - 1)
    : word;

/// The use of the line at the read sentence [at] (critic 6–9, R1–R6).
_AlcoholUse _alcoholUseAt(
  List<_AlcoholSentence> s,
  int at,
  String name,
  IngredientLine line,
  String? group,
  Set<String> ingredients,
) {
  final here = s[at];
  final offset =
      RegExp('\\b${RegExp.escape(name)}').firstMatch(here.text)?.start ?? 0;
  // (closer1 D3: never its side clause — "While the noodles boil, toss the
  // chicken …" names no noodles of the line's, 0528.)
  final clause = here.text.replaceFirst(
    RegExp(r'^(while|meanwhile|as|when)\b[^,]*,'),
    '',
  );
  final words = {
    for (final w in RegExp('[a-z]+').allMatches(clause)) ...{
      w[0]!,
      _alcoholSingular(w[0]!),
    },
  }.difference({..._alcoholCommonWords, name});
  // The foods the line coats or soaks ("stir gently until chicken is
  // evenly coated"): the adding sentence's words that name an ingredient,
  // and its group's one-word title ("SAUCE", "STUFFING"; never the last
  // word of "CHICKEN AND VEGETABLES").
  final foods = {
    ?group,
    ..._alcoholHeadsIn(clause, ingredients),
    ..._alcoholCoatedIn(clause),
  };
  final trail = (
    name: name,
    words: words,
    vessel: _alcoholVesselAt(s, at),
    foods: foods,
    vocab: ingredients,
  );
  // R5: a mass rule's line (critic 8).
  final can = RegExp(r'\bcans?\b').hasMatch(line.raw.toLowerCase());
  for (var i = at; i < s.length; i++) {
    final text = i == at ? here.text.substring(offset) : s[i].text;
    if (_alcoholHandOff.hasMatch(text) ||
        (can && _alcoholBeerCan.hasMatch(text))) {
      return _alcoholKept('handoff');
    }
  }
  // R2.1: a flame in the adding sentence or the next two of its step
  // (critic 2) — the minutes after it, if 15 or more, the lower row.
  for (var i = at; i < s.length && i <= at + 2 && s[i].step == here.step; i++) {
    if (!s[i].empty && _alcoholIgnites.hasMatch(s[i].text)) {
      return _alcoholTimed(
        i + 1 < s.length
            ? _alcoholRun(
                s,
                i + 1,
                0,
                trail,
                onHeat: true,
                follow: false,
              ).minutes
            : 0,
        flamed: true,
      );
    }
  }
  final before = here.text.substring(0, offset);
  final after = here.text.substring(offset);
  // Served with the dish ("serve with the sauce"): never heated (R2.3).
  if (RegExp(r'\bserve\b').hasMatch(before)) {
    return _alcoholKept('noheat');
  }
  // Decision 5: the line itself poured over or around, not stirred.
  final poured =
      RegExp(
            '\\bpour\\b[^.;]*\\b${RegExp.escape(name)}\\w*\\b[^.;]*\\b'
            r'(over|around|into)\b',
          ).hasMatch(here.text) &&
          !_alcoholStirs.hasMatch(here.text) ||
      // … or the mix just made poured round the food in the next sentence
      // ("Whisk … rice wine … in small bowl. Pour around fish.", 0268).
      (at + 1 < s.length &&
          s[at + 1].step == here.step &&
          _alcoholPoursIt.hasMatch(s[at + 1].text) &&
          !_alcoholStirs.hasMatch(s[at + 1].text));
  // R2.2: off the heat — a hot dish (Q-f), unless the vessel goes back on
  // the heat (critic 2: timed from the return); so too a dish strained or
  // poured off the heat in the adding sentence itself ("pour custard
  // through fine-mesh strainer into large bowl; stir in liquor", 0853).
  final offBefore = RegExp(
    r'\bstrain\b|\bthrough (a )?fine-mesh\b',
  ).hasMatch(before);
  if (offBefore && (_alcoholHeats(before) || _alcoholCarried(s, at))) {
    return _alcoholOffHeat;
  }
  if (_alcoholOffHeatWords.hasMatch(before) || before.startsWith('remove')) {
    if (!_alcoholReturnsAfter(s, at, offset) && !_alcoholHeats(after)) {
      // The dish taken on to its next heat (closer1 D3: "Off the heat,
      // whisk in … sherry. … Turn the mixture into a … gratin dish … bake
      // … 13 to 15 minutes", 0303; else Q-f's hot dish, 5002).
      final later = _alcoholRun(s, at, offset, trail, onHeat: false);
      return later.heated
          ? _alcoholHeated(s, at, later, poured: poured)
          : _alcoholOffHeat;
    }
    return _alcoholHeated(
      s,
      at,
      _alcoholRun(s, at, offset, trail, onHeat: true),
      poured: poured,
    );
  }
  // (closer1 D3: or the vessel the line is in is a bowl — "Add 1¼ cups of
  // the beer to the flour mixture in the mixing bowl. Add the remaining ¼
  // cup beer as needed", 0255: never carried by the oil heating beside it.)
  final intoCold =
      _alcoholVesselsIn(
        here.text,
      ).any((v) => _alcoholColdVessels.contains(v.split('|').last)) ||
      _alcoholCold(trail.vessel);
  // A side clause ("While the noodles boil, toss the chicken …") heats
  // another pot.
  final own = here.text.replaceFirst(
    RegExp(r'^(while|meanwhile|as|when)\b[^,]*,'),
    '',
  );
  if (_alcoholHeats(own) ||
      (!intoCold &&
          !here.text.contains('recombine') &&
          _alcoholCarried(s, at))) {
    return _alcoholHeated(
      s,
      at,
      _alcoholRun(s, at, offset, trail, onHeat: true),
      poured: poured,
    );
  }
  // Q-f: stirred into a sauce, soup or custard just cooked, nothing cooling
  // it since and nothing heating it after (the run below reads none) — a
  // hot dish, 5002.
  final intoHot = RegExp(
    r'\b(in)?to (the )?(hot |warm )?(sauce|soup|stew|custard|gravy|syrup)\b',
  ).hasMatch(after);
  // R4: a batter, dough or filling (named in the adding sentence's step) —
  // followed as the line, timed from its first bake or fry; none (a dough
  // baked elsewhere): 100.
  final batter = {
    for (var i = at; i < s.length && s[i].step == here.step; i++)
      for (final m in _alcoholBatter.allMatches(s[i].text)) m[0]!,
    if (at > 0 &&
        s[at - 1].step == here.step &&
        RegExp(r'\b(flour|cornstarch)\b').hasMatch(s[at - 1].text) &&
        !_alcoholHeats(s[at - 1].text))
      'batter',
  };
  if (batter.isNotEmpty) {
    final read = _alcoholRun(
      s,
      at,
      offset,
      (
        name: name,
        words: trail.words,
        vessel: _alcoholVesselAt(s, at, near: true),
        foods: {...foods, ...batter},
        vocab: ingredients,
      ),
      onHeat: false,
    );
    return read.heated
        ? _alcoholHeated(s, at, read, poured: false)
        : _alcoholKept('fallback:untimed');
  }
  // R2.3 / R6 (critic 7): a cold mix — in a bowl or the pot — timed from
  // its first heat in the line's vessel; none: no heat (100).
  // A mix whisked together and set aside with no vessel named is in a bowl
  // ("Whisk together reserved mushroom liquid, … sherry, and cornstarch;
  // set aside", 0542; closer1 D3).
  final read = _alcoholRun(
    s,
    at,
    offset,
    (
      name: name,
      words: trail.words,
      vessel:
          _alcoholVesselAt(s, at, near: true) ??
          (RegExp(
                r'\btogether\b|\bset aside\b',
              ).hasMatch(here.text)
              ? 'bowl'
              : null),
      foods: foods,
      vocab: ingredients,
    ),
    onHeat: false,
  );
  return read.heated
      ? _alcoholHeated(s, at, read, poured: poured)
      : intoHot && _alcoholHotBefore(s, at)
      ? _alcoholOffHeat
      : _alcoholKept('noheat');
}

/// Whether the dish is still hot at sentence [at]: the nearest earlier
/// read sentence that heats or cools (of its step or the two before) heats.
bool _alcoholHotBefore(List<_AlcoholSentence> s, int at) {
  for (var i = at - 1; i >= 0 && s[i].step >= s[at].step - 2; i--) {
    final text = s[i].text;
    if (s[i].empty || s[i].side || (s[i].sideStep && s[i].step != s[at].step)) {
      continue;
    }
    if (_alcoholStops
        .allMatches(text)
        .any((m) => _alcoholStopKind(m) == 'wait')) {
      return false;
    }
    if (_alcoholHeats(text)) {
      return true;
    }
  }
  return false;
}

/// A use heated from sentence [at]: poured over and baked, not stirred
/// (85, its oven minutes); the band of the run's minutes; no minutes
/// printed — heated, untimed (85, critic 9) when a heat ran until a
/// doneness or no stop came within two sentences of the heat's start,
/// else boil-off (into the hot liquid and off or served at once).
_AlcoholUse _alcoholHeated(
  List<_AlcoholSentence> s,
  int at,
  _AlcoholRunRead read, {
  required bool poured,
}) {
  if (read.sealed && read.minutes == 0) {
    return _alcoholKept('fallback:sealed');
  }
  if (poured && (read.ovenMinutes > 0 || _alcoholOven.hasMatch(s[at].text))) {
    final baked = read.ovenMinutes.floor();
    return (
      kept: 85,
      code: '5002',
      rule: 'not_stirred',
      minutes: baked,
      words: 'poured over and baked $baked min keeps 85 %',
      part: 'poured over and baked $baked min keeps 85 %',
    );
  }
  if (read.minutes > 0) {
    return _alcoholTimed(read.minutes);
  }
  return read.closes && !read.until ? _alcoholBoilOff : _alcoholUntimed;
}

/// A volume printed beside a name: "¼ cup of the brandy", "1 cup more
/// wine", "the remaining 1 tablespoon cognac", "the remaining wine" — read
/// at the end of the text before the name.
final RegExp _alcoholRemainingBefore = RegExp(
  r'\b(remaining|rest of( the)?)\s+'
  '(?<amount>(\\d+\\s*[$vulgarFractionChars]?|[$vulgarFractionChars])'
  r'\s*(cups?|tablespoons?|teaspoons?|ounces?)\s+)?'
  r'(of (the )?)?([a-z-]+ ){0,2}$',
);

final RegExp _alcoholAmountBefore = RegExp(
  '(?<amount>(\\d+\\s*[$vulgarFractionChars]?|[$vulgarFractionChars])'
  r'\s*(cups?|tablespoons?|teaspoons?|ounces?))\s+'
  r'(of (the )?)?(more )?([a-z-]+ ){0,2}$',
);

/// The part of a line a sentence names: its printed amount and whether it
/// is "the remaining" one — or null (no amount, not the rest, or the
/// "extra" a line keeps outside its amount: "plus extra for seasoning").
({String? amount, bool rest})? _alcoholPartIn(String text, String name) {
  for (final m in RegExp('\\b${RegExp.escape(name)}').allMatches(text)) {
    final before = text.substring(max(0, m.start - 60), m.start);
    if (RegExp(r'\bextra ([a-z-]+ ){0,2}$').hasMatch(before)) {
      continue;
    }
    if (_alcoholRemainingBefore.firstMatch(before) case final r?) {
      return (amount: r.namedGroup('amount')?.trim(), rest: true);
    }
    if (_alcoholAmountBefore.firstMatch(before) case final a?) {
      return (amount: a.namedGroup('amount'), rest: false);
    }
  }
  return null;
}

/// [amount]'s volume in mL ("¼ cup", "1 tablespoon").
double? _alcoholMl(String amount) {
  final m = RegExp(
    '^(\\d+\\s*[$vulgarFractionChars]?|[$vulgarFractionChars])'
    r'\s*(cup|tablespoon|teaspoon|ounce)',
  ).firstMatch(amount);
  final n = m == null ? null : parseQuantity(m[1]!.replaceAll(' ', ''));
  if (n == null) {
    return null;
  }
  return n *
      switch (m![2]) {
        'cup' => 236.588,
        'tablespoon' => 14.7868,
        'teaspoon' => 4.92892,
        _ => 29.5735,
      };
}

/// [line]'s volume in mL: its amounts (and a same-food plus part), else a
/// bottle's or a can's printed size ("1 (750-ml) bottle", "2 (12-ounce)
/// bottles").
double? _alcoholLineMl(IngredientLine line) {
  final own = volumeMlOf(line.amounts);
  if (own != null) {
    final plus = plusPartOf(line.raw);
    final more = plus != null && plus.sameFood
        ? volumeMlOf([plus.amount])
        : null;
    return own + (more ?? 0);
  }
  final size = RegExp(
    r'^(\d+) \((\d+)-(ml|milliliter|ounce)\)',
  ).firstMatch(line.raw.toLowerCase());
  if (size == null) {
    return null;
  }
  return int.parse(size[1]!) *
      int.parse(size[2]!) *
      (size[3] == 'ounce' ? 29.5735 : 1.0);
}

AlcoholReading _alcoholRead(Recipe recipe, int position, int fdcId) {
  final s = _alcoholSentencesOf(recipe);
  if (s.isEmpty) {
    return (kept: 100, code: '', rule: 'fallback:no_steps', flag: null);
  }
  final lines = nutritionLines(recipe);
  final line = lines[position];
  final heads = _headsOf(recipe);
  List<String> alternatives(IngredientLine l) => [
    for (final alt in normalizeItem(lineItemOf(l)).split(' or '))
      if (headNounOf(alt.trim()) case final head? when head != 'water') head,
  ];
  // A line's group word: its ingredient group title's last word ("ORANGE
  // SAUCE": sauce).
  String? groupOf(int p) {
    var n = 0;
    for (final g in recipe.ingredients) {
      if (p < n + g.items.length) {
        return RegExp(
          '[a-z]+',
        ).allMatches(g.group?.toLowerCase() ?? '').lastOrNull?[0];
      }
      n += g.items.length;
    }
    return null;
  }

  final group = groupOf(position);
  // A one-word group title, the only one a food or a step can name as the
  // line's (closer1 D3).
  final groupWord = () {
    var n = 0;
    for (final g in recipe.ingredients) {
      if (position < n + g.items.length) {
        final words = RegExp('[a-z]+').allMatches(g.group?.toLowerCase() ?? '');
        return words.length == 1 ? words.single[0] : null;
      }
      n += g.items.length;
    }
    return null;
  }();
  // R1 (critic 6): the head; never named — an alternative's head, the
  // record's class word, the group's title.
  final flat = {for (final (i, x) in s.indexed) (x.step, x.index): i};
  String? name;
  var mentions = const <int>[];
  final groupMentions = group == null
      ? const <int>[]
      : [
          for (final (i, x) in s.indexed)
            if (!x.side &&
                RegExp(
                  '(?<!soy |fish |hot |oyster |hoisin |worcestershire |chili '
                  '|tomato |barbecue |dipping |tartar )'
                  '\\b${RegExp.escape(group)}\\b',
                ).hasMatch(x.text))
              i,
        ];
  for (final candidate in [
    if (heads[position] case final head? when head != 'water') head,
    ...alternatives(line),
    ?alcoholRecords[fdcId],
    'liquor',
    ?group,
  ]) {
    final at = candidate == group
        ? groupMentions
        : [for (final m in _naming(recipe, candidate)) ?flat[m]];
    if (at.isNotEmpty) {
      name = candidate;
      mentions = at;
      break;
    }
  }
  if (name == null) {
    return (kept: 100, code: '', rule: 'fallback:unnamed', flag: null);
  }
  // The k-th line of a name reads from its k-th use (critic 10) — a
  // "<name> mixture" names a use already made; a line past the uses reads
  // the last.
  // (closer1 D3) Lines of one name count apart by whether their group is a
  // mix: a mix group's line ("SAUCE: 1 tablespoon dry sherry") beside one
  // outside a mix (the chicken's sherry) reads its group's word, the other
  // the name's uses (0528, 0529).
  bool sharesName(int p) =>
      heads[p] == name || alternatives(lines[p]).contains(name);
  bool mixLine(int p) => _alcoholMixGroups.contains(groupOf(p));
  final mixed = mixLine(position);
  final uses0 = <int>[
    for (final m in mentions)
      if (!RegExp(
        '\\b${RegExp.escape(name)}( [a-z]+)? mixture\\b',
      ).hasMatch(s[m].text))
        m,
  ];
  // Only when the unmixed lines take every use of the name (the steps
  // never name the sauce's sherry: 0528, 0529; the crepes' cognac they do).
  final unmixed = [
    for (var p = 0; p < lines.length; p++)
      if (sharesName(p) && !mixLine(p)) p,
  ];
  final groupRead =
      unmixed.isNotEmpty &&
      unmixed.length >= uses0.length &&
      [
        for (var p = 0; p < lines.length; p++)
          if (sharesName(p) && mixLine(p)) p,
      ].isNotEmpty;
  var k = 0;
  for (var p = 0; p < position; p++) {
    if (sharesName(p) && !(groupRead && mixLine(p))) {
      k++;
    }
  }
  // A line past the uses whose group is a mix ("SAUCE") reads its group's
  // word: "Whisk sauce to recombine" (0513).
  if (group != null && mixed && (groupRead || (k > 0 && k >= uses0.length))) {
    final own = RegExp(
      '(?<!soy |fish |hot |oyster |hoisin |worcestershire |chili |tomato '
      '|barbecue |dipping |tartar )\\b${RegExp.escape(group)}\\b',
    );
    final at = s.indexWhere((x) => !x.side && own.hasMatch(x.text));
    if (at >= 0) {
      name = group;
      mentions = [at];
      uses0
        ..clear()
        ..add(at);
      k = 0;
    }
  }
  // Two lines of one name (critic 10): a use whose sentence names the
  // OTHER line's group word is the other line's ("whisk … rice wine … for
  // the sauce" is the SAUCE line's, not the PORK line's).
  final sharedName = [
    for (var p = 0; p < lines.length; p++)
      if (p != position &&
          (heads[p] == name || alternatives(lines[p]).contains(name)))
        p,
  ].isNotEmpty;
  final otherGroups = {
    for (var p = 0; p < lines.length; p++)
      if (p != position &&
          (heads[p] == name || alternatives(lines[p]).contains(name)))
        ?groupOf(p),
  }.difference({?group, name});
  final mine = [
    for (final m in uses0)
      if (!otherGroups.any(
        (g) => RegExp(
          '(?<!soy |fish |hot |oyster |hoisin )\\b$g',
        ).hasMatch(s[m].text),
      ))
        m,
  ];
  final first = mine.isNotEmpty && mine.length < uses0.length
      ? mine.first
      : k == 0 && mentions.length == 1
      ? mentions.single
      : uses0.isEmpty
      ? mentions.first
      : uses0[min(k, uses0.length - 1)];
  // The line's parts (a "divided" or "plus" line, P18–P21): its first use,
  // then each later mention printing a volume or "remaining", until the
  // parts fill the line.
  final lineMl = _alcoholLineMl(line);
  final parts = <({int at, double? ml, String words})>[];
  var used = 0.0;
  for (final at in mentions.where((m) => m >= first)) {
    final part = _alcoholPartIn(s[at].text, name);
    if (parts.isNotEmpty && part == null) {
      continue;
    }
    if (parts.isNotEmpty && lineMl != null && used >= lineMl - 0.5) {
      break;
    }
    final ml = part?.amount == null ? null : _alcoholMl(part!.amount!);
    // A later amount the line cannot hold is another line's ("3 tablespoons
    // of the cognac" beside the batter's 2 tablespoons, 0960); so is every
    // later amount when the first use prints none and another line shares
    // the name.
    if (parts.isNotEmpty &&
        ((ml != null && lineMl != null && ml > lineMl - used + 0.5) ||
            (parts.first.ml == null && otherGroups.isNotEmpty) ||
            (parts.first.ml == null && sharedName))) {
      continue;
    }
    parts.add((
      at: at,
      ml: (part?.rest ?? false) && part?.amount == null ? null : ml,
      words: part?.amount ?? 'the rest',
    ));
    used += ml ?? 0;
    if (part?.rest ?? false) {
      break;
    }
  }
  // The foods a line can coat or soak (closer1 D3): the words of another
  // line weighed or counted — never a volume of a seasoning or a liquid
  // ("1 teaspoon garlic", "¼ cup orange juice") — that only that line's
  // item prints ("porcini mushrooms" and "cremini mushrooms": two foods,
  // so "mushrooms" names neither).
  Set<String> wordsOf(IngredientLine l) => {
    for (final w in RegExp('[a-z]+').allMatches(normalizeItem(lineItemOf(l))))
      if (w[0]!.length > 3) ...{w[0]!, _alcoholSingular(w[0]!)},
  };
  final wordLines = <String, int>{};
  for (final l in lines) {
    for (final w in wordsOf(l)) {
      wordLines[w] = (wordLines[w] ?? 0) + 1;
    }
  }
  final ingredients = <String>{
    for (final (p, l) in lines.indexed)
      if (p != position && volumeMlOf(l.amounts) == null)
        for (final w in wordsOf(l))
          if (wordLines[w] == 1) w,
    for (final (p, _) in lines.indexed)
      if (p != position && _alcoholLiquids.contains(heads[p])) heads[p]!,
  }.difference(_alcoholCommonWords);
  // A part added by "Repeat with … the remaining 2 tablespoons wine" is
  // used as the part before it was (0540; closer1 D3).
  final uses = <_AlcoholUse>[];
  for (final (i, p) in parts.indexed) {
    uses.add(
      i > 0 && s[p.at].text.startsWith('repeat')
          ? uses[i - 1]
          : _alcoholUseAt(s, p.at, name, line, groupWord, ingredients),
    );
  }
  // Split, weighted by the printed volumes (decision 7); a part no volume
  // reads: the rest of the line, else the HIGHER retention of the uses.
  final known = parts
      .map((p) => p.ml)
      .nonNulls
      .fold<double>(0, (a, b) => a + b);
  final unread = parts.where((p) => p.ml == null).length;
  final weights = [
    for (final p in parts)
      p.ml ??
          (unread == 1 && lineMl != null && lineMl > known
              ? lineMl - known
              : null),
  ];
  final kept = uses.length == 1
      ? uses.single.kept
      : weights.contains(null)
      ? uses.map((u) => u.kept).reduce(max)
      : [
              for (final (i, u) in uses.indexed) u.kept * weights[i]!,
            ].reduce((a, b) => a + b) /
            weights.fold(0.0, (a, b) => a + b!);
  final codes = {for (final u in uses) u.code};
  // v65 (M66, the owner's Q8 (b)): a batter fried in oil keeps 5002's 85 %
  // (the standing Q-a ruling) — R6 prints no frying row; the flag says so.
  final fried =
      codes.length == 1 &&
          codes.single == '5002' &&
          _batterInBowl(recipe).contains(position)
      ? ' (USDA prints no row for a batter fried in oil)'
      : '';
  final words = {for (final u in uses) u.words};
  return (
    kept: kept,
    code: codes.length == 1
        ? codes.single
        : uses.map((u) => u.code.isEmpty ? 'none' : u.code).join('+'),
    rule: uses.length == 1 ? uses.single.rule : 'split',
    flag: kept >= 100
        ? null
        : words.length == 1
        ? 'approximate (USDA retention: alcohol ${words.single}$fried)'
        : 'approximate (USDA retention: ${[
            for (final (i, u) in uses.indexed) '${parts[i].words} ${u.part}',
          ].join('; ')}$fried)',
  );
}

/// Rule B1 (v41, R2): rendered bacon. The record bought, SR 168277 "Pork,
/// cured, bacon, unprepared".
const int rawBaconFdcId = 168277;

/// SR 168322 "Pork, cured, bacon, pre-sliced, cooked, pan-fried" — the
/// cooked part (a cached search hit, "thin-sliced cooked deli ham").
const int cookedBaconFdcId = 168322;

/// SR 172345 "Animal fat, bacon grease" — the fat kept in the pan.
const int baconGreaseFdcId = 172345;

/// Cooked bacon per gram raw: USDA Agriculture Handbook 102 (rev. 1975),
/// item 1981 "bacon, sliced, all methods" → cooked 33 % (18–43) — v51 (M49
/// Q4 b, the owner's 2026-10-07 standing authorization) re-rules Y11's
/// 0.403 (2026-10-06, the protein balance 13.66 / 33.9 g of 168322: the
/// two records are different samples; 0.33 counts 11.19 g of 168277's
/// 13.66 g protein, 18 % of the balance given up, and AH-102's own range
/// holds 0.403).
const double baconCookedYield = 0.33;

/// Fat rendered per gram raw, by the same fat balance: 168277's fat less
/// the cooked part's, 0.3713 − 0.33 × 0.351 = 0.25547.
const double baconRenderedPerGram = 0.2555;

/// The flag a rendered row carries ([compositeFlagOf]).
const String baconYieldFlag =
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → '
    'cooked 33 % (18–43))';

/// 172345's own portion, "tsp" 4.3 g over 4.92892 mL.
const double baconGreaseGramsPerMl = 0.8724;

/// B1's (a): the meat lifted out of its fat.
final RegExp _baconOut = RegExp(
  'slotted spoon|transfer (the )?(remaining )?(bacon|pancetta)|'
  'paper towel.lined plate|transfer (the )?(bacon|pancetta) to (a )?bowl|'
  'leaving (the )?(bacon|pancetta) in',
);

/// A number B1's fat terms read: digits, a vulgar fraction, a word.
final String _baconN = '[\\d$vulgarFractionChars]+|one|two|three|four';

/// B1's (b): the fat poured off down to a stated amount ...
final RegExp _baconKeep = RegExp(
  r'(?:pour off|pour|discard|remove and discard)\s+(?:all\s+)?but\s+'
  '(?:about\\s+)?($_baconN)\\s+(tablespoons?|teaspoons?|cups?)',
);

/// ... or measured out and the rest discarded ...
final RegExp _baconReserve = RegExp(
  'measure out and reserve\\s+($_baconN)\\s+(cups?|tablespoons?)\\s+fat;'
  r'\s*discard',
);

/// ... or a range kept and the extra discarded (its upper bound).
final RegExp _baconExtra = RegExp(
  '($_baconN)\\s+to\\s+($_baconN)\\s+(cups?)\\s+fat;\\s*discard any extra',
);

/// The poured fat kept and reused (within 60 characters of the pour-off):
/// no rendering is lost.
final RegExp _baconVeto = RegExp(
  'into a (small )?bowl|set aside|pour off and reserve|reserve remaining fat',
);

/// A kept part as written — a [_baconN] quantity and a unit word — parsed.
Amount _keptAmount(String quantity, String unit) => Amount(
  measure: Measure.volume,
  quantity: _nWords[quantity] ?? quantity,
  unit: unit.replaceFirst(RegExp(r's$'), ''),
);

/// [_baconN]'s words as digits.
const Map<String, String> _nWords = {
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
};

/// The mL of fat [recipe]'s steps keep in the pan, or null when no ONE step
/// lifts the meat out AND cuts the fat to a stated amount (B1's signal).
double? _baconKeptMl(Recipe recipe) => _baconKept(recipe)?.ml;

/// [_baconKeptMl]'s reading with where it stands — the step, the sentence
/// of the kept amount, the amount as written ("2 tablespoons", a range's
/// "⅓ cup") — for the oil sharing the pan ([_baconPanOf], v51). Once per
/// recipe: it reads the steps alone (RULE C, v59 verifier 2 D1: read per
/// bacon row by [withRenderedBacon] on every compute, 5.3 s of a 400-line
/// compute at the caps).
({double ml, int step, int sentence, String text})? _baconKept(
  Recipe recipe,
) => _stepIndexOf(recipe).memo(#baconKept, () {
  ({double ml, int step, int sentence, String text})? at(
    int step,
    String text,
    Match m,
    String quantity,
    String unit,
  ) {
    final ml = volumeMlOf([_keptAmount(quantity, unit)]);
    return ml == null
        ? null
        : (
            ml: ml,
            step: step,
            sentence:
                text.substring(0, m.start).split(_sentenceBreak).length - 1,
            text: '$quantity $unit',
          );
  }

  for (final (i, step) in recipe.steps.indexed) {
    final text = step.text.toLowerCase();
    if (!_baconOut.hasMatch(text)) {
      continue;
    }
    if (_baconKeep.firstMatch(text) case final keep?) {
      final after = text.substring(
        keep.start,
        min(text.length, keep.end + 60),
      );
      if (_baconVeto.hasMatch(after)) {
        continue;
      }
      return at(i, text, keep, keep[1]!, keep[2]!);
    }
    if (_baconReserve.firstMatch(text) case final reserve?) {
      return at(i, text, reserve, reserve[1]!, reserve[2]!);
    }
    if (_baconExtra.firstMatch(text) case final extra?) {
      return at(i, text, extra, extra[2]!, extra[3]!);
    }
  }
  return null;
});

/// v59 (M60 P7b, the owner's Q15 (a); pre-Q18): bacon B1 leaves unrendered
/// ([_baconKept] null) that cooks ON a food — a step sentence arranges,
/// lays, drapes or shingles the bacon over something other than a towel,
/// plate, sheet, rack or pan ("arrange the bacon slices, crosswise, over
/// the loaf", 0306), or wraps a food with or in bacon ("wrap with 1 slice
/// bacon", 0652), and a LATER sentence bakes, roasts, grills or broils:
/// the fat drips off the food, so rule B1 keeps none ([withRenderedBacon]).
/// Once per recipe: it reads the steps alone (RULE C, v59 verifier 2 D1:
/// read per bacon row on every compute and per drip row on every matches
/// GET).
bool _baconDrips(Recipe recipe) => _stepIndexOf(recipe).memo(#baconDrips, () {
  if (_baconKept(recipe) != null) {
    return false;
  }
  final sentences = _stepIndexOf(recipe).allSentences;
  for (final (i, sentence) in sentences.indexed) {
    final over = _baconLaidOver(sentence);
    if ((over != null && !_baconOverNoFood.hasMatch(over)) ||
        _baconWraps(sentence)) {
      return sentences.skip(i + 1).any(_baconCooksOn.hasMatch);
    }
  }
  return false;
});

/// P7b's lay ([_baconDrips]): what a laid bacon lies over — a lay verb,
/// then "bacon" with no period between, then "over" with no period or
/// semicolon after the bacon; the object the first such "over" takes, up to
/// a comma, period or semicolon — what
/// `\b(?:arrang…|lay…|drap…|shingl…)\b[^.]*?\bbacon\b[^.;]*?\bover\s+([^,.;]+)`
/// captured on its first match. One pass over the sentence's tokens (RULE
/// C, v59 verifier 2 D1: that regex's two lazy gaps re-read the sentence
/// from each verb and each bacon, 7 s a compute at the caps); the first
/// "over" a laid bacon reaches is that match's (its leftmost verb reaches
/// every bacon a later verb of the same period-free run reaches).
String? _baconLaidOver(String sentence) {
  var laid = false;
  var bacon = false;
  for (final m in _baconLayToken.allMatches(sentence)) {
    switch (m[0]!) {
      case '.':
        laid = bacon = false;
      case ';':
        bacon = false;
      case 'bacon':
        bacon = bacon || laid;
      case 'over':
        if (bacon) {
          return _baconOverObject.matchAsPrefix(sentence, m.start)![1];
        }
      default:
        laid = true;
    }
  }
  return null;
}

/// [_baconLaidOver]'s tokens: a period or semicolon, a lay verb, "bacon",
/// or an "over" with an object.
final RegExp _baconLayToken = RegExp(
  r'[.;]|\b(?:(?:arrang(?:e[sd]?|ing)|lay(?:s|ing)?|drap(?:e[sd]?|ing)|'
  r'shingl(?:e[sd]?|ing)|bacon)\b|over(?=\s+[^,.;]))',
);

/// The object of [_baconLaidOver]'s "over".
final RegExp _baconOverObject = RegExp(r'over\s+([^,.;]+)');

/// P7b's lay over no food: a towel, plate, sheet, rack or pan.
final RegExp _baconOverNoFood = RegExp(
  r'\b(?:towels?|plates?|sheets?|racks?|pans?)\b',
);

/// P7b's wrap ([_baconDrips]): a food wrapped with or in bacon — a "wrap"
/// word, then, with no period between, "with" or "in" and at most three
/// words before "bacon": what
/// `\bwrap(?:s|ped|ping)?\b[^.]*?\b(?:with|in)\s+(?:[\w-]+\s+){0,3}?bacon\b`
/// matched. One pass over the sentence's tokens (RULE C, v59 verifier 2
/// D1: the lazy gap re-read the sentence from each "wrap"), each "with" or
/// "in" after a wrap read at most four words on.
bool _baconWraps(String sentence) {
  var wrap = false;
  for (final m in _baconWrapToken.allMatches(sentence)) {
    if (m[0] == '.') {
      wrap = false;
    } else if (m[0]!.startsWith('wrap')) {
      wrap = true;
    } else if (wrap &&
        _baconWrapTail.matchAsPrefix(sentence, m.start) != null) {
      return true;
    }
  }
  return false;
}

/// [_baconWraps]' tokens: a period, a "wrap" word, a "with" or "in".
final RegExp _baconWrapToken = RegExp(
  r'\.|\b(?:wrap(?:s|ped|ping)?\b|(?:with|in)(?=\s))',
);

/// What [_baconWraps]' "with" or "in" wraps in: bacon, within three words.
final RegExp _baconWrapTail = RegExp(
  r'(?:with|in)\s+(?:[\w-]+\s+){0,3}?bacon\b',
);

/// [_baconLaidOver] and [_baconWraps] on [sentence] (RULE C pins).
@visibleForTesting
(String?, bool) baconLayWrapForTest(String sentence) =>
    (_baconLaidOver(sentence), _baconWraps(sentence));

/// P7b's later cooking: baked, roasted, grilled or broiled.
final RegExp _baconCooksOn = RegExp(
  r'\b(?:bak(?:e[sd]?|ing)|roast(?:s|ed|ing)?|grill(?:s|ed|ing)?|'
  r'broil(?:s|ed|ing)?)\b',
);

/// P7b's flag: [baconYieldFlag] with the drip ([_baconDrips]).
const String baconDripFlag =
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → '
    'cooked 33 % (18–43); the fat drips off the food)';

/// A line rule B1 renders, by its words: bacon or pancetta, never its fat
/// nor Canadian bacon ([_baconPanOf]).
final RegExp _renderedBacon = RegExp(
  r'^(?!.*\b(?:fat|grease|drippings|canadian)\b).*\b(?:bacon|pancetta)\b',
);

/// Rule B1's pan shared with an oil ([_baconPanOf]).
typedef _BaconPan = ({
  IngredientLine bacon,
  IngredientLine oil,
  Amount? part,
  double ml,
  String text,
});

/// v51 (M49 Q19, P4 §4): rule B1's pan ([_baconKept]) when an oil browns in
/// it before the pour-off ([_panOilAt]: "heat the oil … Add the pancetta
/// … Pour off all but 2 tablespoons of fat", 0332; "Add oil and cook" a
/// step before, Salade Lyonnaise; "Heat pancetta and oil … ¼ to ⅓ cup fat;
/// discard any extra", gricia): the one undivided bacon line, the oil line
/// and its part in the pan, the kept amount (mL, as written) — or null.
/// Once per recipe.
_BaconPan? _baconPanOf(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#baconPan, () {
      final kept = _baconKept(recipe);
      final pan = kept == null
          ? null
          : _panOilAt(recipe, (kept.step, kept.sentence));
      if (pan == null) {
        return null;
      }
      final bacons = [
        for (final l in nutritionLines(recipe))
          if (l.amounts.isNotEmpty &&
              !l.raw.toLowerCase().contains('divided') &&
              _renderedBacon.hasMatch(normalizeItem(lineItemOf(l))))
            l,
      ];
      return bacons.length != 1
          ? null
          : (
              bacon: bacons.single,
              oil: pan.line,
              part: pan.part,
              ml: kept!.ml,
              text: kept.text,
            );
    });

/// The grams of the oil in [pan] (its part in the pan, else the line), with
/// no food — the one figure both rows of the split read.
double? _panOilGrams(_BaconPan pan) {
  final item = normalizeItem(lineItemOf(pan.oil));
  return pan.part == null
      ? _freeGrams(pan.oil, item)
      : resolveGrams(
          amounts: [pan.part!],
          food: null,
          normalizedItem: item,
        )?.grams;
}

/// The oil's share of [pan]'s kept fat: kept × O / (R + O), the kept fat
/// at most R + O (R the bacon line's rendered fat, O [_panOilGrams]).
double? _baconPanOilShare(_BaconPan pan) {
  final raw = _freeGrams(pan.bacon, normalizeItem(lineItemOf(pan.bacon)));
  final oil = _panOilGrams(pan);
  if (raw == null || raw <= 0 || oil == null) {
    return null;
  }
  final rendered = raw * baconRenderedPerGram;
  final pooled = min(pan.ml * baconGreaseGramsPerMl, rendered + oil);
  return pooled * oil / (rendered + oil);
}

/// [row] as rule B1 counts it (v41, R2): an `auto` or `confirmed` row on
/// [rawBaconFdcId], unheld, weighed at [raw] grams (> 0; default: its own
/// grams) on a line not "divided" — never grams a person typed (D12, F2) —
/// whose [recipe] renders and drains the bacon ([_baconKeptMl]) is ONE row
/// on the record bought with two parts: the cooked bacon (raw ×
/// [baconCookedYield] on [cookedBaconFdcId]) and the fat kept in the pan
/// (the stated amount, at most what renders, on [baconGreaseFdcId]; with
/// an oil in the pan, the bacon's R / (R + O) share of it, v51); its grams
/// their sum. v59 (M60 P7b): bacon that cooks on a food ([_baconDrips])
/// writes the same two parts with no fat kept. Any other row carries no
/// parts.
IngredientMatchRow withRenderedBacon(
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row, {
  double? raw,
}) {
  final grams = raw ?? row.grams;
  final keptMl =
      row.fdcId == rawBaconFdcId &&
          (row.status == 'auto' || row.status == 'confirmed') &&
          row.hold == null &&
          row.gramSource != GramSource.override.name &&
          grams != null &&
          grams > 0 &&
          !line.raw.toLowerCase().contains('divided')
      // v59 (M60 P7b): bacon that drips keeps no fat ([_baconDrips]).
      ? _baconKeptMl(recipe) ?? (_baconDrips(recipe) ? 0.0 : null)
      : null;
  if (keptMl == null) {
    return row.parts == null ? row : row.copyWith(clearParts: true);
  }
  double round2(double v) => double.parse(v.toStringAsFixed(2));
  final cooked = round2(grams! * baconCookedYield);
  // v51 (M49 Q19, P4 §4): an oil browned in the same pan ([_baconPanOf])
  // shares the stated amount — the kept fat is at most R + O and the
  // bacon's part of it R / (R + O); the oil's row keeps the rest
  // ([_keptInPan]).
  final pan = _baconPanOf(recipe);
  final oil = pan == null || pan.bacon.raw != line.raw
      ? 0.0
      : _panOilGrams(pan) ?? 0.0;
  final rendered = grams * baconRenderedPerGram;
  final pooled = min(keptMl * baconGreaseGramsPerMl, rendered + oil);
  final kept = round2(
    oil == 0 ? pooled : pooled * rendered / (rendered + oil),
  );
  return row.copyWith(
    grams: round2(cooked + kept),
    parts: jsonEncode([
      {'fdc_id': cookedBaconFdcId, 'grams': cooked},
      {'fdc_id': baconGreaseFdcId, 'grams': kept},
    ]),
  );
}

/// [row] with the parts its rule stores — the ONE writer of the `parts`
/// column, at every place a row is built or derived: rule B1's rendered
/// bacon ([withRenderedBacon]); v49 (M47 Q6) a zest over a tablespoon plus
/// juice ([SecondFoodRule.second]: the zest on its peel record, the juice
/// on its own); v49 (M47 Q14 (ii)) the half rule's cans ([halvesCans]) on a
/// record with a solids-and-liquids twin ([cannedBeanLiquids]: the drained
/// can on the record bought, the undrained one on the twin). Each only on
/// an `auto` or `confirmed` row, unheld, never under grams a person typed;
/// its grams the parts' sum, each part rounded to 0.01 g and named by its
/// `role`. Any other row carries no parts.
IngredientMatchRow withParts(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row, {
  double? raw,
}) {
  final bacon = withRenderedBacon(recipe, line, row, raw: raw);
  if (bacon.parts != null ||
      bacon.fdcId == null ||
      (bacon.status != 'auto' && bacon.status != 'confirmed') ||
      bacon.hold != null ||
      bacon.gramSource == GramSource.override.name ||
      (bacon.grams ?? 0) <= 0) {
    return bacon;
  }
  double round2(double v) => double.parse(v.toStringAsFixed(2));
  IngredientMatchRow split(
    (int, double, String) first,
    (int, double, String) second,
  ) {
    final a = round2(first.$2);
    final b = round2(second.$2);
    return bacon.copyWith(
      grams: round2(a + b),
      parts: jsonEncode([
        {'fdc_id': first.$1, 'grams': a, 'role': first.$3},
        {'fdc_id': second.$1, 'grams': b, 'role': second.$3},
      ]),
    );
  }

  // Only a row on a peel record reads the rule (its regexes run per row).
  final rule = _citrusPeel.values.any((peel) => peel.fdcId == bacon.fdcId)
      ? secondFoodRuleOf(line, recipe: recipe)
      : null;
  final second = rule?.second;
  if (rule != null && second != null && bacon.fdcId == rule.fdcId) {
    final zest = rule.gramsOn(knownFood(db, rule.fdcId, line: line));
    final juice = second.grams(knownFood(db, second.fdcId, line: line));
    // Either record not cached (never after the compute's own fetch,
    // [ruleRowFor]): held, as before v49.
    return zest == null || juice == null
        ? bacon.copyWith(hold: 'second_food')
        : split(
            (rule.fdcId, zest.grams, 'zest'),
            (second.fdcId, juice.grams, 'juice'),
          );
  }
  final liquid = cannedBeanLiquids[bacon.fdcId];
  final share = cannedBeanShares[bacon.fdcId]?.share;
  if (liquid != null &&
      share != null &&
      halvesCans(line.raw) &&
      knownFood(db, liquid) != null) {
    // The half rule's grams: one can × (1 + share); each can is grams ÷
    // (1 + share).
    final can = bacon.grams! / (1 + share);
    return split(
      (bacon.fdcId!, can * share, 'drained'),
      (liquid, can, 'undrained'),
    );
  }
  return bacon;
}

/// The parts a two-part row stores: `[{"fdc_id": …, "grams": …}, …]`
/// (v49: a `role` too, [withParts]; rule B1's rows keep none).
List<({int fdcId, double grams})> partsOf(String? parts) => parts == null
    ? const []
    : [
        for (final part in jsonDecode(parts) as List<dynamic>)
          (
            fdcId: (part as Map<String, dynamic>)['fdc_id'] as int,
            grams: (part['grams'] as num).toDouble(),
          ),
      ];

/// Whether the line [raw] names a second food the first food's record does
/// not cover ("2 large eggs plus 6 large yolks", "zest plus 2 tablespoons
/// juice"): the engine counts it by its [secondFoodRuleOf] or holds it
/// `second_food`, and a decision on its key reaches it never
/// ([decisionReach]). Read from the raw text alone, so the reach filters
/// stored rows with no recipe loaded.
bool namesSecondFood(String raw) {
  secondFoodReads++;
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

/// How many raws [namesSecondFood] read since reset — what the tests pin
/// the reach's per-request memo by (Run 055 V1), never a clock.
@visibleForTesting
int secondFoodReads = 0;

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

/// v44 (S7 a): the rule of a zest of at most a tablespoon plus a COUNT of
/// the same fruit ("½ teaspoon grated orange zest plus 5 oranges peeled and
/// segmented", grill-roasted-bone-in-pork-rib-roast's salsa): the fruit counted
/// on its whole-fruit record ([_citrusFruit]), the zest dropped as the
/// juice rule drops it. v49 (M47 Q6, critic F17): lemons and limes too
/// ("1 tablespoon grated lemon zest, plus 2 lemons, halved", grilled
/// swordfish; "2 teaspoons grated lemon zest, plus 1 lemon", fava beans),
/// each read as a bare "2 lemons" line reads (FNDDS 2709168, SR 168155).
/// Null for any other line.
SecondFoodRule? _zestPlusFruit(
  IngredientLine line,
  PlusPart plus,
  String firstText, {
  required bool citrus,
}) {
  final zestOf = RegExp(
    r'\b(lemon|lime|orange) (?:zest|peel)\b',
  ).firstMatch(firstText);
  final zestVolume = line.amounts
      .where((amount) => amount.measure == Measure.volume)
      .firstOrNull;
  final zestMl = zestVolume == null ? null : volumeMlOf([zestVolume]);
  if (!citrus ||
      zestOf == null ||
      _citrusFruit[zestOf[1]] == null ||
      plus.amount.unit != null ||
      // "5 oranges peeled …": the count, then the fruit itself.
      !RegExp(
        '^[^a-z]*(?:(?:small|medium|large) )?${zestOf[1]}s?\\b(?! juice)',
      ).hasMatch(plus.text.toLowerCase()) ||
      zestMl == null ||
      zestMl > _tablespoonMl + 0.01) {
    return null;
  }
  final fruit = '${zestOf[1]}s';
  return SecondFoodRule._(_citrusFruit[zestOf[1]]!, fruit, (food) {
    final grams = resolveGrams(
      amounts: [plus.amount],
      food: food,
      normalizedItem: fruit,
    );
    return grams == null
        ? null
        : GramResolution(
            grams: grams.grams,
            source: grams.source,
            basis: '${grams.basis} · the fruit only (the zest is dropped)',
          );
  });
}

/// The whole-fruit record a zest-plus-counted-fruit line counts on (v44,
/// S7 a: oranges; v49: the records the library's bare lemon and lime
/// counts sit on).
const Map<String, int> _citrusFruit = {
  'orange': 746771, // Oranges, raw, navels
  'lemon': 2709168, // Lemon, raw
  'lime': 168155, // Limes, raw
};

/// v49 (M47 Q6): the peel record a zest over a tablespoon counts on, by
/// fruit — lime zest on lemon peel, the shipped flagged approximation
/// ([approximationRecords] 'lime zest').
const Map<String, ({int fdcId, String words})> _citrusPeel = {
  'lemon': (fdcId: 167749, words: 'lemon peel'), // Lemon peel, raw
  'lime': (fdcId: 167749, words: 'lemon peel'),
  'orange': (fdcId: 169103, words: 'orange peel'), // Orange peel, raw
};

/// v49 (M47 Q6): whether [recipe]'s steps strain or discard the zest at or
/// after its first mention — "Strain the juice mixture" (fresh margaritas),
/// "Strain milk mixture …; discard lemon zest" (lemon pudding cakes), the
/// curd poured "through a fine-mesh strainer" (lemon tart).
bool _zestStrained(Recipe recipe) {
  final text = recipe.steps.map((step) => step.text).join(' ').toLowerCase();
  final at = RegExp(r'\b(zest|peel)\b').firstMatch(text)?.start;
  return at != null &&
      RegExp(
        r'\bstrain|\bdiscard\w*\s+(?:the\s+)?(?:(?:lemon|lime|orange)\s+)?'
        r'(?:zest|peel)\b',
      ).hasMatch(text.substring(at));
}

/// The whole-egg record [eggPartsMassSumOn] counts on: "Eggs, Grade A,
/// Large, egg whole" (Foundation).
const int _wholeEgg = 748967;

/// A tablespoon: the most zest [citrusJuiceRuleOn] drops.
const double _tablespoonMl = 14.7868;

/// A second-food line the engine counts on one record by rule: the record,
/// the words its score is ranked under, and the grams on it.
class SecondFoodRule {
  const SecondFoodRule._(this.fdcId, this.query, this._grams, [this.second]);

  /// The record the line counts on.
  final int fdcId;

  /// The words the record is ranked under for the row's confidence.
  final String query;

  final GramResolution? Function(FdcFood? food) _grams;

  /// v49 (M47 Q6): the line's second part on its own record (a zest over a
  /// tablespoon plus juice: the juice) — the row then stores two parts
  /// ([withParts]); null for a one-record rule.
  final ({int fdcId, GramResolution? Function(FdcFood? food) grams})? second;

  /// The line's grams on [food] (the record [fdcId]; the egg sum needs
  /// none) — its first part's alone when the rule has a [second].
  GramResolution? gramsOn(FdcFood? food) => _grams(food);
}

/// The [SecondFoodRule] of [line], or null: a zest-plus-juice line under
/// [citrus], an eggs-plus-parts line under [eggs].
SecondFoodRule? secondFoodRuleOf(
  IngredientLine line, {
  bool citrus = citrusJuiceRuleOn,
  bool eggs = eggPartsMassSumOn,
  Recipe? recipe,
}) {
  // Only a line that names a second food: the reach leaves out exactly
  // those ([decisionReach]), so a rule line is never offered.
  final at = RegExp(
    '\\bplus\\s+(?=[\\d$vulgarFractionChars])',
    caseSensitive: false,
  ).firstMatch(line.raw);
  final names = namesSecondFood(line.raw);
  final plus = at == null ? null : plusPartOf(line.raw);
  if (at == null || plus == null) {
    return null;
  }
  final firstText = line.raw.substring(0, at.start).toLowerCase();
  if (_zestPlusFruit(line, plus, firstText, citrus: citrus) case final rule?) {
    return rule;
  }
  if (!names) {
    return null;
  }
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
    // v49 (M47 Q6, amends checkpoint 5): a zest over a tablespoon is
    // counted — two parts, the zest on its peel record and the juice on
    // its own — unless a step strains or discards it (juice only). Read on
    // the recipe's steps: with none, held as before.
    final large = zestMl != null && zestMl > _tablespoonMl + 0.01;
    if (juice == null ||
        volumeMlOf([juice]) == null ||
        zestMl == null ||
        (large && recipe == null)) {
      return null;
    }
    final fruit = citrusKey[1]!;
    final strained = large && _zestStrained(recipe!);
    GramResolution? juiceOn(FdcFood? food, String note) {
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
              basis: '${grams.basis}$note',
            );
    }

    if (large && !strained) {
      final peel = _citrusPeel[fruit]!;
      return SecondFoodRule._(
        peel.fdcId,
        peel.words,
        (food) => resolveGrams(
          amounts: [zest!],
          food: food,
          normalizedItem: '$fruit zest',
        ),
        (
          fdcId: _citrusJuice[fruit]!,
          grams: (food) => juiceOn(food, ''),
        ),
      );
    }
    return SecondFoodRule._(
      _citrusJuice[fruit]!,
      '$fruit juice',
      (food) => juiceOn(
        food,
        strained
            ? ' · juice only (the zest is strained out)'
            : ' · juice only (the zest is dropped)',
      ),
    );
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
  // v44 (S6 a): a lone cut word the corpus split from its food ("4 (6- to
  // 8-ounce) boneless, skinless chicken breasts, trimmed" parsed the item
  // "(6- to 8-ounce) boneless", skillet-chicken-and-rice's two sections)
  // reads on to its food, as the main twin's line keys.
  'boneless',
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

/// The rule note of a SECTION line ([recipe] keyed `<host>#<title>`) that
/// is its main recipe's OWN part (v44, S6 a; the owner's sub-choice: the
/// note says what the line says): an amount-less "Reserved turkey giblets,
/// neck, and tailpiece" / "Defatted pan drippings from Herbed Roast Turkey"
/// — no amount on the line, so 0 g as every amount-less line (the gravies
/// differ in what they do with the parts; the rule claims nothing more) —
/// or "1 teaspoon reserved spice rub" whose mixture the main recipe's own
/// group makes (grill-roasted-beef-short-ribs' "SPICE RUB": "Measure out 1
/// teaspoon rub and set aside for glaze") — counted there. Null otherwise
/// (a main line: chicken-and-dumplings' "3 tablespoons reserved chicken
/// fat" is a food).
String? mainRecipePartNote(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  String normalized,
) {
  if (hostOf(recipe.id) == recipe.id) {
    return null;
  }
  final reserved = normalized.startsWith('reserved ');
  if (line.amounts.isEmpty) {
    return reserved || normalized.contains('drippings from ')
        ? reservedNoAmountNote
        : null;
  }
  if (!reserved) {
    return null;
  }
  final mixture = normalized.substring('reserved '.length);
  final host = nutritionRecipeOf(db, hostOf(recipe.id))?.recipe;
  return host != null &&
          host.ingredients.any(
            (group) => normalizeItem(group.group ?? '') == mixture,
          )
      ? reservedMixtureNote
      : null;
}

/// [mainRecipePartNote]'s note for an amount-less part (an
/// [engineRuleNotes] entry).
final String reservedNoAmountNote = engineRuleNotes[6];

/// [mainRecipePartNote]'s note for the main recipe's own mixture.
final String reservedMixtureNote = engineRuleNotes[7];

/// v68 (batch M70; prep49 design_v2 §2 M70, the owner's Q13 G2): the grams
/// of a SECTION's amount-less "Reserved turkey giblets, …" line that a
/// section step stirs back ("Stir the reserved giblets into the gravy",
/// 0154) — weighed off the host's turkey line as the bird row is: its
/// printed weight × (85 − 78) / 85, the neck and giblets of USDA AH-102's
/// turkey dressing data (12 lb and over: 85 ready to cook with them, 78
/// without — the figure the bird row already takes off), × 6 / (4 + 6), the
/// giblets' share of AH-102 item 2590's neck 4 / giblets 6. Null for any
/// other line. The one reader every caller asks ([lineGrams]: the compute,
/// a Confirm's [gramsFor], the GET basis) whatever the record (matcher
/// `_rankAs` lands SR 171083 "Turkey, whole, giblets, raw", a hit in the
/// cached 'giblet pan gravy' answer); a reserved line buys nothing, so no
/// reader fetches its detail ([buysRefuse]): zero requests.
/// The bird line is read by its TEXT (the host's first line whose item's
/// head is 'turkey' with a printed weight), never the host's stored row: a
/// section computes before its host (bulkScopeIds). Its grams join the
/// section's [ingredientsHashOf], so a host-only bird edit stales it.
/// ponytail: one host, one bird line; a second reserved part (the neck, a
/// backbone) is not read; the neck and tailpiece the steps strain out are
/// not counted (the basis says so).
GramResolution? hostWeighedGiblets(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  String normalized,
) {
  if (line.amounts.isNotEmpty ||
      !normalized.startsWith('reserved ') ||
      !normalized.contains('giblet') ||
      hostOf(recipe.id) == recipe.id ||
      !_stepIndexOf(recipe).allSentences.any(_stirsGibletsBack.hasMatch)) {
    return null;
  }
  final host = nutritionRecipeOf(db, hostOf(recipe.id))?.recipe;
  if (host == null) {
    return null;
  }
  for (final bird in nutritionLines(host)) {
    final item = normalizeItem(lineItemOf(bird));
    if (headNounOf(item) != 'turkey') {
      continue;
    }
    final printed = resolveGrams(
      amounts: bird.amounts,
      food: null,
      normalizedItem: item,
      raw: bird.raw,
    );
    if (printed == null || printed.source != GramSource.weight) {
      return null;
    }
    return GramResolution(
      grams: printed.grams * (85 - 78) / 85 * 6 / (4 + 6),
      source: GramSource.weight,
      basis:
          "the host's turkey ${printed.basis}: ${_fmtAmount(printed.grams)} g "
          '× 7/85 neck and giblets (USDA AH-102 turkey dressing data, 12 lb '
          'and over: 85 with, 78 without) × 6/10 giblets (item 2590: neck 4, '
          'giblets 6, fryer-roaster class) · approximate (the neck and '
          'tailpiece are strained out — not counted)',
    );
  }
  return null;
}

final RegExp _stirsGibletsBack = RegExp(
  r'\bstir\b[^.]*\bgiblets\b[^.]*\binto\b',
);

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

/// The decision key of [line] — read from its text and item alone, so
/// memoised by them (Run 055 V1: ~0.3 ms on a 1,000-character line, read
/// by the layout, the reach and the search of every line of every GET).
String lineKeyOf(IngredientLine line) {
  if (_lineKeys.length >= _cap(20000)) {
    _lineKeys.clear(); // ponytail: whole-map clear; an LRU if outgrown.
  }
  return _lineKeys.putIfAbsent(
    (line.raw, line.item),
    () {
      keyReads++;
      return decisionKeyFor(decisionItemOf(line));
    },
  );
}

final Map<(String, String?), String> _lineKeys = {};

/// The flattened, positioned ingredient lines nutrition works over. A "1
/// recipe X" line whose subsection is one counted food carries that food's
/// amounts ([_singleFoodYield], the ruling Q1) — here, so every path that
/// weighs the line (a compute, a confirm, a pick, the basis) reads the same
/// amounts. Memoized per recipe (a [Recipe] never changes), so a line stays
/// [identical] to itself.
List<IngredientLine> nutritionLines(Recipe recipe) =>
    _lines[recipe] ??= List.unmodifiable([
      for (final group in recipe.ingredients)
        for (final line in group.items)
          switch (_singleFoodYield(recipe, line)) {
            final amounts? => IngredientLine(
              raw: line.raw,
              item: line.item,
              prep: line.prep,
              amounts: amounts,
            ),
            null => line,
          },
    ]);

/// [nutritionLines], per recipe.
final Expando<List<IngredientLine>> _lines = Expando();

/// Hash of everything nutrition depends on — when it changes, stored
/// results are stale. [memo] serves the library reads of a recipe holding
/// a reference line (v47, F2: [proseSectionsReadBy]); one per request or
/// compute, as every resolver read.
String ingredientsHashOf(Recipe recipe, ResolverMemo memo) {
  // The matcher version is part of it: a bump makes every computed recipe
  // stale, so the stale sweep re-resolves its engine rows instead of leaving
  // scores and picks frozen at the matcher that wrote them. So are the
  // recipe's own steps and its title, which the discarded-media rules read
  // ([discardedMediumOf]): a steps-only edit adding or removing a drain
  // left the hold and the totals frozen, never stale (v11, Opus critic).
  final lines = nutritionLines(recipe);
  final references = lines.any((line) => isReferenceIn(recipe, line));
  final prose = references
      ? proseSectionsReadBy(recipe, memo)
      : const <String>[];
  final payload = jsonEncode({
    'matcher': matcherVersion,
    'title': recipe.title,
    'steps': [for (final step in recipe.steps) step.text],
    // v41 (S12): what the sub-recipe resolver reads beside the line — the
    // note naming a dough, the sections a reference names — for a recipe
    // holding a reference line ([resolveReference]).
    if (references) ...{
      'prep_notes': recipe.prepNotes,
      'sections': [for (final sub in recipe.subsections) sub.title],
      // v52 (M51 Q8): the group headings — rule SW reads a CONDIMENTS one.
      'groups': [for (final group in recipe.ingredients) group.group],
      // v47 (F2): and whether the section a line names lists lines — only
      // when one does not, so every other recipe hashes as before (v52: or
      // the child an amount-less line names, [proseSectionsReadBy]).
      if (prose.isNotEmpty) 'prose_sections': prose,
    },
    // v44 (P1 §3.1): a SECTION's yield, which its parents' shares read
    // ([parseShare]) and no other term covers — a yield edit stales the
    // section, whose new stamp re-derives its parents.
    if (hostOf(recipe.id) != recipe.id) 'servings': recipe.servings,
    'lines': [
      for (final line in lines)
        {
          'raw': line.raw,
          'item': line.item,
          'amounts': [for (final amount in line.amounts) amount.toMap()],
          // A sub-recipe's eaten "plus" part is read from its subsection
          // ([weighedLine]): an edit there changes what the line counts
          // (Run 047: 0711's oil renamed or removed left the totals fresh).
          if (weighedLine(recipe, line) case final eaten
              when !identical(eaten, line))
            'eaten': {
              'raw': eaten.raw,
              'item': eaten.item,
              'amounts': [for (final amount in eaten.amounts) amount.toMap()],
            },
          // v68 (M70; closer 2, D1): a section's reserved giblets are
          // weighed off the HOST's bird line ([hostWeighedGiblets]) — a
          // host-only edit of the bird's printed weight left the section
          // fresh on its old grams. Only on a line that reader weighs (its
          // two cheap gates first), so every other recipe hashes as before.
          if (line.amounts.isEmpty && hostOf(recipe.id) != recipe.id)
            if (hostWeighedGiblets(
                  memo.db,
                  recipe,
                  line,
                  normalizeItem(lineItemOf(line)),
                )
                case final giblets?)
              'host_weighed': giblets.grams,
        },
    ],
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

/// The section keys [recipe]'s reference lines resolve to that list NO
/// ingredient lines — each line's `no_ingredients` rule row (v47, F2; Run
/// 062 O2: lemon-meringue-pie|0's prose "Single-Crust Pie Dough for Custard
/// Pies", another recipe's section). The rule row stores no child, so no
/// stamp ties the parent to the section: the hash does. A section that
/// gains lines leaves the list (the parent reads stale, a sweep routes it);
/// one that loses them joins it (the parent falls back to the rule row in
/// the sweep that collects the section). Only the lines the sub-recipe
/// rule zeroes ([subRecipeRowFor]), as [referenceRowFor] reads them. v52
/// (M51 Q9, rule PV): a line counted as the prose section's BASE folds the
/// prose section all the same — it gaining lines stales the parent, which
/// then routes to it. Read off the shipped order ([_resolveInOrder]), so a
/// line with NO amount folds it too, and (M51 Q22, rule WB; closer3 D1)
/// such a line also folds the library child or section whose lines keep it
/// from WB's whole batch — one listing none (latin-flan) or one made from a
/// recipe (`nested`): those lines decide `noAmount` against `routed` and no
/// stamp ties the 0 g rule row to the child. A served-with marked line with
/// no amount reads no child ([resolveReference]), so it folds nothing.
List<String> proseSectionsReadBy(Recipe recipe, ResolverMemo memo) => [
  for (final (i, line) in nutritionLines(recipe).indexed)
    if (subRecipeRowFor(recipe, i, line) != null &&
        !(line.amounts.isEmpty && servedWithMarked(recipe, line)))
      if (switch (_resolveInOrder(memo.db, recipe, line, memo)) {
            ReferenceResolution(noIngredients: true, section: final at?) =>
              sectionKeyOf(at.host, at.title),
            ReferenceResolution(
              kind: ReferenceKind.nested || ReferenceKind.noShare,
              childId: final id?,
            )
                when line.amounts.isEmpty =>
              id,
            _ => null,
          }
          case final key?)
        key,
];

/// Whether [recipe]'s stored totals ([row], else read) are FRESH: stamped
/// for its current inputs ([ingredientsHashOf]) AND on its current layout
/// ([SaltDatabase.layoutOf], migration 013). The hash alone is an ABA gate
/// (Run 052 O1/S2): a save, a person's write laying the rows out for it
/// (dropping a gone line's row) and a revert hash as before, but the layout
/// moved — the restored line has no row, and the totals miss it. AND
/// (RULE A, v27, migration 014) with no decided row UNDERIVED: one whose
/// `derived_seq` is not the stamp's key ([SaltDatabase.underivedSql], read
/// over the rows as they are NOW — a stamp written over a person's
/// underived write never reads fresh, Run 057 S15/O1). Every reader of
/// freshness goes through here or reads the same halves
/// ([SaltDatabase.recipesWithNutrition]). [memo]: the caller's resolver
/// reads ([ingredientsHashOf]), else one of its own. v47 (F5): AND every
/// SECTION its totals read is fresh itself ([staleSectionsReadBy]) — the
/// recipe page reads stale and offers Recompute the moment a routed
/// section is edited, as the `stale` sweep lists it.
bool nutritionIsFresh(
  SaltDatabase db,
  Recipe recipe, [
  RecipeNutritionRow? row,
  ResolverMemo? memo,
]) {
  final reads = memo ?? ResolverMemo(db);
  return nutritionStampCurrent(db, recipe, row, reads) &&
      !db.hasUnderivedRows(recipe.id) &&
      staleSectionsReadBy(db, recipe, reads) == null;
}

/// Whether a SECTION [recipe]'s totals read moved since they were derived
/// (v47, F5 — Run 062 fleet-2 critic), each section's stamp read as the
/// page reads a recipe's own ([staleReasonOf], closer round 2's D1 — Run
/// 059 O23): `inputs` when one's inputs or layout moved (its lines, yield
/// or steps edited in its host's document — the parent's own hash reads
/// the section TITLES only, and its `child_stamp` moves only once the
/// section is recomputed), else `interrupted` when one is mid-write or a
/// writer of it never finished, else `underived` when one holds an
/// underived row or was stamped waiting on USDA — never `inputs` when
/// nothing changed; null when every one is fresh. Only the sections the
/// totals count
/// ([recomputeTotals]: a row on a section key, not skipped, not held
/// choose/nested) that hold a stamp — one with none already reads its
/// parent stale (the totals stamp it waiting on USDA, or a `child_stamp`
/// names a stamp it no longer has). A library child is not read here: its
/// own page reads stale and offers Recompute, whose new stamp then stales
/// this one (`child_stamp`).
String? staleSectionsReadBy(
  SaltDatabase db,
  Recipe recipe,
  ResolverMemo memo,
) {
  final reasons = <String?>{
    for (final key in {
      for (final row in db.ingredientMatchesFor(recipe.id))
        if (row.childRecipeId case final key?
            when hostOf(key) != key &&
                row.status != 'skipped' &&
                !recipeChoiceHolds.contains(row.hold))
          key,
    })
      if ((memo.childNutrition(key), memo.hostRecipe(hostOf(key))) case (
        final stamp?,
        final host?,
      ))
        if (sectionOf(host, key) case final section?)
          staleReasonOf(db, section, stamp, memo),
  };
  for (final reason in const ['inputs', 'interrupted', 'underived']) {
    if (reasons.contains(reason)) {
      return reason;
    }
  }
  return null;
}

/// Why [recipe]'s stamp [row] reads stale, as the page's `stale_reason`
/// names it (v28/v29), or null when it is fresh: `interrupted` — a writer
/// holds its mark or never finished (migration 017); `underived` — the
/// stamp is on the current inputs and layout but a decision is waiting on
/// USDA, or the totals were stamped waiting on USDA ([unavailableStampOf]
/// the current inputs; never `inputs` when nothing changed, Run 059 O23);
/// `inputs` — the inputs or layout moved since. The page reads it for the
/// recipe's own stamp and, through [staleSectionsReadBy], for each section
/// its totals count (v47 closer round 2, D1).
String? staleReasonOf(
  SaltDatabase db,
  Recipe recipe,
  RecipeNutritionRow row,
  ResolverMemo memo,
) =>
    row.computing > 0 ||
        row.ingredientsHash.startsWith(SaltDatabase.interruptedStamp)
    ? 'interrupted'
    : nutritionStampCurrent(db, recipe, row, memo)
    ? (db.hasUnderivedRows(recipe.id) ? 'underived' : null)
    : row.ingredientsHash == unavailableStampOf(ingredientsHashOf(recipe, memo))
    ? 'underived'
    : 'inputs';

/// The stamp half of [nutritionIsFresh]: the totals were stamped for
/// [recipe]'s current inputs and layout. What `computeUntilFresh` repeats
/// a compute for (a save cut it off) — never an underived row, which a
/// second pass would only ask FDC for again (Run 057 S5/S16/O2/O16).
bool nutritionStampCurrent(
  SaltDatabase db,
  Recipe recipe, [
  RecipeNutritionRow? row,
  ResolverMemo? memo,
]) {
  final stamp = row ?? db.nutritionFor(recipe.id);
  return stamp != null &&
      stamp.ingredientsHash ==
          ingredientsHashOf(recipe, memo ?? ResolverMemo(db)) &&
      stamp.layoutSeq == db.layoutSeqOf(recipe.id);
}

/// Matches every ingredient line of [recipe] against FDC and computes the
/// per-serving totals. Existing user decisions (confirmed / overridden /
/// skipped rows whose raw text is unchanged, never the engine's own rule
/// rows, [isEngineRuleRow]) are preserved; `auto`, `unmatched`, rule and
/// changed rows are re-resolved.
///
/// Returns the first provider failure a decided row's derivation met
/// (RULE A's "derivation unavailable": the row left underived, the rest
/// computed and stamped), or null — so the job loops stop on a bad key or
/// an outage with the provider's own reason (Run 057 S16/O16), while a
/// caller that only computes reads the row fact ([nutritionIsFresh]).
///
/// [retryUnavailable] (the `all` scope's sweep, v29 RULE A — Run 059 S3):
/// a row held [foodUnavailableHold] is asked again, once in the pass (a
/// healthy food held by transient failures recovers with no person); every
/// other pass re-reads such a hold from the caches only.
Future<NutritionProviderException?> matchAndCompute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe recipe, {
  bool retryUnavailable = false,
}) async {
  // IN PROGRESS until the totals are written (v29, migration 017; Run 059
  // Opus critic 1) — an OWNED mark, taken before the pass's first row
  // write (the layout's) and released with its totals: a pass that never
  // gets there — a restart, an await never answered — leaves the recipe
  // stale whatever it marked derived; one that throws releases its mark
  // and clears the stamp (stale, `interrupted`) — the next compute repairs
  // it, and no other writer's mark is touched.
  final marked = db.markComputing(recipe.id);
  var ended = false;
  try {
    final failure = await _computePass(
      db,
      fdc,
      recipe,
      retryUnavailable: retryUnavailable,
      marked: marked,
    );
    ended = true;
    return failure;
  } finally {
    if (!ended) {
      db.releaseComputing(recipe.id, owned: marked, stale: true);
    }
  }
}

/// [matchAndCompute]'s pass under its mark ([marked]: whether it took one,
/// released by its totals).
Future<NutritionProviderException?> _computePass(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe recipe, {
  required bool retryUnavailable,
  required bool marked,
}) async {
  // One request per FOOD per pass ([onePass]), suspended after
  // [detailOutageAfter] failing in a row.
  final provider = onePass(fdc, recipe: recipe.id) as _OnePass;
  final lines = nutritionLines(recipe);
  // Rows are keyed by POSITION, so an edit (insert, delete, reorder, a
  // changed text) moves lines out from under their rows. The layout
  // ([layoutMatchRows]) carries every row to its line — in ONE transaction,
  // before the first await — and drops the rows whose lines are gone; the
  // same layout runs before a person's write ([applyMatchOverride]), so a
  // decision made between a save and this compute lands on its line too.
  // After it, a person's decision here is either kept (its text unchanged)
  // or its line's amount was edited ("orphan": same ingredient, old text,
  // the grams re-derived below). An engine row (`auto`, `unmatched`, a rule
  // row [isEngineRuleRow]) is re-derived; it never takes another line's
  // decision. Every write below stays guarded
  // ([SaltDatabase.upsertIngredientMatchIfUndecided]): a provider throw
  // leaves the laid-out decisions where they are, and a person's write
  // during an await stands.
  final paired = layoutMatchRows(db, recipe);
  // Every write lands only while the stored recipe's nutrition inputs
  // ([ingredientsHashOf]: its lines, steps, title) are still the ones read
  // here: a save changing them during an await makes these lines stale, and
  // the next layout (a person's write, the next compute) moves the rows out
  // from under their positions — so from then on this compute writes no
  // row, and its totals are NOT stamped fresh (the recipe reads stale, so
  // the next sweep revisits it). A save changing nothing it reads (tags,
  // notes) blocks nothing. The stored recipe is re-read only when its
  // content hash moved.
  // Equal inputs are not enough (Run 051 C1, ABA): a save, a person's
  // write laying the rows out for it, and a save reverting it leave the
  // hash as it was and the rows where the middle save put them. So every
  // write also checks, in its own transaction, that no layout came between
  // ([SaltDatabase.layoutOf]: the sequence a layout that moves a row or
  // lays the rows on other lines bumps); one that did trips the gate as a
  // save does.
  final seq = db.layoutSeqOf(recipe.id);
  // The library's titles and sections, read at most once in this compute
  // and only for a reference line (v41, F14) — the hash's too (v47, F2).
  final references = ResolverMemo(db);
  final inputs = ingredientsHashOf(recipe, references);
  // A section key's content is its HOST's document (v44, F2): a host save
  // during a section's await moves the host's hash.
  var version = db.contentHashOf(hostOf(recipe.id));
  var current = true;
  bool fresh() {
    if (current && db.layoutSeqOf(recipe.id) != seq) {
      current = false;
    }
    final now = db.contentHashOf(hostOf(recipe.id));
    if (current && now != version) {
      version = now;
      final stored = nutritionRecipeOf(db, recipe.id)?.recipe;
      current =
          stored != null && ingredientsHashOf(stored, references) == inputs;
    }
    return current;
  }

  bool write(IngredientMatchRow row) =>
      fresh() && db.upsertIngredientMatchIfUndecided(row, layoutSeq: seq);
  // Each decided row AS THE LAYOUT PLACED IT — at its line's position, a
  // moved row with that line's key, as [SaltDatabase
  // .relayoutIngredientMatches] stored it: every derived write below is
  // addressed by the row's CURRENT position (v26, Run 056 S1: `paired`
  // holds the rows as read before the layout, so 0129's confirmed liquid
  // smoke, shifted up a line by a save, was looked up at its OLD position —
  // nothing written, or a twin there overwritten — and the recipe stamped
  // fresh on the stale grams).
  final decidedAt = <int, IngredientMatchRow>{};
  final orphanAt = <int, IngredientMatchRow>{};
  for (final (position, row) in paired.indexed) {
    if (row != null && _isDecided(row)) {
      final laid = row.position == position
          ? row
          : row.copyWith(
              position: position,
              itemKey: lineKeyOf(lines[position]),
            );
      (row.raw == lines[position].raw ? decidedAt : orphanAt)[position] = laid;
    }
  }
  // What every decided row this compute derives is derived FOR (RULE A,
  // v27): the layout and inputs it read — written on the row
  // (`derived_seq`) with its derived fields. A row whose derivation could
  // not run ([derivedFor]'s `unavailable`) keeps what it had: underived
  // for these inputs, so the recipe reads stale ([nutritionIsFresh]) and
  // the next sweep derives it — one request per such row per pass. Its
  // first failure is returned for the job loops.
  final derivedKey = derivedKeyOf(seq, inputs);
  NutritionProviderException? failure;
  // RULE A's FOOD failure class (v28, Run 058 Opus critic 1 / S27): FDC
  // failing ONE decided row's food is that row's state — left underived,
  // its computes counted ([SaltDatabase.countFoodFailureIfUnchanged]),
  // held [foodUnavailableHold] at the [foodUnavailableAfter]th — never the
  // job's: returned only when no GLOBAL failure is, and the job loops go on.
  NutritionProviderException? foodFailure;
  // The FOOD failures of this pass, counted once the line loop ends —
  // ALWAYS (the owner's ruling on Run 059 O11, superseding the v28
  // closer's D8: a GLOBAL failure stops further requests and the job, it
  // never discards the counts already taken), the request that tipped a
  // detail outage included ([_Escalated]).
  final foodFailed =
      <
        ({
          int position,
          IngredientMatchRow over,
          IngredientMatchRow row,
          NutritionProviderException error,
        })
      >[];
  void unavailableRow(
    int position,
    IngredientMatchRow over,
    IngredientMatchRow row,
    NutritionProviderException error,
  ) {
    if (error is DetailsSuspended) {
      return; // Never asked: underived, uncounted ([onePass]).
    }
    final food = error is _Escalated ? error.food : error;
    if (error.scope == FailureScope.global) {
      failure ??= error;
    }
    if (food.scope == FailureScope.food) {
      foodFailed.add((position: position, over: over, row: row, error: food));
    }
  }

  void countFoodFailure(
    int position,
    IngredientMatchRow over,
    IngredientMatchRow row,
    NutritionProviderException error,
  ) {
    foodFailure ??= error;
    final count = fresh()
        ? db.countFoodFailureIfUnchanged(over, layoutSeq: seq)
        : null;
    // A row already held (asked again by the `all` scope) is held again at
    // once: its count runs on, kept by the held write (v29, Run 059 S2).
    if (count == null ||
        (count < foodUnavailableAfter && over.hold != foodUnavailableHold)) {
      return;
    }
    // Held for a person (pick or skip, [holdActions]): out of the totals,
    // typed grams kept as the decision, derived grams none.
    final typed = row.gramSource == GramSource.override.name;
    if (fresh()) {
      db.replaceIngredientMatchIfUnchanged(
        row.copyWith(
          hold: foodUnavailableHold,
          clearGrams: !typed,
          clearGramSource: !typed,
          derivedSeq: derivedKey,
        ),
        over: over,
        layoutSeq: seq,
        keepRetryCount: true,
      );
    }
  }

  void countFoodFailures() {
    for (final f in foodFailed) {
      countFoodFailure(f.position, f.over, f.row, f.error);
    }
    foodFailed.clear();
  }

  // RULE A for EVERY line kind (v29, Run 059 Sonnet critic 1 / O3 / Opus
  // critic 3): an ENGINE line whose candidate, prior decision or nutrient
  // record FDC fails (FOOD) gets a row of its own — `unmatched`, no food,
  // [engineUnavailableNote] — counted like a decided row (the same
  // [countFoodFailure]: its `retry_count`, held [foodUnavailableHold] at
  // the [foodUnavailableAfter]th), and the pass goes on to the next line.
  // Until held the row is underived ([SaltDatabase.underivedSql]): the
  // recipe reads stale and the sweep asks again, once per pass.
  // v36 (Run 060 S4): a line whose row already CARRIES A FOOD ([laid], an
  // `auto` row of an earlier pass) keeps it — food, grams, status — and
  // is counted and held exactly as a decided row is (the held write keeps
  // the food); the unmatched row is built only for a line with none.
  // The lines whose row was KEPT so (v36): their food or nutrient record
  // no cache holds leaves the row out of the totals as a decided row's
  // does — the stamp current, the recipe stale by the row itself
  // ([SaltDatabase.underivedSql]) — so a job's next pass
  // ([computeUntilFresh]) never counts the same failure again.
  final kept = <int>{};
  void engineUnavailable(
    int position,
    IngredientLine line,
    IngredientMatchRow? laid,
    NutritionProviderException error,
  ) {
    var over = laid;
    if (over == null) {
      over = IngredientMatchRow(
        recipeId: recipe.id,
        position: position,
        raw: line.raw,
        itemKey: lineKeyOf(line),
        fdcId: null,
        description: engineUnavailableNote,
        dataType: null,
        confidence: 0,
        grams: null,
        gramSource: null,
        status: 'unmatched',
      );
      if (!write(over)) {
        return;
      }
    } else if (over.fdcId != null) {
      kept.add(position);
    }
    unavailableRow(position, over, over, error);
  }

  // Foods built from a search hit this compute (see the candidate loop):
  // the totals read them here, since they are not in fdc_food_cache.
  final standIns = <int, FdcFood>{};

  // No catch (v29): a pass that throws leaves the recipe stale whatever
  // rows it marked derived ([matchAndCompute] clears the stamp as it
  // releases the mark; one that never returns keeps its mark) — Run 058
  // Opus critic 3's cleared keys, Run 059 Opus critic 1's interrupted
  // pass: ONE mechanism; the next compute repairs it.
  for (final (position, line) in lines.indexed) {
    // The query keeps the line's own words; the KEY a decision is stored and
    // reused under is the singular form, so "onion" and "onions" are one.
    final key = lineKeyOf(line);

    // A human decided this row; their call stands, placed at this line by
    // the layout above. `unmatched` is NOT a decision — it is the engine's
    // own "FDC had nothing", and a sweep exists precisely to retry those
    // once FDC gains data or the matcher improves. (A cached empty search
    // answer still short-circuits it, so the retry is free but only helps
    // once the normalised query or the cache changes.)
    final decided = decidedAt[position];
    // A decision held for a food with no record (`food_gone`,
    // `food_unavailable`) is RE-READ before it is enforced (RULE A v29,
    // Run 059 O1/S1/S6/S27): derived from the caches alone ([cacheOnly]:
    // [knownFood], fdc_food_cache then the search-cache index — the one
    // reader the GET and the PUT's gate read too), never asked of FDC
    // (Run 057 S5/S16: the sweep re-asked every pass). A cache that holds
    // the food and its nutrient record again derives it (no request); one
    // that does not leaves the hold standing, derived for these inputs —
    // an edit neither re-asks nor re-stales a held row (Run 059 S2). Only
    // the `all` scope asks again for a `food_unavailable` row, once per
    // pass ([retryUnavailable], S3).
    if (decided != null) {
      final reread =
          noRecordHolds.contains(decided.hold) &&
          !(retryUnavailable && decided.hold == foodUnavailableHold);
      final (:row, :food, note: _, :unavailable) = await derivedFor(
        db,
        reread ? cacheOnly : provider,
        recipe,
        position,
        line,
        decided,
        references: references,
      );
      if (unavailable != null) {
        if (!reread) {
          unavailableRow(position, decided, row, unavailable);
        } else if (decided.derivedSeq != derivedKey && fresh()) {
          db.markDerivedIfUnchanged(
            decided,
            derivedSeq: derivedKey,
            layoutSeq: seq,
            keepRetryCount: true,
          );
        }
        continue;
      }
      if (food != null && _foodFromCache(db, food.fdcId) == null) {
        standIns[food.fdcId] = food;
      }
      final derived = withDerived(
        decided,
        row,
      ).copyWith(derivedSeq: derivedKey);
      if (!sameMatchRow(derived, decided)) {
        if (fresh()) {
          db.replaceIngredientMatchIfUnchanged(
            derived,
            over: decided,
            layoutSeq: seq,
          );
        }
      } else if (decided.derivedSeq != derivedKey) {
        if (fresh()) {
          db.markDerivedIfUnchanged(
            decided,
            derivedSeq: derivedKey,
            layoutSeq: seq,
          );
        }
      }
      continue;
    }

    // The sub-recipe rule ([subRecipeRowFor]) gates EVERY write below — the
    // re-attach of an edited line, a decision reused from another recipe, a
    // fresh match (Run 045: an amount edit re-attached a stale confirmed
    // food to a marked line, 408 g of eggs; a shared key's decision made a
    // marked count a plain no-grams row). A sub-recipe the recipe makes
    // apart stays out of the totals, on no food, 0 g unmeasured (the user's
    // ruling, 2026-09-27) — unless it is a count of the food itself
    // ([subRecipeCountsItsFood]) or carries an eaten "plus" part, which is
    // the line the engine then matches and weighs ([weighedLine]); the row
    // keeps the line's own text and key. A count whose food gives no grams
    // is the sub-recipe still.
    final eaten = weighedLine(recipe, line);
    final uncounted = subRecipeRowFor(recipe, position, line);
    IngredientMatchRow? subRecipeOn(double? grams, {bool sized = true}) =>
        subRecipeRowFor(
          recipe,
          position,
          line,
          onFood: true,
          grams: grams,
          sized: sized,
        );
    final normalized = normalizeItem(lineItemOf(eaten));

    // A decided line edited to the same ingredient (and possibly moved):
    // the layout carried its row here, its old text still on it. What it
    // becomes is [derivedFor]'s, the one outcome a person's write in
    // the stale window gives it too — ahead of the sub-recipe rule (B3).
    final edited = orphanAt[position];
    if (edited != null) {
      final (:row, :food, note: _, :unavailable) = await derivedFor(
        db,
        provider,
        recipe,
        position,
        line,
        edited,
        references: references,
      );
      if (unavailable != null) {
        unavailableRow(position, edited, row, unavailable);
        continue;
      }
      if (food != null && _foodFromCache(db, food.fdcId) == null) {
        standIns[food.fdcId] = food;
      }
      // Over the row it laid out, and only while it is still that row: a
      // person's write on this line during the awaits (an un-skip, under
      // the line's own text) stands (Run 052 O3).
      if (fresh()) {
        db.replaceIngredientMatchIfUnchanged(
          row.copyWith(derivedSeq: derivedKey),
          over: edited,
          layoutSeq: seq,
        );
      }
      continue;
    }
    final seasoning = eaten.amounts.isEmpty && isSeasoningToTaste(normalized);
    final equipment = isNonFood(normalized);
    // v37 (Z14): a split line's tail is counted with the line above.
    final continuation = isContinuationFragment(
      line.raw,
      hasAmounts: line.amounts.isNotEmpty,
      normalizedItem: normalized,
    );
    // v41: a reference line is the composite row its resolution gives
    // ([referenceRowFor]: routed, held, or the 0 g rule row) — unless it
    // offers a food with an amount ([foodAlternativeOf], A10 a) and a
    // person's decision on its key is CARRIED (gate 2: the parent deleted
    // and re-imported), which is weighed there below. A fresh engine match
    // never lands on such a line.
    final carried =
        uncounted != null &&
        foodAlternativeOf(line) != null &&
        db.decisionFor(key)?.fdcId != null;
    if (uncounted != null && !carried) {
      write(referenceRowFor(db, recipe, position, line, references));
      continue;
    }
    // v44 (S6 a): a SECTION line that is its main recipe's own part
    // ([mainRecipePartNote]) is the engine's 0 g rule row — never a search.
    // v68 (M70, Q13 G2): unless the steps stir its giblets back — then it
    // is matched (matcher `_rankAs`: SR 171083 in the cached 'giblet pan
    // gravy' answer) and weighed off the host's bird ([hostWeighedGiblets]).
    if (mainRecipePartNote(db, recipe, eaten, normalized) case final note?
        when hostWeighedGiblets(db, recipe, eaten, normalized) == null) {
      write(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: note,
          dataType: null,
          confidence: 1,
          grams: 0,
          gramSource: GramSource.unmeasured.name,
          status: 'confirmed',
        ),
      );
      continue;
    }
    // v37 (the class ruling, 2026-10-04): a zero-nutrient flavouring
    // ([isZeroNutrientFlavouring]) counts 0 g on no food — never the wrong
    // record it would rank onto ("Pectin, liquid" for liquid smoke). A
    // person's row stands (the paths above); a line held as a discarded
    // medium stays held for its person ([heldMediumLine]).
    if (isZeroNutrientFlavouring(normalized) &&
        !heldMediumLine(recipe, eaten)) {
      write(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: engineRuleNotes[5],
          dataType: null,
          confidence: 1,
          grams: 0,
          gramSource: GramSource.unmeasured.name,
          status: 'confirmed',
        ),
      );
      continue;
    }
    if (continuation ||
        normalized.isEmpty ||
        isWaterLike(normalized) ||
        seasoning ||
        equipment) {
      write(
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: null,
          description: continuation
              ? engineRuleNotes[4]
              : normalized.isEmpty
              ? 'Nothing searchable in this line'
              : seasoning
              ? engineRuleNotes[1]
              : equipment
              ? engineRuleNotes[2]
              : engineRuleNotes[3],
          dataType: null,
          confidence: 1,
          grams: null,
          gramSource: null,
          status: normalized.isEmpty && !continuation
              ? 'unmatched'
              : 'confirmed',
        ),
      );
      continue;
    }

    // An engine row of this line whose food FDC failed (RULE A v29):
    // until held, asked again (once per pass); held, RE-READ from the
    // caches alone ([cacheOnly]) like a decided row's hold — a cache
    // holding the food again matches the line with no request — and
    // asked of FDC again only by the `all` scope ([retryUnavailable]).
    // v36 (Run 060 S4): an engine row CARRYING A FOOD (`auto`, from an
    // earlier pass) is such a row too — a FOOD failure keeps it as a
    // decided row is kept ([engineUnavailable]), never overwritten.
    final laid = paired[position];
    final failed =
        laid != null &&
            ((laid.status == 'unmatched' &&
                    laid.description == engineUnavailableNote &&
                    laid.raw == line.raw) ||
                (laid.status == 'auto' && laid.fdcId != null))
        ? laid.copyWith(position: position, itemKey: key)
        : null;
    final lineProvider =
        failed?.hold == foodUnavailableHold && !retryUnavailable
        ? cacheOnly
        : provider;
    try {
      // A second food the engine counts by rule ([secondFoodRuleOf]): the
      // line's own record, ahead of any key decision — a decision names the
      // first food only.
      final byRule = await ruleRowFor(
        db,
        lineProvider,
        recipe,
        position,
        line,
      );
      if (byRule != null) {
        if (_foodFromCache(db, byRule.food.fdcId) == null) {
          standIns[byRule.food.fdcId] = byRule.food;
        }
        write(byRule.row);
        continue;
      }

      // A person already decided this ingredient (in any recipe, even one
      // since deleted): their food travels, with grams from THIS line's
      // amounts. Still `auto` (an engine write), so a decision made here later
      // still wins, and the review queue treats it as counted — confidence 1
      // says a person chose it.
      final prior = db.decisionFor(key);
      if (prior != null && prior.fdcId != null) {
        final known = await _decidedFood(
          db,
          lineProvider,
          prior.fdcId!,
          eaten,
        );
        // Its nutrient record resolved with it (v28): one FDC no longer
        // serves leaves the decision unusable here — the line is matched.
        if (known != null &&
            !await _siblingGone(db, lineProvider, known.fdcId)) {
          final (weighedOn, weighed) = await gramsFor(
            db,
            lineProvider,
            known,
            eaten,
            recipe: recipe,
          );
          // v39 (Y3): a carried decision on the skin-on record moves like
          // the engine's pick.
          final (food, resolution) = await skinOffFood(
            db,
            lineProvider,
            recipe,
            eaten,
            weighedOn,
            weighed,
          );
          if (_foodFromCache(db, food.fdcId) == null) {
            standIns[food.fdcId] = food;
          }
          final outcome = engineOutcome(
            recipe,
            eaten,
            food,
            resolution,
            decided: true,
          );
          final sub = subRecipeOn(outcome.grams);
          if (sub != null) {
            write(sub);
            continue;
          }
          final carriedRow = withParts(
            db,
            recipe,
            eaten,
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
          await _resolveParts(db, lineProvider, carriedRow);
          write(carriedRow);
          continue;
        }
      }
      if (uncounted != null) {
        // A carried decision this line could not use: the reference row.
        write(referenceRowFor(db, recipe, position, line, references));
        continue;
      }

      final search = lineSearchFor(db, normalized, lineKeyOf(eaten));
      // v49 (M47 Q23 (a)): an item FDC holds no record of lands `no_match`
      // with no record shown, and asks nothing ([noFdcRecordItems]).
      final candidates = noFdcRecordItems.contains(normalized)
          ? const <FdcCandidate>[]
          : await _cachedSearch(db, lineProvider, search.answer);
      // v54 (M56): R2 then R3 after the fresh-over-cured move.
      final ranked = trimDepthRecord(
        eaten.raw,
        leanAndFatSibling(
          eaten.raw,
          freshOverCured(
            eaten.raw,
            rankCandidates(
              search.query,
              candidates,
              canned: namesCannedLegume(eaten.raw, normalized),
              skinOn: impliesSkinOn(eaten.raw, normalized),
              skinless: removesSkin(eaten.raw),
            ),
          ),
        ),
      );
      if (ranked.isEmpty) {
        write(
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
      // detail is still preferred whenever one is held. That stand-in is
      // held in [standIns] for this compute's totals and NEVER written to
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
                : await _cachedFood(db, lineProvider, id));
        // A candidate whose nutrient record FDC no longer serves cannot be
        // counted (v28, Sonnet critic 2: it left the recipe stale for 3
        // passes): passed over like one with no record — the line re-matched.
        if (resolved == null || await _siblingGone(db, lineProvider, id)) {
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
        write(
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
      final twin = belowGateSizedTwin(db, eaten, search.query, ranked, best);
      if (twin != null) {
        best = twin.candidate;
        food = twin.food;
      }
      // A pick below the review gate is likely a wrong food: no detail is
      // fetched for its grams until a person confirms it.
      final fetch = !belowConfidenceGate(best.confidence);
      final (weighedOn, weighed) = await gramsFor(
        db,
        lineProvider,
        food!,
        eaten,
        fetch: fetch,
        recipe: recipe,
      );
      // v39 (Y3): a skin-discarded bone-in part moves to its meat-only
      // record, weighed there (v43: the part's AH-102 meat figure).
      final (gramsFood, resolution) = await skinOffFood(
        db,
        lineProvider,
        recipe,
        eaten,
        weighedOn,
        weighed,
      );
      final meatOnly = gramsFood.fdcId == weighedOn.fdcId ? null : gramsFood;
      final uncached = _foodFromCache(db, gramsFood.fdcId) == null;
      if (uncached) {
        standIns[gramsFood.fdcId] = gramsFood;
      }
      final outcome = engineOutcome(
        recipe,
        eaten,
        gramsFood,
        resolution,
        picked: true,
        confidence: best.confidence,
      );
      // A count of the food the engine cannot weigh is the sub-recipe still —
      // when its FOOD gives no grams. A pick below the gate fetched no detail,
      // so its missing grams say nothing about the food: the row stays the
      // held pick, in `check`, for a person (Run 045: it was zeroed as a
      // confirmed sub-recipe, and nothing surfaced it) — unless its detail
      // was cached already. (A pick over the gate that weighs no count or
      // volume has fetched its detail, so "over the gate" was the same test.)
      final sub = subRecipeOn(outcome.grams, sized: !uncached);
      if (sub != null) {
        write(sub);
        continue;
      }
      final picked = withParts(
        db,
        recipe,
        eaten,
        IngredientMatchRow(
          recipeId: recipe.id,
          position: position,
          raw: line.raw,
          itemKey: key,
          fdcId: meatOnly?.fdcId ?? best.candidate.fdcId,
          description: meatOnly?.description ?? best.candidate.description,
          dataType: meatOnly?.dataType ?? best.candidate.dataType,
          confidence: best.confidence,
          grams: outcome.grams,
          gramSource: outcome.source,
          status: 'auto',
          hold: outcome.hold,
        ),
      );
      await _resolveParts(db, lineProvider, picked);
      write(picked);
    } on NutritionProviderException catch (error) {
      if (identical(lineProvider, cacheOnly)) {
        // No cache holds it yet: the hold stands, no request — derived for
        // these inputs as a decided row's re-read hold is (v36, verifier
        // D2: a held kept row is keyed by `derived_seq`, so an edit never
        // leaves it underived and a cache gain re-opens it).
        if (failed!.derivedSeq != derivedKey && fresh()) {
          db.markDerivedIfUnchanged(
            failed,
            derivedSeq: derivedKey,
            layoutSeq: seq,
            keepRetryCount: true,
          );
        }
        continue;
      }
      if (error is DetailsSuspended) {
        continue; // Never asked: the line's row stands, uncounted.
      }
      if (error is _Escalated) {
        engineUnavailable(position, line, failed, error);
      }
      if (error.scope == FailureScope.global) {
        countFoodFailures();
        rethrow;
      }
      engineUnavailable(position, line, failed, error);
    }
  }

  countFoodFailures();

  // The totals never fetch (RULE A): every food they read — its nutrient
  // record ([nutrientSiblings]) included — was resolved by the derivation
  // that wrote its row (v28: the separate sibling prefetch is gone; a
  // derivation resolves the sibling where it resolves the food).
  // The stamp names the inputs and layout the totals were computed on —
  // never whether the decided rows are derived: that is each row's own
  // fact, read by [nutritionIsFresh] over the rows as they are when it is
  // read (Run 057 S15/O1/O15: `derivedAll`, this compute's snapshot,
  // stamped fresh over a person's underived write during an await).
  recomputeTotals(
    db,
    recipe,
    freshMatch: (layoutSeq: seq, current: fresh),
    standIns: standIns,
    // A line the suspension left unasked: stale, waiting on USDA.
    unavailable: provider.skipped,
    kept: kept,
    ending: marked,
    references: references,
  );
  return failure ??
      (provider.skipped ? provider.suspended : null) ??
      foodFailure;
}

/// Lays [recipe]'s match rows out on its lines ([pairRowsToLines]) in ONE
/// transaction ([SaltDatabase.relayoutIngredientMatches]): a row a line
/// takes moves to that line's position, every other row is deleted (its
/// line is gone, or its ingredient changed). Synchronous, so it lands before
/// any await of its caller: [matchAndCompute], and a person's write
/// (`applyMatchOverride`) — a decision made after a save and before the
/// next compute lands on its line, never on the row another line left at
/// that position; and [applyDecisionToOthers], per target recipe. The
/// pairing reads the version before the save from the texts the last
/// layout kept ([SaltDatabase.layoutOf]: a row-less line is still its line,
/// a row carrying an amount edit's old text reads as its line's), and this
/// layout keeps the new lines' texts and bumps the layout sequence every
/// row write checks — in the same transaction. Writes nothing when the
/// rows are laid out on these same lines. Returns the row each line took,
/// or null.
///
/// Known limit (behaviour change vs v16): engine rows move with their lines
/// and unpaired rows are deleted HERE, so after a provider failure a line
/// the compute did not re-derive has no row (not another line's stale row).
List<IngredientMatchRow?> layoutMatchRows(SaltDatabase db, Recipe recipe) {
  final lines = nutritionLines(recipe);
  final rows = db.ingredientMatchesFor(recipe.id);
  final paired = pairRowsToLines(
    rows,
    lines,
    laidOut: db.layoutOf(recipe.id).lines,
  );
  final kept = {
    for (final row in paired)
      if (row != null) row.position,
  };
  db.relayoutIngredientMatches(
    recipe.id,
    drop: {
      for (final row in rows)
        if (!kept.contains(row.position)) row.position,
    },
    moves: {
      for (final (at, row) in paired.indexed)
        if (row != null && row.position != at)
          row.position: (to: at, itemKey: lineKeyOf(lines[at])),
    },
    lines: [for (final line in lines) line.raw],
  );
  return paired;
}

/// The most layouts [pairRowsToLines] expands before it settles for the
/// best found so far.
const pairingBudget = 10000;

/// The layouts the last [pairRowsToLines] call expanded (at most its
/// budget) — what the tests pin the budget and the bound by, never a clock.
@visibleForTesting
int pairingExpansions = 0;

/// The stored row each of [lines] takes, or null: the cheapest reading of
/// the save as an EDIT SCRIPT of the old lines' texts (in position order;
/// see the body for what is read as old) into the lines' texts, the pairing
/// oracle's semantics: a delete, an insert, a same-ingredient substitution
/// (an amount edit: the row, and its decision, stay with the line) and a
/// move of one line cost one each; a substitution to ANOTHER ingredient is
/// a delete and an insert (two ops; it carries nothing — its row is
/// dropped, the line re-derived; matcher v20, Run 051 O2/S3). Of the
/// cheapest readings, the fewest of a person's decisions dropped; then the
/// fewest rows off their own positions (a layout is its own next layout);
/// then the least distance moved (of twins, the nearest). [_layoutCost]
/// scores a layout in that order.
///
/// EXACT, by a depth-first branch and bound over the lines: each line takes
/// an unused row of its exact text or its ingredient ([lineKeyOf]), a gap,
/// or none, and a branch is cut when a lower bound on its cost (the texts
/// still pairable exactly, the longest in-order chain still possible) is
/// no better than the best layout found. The search starts from the
/// in-order alignment ([_alignRows]), which wins ties, and an unedited list
/// (cost 0) is that alignment alone (one expansion). It expands at most
/// [budget] layouts ([pairingExpansions]), then returns the best found so
/// far — never a row twice, nor a row on a line of another text and
/// ingredient.
///
/// Proven by the multi-op pairing oracle (1..3 edits per save, and its gap
/// mode: two saves with the rows incomplete between them;
/// pairing_oracle_test.dart) and its named scenarios. Known limits:
/// text-only — where identical lines make an edit ambiguous, this is the
/// cheapest reading keeping the most decisions, which may not be what the
/// person did (which twin they deleted); without [laidOut], what the rows
/// cannot show (see the body); and it runs synchronously on every compute,
/// PUT and matches GET, so [budget] is its time bound: a save far past a
/// few edits stops there (measured, JIT, real corpus lines shuffled whole
/// with a quarter rewritten: ~12 ms at 60 lines, ~100 ms (120 ms cold) at
/// 400, the edit service's line cap; a three-edit save of 400 lines ~50 ms
/// in ~3,800 expansions). A RUN of twins (consecutive rows of one text and
/// keys) is ONE item, an ordered multiset: the search decides how many of
/// its rows the lines take and where, never which twin (v29, Run 059
/// O12/S12/S14: v28 still chose a twin per line, and one edit before 50 or
/// more twins spent the whole budget — 400 twins 1.0–4.3 s; now ~800
/// expansions, 20–45 ms; seed 41487's save 4,916 → 2,760); the rows a run
/// gives are its decided ones first, the surplus dropped where the fewest
/// rows leave their own positions (ties: from the end), laid in position
/// order. Twins apart (another line between them) are still distinct rows
/// to the search: 30,000 saves of 11–16 lines over two texts reach the
/// budget once (v28: twice). What it then returns is the best layout
/// found: never a row twice nor a decision on another ingredient; at worst
/// a decision kept on another twin of its line.
List<IngredientMatchRow?> pairRowsToLines(
  List<IngredientMatchRow> rows,
  List<IngredientLine> lines, {
  int budget = pairingBudget,
  List<String>? laidOut,
}) {
  final byPos = {for (final row in rows) row.position: row};
  // The old side of the script is the lines the rows were last laid out on:
  // [laidOut]'s texts when the caller has them, else the rows' own texts.
  // Read from the rows alone, two states mislead (Run 051 S4, the gap
  // fuzz): a row still carrying an amount edit's OLD text reads as that
  // text, not its line's; and a line with no row (a person's write in the
  // stale window, a compute whose gate tripped or that failed) reads as no
  // line at all, so the line it became looks inserted and a row of its
  // text or ingredient slides onto it. Without [laidOut], a position below
  // the last row's with no row is a GAP: a line of unknown text that fits
  // any line and carries nothing (a row-less line after the last row stays
  // unseen).
  final last = max(byPos.keys.fold(-1, max), (laidOut?.length ?? 0) - 1);
  String? textAt(int p) =>
      laidOut != null && p < laidOut.length ? laidOut[p] : null;
  final old = [
    for (var p = 0; p <= last; p++)
      (byPos[p] ??
              IngredientMatchRow(
                recipeId: '',
                position: p,
                raw: '',
                fdcId: null,
                description: null,
                dataType: null,
                confidence: 0,
                grams: null,
                gramSource: null,
                status: 'auto',
              ))
          .copyWith(raw: textAt(p)),
  ];
  final gap = [
    for (var p = 0; p <= last; p++) !byPos.containsKey(p) && textAt(p) == null,
  ];
  final n = old.length;
  final m = lines.length;
  final b = n + m + 1;
  final texts = <String, int>{};
  final lineText = [
    for (final line in lines) texts.putIfAbsent(line.raw, () => texts.length),
  ];
  final rowText = [
    for (final row in old) texts.putIfAbsent(row.raw, () => texts.length),
  ];
  final keys = [for (final line in lines) lineKeyOf(line)];
  // A row's ingredient is its STORED key — the key of the line it was
  // written for, the corpus's curated item included (Run 052 O9: on 51
  // corpus lines the editor's parse of the text gives another key, and an
  // amount edit through the editor keeps the curated item). Its own text's
  // key under THIS matcher stands in only where the stored one is absent,
  // or names the same food by another wording — the same head noun
  // ([headNounOf]): the boot backfill re-keys only rows whose text is still
  // their line's, so a key a matcher bump changed would strand an
  // amount-edited row (Run 051, Opus critic 1 #2). Never a key of another
  // head noun (Run 052 O4: 0132's 'whole bone-in skin-on chicken breast'
  // reads 'whole bone-in' from its text, and a typed turkey-breast line
  // keyed so took the chicken pick): a rewrite whose head noun changes
  // never carries.
  final rowKeys = [
    for (final (i, row) in old.indexed)
      gap[i] ? const <String>{} : _rowKeysOf(row),
  ];
  // A line may take a row of its exact text or its ingredient (an empty key
  // names none), or a gap.
  bool fit(int i, int at) =>
      gap[i] ||
      rowText[i] == lineText[at] ||
      (keys[at].isNotEmpty && rowKeys[i].contains(keys[at]));
  var best = _alignRows(old, lines.length, fit);
  var bestCost = _layoutCost(old, gap, lines, best);
  final fits = [
    for (var at = 0; at < m; at++)
      [
        for (var i = 0; i < n; i++)
          if (fit(i, at)) i,
      ],
  ];
  // TWINS (v29, Run 059 O12/S12/S14 — v28 laid a run in its own order but
  // still chose WHICH twin each line took: one edit before 50 twins spent
  // the whole budget): a run of consecutive old rows with the same text and
  // keys is ONE item — any line one of them fits, the other fits — an
  // ordered multiset. The search decides only how many of a run's rows the
  // lines take and on which lines (a line takes the run's next row in
  // position order, never a chosen twin; the bound reads a run's untaken
  // rows as one block, [extendBlock]); a layout then takes, of the run's
  // rows, its decided ones first and lays them on those lines in position
  // order ([takenOf]; the final layout's surplus is re-chosen where the
  // fewest rows leave their own positions, below). Exact for the script's
  // cost (the rows' texts and keys are the run's; a crossed pair of twins
  // uncrossed is a chain at least as long) and for the decisions lost (the
  // fewest a run giving that many rows can lose), so the search never
  // branches on twins. `runOf[i]`: the first row of i's run.
  final runOf = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    runOf[i] =
        i > 0 &&
            !gap[i] &&
            !gap[i - 1] &&
            rowText[i] == rowText[i - 1] &&
            rowKeys[i].length == rowKeys[i - 1].length &&
            rowKeys[i].containsAll(rowKeys[i - 1])
        ? runOf[i - 1]
        : i;
  }
  // Each run's rows, by its first row; and the rows of a run's lines,
  // given how many lines take it: its decided rows first, then the rest,
  // the surplus dropped from the end, in position order (a leaf's; the
  // best layout's surplus is settled below).
  final members = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    (members[runOf[i]] ??= []).add(i);
  }
  // Each run's first row and its size (by first row), for the bound.
  final runs = [...members.keys];
  final sizeOf = List<int>.filled(n, 0);
  for (final r in runs) {
    sizeOf[r] = members[r]!.length;
  }
  List<int> takenOf(int run, int k) {
    final rows = members[run]!;
    if (k == rows.length) {
      return rows;
    }
    final decided = rows.where((i) => _isDecided(old[i])).length;
    var decidedLeft = min(k, decided);
    var otherLeft = k - decidedLeft;
    return [
      for (final i in rows)
        if (_isDecided(old[i]) ? decidedLeft-- > 0 : otherLeft-- > 0) i,
    ];
  }

  // The runs each line fits, each once (first rows ascending) — [fits]
  // itself when no run has twins (v29 closer, the verifier's D8: the copy
  // cost 1.4 ms a layout on 400 lines one key fits, every PUT).
  final fitRuns = runs.length == n
      ? fits
      : [
          for (final f in fits)
            [
              for (var k = 0; k < f.length; k++)
                if (k == 0 || runOf[f[k - 1]] != runOf[f[k]]) runOf[f[k]],
            ],
        ];
  // The rows each run has given on this branch.
  final taken = List<int>.filled(n, 0);
  // The row each line took on this branch (its run's next, in position
  // order), or null.
  final rowAt = List<int?>.filled(m, null);
  final want = List.filled(texts.length, 0);
  final have = List.filled(texts.length, 0);
  final tails = <int>[];
  // Patience: [row] extends the in-order chains [tails] holds.
  void extend(int row) {
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tails[mid] < row) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == tails.length) {
      tails.add(row);
    } else {
      tails[lo] = row;
    }
  }

  // Patience over the rows [a]..[b] (a run's untaken twins) in decreasing
  // order, as [extend] row by row — in one step: the first chain ending at
  // or past a now ends at a, and each later one up to the first ending at
  // or past b ends one past its predecessor's old end.
  int below(int x) {
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tails[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void extendBlock(int a, int b) {
    if (a == b) {
      extend(a); // One row: one search (the D8 closer: half the bound's).
      return;
    }
    final i0 = below(a);
    final i1 = below(b);
    if (i1 == tails.length) {
      tails.add(0);
    }
    for (var j = i1; j > i0; j--) {
      tails[j] = tails[j - 1] + 1;
    }
    tails[i0] = a;
  }

  // A lower bound on [_layoutCost]'s leading term (the script's cost) for
  // every layout the lines before [at] begin: the rows on a line of their
  // text (each text's rows left against its lines left), and the longest
  // in-order chain — each line before [at] its row, each line left any
  // unused row it fits (patience, largest first: a line adds at most one).
  int bound(int at) {
    var exact = 0;
    for (var j = 0; j < at; j++) {
      if (rowAt[j] case final i? when gap[i] || rowText[i] == lineText[j]) {
        exact++;
      }
    }
    want.fillRange(0, want.length, 0);
    have.fillRange(0, have.length, 0);
    for (var k = at; k < m; k++) {
      want[lineText[k]]++;
    }
    var gaps = 0;
    for (final r in runs) {
      final left = sizeOf[r] - taken[r];
      gap[r] ? gaps += left : have[rowText[r]] += left;
    }
    var left = 0;
    for (var t = 0; t < want.length; t++) {
      left += min(want[t], have[t]);
    }
    exact += min(m - at, left + gaps);
    tails.clear();
    for (var k = 0; k < m; k++) {
      if (k < at) {
        if (rowAt[k] case final i?) {
          extend(i);
        }
      } else {
        // A run's rows are taken in position order on a branch: the ones
        // past those it has given, one block of rows per run.
        final f = fitRuns[k];
        for (var x = f.length - 1; x >= 0; x--) {
          final r = f[x];
          if (taken[r] < sizeOf[r]) {
            extendBlock(r + taken[r], r + sizeOf[r] - 1);
          }
        }
      }
    }
    return n + m - exact - tails.length;
  }

  var nodes = 0;
  void search(int at) {
    if (nodes >= budget) {
      return;
    }
    nodes++;
    if (at == m) {
      final count = <int, int>{};
      for (final i in rowAt.nonNulls) {
        count[runOf[i]] = (count[runOf[i]] ?? 0) + 1;
      }
      final rowsOf = {
        for (final MapEntry(key: r, value: k) in count.entries)
          r: takenOf(r, k).iterator,
      };
      final paired = [
        for (final i in rowAt)
          i == null ? null : old[(rowsOf[runOf[i]]!..moveNext()).current],
      ];
      final cost = _layoutCost(old, gap, lines, paired);
      if (cost < bestCost) {
        best = paired;
        bestCost = cost;
      }
      return;
    }
    if (bound(at) * b * b * b * b >= bestCost) {
      return;
    }
    for (final r in fitRuns[at]) {
      if (taken[r] < sizeOf[r]) {
        rowAt[at] = r + taken[r]++;
        search(at + 1);
        taken[r]--;
      }
    }
    rowAt[at] = null;
    search(at + 1);
  }

  search(0);
  pairingExpansions = nodes;
  // Which of a run's rows the best layout keeps where its lines are fewer
  // than its rows: of the in-order choices losing the fewest decisions,
  // the one moving the fewest rows off their own positions, then the
  // least distance (rows stay put — a layout is its own next layout); a
  // tie keeps the earlier rows (the surplus dropped from the end). One
  // dynamic program per such run over its rows × its lines, once per call.
  final linesOf = <int, List<int>>{};
  for (var at = 0; at < m; at++) {
    if (best[at]?.position case final i?) {
      (linesOf[runOf[i]] ??= []).add(at);
    }
  }
  final settled = [...best];
  for (final MapEntry(key: r, value: ls) in linesOf.entries) {
    final rows = members[r]!;
    final c = rows.length;
    final k = ls.length;
    if (k == c || gap[r]) {
      continue;
    }
    // f[i * (k + 1) + j]: the least (lost, moved, drift), packed, laying
    // rows[i..] on ls[j..].
    const lost = 1 << 40;
    const moved = 1 << 20;
    final f = List<int>.filled((c + 1) * (k + 1), 0);
    for (var i = c; i >= 0; i--) {
      for (var j = k; j >= 0; j--) {
        if (c - i < k - j) {
          f[i * (k + 1) + j] = 1 << 62;
        } else if (i < c) {
          final row = rows[i];
          final skip = c - i > k - j
              ? f[(i + 1) * (k + 1) + j] + (_isDecided(old[row]) ? lost : 0)
              : 1 << 62;
          final take = j < k
              ? f[(i + 1) * (k + 1) + j + 1] +
                    (row == ls[j] ? 0 : moved + (row - ls[j]).abs())
              : 1 << 62;
          f[i * (k + 1) + j] = take <= skip ? take : skip;
        }
      }
    }
    for (var i = 0, j = 0; j < k; i++) {
      final row = rows[i];
      final take =
          f[(i + 1) * (k + 1) + j + 1] +
          (row == ls[j] ? 0 : moved + (row - ls[j]).abs());
      if (take == f[i * (k + 1) + j]) {
        settled[ls[j++]] = old[row];
      }
    }
  }
  if (_layoutCost(old, gap, lines, settled) case final cost
      when cost < bestCost) {
    best = settled;
    bestCost = cost;
  }
  // A run's twins taken in their own order can stand off their own lines
  // where a crossed pair would not (the moved tiebreak: "a layout is its
  // own next layout", Run 052 S12/O12): each twin whose own line holds a
  // twin of its run swaps with it while the layout's cost falls — never
  // the script's cost (uncrossing is exact for it, above), only the moved
  // and drift terms. O(twins off their lines) layouts scored per round.
  for (var improved = true; improved;) {
    improved = false;
    for (var at = 0; at < m; at++) {
      final i = best[at]?.position;
      if (i == null || i == at || i >= m) {
        continue;
      }
      final j = best[i]?.position;
      if (j == null || runOf[j] != runOf[i] || gap[i] || gap[j]) {
        continue;
      }
      final swapped = [...best]
        ..[at] = best[i]
        ..[i] = best[at];
      final cost = _layoutCost(old, gap, lines, swapped);
      if (cost < bestCost) {
        best = swapped;
        bestCost = cost;
        improved = true;
      }
    }
  }
  return [for (final row in best) byPos[row?.position]];
}

/// The keys a stored row fits a line by ([pairRowsToLines]): its stored
/// key, and its own text's when that one is absent or names the same head
/// noun.
Set<String> _rowKeysOf(IngredientMatchRow row) {
  final stored = row.itemKey;
  final own = _keyOfRaw(row.raw);
  if (stored == null || stored.isEmpty) {
    return {own};
  }
  final head = headNounOf(stored);
  return {stored, if (head != null && headNounOf(own) == head) own};
}

/// The ingredient key of a line written [raw] (the editor's parse).
String _keyOfRaw(String raw) {
  if (_rawKeys.length >= _cap(20000)) {
    _rawKeys.clear(); // ponytail: as [lineKeyOf]'s memo.
  }
  return _rawKeys.putIfAbsent(raw, () {
    keyReads++;
    final parsed = parseIngredientLine(raw);
    return lineKeyOf(
      IngredientLine(
        raw: raw,
        amounts: parsed.amounts,
        item: parsed.item,
        prep: parsed.prep,
      ),
    );
  });
}

final Map<String, String> _rawKeys = {};

/// [pairRowsToLines]' seed: the longest in-order alignment of [old] (in
/// position order) to [m] lines, each row on a line it fits ([fit]: of its
/// exact text or its ingredient, or a gap on any line).
List<IngredientMatchRow?> _alignRows(
  List<IngredientMatchRow> old,
  int m,
  bool Function(int i, int at) fit,
) {
  final n = old.length;
  int worth(int i, int at) => fit(i, at) ? 1 : 0;

  // best[i][j]: old[i..] against lines[j..].
  final best = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      best[i][j] = max(
        best[i + 1][j + 1] + worth(i, j),
        max(best[i + 1][j], best[i][j + 1]),
      );
    }
  }
  final paired = List<IngredientMatchRow?>.filled(m, null);
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    final w = worth(i, j);
    if (w > 0 && best[i][j] == best[i + 1][j + 1] + w) {
      paired[j++] = old[i++];
    } else if (best[i][j] == best[i + 1][j]) {
      i++;
    } else {
      j++;
    }
  }
  return paired;
}

/// [paired] (the row each of [lines] took) read as an edit script of [old]
/// (in position order): its cost, then the decisions it drops (the pairing
/// oracle's semantics), then the rows off their own positions, then how far
/// they moved, packed so the smaller is the better. A kept row on a line
/// of its text is free in order and one move out of it; of its ingredient,
/// one substitution (plus the move); every other row is a delete, every
/// other line an insert — a substitution to ANOTHER ingredient is exactly
/// that pair, two ops (matcher v20: v19 counted it one op as written and
/// ranked that ahead of the decisions dropped, so a move + amount edit +
/// delete read as a delete + a cross-ingredient substitution and dropped
/// the moved line's decision).
/// Every op costs one, so the ops as written ARE the cost: no separate term.
/// A gap ([pairRowsToLines]) is a line of unknown text: on any line it is
/// exact.
int _layoutCost(
  List<IngredientMatchRow> old,
  List<bool> gap,
  List<IngredientLine> lines,
  List<IngredientMatchRow?> paired,
) {
  final n = old.length;
  final m = lines.length;
  final b = n + m + 1;
  final index = {for (final (i, row) in old.indexed) row.position: i};
  final rowAt = [for (final row in paired) index[row?.position]];
  final used = {...rowAt.nonNulls};
  var exact = 0;
  for (var at = 0; at < m; at++) {
    if (paired[at] case final row?
        when gap[row.position] || row.raw == lines[at].raw) {
      exact++;
    }
  }
  final lost = [
    for (var i = 0; i < n; i++)
      if (!used.contains(i) && _isDecided(old[i])) i,
  ].length;
  // The kept rows already in order (the longest such chain: every other
  // kept row is one move).
  final inOrder = _lisOf([
    for (final i in rowAt)
      if (i != null) i,
  ]);
  final cost = n + m - exact - inOrder;
  // Last, the rows off their own positions: rows already laid out stay
  // put (a layout is its own next layout); then how far they moved (of
  // twins, the nearest: a pick on the last of two "Salt and pepper" stays
  // on the last when an edit in place made the other).
  var moved = 0;
  var drift = 0;
  for (var at = 0; at < m; at++) {
    if (paired[at] case final row? when row.position != at) {
      moved++;
      drift += (row.position - at).abs();
    }
  }
  return ((cost * b + lost) * b + moved) * b * b + drift;
}

/// The length of the longest strictly increasing run in [seq] (patience).
int _lisOf(List<int> seq) {
  final tails = <int>[];
  for (final x in seq) {
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tails[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == tails.length) {
      tails.add(x);
    } else {
      tails[lo] = x;
    }
  }
  return tails.length;
}

/// [ranked] with, when its top record is a cured one for a line asking for
/// the FRESH food ([freshHoldOf] `cured_for_fresh`), the answer's best
/// uncured, undocked record first — the one sharing the most of the line's
/// words, ties in rank order: "1 (6- to 8-pound) bone-in fresh half ham
/// with skin, preferably shank end, rinsed" (Roast Fresh Ham, 0249) takes
/// "Pork, fresh, leg (ham), shank half, separable lean and fat, raw"
/// (168226) from its own cached answer over the cured rump at 0.50
/// (checkpoint 8, B7). The record keeps its own score, so it stays below
/// the gate for a person.
List<RankedCandidate> freshOverCured(
  String raw,
  List<RankedCandidate> ranked,
) {
  if (ranked.isEmpty ||
      freshHoldOf(raw, ranked.first.candidate.description) !=
          'cured_for_fresh') {
    return ranked;
  }
  Set<String> words(String text) => RegExp(
    '[a-z]{3,}',
  ).allMatches(text.toLowerCase()).map((m) => m[0]!).toSet();
  final own = words(raw);
  RankedCandidate? best;
  var shared = 0;
  for (final candidate in ranked) {
    final description = candidate.candidate.description;
    if (candidate.docked || freshHoldOf(raw, description) != null) {
      continue;
    }
    final n = words(description).intersection(own).length;
    if (n > shared) {
      best = candidate;
      shared = n;
    }
  }
  return best == null
      ? ranked
      : [
          best,
          for (final c in ranked)
            if (!identical(c, best)) c,
        ];
}

/// v54 (batch M56 R2, prep48 design_v2 §2): [ranked] with, when its top is
/// a "separable lean only" record for a line that does not ask for lean
/// (`lean`, "trimmed of all fat", "all visible fat"), the top's EXACT
/// lean-and-fat sibling in the same answer first — its description with
/// "lean only" read as "lean and fat" or "lean and fat only" (FDC writes
/// both), case and spacing folded — carrying the top's confidence: the same
/// cut, trim and grade — what separates them is the sibling's extra
/// words ("and fat", 0.008 on the SR blade-end pork pair) or Foundation's
/// data-type bonus (the eye round, 0.046). The owner's tie-break ("the
/// cut's lean-and-fat record over 'lean only'", `tieRank`) read past an
/// exact tie: "1 (2½-pound) boneless blade-end pork loin roast"
/// (maple-glazed-pork-roast|4) 169194 → 168381.
/// After [freshOverCured]; rank-as (R1) has already chosen the answer, so
/// R1c's strip steaks never reach here on 746759.
List<RankedCandidate> leanAndFatSibling(
  String raw,
  List<RankedCandidate> ranked,
) {
  if (ranked.isEmpty) {
    return ranked;
  }
  String fold(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final top = fold(ranked.first.candidate.description);
  if (!top.contains('separable lean only') ||
      RegExp(
        r'\blean\b|trimmed of all fat|all visible fat',
      ).hasMatch(raw.toLowerCase())) {
    return ranked;
  }
  final siblings = {
    top.replaceFirst('lean only', 'lean and fat'),
    top.replaceFirst('lean only', 'lean and fat only'),
  };
  for (final candidate in ranked.skip(1)) {
    if (siblings.contains(fold(candidate.candidate.description))) {
      return _movedFirst(ranked, candidate);
    }
  }
  return ranked;
}

/// v54 (batch M56 R3, prep48 design_v2 §2): a trim the line PRINTS that its
/// record does not name, read on the cached record that does — record-keyed
/// (phrase → {top's record → target}), the target a hit in the line's own
/// answer, so zero requests (never a [skinOffFood] entry, which fetches a
/// detail). "fat trimmed to ⅛ to ¼ inch, rib bones frenched" (roast-rack-
/// of-lamb|0): NZ 172641 "rack - fully frenched" → Australian 174414 "rib
/// chop/rack roast, frenched, bone-in, …, trimmed to 1/8" fat, raw", the
/// only cached raw frenched rack at a stated depth (¼ inch reads USDA's
/// deepest, 1/8"; origin and frenching differ too — design §7, F11), its
/// AH-102 yield keyed in [ah102Meats]. Q7: "fat caps removed" (ultimate-
/// charcoal-grilled-steaks|0) on R1c's 2727572 → 171751 "top loin steak,
/// boneless, lip off, …, trimmed to 0" fat, choice, raw".
/// v66 (batch M68 R-A; prep49 design_v2 §2 M68, the owner's Q1 (a) for the
/// WHOLE brisket, 2026-10-09): the whole brisket's lean-only 168607 →
/// 168664 "Beef, brisket, whole, separable lean and fat, trimmed to 1/8"
/// fat, all grades, raw" (barbecued-whole-beef-brisket|10, a hit in the
/// line's own 'whole beef brisket' answer; ⅛" is the deepest brisket trim
/// USDA publishes). The FLAT (168743, braised-brisket-with-pomegranate|0)
/// waited for L49: USDA's flat pairs render 41–51 % of the fat.
/// v68 (batch M70; prep49 design_v2 §2 M70, the owner's Q1 flat (b′)): the
/// flat's 0" 168743 → SR 173128 "Beef, brisket, flat half, separable lean
/// and fat, trimmed to 1/8" fat, choice, raw" (a hit in the line's own
/// 'beef brisket' answer, index 19), its energy at USDA's same-cut,
/// same-trim braised pair's share ([braisedEnergyShare]).
final List<(RegExp, Map<int, int>)> trimDepthRecords = [
  (
    RegExp('fat trimmed to (⅛|¼)( to (⅛|¼))? inch'),
    {172641: 174414, 168607: 168664, 168743: 173128},
  ),
  (RegExp('fat caps? removed'), {2727572: 171751}),
];

/// v68 (batch M70; prep49 design_v2 §2 M70, the owner's Q1 flat (b′), on
/// live step L49's read): the share of a raw record's energy its braise
/// keeps — USDA's raw/braised pair of the SAME cut, trim and grade by the
/// protein tracer: 173128 → SR 173130 "Beef, brisket, flat half, separable
/// lean and fat, trimmed to 1/8" fat, choice, cooked, braised" (P 18.1 →
/// 28.7, E 278 → 298, both cached hits): yield 18.1 / 28.7 = 0.6307, e =
/// 298 × 0.6307 / 278 = 0.6760 — the separable fat the steps skim (fat
/// kept 55.4 %; the lean-only flat pair keeps all its energy). Applied in
/// [recomputeTotals] beside Q25's alcohol, ENERGY only, only where
/// [trimStandInFlagOf] flags the line (one raw test: the flag and the
/// deduction never part); the row's grams and kcal column stay gross.
/// ponytail: one pair; a second braised cut needs its own same-cut pair.
const Map<int, double> braisedEnergyShare = {
  173128: 298 * 18.1 / (28.7 * 278),
};

/// [ranked] with [trimDepthRecords]' target first when the line prints its
/// phrase and the top is its key; after [leanAndFatSibling].
List<RankedCandidate> trimDepthRecord(
  String raw,
  List<RankedCandidate> ranked,
) {
  if (ranked.isEmpty) {
    return ranked;
  }
  final line = raw.toLowerCase();
  for (final (phrase, pairs) in trimDepthRecords) {
    final target = pairs[ranked.first.candidate.fdcId];
    if (target == null || !phrase.hasMatch(line)) {
      continue;
    }
    for (final candidate in ranked.skip(1)) {
      if (candidate.candidate.fdcId == target) {
        return _movedFirst(ranked, candidate);
      }
    }
  }
  return ranked;
}

/// [ranked] with [moved] first, carrying the top's confidence (R2, R3).
List<RankedCandidate> _movedFirst(
  List<RankedCandidate> ranked,
  RankedCandidate moved,
) => [
  RankedCandidate(
    candidate: moved.candidate,
    confidence: ranked.first.confidence,
    docked: moved.docked,
  ),
  for (final c in ranked)
    if (!identical(c, moved)) c,
];

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
  final rule = secondFoodRuleOf(line, recipe: recipe);
  if (rule == null) {
    return null;
  }
  final target =
      knownFood(db, rule.fdcId, line: line) ??
      await _cachedFood(db, provider, rule.fdcId);
  if (target == null) {
    return null;
  }
  // v49 (M47 Q6): a two-part rule's second record, fetched once like the
  // rule's own ([withParts] reads it from the caches).
  if (rule.second case final second?
      when knownFood(db, second.fdcId, line: line) == null) {
    await _cachedFood(db, provider, second.fdcId);
  }
  final outcome = engineOutcome(recipe, line, target, null, picked: true);
  return (
    food: target,
    row: withParts(
      db,
      recipe,
      line,
      IngredientMatchRow(
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
  List<Amount> amounts,
) =>
    withoutPortions?.source == GramSource.weight &&
    (food.dataType == 'SR Legacy' &&
            ((edibleYieldOn && buysRefuse(raw)) ||
                (cannedDrained && drainsCan(raw)) ||
                (wholeBirdYieldOn && countsGameHens(raw))) ||
        // v39 (Y2): FNDDS's "1 lobster" portion.
        buysLiveLobsters(raw) ||
        // v39 (A3): a counted item peeled after its printed weight, by the
        // record's own "Peeled" portion — published only by Foundation's
        // bananas (1105314, 1105073) among the cached details.
        (food.dataType == 'Foundation' &&
            countOf(amounts) != null &&
            peeledAfterItem(raw)));

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
  Recipe? recipe,
}) async {
  GramResolution? resolve(FdcFood on) =>
      lineGrams(db, line, on, recipe: recipe);
  final resolution = resolve(food);
  final portions = _needsPortions(line.amounts, resolution);
  if (!fetch ||
      (!portions &&
          !_weightReadsPortions(line.raw, food, resolution, line.amounts))) {
    return (food, resolution);
  }
  final detail = await _cachedFood(db, provider, food.fdcId);
  if (detail == null) {
    db.fdcFoodCachePut(food.fdcId, jsonEncode(food.toJson()));
    _unholdOn(db, [food.fdcId]);
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
  // v68 (M70): a fine-cut sibling's detail ([fineCutSiblings]), fetched
  // once by the first volume line on its record — never a cache's luck.
  final cut = fineCutSiblings[detail.fdcId];
  if (cut != null &&
      _foodFromCache(db, cut) == null &&
      volumeMlOf(line.amounts) != null) {
    await _cachedFood(db, provider, cut);
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
  FdcFood? food, {
  Recipe? recipe,
}) {
  // The grams tables match on the line's own words, not the key.
  final normalized = normalizeItem(lineItemOf(line));
  // v68 (M70, Q13 G2): a section's reserved giblets, off the host's bird.
  if (recipe != null) {
    if (hostWeighedGiblets(db, recipe, line, normalized) case final g?) {
      return g;
    }
  }
  // v43 (Y13): the RECORD decides the meat share ([ah102Records]); the
  // recipe's skin trip only names the part a meat-only whole bird keeps
  // its skin on — with no recipe, none.
  final skinOff = recipe != null && skinDiscarded(recipe, line);
  final skinKept = skinOff ? skinKeptPart(recipe, line) : null;
  // v49 (M47 Q11): a recipe that eats the shell reads no AH-102 shell row;
  // (Q14 (i)) one whose steps add a can with its liquid keeps it whole.
  final shellEaten = recipe != null && shellEatenIn(recipe);
  final canLiquidEaten = recipe != null && canLiquidEatenIn(recipe, line);
  // v59 (M60 P7a): a produce line whose steps pare it ([stepsPeelIn]).
  final stepsPeel =
      recipe != null &&
      produceYields.containsKey(food?.fdcId) &&
      stepsPeelIn(recipe, line);
  GramResolution? on(FdcFood? record) => resolveGrams(
    amounts: line.amounts,
    food: record,
    normalizedItem: normalized,
    raw: line.raw,
    skinOff: skinOff,
    skinKept: skinKept,
    shellEaten: shellEaten,
    canLiquidEaten: canLiquidEaten,
    stepsPeel: stepsPeel,
  );
  if (food != null && freshHerbLine(line.raw, food.description)) {
    return _freshHerbGrams(line, food, normalized, on(food));
  }
  // v68 (M70, pE Q6): a fine-cut volume on a [fineCutSiblings] record
  // weighs on its cached sibling's chopped portion — the line's food stays.
  final cutId = food == null ? null : fineCutSiblings[food.fdcId];
  final cutSibling = cutId == null ? null : _foodFromCache(db, cutId);
  final fine = cutSibling == null
      ? null
      : fineCutWeighing(food!, cutSibling, line.raw, line.amounts);
  if (fine != null) {
    if (on(fine.food) case final grams?) {
      return GramResolution(
        grams: grams.grams,
        source: grams.source,
        basis: '${grams.basis} · ${fine.note}',
      );
    }
  }
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

/// A fresh herb line on its dried spice record ([freshHerbLine]) sized as
/// the user ruled on 2026-09-28 (Q2): the dried amount the line offers
/// ("1 tablespoon minced fresh oregano or 1 teaspoon dried", Albóndigas en
/// Chipotle, 1208) on the record; else a fresh VOLUME at one third (the
/// corpus's own fresh-to-dried ratio: that same line); fresh leaves by
/// count ("12 whole fresh sage leaves", Chicken Canzanese, 0422) 0 g
/// unmeasured, like a sprig. A weight or a sprig stays as [own] reads it.
GramResolution? _freshHerbGrams(
  IngredientLine line,
  FdcFood food,
  String normalized,
  GramResolution? own,
) {
  final dried = RegExp(
    '\\bor\\s+([\\d$vulgarFractionChars/]+(?: +[\\d$vulgarFractionChars/]+)*)'
    r'\s*(teaspoons?|tablespoons?)\s+dried\b',
    caseSensitive: false,
  ).firstMatch(line.raw);
  final written = dried == null
      ? null
      : resolveGrams(
          amounts: [
            Amount(
              measure: Measure.volume,
              quantity: dried[1]!.trim(),
              unit: dried[2]!.toLowerCase().replaceAll(RegExp(r's$'), ''),
              primary: true,
            ),
          ],
          food: food,
          // The record's own portions: the line's words would read the
          // density table's 'dried oregano' for one of the two lines only.
          normalizedItem: '',
        );
  if (written != null) {
    return GramResolution(
      grams: written.grams,
      source: written.source,
      basis: 'the dried amount the line offers: ${written.basis}',
    );
  }
  final leaves = line.amounts.where(
    (a) => a.measure == Measure.count && (a.unit ?? '').isEmpty,
  );
  if (leaves.isNotEmpty && RegExp(r'\b(leaf|leaves)\b').hasMatch(normalized)) {
    return GramResolution(
      grams: 0,
      source: GramSource.unmeasured,
      basis:
          '${leaves.first.quantity} leaves — a fresh leaf is not measured, '
          'counted as 0 g',
    );
  }
  if (own == null || own.grams <= 0 || own.source == GramSource.weight) {
    return own;
  }
  return GramResolution(
    grams: own.grams / 3,
    source: own.source,
    basis: '${own.basis} × ⅓ (a fresh volume on the dried record)',
  );
}

/// A person's call on a row: anything but the engine's own `auto`,
/// `unmatched` and rule rows ([isEngineRuleRow] — a sub-recipe, water,
/// equipment or seasoning row the engine confirmed itself, which it
/// rewrites when its rule changes; matcher v14).
/// Whether [row] is a person's decision (confirmed, overridden, skipped;
/// never the engine's own rule row).
bool isDecidedRow(IngredientMatchRow row) => _isDecided(row);

bool _isDecided(IngredientMatchRow row) =>
    row.status != 'auto' && row.status != 'unmatched' && !isEngineRuleRow(row);

/// Recomputes the stored per-serving totals from the persisted matches —
/// instant and CACHE-ONLY (v27, RULE A: no provider call, so no parameter
/// for one — the compute is the one fetcher, and every other caller, the
/// serving-basis route, a person's write, an apply-to-all target, is
/// arithmetic over what is stored). [standIns] are the foods a fresh match
/// built from search hits (never cached); otherwise a food is read from
/// fdc_food_cache, else the line's cached search hit ([knownFood]). A row
/// whose food no cache holds is left out, and is UNDERIVED — a decided row
/// loses its `derived_seq` (the next compute derives it, fetching), an
/// engine row's recipe is stamped stale (the next compute re-matches it) —
/// the same outcome whether FDC failed or answered "no such food" (Run 057
/// Opus critics 2 and 3: the 404 arm stamped fresh, the outage arm made a
/// serving-basis change drop a food and turn the recipe stale). A decided
/// row held `food_gone` or `food_unavailable` is held: left out, nothing to
/// derive. [kept]: the compute's engine rows kept through a FOOD failure
/// (v36) — left out as a decided row is, never stamping the recipe waiting
/// on USDA (their `retry_count` reads it stale). With [missing], a food no
/// cache holds is added to it and NOTHING
/// is written (false): a plain recompute's caller resolves them first
/// ([recomputeTotalsResolving], v28) — the totals read only what a
/// derivation resolved. True when written (or the recipe is gone).
bool recomputeTotals(
  SaltDatabase db,
  Recipe recipe, {
  int? servingBasis,
  ({int layoutSeq, bool Function() current})? freshMatch,
  Map<int, FdcFood> standIns = const {},
  ({Recipe recipe, String hash})? hashed,
  Set<int>? missing,
  bool unavailable = false,
  Set<int> kept = const {},
  bool ending = false,
  ResolverMemo? references,
}) {
  // The totals and the stamp are read in ONE synchronous pass over the
  // STORED recipe and its rows (Run 053 O4): a plain recompute carries the
  // stored stamp, so totals built from a Recipe its caller read before an
  // await (an apply-to-all target, the serving-basis route) would sit under
  // a newer compute's fresh stamp.
  final now = nutritionRecipeOf(db, recipe.id)?.recipe;
  if (now == null) {
    return true; // Deleted meanwhile: its rows cascaded away (Run 051 B6).
  }
  final children = references ?? ResolverMemo(db);
  FdcFood? food(int fdcId, {IngredientLine? line}) =>
      standIns[fdcId] ?? knownFood(db, fdcId, line: line);
  // Rows whose food no cache holds (RULE A): a decided row's position,
  // its derivation cleared; an engine row's, the stamp stale.
  final underived = <int>[];
  var engineMissing = false;

  final lines = nutritionLines(now);
  // Rows beyond the current line count are orphans from an edit — they
  // must not contribute (matchAndCompute deletes them; a recompute
  // between the edit and the next full match must ignore them).
  final matches = db
      .ingredientMatchesFor(recipe.id)
      .where((row) => row.position < lines.length)
      .toList();
  // v53 (M52): the coat budget and the frying-oil uptake on the rows it
  // weighs ([_m52Plan], [_m52Weighs]: the engine's and a person's confirm
  // with no grams typed — verify2 D1), re-read from the rows as they are
  // on every path that totals the recipe — a compute, a person's write, an
  // apply-to-all target — and written with the totals (never without them,
  // [missing]); a row kept through a FOOD failure keeps its count.
  // Read on the caller's instance when it is the stored recipe (its step
  // index is built already — RULE C: one index per request).
  final m52 = _m52Plan(
    db,
    recipe == now ? recipe : now,
    matches,
    (id, line) => food(id, line: line),
  );
  final m52Writes = <(IngredientMatchRow, {IngredientMatchRow over})>[];
  for (final (k, row) in matches.indexed) {
    final plan = m52[row.position];
    if (plan == null || kept.contains(row.position) || !_m52Weighs(row)) {
      continue;
    }
    // v60 (M62 H): the engine's dip of a coat held with no budget takes
    // the coat's hold; a person's confirm, 0 g poured away (below).
    if (plan.held && row.status == 'auto') {
      if (row.hold != 'coating' ||
          row.grams != null ||
          row.gramSource != null) {
        matches[k] = row.copyWith(
          hold: 'coating',
          clearGrams: true,
          clearGramSource: true,
        );
        m52Writes.add((matches[k], over: row));
      }
      continue;
    }
    if (row.hold == null &&
        row.gramSource == GramSource.discarded.name &&
        row.grams == plan.grams) {
      continue;
    }
    matches[k] = row.copyWith(
      grams: plan.grams,
      gramSource: GramSource.discarded.name,
      clearHold: true,
    );
    m52Writes.add((matches[k], over: row));
  }
  final totals = <String, double>{};
  var totalGrams = 0.0;
  var contributing = 0;
  var accounted = 0;
  void add(FdcFood record, double grams) {
    for (final def in nutrientDefs) {
      for (final number in def.fdcNumbers) {
        final per100 = record.nutrientsPer100g[number];
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
      record.nutrientsPer100g.containsKey,
    );
    if (!hasEnergy) {
      totals['energy'] =
          (totals['energy'] ?? 0) + kcalPer100g(record) * grams / 100;
    }
  }

  for (final row in matches) {
    if (row.status == 'skipped') {
      accounted += 1;
      continue;
    }
    // v41 (F5, N3): a reference line no recipe counts — held
    // `choose_recipe` or `nested_recipe`, whatever its status (a person's
    // nested pick, a decided row whose child is gone): neither accounted
    // nor contributing, as the bucket reads it ([recipeChoiceHolds]). A
    // confirmed marinade (`discarded_recipe`) is poured away: below.
    if (recipeChoiceHolds.contains(row.hold)) {
      continue;
    }
    // v41 (R1): a routed row counts its child's batch totals × its share,
    // its grams LIVE (the child's total grams × the share, F10 — never the
    // stored display grams); accounted only when the child is complete. A
    // child with no nutrition row (or gone): a decided row is underived, an
    // engine row's recipe stale — never FDC's [missing] (F6).
    if (row.childRecipeId case final childId?) {
      // The compute's memo: its child read once with the row it wrote (F14).
      final child = children.childNutrition(childId);
      final share = row.childShare;
      if (child == null) {
        if (_isDecided(row)) {
          underived.add(row.position);
        } else {
          engineMissing = true;
        }
        continue;
      }
      if (share == null) {
        continue;
      }
      for (final MapEntry(:key, :value) in batchTotalsOf(child).entries) {
        totals[key] = (totals[key] ?? 0) + value * share;
      }
      totalGrams += (child.totalGrams ?? 0) * share;
      contributing += 1;
      if (child.status == 'complete') {
        accounted += 1;
      }
      continue;
    }
    if (row.fdcId == null) {
      // Water-like confirmed rows count as fully accounted zeros. A
      // sub-recipe the engine did not route (v41 R3, A3 a: a section, no
      // amount, no share) is not: its recipe reads partial — but a dish
      // served with it (v52, M51 Q8: rule SW and D7) is accounted, as water.
      if (row.status == 'confirmed' &&
          (row.description != subRecipeNote ||
              (lines[row.position].raw == row.raw &&
                  resolveReference(
                        db,
                        now,
                        lines[row.position],
                        children,
                      ).kind ==
                      ReferenceKind.servedWith))) {
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
    // The eaten part of a "plus" medium ("1 cup plus 2 teaspoons table
    // salt", the 2 teaspoons rubbed on the pork) counts like any line.
    final engineZero =
        grams <= 0 &&
        row.hold != 'unnamed_food' &&
        (row.gramSource == GramSource.discarded.name ||
            row.gramSource == GramSource.unmeasured.name);
    // Held for review: a low-confidence auto match is likely the WRONG
    // food, so it stays out of the totals — a bad match must never silently
    // feed the label. It still surfaces in the review sheet ("check
    // match"); confirming or re-picking it (status leaves 'auto') opts it
    // back in. The recipe also stays "partial" until then, since the line
    // is not yet accounted. A [IngredientMatchRow.hold] reason holds a row
    // the same way.
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
    if (noRecordHolds.contains(row.hold)) {
      continue; // Held: FDC serves no such food (derived to the hold).
    }
    // v41 (R2, rule B1): a rendered row counts its parts, each on its own
    // record ([withRenderedBacon]) — never under grams a person typed.
    if (row.parts != null && row.gramSource != GramSource.override.name) {
      final parts = [
        for (final part in partsOf(row.parts))
          (
            part: part,
            record: switch (food(part.fdcId, line: lines[row.position])) {
              null => null,
              final own => switch (nutrientSiblings[part.fdcId]) {
                null => own,
                final sibling => food(sibling),
              },
            },
          ),
      ];
      final gone = parts.where((p) => p.record == null).toList();
      if (gone.isNotEmpty) {
        for (final p in gone) {
          missing?.add(p.part.fdcId);
        }
        if (_isDecided(row)) {
          underived.add(row.position);
        } else if (!kept.contains(row.position)) {
          engineMissing = true;
        }
        continue;
      }
      accounted += 1;
      contributing += 1;
      totalGrams += grams;
      for (final p in parts) {
        add(p.record!, p.part.grams);
      }
      continue;
    }
    final own = food(row.fdcId!, line: lines[row.position]);
    final sibling = nutrientSiblings[row.fdcId];
    final record = sibling == null || own == null ? own : food(sibling);
    if (record == null) {
      missing?.add(own == null ? row.fdcId! : sibling!);
      if (_isDecided(row)) {
        underived.add(row.position);
      } else if (!kept.contains(row.position)) {
        engineMissing = true;
      }
      continue;
    }
    accounted += 1;
    contributing += 1;
    totalGrams += grams;
    add(record, grams);
    // Q25 (v54): an alcohol line keeps the share of its ethanol energy its
    // cooking keeps (USDA R6, [alcoholRetentionOf]); its grams, its record
    // and every other nutrient count as they are (design_q25_v2 §1.2).
    if (alcoholRetentionOf(
          recipe == now ? recipe : now,
          lines[row.position],
          row,
        )
        case final kept?) {
      totals['energy'] =
          (totals['energy'] ?? 0) -
          ethanolKcalPer100g(record) * grams / 100 * (1 - kept.kept / 100);
    }
    // v68 (M70, Q1 flat (b′)): a braised cut keeps its braised pair's share
    // of the energy ([braisedEnergyShare]) — only on a line its flag reads
    // ([trimStandInFlagOf]); its grams, its record and every other nutrient
    // count as they are (Q25's shape; a person's typed grams too).
    if (braisedEnergyShare[row.fdcId] case final e?
        when trimStandInFlagOf(lines[row.position].raw, row.fdcId) != null) {
      totals['energy'] =
          (totals['energy'] ?? 0) - kcalPer100g(record) * grams / 100 * (1 - e);
    }
  }

  // Read in the same pass (Run 051 B7): a save of its serves meanwhile is
  // the basis the totals are stamped under.
  final stored = db.nutritionFor(recipe.id);
  // Servings first; then the recipe's YIELD count as an editable default so
  // 'MAKES ABOUT 16 LARGE COOKIES' still lands per-cookie rather than
  // reporting one 16-cookie batch as a serving. A yield is not a serving
  // count (that is why it never reaches Recipe.serves) — it is only a
  // better starting basis than the whole batch, and the admin can override.
  // A section key (v44, P3 §3.4) is per batch: it has no serving basis of
  // its own (never its host's serves, never its yield measure's count).
  var basis = hostOf(recipe.id) != recipe.id
      ? 1
      : servingBasis ??
            stored?.servingBasis ??
            now.serves?.min ??
            parseYieldCount(now.servings)?.min ??
            1;
  if (basis < 1) {
    basis = 1; // Hand-edited YAML can carry serves 0.
  }
  final perServing = _perServingOf(totals, basis);
  final calories = perServing['energy']?['amount'] as double?;
  final status = accounted >= lines.length ? 'complete' : 'partial';
  // Only a full re-match may stamp the current recipe's hash — a plain
  // recompute (serving basis, match override) after an ingredient edit
  // must keep reporting `stale` until the admin recomputes for real. A
  // re-match superseded by a save of the recipe's inputs mid-compute
  // (its row writes stopped there) stamps no hash at all: stale, whatever
  // the stored recipe now reads, so the next sweep revisits it. Neither
  // does a plain recompute of a recipe never stamped (a person's write
  // before any compute, or after a first compute that failed mid-way: Run
  // 051 B4 — it read fresh with one row for 19 lines, and no bulk scope
  // revisited it).
  // The stamp also names the layout the totals were computed on
  // ([nutritionIsFresh]; Run 052 O1/S2: a save, a person's write laying the
  // rows out for it and a revert hash as before), and no stamp is fresh
  // with a line that has no row: its food is missing from the totals. A
  // re-match's gate ([freshMatch]'s `current`: the compute's own inputs and
  // layout) is read HERE, after this function's awaits and with none
  // between it and the write — a save or a layout during them stamps stale.
  // [missing] given and a food missing: nothing written — the caller
  // resolves them first ([recomputeTotalsResolving]).
  if (missing != null && missing.isNotEmpty) {
    return false;
  }
  final rowless =
      {
        for (final row in matches) row.position,
      }.length <
      lines.length;
  // The current inputs' hash, once ([hashed] when it is still the stored
  // recipe's).
  late final currentHash = hashed != null && hashed.recipe == now
      ? hashed.hash
      : ingredientsHashOf(now, children);
  final (stampHash, stampSeq) = switch (freshMatch) {
    // A re-match whose suspension ([onePass]) left a line with no row
    // stamps it waiting on USDA (below), never as changed inputs.
    _ when rowless && !(unavailable && freshMatch != null) => ('', null),
    // A plain recompute keeps the stamp only on the inputs it was
    // stamped on (Run 054 O3: totals of an edited recipe under the old
    // stamp read fresh again after a revert).
    // [hashed]: the caller's own hash of the recipe it read (a person's
    // PUT), reused while the stored recipe still equals it — one hash of
    // the whole recipe per request, not two (v27 closer, the verifier's
    // D11: plus-real's PUT paid ~8 ms for the second).
    null
        when stored != null &&
            (stored.ingredientsHash == currentHash ||
                stored.ingredientsHash == unavailableStampOf(currentHash)) =>
      (stored.ingredientsHash, stored.layoutSeq),
    null => ('', null),
    (:final layoutSeq, :final current) =>
      current() ? (ingredientsHashOf(recipe, children), layoutSeq) : ('', null),
  };
  // A food these totals could not count (an engine row's no cache holds,
  // [unavailable]: an apply-to-all target FDC could not weigh) stamps the
  // inputs STALE as waiting on USDA, never as changed (v29, Run 059 O23):
  // [unavailableStampOf] the hash — no current hash equals it, and the
  // page's `stale_reason` reads `underived`.
  // M52's rows land with the totals, at the layout read here (no await
  // between), while a re-match's inputs are still its own.
  if (m52Writes.isNotEmpty && (freshMatch == null || freshMatch.current())) {
    final seq = db.layoutSeqOf(recipe.id);
    for (final (row, :over) in m52Writes) {
      // A person's confirm ([_m52Weighs]) is derived as [derivedFor] derives
      // it, written only while it is still the row read (its decision
      // untouched: the grams of a confirm are the engine's, RULE A).
      if (row.status == 'auto') {
        db.upsertIngredientMatchIfUndecided(row, layoutSeq: seq);
      } else {
        db.replaceIngredientMatchIfUnchanged(row, over: over, layoutSeq: seq);
      }
    }
  }
  final (hash, layoutSeq) =
      (engineMissing || unavailable) &&
          stampHash.isNotEmpty &&
          !stampHash.startsWith(_unavailableStamp)
      ? (unavailableStampOf(stampHash), null)
      : (stampHash, stampSeq);
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
    layoutSeq: layoutSeq,
    totalsJson: jsonEncode(totals),
    underived: underived,
    ending: ending,
  );
  _log.info(
    'Nutrition for ${recipe.id}: $status, '
    '$contributing/${lines.length} lines, '
    '${calories?.toStringAsFixed(0) ?? '?'} kcal/serving (basis $basis)',
  );
  return true;
}

/// The stamp of totals that could not count a food FDC cannot serve now,
/// on inputs hashed [hash] ([recomputeTotals]): stale, and read as waiting
/// on USDA (`stale_reason: underived`) while the inputs are still [hash].
String unavailableStampOf(String hash) => '$_unavailableStamp$hash';

const String _unavailableStamp = 'unavailable:';

/// A PLAIN recompute ([recomputeTotals]: a person's PUT, an apply-to-all
/// target) whose totals would meet the WRITTEN line's food — or its
/// nutrient record ([nutrientSiblings]) — no cache holds resolves it first
/// (RULE A v28, Run 058 S2/S3), and ONLY it (v29, Run 059 S13: [only], the
/// line's food and its sibling — at most two requests through the pass's
/// memo, the first GLOBAL failure stopping them; v28 asked once per
/// uncached food in the recipe, 400 requests for one PUT). Every other row
/// whose food no cache holds stays out of the totals, UNDERIVED (a decided
/// row's `derived_seq` cleared, an engine row's recipe stamped waiting on
/// USDA): the recipe reads stale and the sweep derives them. [unavailable]:
/// the caller left a food unweighed ([recomputeTotals]). [ending]: the
/// caller's in-progress mark, released by the totals' write
/// ([SaltDatabase.markComputing]).
Future<void> recomputeTotalsResolving(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe, {
  required Set<int> only,
  ({int layoutSeq, bool Function() current})? freshMatch,
  ({Recipe recipe, String hash})? hashed,
  bool unavailable = false,
  bool ending = false,
}) async {
  final missing = <int>{};
  if (recomputeTotals(
    db,
    recipe,
    freshMatch: freshMatch,
    hashed: hashed,
    missing: missing,
    unavailable: unavailable,
    ending: ending,
  )) {
    return;
  }
  for (final fdcId in missing.intersection(only)) {
    try {
      await _cachedFood(db, provider, fdcId);
    } on NutritionProviderException catch (error) {
      _log.info('totals of ${recipe.id}: food $fdcId unavailable: $error');
      if (error.scope == FailureScope.global) {
        break;
      }
    }
  }
  recomputeTotals(
    db,
    recipe,
    freshMatch: freshMatch,
    hashed: hashed,
    unavailable: unavailable,
    ending: ending,
  );
}

/// The foods a row on [fdcId] reads: the food and its nutrient record
/// ([nutrientSiblings]) — what a person's write may resolve
/// ([recomputeTotalsResolving]'s `only`).
Set<int> foodsOf(int? fdcId) => {
  ?fdcId,
  if (nutrientSiblings[fdcId] case final sibling?) sibling,
};

/// The per-serving label of the per-recipe [totals] (nutrient key -> total)
/// divided by [basis]: each amount to 2 places, its %DV to 1.
Map<String, Map<String, Object?>> _perServingOf(
  Map<String, double> totals,
  int basis,
) => {
  for (final def in nutrientDefs)
    if (totals[def.key] case final total?)
      def.key: {
        'label': def.label,
        'amount': double.parse((total / basis).toStringAsFixed(2)),
        'unit': def.unit,
        if (def.dailyValue != null)
          'dv_percent': double.parse(
            (total / basis / def.dailyValue! * 100).toStringAsFixed(1),
          ),
      },
};

/// The serving-basis route's write (v27 closer, RULE A — the verifier's
/// D1, Run 057 Opus critic 3): PURE ARITHMETIC over the stored per-recipe
/// totals — the label is those totals divided by [servingBasis], written at
/// once. No row is read or written, no food is read (so no cache miss can
/// drop one), no `derived_seq` cleared, and the stamp, status, counts and
/// grams stay exactly as the last compute left them: a basis change never
/// turns a fresh recipe stale or a complete one partial. A row written
/// before migration 015 has no stored totals: its per-serving amounts times
/// its stored basis stand in (rounded to 2 places per serving — ponytail:
/// a drift of at most 0.005 × basis until the next compute stores the
/// totals; every stamp is recomputed after the v27 upgrade anyway).
void rebaseNutrition(SaltDatabase db, String recipeId, int servingBasis) {
  final stored = db.nutritionFor(recipeId);
  if (stored == null) {
    return;
  }
  final totals = batchTotalsOf(stored);
  final perServing = _perServingOf(totals, servingBasis);
  db.rebaseRecipeNutrition(
    recipeId: recipeId,
    servingBasis: servingBasis,
    caloriesPerServing: perServing['energy']?['amount'] as double?,
    nutrientsJson: jsonEncode(perServing),
    totalsJson: jsonEncode(totals),
  );
}

/// A recipe's per-batch totals (nutrient key -> amount) from its stored
/// nutrition row: the stored totals (migration 015), else its per-serving
/// amounts × its basis (a row written before them; ponytail: a drift of at
/// most 0.005 × basis until the next compute stores the totals). What the
/// serving-basis route divides anew ([rebaseNutrition]) and what a parent's
/// routed row counts of its child (v41, [recomputeTotals]).
Map<String, double> batchTotalsOf(RecipeNutritionRow stored) {
  if (stored.totalsJson case final json?) {
    return {
      for (final MapEntry(:key, :value)
          in (jsonDecode(json) as Map<String, dynamic>).entries)
        key: (value as num).toDouble(),
    };
  }
  final was = stored.servingBasis ?? 1;
  return {
    for (final MapEntry(:key, :value)
        in (jsonDecode(stored.nutrientsJson) as Map<String, dynamic>).entries)
      key: ((value as Map<String, dynamic>)['amount'] as num) * was * 1.0,
  };
}

/// What [basis] divides a recipe's totals by: `per_batch` when it is 1 —
/// the whole batch ("MAKES 1 LOAF", no servings at all, or an admin's 1 on
/// a larger yield or serves count) — unless the recipe SERVES one (its
/// serves count starts at 1: "SERVES 1", "SERVES 1 TO 2", a bare "1") or its
/// MAKES yield is exactly ONE single portion ([singlePortionYields]:
/// "MAKES 1 OMELET", "MAKES 1 COCKTAIL"), whose one is a real serving (the
/// user's ruling, 2026-09-28). A range starting at one ("MAKES 1 TO 16
/// EGGS") is a batch: the totals describe the range's midpoint, not one egg
/// (Run 046). Any larger basis divides the batch: by a serves count, or by
/// a MAKES yield count ([recomputeTotals]), where a "serving" is one of the
/// yield — one of "MAKES TWO 9-INCH PIZZAS", not the batch (refix round 1:
/// the first rule, basis 2 or less with no serves count, labelled 29 such
/// basis-2 recipes per batch). `per_serving` otherwise.
String basisKindOf(int basis, {String? servings}) =>
    basis == 1 &&
        parseServings(servings)?.min != 1 &&
        !_singlePortionYield(servings)
    ? 'per_batch'
    : 'per_serving';

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

/// Whether the MAKES yield of [servings] is exactly ONE portion: its yield
/// count ([parseYieldCount]: "1", "ONE") is 1 and the head noun of its
/// first clause (up to a comma or semicolon, a trailing parenthetical
/// dropped: "MAKES 1 COCKTAIL (ABOUT 4 OUNCES)" is a cocktail) is a
/// [singlePortionYields] noun, SINGULAR: one portion names a singular noun,
/// so a range starting at one ("MAKES 1 TO 16 EGGS", a plural) is a batch.
/// "MAKES 1 SANDWICH LOAF" is a loaf, and "MAKES 32 SANDWICH COOKIES"
/// cookies (refix round 2).
bool _singlePortionYield(String? servings) {
  final count = parseYieldCount(servings);
  if (count == null || count.min != 1) {
    return false;
  }
  final clause = servings!
      .split(RegExp('[,;]'))
      .first
      .toLowerCase()
      .replaceFirst(RegExp(r'(?<!\s)\s*\([^)]*\)\s*$'), '');
  final head = RegExp('[a-z]+').allMatches(clause).lastOrNull?[0];
  return singlePortionYields.contains(head);
}

/// Re-ranked candidates for one line — ranked as the compute ranks them
/// ([freshOverCured]); a caller passes the [weighedLine] (Run 047: 0249's
/// sheet led with the cured record the compute moved away from, 0711's
/// listed onions for a row on oil). With [cacheOnly] (the GET path — any
/// authenticated user) the search cache is the sole source: a read must
/// never spend the FDC request budget or block on the rate limiter.
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
  return trimDepthRecord(
    line.raw,
    leanAndFatSibling(
      line.raw,
      freshOverCured(
        line.raw,
        rankCandidates(
          search.query,
          candidates,
          canned: namesCannedLegume(line.raw, normalized),
          skinOn: impliesSkinOn(line.raw, normalized),
          skinless: removesSkin(line.raw),
        ),
      ),
    ),
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
/// unprepared)" — whoever put the row on that record (the record relation
/// IS the approximation: a person's confirm or pick of it says so too), but
/// never on a skipped row, which counts nothing.
///
/// [memo]: the matches GET's, so M52's plan is read once per request, not
/// once per row ([_m52RowOf]); never a memo whose life spans a row write.
String? gramBasisFor(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row, {
  Recipe? recipe,
  ResolverMemo? memo,
}) {
  // A sub-recipe row on a food weighs the line's eaten "plus" part
  // ([weighedLine]: 0711's "3 tablespoons reserved oil").
  final weighed = recipe == null || row.fdcId == null
      ? line
      : weighedLine(recipe, line);
  // v53 (M52): a coat or frying oil the engine counted by [_m52Plan].
  final m52 = recipe == null
      ? null
      : _m52RowOf(db, recipe, line, row, memo: memo);
  final m52Flag = m52?.flag == null ? '' : ' · ${m52!.flag}';
  final basis = _gramBasis(db, weighed, row, recipe, m52: m52);
  // A skipped row adds nothing to the totals: no "approximate" or "counted
  // as" suffix (Run 046) — its basis alone says what was measured.
  if (basis == null || row.status == 'skipped') {
    return basis;
  }
  // v50 (M50 Q20 iv, Q21, Q7): a counted line the steps keep a volume of,
  // leave an excess of in the bowl, or lift out of a marinade says so —
  // never on grams a person typed, nor on a row counted 0 g.
  final flag =
      recipe == null ||
          row.hold != null ||
          row.grams! <= 0 ||
          row.gramSource == GramSource.override.name ||
          row.gramSource == GramSource.discarded.name
      ? null
      : m50FlagOf(recipe, line);
  final flagged = flag == null ? '' : ' · $flag';
  // A fresh herb on its dried record says its own suffix — only on the
  // engine's weighing, never on grams a person typed, nor on a sprig or
  // leaf counted as 0 g (Run 047 critic).
  if (row.description != null && freshHerbLine(line.raw, row.description!)) {
    return row.gramSource == GramSource.override.name ||
            row.gramSource == GramSource.unmeasured.name ||
            // v50: nor on one a step discards (0 g, its own basis).
            (row.gramSource == GramSource.discarded.name && row.grams! <= 0)
        ? basis
        : '$basis · approximate (dried herb record for a fresh herb)'
              '$flagged$m52Flag';
  }
  // Read on the weighed line, as the grams are (Run 049: "1 recipe Pesto
  // Base, plus 2 ounces pancetta" on the bacon record lost its label).
  final approximation = isApproximation(
    item: normalizeItem(lineItemOf(weighed)),
    raw: weighed.raw,
    fdcId: row.fdcId,
    description: row.description,
  );
  // v54 (M56 R1d, Q2 (i)): the printed trim the 0-inch flat stands in for.
  final standIn = trimStandInFlagOf(
    weighed.raw,
    row.fdcId,
    title: recipe?.title,
  );
  final stood = standIn == null ? '' : ' · $standIn';
  return approximation
      ? '$basis · approximation (counted as ${row.description})'
            '$stood$flagged$m52Flag'
      : '$basis$stood$flagged$m52Flag';
}

/// v54 (batch M56 R1d; the owner's 2026-10-08 decision Q2 (i), critic F2):
/// the stand-in a brisket line printing a ¼-inch fat cap counts on — the
/// raw flat at 0" (168743, R1d's record; no ¼" brisket record is cached) —
/// says so, whoever chose the record (the record relation is the stand-in,
/// as [isApproximation]'s). 0224's braise skims the rendered fat (step 5).
/// ponytail: keyed on the one corpus line's words, its step number that
/// recipe's; a second printed-depth brisket line needs its own steps read.
/// v61 (M63, Q6; live step L5's search, 2026-10-08): a top sirloin roast on
/// the lean-only petite roast 173408 that does not ask for lean says so —
/// FDC publishes no lean-and-fat petite roast (choice 173408, select
/// 174695 and all grades 173053 are all lean only, 0"), so R2 cannot fire
/// and a rank-as onto a top sirloin STEAK would read another subprimal.
/// v63 (M65 F2, the owner's Q14): ricotta salata on SR 173420 "Cheese,
/// feta" states the composition it borrows — FDC has no ricotta salata.
/// v66 (batch M68; the owner's Q1 (a) and Q2 (c), 2026-10-09): the whole
/// brisket's ¼-inch cap on 168664 ([trimDepthRecords]) says it is counted
/// at ⅛" with its rendered fat not deducted (USDA's braised pair 168664 →
/// 168665 keeps 93.3 % of the energy by the protein tracer); a fresh flat
/// 168743 in a recipe [title]d "corned beef" (0090, 0091 — both cure and
/// rinse it) says the cure's sodium is not counted — CP9's "rinsed cure 0 g"
/// and the 2026-09-27 "brine co-solutes zero" kept literal; the corned
/// record 170199 is not ranked (R-B not built).
/// ponytail: the title is the cure's only read (no step read); a cured
/// brisket in an untitled recipe is missed — none in the corpus.
/// v68 (batch M70, Q1 flat (b′)): the flat's ¼-inch cap on 173128 says it
/// is counted at ⅛" with the fat the steps skim deducted by its braised
/// pair's energy share ([braisedEnergyShare]); 168743's ¼" arm stays (the
/// fallback where the answer loses 173128).
String? trimStandInFlagOf(String raw, int? fdcId, {String? title}) =>
    switch (fdcId) {
      173128 when raw.toLowerCase().contains('fat trimmed to ¼ inch') =>
        "approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch "
            "flat trim; USDA's braised pair 173128 → 173130 keeps "
            '${(braisedEnergyShare[173128]! * 100).toStringAsFixed(1)} % of '
            'the energy by the protein tracer — the fat the steps skim, '
            'deducted)',
      168743 when raw.toLowerCase().contains('fat trimmed to ¼ inch') =>
        'approximate (the printed ¼-inch fat cap renders and is skimmed '
            '(step 5); counted as the 0-inch trimmed flat)',
      168743
          when title != null &&
              RegExp(
                r'\bcorned beef\b',
                caseSensitive: false,
              ).hasMatch(title) =>
        "approximate (the steps cure and rinse the brisket — the cure's "
            'sodium is not counted; a rinsed cure counts 0 g, CP9)',
      168664 when raw.toLowerCase().contains('fat trimmed to ¼ inch') =>
        "approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch "
            'trim, the deepest it publishes for brisket; the fat that renders '
            "into the separator is not deducted — USDA's own braised pair "
            '168664 → 168665 keeps 93 % of the energy)',
      173408 when !RegExp(r'\blean\b').hasMatch(raw.toLowerCase()) =>
        'approximate (lean only — FDC publishes no lean-and-fat top sirloin '
            "petite roast (search 2026-10-08); the roast's separable fat not "
            'counted)',
      173420 when raw.toLowerCase().contains('ricotta salata') =>
        'approximate (FDC holds no ricotta salata — a stand-in by class; '
            "feta's sodium (1,139 mg per 100 g) and fat (21.49 g per 100 g) "
            'counted)',
      _ => null,
    };

String? _gramBasis(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row,
  Recipe? recipe, {
  _M52Row? m52,
}) {
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
  // v41: a routed reference row reads its child (the copy sheet's "from the
  // recipe {title}: {g} g, {kcal} kcal"); a held one counts 0 g, as the
  // rule row it was says.
  if (row.gramSource == GramSource.recipe.name) {
    final childId = row.childRecipeId;
    if (childId == null || row.hold != null) {
      return 'a sub-recipe — counted as 0 g';
    }
    final title = nutritionRecipeOf(db, childId)?.recipe.title ?? childId;
    final child = db.nutritionFor(childId);
    final kcal = child == null || row.childShare == null
        ? null
        : (batchTotalsOf(child)['energy'] ?? 0) * row.childShare!;
    return 'from the recipe $title: ${_fmtAmount(row.grams!)} g'
        '${kcal == null ? '' : ', ${_fmtKcal(kcal)} kcal'}';
  }
  // v41 (R2): a rendered row says what rule B1 made of the raw weight.
  if (row.parts != null && fdcId == rawBaconFdcId) {
    final parts = partsOf(row.parts);
    final raw = lineGrams(
      db,
      line,
      knownFood(db, rawBaconFdcId, line: line),
      recipe: recipe,
    )?.grams;
    if (raw != null && parts.length == 2) {
      // v51 (M49 Q19): the kept amount shared with an oil says so.
      final pan = recipe == null ? null : _baconPanOf(recipe);
      final shared = pan != null && pan.bacon.raw == line.raw
          ? ', sharing the ${pan.text} kept with the oil'
          : '';
      return '${_fmtAmount(raw)} g raw → ${_fmtAmount(parts[0].grams)} g '
          'cooked bacon + ${_fmtAmount(parts[1].grams)} g bacon grease kept '
          'in the pan$shared';
    }
  }
  if (row.gramSource == GramSource.discarded.name) {
    // v51 (M49 Q19): an oil the steps pour down to a printed part
    // ([_keptInPan]) — never a medium's row (a frying oil keeps its own).
    final pan = recipe == null || row.grams! <= 0
        ? null
        : _keptInPanBasis(recipe, line);
    if (pan != null &&
        discardedMediumOf(
              recipe!,
              line,
              normalizeItem(lineItemOf(line)),
            ) ==
            null) {
      return pan;
    }
    // v53 (M52): a coat budgeted from its food, a frying oil whose fried
    // food absorbs part of it, or — bone-in skin-on chicken — none net.
    if (m52 != null && m52.noNetUptake) {
      return o1cBasis;
    }
    final m52What = m52 == null || m52.flag == null
        ? null
        : m52.dip
        ? 'the dip on the food'
        : m52.cut
        ? 'the cut dough'
        : m52.coat
        ? 'the coat on the food'
        : 'the oil the fried food absorbs';
    // v50 (M50): what a strain, a discard by name or a printed part kept
    // did to the line — the engine's row; a person's confirm of a held
    // medium at 0 g reads "poured away" below.
    final m50 = recipe == null || (row.grams! <= 0 && row.status != 'auto')
        ? null
        : _m50DiscardedBasis(
            recipe,
            line,
            weighing: () => lineGrams(
              db,
              line,
              fdcId == null ? null : knownFood(db, fdcId, line: line),
              recipe: recipe,
            )?.basis,
          );
    if (m50 != null) {
      return m50;
    }
    final plus = plusPartOf(line.raw);
    // An eaten FIRST part names itself (0114's "1 tablespoon").
    final eaten = plus == null || recipe == null
        ? null
        : _eatenPlusPart(
            recipe,
            line,
            headNounOf(normalizeItem(lineItemOf(line))),
          );
    final part = eaten == null || eaten.text == plus?.text
        ? 'plus ${plus?.text}'
        : eaten.text;
    // v51: a frying oil's kept part counted beside it ([engineOutcome]).
    final keptToo = plus == null || recipe == null
        ? null
        : _keptFryingOilText(recipe, line);
    // v57 (M59 F1): the part the steps rinse off ([_rinsedOff]) is never
    // named as counted; what is counted — a kept pour-off part, the uptake
    // — is (closer 1, V1-D2: engineOutcome counts the kept part then).
    final rinsed =
        eaten != null &&
        row.grams! > 0 &&
        _rinsedOff(
          recipe!,
          eaten,
          headNounOf(normalizeItem(lineItemOf(line)))!,
        );
    final counted = [
      if (keptToo != null) 'the $keptToo the steps keep',
      ?m52What,
    ];
    if (rinsed && counted.isNotEmpty) {
      return 'discarded in cooking — only ${counted.join(' and ')} counted '
          '("$part": the steps rinse it off)';
    }
    // A person's confirm of a held medium with no eaten part (B6).
    final also = m52What == null ? '' : ' and $m52What';
    late final yielded = _yieldOilFlagOf(recipe, line);
    if (m52What != null && plus == null && m52!.kept <= 0) {
      return 'discarded in cooking — only $m52What counted';
    }
    return row.grams! <= 0 && row.status != 'auto'
        ? 'poured away — counted as 0 g'
        : row.grams! <= 0
        ? 'discarded in cooking — counted as 0 g'
        : plus != null && keptToo != null
        ? m52What != null
              ? 'discarded in cooking — only "$part", the $keptToo the steps '
                    'keep and $m52What counted'
              : 'discarded in cooking — only "$part" and the $keptToo the '
                    'steps keep counted'
        // v62 (closer 3, verifier 3 D2): beside a printed yield's part
        // ([_yieldKept]) a plus part is named only when a step eats it,
        // and the yield's part is named with its flag.
        : plus != null && !rinsed && (yielded.isEmpty || eaten != null)
        ? 'discarded in cooking — only "$part"'
              '${yielded.isEmpty ? '' : ' and the part the recipe keeps'}'
              '$also counted$yielded'
        : 'discarded in cooking — only the part the recipe keeps$also '
              'counted$yielded';
  }
  if (row.gramSource == GramSource.unmeasured.name &&
      row.fdcId == null &&
      (recipe == null
          ? isSubRecipeReference(line.raw)
          : isReferenceIn(recipe, line))) {
    return 'a sub-recipe — counted as 0 g';
  }
  if (row.gramSource == GramSource.unmeasured.name &&
      row.fdcId == null &&
      row.description == engineRuleNotes[5]) {
    return 'flavouring, no nutrients — counted as 0 g';
  }
  if (row.gramSource == GramSource.unmeasured.name &&
      row.fdcId == null &&
      row.description == engineRuleNotes[7]) {
    return 'counted in the main recipe’s spice rub — counted as 0 g';
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
  final rule = secondFoodRuleOf(line, recipe: recipe);
  if (rule != null && rule.fdcId == fdcId) {
    final byRule = rule.gramsOn(food);
    // v49 (M47 Q6): a two-part row names both parts ([withParts]).
    final second = rule.second;
    final other = second == null || byRule == null
        ? null
        : second.grams(knownFood(db, second.fdcId, line: line));
    final both = second == null
        ? byRule
        : other == null
        ? null
        : GramResolution(
            grams: byRule!.grams + other.grams,
            source: byRule.source,
            basis: 'zest ${byRule.basis} + juice ${other.basis}',
          );
    if (both != null && (both.grams - row.grams!).abs() <= 0.05) {
      return both.basis;
    }
  }
  GramResolution? on(FdcFood? food) {
    final grams = lineGrams(db, line, food, recipe: recipe);
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

/// Grams as the app writes them (`fmtAmount`, A4: one rule for the
/// server's basis text and the app's line): one decimal under 10, else
/// whole ("643", not "642.9").
/// Read at the 2 places every row's grams are shown at (10 ounces, 283.495
/// g, reads 284).
String _fmtAmount(double v) {
  final shown = double.parse(v.toStringAsFixed(2));
  return shown < 10 ? shown.toStringAsFixed(1) : shown.round().toString();
}

/// Whole kcal with thousands separators ("3,057").
String _fmtKcal(double v) => v.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// The flag a composite row carries at GET (v41, S8: its own line, never a
/// `gram_basis` suffix), or null: a routed `auto` row on the first of
/// several titles its parent's note names — "approximation (the first
/// {kind} the note names: {title})", cleared by a person's decision (D6);
/// a counted child that is partial — "approximation ({title} is partial:
/// {m} of {n} lines)"; a rendered row — [baconYieldFlag] (v51; "approximate
/// (rendered and drained; yield from FDC protein)" before). The last two
/// name a fact and stay on
/// a Confirm (A6). Several join with " · ".
String? compositeFlagOf(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row,
  ResolverMemo memo,
) {
  if (row.status == 'skipped') {
    return null;
  }
  final flags = <String>[];
  if (row.childRecipeId case final childId? when row.hold == null) {
    final title = nutritionRecipeOf(db, childId)?.recipe.title ?? childId;
    if (isDefaultRoute(db, recipe, line, row, memo)) {
      // {kind}: the item's last word ("double-crust pie dough": dough).
      final kind = referenceItemOf(line).split(' ').last;
      flags.add(
        'approximation (the first $kind the note '
        'names: $title)',
      );
    }
    // v52 (M51): rule WB's whole batch on a line with no amount; rule
    // PV's base, counted for the prose variation the line names.
    if (line.amounts.isEmpty && row.childShare == 1) {
      flags.add(wbFlag);
    }
    if (resolveReference(db, recipe, line, memo) case ReferenceResolution(
      variation: _?,
      childId: final base?,
    ) when base == childId) {
      flags.add(pvFlagOf(title));
    }
    final child = db.nutritionFor(childId);
    if (child != null && child.status != 'complete') {
      flags.add(
        'approximation ($title is partial: ${child.matchedCount} '
        'of ${child.totalCount} lines)',
      );
    }
  }
  // Rule B1's rendered row (v49: the only parts rule with a flag — a
  // citrus or a can row's two parts are each the food as used).
  if (row.parts != null &&
      row.gramSource != GramSource.override.name &&
      row.fdcId == rawBaconFdcId) {
    flags.add(_baconDrips(recipe) ? baconDripFlag : baconYieldFlag);
  }
  // Q25 (v54): the share of an alcohol line's ethanol its cooking keeps —
  // a fact about the row, kept on a Confirm, as B1's (design §5).
  if (alcoholRetentionOf(recipe, line, row)?.flag case final retention?) {
    flags.add(retention);
  }
  return flags.isEmpty ? null : flags.join(' · ');
}

/// Rule WB's flag (v52, M51 Q22; the approved copy
/// docs/mockups/v51-references-copy.html §4): a reference line with no
/// amount counted as one whole batch of its child.
const String wbFlag =
    'approximate (no amount on the line — the whole batch counted)';

/// Rule PV's flag (v52, M51 Q9; the approved copy §4): a reference to a
/// prose variation counted as its base [title].
String pvFlagOf(String title) =>
    "approximation (counted as $title; the variation's changes are not read)";

/// Whether [row] — [line]'s row in [recipe] — is the ENGINE's route on the
/// first of two or more library titles its parent's note names (the
/// default flag, D6): routed, `auto`, on the child the resolver picks now
/// with `named` ≥ 2. A person's Confirm or pick is never a default.
bool isDefaultRoute(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row,
  ResolverMemo memo,
) {
  if (row.childRecipeId == null || row.hold != null || row.status != 'auto') {
    return false;
  }
  final found = resolveReference(db, recipe, line, memo);
  return found.childId == row.childRecipeId && found.named >= 2;
}

/// One candidate of a reference line's fix sheet ([referenceCandidates]):
/// its group (`own_section`, `note_named`, `library`, `similar`,
/// `other_section`), the library recipe (`recipe`; null for a section),
/// a section's `section` title and its host, and a note-named title's
/// `rank` (0 = named first).
typedef ReferenceCandidate = ({
  String group,
  LibraryTitle? recipe,
  String? section,
  String? hostId,
  String? hostTitle,
  int? rank,
});

/// Rule PO (v44, S8 a, P1 §2.6): the own sections a "(recipes follow)"
/// line held for a person — `choose_recipe` generic or a marinade's
/// `discarded_recipe` — lists: the recipe's sections WITH ingredient lines
/// that no other reference line of the recipe resolves to ("1 recipe glaze
/// (recipes follow)" lists roast-fresh-ham's four glazes; barbecued-pulled-
/// pork's "2 cups barbecue sauce" its two sauces, not the Dry Rub line 1
/// routes to). Null for any other line (its own group stays the resolver's
/// title forms). Listed for a person only — the engine never routes them.
List<String>? pickOwnSections(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
) {
  if (!RegExp(r'\brecipes follow\b').hasMatch(line.raw.toLowerCase())) {
    return null;
  }
  final found = resolveReference(db, recipe, line, memo);
  if (found.kind != ReferenceKind.marinade &&
      (found.kind != ReferenceKind.held || found.missing)) {
    return null;
  }
  final routed = <String>{
    for (final (i, other) in nutritionLines(recipe).indexed)
      if (other.raw != line.raw && subRecipeRowFor(recipe, i, other) != null)
        if (resolveReference(db, recipe, other, memo).section case (
          :final host,
          :final title,
        ) when host == recipe.id)
          title,
  };
  return [
    for (final sub in recipe.subsections)
      if (sub.title case final title?
          when !routed.contains(title) &&
              nutritionLines(sectionRecipeOf(recipe, sub)).isNotEmpty)
        title,
  ];
}

/// The fix sheet's candidates for the reference [line] of [recipe] (v41,
/// api_app §1d), in the resolution order: this recipe's sections (v44:
/// pickable once computed), the library titles its note names (in the note's
/// order), the library title equal to the item, library titles holding
/// every word of the item ([similarTitles], at most 5), and other recipes'
/// sections holding every word of it (at most 5). [recipe] itself is never
/// one; a title in an earlier group is not repeated. Reads [memo] only.
List<ReferenceCandidate> referenceCandidates(
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
) {
  final item = referenceItemOf(line);
  final itemWords = _refWords(item);
  final hostTitles = {
    for (final entries in memo.titles.values)
      for (final e in entries) e.id: e.title,
  };
  final named = noteNamedTitles(recipe, item, memo);
  final seen = {for (final t in named) t.id};
  final exact = [
    for (final e in memo.titles[item] ?? const <LibraryTitle>[])
      if (e.id != recipe.id && seen.add(e.id)) e,
  ];
  final own =
      pickOwnSections(memo.db, recipe, line, memo) ??
      [
        for (final sub in recipe.subsections)
          if (sub.title case final title? when _ownSectionNames(title, item))
            title,
      ];
  return [
    for (final title in own)
      (
        group: 'own_section',
        recipe: null,
        section: title,
        hostId: recipe.id,
        hostTitle: recipe.title,
        rank: null,
      ),
    for (final (rank, t) in named.indexed)
      (
        group: 'note_named',
        recipe: t,
        section: null,
        hostId: null,
        hostTitle: null,
        rank: rank,
      ),
    for (final t in exact)
      (
        group: 'library',
        recipe: t,
        section: null,
        hostId: null,
        hostTitle: null,
        rank: null,
      ),
    for (final t in similarTitles(recipe, item, memo))
      if (seen.add(t.id))
        (
          group: 'similar',
          recipe: t,
          section: null,
          hostId: null,
          hostTitle: null,
          rank: null,
        ),
    for (final s in [
      for (final MapEntry(key: normalized, value: entries)
          in memo.sections.entries)
        if (itemWords.isNotEmpty &&
            itemWords.every(_refWords(normalized).contains))
          for (final s in entries)
            // v44 (S14 a, N4): another host's CHILD sections only.
            if (s.host != recipe.id &&
                memo.computedSections.contains(sectionKeyOf(s.host, s.title)))
              s,
    ].take(5))
      (
        group: 'other_section',
        recipe: null,
        section: s.title,
        hostId: s.host,
        hostTitle: hostTitles[s.host],
        rank: null,
      ),
  ];
}

/// The rows a RECIPE decision on [itemKey] — [childId], made on the line
/// [excluding] — lands on (v41, design_v3 §2.3 b, the composite twin of
/// [decisionReach]): the key's undecided routed rows
/// ([SaltDatabase.undecidedRoutedMatchesForItemKey]) on ANOTHER child, or
/// on [childId] by a flagged default ([isDefaultRoute]); an unflagged row
/// on the same child waits on nothing. Only a line whose share of [childId]
/// reads ([parseShare]) — each target keeps its OWN share. What `others` /
/// `others_lines` count on a routed row and exactly what
/// [applyRecipeToOthers] writes. Never a food row (S18), never a held
/// reference line (a LINE hold, A2). v44 (S9 a): a SECTION pick is
/// line-local — a section child reaches nothing, and a row routed to a
/// section is never reached (another recipe's "glaze" is its own).
List<IngredientMatchRow> recipeReach(
  SaltDatabase db,
  String itemKey, {
  required String childId,
  required ({String recipeId, int position}) excluding,
  required ResolverMemo memo,
}) {
  final child = hostOf(childId) != childId
      ? null
      : nutritionRecipeOf(db, childId)?.recipe;
  if (child == null) {
    return const [];
  }
  final recipes = <String, Recipe?>{};
  return [
    for (final row in db.undecidedRoutedMatchesForItemKey(
      itemKey,
      excluding: excluding,
    ))
      if (hostOf(row.childRecipeId!) == row.childRecipeId)
        if (recipes.putIfAbsent(
              row.recipeId,
              () => nutritionRecipeOf(db, row.recipeId)?.recipe,
            )
            case final recipe?)
          if (nutritionLines(recipe).elementAtOrNull(row.position)
              case final line?
              when line.raw == row.raw &&
                  parseShare(line.raw, line.amounts, child.servings) != null &&
                  (row.childRecipeId != childId ||
                      isDefaultRoute(db, recipe, line, row, memo)))
            row,
  ];
}

/// Lands a person's RECIPE decision — [childId] on [itemKey], made on the
/// line [excluding] — on every row [recipeReach] reaches (v41, A1 b: the
/// apply-to-all is how a recipe pick travels; nothing is written to
/// `ingredient_decisions`). Each target is written as a person's decision
/// (`overridden`: an `auto` target would be re-resolved back to its own
/// note's default at its next compute), on [childId] at its OWN line's
/// share, derived as every decided composite row is ([derivedFor]'s child
/// arm, no FDC request), its default flag cleared; guarded at the statement
/// (a person's decision meanwhile stands, counted `decided`), each recipe
/// laid out first and its totals recomputed. The receipt is
/// [applyDecisionToOthers]'s (v47: recipes only, [alsoCompleted] seeding
/// it; a reached section's parents recomputed, [recomputeParentsOf]).
Future<
  ({
    int recipes,
    int lines,
    int failed,
    int completed,
    List<String> completedRecipes,
    int moved,
    int decided,
    int gone,
    int failedLines,
    int unavailable,
  })
>
applyRecipeToOthers(
  SaltDatabase db,
  NutritionProvider provider, {
  required String itemKey,
  required String childId,
  required ({String recipeId, int position}) excluding,
  List<String> alsoCompleted = const [],
}) async {
  final byRecipe = <String, List<IngredientMatchRow>>{};
  final memo = ResolverMemo(db);
  for (final target in recipeReach(
    db,
    itemKey,
    childId: childId,
    excluding: excluding,
    memo: memo,
  )) {
    byRecipe.putIfAbsent(target.recipeId, () => []).add(target);
  }
  final child = nutritionRecipeOf(db, childId)?.recipe;
  final reached = <String>{};
  var lines = 0;
  var failed = 0;
  var failedLines = 0;
  var moved = 0;
  var decided = 0;
  var gone = 0;
  final completed = [...alsoCompleted];
  for (final MapEntry(key: id, value: targets) in byRecipe.entries) {
    var owned = false;
    var marked = false;
    var wrote = false;
    try {
      final recipe = nutritionRecipeOf(db, id)?.recipe;
      if (recipe == null) {
        gone += targets.length;
        continue;
      }
      final before = {
        for (final row in db.ingredientMatchesFor(id)) row.position: row,
      };
      final paired = layoutMatchRows(db, recipe);
      final seq = db.layoutSeqOf(id);
      final placed = {
        for (final (at, row) in paired.indexed)
          if (row != null) row.position: at,
      };
      final recipeLines = nutritionLines(recipe);
      final hash = ingredientsHashOf(recipe, memo);
      var applied = 0;
      for (final target in targets) {
        final at = sameMatchRow(before[target.position], target)
            ? placed[target.position]
            : null;
        final line = at == null ? null : recipeLines[at];
        if (line == null || line.raw != target.raw) {
          // A save or a compute since the reach: left for its compute.
          moved += 1;
          continue;
        }
        final row = (await derivedFor(
          db,
          cacheOnly,
          recipe,
          at!,
          line,
          target.copyWith(
            position: at,
            status: 'overridden',
            childRecipeId: childId,
            // Its OWN line's share of the child (never the old child's).
            childShare: parseShare(line.raw, line.amounts, child!.servings),
            clearChildStamp: true,
            clearHold: true,
            clearParts: true,
          ),
        )).row;
        if (!marked) {
          marked = true;
          owned = db.markComputing(id);
        }
        if (!db.upsertIngredientMatchIfUndecided(
          row.copyWith(derivedSeq: derivedKeyOf(seq, hash)),
          layoutSeq: seq,
        )) {
          decided += 1;
          continue;
        }
        wrote = true;
        applied += 1;
      }
      if (applied == 0) {
        continue;
      }
      final statusBefore = db.nutritionFor(id)?.status;
      await recomputeTotalsResolving(
        db,
        provider,
        recipe,
        only: const {},
        ending: owned,
      );
      marked = false;
      reached.add(hostOf(id));
      lines += applied;
      for (final done in await _completedBy(db, provider, id, statusBefore)) {
        if (!completed.contains(done)) completed.add(done);
      }
    } on Exception catch (error) {
      failed += 1;
      failedLines += targets.length;
      _log.warning('recipe apply-to-all failed for $id: $error');
    } finally {
      if (marked) {
        db.releaseComputing(id, owned: owned, stale: wrote);
      }
    }
  }
  return (
    recipes: reached.length,
    lines: lines,
    failed: failed,
    completed: completed.length,
    completedRecipes: completed,
    moved: moved,
    decided: decided,
    gone: gone,
    failedLines: failedLines,
    unavailable: 0,
  );
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
  _unholdOn(db, [for (final candidate in results) candidate.fdcId]);
  return results;
}

/// Which cached search answers a line, and the words that rank it: `query`
/// ranks the candidates; `answer` is the fdc_search_cache row that holds them
/// — and, when it holds nothing yet, the words FDC is asked. They differ in
/// one case: a line whose own words were never searched reads the answer
/// stored under its KEY's words ("pork tenderloins" reads "pork tenderloin":
/// 56 of 56 such cached pairs ranked the same top food, sweep audit
/// 2026-09-26), still ranked under its own words. An "A or B" line whose A is
/// a known query searches A alone ([leftAlternative]). A rank-as item
/// ([rankAsFor]) reads its named cached answer under the record's words,
/// before any of that.
({String query, String answer}) lineSearchFor(
  SaltDatabase db,
  String normalized,
  String key,
) {
  final rankAs = rankAsFor(normalized);
  if (rankAs != null) {
    return rankAs;
  }
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

/// How many [knownFood] reads ran since reset — what the tests pin "one
/// resolution per row per request" by (RULE C v28, Run 058 O5/S10).
@visibleForTesting
int knownFoodReads = 0;

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
  knownFoodReads++;
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

  // The own answer first, then the other answers that list the food (an
  // indexed lookup, migration 016's `fdc_search_cache_foods`).
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

/// RULE A (v28; Run 058 Sonnet critic 2, S2, S3): the record a food's
/// nutrients are read from ([nutrientSiblings]) is an input of every
/// derivation that reads the food — resolved WHERE the food is (a decided
/// row's [derivedFor], an engine candidate, the prior decision), never in a
/// separate prefetch the totals depended on: a cache, else FDC (one
/// request, cached). True when FDC answers "no such food" for it — the
/// food cannot be counted: a decided row's `food_gone`, an engine
/// candidate passed over (the line re-matched). The provider's failure is
/// thrown (a decided row: underived).
Future<bool> _siblingGone(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) async {
  final sibling = nutrientSiblings[fdcId];
  return sibling != null &&
      knownFood(db, sibling) == null &&
      await _cachedFood(db, provider, sibling) == null;
}

/// Whether a cache holds [fdcId]'s nutrient record ([nutrientSiblings]) —
/// no request.
bool _siblingCached(SaltDatabase db, int fdcId) {
  final sibling = nutrientSiblings[fdcId];
  return sibling == null || knownFood(db, sibling) != null;
}

/// RULE C (v28, Run 058 O6/S11): ONE request per FOOD per pass. A pass —
/// a compute ([matchAndCompute]), a person's write and its apply-to-all
/// (`applyMatchOverride`) — reads [provider] through this: the first
/// `food(id)` asks FDC, and every later ask for that id in the pass is
/// answered by the same answer — a record (cached by [_cachedFood] anyway),
/// "no such food" (a 404 is cached nowhere: 400 typed rows on one retired
/// food asked 400 times, Run 058 O6), or the same failure. Every path that
/// fetches a food — a decided row, its nutrient sibling ([_siblingGone]),
/// an engine candidate, the prior decision, an apply target — goes through
/// [_cachedFood], so none asks twice. Searches are not memoised here: an
/// answer is cached by its query, a failure is GLOBAL (the pass stops).
/// Underneath, the JOB's outage watch ([jobProvider]): a provider not yet
/// watched is a job of one pass.
/// [recipe]: the recipe the pass is for — the watch's unit of escalation
/// (a person's write and its apply-to-all are one: never escalated).
/// The PASS's own suspension (the owner's ruling on Run 059 O10): FOOD
/// failures on [detailOutageAfter] distinct ids REQUESTED in this pass in
/// a row, no detail answered between (a failure the job already holds
/// answers with no request and is not counted), and the pass asks FDC for
/// no more details: every later uncached detail throws [DetailsSuspended]
/// with no request — a decided row it reaches is left underived, an
/// engine line keeps the row it had, both uncounted, and the totals stamp
/// the recipe stale ([recomputeTotals]' `unavailable`). Not an escalation:
/// the job goes on, and its watch escalates at the next recipe's first
/// failure — so an outage costs at most [detailOutageAfter] + 1 detail
/// requests per sweep, whatever the recipe's size.
NutritionProvider onePass(NutritionProvider provider, {String? recipe}) =>
    provider is _OnePass
    ? provider
    : _OnePass(
        provider is _JobWatch ? provider : _JobWatch(provider),
        recipe,
      );

class _OnePass implements NutritionProvider {
  _OnePass(this._inner, this._recipe);
  final _JobWatch _inner;
  final String? _recipe;
  final Map<int, Future<FdcFood?>> _asked = {};

  /// Requested details that failed FOOD since the pass's last answer.
  var _failedRun = 0;

  /// Set at the suspension; [skipped]: a detail was refused under it.
  DetailsSuspended? suspended;
  bool skipped = false;

  @override
  Future<List<FdcCandidate>> search(String query) => _inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) => _asked[fdcId] ??= _ask(fdcId);

  Future<FdcFood?> _ask(int fdcId) async {
    if (suspended case final down?) {
      skipped = true;
      throw down;
    }
    final replay = _inner._down != null || _inner._failed.containsKey(fdcId);
    try {
      final food = await _inner.foodFor(fdcId, _recipe);
      _failedRun = 0;
      return food;
    } on NutritionProviderException catch (error) {
      if (!replay &&
          error.scope == FailureScope.food &&
          ++_failedRun >= detailOutageAfter) {
        suspended = DetailsSuspended(error);
      }
      rethrow;
    }
  }
}

/// A pass's suspension ([onePass]): FOOD — never the job's stop — and what
/// a suspended pass returns, so `computeUntilFresh` runs no second pass
/// (it would only ask FDC again; the next sweep does).
class DetailsSuspended extends NutritionProviderException {
  /// After [food], the failure that tipped it.
  DetailsSuspended(NutritionProviderException food)
    : super(
        '${food.message} (no more food details asked for this recipe '
        'in this pass)',
        scope: FailureScope.food,
      );
}

/// RULE A's escalation, counted in the JOB's units (v29, Run 059
/// O4/O10/S4/O11): a job — a bulk sweep, a recipe's compute job, a
/// person's write — reads FDC through ONE of these for all its passes.
/// FOOD failures on [detailOutageAfter] DISTINCT ids in a row, no detail
/// answered between them (a record or a 404 — any answer resets the run),
/// SPANNING AT LEAST TWO RECIPES (the owner's ruling on Run 059 O11: an
/// outage is a property of the job; one recipe's failures, however many,
/// are its rows' state), are an outage of the detail endpoint: GLOBAL with
/// the provider's reason ([_Escalated], carrying the tipping request's own
/// FOOD failure — still counted on its row), and every later detail of the
/// job throws it with no request. With the pass's own suspension
/// ([onePass]: one recipe asks at most [detailOutageAfter] failing details
/// in a row) a detail outage stops a sweep after at most
/// [detailOutageAfter] + 1 requests, whatever the recipes' sizes: 3 in
/// the first failing recipe, 1 in the next. A food that
/// failed FOOD once in the job is not asked again in it: the same failure
/// answers (one broken record shared by many recipes is one request and
/// one id, never an outage). Escalation never discards a count: every FOOD
/// failure is counted on its row ([matchAndCompute]), so broken records
/// are held after three sweeps whatever else the sweep meets.
NutritionProvider jobProvider(NutritionProvider provider) =>
    provider is _JobWatch ? provider : _JobWatch(provider);

class _JobWatch implements NutritionProvider {
  _JobWatch(this._inner);
  final NutritionProvider _inner;

  /// Each id whose detail failed FOOD in this job, and its failure.
  final Map<int, NutritionProviderException> _failed = {};

  /// The ids whose detail failed FOOD since FDC last answered one, each
  /// with the recipe it was asked for.
  final Map<int, String?> _run = {};

  /// The escalated failure: every later detail of the job throws it.
  NutritionProviderException? _down;

  @override
  Future<List<FdcCandidate>> search(String query) => _inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) => foodFor(fdcId, null);

  /// [food] for a pass of [recipe] ([onePass]).
  Future<FdcFood?> foodFor(int fdcId, String? recipe) async {
    final down = _down ?? _failed[fdcId];
    if (down != null) {
      throw down;
    }
    try {
      final food = await _inner.food(fdcId);
      _run.clear();
      return food;
    } on NutritionProviderException catch (error) {
      if (error.scope == FailureScope.food) {
        _failed[fdcId] = error;
        _run[fdcId] = recipe;
        if (_run.length >= detailOutageAfter &&
            _run.values.toSet().length > 1) {
          _down = NutritionProviderException(error.message);
          throw _Escalated(error);
        }
      }
      rethrow;
    }
  }
}

/// The request that tipped a job's detail outage ([jobProvider]): GLOBAL
/// (the job stops), and [food] — its own FOOD failure, counted on the row
/// that asked (the owner's ruling on O11: escalation never discards a
/// count).
class _Escalated extends NutritionProviderException {
  _Escalated(this.food) : super(food.message);

  /// The row's own failure.
  final NutritionProviderException food;
}

/// How many FOOD failures on distinct foods in a row, across one job, are
/// a detail outage ([jobProvider]): 3 — two retired or broken records side
/// by side are plausible, a third with nothing answered between is FDC.
const int detailOutageAfter = 3;

/// The provider of a re-read (RULE A v29): it never fetches — it throws,
/// so nothing caches a miss and a derivation needing FDC reads
/// `unavailable` — the matches GET, the PUT's gate, and a compute's re-read
/// of a hold for having no record ([derivedFor] through it reads only
/// [knownFood], fdc_food_cache then the search-cache index).
const NutritionProvider cacheOnly = _CacheOnly();

class _CacheOnly implements NutritionProvider {
  const _CacheOnly();

  @override
  Future<List<FdcCandidate>> search(String query) =>
      throw NutritionProviderException('cache only: search "$query"');

  @override
  Future<FdcFood?> food(int fdcId) =>
      throw NutritionProviderException('cache only: food $fdcId');
}

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
    _unholdOn(db, [fdcId]);
  }
  return food;
}

/// RULE A (v29, Run 059 O1/S1): a cache just gained [fdcIds] — the rows
/// held for having no record of one of them, or of its nutrient record
/// ([nutrientSiblings]), are re-opened ([SaltDatabase.unholdOn]): their
/// recipes read stale, and the next compute re-reads each hold from the
/// caches, no request. Schedules the re-read the GET already shows.
void _unholdOn(SaltDatabase db, List<int> fdcIds) => db.unholdOn([
  ...fdcIds,
  for (final MapEntry(:key, :value) in nutrientSiblings.entries)
    if (fdcIds.contains(value)) key,
]);

/// Public cache-aware food lookup (the match-override endpoint needs it).
Future<FdcFood?> cachedFood(
  SaltDatabase db,
  NutritionProvider provider,
  int fdcId,
) => _cachedFood(db, provider, fdcId);

/// How many decided rows ([isDecidedRow]) of each text [rows] hold.
Map<String, int> _decidedByRaw(Iterable<IngredientMatchRow> rows) {
  final counts = <String, int>{};
  for (final row in rows) {
    if (_isDecided(row)) {
      counts[row.raw] = (counts[row.raw] ?? 0) + 1;
    }
  }
  return counts;
}

/// The rows a decision on [itemKey] made on the line [excluding] lands on
/// — what `others` / `others_lines` count and exactly what
/// [applyDecisionToOthers] writes: [SaltDatabase.undecidedMatchesForItemKey]
/// (a different food at any score, [fdcId] only below [lowConfidence] or
/// held by a food hold, never a line-held row; with no [fdcId] every
/// undecided row) less every row a line hold would hold once it took the
/// food: a line that names a second food ([namesSecondFood]) — its rule
/// counts it on its own record, or it is held `second_food` whatever food
/// the key gives it — shellfish bought in the shell ([boughtInShell], held
/// `in_shell` on any food), and a line that is a held medium, matched or
/// not, read from its recipe now ([_heldMediumNow]: an unmatched salt bath
/// or pot salt, a dredge on a stale recipe whose row has no hold yet; a
/// brine and its sugar are zeroed, never held — R3). No decision on the key
/// moves either
/// (checkpoint 5 review: the offer counted 43 rule rows and the apply
/// landed 0; an unmatched second-food line was reported applied).
List<IngredientMatchRow> decisionReach(
  SaltDatabase db,
  String itemKey, {
  required ({String recipeId, int position}) excluding,
  int? fdcId,
  ReachMemo? memo,
}) {
  final reads = memo ?? ReachMemo();
  // Once per key and food a request (Run 055 V1: the matches GET reached
  // per LINE, every same-key row's text re-read each time — 160 identical
  // lines, 16 s).
  return reads._reach.putIfAbsent(
    (itemKey, excluding.recipeId, excluding.position, fdcId),
    () => [
      for (final row in _reachRows(db, itemKey, excluding, fdcId))
        if (!reads._textOut.putIfAbsent(
              row.raw,
              () => namesSecondFood(row.raw) || boughtInShell(row.raw),
            ) &&
            !_heldMediumNow(db, row, reads))
          row,
    ],
  );
}

/// [decisionReach]'s stored rows, counted ([reachScans]).
List<IngredientMatchRow> _reachRows(
  SaltDatabase db,
  String itemKey,
  ({String recipeId, int position}) excluding,
  int? fdcId,
) {
  reachScans++;
  return db.undecidedMatchesForItemKey(
    itemKey,
    excluding: excluding,
    fdcId: fdcId,
    belowConfidence: confidenceGateFloor,
  );
}

/// How many times [decisionReach] read its rows since reset — what the
/// tests pin the per-key memo by (Run 055 V1), never a clock.
@visibleForTesting
int reachScans = 0;

/// How many keys [lineKeyOf] and a row's own text derived since reset —
/// what the tests pin their memos by (Run 055 V1), never a clock.
@visibleForTesting
int keyReads = 0;

/// One request's reads for [decisionReach] (Run 054 S4/O4/O15): each reached
/// recipe's stored content hash read once, and decoded at most once — a
/// matches GET reaches the same recipes from every line of its recipe.
/// Never kept past the request: a write between two requests changes what
/// it read (the holds themselves are kept by hash, [_heldByVersion]).
class ReachMemo {
  final Map<String, String?> _versions = {};
  final Map<String, Recipe?> _recipes = {};
  // Whether a reached raw names a second food or is bought in the shell.
  final Map<String, bool> _textOut = {};
  // The reach of each (key, excluded line, food) already walked.
  final Map<(String, String, int, int?), List<IngredientMatchRow>> _reach = {};
}

/// Each reached line's text and hold by its recipe's stored content hash
/// and its position, across requests (Run 054 S4/O4/O15: one GET of 0491
/// reached 517 rows of other recipes at ~0.5 ms of detector each, 1,033
/// runs at v23; the same rows every GET). Exact: the detector reads only
/// the stored document, whose every change changes the hash, and the
/// matcher version is the process's. Cleared past [_heldByVersionCap].
///
/// v44 (N2): keyed by the row's recipe id as well — a section key's version
/// is its HOST's hash, so a host's main line p and its section's line p
/// would otherwise share one slot.
final Map<(String, String, int), ({String? raw, bool held})> _heldByVersion =
    {};
const _heldByVersionCap = 50000;

/// How many lines [decisionReach] ran the medium detector on since reset
/// — what the tests pin the reach's memo by, never a clock.
@visibleForTesting
int reachHoldReads = 0;

/// How many reached recipes [decisionReach] decoded since reset — what the
/// tests pin [ReachMemo]'s per-request decode by (Run 055 S1), never a clock.
@visibleForTesting
int reachDecodes = 0;

/// Whether [row]'s line is a medium the engine HOLDS ([heldMediumLine]),
/// read from its recipe as stored now, matched or not ([memo]). Never the
/// row's stored hold: on a stale recipe (a steps edit, a matcher bump not
/// yet swept) a matched row the detector now holds still reads `hold`
/// null, and a decision would be offered and applied to a line that stays
/// held (Run 053 Opus critic 3).
bool _heldMediumNow(SaltDatabase db, IngredientMatchRow row, ReachMemo memo) {
  // A matched sub-recipe reference is no held row on the decided food: its
  // held eaten part weighs nothing, and the apply writes the sub-recipe
  // rule's 0 g row ([subRecipeRowFor]; v18 W4 — the unmatched one stays
  // unreached, W2). (Read on the row's text: a line of another text is
  // not this row's, below.)
  if (row.fdcId != null && isSubRecipeReference(row.raw)) {
    return false;
  }
  final version = memo._versions.putIfAbsent(
    row.recipeId,
    () => db.contentHashOf(hostOf(row.recipeId)),
  );
  if (version == null) {
    return false; // Deleted meanwhile.
  }
  final read =
      _heldByVersion[(row.recipeId, version, row.position)] ??
      () {
        final recipe = memo._recipes.putIfAbsent(row.recipeId, () {
          reachDecodes++;
          try {
            return nutritionRecipeOf(db, row.recipeId)?.recipe;
            // A doc that will not decode is reached, and the apply counts it
            // failed: never a reach (the offer's GET) that throws.
            // ignore: avoid_catches_without_on_clauses
          } catch (_) {
            return null;
          }
        });
        final lines = recipe == null ? null : nutritionLines(recipe);
        final ({String? raw, bool held}) found;
        if (lines == null || row.position >= lines.length) {
          found = (raw: null, held: false);
        } else {
          reachHoldReads++;
          final line = lines[row.position];
          // The weighed line, as the apply weighs it (Run 049: a same-food
          // plus row whose eaten part is a held salt bath was "applied").
          found = (
            raw: line.raw,
            held: heldMediumLine(recipe!, weighedLine(recipe, line)),
          );
        }
        if (_heldByVersion.length >= _cap(_heldByVersionCap)) {
          _heldByVersion.clear();
        }
        return _heldByVersion[(row.recipeId, version, row.position)] = found;
      }();
  return read.raw == row.raw && read.held;
}

/// Whether [line] of [recipe] is a discarded medium the engine HOLDS for a
/// person (`discarded_medium`, [discardedMediumOf]) — not one the policy
/// zeroes. Read from the line and the steps, whatever the row stores.
bool heldMediumLine(Recipe recipe, IngredientLine line) {
  final medium = discardedMediumOf(
    recipe,
    line,
    normalizeItem(lineItemOf(line)),
  );
  return medium != null &&
      !(medium.followsPolicy &&
          discardedMediaPolicy == DiscardedMediaPolicy.zero);
}

/// The row an un-skip returns [row] — position [position] of [recipe] — to:
/// automatic triage, as a compute writes it. The sub-recipe rule gates it
/// ([subRecipeRowFor]) and the line is weighed as every path weighs it
/// ([weighedLine]: 0711's oil stays counted, never held `second_food`). Its
/// hold is re-derived for the food now on the row — never an engine-era
/// hold left over from another food. A person's food (confidence 1: a pick
/// or a decision, inherited or not) answers every FOOD hold, never a LINE
/// hold ([engineOutcome] with `decided`): a discarded medium, a second
/// food, shellfish bought in the shell stay held — an un-skip is no
/// confirm, and a decision inherited from another recipe was never a look
/// at this line (v11: skip then un-skip counted 1,814 g of mussels in the
/// shell, 0294). Only a confirm or a pick clears them. A held medium takes
/// the engine's grams back too — none, or its eaten part — never a
/// person's 0 g poured away, which would read resolved with nobody's
/// decision (Run 047 critic: 0112's soy sauce). Grams a person typed come
/// back as the person's row, counted, before any gate: neither the
/// sub-recipe rule nor the second-food rule replaces them (Run 049, 050).
/// An engine row whose line the second-food rule counts moves to the rule's
/// record with the rule's grams (checkpoint 5 review: an un-skip left a
/// rule line held on the peel for good).
Future<IngredientMatchRow> unskippedRow(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  int position,
  IngredientMatchRow row,
) async {
  // Grams a person typed are their row: an un-skip gives it back counted,
  // with no hold — `overridden`, as a grams edit makes an `auto` row (Run
  // 049: a held medium's typed grams came back on an `auto` row, held out
  // of the totals, that the next compute re-derived). First, as the
  // compute keeps a decided row and a confirm or pick keeps typed grams:
  // neither the sub-recipe gate nor the second-food rule replaces them
  // (Run 050: an un-skip turned a made-apart sub-recipe's pick and typed
  // 50 g into the 0 g sub-recipe row).
  if (row.fdcId != null && row.gramSource == GramSource.override.name) {
    return row.copyWith(status: 'overridden', clearHold: true);
  }
  final line = nutritionLines(recipe)[position];
  final uncounted = subRecipeRowFor(recipe, position, line);
  if (uncounted != null) {
    // v41: the composite row the compute writes ([referenceRowFor]).
    return referenceRowFor(db, recipe, position, line, ResolverMemo(db));
  }
  final eaten = weighedLine(recipe, line);
  var out = row.copyWith(status: 'auto', clearHold: true);
  final personal = out.confidence >= 1;
  // A row already on the rule's record is not re-derived by the rule: a
  // confirm keeps the engine's confidence, so a person's typed grams there
  // are not `personal`, and the rule would replace them (Run 049: "¼
  // teaspoon grated lime zest plus 1½–2 tablespoons juice" confirmed at
  // 40 g came back at the rule's 26.65 g).
  final byRule =
      personal || secondFoodRuleOf(line, recipe: recipe)?.fdcId == out.fdcId
      ? null
      : await ruleRowFor(db, provider, recipe, position, line);
  if (byRule != null) {
    return byRule.row;
  }
  final onRow = out.fdcId == null
      ? null
      : knownFood(db, out.fdcId!, line: eaten);
  if (onRow == null) {
    // A skipped rule row — a marked count's sub-recipe, a seasoning, water,
    // equipment — is that row again, as the compute wrote it: never an
    // `auto` row on no food, in `no_match` (Run 047 critic).
    final rule = row.copyWith(status: 'confirmed');
    return isEngineRuleRow(rule) ? rule : out;
  }
  final medium = heldMediumLine(recipe, eaten);
  final source = GramSource.values.asNameMap()[out.gramSource];
  final derived = lineGrams(db, eaten, onRow, recipe: recipe);
  // The stored grams keep their basis when the line still derives them
  // (the tolerance [gramBasisFor] reads with): the hold reads it — a shell
  // row counts only by its yield's flag ([shellCounted]; v49 closer 2: an
  // un-skip held 0294's AH-102 mussels, 0429's shrimp and 0034's clams
  // `in_shell` though the compute counts them).
  final stored = out.grams == null || source == null
      ? null
      : derived != null &&
            derived.source == source &&
            (derived.grams - out.grams!).abs() <= 0.05
      ? derived
      : GramResolution(grams: out.grams!, source: source);
  final outcome = engineOutcome(
    recipe,
    eaten,
    onRow,
    medium ? derived : stored,
    picked: !personal,
    decided: personal,
    confidence: out.confidence,
  );
  out = medium
      ? out.copyWith(
          grams: outcome.grams,
          clearGrams: outcome.grams == null,
          gramSource: outcome.source,
          clearGramSource: outcome.source == null,
          hold: outcome.hold,
        )
      : out.copyWith(hold: outcome.hold);
  // Rule B1 (v41) on the line's raw weight: a skip kept the rendered sum;
  // v49: every rule's parts ([withParts]).
  out = withParts(
    db,
    recipe,
    eaten,
    out,
    raw: out.fdcId == rawBaconFdcId ? derived?.grams : null,
  );
  return subRecipeRowFor(
        recipe,
        position,
        line,
        onFood: true,
        grams: out.grams,
        sized:
            personal ||
            !belowConfidenceGate(out.confidence) ||
            _foodFromCache(db, onRow.fdcId) != null,
      ) ??
      out;
}

/// RULE A (v25, Run 055 I1): a decided row stores ONLY the person's
/// decision — its status, its food, grams a person typed. Everything else
/// on it (the hold, the grams unless typed, their source, the `hold_note`)
/// is DERIVED from the current [recipe] by this one function, at every
/// compute ([matchAndCompute], which writes only these derived fields), at
/// every person's write (`applyMatchOverride`, after it sets the decision)
/// and at every read (`matchesBody`). A compute never changes a decision.
/// The decision [edited] may sit on its line [line] (position [position]),
/// or on its line's old text when a save edited that line to the SAME
/// ingredient — the layout paired them ([pairRowsToLines]; Run 051 B1/B2).
/// What each decision resolves, by hold kind, is stated below (`keepsHold`).
///
/// The status stands (a skip stays a skip, a pick keeps its food), and a
/// skip or a row a person typed grams on goes ahead of the sub-recipe rule
/// (Run 051 B3: an amount edit on 1201's "10 cups Vanilla Frosting (recipe
/// follows)" replaced a pick, its typed grams and a skip with the 0 g
/// sub-recipe row). The grams are the compute's real
/// outcome for the new line ([engineOutcome], the discard policy included,
/// read WITH the grams: a poured-away medium stays at 0 g — v19 re-derived
/// a skipped "3 cups vegetable oil for frying" at 672 g and an un-skip
/// counted it, Run 051 O11). Grams a person typed stay when the amount is
/// unchanged (a prep-only rewrite, "1 onion, chopped" to "1 onion,
/// minced") or the line is a discarded medium by that same outcome (with
/// grams: "3 quarts peanut oil", no "for frying", is one), else they are
/// re-derived — none derivable, none (an un-skip never revives the old
/// amount's weight, Run 050). The amount is every amount the line writes,
/// its "plus" part's included (Run 052 O2/S3). A row on no food keeps itself. A non-skipped
/// row a person typed no grams on is gated by the sub-recipe rule
/// ([subRecipeRowFor]) as a confirm writes it (v14 A1: a confirmed counted
/// egg line edited to "1 recipe Easy-Peel Hard-Cooked Eggs" is the 0 g
/// sub-recipe). The `food` is the food the row stands on (a search hit not
/// in the food cache, for the totals), or null.
///
/// [m52Memo]: the matches GET's, so a confirmed coat or frying oil reads
/// M52's plan once per request ([_m52OnConfirm]); never a memo whose life
/// spans a row write (the compute's [references] does — a confirmed coat,
/// batter or dip line reads its plan through it, re-keyed on the rows as
/// they are at each derivation: v61 closer 1, verify1 D1).
Future<
  ({
    IngredientMatchRow row,
    FdcFood? food,
    String? note,
    NutritionProviderException? unavailable,
  })
>
derivedFor(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  int position,
  IngredientLine line,
  IngredientMatchRow edited, {
  ({FdcFood? food})? resolved,
  ResolverMemo? references,
  ResolverMemo? m52Memo,
}) async {
  final eaten = weighedLine(recipe, line);
  final normalized = normalizeItem(lineItemOf(eaten));
  // The row's food from the caches ([knownFood]), read ONCE (RULE C v28,
  // Run 058 O5/S10): the typed fast path and the decided food below share
  // it, and a caller that already resolved it ([resolved]: the matches GET,
  // which shows it) passes it in.
  late final onCache = edited.fdcId == null
      ? null
      : resolved != null
      ? resolved.food
      : knownFood(db, edited.fdcId!, line: eaten);
  final placed = edited.copyWith(
    position: position,
    raw: line.raw,
    itemKey: lineKeyOf(line),
  );
  final skipped = edited.status == 'skipped';
  final typed = edited.gramSource == GramSource.override.name;
  // Every amount the line writes, its "plus" part's too: the parse keeps
  // the first amount and files "plus 3 tablespoons reserved oil" under
  // prep, so an edit of the eaten plus part ("1 recipe Crispy Onions, plus
  // 3 tablespoons" to 6, Mujaddara 0711; "2 large eggs plus 6 large
  // yolks" to 8) read as prep-only and kept the old typed grams (Run 052
  // O2/S3).
  String amountsOf(String raw) => jsonEncode([
    for (final amount in parseIngredientLine(raw).amounts) amount.toMap(),
    plusPartOf(raw)?.amount.toMap(),
  ]);
  final sameAmount = amountsOf(edited.raw) == amountsOf(line.raw);
  // A skip, or grams a person typed, on its own amount reads NO food: a
  // skip stores no hold and counts nothing (its grams stay as they were;
  // v15 E11: a below-gate pick skipped, its detail uncached), typed grams
  // answer every hold and count as typed — so neither fetches a detail it
  // never reads (Run 056 O1: 0279's typed "2 teaspoons Sichuan
  // peppercorns" fetched one at the PUT and at every compute, and threw
  // the whole compute while FDC was out). Carried by an amount edit either
  // is re-derived below, so an un-skip never revives the old amount's
  // weight (Run 050, Run 051 O11). Typed grams are counted ON their food,
  // so a typed row reads its food from the caches ([knownFood], no
  // request) — and only a food no cache holds is asked for below, as the
  // totals would need it (v27, RULE A: the totals never fetch; Opus critic
  // 2: typed grams on a food FDC no longer serves were dropped from the
  // totals under a fresh stamp — now the `food_gone` hold).
  // Its nutrient record too ([nutrientSiblings], v28): a typed row on a
  // food whose record no cache holds is resolved below like any other.
  final typedOn =
      typed &&
          !skipped &&
          sameAmount &&
          edited.fdcId != null &&
          _siblingCached(db, edited.fdcId!)
      ? onCache
      : null;
  if ((skipped || typed) &&
      sameAmount &&
      (skipped || typedOn != null || edited.fdcId == null)) {
    return (
      // v41 (F2): typed grams answer the line on ONE record, and a skip
      // counts nothing — neither keeps a rendered row's parts; a skip reads
      // no child, so it keeps no stamp the child's next write would leave
      // stale for good.
      row: placed.copyWith(
        clearHold: true,
        clearParts: true,
        clearChildStamp: skipped,
      ),
      food: typedOn,
      note: null,
      unavailable: null,
    );
  }
  // v41 (F1, N1, N6): a person's decision on a composite reference row —
  // a Confirm or a pick of a child recipe, a saved share — counts the
  // child, re-read here at every compute, PUT and GET, BEFORE the no-food
  // branch below (which would clear its grams).
  if (edited.childRecipeId != null) {
    return (
      row: _childRowOf(
        db,
        line,
        placed,
        sameAmount: sameAmount,
        children: references ?? ResolverMemo(db),
      ),
      food: null,
      note: null,
      unavailable: null,
    );
  }
  if (edited.fdcId == null) {
    // No food: the row as it was, no grams (a typed no-food row is
    // unreachable — the PUT refuses grams with no food; a v20 term kept its
    // grams on any amount, deleted Run 052 S10).
    return (
      row: placed.copyWith(clearGrams: true, clearGramSource: true),
      food: null,
      note: holdNoteOf(recipe, line, placed.hold),
      unavailable: null,
    );
  }
  // RULE A's unhappy outcome (v26, Run 056 S2/O1/S29, Sonnet critic 1;
  // restated v28, Run 058 S29): the derivation cannot run — FDC FAILS a
  // fetch it needs (the food detail [gramsFor] reads for household
  // portions or an edible yield, the food itself or its nutrient record
  // when no cache holds them). The decision stands with the derived fields
  // exactly as the last successful derivation left them (never cleared, no
  // line hold dropped: 0857's confirmed "1¾ cups (8¾ ounces)" flour keeps
  // its 248 g), and [unavailable] tells the caller so: the compute writes
  // nothing over the row and leaves it UNDERIVED (`derived_seq` null — the
  // stamp untouched, the recipe reading stale through the freshness
  // predicate's third half; a FOOD-scoped failure counts the row's
  // `retry_count` and is held `food_unavailable` after three), the PUT
  // stores the decision so (underived), the GET shows the row as stored.
  // Never a throw for one row. FDC answering "no such food" (a 404) for
  // the food or its nutrient record is NOT this outcome: it is derived, to
  // the `food_gone` hold (below).
  final (FdcFood, GramResolution?)? weighed;
  try {
    final known = onCache ?? await _cachedFood(db, provider, edited.fdcId!);
    // A food whose nutrient record FDC answers "no such food" for is gone
    // as surely as one whose own record is (v28, Sonnet critic 2).
    weighed = known == null || await _siblingGone(db, provider, known.fdcId)
        ? null
        : await gramsFor(db, provider, known, eaten, recipe: recipe);
  } on NutritionProviderException catch (failure) {
    // The row as stored, at its current position — on the text it was last
    // derived on: a decision an amount edit carried keeps its old text, so
    // the next derivation still reads the amount as edited (typed grams of
    // the old amount are never revived as the new one's, Run 052 S10/O11).
    // Its LINE hold only (Run 057 O3): a food hold an engine row carried
    // (`no_nutrients` on the old food) is no derivation of this decision —
    // a decision answers every food hold; `food_gone` is this food's own.
    // A SKIP an amount edit carried keeps NO grams of the old amount (v27
    // closer, the verifier's D2, Opus critic 2 #2: 0279's peppercorns typed
    // 77 g for "2 teaspoons", skipped, edited to "3 teaspoons" and
    // un-skipped while FDC was out came back `overridden` at 77 g under the
    // new line and the totals counted them): a skip counts nothing, so its
    // grams are only what an un-skip would revive, and the success path
    // keeps none of another amount either — unless typed on a line that is
    // a discarded medium by the same food-free reading (`keepTyped`). A
    // confirm or a pick keeps its grams as stored (RULE A: what the totals
    // count, until a derivation reads the new amount).
    final dropGrams =
        skipped &&
        !sameAmount &&
        !(typed && discardedMediumOf(recipe, eaten, normalized) != null);
    final hold = edited.hold;
    return (
      row: edited.copyWith(
        position: position,
        clearHold:
            skipped ||
            !(lineHolds.contains(hold) || noRecordHolds.contains(hold)),
        clearGrams: dropGrams,
        clearGramSource: dropGrams,
      ),
      food: null,
      note: holdNoteOf(recipe, line, edited.hold),
      unavailable: failure,
    );
  }
  if (weighed == null) {
    // FDC answers no such food and no cache holds it (a superseded record
    // whose stand-in a fresh search answer replaced): NOT an outage — the
    // decision is derived, to the `food_gone` HOLD (v27, RULE A; Opus
    // critic 2, Sonnet critic 1): out of the totals, in `check` for a
    // person to pick again or skip; typed grams stay typed (the decision),
    // none derived. A skip stores no hold. The next compute asks again (one
    // request) only once a pick or an edit moves it.
    return (
      row: placed.copyWith(
        hold: skipped ? null : foodGoneHold,
        clearHold: skipped,
        clearGrams: !typed || !sameAmount,
        clearGramSource: !typed || !sameAmount,
      ),
      food: null,
      note: null,
      unavailable: null,
    );
  }
  final (food, resolution) = weighed;
  // v60 (M62): a dip's line reads M52's plan once ([_m52OnConfirm]) — E-w's
  // grams for a confirm, or H: the dip of a coat held with no budget is
  // held as the coat's lines are (`coating`, no grams), so the rules by
  // hold kind below decide it as they decide a held coat.
  final dip = _dipsOf(recipe).containsKey(position)
      ? _m52OnConfirm(
          db,
          recipe,
          placed,
          memo: m52Memo,
          pass: references,
        )
      : null;
  final heldDip = dip?.held ?? false;
  final outcome = heldDip
      ? (grams: null, source: null, hold: 'coating')
      : engineOutcome(recipe, eaten, food, resolution, decided: true);
  final medium = discardedMediumOf(recipe, eaten, normalized);
  final mediumLine = medium != null || heldDip;
  final held = mediumHolds.contains(outcome.hold);
  final keepTyped = typed && (sameAmount || mediumLine);
  // The weight the decision derives. A line with NO amount has none
  // (v26, Run 056 O13/S22): the engine's 0 g ([amountlessLinesZero]) is
  // the weight of a line no person decided. A pick names a food, not an
  // amount: it stays with no grams, in `no_grams`, for a person to weigh
  // (the contract goldens' reviewer move on "Confectioners' sugar, for
  // dusting"), and a held one keeps its hold by the kind rule below. A
  // confirm is "this food at the engine's current weight": a held medium
  // resolves to 0 g poured away (below; 0318's "Kosher salt" was stored
  // 0 g `unmeasured`, "eaten part counted"), an unheld line keeps the
  // engine's 0 g, left where it is (API.md). An amount-less line never
  // has an eaten part > 0 (the engine's 0 g wins, [engineOutcome]).
  // v53 (M52; verify2 D1): a confirm of a coat or frying oil M52 counts is
  // the plan's grams — the engine's current weight of it ([_m52OnConfirm]).
  final m52 = edited.status != 'confirmed' || typed
      ? null
      : dip ??
            (medium == DiscardedMedium.coating ||
                    medium == DiscardedMedium.fryingOil ||
                    // v56 (M58 W): a batter line the coat budget weighs.
                    _batterInBowl(recipe).contains(position) ||
                    // v66 (M67 A2): a cut dough's mix line.
                    _cutMixAt(recipe, position)
                ? _m52OnConfirm(
                    db,
                    recipe,
                    placed,
                    memo: m52Memo,
                    pass: references,
                  )
                : null);
  final weight = m52 != null
      ? m52.grams
      : eaten.amounts.isEmpty && edited.status == 'overridden'
      ? null
      : outcome.grams;
  // RULE A — what a person's decision resolves, by hold kind (API.md):
  // - typed grams answer every hold: the grams as typed, no hold;
  // - a skip stores no hold;
  // - a confirm — "this food, the engine's CURRENT weight": a held medium's
  //   eaten part when the engine knows one (a divided line, an eaten
  //   "plus" part, the rest of a written share), else 0 g poured away; no
  //   hold;
  // - a pick: a DIVIDED line (an eaten part the engine knows) counts it and
  //   resolves the hold; a wholly poured-away line (`discarded_medium`, no
  //   eaten part) is 0 g and resolved; any other line held as a medium
  //   part of which is eaten (`starter_discard`, `coating`,
  //   `partial_pour_away` with no eaten part known; `ambiguous_medium`, all
  //   of it or none, which nothing says) keeps its hold, no grams — 0 g
  //   would drop the part that is eaten with no flag. Which holds a pick
  //   keeps is the action table's ([holdActions]: a pick not among its
  //   `finishes`).
  final keepsHold =
      held &&
      !keepTyped &&
      edited.status == 'overridden' &&
      weight == null &&
      // The holds a pick alone keeps: the table's ([holdActions]) whose
      // finishes leave out a pick (the v28 closer's D2: one table).
      !holdActionsOf(outcome.hold).finishes.contains(HoldDecision.pick);
  final resolves = held && !keepTyped && !keepsHold;
  // A resolved medium's source is `discarded` whatever its grams: its eaten
  // part is read as kept from a poured-away line ([engineOutcome]), and
  // with none it is 0 g poured away (v25's `&& outcome.grams == null` term
  // let an amount-less line's 0 g `unmeasured` through — Run 056 A2).
  final grams = keepTyped
      ? edited.grams
      : resolves
      ? weight ?? 0
      : weight;
  final source = keepTyped
      ? edited.gramSource
      // v56 (M58 W): a batter line M52 weighs is `discarded`, as its coat.
      : resolves || m52 != null
      ? GramSource.discarded.name
      : weight == null
      ? null
      : outcome.source;
  // Rule B1 (v41, D12): a Confirm keeps a rendered row's two parts; a pick
  // (`overridden`) is one record at the line's raw grams — how a person
  // undoes the rule.
  final row = withParts(
    db,
    recipe,
    eaten,
    placed.copyWith(
      grams: grams,
      clearGrams: grams == null,
      gramSource: source,
      clearGramSource: source == null,
      hold: outcome.hold,
      clearHold: !keepsHold,
    ),
  );
  // The sub-recipe rule gates the row as a confirm or pick writes it: not a
  // skip, nor a row a person typed grams on (they count the line, whatever
  // the amount now weighs), nor a food on a reference line's food
  // alternative (v41 A10 a, gate 1: weighed there, [weighedLine]).
  final gated = skipped || typed || foodAlternativeOf(line) != null
      ? null
      : subRecipeRowFor(recipe, position, line) ??
            subRecipeRowFor(recipe, position, line, onFood: true, grams: grams);
  // The words for what the decision did (`hold_note`): a resolved medium
  // says so, a kept hold says what holds it.
  final note = gated != null || skipped
      ? null
      : resolves
      ? '${(weight ?? 0) > 0 ? 'eaten part counted' : 'poured away'} '
            'after your ${edited.status == 'confirmed' ? 'confirm' : 'pick'}'
      : keepsHold
      ? holdNoteOf(recipe, line, outcome.hold)
      : null;
  // Rule B1's part records, resolved as the food is (RULE A: the totals
  // never fetch) — a failure is this derivation's, as the food's is.
  if (gated == null) {
    try {
      await _resolveParts(db, provider, row);
    } on NutritionProviderException catch (failure) {
      return (
        row: edited.copyWith(position: position),
        food: null,
        note: null,
        unavailable: failure,
      );
    }
  }
  return (row: gated ?? row, food: food, note: note, unavailable: null);
}

/// Rule B1's part records ([withRenderedBacon]), resolved where the row's
/// food is (RULE A: the totals never fetch): a part no cache holds
/// ([knownFood]: the food cache, else a cached search hit — snapshot 17
/// holds 168322 as a hit of "thin-sliced cooked deli ham", so no request)
/// is fetched and cached ([_cachedFood]).
Future<void> _resolveParts(
  SaltDatabase db,
  NutritionProvider provider,
  IngredientMatchRow row,
) async {
  for (final part in partsOf(row.parts)) {
    if (knownFood(db, part.fdcId) == null) {
      await _cachedFood(db, provider, part.fdcId);
    }
  }
}

/// [decided] with ONLY the fields [derivedFor] derives taken from [row]
/// (the hold, the grams, their source): what a compute writes over a
/// decided row on its own line, and what the matches GET shows for it —
/// never its status or food (RULE A: a compute never changes a decision).
IngredientMatchRow withDerived(
  IngredientMatchRow decided,
  IngredientMatchRow row,
) => decided.copyWith(
  grams: row.grams,
  clearGrams: row.grams == null,
  gramSource: row.gramSource,
  clearGramSource: row.gramSource == null,
  hold: row.hold,
  clearHold: row.hold == null,
  // v41: a rendered row's parts and a composite row's share and stamp are
  // derived too (the child itself is the decision).
  parts: row.parts,
  clearParts: row.parts == null,
  childShare: row.childShare,
  childStamp: row.childStamp,
  clearChildStamp: row.childStamp == null,
);

/// [derivedFor]'s child arm (v41, design_v3 §2.2 item 4): a decided row
/// [placed] on its [line] that names a child recipe, as derived now. The
/// child GONE: held `choose_recipe` (its status kept, the `food_gone`
/// precedent), 0 g, the stamp cleared (N6: else the parent reads underived
/// after every sweep), the child's id kept (a re-import, same id, routes it
/// again). The child itself made from a recipe: held `nested_recipe`, 0 g,
/// its stamp kept. The child with no nutrition row: the row as stored (the
/// totals leave it underived — never FDC's `missing` path, F6). Else
/// counted: the share a person saved while the line's amount is the one it
/// was saved on ([sameAmount], as typed grams), else re-read from the line
/// and the child's yield ([parseShare]); grams = the child's total grams ×
/// the share; the stamp = the child's `computed_at`; any recipe hold
/// answered (the child is back).
IngredientMatchRow _childRowOf(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow placed, {
  required bool sameAmount,
  required ResolverMemo children,
}) {
  final child = nutritionRecipeOf(db, placed.childRecipeId!)?.recipe;
  if (child == null) {
    return placed.copyWith(
      hold: chooseRecipeHold,
      grams: 0,
      gramSource: GramSource.recipe.name,
      clearChildStamp: true,
      clearParts: true,
    );
  }
  final stored = children.childNutrition(child.id);
  if (nutritionLines(child).any((l) => isReferenceIn(child, l))) {
    return placed.copyWith(
      hold: nestedRecipeHold,
      grams: 0,
      gramSource: GramSource.recipe.name,
      childStamp: stored?.computedAt,
      clearChildStamp: stored == null,
    );
  }
  if (stored == null) {
    return placed;
  }
  final share = sameAmount && placed.childShare != null
      ? placed.childShare
      : parseShare(line.raw, line.amounts, child.servings);
  return placed.copyWith(
    grams: share == null ? 0 : (stored.totalGrams ?? 0) * share,
    gramSource: GramSource.recipe.name,
    childShare: share,
    childStamp: stored.computedAt,
    clearHold: true,
    clearParts: true,
  );
}

/// The parents routed to the section [key], re-read after a request
/// recomputed it — a person's decision on one of its lines, or an
/// apply-to-all reaching one (v47, F3 — Run 062 O3, Run 061 S5): the
/// queue's `finishes` credits them, so the request that decides keeps that
/// promise, never the next stale sweep (and its parents no longer read
/// stale, their `child_stamp` behind, until one). Each RECIPE holding a
/// row on the key (a section's own nested row counts nothing): its rows on
/// the key that stand on their line, not skipped, derived as its compute
/// derives a composite row ([_childRowOf]: the section's total grams × the
/// share, its stamp — no request), written only over the row as read and
/// under the layout read ([SaltDatabase.replaceIngredientMatchIfUnchanged]);
/// then its totals under its own in-progress mark, the stamp kept (its own
/// inputs did not move). Returns the parents whose stored status turned
/// `complete`, by id — recipes, never a key.
Future<List<String>> recomputeParentsOf(
  SaltDatabase db,
  NutritionProvider provider,
  String key,
) async {
  final completed = <String>[];
  for (final id in db.recipesReadingChildren([key])) {
    final parent = hostOf(id) == id ? nutritionRecipeOf(db, id)?.recipe : null;
    if (parent == null) {
      continue;
    }
    final memo = ResolverMemo(db);
    final lines = nutritionLines(parent);
    final seq = db.layoutSeqOf(id);
    final before = db.nutritionFor(id)?.status;
    final owned = db.markComputing(id);
    var wrote = false;
    var ended = false;
    try {
      for (final row in db.ingredientMatchesFor(id)) {
        final line = lines.elementAtOrNull(row.position);
        if (row.childRecipeId != key ||
            row.status == 'skipped' ||
            line == null ||
            line.raw != row.raw) {
          continue;
        }
        final derived = _childRowOf(
          db,
          line,
          row,
          sameAmount: true,
          children: memo,
        );
        if (!sameMatchRow(derived, row) &&
            db.replaceIngredientMatchIfUnchanged(
              derived,
              over: row,
              layoutSeq: seq,
            )) {
          wrote = true;
        }
      }
      await recomputeTotalsResolving(
        db,
        provider,
        parent,
        only: const {},
        ending: owned,
      );
      ended = true;
    } finally {
      if (!ended) {
        db.releaseComputing(id, owned: owned, stale: wrote);
      }
    }
    if (before != 'complete' && db.nutritionFor(id)?.status == 'complete') {
      completed.add(id);
    }
  }
  return completed;
}

/// What one target a request recomputed completed, by RECIPE (v47, F3):
/// [id] itself when it is a recipe whose stored status turned `complete`
/// from [before]; for a SECTION key, the parents its new totals completed
/// ([recomputeParentsOf]) — a section is not a recipe, and its key never
/// reaches the wire.
Future<List<String>> _completedBy(
  SaltDatabase db,
  NutritionProvider provider,
  String id,
  String? before,
) async => hostOf(id) != id
    ? await recomputeParentsOf(db, provider, id)
    : [
        if (before != 'complete' && db.nutritionFor(id)?.status == 'complete')
          id,
      ];

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
/// at the statement, and a guarded-out write is not counted. Each recipe's
/// rows are laid out on its lines first ([layoutMatchRows]); a row whose
/// recipe no longer has that line, or whose line is now another
/// ingredient, is left for the next compute — and so is every target of a
/// recipe laid out anew during an await (a save and a person's write or a
/// compute moved its rows): counted in `moved`, never written over a row
/// the layout put there. A target FDC cannot weigh now (the portions it
/// needs: RULE A's one outcome, v27) is not written, counted in
/// `unavailable`, and its recipe's totals are recomputed and stamped stale
/// (the stale sweep inherits the decision there). A recipe that fails —
/// its document will not decode — is logged, counted in
/// `failed`, and does not stop the rest; what was already written stays,
/// and the counts say exactly what landed: `lines` counts the rows whose
/// review bucket changed or that took the decided food — the rows
/// [decisionReach] offered, less those skipped or guarded out — `recipes`
/// the recipes holding one, and `completed` those of them whose stored
/// status turned `complete` with this apply (what the queue's `finishes`
/// promised; the receipt reconciles against it), `completedRecipes` their
/// ids. A reached recipe that was complete already (a different-food pick
/// reaches counted lines) is not counted: it was finished before. The
/// decided line's own recipe CAN be counted: its other lines of the item
/// are reached, and when they were its last open ones it completes here.
/// v47 (F3, Run 062 O3 / Run 061 S5): RECIPES only, never a section key —
/// a reached section line counts its HOST in `recipes`, and what it
/// completes is the parents routed to the section, recomputed in this
/// request ([recomputeParentsOf]); [alsoCompleted] seeds `completedRecipes`
/// (the parents the decided SECTION line's own write completed, its host
/// excepted — the PUT's).
Future<
  ({
    int recipes,
    int lines,
    int failed,
    int completed,
    List<String> completedRecipes,
    int moved,
    int decided,
    int gone,
    int failedLines,
    int unavailable,
  })
>
applyDecisionToOthers(
  SaltDatabase db,
  NutritionProvider provider, {
  required String itemKey,
  required FdcFood decided,
  required ({String recipeId, int position}) excluding,
  List<String> alsoCompleted = const [],
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
  // How many decided rows of each text a target recipe holds at the reach:
  // a target whose row is gone at its recipe's turn was decided meanwhile
  // only while more such rows stand then (Run 053 O5/S3).
  final decidedAtReach = {
    for (final id in byRecipe.keys)
      id: _decidedByRaw(db.ingredientMatchesFor(id)),
  };
  var lines = 0;
  var failed = 0;
  var failedLines = 0;
  var moved = 0;
  var decidedMeanwhile = 0;
  var gone = 0;
  var unavailable = 0;
  final reached = <String>{};
  final completed = [...alsoCompleted];
  for (final entry in byRecipe.entries) {
    // Every offered line ends in exactly one count: `lines` (written),
    // `decided` (a person decided it meanwhile), `gone` (its line is gone
    // or another ingredient now, or its recipe was deleted), `moved` (its
    // recipe laid out anew during an await: left for its compute),
    // `unavailable` (FDC could not serve the portions it needs: left as
    // the engine's row, RULE A — v27), or `failedLines` (its recipe failed:
    // its document will not decode) — Run 052 O14/S1.
    final settledBefore = decidedMeanwhile + gone + moved + unavailable;
    // This target's in-progress mark ([SaltDatabase.markComputing], v29
    // migration 017): taken before its first row write, released by its
    // totals — or below, stale when a row was written and no totals were.
    String? marked;
    var owned = false;
    var wrote = false;
    try {
      final found = nutritionRecipeOf(db, entry.key);
      if (found == null) {
        gone += entry.value.length; // Deleted; its rows cascaded away.
        continue;
      }
      // Its rows laid out on its lines first, as a compute or a person's
      // write lays them out ([layoutMatchRows]), under a layout every write
      // below checks in its own transaction (Run 051 C1/S7: a save and a
      // relayout during an await moved a decided row onto a target's
      // position, and the guarded write — its text differs — replaced it).
      final recipeLines = nutritionLines(found.recipe);
      final before = {
        for (final row in db.ingredientMatchesFor(found.recipe.id))
          row.position: row,
      };
      final paired = layoutMatchRows(db, found.recipe);
      final seq = db.layoutSeqOf(found.recipe.id);
      // Where the layout put each row: its old position -> its line's
      // (Run 052 O14: a sibling a save only shifted is found where it went,
      // not looked up at its stored position).
      final placed = {
        for (final (at, row) in paired.indexed)
          if (row != null) row.position: at,
      };
      var applied = 0;
      var unweighed = false;
      final taken = <int>{};
      final decidedNow = _decidedByRaw(before.values);
      final reachDecided = decidedAtReach[entry.key] ?? const {};
      for (final target in entry.value) {
        // The reached row as it stands now, by identity ([sameMatchRow]):
        // at its stored position, or wherever a layout since the reach
        // (another recipe's await) moved it — never another line's row
        // that took its position.
        final from =
            sameMatchRow(before[target.position], target) &&
                !taken.contains(target.position)
            ? target.position
            : before.entries
                  .where(
                    (e) =>
                        !taken.contains(e.key) && sameMatchRow(e.value, target),
                  )
                  .firstOrNull
                  ?.key;
        if (from == null) {
          // Not there any more (Run 053 O5/S3): a person decided it
          // meanwhile (a decided row of its text stands that did not at
          // the reach), its line is gone or another ingredient now, or a
          // compute rewrote it (left for that compute).
          // ponytail: counts by text, so a recipe holding a second line of
          // the item reads `moved` where its line became another
          // ingredient; match lines to rows if that ever matters.
          final raw = target.raw;
          if ((decidedNow[raw] ?? 0) > (reachDecided[raw] ?? 0)) {
            decidedNow[raw] = decidedNow[raw]! - 1;
            decidedMeanwhile += 1;
          } else if (!recipeLines.any(
            (line) => line.raw == raw || lineKeyOf(line) == itemKey,
          )) {
            gone += 1;
          } else {
            moved += 1;
          }
          continue;
        }
        taken.add(from);
        // Where the layout put it; it is written only on a line of its text
        // or of this ingredient: a line whose text changed takes it only as
        // the same ingredient (an amount edit not yet computed: written
        // under the line's text, with the line's grams — Run 051 E3, the
        // offer counted it).
        final at = placed[from];
        final line = at == null ? null : recipeLines[at];
        if (line == null ||
            (line.raw != target.raw && lineKeyOf(line) != itemKey)) {
          gone += 1; // Its line is gone, or another ingredient now.
          continue;
        }
        // A search hit stands in until a target needs portions; then the
        // detail is fetched once and serves every later target. Gated as
        // the compute writes it ([subRecipeRowFor]): a marked count its food
        // gives no grams is the 0 g sub-recipe (Run 047 critic). Weighed as
        // the compute weighs it ([weighedLine]): a same-food "plus" part
        // names no second food, so [decisionReach] reaches it (Run 048
        // critic: "1 recipe Garlic Oil (recipe follows), plus 2 tablespoons
        // garlic oil" weighed as the whole recipe, 140 g for 28).
        final eaten = weighedLine(found.recipe, line);
        final FdcFood onFood;
        final GramResolution? resolution;
        try {
          final GramResolution? weighed;
          (food, weighed) = await gramsFor(
            db,
            provider,
            food,
            eaten,
            recipe: found.recipe,
          );
          // Its nutrient record with it (v28, Sonnet critic 2 / S3): one
          // FDC no longer serves counts nothing — the target left as the
          // engine's row, like a weigh FDC cannot serve.
          if (await _siblingGone(db, provider, food.fdcId)) {
            throw const NutritionProviderException(
              'FoodData Central has no nutrient record for this food.',
              scope: FailureScope.food,
            );
          }
          // v39 (Y3): a target that discards the skin moves as its
          // compute would; [food] stays the decision for the next target.
          (onFood, resolution) = await skinOffFood(
            db,
            provider,
            found.recipe,
            eaten,
            food,
            weighed,
          );
        } on NutritionProviderException catch (error) {
          // The weigh is inside RULE A's one outcome (v27, Run 057 Opus
          // critic 1): a target whose portions FDC cannot serve now is not
          // written — it stays the engine's row, underived for this
          // decision, which its recipe's next compute inherits — and is
          // counted `unavailable`; the targets before it are written, and
          // the recipe's totals recomputed below and stamped STALE (never a
          // partial write under the old totals and a fresh stamp), so the
          // stale sweep visits it and inherits the decision there.
          _log.info('apply-to-all target ${entry.key}#$at unavailable: $error');
          unavailable += 1;
          unweighed = true;
          continue;
        }
        final outcome = engineOutcome(
          found.recipe,
          eaten,
          onFood,
          resolution,
          decided: true,
        );
        final row =
            subRecipeRowFor(found.recipe, at!, line) ??
            subRecipeRowFor(
              found.recipe,
              at,
              line,
              onFood: true,
              grams: outcome.grams,
            ) ??
            // Rule B1 (v41, D12): a carried bacon decision re-runs the rule
            // on the target's own steps.
            withParts(
              db,
              found.recipe,
              eaten,
              IngredientMatchRow(
                recipeId: found.recipe.id,
                position: at,
                raw: line.raw,
                itemKey: itemKey,
                fdcId: onFood.fdcId,
                description: onFood.description,
                dataType: onFood.dataType,
                confidence: 1,
                grams: outcome.grams,
                gramSource: outcome.source,
                status: 'auto',
                hold: outcome.hold,
              ),
            );
        if (row.hold != null) {
          // A LINE hold now (a decided food answers every food hold): the
          // recipe changed since the reach (a steps edit made the line a
          // dredge) — left for its compute, never written or counted as
          // reached (Run 053 Opus critic 3).
          moved += 1;
          continue;
        }
        if (db.layoutSeqOf(found.recipe.id) != seq) {
          // Laid out anew during an await: left for its compute — or the
          // recipe was deleted meanwhile (its layout cascaded away: Run 052
          // O6), or deleted and re-created without the line (Run 054 S3),
          // and the line is gone: the same reading as a row not found at
          // the turn (above), on the recipe as stored now.
          final now = nutritionRecipeOf(db, found.recipe.id)?.recipe;
          if (now == null ||
              !nutritionLines(now).any(
                (l) => l.raw == target.raw || lineKeyOf(l) == itemKey,
              )) {
            gone += 1;
          } else {
            moved += 1;
          }
          continue;
        }
        // In progress until its totals are written below (v29, migration
        // 017), marked BEFORE the row: a restart between them never leaves
        // a row the totals miss under a fresh stamp.
        if (marked == null) {
          marked = found.recipe.id;
          owned = db.markComputing(marked);
        }
        // Guarded at the statement: only an undecided row is replaced (a
        // person's decision during the awaits stands).
        if (!db.upsertIngredientMatchIfUndecided(row, layoutSeq: seq)) {
          decidedMeanwhile += 1;
          continue;
        }
        wrote = true;
        // Applied: every written row — its bucket changed or it took the
        // decided food, a line left short of an amount on it too ("2
        // (2-inch) strips lemon zest" stays no_grams on "Lemon, raw"): the
        // offer counted it, and the decision reached it (checkpoint 5
        // review). A row a line hold holds is not written (above), so no
        // written row stays in its bucket on its food — a write counted in
        // no bucket was the Run 053 Opus critic 3 hole.
        applied += 1;
      }
      // A write that moved no bucket and no counted food moved no total.
      if (applied == 0 && !unweighed) {
        continue;
      }
      final statusBefore = db.nutritionFor(found.recipe.id)?.status;
      await recomputeTotalsResolving(
        db,
        provider,
        found.recipe,
        only: foodsOf(food.fdcId),
        unavailable: unweighed,
        ending: owned,
      );
      marked = null; // Released by the totals.
      if (applied == 0) {
        continue;
      }
      // v47 (F3): RECIPES — a section target is its host's line, and what
      // it completes is the parents routed to it ([_completedBy]).
      reached.add(hostOf(found.recipe.id));
      lines += applied;
      for (final id in await _completedBy(
        db,
        provider,
        found.recipe.id,
        statusBefore,
      )) {
        if (!completed.contains(id)) completed.add(id);
      }
      // A recipe that will not decode must not stop the rest — and must be
      // counted. An EXCEPTION only (v29, Run 059 S29): the totals may ask
      // FDC for the target's own food ([recomputeTotalsResolving]), and a
      // programming Error (a fixture's UnrecordedAnswer, a StateError) must
      // propagate, never be counted `failed`. A target's weigh FDC cannot
      // serve is the `unavailable` arm above (Run 057 O14).
    } on Exception catch (error) {
      failed += 1;
      failedLines +=
          entry.value.length -
          (decidedMeanwhile + gone + moved + unavailable - settledBefore);
      _log.warning('apply-to-all failed for ${entry.key}: $error');
    } finally {
      if (marked != null) {
        db.releaseComputing(marked, owned: owned, stale: wrote);
      }
    }
  }
  return (
    recipes: reached.length,
    lines: lines,
    failed: failed,
    completed: completed.length,
    completedRecipes: completed,
    moved: moved,
    decided: decidedMeanwhile,
    gone: gone,
    failedLines: failedLines,
    unavailable: unavailable,
  );
}

// ---------------------------------------------------------------------------
// v53 (M52 — coats and frying-oil uptake; prep47 design_v2 §1 Q2 (a), Q3
// (a), Q24 (b), §2 M52; critic F1, F2, F8, F13; the owner's 2026-10-07
// standing authorization). RE-RULES checkpoint 9 Q2 ("dredging flour and
// crumbs HELD until a coating fraction is set"), the 2026-10-03 (night) (1)
// "the four fried dredges stay held", and amends the discarded-media zero
// for frying oil ("no source gives a fraction"): USDA's FNDDS fried-food
// recipes do, read from their `inputFoods` at the live steps M53/M55
// (.claude/diag/2026-10-07/prep47/p3_read_figures.md — every figure below
// is that table's READ figure, or its stated DERIVED one).

/// One FNDDS recipe whose `inputFoods` were read: `b` g of breading (USDA
/// 99995000) and `o` g of vegetable oil per `r` g of the raw `food` (a
/// cooked ingredient brought to raw by protein, USDA's retention
/// convention), as the flags print them.
typedef _Fndds = ({
  int id,
  String description,
  String food,
  String b,
  String o,
  String r,
});

const _Fndds _breastFried = (
  id: 2705975,
  description:
      'Chicken breast, fried, coated, prepared skinless, coating eaten, '
      'from raw',
  food: 'chicken breast',
  b: '15',
  o: '7',
  r: '104.76',
);
const _Fndds _thighFried = (
  id: 2706047,
  description:
      'Chicken thigh, fried, coated, prepared skinless, coating eaten, '
      'from raw',
  food: 'chicken thigh',
  b: '15',
  o: '7',
  r: '98.39',
);
const _Fndds _wingFried = (
  id: 2706065,
  description: 'Chicken wing, fried, coated, from raw',
  food: 'chicken wing',
  b: '15',
  o: '7',
  r: '105.96',
);
const _Fndds _countryFried = (
  id: 2705842,
  description: 'Beef, steak, country fried',
  food: 'beef steak',
  b: '20',
  o: '9',
  r: '90.99',
);
const _Fndds _codFried = (
  id: 2706244,
  description: 'Fish, cod, fried',
  food: 'cod',
  b: '25',
  o: '10',
  r: '65',
);
const _Fndds _haddockFried = (
  id: 2706258,
  description: 'Fish, haddock, fried',
  food: 'haddock',
  b: '25',
  o: '10',
  r: '65',
);
const _Fndds _shrimpFried = (
  id: 2706364,
  description: 'Shrimp, fried',
  food: 'shrimp',
  b: '25',
  o: '10',
  r: '65',
);
const _Fndds _breastBaked = (
  id: 2705980,
  description: 'Chicken breast, baked, coated, skin / coating eaten',
  food: 'chicken breast',
  b: '10',
  o: '2',
  r: '125.77',
);

/// v67 (M69 R2, Q6 a; L49 #3, live61_raw/2710050.json): FNDDS 2710050
/// lists 41.4 g "Eggplant, raw" and a BATTER of 13.2 g — flour 4 g, dried
/// egg 0.5, tap water 8.3, nonfat dry milk 0.3, baking powder 0.1 — whose
/// carbohydrate on the cached records (789890 77.3 %, 329490 1.87 %,
/// 172195 51.98 %, 172803 27.7 %; the dried egg's and dry milk's own SR
/// inputs are not cached — the same-description Foundation and the
/// vitamin-fortified twin are read) is 3.28499 g: k = 3.28499 / 41.4 ×
/// 100 = 7.93. `b` is the batter's mass ([_coatFlag] lists it); `o` the
/// two oils (4.4 + 0.5 g), never read for a coat.
const _Fndds _eggplantParm = (
  id: 2710050,
  description: 'Eggplant parmesan casserole, regular',
  food: 'eggplant',
  b: '13.2',
  o: '4.9',
  r: '41.4',
);
const _Fndds _legsBaked = (
  id: 2705998,
  description:
      'Chicken leg, drumstick and thigh, baked, coated, skin / coating eaten',
  food: 'chicken legs',
  b: '10',
  o: '2',
  r: '129.02',
);
const _Fndds _codBaked = (
  id: 2706243,
  description: 'Fish, cod, baked or broiled, coated',
  food: 'cod',
  b: '15',
  o: '4',
  r: '81',
);
const _Fndds _porkCoated = (
  id: 2705871,
  description: 'Pork, chop, coated, lean only eaten',
  food: 'pork chop',
  b: '10',
  o: '2',
  r: '108.38',
);
const _Fndds _cauliflowerFried = (
  id: 2710042,
  description: 'Fried cauliflower',
  food: 'cauliflower',
  b: '50',
  o: '12',
  r: '39.58',
);

/// v61 (M63, Q11; read at live step L3, .claude/diag/2026-10-08/
/// live60_raw/2706549.json): the crab cake fries in its own 5 g of oil per
/// 65 g of crab ("blue, cooked, moist heat" — the line's crab is cooked
/// too, so no protein conversion). Its 5 g of dry crumbs are mixed in, a
/// binder: no breading row, so no coat figure (`b` is never read).
const _Fndds _crabCakeFried = (
  id: 2706549,
  description: 'Crab, cake',
  food: 'crab',
  b: '0',
  o: '5',
  r: '65',
);

/// c_b, the FNDDS breading's (99995000) carbohydrate per gram: each read
/// recipe's own carbohydrate ÷ its breading grams on the six whose other
/// inputs are cooked, 0.397–0.401 (p3_read_figures.md) — v57 (M59 D)
/// scales [_cauliflowerFried]'s uptake by it. v60 (M62): the breading's own
/// record, FNDDS 2710785, confirms it — 40.1 g per 100 g.
const double _breadingCarbPerGram = 0.40;

/// v60 (M62 E-w, P2 read at live step L): the wet grams of FNDDS 2710785
/// "Breading or batter as ingredient in food" (food code 99995000, the
/// breading every read coat record lists) per gram of its carbohydrate —
/// 15 g egg and 120 g water in 287 g at 40.1 g carbohydrate per 100 g
/// (1.173): what [_m52Plan] sizes a coat's egg or buttermilk dip by.
const double _breadingWetPerCarb = (15 + 120) / (287 * 0.401);

/// The flag of a dip sized by [_breadingWetPerCarb] (v60, M62 E-w).
final String _dipFlag =
    'approximation (dip: ${_breadingWetPerCarb.toStringAsFixed(2)} g per g '
    "of the coat's carbohydrate — USDA FNDDS 2710785 \"Breading or batter as "
    'ingredient in food": 15 g egg and 120 g water in 287 g at 40.1 g '
    "carbohydrate per 100 g; the dip's excess not counted)";

/// An analytical SR Legacy record a figure is DERIVED from (no
/// `inputFoods` exist): P3's balance on its composition.
typedef _Sr = ({int id, String description});

const _Sr _squidFried = (
  id: 171982,
  description: 'Mollusks, squid, mixed species, cooked, fried',
);
const _Sr _friesSr = (
  id: 170698,
  description: 'Fast foods, potato, french fried in vegetable oil',
);
const _Sr _chipsSr = (
  id: 19411,
  description: 'Snacks, potato chips, plain, salted',
);
const _Sr _plantainsSr = (
  id: 168200,
  description: 'Plantains, yellow, fried, Latino restaurant',
);
const _Sr _tostadaSr = (id: 167525, description: 'Tostada shells, corn');

// v59 (M61 — fried doughs, fritters, rolls and falafel; prep48 design_v2
// §2 M61, §1 Q12; the owner's rulings R-a … R-e of 2026-10-08 under the
// 2026-10-07 standing authorization): the FNDDS recipes read at live step
// L1 (.claude/diag/2026-10-08/live60_raw/), `o` g oil per `r` g of their
// raw inputs other than the oil and water — the egg roll's 10 g of pork
// steak (2705875) brought to raw by protein on the lumpia's own raw pork
// (2514745), its prepared vegetable egg roll at the listed 90 g (no raw
// pair). No breading row: `b` is never read for these.
const _Fndds _pakoraFried = (
  id: 2710066,
  description: 'Pakora',
  food: 'pakora batter',
  b: '0',
  o: '21',
  r: '249.18',
);
const _Fndds _eggRollFried = (
  id: 2708702,
  description: 'Egg roll, with beef and/or pork',
  food: 'egg roll',
  b: '0',
  o: '8',
  r: '104.99',
);

/// R-d: FNDDS 2708072 "Doughnut, yeast type" lists this record alone and no
/// oil, so P3's balance reads it — with the PROTEIN tracer (the record is
/// glazed: a glaze carries carbohydrate, no protein) against the corpus
/// dough: 16.72 % (the carbohydrate tracer 13.35, the glaze's sugars netted
/// at most 25.67 — API.md's gaps).
const _Sr _doughnutSr = (
  id: 172758,
  description:
      'Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)',
);

/// v66 (M67 B, the owner's Q10 (a); prep49 design_v2 §2 M67, pD rule B):
/// a cake dough (struffoli; a doughnut or dough with no yeast row) on the
/// one input FNDDS 2708063 "Doughnut, cake type, plain" lists — no oil row,
/// so P3's balance reads it, with the CARBOHYDRATE tracer (the record is
/// unglazed: P3's uncoated convention, no departure) against the corpus
/// dough: D = 47.1 / 0.491276 = 95.873, O = 24.9 − 95.873 × 0.118227 =
/// 13.565, u = 14.15 % (the protein tracer 30.62 %; 2708024 "Fritter,
/// plain", a pourable batter, read 23.32 % before — the flag states both).
const _Sr _cakeDoughnutSr = (
  id: 174990,
  description:
      'Doughnuts, cake-type, plain (includes unsugared, old-fashioned)',
);

/// v68 (batch M70, pF L1; R-1 read 2026-10-09, live61_raw/raw_2709565.json):
/// FNDDS 2709565 "Yuca fries" lists 100 g "Cassava, raw", 15 g "Vegetable
/// oil, NFS" and 0.4 g salt — its input IS the raw cassava the yuca line
/// counts on (SR 169985), so the uptake is READ: 15 g oil per 100 g raw.
const _Fndds _yucaFries = (
  id: 2709565,
  description: 'Yuca fries',
  food: 'cassava',
  b: '0',
  o: '15',
  r: '100',
);

/// R-e: FNDDS 2707408 "Falafel" lists one cup of oil, the frying medium
/// (41.2 g fat per 100 g), never an uptake — P3's balance with the
/// carbohydrate tracer on this record: 21.64 % (protein 13.99).
const _Sr _falafelSr = (id: 172455, description: 'Falafel, home-prepared');

/// A coat or uptake figure (`value`, as the flag prints it) and where it
/// comes from: a READ FNDDS recipe or a DERIVED SR record; `standIn` when
/// the food has no record of its own and is read as the source's.
typedef _M52Figure = ({String value, _Fndds? read, _Sr? derived, bool standIn});

_M52Figure _readFig(String value, _Fndds read, {bool standIn = false}) =>
    (value: value, read: read, derived: null, standIn: standIn);

_M52Figure _derivedFig(String value, _Sr derived, {bool standIn = false}) =>
    (value: value, read: null, derived: derived, standIn: standIn);

/// The record families a coated food is counted on (P3-A): the largest
/// counted line on one of them is the food the coat is sized from.
const List<String> _meatRecords = [
  'Chicken,',
  'Turkey,',
  'Pork,',
  'Beef,',
  'Ham,',
  'Fish,',
  'Crustaceans,',
  'Mollusks,',
];

/// v67 (M69 R2, Q6 a): the vegetable records a coat may be sized from when
/// no meat is coated ([_coatedVegetable]) — ONLY records [_coatFigure] has
/// an arm for, and only at that arm's shape: its default arms are the
/// chicken breast's (FNDDS 2710055's onion rings list no coat input — they
/// stay held; the eggplant's one arm is C2).
const List<String> _coatVegetables = ['Eggplant,'];

/// The coated vegetable among [rows] of [recipe]: the largest counted row
/// on a [_coatVegetables] record whose head a coating sentence names
/// ([_coatsSentence], [_naming]) — 0407's "2 pounds globe eggplant" (S3
/// "… shake to coat the slices"); null when none, or when its shape is not
/// C2, the eggplant's one [_coatFigure] arm (v67 closer 2, D1: fried, C1 or
/// C1d, it would read the fried chicken breast's 5.73 or the steak's 8.79 —
/// it stays held, as before M69). The naming test is read once per head
/// (RULE C; v67 closer 1, D2: per row it rescanned the head's sentences,
/// O(lines × sentences) at the caps).
IngredientMatchRow? _coatedVegetable(
  Recipe recipe,
  Iterable<IngredientMatchRow> rows,
) {
  final index = _stepIndexOf(recipe);
  final heads = _headsOf(recipe);
  IngredientMatchRow? food;
  for (final r in rows) {
    final head = heads[r.position];
    if (_m52Counted(r) &&
        head != null &&
        _coatVegetables.any(r.description!.startsWith) &&
        (food == null ||
            r.grams! > food.grams! ||
            (r.grams == food.grams && r.position < food.position)) &&
        // Key: head — the food a coating sentence is searched for.
        index.memo(
          ('coatNamed', head),
          () => _naming(
            recipe,
            head,
          ).any((at) => _coatsSentence.hasMatch(index.sentence(at))),
        )) {
      food = r;
    }
  }
  return food != null &&
          _coatShapeOf(recipe, food.description!) == _CoatShape.c2
      ? food
      : null;
}

/// v67 (M69 R1, Q4 (i)): a step pounding the coated food thin — "pound
/// cutlets to even ¼-inch thickness" (0418), "pound the cutlets to an even
/// ¼-inch thickness" (0419–0421), "gently pound to even ½-inch thickness"
/// (0415, 0418) — never "slice into ¼-inch-thick pieces" (0235: no pound).
final RegExp _poundsThin = RegExp(
  r'\bpound\w*\b[^.]*?\bto (?:an )?(?:even )?(?:⅛|¼|⅜|½)-inch thick(?:ness)?\b',
);

/// A line printing a thin piece: "4 (5- to 6-ounce) sole or flounder
/// fillets, ⅜ inch thick (see note)" (0466) — never "¾ to 1 inch thick"
/// (0257's steaks).
final RegExp _thinLine = RegExp(
  r'(?<![\d¼½¾⅛⅜])(?:⅛|¼|⅜|½)[- ]inch[- ]thick\b',
);

/// Whether the coated food on [line] of [recipe] is a THIN piece
/// ([_m52Plan]'s C4): a step sentence pounds it ⅛–½ inch thick (read once
/// per recipe), or its line prints that thickness.
bool _thinPiece(Recipe recipe, IngredientLine line) =>
    _stepIndexOf(recipe).memo(
      #poundsThin,
      () => _stepIndexOf(recipe).allSentences.any(_poundsThin.hasMatch),
    ) ||
    _thinLine.hasMatch(line.raw.toLowerCase());

/// The food a meat record names, as the M52 flags print it: "chicken
/// breast", "chicken wings", "chicken", "cod", "shrimp", "beef".
String _m52FoodName(String description) {
  final d = description.toLowerCase();
  final words = d.split(', ');
  if (words.first == 'chicken') {
    for (final (part, name) in const [
      ('breast', 'chicken breast'),
      ('thigh', 'chicken thigh'),
      ('wing', 'chicken wings'),
      ('leg', 'chicken legs'),
    ]) {
      if (RegExp('\\b$part').hasMatch(d)) {
        return name;
      }
    }
    return 'chicken';
  }
  return const {'fish', 'crustaceans', 'mollusks'}.contains(words.first) &&
          words.length > 1
      ? words[1].split(' ').first
      : words.first;
}

/// The coat's shape (P3-A): C1 fried (a single dredge, or flour → egg →
/// crumb), C1d a second dredge after the egg, C2 baked, C3 floured seafood
/// fried, C5 a battered fish or shrimp. C4 — a sautéed dusting of a THIN
/// piece ([_thinPiece]; v67, M69 R1, the owner's Q4 ruling (b)) — has no
/// record and reads C2's (a thick piece's dusting stays held).
enum _CoatShape { c1, c1d, c2, c3, c4, c5 }

/// A sentence that dredges or coats ([_coatShapeOf]: the bake must come
/// after it).
final RegExp _coatsSentence = RegExp(r'\b(?:dredg|coat)');

/// A sentence that bakes the food ("Bake until …", "bake the chicken") —
/// never "keep warm in the oven" nor a roast ([_coatShapeOf]).
final RegExp _bakesSentence = RegExp(r'\bbake\b');

/// A second dredge after the egg: "Finally, coat with flour again" (0148),
/// "Coat the steaks with flour again" (0304) — C1d.
final RegExp _secondDredge = RegExp(
  r'\b(?:coat|dredg)\w*\b[^.]*\bflour again\b',
);

/// A sentence putting a food in the oil ("add to hot oil", "place in the
/// oil") — a frying sentence with [_fryVerb].
final RegExp _intoOil = RegExp(r'\b(?:to|in|into) (?:the )?(?:hot )?oil\b');

/// Whether [s] of [recipe] fries: the frying verb, a fat heated to a
/// frying temperature or discarded, an oil heated for a shallow fry
/// ([_heatsTheOil]) or a food put into the oil.
bool _m52Fries(Recipe recipe, String s) =>
    _fryVerb.hasMatch(s) ||
    _heatsTheOil.hasMatch(s) ||
    _intoOil.hasMatch(s) ||
    _fats.values.any(
      (fat) =>
          fat.heatsToFry(s, () => _heatReading(recipe, s)) ||
          fat.discards.hasMatch(s),
    );

/// The coat's shape in [recipe] for a food on [coated] (P3-A, critic F2):
/// a recipe that fries reads C1 (C5 a fish or shrimp a sentence batters; C3
/// Mollusks or Crustaceans with no crumb line; C1d a second dredge) —
/// unless a bake after the coat comes after its last frying sentence: the
/// LAST cook of the coated food decides, so browned in oil then baked reads
/// C2 (0118's cutlets; 0149's chicken, fried then baked). One that does not
/// fry reads C2 when a sentence after the coat bakes, else null — C4, a
/// sautéed dusting, is read in [_m52Plan] outside this memo (its line test
/// reads the coated ROW's line, never the description this memo keys).
_CoatShape? _coatShapeOf(Recipe recipe, String coated) =>
    // v60 (M62): once per recipe and coated food — a person's decision on
    // a dip plans M52 per row ([_m52OnConfirm]), and the steps' scan is
    // the plan's one read of every sentence (RULE C).
    // Key: coated — the record the shape tests (C5, C3).
    _stepIndexOf(
      recipe,
    ).memo(('coatShape', coated), () => _shapeOf(recipe, coated));

_CoatShape? _shapeOf(Recipe recipe, String coated) {
  final all = _stepIndexOf(recipe).allSentences;
  final coatAt = all.indexWhere(_coatsSentence.hasMatch);
  var lastBake = -1;
  var lastFry = -1;
  for (final (i, s) in all.indexed) {
    if (coatAt >= 0 && i > coatAt && _bakesSentence.hasMatch(s)) {
      lastBake = i;
    }
    if (_m52Fries(recipe, s)) {
      lastFry = i;
    }
  }
  if (!_fries(recipe) || lastBake > lastFry) {
    return lastBake >= 0 ? _CoatShape.c2 : null;
  }
  // v56 (M58 W, Q8): battered shrimp is C5 on its own record, before C3.
  if ((coated.startsWith('Fish,') ||
          coated.startsWith('Crustaceans, shrimp')) &&
      all.any((s) => s.contains('batter'))) {
    return _CoatShape.c5;
  }
  if ((coated.startsWith('Mollusks,') || coated.startsWith('Crustaceans,')) &&
      !_headsOf(recipe).any((h) => h == 'crumb' || h == 'panko')) {
    return _CoatShape.c3;
  }
  return all.any(_secondDredge.hasMatch) ? _CoatShape.c1d : _CoatShape.c1;
}

/// k, the coat's carbohydrate per 100 g of the raw coated food, for
/// [shape] on [coated] (p3_read_figures.md; per food where a same-food
/// record exists, critic F8: the thigh's 6.10, the wing's 5.66).
_M52Figure _coatFigure(_CoatShape shape, String coated) {
  final d = coated.toLowerCase();
  final chicken = d.startsWith('chicken');
  return switch (shape) {
    _CoatShape.c1 when chicken && d.contains('thigh') => _readFig(
      '6.10',
      _thighFried,
    ),
    _CoatShape.c1 when chicken && d.contains('wing') => _readFig(
      '5.66',
      _wingFried,
    ),
    _CoatShape.c1 => _readFig('5.73', _breastFried),
    _CoatShape.c1d => _readFig('8.79', _countryFried),
    _CoatShape.c2 when d.startsWith('fish') => _readFig('7.41', _codBaked),
    _CoatShape.c2 when d.startsWith('pork') => _readFig('6.61', _porkCoated),
    _CoatShape.c2
        when chicken &&
            !d.contains('breast') &&
            RegExp(r'\b(?:leg|thigh|drumstick)').hasMatch(d) =>
      _readFig('3.10', _legsBaked),
    // v67 (M69 R2): the coated vegetable's own read recipe.
    _CoatShape.c2 when d.startsWith('eggplant') => _readFig(
      '7.93',
      _eggplantParm,
    ),
    _CoatShape.c2 => _readFig('3.18', _breastBaked),
    // v67 (M69 R1, the owner's ruling (b), 2026-10-09): no record for a
    // sautéed dusting — C2's read, the lightest coat USDA prints, stands in
    // ([_coatFlag] names FNDDS 2706416's unused 7.82).
    _CoatShape.c4 => _readFig('3.18', _breastBaked, standIn: true),
    _CoatShape.c3 => _derivedFig('3.94', _squidFried),
    // v56 (M58 W): the battered food's own read record.
    _CoatShape.c5 when d.contains('shrimp') => _readFig('15.38', _shrimpFried),
    _CoatShape.c5 when d.contains('haddock') => _readFig(
      '15.38',
      _haddockFried,
    ),
    _CoatShape.c5 => _readFig('15.38', _codFried),
  };
}

/// A fried food's uptake class (P3-B, p3_read_figures.md): its `figure`
/// (u, the oil it absorbs as a % of its raw weight; null for O1c, bone-in
/// skin-on chicken, which absorbs none by USDA's own fat balance), its
/// `name` in the flag, the `word` a frying sentence names it by, and
/// whether it is a `meat` (counted only as a coat recipe's coated food).
typedef _FriedClass = ({
  _M52Figure? figure,
  String name,
  RegExp word,
  bool meat,
});

/// The uptake class of a fried food on [description] whose line reads
/// [item] (lower-cased) — or null when no record gives one (tempeh: it
/// stays 0; a dough, fritter or falafel a frying sentence names counts on
/// its oil by [_friedProductOf], v59; yuca on cassava reads FNDDS
/// 2709565's 15 %, v68). [coatHeld]: the recipe
/// holds a dredge on it (beef: the read cube steak, else a stand-in);
/// [shape]: its coat's (shrimp: C3 floured, O3, else battered, O2s);
/// [chips]: the recipe's potatoes are chips (grated, or "chips").
_FriedClass? _friedClassOf(
  String description,
  String item, {
  required bool coatHeld,
  required _CoatShape? shape,
  required bool chips,
}) {
  final d = description.toLowerCase();
  if (_meatRecords.any(description.startsWith)) {
    _FriedClass meat(_M52Figure? figure, String word) => (
      figure: figure,
      name: _m52FoodName(description),
      word: RegExp(word),
      meat: true,
    );
    final breast = _readFig('6.68', _breastFried, standIn: true);
    return switch (d) {
      _ when d.startsWith('chicken') => meat(
        d.contains('wing')
            ? _readFig('6.61', _wingFried)
            : d.contains('thigh')
            ? _readFig('7.11', _thighFried)
            : d.contains('meat and skin')
            ? null
            : _readFig('6.68', _breastFried),
        r'\b(?:chicken|wings?|cutlets?|breasts?|thighs?)\b',
      ),
      _ when d.startsWith('beef') => meat(
        _readFig('9.89', _countryFried, standIn: !coatHeld),
        r'\b(?:beef|steaks?)\b',
      ),
      _ when d.startsWith('fish') => meat(
        d.contains('cod')
            ? _readFig('15.38', _codFried)
            : d.contains('haddock')
            ? _readFig('15.38', _haddockFried)
            : breast,
        r'\b(?:fish|cod|haddock|fillets?)\b',
      ),
      _ when d.startsWith('crustaceans, shrimp') => meat(
        shape == _CoatShape.c3
            ? _derivedFig('5.3', _squidFried)
            : _readFig('15.38', _shrimpFried),
        r'\bshrimp\b',
      ),
      _ when d.startsWith('mollusks') => meat(
        _derivedFig('5.3', _squidFried),
        r'\b(?:squid|calamari)\b',
      ),
      // v61 (M63, Q11): the crab cake's own read oil.
      // ponytail: any fried crab reads the cake's figure (no corpus
      // soft-shell or other fried crab row).
      _ when d.startsWith('crustaceans, crab') => meat(
        _readFig('7.69', _crabCakeFried),
        r'\b(?:crab|cakes?)\b',
      ),
      _ => meat(breast, r'\b(?:pork|chops?|cutlets?|crab|cakes?)\b'),
    };
  }
  final words = '$item $d';
  final potato = RegExp(r'\bpotato(?:es)?\b|\bfries\b');
  return switch (words) {
    _ when words.contains('sweet potato') => (
      figure: _derivedFig('6.0', _friesSr, standIn: true),
      name: 'sweet potatoes',
      word: potato,
      meat: false,
    ),
    _ when words.contains('potato') => (
      figure: chips
          ? _derivedFig('10.9', _chipsSr)
          : _derivedFig('6.0', _friesSr),
      name: 'potatoes',
      word: potato,
      meat: false,
    ),
    _ when words.contains('plantain') => (
      figure: _derivedFig('5.5', _plantainsSr),
      name: 'plantains',
      word: RegExp(r'\bplantains?\b'),
      meat: false,
    ),
    _ when words.contains('eggplant') => (
      figure: _derivedFig('6.0', _friesSr, standIn: true),
      name: 'eggplant',
      word: RegExp(r'\beggplants?\b'),
      meat: false,
    ),
    _ when words.contains('corn tortilla') => (
      figure: _derivedFig('13.4', _tostadaSr),
      name: 'corn tortillas',
      word: RegExp(r'\btortillas?\b'),
      meat: false,
    ),
    _ when words.contains('cauliflower') => (
      figure: _readFig('30.32', _cauliflowerFried),
      name: 'cauliflower',
      word: RegExp(r'\bcauliflower\b'),
      meat: false,
    ),
    // v68 (M70, pF L1): fried yuca on SR 169985 "Cassava, raw".
    _ when words.contains('cassava') || words.contains('yuca') => (
      figure: _readFig('15.00', _yucaFries),
      name: 'yuca',
      word: RegExp(r'\byuca\b'),
      meat: false,
    ),
    _ => null,
  };
}

/// v59 (M61, Q12): the fried PRODUCT the [frying] sentences name when no
/// counted line is the fried food — the first word of a fixed order (a
/// named product before a bare batter or dough) — as an uptake class, or
/// null. [meat]: the raw mix counts a pork, beef or chicken row (a meatless
/// roll's record, FNDDS 2708700, was never read: no figure, Q12 iv);
/// [yeast]: it counts a yeast row (a cake dough's record, 2708063, lists no
/// oil: v66 (M67 B) P3's balance on its input, SR 174990, stands in).
_FriedClass? _friedProductOf(
  List<String> frying, {
  required bool meat,
  required bool yeast,
}) {
  _M52Figure? roll({bool standIn = true}) =>
      meat ? _readFig('7.62', _eggRollFried, standIn: standIn) : null;
  final fritter = _readFig('8.43', _pakoraFried, standIn: true);
  final cake = _derivedFig('14.15', _cakeDoughnutSr, standIn: true);
  for (final (word, name, figure) in <(String, String, _M52Figure?)>[
    ('lumpia', 'lumpia', roll()),
    ('egg rolls?', 'egg roll', roll(standIn: false)),
    ('spring rolls?', 'spring roll', roll()),
    ('pakoras?', 'pakora batter', _readFig('8.43', _pakoraFried)),
    ('fritters?', 'fritter batter', fritter),
    ('falafel', 'falafel mix', _derivedFig('21.64', _falafelSr)),
    ('struffoli', 'struffoli dough', cake),
    (
      'doughnuts?',
      'doughnut dough',
      yeast ? _derivedFig('16.72', _doughnutSr) : cake,
    ),
    ('batter', 'batter', fritter),
    (
      'dough',
      'dough',
      yeast ? _derivedFig('16.72', _doughnutSr, standIn: true) : cake,
    ),
  ]) {
    final re = RegExp('\\b(?:$word)\\b');
    if (frying.any(re.hasMatch)) {
      return figure == null
          ? null
          : (figure: figure, name: name, word: re, meat: false);
    }
  }
  return null;
}

/// v66 (M67 A2, the owner's Q9; prep49 design_v2 §2 M67): the share of a
/// rolled dough the steps cut and fry — the first step printing the sheet
/// ("10 by 13-inch rectangle"), the count ("cut 12 rounds") and the cutter
/// ("3-inch round cutter"): s = n·π(d/2)² / (L·W), 65.25 % on 1105 (the
/// holes cut from the rounds are fried too, so they stay inside the n
/// discs; the sheet is rolled even, so area is mass) — with the flag its
/// rows carry. Null unless 0 < s < 1. Once per recipe (`memo:cutShare`).
/// ponytail: rounds cut from a rectangle or square sheet only; any other
/// sheet or cut (an "8-inch square", rings, squares) reads the whole mix.
({double share, String flag})? _cutShareOf(Recipe recipe) =>
    _stepIndexOf(recipe).memo(#cutShare, () {
      for (final step in _stepIndexOf(recipe).lower) {
        if (!step.contains('round cutter')) {
          continue;
        }
        final sheet = _cutSheet.firstMatch(step);
        final count = _cutCount.firstMatch(step);
        final cutter = _roundCutter.firstMatch(step);
        if (sheet == null || count == null || cutter == null) {
          continue;
        }
        final [l, w, n, d] = [
          for (final v in [sheet[1], sheet[2], count[1], cutter[1]])
            int.tryParse(v!) ?? 0,
        ];
        final s = n * pi * d * d / 4 / (l * w);
        if (!(s > 0 && s < 1)) {
          return null;
        }
        final rest = step.contains('if desired')
            ? ', cut only "if desired",'
            : '';
        return (
          share: s,
          flag:
              'approximation (the cut share ${(s * 100).toStringAsFixed(2)} '
              "%: $n × $d-inch rounds from the steps' $l by $w-inch sheet; "
              'the remaining dough$rest not counted)',
        );
      }
      return null;
    });

final RegExp _cutSheet = RegExp(r'(\d+) by (\d+)-inch (?:rectangle|square)');
final RegExp _cutCount = RegExp(r'\bcut (\d+) rounds\b');
final RegExp _roundCutter = RegExp(r'(\d+)-inch round cutter');

/// Whether line [i] of [recipe] may be a cut dough's mix line: the steps
/// print a cut share ([_cutShareOf]), the line is no medium and a frying oil
/// follows it in its ingredient group — text only, the gate of the readers
/// beside [_m52Plan] ([_m52RowOf], [derivedFor], [_m52Key]); the plan
/// decides. The lines once per Recipe instance (a Recipe is immutable): the
/// key reads every row of every confirm's list.
bool _cutMixAt(Recipe recipe, int i) => (_cutMix[recipe] ??= () {
  final at = <int>{};
  if (_cutShareOf(recipe) == null) {
    return at;
  }
  var start = 0;
  for (final g in recipe.ingredients) {
    var oil = false;
    for (var i = start + g.items.length - 1; i >= start; i--) {
      final medium = _mediumAt(recipe, i);
      if (medium == DiscardedMedium.fryingOil) {
        oil = true;
      } else if (medium == null && oil) {
        at.add(i);
      }
    }
    start += g.items.length;
  }
  return at;
}()).contains(i);
final Expando<Set<int>> _cutMix = Expando();

/// Whether [_friedClassOf] reads line i of a Recipe instance on a record's
/// description as a fried food, once per (i, description) ([_m52Key]).
final Expando<Map<(int, String), bool>> _friedLines = Expando();

/// O1c's basis (p3_read_figures.md): a bone-in skin-on chicken fried in the
/// oil absorbs none of it net — USDA's skin-on fried legs carry less fat
/// than the raw parts the engine already counts.
const String o1cBasis =
    'frying oil: 0 g — USDA FNDDS 2705996 recipe adds 7 g oil per 100 g, '
    'but the fried skin-on parts carry less fat (17.2 g) than the raw parts '
    'counted here: no net uptake';

/// The flag of a coat sized by [figure] on the raw [name] in [shape];
/// [batter]: a batter left in the bowl is among its parts (v56, M58 W).
/// v56 (M58 S): a read figure of another food says it stands in, as
/// [_uptakeClause] does; a batter on a C1/C2 breading figure says so (F10).
/// v67 (M69 R2, closer 3): FNDDS 2710050 IS a batter figure — a batter on it
/// is not "a batter read on a breading figure", and its "a crumb coat read on
/// a batter figure" is said only when the coat is a crumb (no batter).
String _coatFlag(
  _M52Figure figure,
  String name,
  _CoatShape shape, {
  required bool batter,
}) {
  final read = figure.read;
  // v65 (M66, pC Q1 b): a C5 batter says what is applied — FNDDS's
  // breading at its carbohydrate, never a batter MASS (the auditors read
  // the shipped text as one).
  final breading = shape == _CoatShape.c5
      ? ' (USDA 99995000, 40.1 % carbohydrate)'
      : '';
  final matched = shape == _CoatShape.c5 ? ', matched by its carbohydrate' : '';
  // v67 (M69 R2): the coat noun by record — FNDDS 2710050's coat is a
  // batter, listed.
  final eggplant = read?.id == _eggplantParm.id;
  final coat = eggplant
      ? 'batter (4 g flour, 0.5 g dried egg, 8.3 g water, 0.3 g dry milk, '
            '0.1 g baking powder; 3.28 g carbohydrate)'
      : 'breading';
  final source = read != null
      ? 'USDA FNDDS ${read.id} recipe: ${read.b} g $coat$breading per '
            '${read.r} g raw ${read.food}$matched'
      : 'derived from USDA SR Legacy ${figure.derived!.id} '
            '"${figure.derived!.description}"';
  // v67 (M69 R1, the owner's ruling (b)): C4 names its stand-in and the
  // read it does not use, on every food (the sole too).
  final standIn = shape == _CoatShape.c4
      ? ' (no record for a sautéed flour dusting; read as the baked breaded '
            'breast, the lightest coat USDA prints; FNDDS 2706416 Veal '
            "Marsala's 62.5 g flour per 617.60 g raw veal, 7.82, counts the "
            "dish's whole flour, sauce included, and is not read)"
      : eggplant
      ? ' (${batter ? '' : 'a crumb coat read on a batter figure; '}8.3 g '
            'of the 13.2 g batter is water and carries no carbohydrate)'
      : read != null && read.food.split(' ').first != name.split(' ').first
      ? _standIn(name, read.description)
      : '';
  final onBreading =
      !eggplant &&
          batter &&
          const {_CoatShape.c1, _CoatShape.c1d, _CoatShape.c2}.contains(shape)
      ? ' (a batter read on a breading figure)'
      : '';
  return 'approximation (coat: ${figure.value} g carbohydrate per 100 g of '
      'the raw $name — $source$standIn$onBreading; the '
      "${batter ? 'batter' : 'dredge'}'s excess not counted)";
}

/// A figure read on another food's [description] stands in for [name].
String _standIn(String name, String description) =>
    ' (no record for $name; read as $description)';

/// One fried food's clause of an uptake flag; [batter]: its read u scaled
/// to the recipe's batter, C of K g carbohydrate (v57, M59 D).
String _uptakeClause(
  _M52Figure figure,
  String name, {
  ({double c, double k})? batter,
}) {
  final read = figure.read;
  final whose = name.endsWith('s') ? "$name'" : "$name's";
  final source = read != null
      ? 'USDA FNDDS ${read.id} recipe: ${read.o} g oil per ${read.r} g raw '
            '${read.food}'
      : 'derived from USDA SR Legacy ${figure.derived!.id} '
            '"${figure.derived!.description}"';
  // v66 (M67 B, critic F8): the cake doughnut names its tracer and the
  // spread — the protein tracer's figure and the fritter batter's read one.
  final cake = figure.derived?.id == _cakeDoughnutSr.id;
  final standIn = !figure.standIn
      ? ''
      : cake
      ? ' (no record for $name; read as a cake doughnut; by its protein '
            "30.62 %; FNDDS 2708024's fritter batter reads 23.32 %)"
      : _standIn(name, read?.description ?? figure.derived!.description);
  final tracer = cake ? ' by its carbohydrate' : '';
  if (batter != null) {
    final u = double.parse(figure.value) * batter.c / batter.k;
    return '${u.toStringAsFixed(2)} % of the raw $whose weight — $source, '
        "scaled to the recipe's batter (${batter.c.toStringAsFixed(2)} g of "
        '${batter.k.toStringAsFixed(2)} g carbohydrate)$standIn';
  }
  return '${figure.value} % of the raw $whose weight — $source$tracer'
      '$standIn';
}

/// One row M52 counts ([_m52Plan]), `discarded` as a medium's kept part
/// is: its `grams`, the `flag` its basis carries, the part `kept` outside
/// the budget (a frying oil's kept part, a coat's part eaten outside the
/// dredge), whether it is a `coat`, and whether its fried food absorbs
/// none (`noNetUptake`, O1c). v60 (M62): a coat's egg or buttermilk `dip`
/// ([_dipsOf]); `held`, the dip of a coat held with no budget (H: an
/// engine row takes the coat's hold, `coating`, no grams — any status
/// carries it, so a person's decision reads it, [derivedFor]). v66 (M67
/// A2): `cut`, a fried dough's mix line counted at the steps' cut share.
typedef _M52Row = ({
  double grams,
  String? flag,
  double kept,
  bool coat,
  bool noNetUptake,
  bool dip,
  bool held,
  bool cut,
});

/// What M52 counts on the rows of [recipe] the engine weighs ([_m52Weighs]:
/// `auto`, or a person's confirm with no typed grams — a pick or typed grams
/// stand), read from [rows] as stored — a pure function of the recipe's
/// text, its other rows and their records ([food]), never of the rows it
/// rewrites, so [recomputeTotals] writes it on every path that totals a
/// recipe and [gramBasisFor] re-reads the same answer:
/// - THE COAT (Q2 a, P3-A): a line the engine holds `coating` counts f =
///   min(1, B / Σ coat carbohydrate) of its dredge, B = k × the COATED
///   FOOD's grams / 100 (the largest counted line on a meat, poultry or
///   seafood record; v67, M69 R2: with none, a coated vegetable —
///   [_coatedVegetable]), the reached coat lines sharing B by their
///   carbohydrate (dredge grams × the record's) — its written part eaten
///   outside the dredge on top, its source the line's; k by the coat's
///   shape ([_coatShapeOf], [_coatFigure]; v67, M69 R1: a shape-less coat
///   on a thin piece is C4, [_thinPiece]); a C5 batter's counted flour
///   and starch come off B; a thick piece's dusting stays held, and a nut
///   or cheese layer unless a step names it with a crumb (v65, M66 R3:
///   [_layerInCrumb]). NOT a fraction of the line (CP9's "no blanket
///   coating fraction" stands): f is the food's. v56 (M58 W, Q8): the
///   lines a batter leaves in the bowl ([_batterInBowl]) are parts too —
///   the whole line the dredge, none eaten, never off B — every part at
///   the one f.
/// - THE DIP (v60, M62 E-w, Q9): the lines of an egg or buttermilk dip
///   ([_dipsOf]) of a budgeted coat count f_w = min(1, W / Σ their whole
///   grams), W = [_breadingWetPerCarb] × B (v65, M66 R1: never the parts'
///   Σ) — the coat's parts unchanged; a part of a dip line a later step
///   writes counts whole on top (R2); a dip with no coat or batter line
///   beside it opens the budget where the recipe shallow-fries the coated
///   food ([_shallowFries], its frying oil a medium) and it has a shape
///   (R4); a coat held with no budget holds its dips with it (H, the
///   owner's Q9).
/// - THE FRYING OIL (Q3 a, P3-B): a line the engine zeroes as frying oil
///   counts u × the fried food's grams / 100 ([_friedClassOf]) on top of
///   its kept part — the M49-marked pour-off too (F13) — capped at the line
///   less that part, two oils of one fry split by their grams (none on a
///   printed yield's part, [_yieldKept]: it is all the oil eaten); the fried
///   food is the coated food in a recipe that holds or counts a coat
///   ([_shallowFries], Q24 b), plus every counted vegetable a frying
///   sentence names (0255's chips beside its cod), else the counted foods
///   its frying sentences name — never the largest protein.
Map<int, _M52Row> _m52Plan(
  SaltDatabase db,
  Recipe recipe,
  List<IngredientMatchRow> rows,
  FdcFood? Function(int fdcId, IngredientLine line) food,
) {
  m52PlanRuns++;
  final lines = nutritionLines(recipe);
  final at = <int, IngredientMatchRow>{
    for (final r in rows)
      if (r.position < lines.length && lines[r.position].raw == r.raw)
        r.position: r,
  };
  // The candidates are read from the ROWS (RULE C: never every line's
  // detectors, so a recompute of a reached recipe reads only these lines):
  // an engine row held `coating`, or one it counted `discarded` — a frying
  // oil, its kept part, a coat this plan budgeted.
  final media = <int, DiscardedMedium?>{
    for (final r in at.values)
      if (_m52Weighs(r) &&
          // v60 (M62): a dip's line is no medium ([_dipsOf]).
          !_dipsOf(recipe).containsKey(r.position) &&
          (r.hold == 'coating' ||
              (r.hold == null && r.gramSource == GramSource.discarded.name)))
        r.position: discardedMediumOf(
          recipe,
          lines[r.position],
          normalizeItem(lineItemOf(lines[r.position])),
        ),
  };
  final coats = [
    for (final MapEntry(:key, :value) in media.entries)
      if (value == DiscardedMedium.coating) key,
  ]..sort();
  final oils = [
    for (final MapEntry(:key, :value) in media.entries)
      if (value == DiscardedMedium.fryingOil) key,
  ]..sort();
  // v56 (M58 W, Q8): a batter left in the bowl ([_batterInBowl], a
  // text-only memo — RULE C intact) joins the coat: each line a part, its
  // whole grams the dredge, none eaten outside it.
  final batter = {
    for (final i in _batterInBowl(recipe))
      if (at.containsKey(i) && media[i] != DiscardedMedium.coating) i,
  };
  // v60 (M62): an egg or buttermilk dip's lines ([_dipsOf], text-only — no
  // medium line among them); a batter's stay at its one f.
  final dips = [
    for (final i in _dipsOf(recipe).keys)
      if (at.containsKey(i) && !batter.contains(i)) i,
  ]..sort();
  if (coats.isEmpty && batter.isEmpty && oils.isEmpty) {
    return const {};
  }
  bool counted(IngredientMatchRow r) => _m52Counted(r);
  bool engine(IngredientMatchRow? r) => _m52Engine(r);
  double round2(double v) => double.parse(v.toStringAsFixed(2));
  IngredientMatchRow? coated;
  if (coats.isNotEmpty || batter.isNotEmpty || _shallowFries(recipe)) {
    for (final r in at.values) {
      if (counted(r) &&
          _meatRecords.any(r.description!.startsWith) &&
          (coated == null ||
              r.grams! > coated.grams! ||
              (r.grams == coated.grams && r.position < coated.position))) {
        coated = r;
      }
    }
  }
  // v67 (M69 R2, Q6 a): no meat beside a held coat — the coat is sized
  // from a coated vegetable ([_coatedVegetable]); the frying-oil block's
  // `coated` stays the meat (a vegetable's shape is never C3, the one shape
  // that block reads).
  final coatedFood =
      coated ?? (coats.isEmpty ? null : _coatedVegetable(recipe, at.values));
  // v67 (M69 R1, the owner's Q4 (b)): a held coat on a meat that neither
  // fries nor bakes after the coat is C4 when the piece is thin
  // ([_thinPiece]) — read here, outside [_coatShapeOf]'s memo (it keys the
  // description; the line test reads the coated row's line).
  final shape = coatedFood == null
      ? null
      : _coatShapeOf(recipe, coatedFood.description!) ??
            (coated != null &&
                    coats.isNotEmpty &&
                    _thinPiece(recipe, lines[coated.position])
                ? _CoatShape.c4
                : null);
  final plan = <int, _M52Row>{};
  // M58 W's batter parts' carbohydrate at their WHOLE grams (the line's, as
  // the dredge takes them): the plan writes those rows `discarded`, so D
  // ([batterOf]) reads them here — never the stored row — on every path.
  final batterCho = <int, double>{};
  // v65 (M66 R4, pC R4, P9): an egg dip with no coat or batter line beside
  // it opens the budget too where the coated food has a shape — its wet
  // share is the food's read record's (R1's C = B; 0415's egg-and-flour wash
  // under a pressed Parmesan crust, the crust counted whole). With no coat
  // or batter line `coated` exists only where a frying oil is a medium and
  // the recipe shallow-fries ([_shallowFries], Q24 b): a baked or air-fried
  // egg wash keeps D5's bowl flag (closer 2, D1).
  final budgeted =
      coatedFood != null &&
      shape != null &&
      (coats.isNotEmpty || batter.isNotEmpty || dips.isNotEmpty);
  if (budgeted) {
    final figure = _coatFigure(shape, coatedFood.description!);
    var budget = double.parse(figure.value) * coatedFood.grams! / 100;
    if (shape == _CoatShape.c5) {
      for (final r in at.values) {
        // A batter's lines are parts below, never off B (M58 W).
        if (counted(r) &&
            !batter.contains(r.position) &&
            _dredgeHeads.contains(_headsOf(recipe)[r.position])) {
          final record = food(r.fdcId!, lines[r.position]);
          budget -= r.grams! * (record?.nutrientsPer100g['205'] ?? 0) / 100;
        }
      }
    }
    final parts = <({int at, double dredge, double eaten, double cho})>[];
    for (final i in [...coats, ...batter]..sort()) {
      final r = at[i];
      if (!engine(r) ||
          (r!.hold != null && r.hold != 'coating') ||
          // v65 (M66 R3, Q5 a GATED): a nut or cheese layer joins only
          // when a step names it with a crumb ([_layerInCrumb]).
          ((r.description!.startsWith('Nuts,') ||
                  r.description!.startsWith('Cheese,')) &&
              !_layerInCrumb(recipe, i))) {
        continue;
      }
      final record = food(r.fdcId!, lines[i]);
      final full = record == null
          ? null
          : lineGrams(db, lines[i], record, recipe: recipe);
      if (full == null) {
        continue;
      }
      if (batter.contains(i)) {
        // M58 W: the whole line is batter (a record below the gate counts
        // nothing and shares nothing).
        if (!(r.status == 'auto' && belowConfidenceGate(r.confidence))) {
          final cho = (record!.nutrientsPer100g['205'] ?? 0) / 100;
          parts.add((at: i, dredge: full.grams, eaten: 0, cho: cho));
          batterCho[i] = full.grams * cho;
        }
        continue;
      }
      final base = engineOutcome(
        recipe,
        lines[i],
        record!,
        full,
        decided: true,
      );
      if (base.hold != 'coating') {
        continue;
      }
      final eaten = base.grams ?? 0;
      parts.add((
        at: i,
        dredge: max(full.grams - eaten, 0),
        eaten: eaten,
        cho: (record.nutrientsPer100g['205'] ?? 0) / 100,
      ));
    }
    final carbs = parts.fold<double>(0, (n, p) => n + p.dredge * p.cho);
    if (carbs > 0) {
      final f = min(1, max(budget, 0) / carbs);
      final flag = _coatFlag(
        figure,
        _m52FoodName(coatedFood.description!),
        shape,
        batter: parts.any((p) => batter.contains(p.at)),
      );
      for (final p in parts) {
        plan[p.at] = (
          grams: round2(f * p.dredge + p.eaten),
          flag: flag,
          kept: p.eaten,
          coat: true,
          noNetUptake: false,
          dip: false,
          held: false,
          cut: false,
        );
      }
    }
    // v60 (M62 E-w): the dip on the food — W = [_breadingWetPerCarb] × C,
    // shared by the dip lines' whole grams; a line below the gate shares
    // nothing (M58 W's precedent). v65 (M66 R1, pC R1): C = B — the coated
    // food's own read record's wet breading per gram of raw food, never
    // capped at the parts' Σ (a coat whose parts count less than B, or a
    // dip with no part at all, R4).
    final wet = _breadingWetPerCarb * max(budget, 0);
    final dipped = <({int at, double dredge, double eaten})>[];
    for (final i in dips) {
      final r = at[i];
      if (!engine(r) ||
          (r!.hold != null && r.hold != 'coating') ||
          (r.status == 'auto' && belowConfidenceGate(r.confidence))) {
        continue;
      }
      final record = food(r.fdcId!, lines[i]);
      final full = record == null
          ? null
          : lineGrams(db, lines[i], record, recipe: recipe);
      if (full != null) {
        _count('dipsSized');
        // v65 (M66 R2, pC R2): a part of the line a step AFTER the dip
        // writes — "remaining ¼ teaspoon zest" (0042 S4) — is eaten outside
        // the dip, whole ([_eatenOutsideMedium], the coat's reader, as
        // [engineOutcome] weighs a coat's); the rest is the dip's. The step
        // names the line by its head or by its item's last word ("orange
        // zest": head 'orange', written "zest"; "large eggs": "eggs") —
        // never a mention another line of that word or of the head writes
        // (closer 1, D1: [_amountWritersOf]'s ownHead; a line with no head
        // passes the word itself).
        final normalized = normalizeItem(lineItemOf(lines[i]));
        final after = _dipsOf(recipe)[i]!.at.$1;
        final head = _headsOf(recipe)[i];
        final last = normalized.split(' ').last;
        final part =
            _eatenOutsideMedium(
              recipe,
              lines[i],
              head,
              DiscardedMedium.coating,
              after: after,
            ) ??
            (last == head
                ? null
                : _eatenOutsideMedium(
                    recipe,
                    lines[i],
                    last,
                    DiscardedMedium.coating,
                    after: after,
                    ownHead: head ?? last,
                  ));
        final eaten = part == null
            ? 0.0
            : resolveGrams(
                    amounts: [part.amount],
                    food: record,
                    normalizedItem: normalized,
                    kosherSalt: packsLikeKosherSalt(lines[i].raw),
                  )?.grams ??
                  0.0;
        dipped.add((
          at: i,
          dredge: max(full.grams - eaten, 0),
          eaten: eaten,
        ));
      }
    }
    final whole = dipped.fold<double>(0, (n, d) => n + d.dredge);
    final share = whole > 0 ? min(1, wet / whole) : 0;
    for (final d in dipped) {
      plan[d.at] = (
        grams: round2(share * d.dredge + d.eaten),
        flag: _dipFlag,
        kept: d.eaten,
        coat: true,
        noNetUptake: false,
        dip: true,
        held: false,
        cut: false,
      );
    }
  } else if (coats.isNotEmpty) {
    // v60 (M62 H, Q9 — the owner's one-way door): a coat held with no
    // budget holds its dip with it — every row on a record (a person's
    // decision reads it); [recomputeTotals] holds the engine's rows, a
    // person's confirm resolves to 0 g poured away.
    for (final i in dips) {
      final r = at[i]!;
      if (r.fdcId == null ||
          r.childRecipeId != null ||
          (r.hold != null && r.hold != 'coating') ||
          (r.status == 'auto' && belowConfidenceGate(r.confidence))) {
        continue;
      }
      plan[i] = (
        grams: 0,
        flag: null,
        kept: 0,
        coat: true,
        noNetUptake: false,
        dip: true,
        held: true,
        cut: false,
      );
    }
  }
  final fryers = [
    for (final i in oils)
      if (engine(at[i]) &&
          at[i]!.hold == null &&
          at[i]!.gramSource == GramSource.discarded.name)
        i,
  ];
  if (fryers.isEmpty) {
    return plan;
  }
  final all = _stepIndexOf(recipe).allSentences;
  final chips = all.any(RegExp(r'\bchips\b').hasMatch);
  final title = recipe.title.toLowerCase();
  final friedTitle = RegExp(r'\bfried\b').hasMatch(title);
  final fried = <({_FriedClass kind, double grams, int at})>[];
  _FriedClass? kindOf(IngredientMatchRow r) {
    final line = lines[r.position];
    final words =
        '${normalizeItem(lineItemOf(line))} ${line.raw.toLowerCase()}';
    return _friedClassOf(
      r.description!,
      words,
      coatHeld: coats.isNotEmpty,
      shape: shape,
      chips: chips || RegExp(r'\b(?:grated|shredded)\b').hasMatch(words),
    );
  }

  if (coated != null) {
    final kind = kindOf(coated);
    if (kind != null) {
      fried.add((kind: kind, grams: coated.grams!, at: coated.position));
    }
  }
  for (final r in at.values) {
    if (identical(r, coated) || !counted(r)) {
      continue;
    }
    final kind = kindOf(r);
    if (kind == null || (kind.meat && coated != null)) {
      continue;
    }
    // A frying sentence names it: the verb or "into the oil" — a vegetable
    // also by a sentence naming it with the oil ("Combine the potatoes,
    // oil …", 0317; "Transfer the potatoes and remaining 1 cup oil to the
    // skillet", 0215's pour-off the M49 mark found) — or a "Fried …" title
    // does (0706 Plátanos Maduros (Fried Sweet Plantains) prints no steps).
    if ((friedTitle && kind.word.hasMatch(title)) ||
        all.any(
          (s) =>
              kind.word.hasMatch(s) &&
              (_fryVerb.hasMatch(s) ||
                  _intoOil.hasMatch(s) ||
                  (!kind.meat && RegExp(r'\boil\b').hasMatch(s))),
        )) {
      fried.add((kind: kind, grams: r.grams!, at: r.position));
    }
  }
  // The ingredient group holding position [i]: [start, end).
  (int, int) groupOf(int i) {
    var start = 0;
    for (final g in recipe.ingredients) {
      final end = start + g.items.length;
      if (i < end) {
        return (start, end);
      }
      start = end;
    }
    return (start, start);
  }

  // v59 (M61, Q12): no counted line is the fried food (O1c's chicken is
  // one) — a PRODUCT a frying sentence names is ([_friedProductOf]), its
  // raw mix the counted rows of the oil line's ingredient group before it
  // (Q12 ii: water carries no record and drops out; a sauce or a glaze
  // group never joins).
  if (fried.isEmpty) {
    final (start, _) = groupOf(fryers.first);
    // v66 (M67 A2, Q9): a dough the steps roll to a sheet and cut counts
    // only the cut share ([_cutShareOf]) — each row the plan weighs at s ×
    // its WHOLE line, never its stored grams (the plan writes those: closer
    // 2's V2-D1 double scaling), the uptake on the cut grams; a pick or
    // typed grams (never written here) at its own.
    // ponytail: a dough line another rule discards would count at the
    // share too — one corpus recipe prints the geometry, none such.
    final share = _cutShareOf(recipe);
    final cut = <int, double>{};
    final mix = <IngredientMatchRow>[];
    for (final r in at.values) {
      if (r.position < start || r.position >= fryers.first) {
        continue;
      }
      if (share != null &&
          engine(r) &&
          r.hold == null &&
          !(r.status == 'auto' && belowConfidenceGate(r.confidence)) &&
          _mediumAt(recipe, r.position) == null) {
        final record = food(r.fdcId!, lines[r.position]);
        final whole = record == null
            ? null
            : lineGrams(db, lines[r.position], record, recipe: recipe)?.grams;
        if (whole != null && whole > 0) {
          cut[r.position] = round2(share.share * whole);
          mix.add(r);
          continue;
        }
      }
      if (counted(r)) {
        mix.add(r);
      }
    }
    final grams = mix.fold<double>(
      0,
      (n, r) => n + (cut[r.position] ?? r.grams!),
    );
    final product = grams <= 0
        ? null
        : _friedProductOf(
            [
              for (final s in all)
                if (_fryVerb.hasMatch(s) || _intoOil.hasMatch(s)) s,
            ],
            meat: mix.any(
              (r) => const ['Pork,', 'Beef,', 'Chicken,'].any(
                r.description!.startsWith,
              ),
            ),
            yeast: mix.any(
              (r) => r.description!.toLowerCase().contains('yeast'),
            ),
          );
    if (product != null) {
      fried.add((kind: product, grams: grams, at: fryers.first));
      for (final MapEntry(:key, :value) in cut.entries) {
        plan[key] = (
          grams: value,
          flag: share!.flag,
          kept: 0,
          coat: false,
          noNetUptake: false,
          dip: false,
          held: false,
          cut: true,
        );
      }
    }
  }
  if (fried.isEmpty) {
    return plan;
  }
  final absorbs = [
    for (final f in fried)
      if (f.kind.figure != null) f,
  ];
  // v57 (M59 D, Q13 b): the fried cauliflower's read u carries FNDDS
  // 2710042's batter, 50 g per 39.58 g raw (every other read record ≤
  // 0.38 g a gram) — scaled by min(1, C / K): C the carbohydrate of the
  // counted rows of the food's ingredient group but the food (the frying
  // oil is `discarded`, never counted; a batter left in the bowl at its
  // whole grams, [batterCho]), K FNDDS's b × c_b / R × the food's grams.
  // Null when the figure is not O5 or the recipe's batter covers K.
  ({double c, double k})? batterOf(
    ({_FriedClass kind, double grams, int at}) f,
  ) {
    final read = f.kind.figure!.read;
    if (read?.id != _cauliflowerFried.id) {
      return null;
    }
    final (start, end) = groupOf(f.at);
    var c = 0.0;
    for (final r in at.values) {
      if (r.position < start || r.position >= end || r.position == f.at) {
        continue;
      }
      // A batter left in the bowl (M58 W) counted whole on every path: its
      // stored row is the plan's `discarded` part after the first compute
      // (closer 2, V2-D1).
      if (batterCho[r.position] case final cho?) {
        c += cho;
      } else if (counted(r)) {
        final record = food(r.fdcId!, lines[r.position]);
        c += r.grams! * (record?.nutrientsPer100g['205'] ?? 0) / 100;
      }
    }
    final k =
        double.parse(read!.b) *
        _breadingCarbPerGram /
        double.parse(read.r) *
        f.grams;
    return c < k ? (c: c, k: k) : null;
  }

  final batters = [for (final f in absorbs) batterOf(f)];
  double uOf(int i) {
    final u = double.parse(absorbs[i].kind.figure!.value);
    final b = batters[i];
    return b == null ? u : u * b.c / b.k;
  }

  final uptake = absorbs.indexed.fold<double>(
    0,
    (n, e) => n + uOf(e.$1) * e.$2.grams / 100,
  );
  final clauses = [
    for (final (i, f) in absorbs.indexed)
      _uptakeClause(f.kind.figure!, f.kind.name, batter: batters[i]),
  ];
  final derived = batters.any((b) => b != null) ? ' — derived' : '';
  final flag = absorbs.isEmpty
      ? null
      : 'approximation (frying oil absorbed$derived: ${clauses.join('; ')})';
  final pans = <({int at, double full, double kept, bool yielded})>[];
  for (final i in fryers) {
    final r = at[i]!;
    final record = food(r.fdcId!, lines[i]);
    final full = record == null
        ? null
        : lineGrams(db, lines[i], record, recipe: recipe);
    if (full == null) {
      continue;
    }
    final kept =
        engineOutcome(recipe, lines[i], record!, full, decided: true).grams ??
        0;
    // v62 (closer 3, verifier 3 D1): a printed yield's part ([_yieldKept])
    // is all the oil the food keeps — no uptake on top of it.
    final yielded = _yieldKept(recipe, lines[i]) != null;
    pans.add((at: i, full: full.grams, kept: kept, yielded: yielded));
  }
  final oil = pans.fold<double>(0, (n, p) => n + p.full);
  for (final p in pans) {
    final absorbed = oil <= 0 || p.yielded
        ? 0.0
        : min(uptake * p.full / oil, max(p.full - p.kept, 0));
    plan[p.at] = (
      grams: absorbed > 0 ? round2(p.kept + absorbed) : p.kept,
      flag: absorbed > 0 ? flag : null,
      kept: p.kept,
      coat: false,
      noNetUptake: absorbs.isEmpty,
      dip: false,
      held: false,
      cut: false,
    );
  }
  return plan;
}

/// [_m52Plan]'s answer for [row] of [recipe] as stored — null unless its
/// line is a coat, a batter left in the bowl (v56, M58 W), a dip (v60,
/// M62), a cut dough's mix line (v66, M67 A2: [_cutMixAt]) or a frying
/// oil, the row one M52 weighs ([_m52Weighs]) counted with these grams (the
/// flag reads only grams it wrote). The plan is [memo]'s when one is given
/// ([ResolverMemo._m52Plans]: one per request), else run for this row.
_M52Row? _m52RowOf(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row, {
  ResolverMemo? memo,
}) {
  if (!_m52Weighs(row) || row.hold != null || row.grams == null) {
    return null;
  }
  final medium = discardedMediumOf(
    recipe,
    line,
    normalizeItem(lineItemOf(line)),
  );
  if (medium != DiscardedMedium.coating &&
      medium != DiscardedMedium.fryingOil &&
      !_batterInBowl(recipe).contains(row.position) &&
      // v60 (M62): a dip's line.
      !_dipsOf(recipe).containsKey(row.position) &&
      // v66 (M67 A2): a cut dough's mix line.
      !_cutMixAt(recipe, row.position)) {
    return null;
  }
  final at = (memo == null
      ? _m52Plan(
          db,
          recipe,
          db.ingredientMatchesFor(recipe.id),
          (id, l) => knownFood(db, id, line: l),
        )
      : _m52Stored(db, recipe, memo).plan)[row.position];
  return at == null || (at.grams - row.grams!).abs() > 0.05 ? null : at;
}

/// [_m52Plan] on [recipe]'s rows as stored, those rows by position and
/// their [_m52Key] — once per [memo] ([ResolverMemo._m52Plans]; a memo
/// whose life spans no row write).
({Map<int, IngredientMatchRow> rows, Map<int, _M52Row> plan, String key})
_m52Stored(
  SaltDatabase db,
  Recipe recipe,
  ResolverMemo memo,
) => memo._m52Plans[recipe] ??= () {
  final rows = db.ingredientMatchesFor(recipe.id);
  return (
    rows: {for (final r in rows) r.position: r},
    plan: _m52Plan(db, recipe, rows, (id, l) => knownFood(db, id, line: l)),
    key: _m52Key(recipe, rows),
  );
}();

/// A row [_m52Plan] reads as eaten (the coated food, a C5 flour off B, a
/// fried food or its mix): on a record, its grams written, not discarded.
bool _m52Counted(IngredientMatchRow r) =>
    r.status != 'skipped' &&
    r.status != 'unmatched' &&
    r.hold == null &&
    r.childRecipeId == null &&
    r.fdcId != null &&
    r.description != null &&
    (r.grams ?? 0) > 0 &&
    r.gramSource != GramSource.discarded.name &&
    !(r.status == 'auto' && belowConfidenceGate(r.confidence));

/// A row [_m52Plan] weighs on its own record ([_m52Weighs], no grams typed).
bool _m52Engine(IngredientMatchRow? r) =>
    r != null &&
    _m52Weighs(r) &&
    r.fdcId != null &&
    r.description != null &&
    r.childRecipeId == null &&
    r.gramSource != GramSource.override.name;

/// Everything [_m52Plan]'s COAT block (its coat, batter and dip entries)
/// reads of [rows] (v61 closer 1, verify1 D1/D2): per row in the plan, by
/// position — weighed, the engine's ([_m52Engine]), its hold passing
/// (none or `coating`), a coat or oil medium the plan reads (not a dip's
/// or a cut dough line's), its record, below the gate; the coated food
/// (its grams; v67, M69 R2: a coated vegetable where no meat is); under
/// C5 the counted flour and starch off B. Never another row's grams: a
/// dip, coat or batter row the plan writes `discarded` and its line's
/// engine form key alike, so rows that key alike give equal
/// coat, batter and dip entries (the recipe's text and the FDC caches
/// fixed) — one plan answers every confirm whose row list keys as its own
/// ([_m52OnConfirm]). With [fryer], the whole plan's (a frying oil's
/// entry) — the fryer block's reads too: each frying oil's hold (weighed
/// only unheld), and the grams of each counted row it may fry (a meat
/// record or a fried vegetable by name: [_friedClassOf] non-null, which
/// reads nothing else) — of EVERY counted row when no coated food is
/// surely fried and a frying sentence names a product (M61's mix) or a
/// counted cauliflower may be fried (M59 D's batter carbohydrate) — save a
/// cut dough's mix line (v66, M67 A2: [_cutMixAt]; the engine's, unheld,
/// not auto below the gate, no fried food by name, no cauliflower), read
/// by its line, record and hold only (and, where the steps print a cut
/// share, every row's hold: "cut i hold"), never its grams or medium bit:
/// the plan weighs it at the share of its WHOLE line, so its engine form
/// and the plan's `discarded` one key alike. So a compute rewriting an auto
/// dip or coat line between two confirmed oils, or every confirmed cut
/// dough line, keys alike (at the editor caps: 200 plans per compute → 2,
/// the totals' one).
/// ponytail: mirrors the plan's row reads by hand — a new read there joins
/// here (nutrition_v61_test compares the compute and the GET with the
/// per-row derivation on every decided dip, v26 times the cap shapes).
String _m52Key(
  Recipe recipe,
  Iterable<IngredientMatchRow> rows, {
  bool fryer = false,
}) {
  final lines = nutritionLines(recipe);
  final at = <int, IngredientMatchRow>{
    for (final r in rows)
      if (r.position < lines.length && lines[r.position].raw == r.raw)
        r.position: r,
  };
  IngredientMatchRow? coated;
  for (final r in at.values) {
    if (_m52Counted(r) &&
        _meatRecords.any(r.description!.startsWith) &&
        (coated == null ||
            r.grams! > coated.grams! ||
            (r.grams == coated.grams && r.position < coated.position))) {
      coated = r;
    }
  }
  final c5 =
      coated != null &&
      _coatShapeOf(recipe, coated.description!) == _CoatShape.c5;
  final dips = _dipsOf(recipe);
  final batter = _batterInBowl(recipe);
  final heads = _headsOf(recipe);
  String words(int i) =>
      '${normalizeItem(lineItemOf(lines[i]))} ${lines[i].raw.toLowerCase()}';
  // M59 D's batter carbohydrate reads every counted row's grams of a
  // cauliflower's group.
  late final cauliflower = at.entries.any(
    (e) =>
        _m52Counted(e.value) &&
        '${words(e.key)} ${e.value.description!.toLowerCase()}'.contains(
          'cauliflower',
        ),
  );
  // v66 (M67 A2): a cut dough's mix line the plan weighs is read on its
  // line and record, never its grams or source — its engine form and the
  // plan's `discarded` one key alike (no frying sentence can name it as a
  // fried food: [_friedClassOf] null), so a compute rewriting every
  // confirmed dough line plans once, not once per line.
  final cut = _cutShareOf(recipe) != null;
  bool cutLine(int i, IngredientMatchRow r) =>
      cut &&
      _cutMixAt(recipe, i) &&
      _m52Engine(r) &&
      r.hold == null &&
      !(r.status == 'auto' && belowConfidenceGate(r.confidence)) &&
      !cauliflower &&
      !((_friedLines[recipe] ??= {})[(i, r.description!)] ??=
          _friedClassOf(
            r.description!,
            words(i),
            coatHeld: false,
            shape: null,
            chips: false,
          ) !=
          null);
  // v67 (M69 R2): with no meat, the coated vegetable the coat block sizes
  // from ([_coatedVegetable]) — keyed whatever the coats (a superset).
  final food = coated ?? _coatedVegetable(recipe, at.values);
  final key = StringBuffer(
    '${food?.position} ${food?.grams} ${food?.description}',
  );
  for (final i in at.keys.toList()..sort()) {
    final r = at[i]!;
    key.write(
      _m52RowKey(
        r,
        dip: dips.containsKey(i) || cutLine(i, r),
        offB:
            c5 &&
            _m52Counted(r) &&
            !batter.contains(i) &&
            _dredgeHeads.contains(heads[i]),
      ),
    );
  }
  if (fryer) {
    // [_m52Plan]'s `coated` is set only beside a coat, a batter or a
    // shallow fry; its `fried` list then holds it.
    final coats = at.entries.any(
      (e) =>
          batter.contains(e.key) ||
          (!dips.containsKey(e.key) &&
              _m52Weighs(e.value) &&
              (e.value.hold == 'coating' ||
                  (e.value.hold == null &&
                      e.value.gramSource == GramSource.discarded.name)) &&
              _mediumAt(recipe, e.key) == DiscardedMedium.coating),
    );
    final every =
        ((coated == null || !(coats || _shallowFries(recipe))) &&
            _productFried(recipe)) ||
        cauliflower;
    // v66 (M67 A2): a cut dough's mix row is planned on its own hold —
    // none, where the row key reads "none or coating" — never its grams.
    for (final i in at.keys.toList()..sort()) {
      final r = at[i]!;
      if (_mediumAt(recipe, i) == DiscardedMedium.fryingOil) {
        key.write('\noil $i ${r.hold}');
      }
      if (cut) {
        key.write('\ncut $i ${r.hold}');
      }
      if (_m52Counted(r) &&
          !cutLine(i, r) &&
          (every ||
              _friedClassOf(
                    r.description!,
                    words(i),
                    coatHeld: false,
                    shape: null,
                    chips: false,
                  ) !=
                  null)) {
        key.write('\nfried $i ${r.grams}');
      }
    }
  }
  return key.toString();
}

/// [r]'s line of [_m52Key] ([dip]: a dip's or a cut dough's mix line, no
/// medium; its grams only [offB]).
String _m52RowKey(
  IngredientMatchRow r, {
  required bool dip,
  required bool offB,
}) {
  final medium =
      !dip &&
      (r.hold == 'coating' ||
          (r.hold == null && r.gramSource == GramSource.discarded.name));
  return '\n${r.position} ${_m52Weighs(r)} ${_m52Engine(r)} '
      "${r.hold == null || r.hold == 'coating'} $medium ${r.fdcId} "
      '${r.childRecipeId != null} '
      "${r.status == 'auto' && belowConfidenceGate(r.confidence)} "
      '${offB ? r.grams : ''} ${r.description}';
}

/// Whether [_m52Key] of a row list stays as it is when its row [row] is
/// replaced by [confirmed] at the same position — in O(1): the confirm's
/// row is never counted, so beyond its own line only a counted meat or
/// [_coatVegetables] row (the coated food) or flour or starch (C5's off
/// B) could move the key; false then, and the caller keys the whole list.
bool _m52KeysAlike(
  Recipe recipe,
  IngredientMatchRow row,
  IngredientMatchRow confirmed,
) {
  final lines = nutritionLines(recipe);
  bool laid(IngredientMatchRow r) =>
      r.position < lines.length && lines[r.position].raw == r.raw;
  return laid(row) &&
      laid(confirmed) &&
      !(_m52Counted(row) &&
          (_meatRecords.any(row.description!.startsWith) ||
              // v67 (M69 R2): a coated vegetable is the coated food too.
              _coatVegetables.any(row.description!.startsWith) ||
              _dredgeHeads.contains(_headsOf(recipe)[row.position]))) &&
      _m52RowKey(
            row,
            dip: _dipsOf(recipe).containsKey(row.position),
            offB: false,
          ) ==
          _m52RowKey(
            confirmed,
            dip: _dipsOf(recipe).containsKey(row.position),
            offB: false,
          );
}

/// [discardedMediumOf] of [recipe]'s line [i], once per Recipe instance (a
/// Recipe is immutable): what [_m52Key] reads for the fryer block.
DiscardedMedium? _mediumAt(Recipe recipe, int i) =>
    (_media[recipe] ??= {}).putIfAbsent(i, () {
      final line = nutritionLines(recipe)[i];
      return discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line)));
    });
final Expando<Map<int, DiscardedMedium?>> _media = Expando();

/// Whether a frying sentence of [recipe] names a fried product
/// ([_friedProductOf], every figure admitted), once per Recipe instance:
/// whether [_m52Plan]'s product mix can be read at all.
bool _productFried(Recipe recipe) => _products[recipe] ??=
    _friedProductOf(
      [
        for (final s in _stepIndexOf(recipe).allSentences)
          if (_fryVerb.hasMatch(s) || _intoOil.hasMatch(s)) s,
      ],
      meat: true,
      yeast: false,
    ) !=
    null;
final Expando<bool> _products = Expando();

/// How many times [_m52Plan] ran (the cost pin, v60 closer 2: the matches
/// GET plans a recipe once, not once per row).
@visibleForTesting
int m52PlanRuns = 0;

/// A row M52 weighs: the engine's (`auto`), or a person's CONFIRM with no
/// grams typed — "this food, the engine's CURRENT weight" (RULE A), so a
/// Confirm keeps the plan's grams as it keeps rule B1's parts ([withParts];
/// verify2 D1: a Confirm of karaage's budgeted cornstarch wrote 0 g poured
/// away). A pick is one record at the line's weight; typed grams stand.
bool _m52Weighs(IngredientMatchRow r) =>
    r.status == 'auto' ||
    (r.status == 'confirmed' && r.gramSource != GramSource.override.name);

/// What a person's CONFIRM of [placed] — a coat, batter (v56), dip (v60)
/// or frying-oil line, or a cut dough's mix line (v66, M67 A2), no grams
/// typed — resolves to ([derivedFor]): [_m52Plan] on the stored rows
/// with [placed] as the confirm leaves it (no hold, `discarded`); null when
/// M52 counts nothing on the line. With [memo] (the matches GET's — v60
/// closer 3, verify3 D1: one plan per CONFIRMED row, O(oils²) at the caps),
/// a stored row at [placed]'s position that already IS that row on every
/// field [_m52Plan] reads ([sameMatchRow]; the position by the lookup)
/// makes the row list the stored one: the request's one plan answers. Any
/// other (a PUT's confirm, a shifted layout) plans its own list. v60
/// (M62): [derivedFor] reads a dip line's entry for any decision (H's hold
/// for a pick too). v61 closer 1 (verify1 D1, D2): a coat, batter or dip
/// line's entry is the plan's coat block's, a function of [_m52Key] alone
/// — so the request's plan answers whenever the confirm's row list keys as
/// the stored one (a confirmed no-coat dip, a pick: one plan per GET, not
/// one per dip); and [pass] (the compute's, whose rows move between its
/// derivations) answers from ONE plan while the rows as they are now key
/// alike — a frying oil's or a cut dough line's by the whole plan's key —
/// and no FDC cache write landed: a compute with every dip, batter line or
/// frying oil confirmed plans once, not once per line (16.2 s, 20.8 s and
/// 34.5 s at the editor caps before).
_M52Row? _m52OnConfirm(
  SaltDatabase db,
  Recipe recipe,
  IngredientMatchRow placed, {
  ResolverMemo? memo,
  ResolverMemo? pass,
}) {
  final confirmed = placed.copyWith(
    gramSource: GramSource.discarded.name,
    clearHold: true,
  );
  final at = placed.position;
  final lines = nutritionLines(recipe);
  // Its entry the coat block's: a dip (never a medium line, [_dipsOf]), a
  // coat line, a batter left in the bowl that is no frying oil.
  late final coat = () {
    if (_dipsOf(recipe).containsKey(at)) {
      return true;
    }
    if (at >= lines.length) {
      return false;
    }
    final medium = discardedMediumOf(
      recipe,
      lines[at],
      normalizeItem(lineItemOf(lines[at])),
    );
    return medium == DiscardedMedium.coating ||
        (medium != DiscardedMedium.fryingOil &&
            _batterInBowl(recipe).contains(at));
  }();
  List<IngredientMatchRow> confirming(Iterable<IngredientMatchRow> rows) => [
    for (final r in rows)
      if (r.position != at) r,
    confirmed,
  ];
  if (memo != null) {
    final stored = _m52Stored(db, recipe, memo);
    final row = stored.rows[at];
    if (sameMatchRow(row, confirmed) ||
        (coat &&
            ((row != null && _m52KeysAlike(recipe, row, confirmed)) ||
                _m52Key(recipe, confirming(stored.rows.values)) ==
                    stored.key))) {
      return stored.plan[at];
    }
  }
  final rows = db.ingredientMatchesFor(recipe.id);
  if (pass != null) {
    final list = confirming(rows);
    final key = _m52Key(recipe, list, fryer: !coat);
    final slots = pass._m52Pass[recipe] ??= {};
    final kept = slots[!coat];
    if (kept != null && kept.key == key && kept.writes == db.fdcCacheWrites) {
      return kept.plan[at];
    }
    final writes = db.fdcCacheWrites;
    final plan = _m52Plan(
      db,
      recipe,
      list,
      (id, l) => knownFood(db, id, line: l),
    );
    slots[!coat] = (key: key, writes: writes, plan: plan);
    return plan[at];
  }
  // v60 (M62): a decision the plan never weighs (a pick, typed grams) is
  // read at a dip only for H's hold, whose mode no other non-meat dip row
  // moves — those are left out (RULE C: a PUT plans no 400 dips per picked
  // dip).
  final dips = _m52Weighs(confirmed) ? null : _dipsOf(recipe);
  return _m52Plan(
    db,
    recipe,
    [
      for (final r in rows)
        if (r.position != at &&
            !(dips != null && dips.containsKey(r.position) && !_isMeatRow(r)))
          r,
      confirmed,
    ],
    (id, l) => knownFood(db, id, line: l),
  )[at];
}

/// Whether [r] stands on a meat record ([_meatRecords]): the one kind of
/// row [_m52Plan] may read as the coated food among a dip's lines (a
/// coated vegetable, v67, is never one).
bool _isMeatRow(IngredientMatchRow r) =>
    _meatRecords.any((m) => r.description?.startsWith(m) ?? false);
