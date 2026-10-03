// The pairing oracle: every recipe edit, then a compute, checked against
// hidden line identities. Run
//   SALT_CORPUS_DIR="…" dart test test/pairing_oracle_test.dart
// Env: ORACLE_OUTAGE=1 (RULE A's outage mode: FDC out for the decided
// food, its caches emptied — v27), ORACLE_SEEDS (default 200),
// ORACLE_STEPS (saves per seed, default 12), ORACLE_OPS_MAX (edits per
// save, 1..this many, default 3; 1 is the
// single-op oracle, replaying its seeds exactly), ORACLE_SEED (run that
// one seed only), ORACLE_SEED_BASE (the first seed, default 0: a fresh
// range), ORACLE_SHOW (violations printed, default 12), ORACLE_GAP_SEEDS
// (the gap mode's fresh seeds, default 0: its regression seeds only — see
// the gap fuzz test for why).
//
// SEMANTICS (what "correct" means here).
//  * Every line carries a hidden identity; a person's decision (a skip, or a
//    pick of 173468 with DISTINCT typed grams, so each pick is one token)
//    belongs to an identity. The engine only ever sees texts: the stored
//    rows' raws (old) and the lines' raws (new).
//  * A save's TEXT VIEW is the pair (old texts, new texts); a save may
//    carry several edits. Its explanations are the fewest-op scripts of
//    {insert, delete, substitute one line's text, move one line} that turn
//    the old texts into the new ones, where a substitution to ANOTHER
//    ingredient IS a delete + an insert (two ops: it carries nothing) and
//    an unchanged list is the no-op (never a swap of twins, which costs a
//    move) — see [_explanations]. Each
//    explanation maps identities exactly: a shifted line keeps its decision,
//    a deleted line's decision is dropped, a substituted line keeps it only
//    when lineKeyOf is unchanged (an amount edit: a pick's typed grams may
//    then be re-derived — token P~g accepts P:g or a re-derived pick).
//  * Of those explanations, only the ones that LOSE THE FEWEST decisions
//    are acceptable (invariant 2: keep a decision whenever the text allows).
//    The result must equal one acceptable explanation's layout EXACTLY —
//    position by position, every line without a decision on an engine row
//    (auto, unmatched, rule row), every decided row carrying its line's raw,
//    one row per line, none beyond. When the text view is unambiguous this
//    is exact identity preservation; when identical texts make it
//    ambiguous it implies the bounded rule (none lost when avoidable, none
//    duplicated, none on another ingredient, an untouched line keeps its
//    row). "Prefers each row's own position" is NOT enforced (a tiebreak).
//  * A person's write in the stale window (after the save, before the
//    compute) or during the compute's awaits lands on the line at its
//    position in the NEW recipe: it overlays that position.
//  * A provider failure mid-compute: the stored decided tokens must equal
//    an acceptable layout's as a multiset (none lost, none duplicated); the
//    next healthy compute must then land the layout exactly.
//  * After every check the model re-syncs to what the engine stored, so one
//    break is reported once and the fuzz goes on.
// Real data: 0405 Acquacotta (steps, groups, lines) and six other corpus
// lines (file named, proven at load). SYNTHESIZED (a stated exception):
// the edit scripts themselves, amount variants (leading quantity changed,
// lineKeyOf proven equal, e.g. "3 teaspoons salt"), and the interleavings.
// Answers: FixtureProvider(pending: pendingSearches), never the network.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _acquacotta = '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml';
const _pickId = 173468; // "Salt, table": recorded; every pick is this food.

/// Corpus lines from other recipes (the file each is read from).
const _others = {
  '2 teaspoons salt': '0176-grillroasted-boneless-turkey-breast.yaml',
  '1 teaspoon salt': '0070-skillet-chicken-fajitas.yaml',
  '¾ cup extra-virgin olive oil': '0856-olive-oil-cake.yaml',
  '1 tablespoon table salt': '0052-sesame-lemon-cucumber-salad.yaml',
  'Salt': '0007-tuscan-style-beef-stew.yaml',
  'Pepper': '0125-oven-roasted-chicken-thighs.yaml',
};

const _sp = 'Salt and pepper';
const _oilHalf = '½ cup extra-virgin olive oil';
const _oilQuarter = '¼ cup extra-virgin olive oil';

/// Seeds outside the default range whose saves broke an earlier v19
/// pairing (Run 050's fix batch, found at ORACLE_SEED_BASE 100000 to
/// 800000): every run replays them. The last two broke the heuristic v19
/// pairing (a re-layout after an FDC failure that was not a fixpoint; a
/// local search stuck on a plateau) and pass under the exact search.
const _regressionSeeds = [
  100019, 100053, 100138, 100234, 100247, 100286, 101428, 101430, 101584, //
  101912, 200035, 201411, 201570, 201839, 500644, 501143, 501571, 501663,
  600490, 800027, 800136, 800321, 801056, 600340, 602070,
];

/// Seeds of the gap fuzz ([_Sim.savedTwice]) that broke a pairing: every
/// gap run replays them. The first eight broke v20's pairing while it read
/// a position with no row as no line at all (224 violations in 191 of 1,000
/// seeds) and pass since a gap counts as a line of unknown text; the rest
/// broke it while it read the rows alone (120 in 112 of 1,000: a row-less
/// line after the last row, a row still carrying an amount edit's old
/// text) and pass since every layout keeps its lines' texts
/// (`recipe_layout`) and the pairing reads them as `laidOut`.
const _gapRegressionSeeds = [
  1, 5, 16, 41, 43, 44, 49, 56, //
  24, 46, 53, 60, 64, 68, 71, 81, 128, 130, 132, 135, 141, 145, 147, 152,
  153, 168, 173, 175, 194, 196,
  // v28 (Run 058 O18/S28): eleven identical lines in a 14-line save of three
  // edits stopped the pairing at its budget (a pick moved to a twin); the
  // twin runs laid out in their own order end it in 4,916 expansions.
  41487,
];

