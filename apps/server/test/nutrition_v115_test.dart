// The v115 pins (batch M102, prep52 P4: "unbleached all-purpose flour" on
// the unbleached record; matcherVersion 101). `unbleached` stays a stop
// word (key, query, cache and density untouched); [namesUnbleached] — the
// whole word on the raw line — is passed to [rankCandidates] as the extra
// ranking token 'unbleached' at the three call sites, as the
// [namesCannedLegume] / [impliesSkinOn] flags are. On the recorded
// 'all-purpose flour' answer (snapshot 33's cache row, the fixtures' copy)
// the token lifts Foundation 789951 "Flour, wheat, all-purpose, enriched,
// unbleached" (358 kcal, carbohydrate 73.2) over 789890 "…, enriched,
// bleached" (366, carbohydrate 77.3): 0.950000 each before (FDC's order
// picked 789890), 0.983333 vs 0.687500 now.
// Corpus-backed groups skip without SALT_CORPUS_DIR; every corpus read sits
// inside a test body. 789951's DETAIL is a fixture copied verbatim from
// snapshot 33's fdc_food_cache.
//
// Hand derivations (kcal per 100 g in the engine's order, nutrient 208:
// 789951 = 358, 789890 = 366):
//   weight  quick-cheese-bread|1 "3 cups (15 ounces)": 15 × 28.3495 =
//           425.24 g × 3.58 = 1,522.37 (was × 3.66 = 1,556.39).
//   density daube-provencal|10 "⅓ cup": ⅓ × 5 oz a cup = 47.25 g × 3.58 =
//           169.15 (was 172.93).
//   section classic-roast-turkey's Giblet Pan Gravy |8 "¼ cup": 35.44 g ×
//           3.58 = 126.86 (was 129.70).
//   coat    chicken-fried-steaks|0: B = 8.79 × 850.485 / 100 = 74.758 g of
//           carbohydrate, ÷ 73.2 % = 102.13 g (was ÷ 77.3 % = 96.71), ×
//           3.58 = 365.63 (was 353.96); crispy-fried-chicken|8: B = 8.79 ×
//           1,266.89 / 100 = 111.360, ÷ 73.2 % = 152.13 g (was 144.06), ×
//           3.58 = 544.63 (was 527.26).
//   0 g     deep-dish-apple-pie|1 "Unbleached all-purpose flour, for the
//           work surface": 0.00 g, 0.00 kcal, its record 789951.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: {...pendingSearches});

const _unbleached = 789951;
const _bleached = 789890;
const _unbleachedName = 'Flour, wheat, all-purpose, enriched, unbleached';
const _bleachedName = 'Flour, wheat, all-purpose, enriched, bleached';

const _quickBread = '0787-quick-cheese-bread.yaml';
const _daube = '0456-daube-provencal.yaml';
const _steaks = '0304-chicken-fried-steaks.yaml';
const _crispy = '0148-crispy-fried-chicken.yaml';
const _deepDish = '0978-deep-dish-apple-pie.yaml';
const _roastTurkey = '0154-classic-roast-turkey.yaml';
const _gumbo = '0028-chicken-and-sausage-gumbo.yaml';

/// STATED synthesized (on all 180 corpus lines naming the word, 172 with a
/// row, the YAML item keeps it — measured — so no corpus line tells the raw
/// line from the item): 0028 |0's real "1 cup (5 ounces) all-purpose flour"
/// with the comma tail of 0107 |4's real "…, preferably bleached" turned to
/// `unbleached`. Its parsed item is 'all-purpose flour' — the item drops the
/// word the raw line names — so it tells a reader of the RAW line (shipped)
/// from one of the item.
const _tailRaw = '1 cup (5 ounces) all-purpose flour, preferably unbleached';

/// The recorded 'all-purpose flour' answer (fixtures: snapshot 33's row).
List<FdcCandidate> _flourAnswer() => _answerOf('all-purpose flour');

/// The recorded answer of [query] (the fixtures' copy of the cache row).
List<FdcCandidate> _answerOf(String query) {
  final searches =
      jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final c in searches[query] as List<dynamic>)
      FdcCandidate.fromJson(c as Map<String, dynamic>),
  ];
}

IngredientLine _lineOf(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
}

