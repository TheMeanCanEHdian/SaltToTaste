// The v116 pins (batch M103, the prep52 key split; matcherVersion 102): the
// owner's ruling of 2026-11-17, "Same kind only". The DECISION key of a line
// naming the whole word `unbleached` carries the word ('unbleached
// all-purpose flour'): `decisionKeyFor` = its v115 body (`_decisionKeyOf`)
// plus one wrapper, at the function level (the single-food AND the two-part
// return). `itemKeyFor` — the query, cache and density key — is unchanged.
// A person's decision on one kind never reaches the other: not at once
// (apply_to_all), not at the next compute (the carry).
//
// Corpus-backed groups skip without SALT_CORPUS_DIR; every corpus read sits
// inside a test body (the file loads corpusless). Synthesized lines (S) only
// where no corpus line takes the path, each said so where it is used.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/item_key_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: {...pendingSearches});

const _unbleached = 789951;
const _bleached = 789890;
const _u = 'unbleached all-purpose flour';
const _n = 'all-purpose flour';

const _quickBread = '0787-quick-cheese-bread.yaml';
const _gumbo = '0028-chicken-and-sausage-gumbo.yaml';
const _creole = '0107-creole-style-shrimp-and-sausage-gumbo.yaml';
const _daube = '0456-daube-provencal.yaml';
const _sheetCake = '0886-yellow-sheet-cake-with-chocolate-frosting.yaml';
const _pieDough = '0974-foolproof-double-crust-pie-dough.yaml';
const _cfs = '0304-chicken-fried-steaks.yaml';
const _stew = '0006-hearty-beef-and-vegetable-stew.yaml';

IngredientLine _lineOf(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
}

/// [file] with only its line [position] (its real steps kept).
Recipe _only(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

/// [r] with its single line retyped [raw] (an edit of the line's text).
Recipe _retyped(Recipe r, String raw) => r.copyWith(
  ingredients: [
    IngredientGroup(items: [_lineOf(raw)]),
  ],
);

String _g(double? x) => x?.toStringAsFixed(2) ?? '-';

/// A row as the pins compare it: record, status, confidence, grams, key.
String _row(IngredientMatchRow m) =>
    '${m.fdcId} ${m.status} ${m.confidence.toStringAsFixed(6)} ${_g(m.grams)} ${m.itemKey}';

/// [r] stored and computed, its section children first.
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

Future<AppliedToOthers?> _put(
  SaltDatabase db,
  Recipe r,
  int position,
  Map<String, Object?> body,
) => applyMatchOverride(db, _fx, r, position, {
  'raw': nutritionLines(r)[position].raw,
  ...body,
});

/// A provider that cannot be asked (owner gate, hv round 1: the row the
/// engine writes when FDC is down).
class _Down implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) async =>
      throw const NutritionProviderException('down', scope: FailureScope.food);
  @override
  Future<FdcFood?> food(int fdcId) async =>
      throw const NutritionProviderException('down', scope: FailureScope.food);
}

/// Rows [at] of [id] with the gram source and hold, and the stored energy.
String _rows(SaltDatabase db, String id, Set<int> at) {
  final totals = db.nutritionFor(id)?.totalsJson;
  final kcal = totals == null
      ? null
      : ((jsonDecode(totals) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final m in db.ingredientMatchesFor(id))
      if (at.contains(m.position))
        '${m.position}: ${_row(m)} ${m.gramSource} ${m.hold}',
    'kcal ${_g(kcal)}',
  ].join(' | ');
}

/// [r] with the line [old] replaced by [raw], or [raw] put first (old null).
Recipe _edited(Recipe r, String? old, String raw) => r.copyWith(
  ingredients: [
    for (final (i, g) in r.ingredients.indexed)
      g.copyWith(
        items: [
          if (old == null && i == 0) _lineOf(raw),
          for (final l in g.items) l.raw == old ? _lineOf(raw) : l,
        ],
      ),
  ],
);

void main() {
  keys();
  group('v116 (M103: same kind only)', skip: skipIfNoCorpus, () {
    stored();
    property();
    person();
    rekey();
    ownerGate();
  });
}