int _envInt(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

String _fmt(num g) => g == g.roundToDouble() ? '${g.toInt()}' : '$g';

IngredientLine _parsed(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
}

/// One line per raw text: the corpus parse when the corpus has the line,
/// else the editor's parse (a synthesized edit).
final Map<String, IngredientLine> _canon = {};
IngredientLine _line(String raw) => _canon[raw] ??= _parsed(raw);

/// The line [raw] as corpus recipe [file] stores it (proof it is real).
IngredientLine _corpusLine(String file, String raw) {
  final r = loadCorpusRecipe(file);
  return [
    for (final g in r.ingredients) ...g.items,
    for (final s in r.subsections)
      for (final g in s.ingredients ?? const <IngredientGroup>[]) ...g.items,
  ].firstWhere((l) => l.raw == raw);
}

/// A stored match row of [raw] at [position] (a pure pairing input).
IngredientMatchRow _row(
  int position,
  String raw, {
  String status = 'auto',
  String? key,
}) => IngredientMatchRow(
  recipeId: 'r',
  position: position,
  raw: raw,
  fdcId: null,
  description: null,
  dataType: null,
  confidence: 0,
  grams: null,
  gramSource: null,
  status: status,
  itemKey: key ?? lineKeyOf(_line(raw)),
);

/// [FixtureProvider] with two interleavings a test arms: [onCall] runs
/// once, at the next provider call (a person's write during one of the
/// compute's awaits), and [failAfter] throws at the provider call after
/// that many more (FDC failing mid-compute).
class _Provider implements NutritionProvider {
  _Provider(this.inner);
  final FixtureProvider inner;
  void Function()? onCall;
  int? failAfter;

  /// Foods FDC fails for (an outage on chosen rows: RULE A, v27).
  Set<int> failFoods = {};

  void _before() {
    final hook = onCall;
    onCall = null;
    hook?.call();
    final n = failAfter;
    if (n != null) {
      if (n <= 0) {
        failAfter = null;
        throw const NutritionProviderException('oracle: FDC down');
      }
      failAfter = n - 1;
    }
  }

  @override
  Future<List<FdcCandidate>> search(String query) async {
    _before();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    _before();
    if (failFoods.contains(fdcId)) {
      throw NutritionProviderException('oracle: food $fdcId down');
    }
    return inner.food(fdcId);
  }
}

/// A stored row as the oracle reads it: `S` a skip, `P:g` a pick with its
/// typed grams, `P*` a pick the engine re-weighed, `-` an engine row
/// (auto, unmatched, rule row), `?…` anything else. With [raw], a decided
/// row carrying another text is marked `!`.
String _tokenOf(IngredientMatchRow row, {String? raw}) {
  final String t;
  if (row.status == 'skipped') {
    t = 'S';
  } else if (row.status == 'overridden' && row.fdcId == _pickId) {
    t = row.gramSource == 'override' && row.grams != null
        ? 'P:${_fmt(row.grams!)}'
        : 'P*';
  } else if (row.status == 'auto' ||
      row.status == 'unmatched' ||
      isEngineRuleRow(row)) {
    return '-';
  } else {
    t = '?${row.status}/${row.fdcId}/${row.grams}';
  }
  return raw != null && row.raw != raw ? '!$t<"${row.raw}">' : t;
}

/// Whether a stored token [got] is the decision [want] (`P~g`: a pick
/// whose line's amount was edited — typed grams kept or re-derived).
bool _tokMatch(String want, String got) => want.startsWith('P~')
    ? got == 'P*' || got == 'P:${want.substring(2)}'
    : want == got;

/// One explanation of an edit's text view: old index → new index (null:
/// deleted) and the old indices whose text it substitutes.
typedef _Script = ({String name, List<int?> to, Set<int> subs, int cost});

/// The most ops one save may take: ORACLE_OPS_MAX (default 3; 1 is the
/// single-op oracle: every save one edit, explained by one op).
var _opsMax = _envInt('ORACLE_OPS_MAX', 3);

/// Time spent enumerating explanations (the fuzz reports its slowest seed).
final _explainClock = Stopwatch();

/// The length of the longest increasing run in [seq] (patience tails).
int _lis(List<int> seq) {
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

/// The fewest-op explanations turning texts [o] into [n] (see SEMANTICS);
/// empty when none costs at most 2 × [_opsMax].
///
/// A script is an injective partial map old → new. It costs its deletes
/// (unmapped old) + inserts (unmapped new) + substitutions (a mapped line
/// whose text differs: one op for the same ingredient — an amount edit —
/// two for another, which carries nothing, like the delete + insert it
/// is) + moves, where moves = mapped − the longest run of mapped lines
/// already in order (the fewest single-line moves; exact). A moved and
/// edited line is a move and a substitution. Of the cheapest scripts, the
/// ones losing the fewest decisions are acceptable ([_acceptable]) — no
/// "fewest ops as written" filter (v19 had one: it counted a substitution
/// to another ingredient one op and so preferred it to a delete + insert of
/// the same cost that kept a decision — Run 051 O2/S3). Every op now costs
/// one and a cross-ingredient substitution is the delete + insert it is.
/// Search: depth first over the old lines (map to an unused new line, same
/// text first, or delete), pruned by cost so far + the moves already
/// forced (mapped − LIS so far never falls) + max(excess, missing) of the
/// texts still unassigned (one op fixes at most one of each), iterative
/// deepening on the cost. Bound: ORACLE_OPS_MAX (3) edits per save over ≤
/// ~25 lines, so a cost ≤ 6; the fuzz reports its slowest seed.
List<_Script> _explanations(List<String> o, List<String> n) {
  for (var k = 0; k <= 2 * _opsMax; k++) {
    final out = _scriptsWithin(o, n, k);
    if (out.isNotEmpty) return out;
  }
  return const [];
}

/// Every script turning [o] into [n] at a cost of at most [k]
/// ([_explanations]).
List<_Script> _scriptsWithin(List<String> o, List<String> n, int k) {
  final keyOf = {
    for (final t in {...o, ...n}) t: lineKeyOf(_line(t)),
  };
  final out = <_Script>[];
  final to = List<int?>.filled(o.length, null);
  final used = List.filled(n.length, false);
  final seq = <int>[]; // the mapped new indices, in old order
  final restOld = <String, int>{}; // texts of old lines not yet assigned
  final unused = <String, int>{}; // texts of new lines not yet taken
  for (final t in o) {
    restOld[t] = (restOld[t] ?? 0) + 1;
  }
  for (final t in n) {
    unused[t] = (unused[t] ?? 0) + 1;
  }
  int textBound() {
    var excess = 0;
    var missing = 0;
    for (final t in {...restOld.keys, ...unused.keys}) {
      final d = (restOld[t] ?? 0) - (unused[t] ?? 0);
      if (d > 0) excess += d;
      if (d < 0) missing -= d;
    }
    return max(excess, missing);
  }

  void emit(int cost) {
    final subs = {
      for (final (i, j) in to.indexed)
        if (j != null && o[i] != n[j]) i,
    };
    // Name the moves by one longest in-order run (display only).
    final pairs = [
      for (final (i, j) in to.indexed)
        if (j != null) (i, j),
    ];
    final keep = <int>{};
    final len = List.filled(pairs.length, 1);
    final prev = List<int?>.filled(pairs.length, null);
    for (var a = 0; a < pairs.length; a++) {
      for (var c = 0; c < a; c++) {
        if (pairs[c].$2 < pairs[a].$2 && len[c] + 1 > len[a]) {
          len[a] = len[c] + 1;
          prev[a] = c;
        }
      }
    }
    var at = pairs.isEmpty ? null : 0;
    for (var a = 1; a < pairs.length; a++) {
      if (len[a] > len[at!]) at = a;
    }
    for (; at != null; at = prev[at]) {
      keep.add(pairs[at].$1);
    }
    final ops = [
      for (final (i, j) in to.indexed)
        if (j == null) 'delete $i',
      for (final (i, j) in pairs)
        if (!keep.contains(i)) 'move $i→$j',
      for (final i in subs) 'sub $i',
      for (var j = 0; j < n.length; j++)
        if (!used[j]) 'insert $j',
    ];
    out.add((
      name: ops.isEmpty ? 'no-op' : ops.join(', '),
      to: [...to],
      subs: subs,
      cost: cost,
    ));
  }

  // [cost]: the deletes and substitutions so far (another ingredient's
  // counting two).
  void walk(int i, int cost) {
    final bound = cost + seq.length - _lis(seq) + textBound();
    if (bound > k) return;
    if (i == o.length) {
      emit(bound); // now exact: inserts = the texts left unused
      return;
    }
    final t = o[i];
    restOld[t] = restOld[t]! - 1;
    // Same text first, then a substitution, then a delete.
    for (final same in [true, false]) {
      for (var j = 0; j < n.length; j++) {
        if (used[j] || (n[j] == t) != same) continue;
        used[j] = true;
        unused[n[j]] = unused[n[j]]! - 1;
        seq.add(j);
        to[i] = j;
        walk(
          i + 1,
          same ? cost : cost + (keyOf[t] == keyOf[n[j]] ? 1 : 2),
        );
        to[i] = null;
        seq.removeLast();
        unused[n[j]] = unused[n[j]]! + 1;
        used[j] = false;
      }
    }
    walk(i + 1, cost + 1);
    restOld[t] = restOld[t]! + 1;
  }

  walk(0, 0);
  return out;
}

/// A line and its hidden identity.
class _Ln {
  _Ln(this.id, this.line);
  final int id;
  final IngredientLine line;
}

bool _isDecision(String t) => t != '-';

/// The acceptable layouts after [before] → [after] with decisions
/// [tokens] (fewest lost among the fewest-op explanations), and the
/// explanations they come from. With [slack] (a diagnostic), every layout
/// of every script costing at most [slack] more, however many it loses.
(List<List<String>>, List<String>) _acceptable(
  List<_Ln> before,
  List<_Ln> after,
  Map<int, String> tokens, {
  int? slack,
}) {
  final o = [for (final l in before) l.line.raw];
  final n = [for (final l in after) l.line.raw];
  _explainClock.start();
  var scripts = _explanations(o, n);
  if (slack != null && scripts.isNotEmpty) {
    scripts = _scriptsWithin(o, n, scripts.first.cost + slack);
  }
  _explainClock.stop();
  if (scripts.isEmpty) {
    throw StateError('oracle: no script of ≤ $_opsMax op(s) explains it');
  }
  final byLost = <int, Map<String, (List<String>, List<String>)>>{};
  for (final s in scripts) {
    final lay = List.filled(after.length, '-');
    var lost = 0;
    for (final (k, l) in before.indexed) {
      final t = tokens[l.id];
      if (t == null) continue;
      final at = s.to[k];
      final sub = s.subs.contains(k);
      if (at == null ||
          (sub && lineKeyOf(l.line) != lineKeyOf(after[at].line))) {
        lost++;
        continue;
      }
      lay[at] = sub && t.startsWith('P:') ? 'P~${t.substring(2)}' : t;
    }
    final entry = (byLost[lost] ??= {})[lay.join('|')] ??= (lay, <String>[]);
    entry.$2.add(s.name);
  }
  final fewest = slack != null
      ? [for (final m in byLost.values) ...m.values]
      : byLost[byLost.keys.reduce(min)]!.values;
  return (
    [for (final e in fewest) e.$1],
    [for (final e in fewest) e.$2.join('/')],
  );
}

/// The decisions [want] no stored token matches, and the stored tokens
/// [got] no wanted decision takes (a copy, or a decision from nowhere).
(List<String>, List<String>) _unmatched(List<String> want, List<String> got) {
  final left = [...got];
  final missing = <String>[];
  for (final w in [
    ...want.where((t) => !t.startsWith('P~')),
    ...want.where((t) => t.startsWith('P~')),
  ]) {
    var i = left.indexWhere(
      (g) => w.startsWith('P~') ? g == 'P:${w.substring(2)}' : g == w,
    );
    if (i < 0 && w.startsWith('P~')) i = left.indexOf('P*');
    if (i < 0) {
      missing.add(w);
    } else {
      left.removeAt(i);
    }
  }
  return (missing, left);
}

List<String> _closest(List<List<String>> want, List<String> got) {
  int miss(List<String> lay) => [
    for (var p = 0; p < got.length; p++)
      if (!_tokMatch(lay[p], got[p])) p,
  ].length;
  return want.reduce((a, b) => miss(b) < miss(a) ? b : a);
}

String _short(String raw) =>
    raw.length <= 30 ? raw.padRight(30) : '${raw.substring(0, 29)}…';

typedef _Violation = ({Set<String> kinds, String text});

/// One recipe under edit: 0405's steps and group names, the lines a test
/// or the fuzzer lays out, a fresh database.
class _Sim {
  _Sim(this.base, this.provider, this.db);
  final Recipe base;
  final _Provider provider;
  final SaltDatabase db;

  /// The database file (the `outage` mode empties its caches of the pick).
  String? dbPath;
  List<List<_Ln>> groups = [];

  /// identity → its decision: `S`, `P:g`, or `P~g` (see [_tokMatch]).
  final tokens = <int, String>{};
  final violations = <_Violation>[];
  var _nextId = 0;
  int grams = 1000;
  Recipe? _recipe;

  List<_Ln> get flat => [for (final g in groups) ...g];

  Recipe get recipe => _recipe ??= base.copyWith(
    ingredients: [
      for (final (i, g) in groups.indexed)
        IngredientGroup(
          group: i < base.ingredients.length
              ? base.ingredients[i].group
              : 'GROUP ${i + 1}',
          items: [for (final l in g) l.line],
        ),
    ],
  );

  _Ln fresh(String raw) => _Ln(_nextId++, _line(raw));

  void start(List<List<String>> raws) {
    groups = [
      for (final g in raws) [for (final r in g) fresh(r)],
    ];
    _recipe = null;
  }

  /// The save every edit path funnels through (recipe_edit_service's
  /// _store → upsertRecipe). A design that lays rows out at save time
  /// must do it under this call, or this helper must call it.
  void save() => db.upsertRecipe(
    recipe,
    sourceSlug: 'src',
    contentHash: contentHashOf(recipe),
  );

  (int, int) locate(int p) {
    var at = p;
    for (final (g, lines) in groups.indexed) {
      if (at < lines.length) return (g, at);
      at -= lines.length;
    }
    return (groups.length - 1, groups.last.length);
  }

  // Edits (each keeps every other line's identity).
  void insertAt(int p, String raw) {
    final (g, i) = locate(p);
    groups[g].insert(i, fresh(raw));
    _recipe = null;
  }

  void insertIn(int g, int i, String raw) {
    groups[g].insert(i, fresh(raw));
    _recipe = null;
  }

  void deleteAt(int p) {
    final (g, i) = locate(p);
    groups[g].removeAt(i);
    _recipe = null;
  }

  void setText(int p, String raw) {
    final (g, i) = locate(p);
    groups[g][i] = _Ln(groups[g][i].id, _line(raw));
    _recipe = null;
  }

  void moveTo(int p, int g, int i) {
    final (from, at) = locate(p);
    final l = groups[from].removeAt(at);
    groups[g].insert(min(i, groups[g].length), l);
    _recipe = null;
  }

  Map<String, Object?> body({required bool skip, int? g}) =>
      skip ? {'skipped': true} : {'fdc_id': _pickId, 'grams': g ?? ++grams};

  String tokenOfBody(Map<String, Object?> b) =>
      b['skipped'] == true ? 'S' : 'P:${b['grams']}';

  /// A person's decision on line [p] at a quiet moment (computed rows).
  Future<void> decide(int p, {bool skip = false, int? g}) async {
    final b = body(skip: skip, g: g);
    await applyMatchOverride(db, provider, recipe, p, b);
    tokens[flat[p].id] = tokenOfBody(b);
  }

  /// matchAndCompute; the provider failure it raised or returned (a
  /// decided row's derivation, RULE A), or null. A fixture miss
  /// ([UnrecordedAnswer], an Error) fails the run.
  Future<NutritionProviderException?> compute() async {
    try {
      return await matchAndCompute(db, provider, recipe);
    } on NutritionProviderException catch (e) {
      return e;
    }
  }

  /// The first compute of the lines: no decision yet, every row an engine
  /// row.
  Future<void> first() async {
    save();
    final failure = await compute();
    if (failure != null) throw StateError('first compute failed: $failure');
    _check(
      'first compute',
      const [],
      flat,
      [List.filled(flat.length, '-')],
      const {},
      const {},
    );
  }

  /// [name]: the edit [mutate] makes, saved, then computed under [mode] —
  /// `plain`; `stale` (a person's decision on line [at] (mod the line
  /// count) of the NEW recipe
  /// between the save and the compute: the stale window); `mid` (that
  /// decision written at the compute's first provider call); `fail` (FDC
  /// throws at the provider call after [failAfter] more, then a healthy
  /// compute) — and checked. Returns the mode exercised (`mid` and `fail`
  /// are `plain` when the compute asked FDC nothing).
  Future<String> edit(
    String name,
    void Function() mutate, {
    String mode = 'plain',
    int at = 0,
    bool skip = true,
    int failAfter = 0,
  }) {
    final before = flat;
    mutate();
    return saved(
      name,
      before,
      mode: mode,
      at: at,
      skip: skip,
      failAfter: failAfter,
    );
  }

  /// [edit] for lines already edited (one or several ops) from [before]:
  /// saved once, computed under [mode], checked.
  Future<String> saved(
    String name,
    List<_Ln> before, {
    String mode = 'plain',
    int at = 0,
    bool skip = true,
    int failAfter = 0,
  }) async {
    final after = flat;
    final line = at % after.length;
    final pre = Map.of(tokens);
    final (accept, why) = _acceptable(before, after, pre);
    save();
    final overlays = <int, String>{};
    final pending = <Future<void>>[];
    var ran = mode == 'stale' ? mode : 'plain';
    Future<void> person() {
      final b = body(skip: skip);
      overlays[line] = tokenOfBody(b);
      return applyMatchOverride(db, provider, recipe, line, b).then<void>(
        (_) {},
        onError: (Object e) {
          overlays.remove(line);
          violations.add((kinds: {'HARNESS'}, text: '$name: write threw $e'));
        },
      );
    }

    if (mode == 'stale') await person();
    if (mode == 'mid') {
      provider.onCall = () {
        ran = 'mid';
        pending.add(person());
      };
    }
    if (mode == 'fail') provider.failAfter = failAfter;
    if (mode == 'outage') {
      // RULE A (v27): FDC out for the decided food, which no cache holds,
      // so every decision's derivation on it needs FDC: those rows are
      // left underived (never lost or moved), the compute returns the
      // failure, and the healthy compute after derives every one.
      raw.sqlite3.open(dbPath!)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [_pickId])
        ..execute(
          'DELETE FROM fdc_search_cache '
          "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
          [_pickId],
        )
        ..dispose();
      provider.failFoods = {_pickId};
    }
    final failure = await compute();
    provider
      ..onCall = null
      ..failAfter = null
      ..failFoods = {};
    await Future.wait(pending);
    final want = [
      for (final lay in accept)
        [for (final (p, t) in lay.indexed) overlays[p] ?? t],
    ];
    if (failure != null) ran = mode == 'outage' ? 'outage' : 'fail';
    final label = '$name [$ran; explained by ${why.join(' | ')}]';
    if (failure != null) {
      _checkAfterFailure(label, want);
      final again = await compute();
      if (again != null) throw StateError('recovery compute failed: $again');
    }
    _check(label, before, after, want, pre, overlays);
    // Every decided row derived once FDC is back (RULE A, v27).
    if (db.hasUnderivedRows(recipe.id)) {
      violations.add((
        kinds: {'UNDERIVED'},
        text: '$label\n  a decided row is underived after a healthy compute',
      ));
    }
    return ran;
  }

  /// Two saves with the rows left INCOMPLETE between them (Run 051 S4):
  /// the edits already made from [before] are saved; then, by [gap],
  /// `stale` a person's decision on line [at] (mod the count) of that
  /// recipe in the stale window, no compute; `mid` a compute during whose
  /// first provider call [second] is made and saved (its gate trips, rows
  /// unwritten); `fail` a compute FDC fails at the provider call after
  /// [failAfter] more — then [second]'s edits are made and saved (unless
  /// `mid` already did), one healthy compute follows, and the result is
  /// checked against the expectation CHAINED over both saves (each first
  /// save's acceptable layout, the person's write overlaid, carried through
  /// the second save's explanations). Returns the gap exercised (`mid` and
  /// `fail` fall back to `plain`: a full compute between the saves).
  Future<String> savedTwice(
    String name,
    List<_Ln> before,
    void Function() second, {
    String gap = 'stale',
    int at = 0,
    bool skip = true,
    int failAfter = 0,
  }) async {
    final mid = flat;
    final pre = Map.of(tokens);
    final (accept1, why1) = _acceptable(before, mid, pre);
    save();
    final overlays = <int, String>{};
    var ran = gap == 'stale' ? gap : 'plain';
    var edited = false;
    void edit2() {
      if (edited) return;
      edited = true;
      second();
      save();
    }

    if (gap == 'stale') {
      final line = at % mid.length;
      final b = body(skip: skip);
      overlays[line] = tokenOfBody(b);
      try {
        await applyMatchOverride(db, provider, recipe, line, b);
      } on Object catch (e) {
        overlays.remove(line);
        violations.add((kinds: {'HARNESS'}, text: '$name: write threw $e'));
      }
    } else {
      if (gap == 'mid') {
        provider.onCall = () {
          ran = 'mid';
          edit2();
        };
      }
      if (gap == 'fail') provider.failAfter = failAfter;
      final failure = await compute();
      provider
        ..onCall = null
        ..failAfter = null;
      if (failure != null) ran = 'fail';
    }
    edit2();
    final after = flat;
    final want = <String, List<String>>{};
    final why = <String>{};
    for (final (k, lay1) in accept1.indexed) {
      final tokens1 = <int, String>{
        for (final (p, t) in lay1.indexed)
          if (_isDecision(overlays[p] ?? t)) mid[p].id: overlays[p] ?? t,
      };
      final (accept2, why2) = _acceptable(mid, after, tokens1);
      for (final lay in accept2) {
        want[lay.join('|')] = lay;
      }
      why.add('${why1[k]} ⇒ ${why2.join(' | ')}');
    }
    final failure = await compute();
    if (failure != null) throw StateError('healthy compute failed: $failure');
    _check(
      '$name [gap $ran; explained by ${why.join(' ‖ ')}]',
      before,
      after,
      [...want.values],
      pre,
      const {},
      chained: true,
    );
    return ran;
  }

  void _checkAfterFailure(String what, List<List<String>> want) {
    final rows = db.ingredientMatchesFor(recipe.id);
    final got = [
      for (final r in rows)
        if (_isDecision(_tokenOf(r))) _tokenOf(r),
    ];
    final parked = [
      for (final r in rows)
        if (r.position < 0) r.position,
    ];
    for (final lay in want) {
      final (lost, extra) = _unmatched(lay.where(_isDecision).toList(), got);
      if (lost.isEmpty && extra.isEmpty && parked.isEmpty) return;
    }
    final (lost, extra) = _unmatched(
      want.first.where(_isDecision).toList(),
      got,
    );
    violations.add((
      kinds: {
        'AFTER_FAILURE',
        if (lost.isNotEmpty) 'LOST',
        if (extra.isNotEmpty) 'DUPLICATED',
        if (parked.isNotEmpty) 'ROWS',
      },
      text:
          '$what\n  right after the failure: stored decisions $got, wanted '
          'one of $want (missing $lost, extra $extra, parked $parked)',
    ));
  }

  /// The stored layout against [want]; a violation when none matches. Then
  /// the model re-syncs to what is stored.
  void _check(
    String what,
    List<_Ln> before,
    List<_Ln> after,
    List<List<String>> want,
    Map<int, String> pre,
    Map<int, String> overlays, {
    bool chained = false,
  }) {
    final rows = db.ingredientMatchesFor(recipe.id);
    final byPos = {for (final r in rows) r.position: r};
    final got = [
      for (final (p, l) in after.indexed)
        byPos[p] == null ? '?missing' : _tokenOf(byPos[p]!, raw: l.line.raw),
    ];
    final stray = [
      for (final r in rows)
        if (r.position < 0 || r.position >= after.length)
          '${r.position}:${_tokenOf(r)}',
    ];
    List<String>? hit;
    for (final lay in stray.isEmpty ? want : const <List<String>>[]) {
      if ([for (final (p, g) in got.indexed) _tokMatch(lay[p], g)].every(
        (ok) => ok,
      )) {
        hit = lay;
        break;
      }
    }
    final best = hit ?? _closest(want, got);
    if (hit == null) {
      final keyOf = {for (final l in before) l.id: lineKeyOf(l.line)};
      final owners = [
        for (final MapEntry(key: id, value: t) in pre.entries) ...[
          (t, keyOf[id]),
          if (t.startsWith('P:')) ('P~${t.substring(2)}', keyOf[id]),
        ],
        for (final MapEntry(key: p, value: t) in overlays.entries)
          (t, lineKeyOf(after[p].line)),
      ];
      final kinds = <String>{
        if (stray.isNotEmpty ||
            got.any((g) => g.startsWith('?') || g.startsWith('!')))
          'ROWS',
      };
      final (lost, extra) = _unmatched(
        best.where(_isDecision).toList(),
        got.where(_isDecision).toList(),
      );
      if (lost.isNotEmpty) kinds.add('LOST');
      for (final e in extra) {
        kinds.add(best.any((w) => _tokMatch(w, e)) ? 'DUPLICATED' : 'EXTRA');
      }
      for (final (p, g) in got.indexed) {
        final keys = {
          for (final (t, k) in owners)
            if (t == g || _tokMatch(t, g)) k,
        };
        if (_isDecision(g) &&
            keys.isNotEmpty &&
            !keys.contains(lineKeyOf(after[p].line))) {
          kinds.add('WRONG_INGREDIENT');
        }
      }
      if (kinds.isEmpty) kinds.add('MOVED');
      // Not the semantics, a tag: what was stored IS the layout of a
      // cheapest script losing more (MORE_LOST), or of a script costing one
      // more (COSTLIER; e.g. an exact-text reading over two substitutions).
      // (Not for a chained check: before → after may take two saves' ops.)
      bool storedAt(int slack) =>
          !chained &&
          before.isNotEmpty &&
          _acceptable(before, after, pre, slack: slack).$1.any(
            (lay) => [
              for (final (p, g) in got.indexed)
                _tokMatch(overlays[p] ?? lay[p], g),
            ].every((ok) => ok),
          );
      if (storedAt(0)) {
        kinds.add('MORE_LOST');
      } else if (storedAt(1)) {
        kinds.add('COSTLIER');
      }
      final b = StringBuffer(
        '${kinds.join('+')}: $what\n'
        '  ${want.length} acceptable layout(s), the nearest shown; old line '
        '#identity decision → new line #identity want got\n'
        '${overlays.isEmpty ? '' : "  a person's write (stale window or "
                  'mid-compute) on new line(s): $overlays\n'}',
      );
      for (var i = 0; i < max(before.length, after.length); i++) {
        final o = i < before.length
            ? '${_short(before[i].line.raw)} #${before[i].id} '
                  '${pre[before[i].id] ?? '-'}'
            : '';
        final n = i < after.length
            ? '${_short(after[i].line.raw)} #${after[i].id} want ${best[i]} '
                  'got ${got[i]}${_tokMatch(best[i], got[i]) ? '' : '   <<'}'
            : '';
        b.writeln('  ${'$i'.padLeft(2)} ${o.padRight(44)} | $n');
      }
      if (stray.isNotEmpty) b.writeln('  stray rows: $stray');
      violations.add((kinds: kinds, text: b.toString()));
    }
    for (final (p, l) in after.indexed) {
      final g = got[p];
      final w = best[p];
      if (g == 'S' || g.startsWith('P:')) {
        tokens[l.id] = w.startsWith('P~') && _tokMatch(w, g) ? w : g;
      } else if (g == 'P*') {
        tokens[l.id] = w.startsWith('P~') ? w : 'P~?${_nextId++}';
      } else {
        tokens.remove(l.id);
      }
    }
    final alive = {for (final l in after) l.id};
    tokens.removeWhere((id, _) => !alive.contains(id));
  }

  void swap(int g, int i) {
    final l = groups[g][i];
    groups[g][i] = groups[g][i + 1];
    groups[g][i + 1] = l;
    _recipe = null;
  }

  /// One save's 1..[_opsMax] random edits, made: their names and kinds
  /// (the single-op mode draws no count, so its seeds replay the one-edit
  /// fuzz).
  (List<String>, List<String>) randomEdits(
    Random rng,
    List<String> pool,
    Map<String, List<String>> variants,
  ) {
    final names = <String>[];
    final kinds = <String>[];
    for (var k = _opsMax == 1 ? 1 : 1 + rng.nextInt(_opsMax); k > 0; k--) {
      final (name, mutate) = randomEdit(rng, pool, variants);
      mutate();
      names.add(name);
      kinds.add(name.split(' ').first);
    }
    return (names, kinds);
  }

  /// One random edit, tagged by its kind: the name and the mutation.
  (String, void Function()) randomEdit(
    Random rng,
    List<String> pool,
    Map<String, List<String>> variants,
  ) {
    final all = flat;
    final n = all.length;
    String raw(int p) => all[p].line.raw;
    const bag = [0, 0, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7, 8];
    while (true) {
      final g = rng.nextInt(groups.length);
      final i = rng.nextInt(groups[g].length + 1);
      final p = rng.nextInt(n);
      switch (bag[rng.nextInt(bag.length)]) {
        case 0:
          final src = raw(rng.nextInt(n));
          return (
            'copy-insert "$src" in group $g at $i',
            () => insertIn(g, i, src),
          );
        case 1:
          final src = pool[rng.nextInt(pool.length)];
          return ('insert "$src" in group $g at $i', () => insertIn(g, i, src));
        case 2:
          if (n <= 2 || groups[locate(p).$1].length < 2) continue;
          return ('delete line $p "${raw(p)}"', () => deleteAt(p));
        case 3:
          final at = [
            for (var q = 0; q < n; q++)
              if (variants[raw(q)]?.isNotEmpty ?? false) q,
          ];
          if (at.isEmpty) continue;
          final q = at[rng.nextInt(at.length)];
          final to = variants[raw(q)]![rng.nextInt(variants[raw(q)]!.length)];
          return (
            'amount-edit line $q "${raw(q)}" → "$to"',
            () => setText(q, to),
          );
        case 4:
          final key = lineKeyOf(all[p].line);
          final to = [
            for (final c in pool)
              if (lineKeyOf(_line(c)) != key) c,
          ];
          final c = to[rng.nextInt(to.length)];
          return (
            'ingredient-edit line $p "${raw(p)}" → "$c"',
            () => setText(p, c),
          );
        case 5:
          final q = rng.nextInt(n);
          if (raw(q) == raw(p)) continue;
          final c = raw(q);
          return (
            'edit-to-equal line $p "${raw(p)}" → line $q\'s "$c"',
            () => setText(p, c),
          );
        case 6:
          if (groups[g].length < 2) continue;
          final k = rng.nextInt(groups[g].length - 1);
          return ('swap group $g lines $k,${k + 1}', () => swap(g, k));
        case 7:
          final (from, _) = locate(p);
          if (groups.length < 2 || groups[from].length < 2) continue;
          final to =
              (from + 1 + rng.nextInt(groups.length - 1)) % groups.length;
          final k = rng.nextInt(groups[to].length + 1);
          return (
            'cross-group-move line $p "${raw(p)}" to group $to at $k',
            () => moveTo(p, to, k),
          );
        default:
          return ('recompute (no edit)', () {});
      }
    }
  }
}

/// [raw] with its leading quantity changed, the ingredient unchanged
/// (synthesized amount edits; lineKeyOf proven equal).
List<String> _variantsOf(String raw) {
  final m = RegExp('^([0-9]+|[¼½¾⅛⅓⅔]) ').firstMatch(raw);
  if (m == null) return const [];
  final key = lineKeyOf(_line(raw));
  return [
    for (final q in const ['1', '2', '3', '¼', '½', '¾'])
      if (q != m[1]) '$q${raw.substring(m[1]!.length)}',
  ].where((v) => lineKeyOf(_line(v)) == key).toList();
}

void main() {
  late Recipe acqua;
  late FixtureProvider fixtures;
  late List<List<String>> acquaRaws;
  final pool = <String>[];
  final variants = <String, List<String>>{};

  setUpAll(() async {
    if (!corpusAvailable) return;
    acqua = loadCorpusRecipe(_acquacotta);
    acquaRaws = [
      for (final g in acqua.ingredients) [for (final l in g.items) l.raw],
    ];
    for (final g in acqua.ingredients) {
      for (final l in g.items) {
        _canon[l.raw] ??= l;
      }
    }
    for (final MapEntry(key: raw, value: file) in _others.entries) {
      _canon[raw] ??= _corpusLine(file, raw);
    }
    fixtures = FixtureProvider(pending: pendingSearches);
    // Every line and variant the fuzz may write must have its FDC answers
    // recorded: each is computed alone once (0405's steps around it).
    final dir = Directory.systemTemp.createTempSync('oracle-probe');
    final db = SaltDatabase.open('${dir.path}/salt.db')
      ..upsertSource(slug: 'src', name: 'Test', type: 'book');
    Future<bool> recorded(String raw) async {
      final r = acqua.copyWith(
        id: 'probe-${raw.hashCode}',
        slug: 'probe-${raw.hashCode}',
        ingredients: [
          IngredientGroup(items: [_line(raw)]),
        ],
      );
      db.upsertRecipe(r, sourceSlug: 'src', contentHash: contentHashOf(r));
      try {
        await matchAndCompute(db, fixtures, r);
        return true;
      } on NutritionProviderException {
        return false;
      }
    }

    final dropped = <String>[];
    for (final raw in [..._canon.keys]) {
      if (!await recorded(raw)) {
        dropped.add(raw);
        continue;
      }
      pool.add(raw);
      final ok = <String>[];
      for (final v in _variantsOf(raw)) {
        (await recorded(v) ? ok : dropped).add(v);
      }
      if (ok.isNotEmpty) variants[raw] = ok;
    }
    db.dispose();
    dir.deleteSync(recursive: true);
    print(
      'oracle pool: ${pool.length} corpus lines, '
      '${variants.values.expand((v) => v).length} amount variants; '
      'unrecorded, left out: $dropped',
    );
  });

  (_Sim, void Function()) open() {
    final dir = Directory.systemTemp.createTempSync('oracle');
    final db = SaltDatabase.open('${dir.path}/salt.db')
      ..upsertSource(slug: 'src', name: 'Test', type: 'book');
    return (
      _Sim(acqua, _Provider(fixtures), db)..dbPath = '${dir.path}/salt.db',
      () {
        db.dispose();
        dir.deleteSync(recursive: true);
      },
    );
  }

  _Sim sim0() {
    final (sim, close) = open();
    addTearDown(close);
    return sim;
  }

  /// A fuzz seed's lines: 0405 whole, or a dense list of repeated and
  /// same-ingredient corpus lines; then the first compute.
  Future<void> startRandom(_Sim sim, Random rng) async {
    const dense = [
      _sp,
      _sp,
      _oilHalf,
      _oilQuarter,
      '¾ cup extra-virgin olive oil',
      '2 teaspoons salt',
      '1 teaspoon salt',
      'Salt',
      'Pepper',
    ];
    if (rng.nextInt(5) < 2) {
      sim.start(acquaRaws);
    } else {
      sim.start([
        for (var g = 1 + rng.nextInt(3); g > 0; g--)
          [
            for (var i = 1 + rng.nextInt(4); i > 0; i--)
              rng.nextInt(10) < 6
                  ? dense[rng.nextInt(dense.length)]
                  : pool[rng.nextInt(pool.length)],
          ],
      ]);
    }
    await sim.first();
  }

  /// Up to [most] random decisions at a quiet moment.
  Future<void> decideRandom(_Sim sim, Random rng, int most) async {
    for (var k = rng.nextInt(most + 1); k > 0; k--) {
      await sim.decide(rng.nextInt(sim.flat.length), skip: rng.nextInt(5) < 2);
    }
  }

  void verdict(_Sim sim) {
    for (final v in sim.violations) {
      print(v.text);
    }
    expect(
      [for (final v in sim.violations) v.kinds.join('+')],
      isEmpty,
      reason: sim.violations.map((v) => v.text).join('\n'),
    );
  }

  // 0405's flat lines: 4 "½ cup extra-virgin olive oil", 5 "Salt and
  // pepper" (SOUP); 16 bread, 17 "¼ cup extra-virgin olive oil", 18 "Salt
  // and pepper" (TOAST). Every edit below is synthesized (a stated
  // exception); every line is a corpus line unless named a variant.
  group('scenarios', () {
    test(
      'S1 (v14): a plain recompute of 0405 with a pick on the second '
      '"Salt and pepper" — the first copy\'s rule row never takes it',
      () async {
        final sim = sim0()..start(acquaRaws);
        await sim.first();
        await sim.decide(18, g: 5);
        await sim.edit('recompute', () {});
        verdict(sim);
      },
    );

    for (final (verb, to) in [
      ('edited to "Salt"', 'Salt'),
      ('deleted', null),
    ]) {
      test('S2 (v15): 0405, the pick on line 18; the FIRST copy (5) $verb — '
          'the second copy keeps its pick', () async {
        final sim = sim0()..start(acquaRaws);
        await sim.first();
        await sim.decide(18, g: 5);
        await sim.edit(
          'line 5 $verb',
          () => to == null ? sim.deleteAt(5) : sim.setText(5, to),
        );
        verdict(sim);
      });
    }

    for (final skip in [false, true]) {
      test(
        'S3 (v15): two decided twins (a pick 3 g, ${skip ? 'a skip' : 'a '
                  'pick 7 g'}) and a line inserted above: both move down one',
        () async {
          final sim = sim0()
            ..start([
              [_sp, _sp],
            ]);
          await sim.first();
          await sim.decide(0, g: 3);
          await sim.decide(1, skip: skip, g: 7);
          await sim.edit(
            'insert ½ cup oil at 0',
            () => sim.insertAt(0, _oilHalf),
          );
          verdict(sim);
        },
      );
    }

    test(
      "S4a (v15): a person's skip of the engine copy (line 2) written at "
      "the compute's first FDC call (the inserted line's search) stands — "
      'the engine re-derives line 2 after it — and the pick moves to line 1',
      () async {
        final sim = sim0()
          ..start([
            [_sp, _sp],
          ]);
        await sim.first();
        await sim.decide(0, g: 3);
        final ran = await sim.edit(
          'insert ½ cup oil at 0; skip line 2 mid-compute',
          () => sim.insertAt(0, _oilHalf),
          mode: 'mid',
          at: 2,
        );
        expect(ran, 'mid', reason: 'the hook never fired');
        verdict(sim);
      },
    );

    test('S4b (v15): FDC failing at the inserted line leaves both decided '
        'twins intact, and the next compute lands them', () async {
      final sim = sim0()
        ..start([
          [_sp, _sp],
        ]);
      await sim.first();
      await sim.decide(0, g: 3);
      await sim.decide(1, skip: true);
      final ran = await sim.edit(
        'insert ½ cup oil at 0; FDC down',
        () => sim.insertAt(0, _oilHalf),
        mode: 'fail',
      );
      expect(ran, 'fail', reason: 'the failure never fired');
      verdict(sim);
    });

    test('S5 (v16 HIGH): 0405, pick 5 g on line 18; line 17 (¼ cup oil) '
        'edited to "Salt and pepper", then back — the untouched line 18 '
        'keeps its pick throughout', () async {
      final sim = sim0()..start(acquaRaws);
      await sim.first();
      await sim.decide(18, g: 5);
      await sim.edit('line 17 → "$_sp"', () => sim.setText(17, _sp));
      await sim.edit('line 17 back', () => sim.setText(17, _oilQuarter));
      final end = [
        for (final r in sim.db.ingredientMatchesFor(sim.recipe.id))
          '${r.position}:${_tokenOf(r)}',
      ].where((t) => !t.endsWith(':-')).toList();
      if (end.join() != '18:P:5') {
        sim.violations.add((
          kinds: {'LOST'},
          text: 'S5 end state: decided rows $end, wanted [18:P:5]',
        ));
      }
      verdict(sim);
    });

    test('S6 (v16): [½ cup oil, "Salt and pepper" ×2], a pick on the second '
        'copy; the first (engine) copy deleted — the pick stays', () async {
      final sim = sim0()
        ..start([
          [_oilHalf, _sp, _sp],
        ]);
      await sim.first();
      await sim.decide(2, g: 7);
      await sim.edit('delete line 1', () => sim.deleteAt(1));
      verdict(sim);
    });

    test('S7 (v16, since v15): ["½ cup extra-virgin olive oil" ×2], picks '
        '3 g and 7 g; the first amount-edited to "¾ cup" (0856\'s line) — '
        'both picks stay, each on its line', () async {
      final sim = sim0()
        ..start([
          [_oilHalf, _oilHalf],
        ]);
      await sim.first();
      await sim.decide(0, g: 3);
      await sim.decide(1, g: 7);
      await sim.edit(
        'line 0 → "¾ cup extra-virgin olive oil"',
        () => sim.setText(0, '¾ cup extra-virgin olive oil'),
      );
      verdict(sim);
    });

    test('S8 (v16): ["2 teaspoons salt", "1 teaspoon salt"], skip line 1, '
        'line 1 amount-edited to "3 teaspoons salt" (a variant) — the skip '
        'stays on line 1, never on the untouched line 0', () async {
      final sim = sim0()
        ..start([
          ['2 teaspoons salt', '1 teaspoon salt'],
        ]);
      await sim.first();
      await sim.decide(1, skip: true);
      await sim.edit(
        'line 1 → "3 teaspoons salt"',
        () => sim.setText(1, '3 teaspoons salt'),
      );
      verdict(sim);
    });

    for (final skip in [true, false]) {
      test('S9 (v16 critic): the stale window — 0405, pick 5 g on line 18; '
          '"2 teaspoons salt" inserted at 0 and saved; before any compute a '
          'person ${skip ? 'skips' : 'picks'} line 18 (the ¼ cup oil, '
          'shifted) — it lands there and line 19 keeps the 5 g pick', () async {
        final sim = sim0()..start(acquaRaws);
        await sim.first();
        await sim.decide(18, g: 5);
        await sim.edit(
          'insert "2 teaspoons salt" at 0; line 18 decided in the stale window',
          () => sim.insertAt(0, '2 teaspoons salt'),
          mode: 'stale',
          at: 18,
          skip: skip,
        );
        verdict(sim);
      });
    }

    test('swap: 0405 lines 4 (½ cup oil, skipped) and 5 ("Salt and pepper", '
        'pick 3 g) swapped — each decision follows its line', () async {
      final sim = sim0()..start(acquaRaws);
      await sim.first();
      await sim.decide(4, skip: true);
      await sim.decide(5, g: 3);
      await sim.edit('swap lines 4,5', () => sim.swap(0, 4));
      verdict(sim);
    });

    test("cross-group: 0405's TOAST \"Salt and pepper\" (pick 5 g) moved to "
        'the top of SOUP, the bread (skipped) shifting down', () async {
      final sim = sim0()..start(acquaRaws);
      await sim.first();
      await sim.decide(18, g: 5);
      await sim.decide(16, skip: true);
      await sim.edit('move line 18 to SOUP 0', () => sim.moveTo(18, 0, 0));
      await sim.edit(
        'move line 6 (the SOUP "Salt and pepper") to the end of TOAST',
        () => sim.moveTo(6, 1, 3),
      );
      verdict(sim);
    });

    test('three copies (engine, pick 3 g, skip): the oil inserted between '
        'copies 0 and 1, then copy 0 deleted', () async {
      final sim = sim0()
        ..start([
          [_sp, _sp, _sp],
        ]);
      await sim.first();
      await sim.decide(1, g: 3);
      await sim.decide(2, skip: true);
      await sim.edit('insert oil at 1', () => sim.insertAt(1, _oilHalf));
      await sim.edit('delete line 0', () => sim.deleteAt(0));
      await sim.edit('delete line 0 (the oil)', () => sim.deleteAt(0));
      verdict(sim);
    });

    test('S10 (found by this fuzz, seed 112): three copies (pick 3 g, '
        'engine, pick 7 g), FDC failing at the oil inserted above; the next '
        'healthy compute must not close the gap the failure left (the '
        "engine copy's row) by sliding the 7 g pick onto it", () async {
      final sim = sim0()
        ..start([
          [_sp, _sp, _sp],
        ]);
      await sim.first();
      await sim.decide(0, g: 3);
      await sim.decide(2, g: 7);
      final ran = await sim.edit(
        'insert ½ cup oil at 0; FDC down at its search',
        () => sim.insertAt(0, _oilHalf),
        mode: 'fail',
      );
      expect(ran, 'fail', reason: 'the failure never fired');
      verdict(sim);
    });

    test('four copies (pick 3 g, engine, skip, pick 7 g): a fifth copy '
        'inserted at 2, line 1 deleted, the oil inserted at 2, line 0 '
        'deleted', () async {
      final sim = sim0()
        ..start([
          [_sp, _sp, _sp, _sp],
        ]);
      await sim.first();
      await sim.decide(0, g: 3);
      await sim.decide(2, skip: true);
      await sim.decide(3, g: 7);
      await sim.edit('insert a copy at 2', () => sim.insertAt(2, _sp));
      await sim.edit('delete line 1', () => sim.deleteAt(1));
      await sim.edit('insert oil at 2', () => sim.insertAt(2, _oilHalf));
      await sim.edit('delete line 0', () => sim.deleteAt(0));
      verdict(sim);
    });

    // Multi-edit saves (Run 050): several ops, ONE save, then the compute.
    const onion = '1 large onion, chopped coarse';
    const celery = '2 celery ribs, chopped coarse';
    const oilOne = '1 cup extra-virgin olive oil'; // an amount variant
    test("Case A (Run 050, Sonnet): [½ cup oil, 'Salt and pepper', ¼ cup "
        'oil (pick 5 g)]; one save deletes the ½ cup line and moves the ¼ '
        'cup line up — the untouched ¼ cup line keeps its pick', () async {
      final sim = sim0()
        ..start([
          [_oilHalf, _sp, _oilQuarter],
        ]);
      await sim.first();
      await sim.decide(2, g: 5);
      final before = sim.flat;
      sim
        ..deleteAt(0)
        ..moveTo(1, 0, 0);
      await sim.saved('delete line 0 + move the ¼ cup oil to 0', before);
      verdict(sim);
    });

    test(
      'Case B (Run 050, Sonnet): [onion, ½ cup oil (pick 3 g), celery, '
      '¼ cup oil (pick 9 g)]; one save moves the ¼ cup line up and edits '
      'the ½ cup line to 1 cup — the untouched ¼ cup line keeps its 9 g',
      () async {
        final sim = sim0()
          ..start([
            [onion, _oilHalf, celery, _oilQuarter],
          ]);
        await sim.first();
        await sim.decide(1, g: 3);
        await sim.decide(3, g: 9);
        final before = sim.flat;
        sim
          ..moveTo(3, 0, 1)
          ..setText(2, oilOne);
        await sim.saved('move ¼ cup oil to 1 + amount-edit ½ → 1 cup', before);
        verdict(sim);
      },
    );

    test('swap (Run 050, Opus; four ops): [onion, ½ cup oil (skip), ¼ cup '
        'oil (pick 3 g)]; one save deletes the onion, edits ½ → ¾ and ¼ → '
        '1 cup, appends "Lemon wedges" — the skip and the pick stay on '
        'their own lines', () async {
      final was = _opsMax;
      _opsMax = 4;
      addTearDown(() => _opsMax = was);
      final sim = sim0()
        ..start([
          [onion, _oilHalf, _oilQuarter],
        ]);
      await sim.first();
      await sim.decide(1, skip: true);
      await sim.decide(2, g: 3);
      final before = sim.flat;
      sim
        ..deleteAt(0)
        ..setText(0, '¾ cup extra-virgin olive oil')
        ..setText(1, oilOne)
        ..insertAt(2, 'Lemon wedges');
      await sim.saved('delete onion + ½ → ¾ + ¼ → 1 cup + Lemon', before);
      verdict(sim);
    });

    test("S11 (O2 pin, the multi-op fuzz's seed 218): the traceback's "
        'diagonal-first tie-break — a save deletes the celery and the '
        '"2 teaspoons salt" and moves the last "Salt" (pick) up beside its '
        'twin: the pick stays on a "Salt" line', () async {
      // Three ops in one save, whatever ORACLE_OPS_MAX the run sets.
      final was = _opsMax;
      _opsMax = max(_opsMax, 3);
      addTearDown(() => _opsMax = was);
      final sim = sim0()
        ..start([
          [
            _sp, '8 cups chicken broth', _oilHalf, _oilHalf, celery, //
            '2 teaspoons salt', 'Salt', _oilHalf, 'Lemon wedges', 'Salt',
          ],
        ]);
      await sim.first();
      await sim.decide(1, skip: true);
      await sim.decide(4, skip: true);
      await sim.decide(9, g: 5);
      final before = sim.flat;
      sim
        ..deleteAt(4)
        ..moveTo(8, 0, 5)
        ..deleteAt(4);
      await sim.saved(
        'delete celery + move the last Salt to 5 + delete '
        '"2 teaspoons salt"',
        before,
      );
      verdict(sim);
    });

    test(
      "S12 (O2 pin, the multi-op fuzz's seed 633): the leftover pass's "
      "rank, a person's decision first — [¾ cup oil, Pepper, garlic, ¼ cup "
      'oil (pick), ¾ cup oil ×3 (skips), "2 teaspoons salt"]; a save swaps '
      'the first two and deletes one skipped copy: every skip survives',
      () async {
        const oil = '¾ cup extra-virgin olive oil';
        final sim = sim0()
          ..start([
            [
              oil, 'Pepper', '4 garlic cloves, peeled', _oilQuarter, //
              oil, oil, oil, '2 teaspoons salt',
            ],
          ]);
        await sim.first();
        await sim.decide(3, g: 5);
        for (final p in [4, 5, 6]) {
          await sim.decide(p, skip: true);
        }
        final before = sim.flat;
        sim
          ..swap(0, 0)
          ..deleteAt(6);
        await sim.saved('swap lines 0,1 + delete line 6', before);
        verdict(sim);
      },
    );

    test("S13 (O2 pin, the multi-op fuzz's seed 288): the leftover pass's "
        'exact text before the ingredient — ["2 teaspoons salt", ¾ cup oil '
        '(pick), Pecorino, salt (pick), ½ cup oil, salt, salt (pick)]; a '
        'save edits the ¾ cup oil to "2 teaspoons salt" and swaps the ½ cup '
        'oil down: the moved ½ cup oil keeps its own (engine) row', () async {
      const salt = '2 teaspoons salt';
      // Three ops in one save, whatever ORACLE_OPS_MAX the run sets.
      final was = _opsMax;
      _opsMax = max(_opsMax, 3);
      addTearDown(() => _opsMax = was);
      final sim = sim0()
        ..start([
          [
            salt, '¾ cup extra-virgin olive oil', //
            'Grated Pecorino Romano cheese', salt, _oilHalf, salt, salt,
          ],
        ]);
      await sim.first();
      for (final p in [1, 3, 6]) {
        await sim.decide(p, g: 5 + p);
      }
      final before = sim.flat;
      sim
        ..setText(1, salt)
        ..swap(0, 4);
      await sim.saved('¾ cup oil → "2 teaspoons salt" + swap 4,5', before);
      verdict(sim);
    });

    for (final skip in [true, false]) {
      test(
        'O2 (Run 051, v20 op model): [½ cup oil '
        '(${skip ? 'skip' : 'pick 5 g'}), onion, "2 teaspoons salt"]; one '
        'save moves the oil below '
        'the onion, edits it to ¾ cup and deletes the salt — the '
        'decision stays on the oil (a cross-ingredient substitution is a '
        'delete + an insert, two ops, never one)',
        () async {
          final was = _opsMax;
          _opsMax = max(_opsMax, 3);
          addTearDown(() => _opsMax = was);
          final sim = sim0()
            ..start([
              [_oilHalf, onion, '2 teaspoons salt'],
            ]);
          await sim.first();
          await sim.decide(0, skip: skip, g: 5);
          final before = sim.flat;
          sim
            ..moveTo(0, 0, 1)
            ..setText(1, '¾ cup extra-virgin olive oil')
            ..deleteAt(2);
          await sim.saved('move oil below onion + ½ → ¾ + delete salt', before);
          // The pick keeps its food; its typed 5 g was for ½ cup, so the
          // amount edit may re-weigh it (P~5: 'P:5' or 'P*').
          final got = [
            for (final r in sim.db.ingredientMatchesFor(sim.recipe.id))
              '${r.position}:${_tokenOf(r)}',
          ];
          expect(got, hasLength(2));
          expect(got.first, '0:-');
          expect(
            _tokMatch(skip ? 'S' : 'P~5', got.last.substring(2)),
            isTrue,
            reason: '$got',
          );
          verdict(sim);
        },
      );
    }

    test('S3 (Run 051): [½ cup oil, ½ cup oil (skip)]; one save deletes the '
        'first and appends "Pepper" — the skip stays on the surviving oil '
        '(a delete + an insert keeps it; the substitution reading drops it '
        'at the same cost)', () async {
      final sim = sim0()
        ..start([
          [_oilHalf, _oilHalf],
        ]);
      await sim.first();
      await sim.decide(1, skip: true);
      final before = sim.flat;
      sim
        ..deleteAt(0)
        ..insertAt(1, 'Pepper');
      await sim.saved('delete line 0 + append Pepper', before);
      final rows = sim.db.ingredientMatchesFor(sim.recipe.id);
      expect(
        [for (final r in rows) '${r.position}:${_tokenOf(r)}'],
        [
          '0:S',
          '1:-',
        ],
      );
      verdict(sim);
    });

    test('S4 (Run 051): ["2 teaspoons salt", ½ cup oil (skip), ½ cup oil]; '
        'save 1 inserts "Pepper" at 1, a person picks line 0 in the stale '
        'window (no row for Pepper yet), save 2 deletes the last oil (the '
        'undecided twin) — the skip stays', () async {
      final sim = sim0()
        ..start([
          ['2 teaspoons salt', _oilHalf, _oilHalf],
        ]);
      await sim.first();
      await sim.decide(1, skip: true);
      final before = sim.flat;
      sim.insertAt(1, 'Pepper');
      final ran = await sim.savedTwice(
        'insert Pepper at 1; pick line 0; delete line 3',
        before,
        () => sim.deleteAt(3),
        skip: false,
      );
      expect(ran, 'stale');
      expect(
        sim.db
            .ingredientMatchesFor(sim.recipe.id)
            .any((r) => r.status == 'skipped'),
        isTrue,
      );
      verdict(sim);
    });

    test('budget: 60 corpus lines shuffled whole with a quarter rewritten '
        'in one save (a synthesized edit, far past the oracle) — the search '
        'stops at pairingBudget with the best layout it found: never a row '
        'twice, a row only on a line of its text or ingredient, and more '
        'rows on a line of their text than the alignment it starts from', () {
      final rng = Random(7);
      final was = [for (var i = 0; i < 60; i++) pool[rng.nextInt(pool.length)]];
      final rows = [
        for (final (i, raw) in was.indexed)
          IngredientMatchRow(
            recipeId: 'r',
            position: i,
            raw: raw,
            fdcId: null,
            description: null,
            dataType: null,
            confidence: 0,
            grams: null,
            gramSource: null,
            status: i % 3 == 0 ? 'skipped' : 'auto',
            itemKey: lineKeyOf(_line(raw)),
          ),
      ];
      final now = [...was]..shuffle(rng);
      for (var k = 0; k < 15; k++) {
        now[rng.nextInt(60)] = pool[rng.nextInt(pool.length)];
      }
      final lines = [for (final raw in now) _line(raw)];
      int exact(List<IngredientMatchRow?> paired) => [
        for (final (at, row) in paired.indexed)
          if (row?.raw == lines[at].raw) at,
      ].length;
      final paired = pairRowsToLines(rows, lines);
      // It stopped AT the budget (D3: the magnitude is pinned below).
      expect(pairingExpansions, pairingBudget);
      final seed = pairRowsToLines(rows, lines, budget: 0);
      final taken = [for (final row in paired) ?row?.position];
      expect(taken.toSet(), hasLength(taken.length));
      for (final (at, row) in paired.indexed) {
        if (row != null && row.raw != lines[at].raw) {
          expect(row.itemKey, lineKeyOf(lines[at]));
          expect(row.itemKey, isNotEmpty);
        }
      }
      expect(exact(paired), greaterThan(exact(seed)));
    });

    test('budget (Run 051 S17): pairingBudget is 10,000 — the search runs '
        'synchronously in every compute, PUT and GET, ~36 ms at 60 lines '
        'when it stops there (1e6 measured 5 s: a raise freezes the '
        'isolate) — and a normal multi-edit save of 40 lines settles far '
        "below it (0901's 30 lines then 0405's, the list and its edits — a "
        'move, ½ → ¾ cup oil, a delete, in one save — synthesized, a '
        'stated exception)', () {
      expect(pairingBudget, 10000);
      final was = [
        ...nutritionLines(
          loadCorpusRecipe(
            '0901-caramel-espresso-yule-log-with-meringue-bracket-style-'
            'mushrooms-and-chocolate-cr.yaml',
          ),
        ),
        ...nutritionLines(loadCorpusRecipe(_acquacotta)),
      ].take(40).toList();
      expect(was[34].raw, _oilHalf);
      final rows = [
        for (final (i, line) in was.indexed)
          IngredientMatchRow(
            recipeId: 'r',
            position: i,
            raw: line.raw,
            fdcId: null,
            description: null,
            dataType: null,
            confidence: 0,
            grams: null,
            gramSource: null,
            status: i.isEven ? 'skipped' : 'auto',
            itemKey: lineKeyOf(line),
          ),
      ];
      final now = [...was]
        ..insert(30, was[3])
        ..removeAt(3)
        ..[34] = _line('¾ cup extra-virgin olive oil')
        ..removeAt(12);
      final paired = pairRowsToLines(rows, now);
      expect(pairingExpansions, lessThan(2500));
      expect(paired[28]?.position, 3);
      expect(paired[33]?.position, 34);
    });

    // pairRowsToLines alone, on stored rows ([_row]) — Run 051 D4/D6/D2.
    test('D4 (S21): over the budget, the in-order alignment is the fallback '
        '— 0405 with line 0 deleted at budget 0 keeps every other row on '
        'its line', () {
      final lines = nutritionLines(loadCorpusRecipe(_acquacotta));
      final rows = [for (final (i, l) in lines.indexed) _row(i, l.raw)];
      final paired = pairRowsToLines(rows, lines.sublist(1), budget: 0);
      expect(
        [for (final r in paired) r?.position],
        [
          for (var i = 1; i < lines.length; i++) i,
        ],
      );
    });

    test("D4 (S21): an empty key names no ingredient — 0028's \"(about ¾ "
        'cup)" (the corpus\'s one keyless line, skipped) edited to "(about '
        '1 cup)" (synthesized, a stated exception) carries nothing', () {
      final keyless = _corpusLine(
        '0028-hearty-minestrone.yaml',
        '(about ¾ cup)',
      );
      expect(lineKeyOf(keyless), isEmpty);
      final paired = pairRowsToLines(
        [_row(0, keyless.raw, status: 'skipped', key: '')],
        [_line('(about 1 cup)')],
      );
      expect(paired, [null]);
    });

    test('D6 (Opus critic 1 #2): a row keys from its own text too when '
        'its stored key names the same food by another wording (the same '
        'head noun, Run 052 F5) — a skipped "½ cup" oil row stored under '
        "'olive oil', a key an older matcher wrote (synthesized, a stated "
        'exception) still carries to its "¾ cup" amount edit', () {
      final paired = pairRowsToLines(
        [_row(0, _oilHalf, status: 'skipped', key: 'olive oil')],
        [
          _corpusLine(
            '0856-olive-oil-cake.yaml',
            '¾ cup extra-virgin olive oil',
          ),
        ],
      );
      expect(paired.single?.position, 0);
    });

    test('D2 (Run 051 S4, the gap fuzz): a position with no row is a line '
        "of unknown text — [½ cup oil (pick), (no row: a person's write "
        'left the ¼ cup line row-less), "Salt and pepper"]; a save deletes '
        'the ½ cup line: the pick goes, never onto the ¼ cup line', () {
      final paired = pairRowsToLines(
        [_row(0, _oilHalf, status: 'overridden'), _row(2, _sp)],
        [_line(_oilQuarter), _line(_sp)],
      );
      expect([for (final r in paired) r?.position], [null, 2]);
    });

    test("D2 (the gap fuzz's seed 60): a row carrying an amount edit's OLD "
        'text, and a row-less line after the last row, mislead a pairing '
        'from the rows alone — laid out on [¾ cup oil (pick), ½ cup oil, ½ '
        'cup oil (the ¾ cup row carried onto it, unrecomputed)], a save '
        'deletes line 0: with the laid-out texts the pick goes; from the '
        'rows alone it rides onto a ½ cup line (every layout keeps the '
        'texts: recipe_layout)', () {
      const oil = '¾ cup extra-virgin olive oil';
      final rows = [
        _row(0, oil, status: 'overridden'),
        _row(1, _oilHalf),
        _row(2, oil),
      ];
      final lines = [_line(_oilHalf), _line(_oilHalf)];
      final laid = pairRowsToLines(
        rows,
        lines,
        laidOut: [oil, _oilHalf, _oilHalf],
      );
      expect([for (final r in laid) r?.position], [1, 2]);
    });
  }, skip: skipIfNoCorpus);

  test(
    'fuzz: seeded saves of 1..ORACLE_OPS_MAX edits each (0405 whole, or '
    'dense lists of repeated '
    'and same-ingredient corpus lines) with random decisions, the stale '
    'window, a write mid-compute and FDC failing mid-compute',
    () async {
      final seeds = _envInt('ORACLE_SEEDS', 200);
      final base = _envInt('ORACLE_SEED_BASE', 0);
      final steps = _envInt('ORACLE_STEPS', 12);
      final show = _envInt('ORACLE_SHOW', 12);
      final one = int.tryParse(Platform.environment['ORACLE_SEED'] ?? '');
      // ORACLE_OUTAGE=1 adds RULE A's outage on the decided food (v27):
      // off by default, so every other seed replays as before.
      final outage = Platform.environment['ORACLE_OUTAGE'] == '1';
      final modeBag = [
        'plain',
        'plain',
        'stale',
        'mid',
        'fail',
        if (outage) ...['outage', 'outage'],
      ];
      final newQueryBag = [
        'plain',
        'stale',
        'mid',
        'mid',
        'fail',
        'fail',
        if (outage) ...['outage', 'outage'],
      ];
      final found = <(int, _Violation)>[];
      final ran = <String, int>{};
      final mixOf = <_Violation, String>{};
      var slowest = (seed: -1, ms: -1, explainMs: -1);
      for (final seed
          in one != null
              ? [one]
              : [
                  for (var s = 0; s < seeds; s++) base + s,
                  ..._regressionSeeds,
                ]) {
        final rng = Random(seed);
        final clock = Stopwatch()..start();
        _explainClock.reset();
        final (sim, close) = open();
        try {
          await startRandom(sim, rng);
          Future<void> decideSome(int most) => decideRandom(sim, rng, most);

          await decideSome(3);
          for (var s = 0; s < steps; s++) {
            // One save of 1..ORACLE_OPS_MAX edits.
            final before = sim.flat;
            final (names, kinds) = sim.randomEdits(rng, pool, variants);
            final mix = (kinds..sort()).join('+');
            // A compute asks FDC only for a query it never asked, so the
            // edits that bring one carry the interleavings more often.
            final bag =
                kinds.any((k) => k == 'insert' || k == 'ingredient-edit')
                ? newQueryBag
                : modeBag;
            final seen = sim.violations.length;
            final mode = await sim.saved(
              'seed $seed step $s: ${names.join(' + ')}',
              before,
              mode: bag[rng.nextInt(bag.length)],
              at: rng.nextInt(1 << 20),
              skip: rng.nextBool(),
              failAfter: rng.nextInt(2),
            );
            ran['$mix/$mode'] = (ran['$mix/$mode'] ?? 0) + 1;
            for (final v in sim.violations.skip(seen)) {
              mixOf[v] = '$mix/$mode';
            }
            await decideSome(2);
          }
        } finally {
          close();
        }
        found.addAll([for (final v in sim.violations) (seed, v)]);
        final explainMs = _explainClock.elapsedMilliseconds;
        if (explainMs > slowest.explainMs) {
          slowest = (
            seed: seed,
            ms: clock.elapsedMilliseconds,
            explainMs: explainMs,
          );
        }
      }
      final byKind = <String, int>{};
      final byOp = <String, int>{};
      for (final (_, v) in found) {
        for (final k in v.kinds) {
          byKind[k] = (byKind[k] ?? 0) + 1;
        }
        final tag = mixOf[v] ?? 'first compute';
        byOp[tag] = (byOp[tag] ?? 0) + 1;
      }
      // One op: each kind/mode; several: saves by op count/mode.
      final runsBy = <String, int>{};
      for (final MapEntry(key: k, value: c) in ran.entries) {
        final tag = _opsMax == 1
            ? k
            : '${k.split('/').first.split('+').length} op(s)/'
                  '${k.split('/').last}';
        runsBy[tag] = (runsBy[tag] ?? 0) + c;
      }
      final runs = [
        for (final k in runsBy.keys.toList()..sort()) '$k=${runsBy[k]}',
      ];
      final hitSeeds = {for (final (s, _) in found) s};
      print(
        'pairing oracle fuzz: ${one ?? seeds} seed(s) x $steps saves of '
        '1..$_opsMax edit(s); saves run: ${runs.join(' ')}\n'
        'violations: ${found.length} in ${hitSeeds.length} seed(s); '
        'by kind $byKind; by edit mix/mode $byOp\n'
        'slowest enumeration: seed ${slowest.seed}, '
        '${slowest.explainMs} ms of ${slowest.ms} ms',
      );
      for (final (seed, v) in found.take(show)) {
        print('--- seed $seed (rerun: ORACLE_SEED=$seed)\n${v.text}');
      }
      expect(
        found.length,
        0,
        reason: 'invariant breaks; the first $show printed above',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: skipIfNoCorpus,
  );

  test(
    'fuzz (gaps): two saves with the rows left incomplete between them — '
    "a person's write in the stale window, a save at the compute's first "
    'provider call, a failed compute — checked against the expectation '
    'chained over both saves',
    () async {
      // Every layout keeps the texts of the lines it laid the rows on
      // (`recipe_layout`) and the pairing reads them (`laidOut`), so the
      // rows need not show a row-less line after the last row or a row
      // still carrying an amount edit's old text. A sweep is
      // ORACLE_GAP_SEEDS=N; the default runs 60 fresh seeds and the
      // regression seeds.
      final seeds = _envInt('ORACLE_GAP_SEEDS', 60);
      final base = _envInt('ORACLE_SEED_BASE', 0);
      final steps = _envInt('ORACLE_STEPS', 12);
      final show = _envInt('ORACLE_SHOW', 12);
      final one = int.tryParse(Platform.environment['ORACLE_SEED'] ?? '');
      const gapBag = ['stale', 'stale', 'mid', 'mid', 'fail'];
      final found = <(int, _Violation)>[];
      final ran = <String, int>{};
      for (final seed
          in one != null
              ? [one]
              : [
                  for (var s = 0; s < seeds; s++) base + s,
                  ..._gapRegressionSeeds,
                ]) {
        final rng = Random(seed);
        final (sim, close) = open();
        try {
          await startRandom(sim, rng);
          await decideRandom(sim, rng, 3);
          for (var s = 0; s < steps; s++) {
            final before = sim.flat;
            final (first, _) = sim.randomEdits(rng, pool, variants);
            var second = const <String>[];
            final seen = sim.violations.length;
            final gap = await sim.savedTwice(
              'seed $seed step $s: ${first.join(' + ')}',
              before,
              () => (second, _) = sim.randomEdits(rng, pool, variants),
              gap: gapBag[rng.nextInt(gapBag.length)],
              at: rng.nextInt(1 << 20),
              skip: rng.nextBool(),
              failAfter: rng.nextInt(2),
            );
            for (var k = seen; k < sim.violations.length; k++) {
              final v = sim.violations[k];
              sim.violations[k] = (
                kinds: v.kinds,
                text: '${v.text}  then: ${second.join(' + ')}\n',
              );
            }
            ran[gap] = (ran[gap] ?? 0) + 1;
            await decideRandom(sim, rng, 2);
          }
        } finally {
          close();
        }
        found.addAll([for (final v in sim.violations) (seed, v)]);
      }
      final hitSeeds = {for (final (s, _) in found) s};
      print(
        'pairing oracle gaps: ${one ?? seeds} seed(s) x $steps double saves; '
        'gaps run: $ran\nviolations: ${found.length} in ${hitSeeds.length} '
        'seed(s): ${hitSeeds.toList()..sort()}',
      );
      for (final (seed, v) in found.take(show)) {
        print('--- seed $seed (rerun: ORACLE_SEED=$seed)\n${v.text}');
      }
      expect(found.length, 0, reason: 'invariant breaks; printed above');
    },
    timeout: const Timeout(Duration(minutes: 60)),
    skip: skipIfNoCorpus,
  );
}
