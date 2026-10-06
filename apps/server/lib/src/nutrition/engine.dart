import 'dart:convert';
import 'dart:math' show max, min;
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
  /// Read from the directions too ([_oilOwnersOf], RULE B): an oil of ¼
  /// cup or more a sentence it owns heats to a frying temperature,
  /// discards or pours off all but a part of, or the one such oil of a
  /// fried food's held dredge — a part poured off "all but" is kept and
  /// counted ([_keptFryingOil]).
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
  /// one. Held (`coating`) until [coatingFraction] is set.
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
  ambiguousMedium;

  /// Whether [discardedMediaPolicy] decides how it counts; the others are
  /// always held for a person.
  bool get followsPolicy =>
      this == fryingOil || this == brine || this == brineSugar || this == soak;

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
      ),
);

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
    for (final at in _naming(recipe, head)) {
      final s = index.sentence(at);
      final pourOff = fat.pourOffAllBut.hasMatch(s);
      if (!pourOff &&
          !fat.heatsToFry(s, () => _heatReading(recipe, s)) &&
          !fat.discards.hasMatch(s)) {
        continue;
      }
      // A pour-off's kept part names no line's amount ("all but 2
      // tablespoons oil" beside a 2-tablespoon sesame oil).
      final said = pourOff ? s.replaceAll(fat.pourOffAllBut, '') : s;
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
    final verb = order == 0 && !lines.any(_massZeroes)
        ? _fryVerbAt(recipe)
        : null;
    if (verb == null && _fries(recipe) && _dredgedIn(recipe)) {
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
  return [
        head,
        for (final kind in const ['parmesan', 'saltine'])
          if (normalized.contains(kind)) kind,
      ].any(
        (word) => _naming(
          recipe,
          word,
        ).any((at) => _layerOfTheCoat.hasMatch(index.sentence(at))),
      ) &&
      (_dredgedIn(recipe) || _leavesExcess(recipe));
}

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
/// brine salt's 44 mL 53.7 g of table salt (1.22), 31.7 g of kosher
/// (0.72); four cups of milk or buttermilk 974 g (1.03). 0 when it has
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
/// counted as a plus line's eaten part is ([engineOutcome]); null when no
/// own sentence keeps one.
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
        : _fats[head]!.pourOffAllBut.firstMatch(pourOff);
    return kept == null
        ? null
        : parseIngredientLine('${kept[1]} $item').amounts.firstOrNull;
  });
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
/// flour"); null when no step writes such a part.
({Amount amount, String text})? _eatenOutsideMedium(
  Recipe recipe,
  IngredientLine line,
  String? head,
  DiscardedMedium? medium,
) {
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
              if (mention.firstMatch(sentence) case final match?) match,
    ];
  });
  // The mention is THIS line's only when no other line of its ingredient
  // writes that amount (Run 054 O7: 1133's "¾ cup flour, divided" split
  // into "¾ cup" and "1 teaspoon" flour lines kept "Sprinkle cubes with 1
  // teaspoon flour" as the dredge's eaten part too — the teaspoon counted
  // twice). RULE C (v26, Run 056 S5/S7: each line parsed every mention and
  // scanned every line per mention — a legal 400-line dredge recipe ~123 s
  // per GET): the mentions parsed ONCE per head and medium, grouped by
  // amount (the first mention of each, in order), and each amount's lines
  // found once per head — a line's answer is two lookups.
  // Key: head and medium — [written]'s, and the parse's head.
  final parts = index.memo(('eatenParts', head, medium), () {
    final first = <(String, String?), ({Amount amount, String text})>{};
    for (final match in written) {
      _count('eatenParses');
      final part = parseIngredientLine(
        '${match[1]}$head',
      ).amounts.firstOrNull;
      if (part != null) {
        first.putIfAbsent(
          (part.quantity, part.unit),
          () => (amount: part, text: match[0]!),
        );
      }
    }
    return first;
  });
  final writers = _amountWritersOf(recipe, head);
  bool free((String, String?) amount) => switch (writers[amount]) {
    null => true,
    final lines => lines.length == 1 && identical(lines.single, line),
  };
  // The first amount no line writes, or this line's own amount when it is
  // the only line writing it and is written first.
  final unwritten = index.memo(
    // Key: head and medium — [parts]'s, and the head's writers.
    ('eatenUnwritten', head, medium),
    () => parts.keys.where((a) => writers[a] == null).firstOrNull,
  );
  final own = line.amounts.firstOrNull;
  final mine = own == null ? null : (own.quantity, own.unit);
  if (mine != null && parts.containsKey(mine) && free(mine)) {
    final order = index.memo(
      // Key: head and medium — [parts]'s.
      ('eatenOrder', head, medium),
      () => {for (final (i, a) in parts.keys.indexed) a: i},
    );
    if (unwritten == null || order[mine]! < order[unwritten]!) {
      return parts[mine];
    }
  }
  return unwritten == null ? null : parts[unwritten];
}