/// P2, P4 and the kind's reach on items no corpus line holds (the M102
/// gate's lesson: measure the rule off the corpus before calling it
/// harmless) — `lineKeyOf`, the stamp every compute writes.
void keys() {
  test('P4: matcherVersion is 107 (RE-PIN, M108 batch, v121: was 106)', () {
    // RE-PIN (M104 batch, v117): matcherVersion 103 (was 102).
    // RE-PIN (M105 batch, v118): matcherVersion 104 (was 103).
    // RE-PIN (M106 batch, v119): matcherVersion 105 (was 104).
    // RE-PIN (M107 batch, v120): matcherVersion 106 (was 105).
    // RE-PIN (M108 batch, v121): matcherVersion 107 (was 106).
    expect(matcherVersion, 107);
  });

  test('P2 (S): the kind word on the decision key — any case, the whole '
      'word, the two-part return too; an empty key stays empty', () {
    // Synthesized: no corpus line capitalises the word in its item, names
    // it in a two-part line, misspells it or names it alone (the 180 corpus
    // lines naming it are all "… unbleached all-purpose flour", 0 two-part).
    expect(lineKeyOf(_lineOf('1 cup Unbleached All-Purpose Flour')), _u);
    // The two-part line's v115 key, measured on the base ec9d489: 'all-purpose
    // flour plus cornstarch' (with or without the word).
    expect(
      lineKeyOf(
        _lineOf(
          '1 cup unbleached all-purpose flour plus 2 tablespoons cornstarch',
        ),
      ),
      'unbleached all-purpose flour plus cornstarch',
    );
    // The word in the SECOND food (owner gate: the kind read off the first
    // food alone passed every pin): the rule is "the item names the word",
    // anywhere, so the whole key carries the kind — TODAY's value, a key
    // apart from its plain twin's, not a claim about the cornstarch.
    expect(
      lineKeyOf(
        _lineOf(
          '1 cup cornstarch plus 2 tablespoons unbleached all-purpose flour',
        ),
      ),
      'unbleached cornstarch plus all-purpose flour',
    );
    expect(
      lineKeyOf(
        _lineOf('1 cup cornstarch plus 2 tablespoons all-purpose flour'),
      ),
      'cornstarch plus all-purpose flour',
    );
    // Negatives: the same two-part line without the word keeps its v115 key
    // exactly; a word that only begins with it is no kind; the word alone
    // keys nothing (no row is ever keyed 'unbleached ').
    expect(
      lineKeyOf(
        _lineOf('1 cup all-purpose flour plus 2 tablespoons cornstarch'),
      ),
      'all-purpose flour plus cornstarch',
    );
    expect(
      lineKeyOf(_lineOf('1 cup unbleachedx all-purpose flour')),
      'unbleachedx all-purpose flour',
    );
    expect(lineKeyOf(_lineOf('unbleached')), '');
    expect(decisionKeyFor('unbleached'), '');
  });

  test('the kind follows the word whatever the food — like the ranking '
      "token, it is not scoped to flour (TODAY's values, synthesized)", () {
    // Synthesized: no corpus ingredient line names `unbleached` beside
    // another food ("unbleached cake flour" occurs in 0886's prep notes
    // only). Recorded as TODAY's values; v115 keyed each without the word.
    expect(
      lineKeyOf(_lineOf('1 cup unbleached bread flour')),
      'unbleached bread flour',
    );
    expect(
      lineKeyOf(_lineOf('1 cup unbleached cake flour')),
      'unbleached cake flour',
    );
    expect(
      lineKeyOf(_lineOf('1 cup unbleached cane sugar')),
      'unbleached cane sugar',
    );
    // The query / cache / density key is untouched.
    expect(itemKeyFor('unbleached bread flour'), 'bread flour');
    expect(itemKeyFor(_u), _n);
  });

  test("P3's negative (S): \"…, preferably unbleached\" ranks with the word "
      "and keys plain — TODAY's value, an ALARM, not a rule", () {
    // Synthesized: no corpus line names the word in its prep tail (0107 |4's
    // real "…, preferably bleached" with the word turned). The item drops
    // the prep word, so the ranking flag (raw) is true and the key (item)
    // plain. The YAML rework can produce this shape; the day it does, this
    // pin fails and the fix is one line in `decisionItemOf` (carry the flag
    // word into the item text) — not built now.
    final line = _lineOf('2 cups all-purpose flour, preferably unbleached');
    expect(namesUnbleached(line.raw), isTrue);
    expect(lineKeyOf(line), _n);
  });
}

/// P1: the key a compute STORES.
void stored() {
  test(
    'P1: a compute stores the kind key on a line naming the word, the '
    'plain key on the others (bleached lines and cake flour included)',
    () async {
      final got = <String, String?>{};
      for (final (file, position) in [
        (_quickBread, 1),
        (_gumbo, 0),
        (_creole, 4),
      ]) {
        final (db, _) = a.pathDb();
        final r = await _compute(db, _only(file, position));
        got['$file|$position'] = d.rowOf(db, r, 0).itemKey;
      }
      expect(got, {
        '$_quickBread|1':
            _u, // "3 cups (15 ounces) unbleached all-purpose flour"
        '$_gumbo|0': _n, // "1 cup (5 ounces) all-purpose flour"
        '$_creole|4': _n, // "½ cup all-purpose flour, preferably bleached"
      });
      // 0886 |3 "2¼ cups (9 ounces) bleached cake flour": its search is not
      // in the fixtures, so its key is read as the compute stamps it.
      final cake = nutritionLines(loadCorpusRecipe(_sheetCake))[3];
      expect(cake.raw, '2¼ cups (9 ounces) bleached cake flour');
      expect(lineKeyOf(cake), 'bleached cake flour');
    },
  );
}