/// [file] with only its line [position] (its real steps kept): a weight or
/// density row reads the line alone.
Recipe _only(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

String _g(double? x) => x?.toStringAsFixed(2) ?? '-';

String _kcal(SaltDatabase db, IngredientMatchRow row) =>
    row.fdcId == null || row.grams == null
    ? _g(row.grams)
    : _g(kcalPer100g(knownFood(db, row.fdcId!)!) * row.grams! / 100);

/// Every stored column the rule writes, as one string.
String _stored(SaltDatabase db, IngredientMatchRow row) => [
  row.fdcId,
  row.description,
  row.status,
  row.hold,
  row.gramSource,
  row.confidence.toStringAsFixed(6),
  _g(row.grams),
  _kcal(db, row),
].join(' | ');

void main() {
  reader();
  ranking();
  callSites();
  group('v115 (M102: unbleached flour)', skip: skipIfNoCorpus, () {
    moved();
    unmoved();
    person();
    sharedKey();
  });
}

/// [namesUnbleached]: the WHOLE word, in any case, on the raw line.
void reader() {
  test('namesUnbleached reads the whole word `unbleached`, in any case', () {
    // Real corpus lines (0787 |1, 0978 |1, 0028 |0, 0107 |4, 0784 |0, 0886
    // |3, 0382 |0).
    for (final (raw, named) in [
      ('3 cups (15 ounces) unbleached all-purpose flour', true),
      ('Unbleached all-purpose flour, for the work surface', true),
      ('1 cup (5 ounces) all-purpose flour', false),
      ('½ cup all-purpose flour, preferably bleached', false),
      ('3 cups (15 ounces) King Arthur all-purpose flour', false),
      ('2¼ cups (9 ounces) bleached cake flour', false),
      ('1⅓ cups (7⅓ ounces) bread flour', false),
      // STATED synthesized (no corpus line spells them): a hyphenated
      // "un-bleached" and the word run into the next one are no whole
      // `unbleached` (the regex's two word boundaries).
      ('1 cup un-bleached all-purpose flour', false),
      ('1 cup unbleachedflour', false),
      ('1 cup ununbleached flour', false),
    ]) {
      expect(namesUnbleached(raw), named, reason: raw);
    }
  });
}

/// [rankCandidates] on the recorded answer, with and without the token.
void ranking() {
  test("the 'all-purpose flour' answer ranks 789951 first with the "
      'unbleached token (0.983333; 789890 0.687500), and 789890 first '
      'without it (a 0.950000 tie, FDC order)', () {
    String top(List<RankedCandidate> r, int n) => [
      for (final c in r.take(n))
        '${c.candidate.fdcId} ${c.confidence.toStringAsFixed(6)}',
    ].join(', ');
    final answer = _flourAnswer();
    expect(
      top(rankCandidates('all-purpose flour', answer, unbleached: true), 4),
      '789951 0.983333, 790018 0.983333, 168936 0.884286, 789890 0.687500',
    );
    expect(
      top(rankCandidates('all-purpose flour', answer), 2),
      '789890 0.950000, 789951 0.950000',
    );
  });

  // The owner gate (the RULE narrowed: the token only on a query naming
  // all-purpose flour passed every pin; then, hand-edit round 1, the token
  // only on a query naming flour did; then, round 2, the token only on an
  // answer whose top stands at or above the 0.5 gate). The token is the
  // QUERY's, whatever the food — STATED: no corpus ingredient line names
  // `unbleached` beside another food (all 180 are "unbleached all-purpose
  // flour"; the word beside cake flour is in prose notes only), so these
  // read the recorded answers under the flag directly. Bread flour holds an
  // unbleached record and moves to it; an answer holding none is docked —
  // cake and whole-wheat flour and, off the flours, granulated sugar stay
  // above the 0.5 gate, panko bread crumbs fall under it, frozen phyllo was
  // under it already.
  test('the token on another food: the bread flour answer ranks its '
      'unbleached record 790146 first (0.940000; 168913 0.900000 without); '
      'an answer with no such record is docked — cake flour 169723 0.533333 '
      '(0.850000), whole-wheat flour 790085 0.757500 (1.000000), granulated '
      'sugar 746784 0.733333 (1.000000), panko bread crumbs 174928 0.455000 '
      '(0.563333), under the gate, frozen phyllo 172791 0.366667 (0.475000), '
      'under it before', () {
    String top(String query, {required bool unbleached}) {
      final c = rankCandidates(
        query,
        _answerOf(query),
        unbleached: unbleached,
      ).first;
      return '${c.candidate.fdcId} ${c.confidence.toStringAsFixed(6)}';
    }

    expect(top('bread flour', unbleached: true), '790146 0.940000');
    expect(top('bread flour', unbleached: false), '168913 0.900000');
    expect(top('cake flour', unbleached: true), '169723 0.533333');
    expect(top('cake flour', unbleached: false), '169723 0.850000');
    expect(top('whole-wheat flour', unbleached: true), '790085 0.757500');
    expect(top('whole-wheat flour', unbleached: false), '790085 1.000000');
    expect(top('granulated sugar', unbleached: true), '746784 0.733333');
    expect(top('granulated sugar', unbleached: false), '746784 1.000000');
    expect(top('panko bread crumbs', unbleached: true), '174928 0.455000');
    expect(top('panko bread crumbs', unbleached: false), '174928 0.563333');
    expect(top('frozen phyllo', unbleached: true), '172791 0.366667');
    expect(top('frozen phyllo', unbleached: false), '172791 0.475000');
  });

  // The owner gate (hand-edit round 2): what the flag IS, on every recorded
  // answer — the whole ranking equals the ranking of the query with the
  // word in it, so a token made conditional on the query, the answer or a
  // confidence differs wherever the condition changes a recorded answer's
  // ranking (STATED limit: a condition true of every recorded answer, or a
  // second spelling where no candidate holds the word, passes — an
  // unmatched token docks the same). ONE recorded answer is apart, measured
  // and pinned as it is: 'half-and-half' (the flag 167814 0.070000, the
  // query naming the word 2705594 0.465000 — the query's own text is read
  // for more than its token set there).
  test('the flag ranks every recorded answer as the query naming the word '
      'would (the whole ranking; half-and-half apart)', () {
    final searches =
        jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
            as Map<String, dynamic>;
    String all(List<RankedCandidate> ranked) => [
      for (final c in ranked)
        '${c.candidate.fdcId} ${c.confidence.toStringAsFixed(6)}',
    ].join(', ');
    final apart = <String>[];
    for (final query in searches.keys) {
      final answer = [
        for (final c in searches[query] as List<dynamic>)
          FdcCandidate.fromJson(c as Map<String, dynamic>),
      ];
      final flagged = all(rankCandidates(query, answer, unbleached: true));
      if (flagged != all(rankCandidates('$query unbleached', answer))) {
        apart.add('$query: ${flagged.split(', ').first}');
      }
    }
    // 1,105 answers at v115; the fixtures only grow.
    expect(searches.length, greaterThanOrEqualTo(1105));
    expect(apart, ['half-and-half: 167814 0.070000']);
    expect(
      all(
        rankCandidates(
          'half-and-half unbleached',
          _answerOf('half-and-half'),
        ),
      ).split(', ').first,
      '2705594 0.465000',
    );
  });
}

/// Each of the three call sites passes the flag (the GREP pin), and the two
/// no stored row reaches read it — by a direct call.
void callSites() {
  test('engine.dart: every rankCandidates call that passes the canned flag '
      'passes the unbleached flag (3 and 3)', () {
    final src = File('lib/src/nutrition/engine.dart').readAsStringSync();
    expect(
      RegExp(r'canned: namesCannedLegume\(').allMatches(src),
      hasLength(3),
    );
    expect(
      RegExp(r'unbleached: namesUnbleached\(').allMatches(src),
      hasLength(3),
    );
    // Each in the same call: the flag's line directly after `skinless:`.
    expect(
      RegExp(
        r'skinless: removesSkin\((\w+)\.raw\),\n\s*unbleached: namesUnbleached\(\1\.raw\),',
      ).allMatches(src),
      hasLength(3),
    );
  });

  // Site 2 (`_rankedCached`, the carried-decision and lean-only reads) and
  // site 3 (`candidatesForLine`, the matches GET's candidates): measured on
  // the replay, neither moves a stored row (sites 2 and 3 added after site
  // 1: every TSV cmp-identical) — a flour row takes none of the moves the
  // site-2 ranking feeds, and the GET's list is no stored row. Pinned by a
  // direct call on the recorded answer (corpusless; the lines are real
  // corpus lines, 0787 |1 and 0028 |0).
  test('site 2 (_rankedCached) and site 3 (candidatesForLine, cache only) '
      'rank 789951 first for an unbleached line and 789890 for an unnamed '
      'one', () async {
    final (db, _) = a.pathDb();
    final searches =
        jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
            as Map<String, dynamic>;
    db.fdcSearchCachePut(
      'all-purpose flour',
      jsonEncode(searches['all-purpose flour']),
    );
    for (final (raw, first) in [
      ('3 cups (15 ounces) unbleached all-purpose flour', _unbleached),
      ('1 cup (5 ounces) all-purpose flour', _bleached),
      (_tailRaw, _unbleached),
    ]) {
      final line = _lineOf(raw);
      expect(
        rankedCachedForTest(db, line).first.candidate.fdcId,
        first,
        reason: 'site 2: $raw',
      );
      expect(
        (await candidatesForLine(
          db,
          _fx,
          line,
          cacheOnly: true,
        )).first.candidate.fdcId,
        first,
        reason: 'site 3: $raw',
      );
    }
  });
}

/// [r] stored and computed, its section children first (each under its own
/// key, as the per-recipe job does); returns the stored recipe.
Future<Recipe> _compute(SaltDatabase db, Recipe r) async {
  db
    ..upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub')
    ..upsertRecipe(r, sourceSlug: 'atk-tv-2023', contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, _fx, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// THE MOVED ROWS, one of each gram source and the 0 g capitalised line
/// (file, position, whole recipe?, every stored column, basis) — the v115
/// replay's rows on snapshot 33, each derived by hand in the header.
const _moved = [
  (
    _quickBread,
    1,
    false,
    '789951 | $_unbleachedName | auto | null | weight | 0.983333 | 425.24 | 1522.37',
    'from 15 ounce',
  ),
  (
    _daube,
    10,
    false,
    '789951 | $_unbleachedName | auto | null | density | 0.983333 | 47.25 | 169.15',
    '1/3 cup ≈ 79 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
  ),
  (
    _steaks,
    0,
    true,
    '789951 | $_unbleachedName | auto | null | discarded | 0.983333 | 102.13 | 365.63',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  ),
  (
    _crispy,
    8,
    true,
    '789951 | $_unbleachedName | auto | null | discarded | 0.983333 | 152.13 | 544.63',
    "discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw chicken — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak (no record for chicken; read as Beef, steak, country fried); the dredge's excess not counted)",
  ),
  (
    _deepDish,
    1,
    false,
    '789951 | $_unbleachedName | auto | null | unmeasured | 0.983333 | 0.00 | 0.00',
    'no amount on the line — counted as 0 g',
  ),
];

void moved() {
  test('the moved rows: every stored column and the basis, as the v115 '
      'replay stores them', () async {
    for (final (file, position, whole, stored, basis) in _moved) {
      final reason = '$file|$position';
      final (db, _) = a.pathDb();
      final r = await _compute(
        db,
        whole ? loadCorpusRecipe(file) : _only(file, position),
      );
      final at = whole ? position : 0;
      final row = d.rowOf(db, r, at);
      expect(_stored(db, row), stored, reason: reason);
      expect(
        gramBasisFor(db, nutritionLines(r)[at], row, recipe: r),
        basis,
        reason: reason,
      );
    }
  });

  test("a section row: classic-roast-turkey's Giblet Pan Gravy |8 ¼ cup on "
      '789951, 35.44 g density, 126.86 kcal; its host |8 routed line '
      '1,571.90 g at the section total', () async {
    final (db, _) = a.pathDb();
    final host = await _compute(db, loadCorpusRecipe(_roastTurkey));
    final key =
        sectionChildKeysOf(
          db,
          host,
          ResolverMemo(db),
        ).singleWhere(
          (k) => nutritionRecipeOf(
            db,
            k,
          )!.recipe.title.contains('Giblet Pan Gravy'),
        );
    final gravy = nutritionRecipeOf(db, key)!.recipe;
    final row = d.rowOf(db, gravy, 8);
    expect(row.raw, '¼ cup unbleached all-purpose flour');
    expect(
      _stored(db, row),
      '789951 | $_unbleachedName | auto | null | density | 0.983333 | 35.44 | 126.86',
    );
    expect(
      gramBasisFor(db, nutritionLines(gravy)[8], row, recipe: gravy),
      '1/4 cup ≈ 59 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
    );
    expect(_g(d.rowOf(db, host, 8).grams), '1571.90');
  });

  test('site 1 reads the RAW line: the synthesized "…, preferably '
      'unbleached" (item \'all-purpose flour\') lands 789951, 141.75 g weight, '
      '507.46 kcal', () async {
    final line = _lineOf(_tailRaw);
    expect(line.item, 'all-purpose flour');
    final (db, _) = a.pathDb();
    final r = await _compute(
      db,
      loadCorpusRecipe(_gumbo).copyWith(
        ingredients: [
          IngredientGroup(items: [line]),
        ],
      ),
    );
    // 5 oz = 141.75 g × 3.58 = 507.46 (on 789890: × 3.66 = 518.80).
    expect(
      _stored(db, d.rowOf(db, r, 0)),
      '789951 | $_unbleachedName | auto | null | weight | 0.983333 | 141.75 | 507.46',
    );
  });
}

/// THE CLASS'S NEGATIVES: no `unbleached` on the line — its v114 row.
void unmoved() {
  // The King Arthur rows (key 'king arthur all-purpose flour') and the
  // bleached cake flour row (key 'bleached cake flour'), both on 789890, are
  // byte-identical on the replay (docs/API.md "Matcher v115", R4); the
  // fixtures hold no search answer for either key.
  test('the unnamed, bleached and bread flour rows keep their v114 rows', () async {
    for (final (file, position, stored) in [
      (
        _gumbo,
        0,
        '789890 | $_bleachedName | auto | null | weight | 0.950000 | 141.75 | 518.80',
      ),
      (
        '0107-creole-style-shrimp-and-sausage-gumbo.yaml',
        4,
        '789890 | $_bleachedName | auto | null | density | 0.950000 | 70.87 | 259.40',
      ),
      (
        '0382-one-hour-pizza.yaml',
        0,
        '168913 | Wheat flours, bread, unenriched | auto | null | weight | 0.900000 | 207.90 | 750.51',
      ),
    ]) {
      final (db, _) = a.pathDb();
      final r = await _compute(db, _only(file, position));
      expect(_stored(db, d.rowOf(db, r, 0)), stored, reason: '$file|$position');
    }
  });
}

/// Every row and the totals of [r], as compared across paths.
String _state(SaltDatabase db, Recipe r) {
  final rows = db.ingredientMatchesFor(r.id)
    ..sort((x, y) => x.position.compareTo(y.position));
  final t = db.nutritionFor(r.id)?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final m in rows)
      [
        m.position,
        m.fdcId,
        _g(m.grams),
        m.gramSource,
        m.hold,
        m.status,
      ].join(':'),
    'E=${_g(e)}',
  ].join(' ');
}

/// R5: a person's verbs on one moved row of each gram source (weight,
/// density, a coat) through the real PUT — stored == recomputeTotals == a
/// full compute, the GET's grams and hold == stored, and the GET's basis
/// beside the stored row (each pinned: [_personRows]).
void person() {
  test('a person decision on a moved row (confirm, typed grams, skip and '
      'back, pick its own record 789951, pick 789890): stored == recompute '
      '== compute == the GET, the basis agreeing', () async {
    final got = <String, String>{};
    for (final (file, position, whole) in [
      (_quickBread, 1, false),
      (_daube, 10, false),
      (_steaks, 0, true),
    ]) {
      for (final (verb, puts) in <(String, List<Map<String, Object?>>)>[
        (
          'confirm',
          [
            {'confirmed': true},
          ],
        ),
        (
          'typed',
          [
            {'grams': 77},
          ],
        ),
        (
          'skip-back',
          [
            {'skipped': true},
            {'skipped': false},
          ],
        ),
        (
          'pick-own',
          [
            {'fdc_id': _unbleached},
          ],
        ),
        (
          'pick-bleached',
          [
            {'fdc_id': _bleached},
          ],
        ),
      ]) {
        final reason = '$file|$position $verb';
        final (db, _) = a.pathDb();
        final r = await _compute(
          db,
          whole ? loadCorpusRecipe(file) : _only(file, position),
        );
        final at = whole ? position : 0;
        final raw = nutritionLines(r)[at].raw;
        for (final body in puts) {
          await applyMatchOverride(db, _fx, r, at, {'raw': raw, ...body});
        }
        final s1 = _state(db, r);
        final row = d.rowOf(db, r, at);
        final items = (await matchesBody(db, _fx, r))['items']! as List;
        final m = (items[at] as Map)['match'] as Map;
        expect(
          (_g((m['grams'] as num?)?.toDouble()), m['hold']),
          (_g(row.grams), row.hold),
          reason: '$reason GET',
        );
        recomputeTotals(db, r);
        expect(_state(db, r), s1, reason: '$reason recompute');
        await matchAndCompute(db, _fx, r);
        expect(_state(db, r), s1, reason: '$reason compute');
        got[reason] =
            '${row.status} ${row.fdcId} ${_g(row.grams)} ${row.gramSource} ${row.hold} ${_kcal(db, row)} | ${m['gram_basis']}';
      }
    }
    expect(got, _personRows);
  });
}

/// R6, THE SHARED DECISION KEY: an unbleached and an unnamed line keep ONE
/// key, 'all-purpose flour', and now land two records. A decision on one
/// variety is the key's decision ([applyDecisionToOthers] reaches a sibling
/// on ANOTHER food at any score; the next compute carries the key's
/// decision to every line of the key). Measured on the base 196a95f with
/// the same PUTs on its own replayed snapshot-33 database: a confirm (or a
/// pick of 789890) with apply_to_all on either variety reached 0 lines —
/// both sat on 789890 — and a carried confirm moved none. On v115 each
/// re-points the OTHER variety (the replay-wide figures in docs/API.md
/// "Matcher v115", R6). Pinned here on 0787 |1 and 0028 |0 alone.
/// (Resolved 2026-11-17, matcher v116, the owner's "same kind only": the
/// decision key carries `unbleached`; the pins below are RE-PINNED to 0
/// cross-kind rows, and the same kind still reaches.)
void sharedKey() {
  // RE-PIN (M103 batch, v116, the owner's "same kind only"): the decision
  // key carries the kind — 0787 |1 keys 'unbleached all-purpose flour',
  // 0028 |0 'all-purpose flour' — so each cross-kind Confirm below reaches
  // 0 rows and the target keeps its own record (v115: re-pointed). 0787 |1
  // 425.24 g × 3.58 = 1,522.37; 0028 |0 141.75 g × 3.66 = 518.80.
  for (final (name, from, to, other, record, grams, kcal) in [
    (
      'a Confirm + apply_to_all on the unnamed 0028 |0 leaves the unbleached '
          '0787 |1 on 789951 (v115: moved it to 789890)',
      (_gumbo, 0),
      (_quickBread, 1),
      _quickBread,
      _unbleached,
      '425.24',
      '1522.37',
    ),
    (
      'a Confirm + apply_to_all on the unbleached 0787 |1 leaves the unnamed '
          '0028 |0 on 789890 (v115: moved it to 789951)',
      (_quickBread, 1),
      (_gumbo, 0),
      _gumbo,
      _bleached,
      '141.75',
      '518.80',
    ),
  ]) {
    test(name, () async {
      final (db, _) = a.pathDb();
      final decided = await _compute(db, _only(from.$1, from.$2));
      final target = await _compute(db, _only(to.$1, to.$2));
      expect(d.rowOf(db, target, 0).fdcId, record, reason: other);
      final reach = decisionReach(
        db,
        lineKeyOf(nutritionLines(decided).single),
        excluding: (recipeId: decided.id, position: 0),
        fdcId: d.rowOf(db, decided, 0).fdcId,
      );
      expect([for (final r in reach) r.recipeId], isEmpty);
      final applied = await applyMatchOverride(db, _fx, decided, 0, {
        'raw': nutritionLines(decided).single.raw,
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied?.lines, 0);
      final row = d.rowOf(db, target, 0);
      expect(
        (row.fdcId, row.status, _g(row.grams), _kcal(db, row)),
        (record, 'auto', grams, kcal),
      );
    });
  }

  test('the same kind still reaches: a pick of 789890 + apply_to_all on the '
      'unbleached 0787 |1 moves the unbleached daube |10 to it, never the '
      'unnamed 0028 |0', () async {
    final (db, _) = a.pathDb();
    final bread = await _compute(db, _only(_quickBread, 1));
    final daube = await _compute(db, _only(_daube, 10));
    final gumbo = await _compute(db, _only(_gumbo, 0));
    final applied = await applyMatchOverride(db, _fx, bread, 0, {
      'raw': nutritionLines(bread).single.raw,
      'fdc_id': _bleached,
      'apply_to_all': true,
    });
    expect(applied?.lines, 1);
    final row = d.rowOf(db, daube, 0);
    // 47.25 g × 3.66 = 172.93.
    expect(
      (row.fdcId, row.status, _g(row.grams), _kcal(db, row)),
      (_bleached, 'auto', '47.25', '172.93'),
    );
    expect(d.rowOf(db, gumbo, 0).confidence, 0.95);
  });

  test('a Confirm WITHOUT apply_to_all on the unnamed 0028 |0 is the plain '
      "kind's decision only: the next compute of 0787 keeps its unbleached "
      '|1 on 789951 (v115: carried 789890 to it)', () async {
    final (db, _) = a.pathDb();
    final gumbo = await _compute(db, _only(_gumbo, 0));
    final bread = await _compute(db, _only(_quickBread, 1));
    expect(d.rowOf(db, bread, 0).fdcId, _unbleached);
    await applyMatchOverride(db, _fx, gumbo, 0, {
      'raw': nutritionLines(gumbo).single.raw,
      'confirmed': true,
    });
    // RE-PIN (M103 batch, v116): two keys; the unbleached one undecided.
    expect(db.decisionFor('all-purpose flour')?.fdcId, _bleached);
    expect(db.decisionFor('unbleached all-purpose flour'), isNull);
    expect(d.rowOf(db, bread, 0).fdcId, _unbleached, reason: 'the PUT alone');
    await matchAndCompute(db, _fx, bread);
    final row = d.rowOf(db, bread, 0);
    expect(
      (row.fdcId, row.status, _g(row.grams), _kcal(db, row)),
      (_unbleached, 'auto', '425.24', '1522.37'),
    );
  });
}

/// The person rows ([person]): status, record, grams, source, hold, kcal,
/// and the GET's basis — measured on the v115 tree. Typed grams count 77 g
/// on 789951 (77 × 3.58 = 275.66); a pick on the coat row keeps its
/// derived `coating` hold with no grams (the ruled pick site, v23 Run 053
/// O8 — nutrition_v23_rules_test G6), on either record.
const Map<String, String> _personRows = {
  '0787-quick-cheese-bread.yaml|1 confirm':
      'confirmed 789951 425.24 weight null 1522.37 | from 15 ounce',
  '0787-quick-cheese-bread.yaml|1 typed':
      'overridden 789951 77.00 override null 275.66 | entered by hand',
  '0787-quick-cheese-bread.yaml|1 skip-back':
      'auto 789951 425.24 weight null 1522.37 | from 15 ounce',
  '0787-quick-cheese-bread.yaml|1 pick-own':
      'overridden 789951 425.24 weight null 1522.37 | from 15 ounce',
  '0787-quick-cheese-bread.yaml|1 pick-bleached':
      'overridden 789890 425.24 weight null 1556.39 | from 15 ounce',
  '0456-daube-provencal.yaml|10 confirm':
      'confirmed 789951 47.25 density null 169.15 | 1/3 cup ≈ 79 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
  '0456-daube-provencal.yaml|10 typed':
      'overridden 789951 77.00 override null 275.66 | entered by hand',
  '0456-daube-provencal.yaml|10 skip-back':
      'auto 789951 47.25 density null 169.15 | 1/3 cup ≈ 79 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
  '0456-daube-provencal.yaml|10 pick-own':
      'overridden 789951 47.25 density null 169.15 | 1/3 cup ≈ 79 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
  '0456-daube-provencal.yaml|10 pick-bleached':
      'overridden 789890 47.25 density null 172.93 | 1/3 cup ≈ 79 mL · approximate (ATK: 1 cup all-purpose flour = 5 ounces)',
  '0304-chicken-fried-steaks.yaml|0 confirm':
      "confirmed 789951 102.13 discarded null 365.63 | discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  '0304-chicken-fried-steaks.yaml|0 typed':
      'overridden 789951 77.00 override null 275.66 | entered by hand',
  '0304-chicken-fried-steaks.yaml|0 skip-back':
      "auto 789951 102.13 discarded null 365.63 | discarded in cooking — only the coat on the food counted · approximation (coat: 8.79 g carbohydrate per 100 g of the raw beef — USDA FNDDS 2705842 recipe: 20 g breading per 90.99 g raw beef steak; the dredge's excess not counted)",
  '0304-chicken-fried-steaks.yaml|0 pick-own':
      'overridden 789951 - null coating - | null',
  '0304-chicken-fried-steaks.yaml|0 pick-bleached':
      'overridden 789890 - null coating - | null',
};