/// Each first amount (quantity, unit) the lines of [head] in [recipe]
/// write, and the lines writing it (by identity) — once per head
/// ([_eatenOutsideMedium]).
Map<(String, String?), Set<IngredientLine>> _amountWritersOf(
  Recipe recipe,
  String head,
  // Key: head — the lines of it.
) => _stepIndexOf(recipe).memo(('amountWriters', head), () {
  final heads = _headsOf(recipe);
  final writers = <(String, String?), Set<IngredientLine>>{};
  for (final (i, line) in nutritionLines(recipe).indexed) {
    final first = line.amounts.firstOrNull;
    if (heads[i] == head && first != null) {
      (writers[(first.quantity, first.unit)] ??= Set.identity()).add(line);
    }
  }
  return writers;
});

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
      _drainedAway(recipe, line, head, steps);
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
      : null;
  // A frying oil's part kept in the pan and eaten ([_keptFryingOil]).
  final eatenPart =
      plus?.amount ??
      divided?.amount ??
      (medium == DiscardedMedium.fryingOil
          ? _keptFryingOil(recipe, line)
          : null);
  final kept = eatenPart != null
      ? resolveGrams(
          amounts: [eatenPart],
          food: food,
          normalizedItem: normalized,
          kosherSalt: packsLikeKosherSalt(line.raw),
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
      : resolved;
  final rule = secondFoodRuleOf(line, citrus: citrus, eggs: eggs);
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
  // on a synthesized one (a stated exception, v11).
  final zero = amountlessLinesZero && line.amounts.isEmpty && !inShell;
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
/// A mussel or shrimp line bought by weight stays held: no record publishes
/// a shell yield.
bool shellCounted(Recipe recipe, GramResolution? resolution) =>
    resolution?.source == GramSource.piece ||
    (resolution?.basis?.contains('($shellYieldLabel)') ?? false) ||
    RegExp(
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

/// [eaten]'s food and grams once the skin is off: an auto row on a
/// skin-on record of [skinlessRecords] — the engine's pick, or a person's
/// decision carried here from another line — whose line, weighed from a
/// printed weight, buys refuse in a recipe that discards the skin
/// ([skinDiscarded]) moves to the meat-only record (cached; else its detail
/// fetched once), weighed there at the meat share. Else [food] and
/// [resolution] as they are. Never a person's own row on this line: it
/// shows the food they chose.
Future<(FdcFood, GramResolution?)> skinOffFood(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe recipe,
  IngredientLine eaten,
  FdcFood food,
  GramResolution? resolution,
) async {
  final skinless = skinlessRecords[food.fdcId];
  final meatOnly =
      skinless == null ||
          resolution?.source != GramSource.weight ||
          !buysRefuse(eaten.raw) ||
          !skinDiscarded(recipe, eaten)
      ? null
      : await _cachedFood(db, provider, skinless);
  return meatOnly == null
      ? (food, resolution)
      : (meatOnly, lineGrams(db, eaten, meatOnly, recipe: recipe));
}

/// The record a decision on [fdcId] names for [line]'s ingredient: on a
/// meat-only record of [skinlessRecords] in a recipe that discards the
/// skin of a cut bought with it, the SKIN-ON record bought — so a Confirm
/// of a moved row (or apply_to_all) never carries the skinless food, nor
/// its meat share, to a line whose skin is eaten; each line that discards
/// it moves again ([skinOffFood]). Else [fdcId].
int? decisionRecordOf(Recipe recipe, IngredientLine line, int? fdcId) {
  for (final MapEntry(key: skinOn, value: meatOnly)
      in skinlessRecords.entries) {
    if (meatOnly == fdcId &&
        buysRefuse(line.raw) &&
        skinDiscarded(recipe, line)) {
      return skinOn;
    }
  }
  return fdcId;
}

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
  final skin = [
    for (final sentence in _stepIndexOf(recipe).allSentences)
      if (RegExp(r'\bskin\b').hasMatch(sentence)) sentence,
  ];
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

/// The section keys [recipe]'s MAIN lines make children (v44, design_v2
/// S2 (a), P1 §2.1): a reference line the sub-recipe rule zeroes (never one
/// a food rule counts — [subRecipeRowFor] null: curry-deviled-eggs|0,
/// gado-gado|17, ground-beef-tacos|15, mujaddara|7) whose resolution names
/// a section with ingredient lines. Read through [memo] (one per scope or
/// compute). The bulk sweep's order and garbage collection and the
/// per-recipe job's children-first read this; the pick-own candidates
/// (rule PO) and the A9 lines join it here.
Set<String> sectionChildKeysOf(
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
/// D11: under "recipes follow" too) → the first library title the parent's
/// note names ("(this page)" in the note; titles of two or more words
/// holding every word of the item, by position, the longest of a span) →
/// the library title equal to the item (unless the parent is made FOR it,
/// D7) → another recipe's section → held. Self is never a candidate. A
/// child made from a recipe itself is `nested` (depth 1); one whose yield
/// reads no share is `noShare`.
ReferenceResolution resolveReference(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  ResolverMemo memo,
) {
  if (line.amounts.isEmpty) {
    return const ReferenceResolution(ReferenceKind.noAmount);
  }
  final item = referenceItemOf(line);
  final itemWords = _refWords(item);
  if (itemWords.contains('marinade')) {
    return const ReferenceResolution(ReferenceKind.marinade);
  }
  final own = [
    for (final sub in recipe.subsections)
      if (sub.title case final title? when _ownSectionNames(title, item)) title,
  ];
  if (own.length == 1) {
    final key = sectionKeyOf(recipe.id, own.single);
    return _childTail(line, sectionOf(recipe, key)!, section: own.single);
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
/// A9 line's bare count of exactly 1 reads one recipe (S11). A child not
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
          : null);
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

/// Rule B1 (v41, R2): rendered bacon. The record bought, SR 168277 "Pork,
/// cured, bacon, unprepared".
const int rawBaconFdcId = 168277;

/// SR 168322 "Pork, cured, bacon, pre-sliced, cooked, pan-fried" — the
/// cooked part (a cached search hit, "thin-sliced cooked deli ham").
const int cookedBaconFdcId = 168322;

/// SR 172345 "Animal fat, bacon grease" — the fat kept in the pan.
const int baconGreaseFdcId = 172345;

/// Cooked bacon per gram raw: protein is not rendered, so 13.66 g of
/// 168277's protein sit in 13.66 / 33.9 g of 168322 (0.40295).
const double baconCookedYield = 0.403;

/// Fat rendered per gram raw: 0.3713 − 0.40295 × 0.351 (168277's fat less
/// the cooked bacon's).
const double baconRenderedPerGram = 0.2299;

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

/// The mL of fat [recipe]'s steps keep in the pan, or null when no ONE step
/// lifts the meat out AND cuts the fat to a stated amount (B1's signal).
double? _baconKeptMl(Recipe recipe) {
  double? ml(String quantity, String unit) => volumeMlOf([
    Amount(
      measure: Measure.volume,
      quantity:
          const {'one': '1', 'two': '2', 'three': '3', 'four': '4'}[quantity] ??
          quantity,
      unit: unit.replaceFirst(RegExp(r's$'), ''),
    ),
  ]);
  for (final step in recipe.steps) {
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
      return ml(keep[1]!, keep[2]!);
    }
    if (_baconReserve.firstMatch(text) case final reserve?) {
      return ml(reserve[1]!, reserve[2]!);
    }
    if (_baconExtra.firstMatch(text) case final extra?) {
      return ml(extra[2]!, extra[3]!);
    }
  }
  return null;
}

/// [row] as rule B1 counts it (v41, R2): an `auto` or `confirmed` row on
/// [rawBaconFdcId], unheld, weighed at [raw] grams (> 0; default: its own
/// grams) on a line not "divided" — never grams a person typed (D12, F2) —
/// whose [recipe] renders and drains the bacon ([_baconKeptMl]) is ONE row
/// on the record bought with two parts: the cooked bacon (raw × 0.403 on
/// [cookedBaconFdcId]) and the fat kept in the pan (the stated amount, at
/// most what renders, on [baconGreaseFdcId]); its grams their sum. Any other
/// row carries no parts.
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
      ? _baconKeptMl(recipe)
      : null;
  if (keptMl == null) {
    return row.parts == null ? row : row.copyWith(clearParts: true);
  }
  double round2(double v) => double.parse(v.toStringAsFixed(2));
  final cooked = round2(grams! * baconCookedYield);
  final kept = round2(
    min(keptMl * baconGreaseGramsPerMl, grams * baconRenderedPerGram),
  );
  return row.copyWith(
    grams: round2(cooked + kept),
    parts: jsonEncode([
      {'fdc_id': cookedBaconFdcId, 'grams': cooked},
      {'fdc_id': baconGreaseFdcId, 'grams': kept},
    ]),
  );
}

/// The parts a two-part row stores: `[{"fdc_id": …, "grams": …}, …]`.
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
/// juice rule drops it. Null for any other line (a lemon's "plus 2 lemons,
/// halved" stays its zest: no whole-lemon record is mapped).
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
/// S7 a; the library's one such line is oranges).
const Map<String, int> _citrusFruit = {
  'orange': 746771, // Oranges, raw, navels
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
/// results are stale.
String ingredientsHashOf(Recipe recipe) {
  // The matcher version is part of it: a bump makes every computed recipe
  // stale, so the stale sweep re-resolves its engine rows instead of leaving
  // scores and picks frozen at the matcher that wrote them. So are the
  // recipe's own steps and its title, which the discarded-media rules read
  // ([discardedMediumOf]): a steps-only edit adding or removing a drain
  // left the hold and the totals frozen, never stale (v11, Opus critic).
  final lines = nutritionLines(recipe);
  final payload = jsonEncode({
    'matcher': matcherVersion,
    'title': recipe.title,
    'steps': [for (final step in recipe.steps) step.text],
    // v41 (S12): what the sub-recipe resolver reads beside the line — the
    // note naming a dough, the sections a reference names — for a recipe
    // holding a reference line ([resolveReference]).
    if (lines.any((line) => isReferenceIn(recipe, line))) ...{
      'prep_notes': recipe.prepNotes,
      'sections': [for (final sub in recipe.subsections) sub.title],
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
        },
    ],
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

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
/// ([SaltDatabase.recipesWithNutrition]).
bool nutritionIsFresh(
  SaltDatabase db,
  Recipe recipe, [
  RecipeNutritionRow? row,
]) => nutritionStampCurrent(db, recipe, row) && !db.hasUnderivedRows(recipe.id);

/// The stamp half of [nutritionIsFresh]: the totals were stamped for
/// [recipe]'s current inputs and layout. What `computeUntilFresh` repeats
/// a compute for (a save cut it off) — never an underived row, which a
/// second pass would only ask FDC for again (Run 057 S5/S16/O2/O16).
bool nutritionStampCurrent(
  SaltDatabase db,
  Recipe recipe, [
  RecipeNutritionRow? row,
]) {
  final stamp = row ?? db.nutritionFor(recipe.id);
  return stamp != null &&
      stamp.ingredientsHash == ingredientsHashOf(recipe) &&
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
  final inputs = ingredientsHashOf(recipe);
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
      current = stored != null && ingredientsHashOf(stored) == inputs;
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
  // The library's titles and sections, read at most once in this compute
  // and only for a reference line (v41, F14).
  final references = ResolverMemo(db);

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
    if (mainRecipePartNote(db, recipe, eaten, normalized) case final note?) {
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
          final carriedRow = withRenderedBacon(
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
      final candidates = await _cachedSearch(db, lineProvider, search.answer);
      final ranked = freshOverCured(
        eaten.raw,
        rankCandidates(
          search.query,
          candidates,
          canned: namesCannedLegume(eaten.raw, normalized),
          skinOn: impliesSkinOn(eaten.raw, normalized),
          skinless: removesSkin(eaten.raw),
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
      final picked = withRenderedBacon(
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
  // v43 (Y13): the RECORD decides the meat share ([ah102Records]); the
  // recipe's skin trip only names the part a meat-only whole bird keeps
  // its skin on — with no recipe, none.
  final skinOff = recipe != null && skinDiscarded(recipe, line);
  final skinKept = skinOff ? skinKeptPart(recipe, line) : null;
  GramResolution? on(FdcFood? record) => resolveGrams(
    amounts: line.amounts,
    food: record,
    normalizedItem: normalized,
    raw: line.raw,
    skinOff: skinOff,
    skinKept: skinKept,
  );
  if (food != null && freshHerbLine(line.raw, food.description)) {
    return _freshHerbGrams(line, food, normalized, on(food));
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
      // sub-recipe the engine did not route (v41 R3, A3 a: a section, a
      // dish served with, no amount, no share) is not: its recipe reads
      // partial.
      if (row.status == 'confirmed' && row.description != subRecipeNote) {
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
      : ingredientsHashOf(now);
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
      current() ? (ingredientsHashOf(recipe), layoutSeq) : ('', null),
  };
  // A food these totals could not count (an engine row's no cache holds,
  // [unavailable]: an apply-to-all target FDC could not weigh) stamps the
  // inputs STALE as waiting on USDA, never as changed (v29, Run 059 O23):
  // [unavailableStampOf] the hash — no current hash equals it, and the
  // page's `stale_reason` reads `underived`.
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
  return freshOverCured(
    line.raw,
    rankCandidates(
      search.query,
      candidates,
      canned: namesCannedLegume(line.raw, normalized),
      skinOn: impliesSkinOn(line.raw, normalized),
      skinless: removesSkin(line.raw),
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
String? gramBasisFor(
  SaltDatabase db,
  IngredientLine line,
  IngredientMatchRow row, {
  Recipe? recipe,
}) {
  // A sub-recipe row on a food weighs the line's eaten "plus" part
  // ([weighedLine]: 0711's "3 tablespoons reserved oil").
  final weighed = recipe == null || row.fdcId == null
      ? line
      : weighedLine(recipe, line);
  final basis = _gramBasis(db, weighed, row, recipe);
  // A skipped row adds nothing to the totals: no "approximate" or "counted
  // as" suffix (Run 046) — its basis alone says what was measured.
  if (basis == null || row.status == 'skipped') {
    return basis;
  }
  // A fresh herb on its dried record says its own suffix — only on the
  // engine's weighing, never on grams a person typed, nor on a sprig or
  // leaf counted as 0 g (Run 047 critic).
  if (row.description != null && freshHerbLine(line.raw, row.description!)) {
    return row.gramSource == GramSource.override.name ||
            row.gramSource == GramSource.unmeasured.name
        ? basis
        : '$basis · approximate (dried herb record for a fresh herb)';
  }
  // Read on the weighed line, as the grams are (Run 049: "1 recipe Pesto
  // Base, plus 2 ounces pancetta" on the bacon record lost its label).
  final approximation = isApproximation(
    item: normalizeItem(lineItemOf(weighed)),
    raw: weighed.raw,
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
  Recipe? recipe,
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
  if (row.parts != null && fdcId != null) {
    final parts = partsOf(row.parts);
    final raw = lineGrams(
      db,
      line,
      knownFood(db, fdcId, line: line),
      recipe: recipe,
    )?.grams;
    if (raw != null && parts.length == 2) {
      return '${_fmtAmount(raw)} g raw → ${_fmtAmount(parts[0].grams)} g '
          'cooked bacon + ${_fmtAmount(parts[1].grams)} g bacon grease kept '
          'in the pan';
    }
  }
  if (row.gramSource == GramSource.discarded.name) {
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
    // A person's confirm of a held medium with no eaten part (B6).
    return row.grams! <= 0 && row.status != 'auto'
        ? 'poured away — counted as 0 g'
        : row.grams! <= 0
        ? 'discarded in cooking — counted as 0 g'
        : plus != null
        ? 'discarded in cooking — only "$part" counted'
        : 'discarded in cooking — only the part the recipe keeps counted';
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
  final rule = secondFoodRuleOf(line);
  if (rule != null && rule.fdcId == fdcId) {
    final byRule = rule.gramsOn(food);
    if (byRule != null && (byRule.grams - row.grams!).abs() <= 0.05) {
      return byRule.basis;
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
/// {m} of {n} lines)"; a rendered row — "approximate (rendered and
/// drained; yield from FDC protein)". The last two name a fact and stay on
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
    final child = db.nutritionFor(childId);
    if (child != null && child.status != 'complete') {
      flags.add(
        'approximation ($title is partial: ${child.matchedCount} '
        'of ${child.totalCount} lines)',
      );
    }
  }
  if (row.parts != null && row.gramSource != GramSource.override.name) {
    flags.add('approximate (rendered and drained; yield from FDC protein)');
  }
  return flags.isEmpty ? null : flags.join(' · ');
}

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
/// [applyDecisionToOthers]'s.
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
}) async {
  final byRecipe = <String, List<IngredientMatchRow>>{};
  for (final target in recipeReach(
    db,
    itemKey,
    childId: childId,
    excluding: excluding,
    memo: ResolverMemo(db),
  )) {
    byRecipe.putIfAbsent(target.recipeId, () => []).add(target);
  }
  final child = nutritionRecipeOf(db, childId)?.recipe;
  var recipes = 0;
  var lines = 0;
  var failed = 0;
  var failedLines = 0;
  var moved = 0;
  var decided = 0;
  var gone = 0;
  final completed = <String>[];
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
      final hash = ingredientsHashOf(recipe);
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
      recipes += 1;
      lines += applied;
      if (statusBefore != 'complete' &&
          db.nutritionFor(id)?.status == 'complete') {
        completed.add(id);
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
    recipes: recipes,
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
  final byRule = personal || secondFoodRuleOf(line)?.fdcId == out.fdcId
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
  final outcome = engineOutcome(
    recipe,
    eaten,
    onRow,
    medium
        ? lineGrams(db, eaten, onRow, recipe: recipe)
        : out.grams == null || source == null
        ? null
        : GramResolution(grams: out.grams!, source: source),
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
  // Rule B1 (v41) on the line's raw weight: a skip kept the rendered sum.
  if (out.fdcId == rawBaconFdcId) {
    out = withRenderedBacon(
      recipe,
      eaten,
      out,
      raw: lineGrams(db, eaten, onRow, recipe: recipe)?.grams,
    );
  }
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
  final outcome = engineOutcome(
    recipe,
    eaten,
    food,
    resolution,
    decided: true,
  );
  final mediumLine =
      discardedMediumOf(
        recipe,
        eaten,
        normalized,
      ) !=
      null;
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
  final weight = eaten.amounts.isEmpty && edited.status == 'overridden'
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
      : resolves
      ? GramSource.discarded.name
      : weight == null
      ? null
      : outcome.source;
  // Rule B1 (v41, D12): a Confirm keeps a rendered row's two parts; a pick
  // (`overridden`) is one record at the line's raw grams — how a person
  // undoes the rule.
  final row = withRenderedBacon(
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
  var recipes = 0;
  var lines = 0;
  var failed = 0;
  var failedLines = 0;
  var moved = 0;
  var decidedMeanwhile = 0;
  var gone = 0;
  var unavailable = 0;
  final completed = <String>[];
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
            withRenderedBacon(
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
      recipes += 1;
      lines += applied;
      if (statusBefore != 'complete' &&
          db.nutritionFor(found.recipe.id)?.status == 'complete') {
        completed.add(found.recipe.id);
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
    recipes: recipes,
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