/// P3: the PROPERTY over every keyed corpus line (main and section lines):
/// the ranking flag (the weighed line's RAW) and the key's kind (the ITEM)
/// agree, both directions. Its limit: it sees the corpus as it is — a line
/// whose item drops the word its raw names (P3's negative) is not one today.
void property() {
  test('P3: namesUnbleached(raw) == the key carries the kind, on every keyed '
      'corpus line', () {
    var flagged = 0;
    var plain = 0;
    final disagree = <String>[];
    final files =
        Directory(corpusRecipesDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yaml'))
            .toList()
          ..sort((x, y) => x.path.compareTo(y.path));
    for (final file in files) {
      final host = loadCorpusRecipe(file.uri.pathSegments.last);
      final recipes = [
        host,
        for (final sub in host.subsections)
          if (sub.title != null && (sub.ingredients ?? const []).isNotEmpty)
            sectionRecipeOf(host, sub),
      ];
      for (final r in recipes) {
        for (final line in nutritionLines(r)) {
          final key = lineKeyOf(line);
          if (key.isEmpty) {
            continue;
          }
          final flag = namesUnbleached(weighedLine(r, line).raw);
          if (flag != key.startsWith('unbleached ')) {
            disagree.add('${r.id}: ${line.raw} -> $key');
          }
          flag ? flagged++ : plain++;
        }
      }
    }
    expect(disagree, isEmpty);
    // 180 = the 172 lines the replay stores a row for + 8 lines of titled
    // sections the replay stores no row for (0077's two variations, the pan
    // sauces of 0119 and 0190, the gravies of 0155, 0156, 0170 and 0207 —
    // matched to the replay's rows by host, section and raw line); the
    // property holds on them too.
    expect((flagged, plain), (180, 16329));
  });
}

void person() {
  test('P6: the real two-kind host (0974 |0 unbleached, its section "Foolproof '
      'Single-Crust Pie Dough" |0 plain) — a Confirm + apply_to_all on either '
      'never touches the other kind; a pick + apply_to_all reaches its own '
      'kind elsewhere (the negative)', () async {
    final got = <String, String>{};
    for (final (verb, fromHost, body) in <(String, bool, Map<String, Object?>)>[
      ('confirm host', true, {'confirmed': true, 'apply_to_all': true}),
      ('confirm section', false, {'confirmed': true, 'apply_to_all': true}),
      ('pick 789890 host', true, {'fdc_id': _bleached, 'apply_to_all': true}),
      (
        'pick 789951 section',
        false,
        {'fdc_id': _unbleached, 'apply_to_all': true},
      ),
    ]) {
      final (db, _) = a.pathDb();
      final host = await _compute(db, loadCorpusRecipe(_pieDough));
      final other = await _compute(db, _only(_quickBread, 1));
      final plain = await _compute(db, _only(_gumbo, 0));
      // Its section, computed under its own key as the bulk job does.
      final section = nutritionRecipeOf(
        db,
        sectionKeyOf(host.id, 'Foolproof Single-Crust Pie Dough'),
      )!.recipe;
      expect(await matchAndCompute(db, _fx, section), isNull);
      expect(
        nutritionLines(section)[0].raw,
        '1¼ cups (6¼ ounces) all-purpose flour',
      );
      expect(_row(d.rowOf(db, host, 0)), '789951 auto 0.983333 354.37 $_u');
      expect(_row(d.rowOf(db, section, 0)), '789890 auto 0.950000 177.18 $_n');
      final applied = await _put(db, fromHost ? host : section, 0, body);
      got[verb] = [
        'host ${_row(d.rowOf(db, host, 0))}',
        'section ${_row(d.rowOf(db, section, 0))}',
        '0787 ${_row(d.rowOf(db, other, 0))}',
        '0028 ${_row(d.rowOf(db, plain, 0))}',
        'applied ${applied?.lines}',
      ].join(' | ');
    }
    // v115 (measured, docs/API.md "Matcher v115" R6): the Confirm on the
    // host re-pointed every plain row to 789951, the section's |0 and 0028
    // |0 among them; the Confirm on the section the reverse.
    expect(got, {
      'confirm host':
          'host 789951 confirmed 0.983333 354.37 $_u | section 789890 auto 0.950000 177.18 $_n | 0787 789951 auto 0.983333 425.24 $_u | 0028 789890 auto 0.950000 141.75 $_n | applied 0',
      'confirm section':
          'host 789951 auto 0.983333 354.37 $_u | section 789890 confirmed 0.950000 177.18 $_n | 0787 789951 auto 0.983333 425.24 $_u | 0028 789890 auto 0.950000 141.75 $_n | applied 0',
      'pick 789890 host':
          'host 789890 overridden 1.000000 354.37 $_u | section 789890 auto 0.950000 177.18 $_n | 0787 789890 auto 1.000000 425.24 $_u | 0028 789890 auto 0.950000 141.75 $_n | applied 1',
      'pick 789951 section':
          'host 789951 auto 0.983333 354.37 $_u | section 789951 overridden 1.000000 177.18 $_n | 0787 789951 auto 0.983333 425.24 $_u | 0028 789951 auto 1.000000 141.75 $_n | applied 1',
    });
  });

  test('P6b: the matches GET counts the same kind only (`others` / '
      '`others_lines`, the sheet\'s "N other recipes")', () async {
    // Owner gate: the GET deriving its reach from the key WITHOUT the kind
    // passed every pin (the reach was pinned through `decisionReach` alone).
    final (db, _) = a.pathDb();
    final bread = await _compute(db, _only(_quickBread, 1));
    final daube = await _compute(db, _only(_daube, 10));
    final gumbo = await _compute(db, _only(_gumbo, 0));
    Future<(Object?, Object?)> others(Recipe r) async {
      final item =
          ((await matchesBody(db, _fx, r))['items']! as List).single as Map;
      return (item['others'], item['others_lines']);
    }

    // The unbleached 0787 |1 (789951) beside the plain 0028 |0 on ANOTHER
    // record (789890): under one key the plain line is an undecided sibling
    // on another food, and counted; under its own kind's key it is not.
    expect(await others(bread), (0, 0));
    expect(await others(gumbo), (0, 0));
    // The positive: once 0787 |1 is picked onto 789890, its own kind's
    // sibling (daube |10, still on 789951) is what an apply would reach —
    // and the plain 0028 |0 still is not.
    await _put(db, bread, 0, {'fdc_id': _bleached});
    expect(await others(bread), (1, 1));
    expect(await others(daube), (0, 0));
    expect(await others(gumbo), (0, 0));
  });

  test('P7: both kinds decided are two decisions; each kind recomputes on '
      'its own', () async {
    final (db, _) = a.pathDb();
    // Each kind decided on the OTHER kind's record (closer round 1, D2: with
    // both on 789951 the recompute below read the same whichever kind's
    // decision the carry took), so the recompute tells the kinds apart.
    final bread = await _compute(db, _only(_quickBread, 1));
    final gumbo = await _compute(db, _only(_gumbo, 0));
    await _put(db, bread, 0, {'fdc_id': _bleached});
    await _put(db, gumbo, 0, {'fdc_id': _unbleached});
    expect(
      [
        for (final r in db.allDecisions())
          '${r.itemKey}|${r.item}|${r.fdcId}|${r.asPicked}',
      ]..sort(),
      [
        'all-purpose flour|all-purpose flour|789951|false',
        'unbleached all-purpose flour|unbleached all-purpose flour|789890|false',
      ],
    );
    // Negative: each key's decision holds its own item text.
    expect(db.decisionFor(_n)?.item, _n);
    expect(db.decisionFor(_u)?.item, _u);
    // An unbleached recipe computed after both: its own kind's decision
    // (789890; the plain kind's would land 789951).
    final daube = await _compute(db, _only(_daube, 10));
    expect(_row(d.rowOf(db, daube, 0)), '789890 auto 1.000000 47.25 $_u');
    // A plain recipe computed after both: its own kind's decision (789951;
    // the unbleached kind's would land 789890).
    final creole = await _compute(db, _only(_creole, 4));
    expect(_row(d.rowOf(db, creole, 0)), '789951 auto 1.000000 70.87 $_n');
  });

  test('P9 (S): one recipe, both kinds — the settle of a Confirm reaches the '
      'same kind only; an un-skip derives from its own kind', () async {
    // Synthesized: no corpus recipe id holds both kinds (one host and its
    // section do, P6). Corpus raws: 0787 |1, 0028 |0, and 0974 |0's head.
    const lines = [
      '3 cups (15 ounces) unbleached all-purpose flour',
      '1 cup (5 ounces) all-purpose flour',
      '2½ cups (12½ ounces) unbleached all-purpose flour',
    ];
    final (db, _) = a.pathDb();
    final r = wp.saveLines(db, lines, id: 'p9');
    await matchAndCompute(db, _fx, r);
    await _put(db, r, 0, {'confirmed': true});
    expect(_row(d.rowOf(db, r, 1)), '789890 auto 0.950000 141.75 $_n');
    expect(_row(d.rowOf(db, r, 2)), '789951 auto 1.000000 354.37 $_u');
    for (final (at, expected) in [
      (1, '789890 auto 0.950000 141.75 $_n'),
      (2, '789951 auto 1.000000 354.37 $_u'),
    ]) {
      await _put(db, r, at, {'skipped': true});
      await _put(db, r, at, {'skipped': false});
      expect(_row(d.rowOf(db, r, at)), expected, reason: 'un-skip $at');
    }
  });

  test('P12: a decided line retyped to the other kind is not followed; an '
      'amount-only edit keeps the decision', () async {
    for (final (raw, expected) in [
      (
        '3 cups (15 ounces) all-purpose flour',
        '789890 auto 0.950000 425.24 $_n',
      ),
      (
        '2 cups (10 ounces) unbleached all-purpose flour',
        '789951 confirmed 0.983333 283.50 $_u',
      ),
    ]) {
      final (db, _) = a.pathDb();
      final r = await _compute(db, _only(_quickBread, 1));
      await _put(db, r, 0, {'confirmed': true});
      final edited = _retyped(r, raw);
      await d.editAndCompute(db, _fx, edited);
      expect(_row(d.rowOf(db, edited, 0)), expected, reason: raw);
    }
  });

  test("P11 (S): apply_to_all's write-time re-check — a target retyped to the "
      'other kind between the reach and the write is not written; one '
      'retyped within its kind is', () async {
    // Synthesized: the reach / write window is a provider await, as
    // nutrition_v23_writepath_test's fetch-window pins build it; the earlier
    // target '0000' is 0006's real "3 tablespoons all-purpose flour" with the
    // word added, so that it is of the reached kind and its portion fetch
    // opens the window.
    for (final (raw, written) in [
      ('3 cups (15 ounces) all-purpose flour', false),
      ('2 cups (10 ounces) unbleached all-purpose flour', true),
    ]) {
      final (db, _) = a.pathDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      await matchAndCompute(
        db,
        provider,
        wp.saveLines(db, [
          '3 tablespoons unbleached all-purpose flour',
        ], id: '0000'),
      );
      final target = wp.saveLines(db, [
        '3 cups (15 ounces) unbleached all-purpose flour',
      ], id: 'b');
      await matchAndCompute(db, provider, target);
      final f = (await FixtureProvider().food(168913))!;
      provider.onCall = () async {
        wp.saveLines(db, [raw], id: 'b');
      };
      final res = await applyDecisionToOthers(
        db,
        provider,
        itemKey: _u,
        decided: FdcFood(
          fdcId: f.fdcId,
          description: f.description,
          dataType: f.dataType,
          nutrientsPer100g: f.nutrientsPer100g,
          portions: const [],
        ),
        excluding: (recipeId: 'zz', position: 0),
      );
      expect(
        (
          [for (final m in db.ingredientMatchesFor('0000')) _row(m)],
          [for (final m in db.ingredientMatchesFor('b')) '${m.raw} ${_row(m)}'],
          (res.lines, res.moved, res.decided, res.gone),
        ).toString(),
        written
            ? '([168913 auto 1.000000 25.69 $_u], [2 cups (10 ounces) unbleached all-purpose flour 168913 auto 1.000000 283.50 $_u], (2, 0, 0, 0))'
            : '([168913 auto 1.000000 25.69 $_u], [], (1, 0, 0, 1))',
        reason: raw,
      );
    }
  });
}

/// P8: the boot re-key 101 → 102.
void rekey() {
  test('P8: the boot re-key moves a decision made on an unbleached line to '
      'the kind key and the rows with it; a plain decision stays', () async {
    for (final (item, key) in [(_u, _u), (_n, _n)]) {
      final (db, _) = a.pathDb();
      final bread = await _compute(db, _only(_quickBread, 1));
      final gumbo = await _compute(db, _only(_gumbo, 0));
      // The database as v115 (matcherVersion 101) left it: both kinds keyed
      // 'all-purpose flour', the decision under it, the markers at 101.
      for (final r in [bread, gumbo]) {
        db.setMatchItemKey(r.id, 0, _n);
      }
      db
        ..insertDecision(
          IngredientDecisionRow(
            itemKey: _n,
            item: item,
            fdcId: item == _u ? _unbleached : _bleached,
            description: 'x',
            dataType: 'Foundation',
            decidedBy: null,
            decidedAt: '2026-11-17T00:00:00.000000Z',
          ),
        )
        ..setSetting(decisionRekeySetting, '101')
        ..setSetting(itemKeyBackfillSetting, '101');
      rekeyAfterMatcherChange(db);
      expect(
        [for (final r in db.allDecisions()) '${r.itemKey}|${r.item}'],
        [
          '$key|$item',
        ],
      );
      expect(
        (d.rowOf(db, bread, 0).itemKey, d.rowOf(db, gumbo, 0).itemKey),
        (_u, _n),
      );
    }
  });
}

/// The owner gate's hand-edit verifier rounds: the `lineKeyOf` sites reached
/// with a line naming the word (by round 1's measurement; the second "gone"
/// count by the closer after it), each pinned by a value its one-site mutant
/// (the key without the kind there) moves — and the layout's stamp, whose
/// neighbours rounds 2, 3 and 5 each found unpinned (G3b; G3c, once round 4
/// had refuted the ground for leaving it stated; then the PROPERTY, G3p).
void ownerGate() {
  test('G1: the row a compute writes when FDC cannot be asked keeps the '
      'kind; a plain pick + apply_to_all does not reach it', () async {
    // `_computePass`'s engineUnavailable row — owner gate, hv round 1.
    final (db, _) = a.pathDb();
    final r = _only(_quickBread, 1);
    db
      ..upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub')
      ..upsertRecipe(
        r,
        sourceSlug: 'atk-tv-2023',
        contentHash: contentHashOf(r),
      );
    final bread = db.recipeByIdOrSlug(r.id)!.recipe;
    expect(
      await matchAndCompute(db, _Down(), bread),
      isA<NutritionProviderException>(),
    );
    const unmatched = 'null unmatched 0.000000 - $_u';
    expect(_row(d.rowOf(db, bread, 0)), unmatched);
    final gumbo = await _compute(db, _only(_gumbo, 0));
    Future<(Object?, Object?)> others(Recipe r) async {
      final item =
          ((await matchesBody(db, _fx, r))['items']! as List).single as Map;
      return (item['others'], item['others_lines']);
    }

    expect((await others(bread), await others(gumbo)), ((0, 0), (0, 0)));
    final applied = await _put(db, gumbo, 0, {
      'fdc_id': 168913,
      'apply_to_all': true,
    });
    expect(applied?.lines, 0);
    expect(_row(d.rowOf(db, bread, 0)), unmatched);
  });

  test("G2: a coat line edited, saved, not computed — the totals' coat plan "
      'keeps its budget on an amount edit, drops it on a retype to the other '
      'kind until the next compute', () async {
    // `_m52Laid` — owner gate, hv round 1. 0304's coat: |0 the flour, |3 the
    // egg, |6 the buttermilk.
    const amount = '4 cups unbleached all-purpose flour';
    const retype = '3 cups all-purpose flour';
    const kept =
        '3: 748967 auto 0.920000 14.58 egg discarded null | 6: 2705393 auto 0.990000 71.13 buttermilk discarded null';
    const dropped =
        '3: 748967 auto 0.920000 50.00 egg piece null | 6: 2705393 auto 0.990000 244.00 buttermilk portion null | kcal 2644.36';
    const computed =
        '0: 789890 auto 0.950000 96.71 $_n discarded null | $kept | kcal 2869.92';
    for (final (raw, confirm, totals, next) in [
      (
        amount,
        false,
        '0: 789951 auto 0.983333 102.13 $_u discarded null | $kept | kcal 2881.59',
        null,
      ),
      (
        amount,
        true,
        '0: 789951 confirmed 0.983333 102.13 $_u discarded null | $kept | kcal 2881.59',
        null,
      ),
      (
        retype,
        false,
        '0: 789951 auto 0.983333 - $_u null coating | $dropped',
        computed,
      ),
      (
        retype,
        true,
        '0: 789951 confirmed 0.983333 0.00 $_u discarded null | $dropped',
        computed,
      ),
    ]) {
      final (db, _) = a.pathDb();
      final cfs = await _compute(db, loadCorpusRecipe(_cfs));
      if (confirm) {
        await _put(db, cfs, 0, {'confirmed': true});
      }
      wp.saveRecipe(db, _edited(cfs, nutritionLines(cfs)[0].raw, raw));
      recomputeTotals(db, nutritionRecipeOf(db, cfs.id)!.recipe);
      final why = '$raw confirmed $confirm';
      expect(_rows(db, cfs.id, {0, 3, 6}), totals, reason: why);
      if (next != null) {
        await matchAndCompute(db, _fx, nutritionRecipeOf(db, cfs.id)!.recipe);
        expect(_rows(db, cfs.id, {0, 3, 6}), next, reason: why);
      }
    }
  });

  test('G3: a decided row a layout moves keeps the kind key; a plain pick + '
      'apply_to_all then reaches nothing', () async {
    // `layoutMatchRows`' moves — owner gate, hv round 1. 0304 |12 "3
    // tablespoons unbleached all-purpose flour" decided, then a line put
    // first (a synthesized edit: 0304 holds no "1 teaspoon table salt"
    // line; any line put first moves |12 to |13).
    for (final (verb, row) in <(Map<String, Object?>, String)>[
      ({'fdc_id': _bleached}, '789890 overridden 1.000000 26.58 $_u'),
      ({'confirmed': true}, '789951 confirmed 0.983333 26.58 $_u'),
    ]) {
      for (final layoutFirst in [true, false]) {
        final (db, _) = a.pathDb();
        final cfs = await _compute(db, loadCorpusRecipe(_cfs));
        await _put(db, cfs, 12, verb);
        wp.saveRecipe(db, _edited(cfs, null, '1 teaspoon table salt'));
        final moved = nutritionRecipeOf(db, cfs.id)!.recipe;
        final why = '$verb layout first $layoutFirst';
        if (layoutFirst) {
          // The layout alone writes the moved row's key.
          layoutMatchRows(db, moved);
          expect(_row(d.rowOf(db, cfs, 13)), row, reason: why);
        }
        await matchAndCompute(db, _fx, moved);
        expect(_row(d.rowOf(db, cfs, 13)), row, reason: why);
        final gumbo = await _compute(db, _only(_gumbo, 0));
        final applied = await _put(db, gumbo, 0, {
          'fdc_id': 168913,
          'apply_to_all': true,
        });
        expect((applied?.lines, _row(d.rowOf(db, cfs, 13))), (0, row));
      }
    }
  });

  test('G3b (S): a moved row with a stale v115 key is re-keyed to the kind by '
      'the layout (its text and its line both name the word)', () async {
    // `layoutMatchRows`' moves — owner gate, hv round 2: the moved row
    // KEEPING its stored key passed G3 (there the stored key is already the
    // line's). Synthesized state: the stored key put back to v115's on a
    // decided row whose line was then amount-edited (a row the boot backfill
    // leaves, its text no longer its line's) and moved by a line put first.
    // Which text supplies the key — the line's, G3c. NOT pinned (hv round 3,
    // stated in docs/API.md "Matcher v116"): a row whose stored text is of
    // the OTHER kind from its line, a pairing only a pre-v116 layout made.
    final (db, _) = a.pathDb();
    final cfs = await _compute(db, loadCorpusRecipe(_cfs));
    await _put(db, cfs, 12, {'fdc_id': _bleached});
    db.setMatchItemKey(cfs.id, 12, _n);
    expect(_row(d.rowOf(db, cfs, 12)), '789890 overridden 1.000000 26.58 $_n');
    wp.saveRecipe(
      db,
      _edited(
        _edited(
          cfs,
          nutritionLines(cfs)[12].raw,
          '4 tablespoons unbleached all-purpose flour',
        ),
        null,
        '1 teaspoon table salt',
      ),
    );
    layoutMatchRows(db, nutritionRecipeOf(db, cfs.id)!.recipe);
    expect(_row(d.rowOf(db, cfs, 13)), '789890 overridden 1.000000 26.58 $_u');
  });

  test("G3c: a moved row takes its LINE's key (the authored item's), not the "
      'key of its own text — 0006 |6, thyme', () async {
    // `layoutMatchRows`' moves — owner gate, hv round 4: the moved row keyed
    // by the parse of its OWN stored text passed the whole server suite. The
    // two keys differ wherever a line's authored item keys apart from the
    // parse of its raw text (51 of the 13,615 lines of the corpus's recipes
    // outside their titled sections, 59 of 16,510 with them; none across
    // kinds): 0006 |6 keys 'thyme', its text alone 'thyme or dried'. No
    // kind in this pin — the stamp's rule, on a corpus line.
    final (db, _) = a.pathDb();
    final stew = await _compute(db, loadCorpusRecipe(_stew));
    expect(
      nutritionLines(stew)[6].raw,
      '1 tablespoon minced fresh thyme or 1 teaspoon dried',
    );
    expect(_row(d.rowOf(db, stew, 6)), '173470 auto 0.900000 2.40 thyme');
    // A synthesized edit: 0006 holds no "1 teaspoon table salt" line; any
    // line put first moves |6 to |7.
    wp.saveRecipe(db, _edited(stew, null, '1 teaspoon table salt'));
    layoutMatchRows(db, nutritionRecipeOf(db, stew.id)!.recipe);
    expect(_row(d.rowOf(db, stew, 7)), '173470 auto 0.900000 2.40 thyme');
  });

  test(
    'G3p: the PROPERTY — whatever key a row holds, a row the layout moves '
    "is stamped its new line's key, on every line of every corpus recipe",
    () {
      // `layoutMatchRows`' moves — owner gate, hv round 5: a FIFTH neighbour of
      // the stamp (the key without its second food, 'egg' for 'egg plus yolk')
      // passed the whole server suite — spot pins do not end the neighbours of
      // "the line's key", so this pins what the stamp IS. Every corpus recipe's
      // own lines (its titled sections' lines are not looped: the limit), one
      // seeded row per line ON its line's text under a key no line has; one
      // line put first (synthesized: 'zzprobe' is no corpus word), so the
      // layout moves every row down by one; each moved row must hold
      // `lineKeyOf` of the line it now sits on.
      final (db, _) = a.pathDb();
      db.upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub');
      final files =
          Directory(corpusRecipesDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.yaml'))
              .toList()
            ..sort((x, y) => x.path.compareTo(y.path));
      var moved = 0;
      final wrong = <String>[];
      for (final file in files) {
        final r = loadCorpusRecipe(file.uri.pathSegments.last);
        db.upsertRecipe(
          r,
          sourceSlug: 'atk-tv-2023',
          contentHash: contentHashOf(r),
        );
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        for (final (at, line) in nutritionLines(stored).indexed) {
          db.upsertIngredientMatch(
            IngredientMatchRow(
              recipeId: r.id,
              position: at,
              raw: line.raw,
              itemKey: 'zz stale',
              fdcId: null,
              description: null,
              dataType: null,
              confidence: 0,
              grams: null,
              gramSource: null,
              status: 'unmatched',
            ),
          );
        }
        wp.saveRecipe(db, _edited(stored, null, '1 teaspoon zzprobe'));
        final now = nutritionRecipeOf(db, r.id)!.recipe;
        layoutMatchRows(db, now);
        final lines = nutritionLines(now);
        for (final m in db.ingredientMatchesFor(r.id)) {
          final line = lines[m.position];
          if (m.position == 0 || m.raw != line.raw) {
            wrong.add('${r.id}|${m.position}: not on its line (${m.raw})');
            continue;
          }
          moved++;
          final key = lineKeyOf(line);
          if ((m.itemKey ?? '') != key) {
            wrong.add('${r.id}|${m.position}: ${m.itemKey} != $key');
          }
        }
      }
      expect(wrong, isEmpty);
      expect(moved, 13615);
    },
  );

  test("G4 (S): apply_to_all's two \"gone\" counts — a target retyped within "
      'the kind is moved, across kinds or to another ingredient gone', () async {
    // `applyDecisionToOthers`' gone count at the turn (an earlier target's
    // portion fetch opens the window before 'b' is read) and after the
    // target's own awaits (b's own portion fetch) — owner gate, hv round 1.
    // Synthesized as P11: '3 tablespoons unbleached all-purpose flour' is
    // 0006's real line with the word added; in the window 'b' is re-saved
    // AND recomputed.
    const early = '3 tablespoons unbleached all-purpose flour';
    final got = <String>[];
    for (final (first, target) in [
      (early, '3 cups (15 ounces) unbleached all-purpose flour'),
      (null, early),
    ]) {
      for (final raw in [
        '2 cups (10 ounces) unbleached all-purpose flour',
        '3 cups (15 ounces) all-purpose flour',
        '1 teaspoon table salt',
      ]) {
        final (db, _) = a.pathDb();
        final inner = FixtureProvider(pending: pendingSearches);
        final provider = wp.Gated(inner);
        if (first != null) {
          await matchAndCompute(
            db,
            provider,
            wp.saveLines(db, [first], id: '0000'),
          );
        }
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [target], id: 'b'),
        );
        final f = (await FixtureProvider().food(168913))!;
        provider.onCall = () async {
          await matchAndCompute(db, inner, wp.saveLines(db, [raw], id: 'b'));
        };
        final res = await applyDecisionToOthers(
          db,
          provider,
          itemKey: _u,
          decided: FdcFood(
            fdcId: f.fdcId,
            description: f.description,
            dataType: f.dataType,
            nutrientsPer100g: f.nutrientsPer100g,
            portions: const [],
          ),
          excluding: (recipeId: 'zz', position: 0),
        );
        got.add(
          '${first == null ? 'after' : 'turn'} '
          '${(res.lines, res.moved, res.decided, res.gone)} '
          '${[for (final m in db.ingredientMatchesFor('b')) '${m.raw}: ${_row(m)}']}',
        );
      }
    }
    expect(got, [
      'turn (1, 1, 0, 0) [2 cups (10 ounces) unbleached all-purpose flour: 789951 auto 0.983333 283.50 $_u]',
      'turn (1, 0, 0, 1) [3 cups (15 ounces) all-purpose flour: 789890 auto 0.950000 425.24 $_n]',
      'turn (1, 0, 0, 1) [1 teaspoon table salt: 173468 auto 1.000000 6.01 table salt]',
      'after (0, 1, 0, 0) [2 cups (10 ounces) unbleached all-purpose flour: 789951 auto 0.983333 283.50 $_u]',
      'after (0, 0, 0, 1) [3 cups (15 ounces) all-purpose flour: 789890 auto 0.950000 425.24 $_n]',
      'after (0, 0, 0, 1) [1 teaspoon table salt: 173468 auto 1.000000 6.01 table salt]',
    ]);
  });

  test(
    'G5 (S): the one reader of the key TEXT — the citrus pair pattern '
    "misses a line naming the word (TODAY's value, an ALARM, not a rule)",
    () async {
      // `secondFoodRuleOf` tests the line key against the citrus pair pattern
      // — owner gate, hv round 1. Synthesized: no corpus line names the word
      // in a citrus pair.
      final got = <String>[];
      for (final raw in [
        '1 tablespoon grated lemon zest plus 2 tablespoons juice',
        '1 tablespoon grated unbleached lemon zest plus 2 tablespoons juice',
      ]) {
        final line = _lineOf(raw);
        final rule = secondFoodRuleOf(line);
        final (db, _) = a.pathDb();
        expect(
          await matchAndCompute(db, _fx, wp.saveLines(db, [raw], id: 'x')),
          isNull,
        );
        got.add(
          '${lineKeyOf(line)}: rule ${rule?.fdcId} ${rule?.query} | '
          '${_rows(db, 'x', {0})}',
        );
      }
      expect(got, [
        'lemon zest plus juice: rule 167747 lemon juice | 0: 167747 auto 0.953333 30.46 lemon zest plus juice density null | kcal 6.70',
        'unbleached lemon zest plus juice: rule null null | 0: 167749 auto 0.570000 6.00 unbleached lemon zest plus juice portion second_food | kcal -',
      ]);
    },
  );
}
