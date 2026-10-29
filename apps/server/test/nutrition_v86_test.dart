// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v86 (batch M84; matcherVersion 81 — record maps; prep51 design_v2
// §2 M84, decided under the 2026-10-07 standing authorization; zero
// requests): D3b two gated braised same-cut pairs in `braisedKept` (§0.3:
// 167853 → SR 167854 spareribs, 172513 → SR 172514 New Zealand fore-shank),
// deducted only where the recipe's own steps skim the fat
// (chinese-style-barbecued-spareribs S2, braised-lamb-shanks S4; the rows
// stay GROSS, the totals deduct); E2b a line whose item's head is 'bones'
// on a "bone marrow" record gets no grams (simple-pot-au-feu|2 on SR
// 169800). Every whole-recipe value is the fresh compute over recorded real
// FDC answers (FixtureProvider) and equals the v86 replay of snapshot 29
// (fix86 g1) on every pinned field — pot-au-feu's per serving is not pinned
// (the fixtures read 645.06 against the replay's 645.03: |13's 2346402 and
// |15's 2710823 were recorded from earlier snapshots, 342.92 / 127.46 kcal
// against 342.72 / 127.47), only what its Confirm adds. Never the network.
// Every corpus line is real. The order row: braised-lamb-shanks|2 (its
// browning fat, prep51 §0.5) is M94's — pin the combined recipe there.
// STATED constructions (negative paths no corpus line reaches):
// pot-au-feu|2 written "1½ pounds marrow" and "1½ pounds bone marrow" (a
// marrow record's line whose head is not 'bones' — the second with a
// 'bone' word — no corpus row but |2 sits on a marrow record) and
// "1½ pounds marrow bone" (the singular: head 'bone', no 'bones' word);
// grams a person types on |2 (the basis's `grams == null` gate); |2
// written amount-less with S1 printing "1½ pounds marrow bones" (the
// guard's place after the recipe readers — no corpus line reaches it); the cap
// shapes' 400 repeated real lines (the house's cap-shape exception).
// The owner gate (verify4 D1): the head gate's REAL converse on the marrow
// record itself — 0133|0's bone-in chicken pieces (head 'chicken') on
// 169800, a person's pick from the line's own cached answer, weighed.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _chinese = '0538-chinese-style-barbecued-spareribs.yaml';
const _shanks =
    '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml';
const _memphis = '0614-memphis-style-barbecued-spareribs.yaml';
const _potAuFeu = '0092-simple-pot-au-feu.yaml';
const _tortilla = '0473-tortilla-soup.yaml';

const _marrow =
    'the line weighs the bones, not the marrow eaten — no figure for the '
    'marrow a bone holds';

/// A fresh database (its directory removed after the test).
(SaltDatabase, String) _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v86-');
  final path = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  ).dbPath;
  final db = SaltDatabase.open(path)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return (db, path);
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// The whole-recipe rows (file, position, raw, fdc id, source, grams, kcal,
/// basis) — the rows stay GROSS (F8): v85's value on every one but |2's.
typedef _Row = (String, int, String, int, String?, String?, String, String);

const _ribs =
    '2 × 1247 g (printed 2½–3 lb, the midpoint) × 0.58 edible · approximate '
    '(USDA AH-102 item 1925: pork spareribs, raw → lean and fat meat 58 % '
    '(43–71; bones 42))';

const List<_Row> _rows = [
  // D3b: gross — the deduction is the totals' (below), the row unchanged.
  (
    _chinese,
    9,
    '2 (2½- to 3-pound) racks St. Louis–style spareribs, cut into individual ribs',
    167853,
    'weight',
    '1446.96',
    '4008.07',
    _ribs,
  ),
  (
    _shanks,
    0,
    '6 (12- to 16-ounce) lamb shanks, trimmed',
    172513,
    'weight',
    '1666.95',
    '3050.52',
    '6 × 397 g (printed 12–16 oz, the midpoint) × 0.70 edible · approximate '
        '(USDA AH-102 item 1339: lamb foreleg (shank), choice, raw → lean and '
        'fat meat 70 % (bones 30; limited data))',
  ),
  // The negative: no step skims (nor do rosticciana|0, kansas-city|5 and
  // oven-barbecued|9, the other 167853 rows at v85; 172513 holds lamb|0
  // alone).
  (
    _memphis,
    1,
    '2 (2½- to 3-pound) racks St. Louis–style spareribs, trimmed',
    167853,
    'weight',
    '1446.96',
    '4008.07',
    _ribs,
  ),
  // E2b — v85: 680.39 g `weight`, "from 1 1/2 pound" (0 kcal either way:
  // confidence 0.486667, held below the gate by the 'alaska native' dock).
  (_potAuFeu, 2, '1½ pounds marrow bones', 169800, null, null, '0.00', _marrow),
];

/// Each recipe's (status, kcal per serving, batch energy) — v85's in the
/// comment where it moved.
const Map<String, (String, String, String)> _totals = {
  // v85: 991.75 / 5950.51 — the row's 4,008.07 kcal × (1 − 0.761918) =
  // 954.25 less (the stored batch −954.26; per serving × 6, −954.24).
  _chinese: ('complete', '832.71', '4996.25'),
  // v85: 613.48 / 3680.89 — the row's 3,050.52 kcal × (1 − 0.924475) =
  // 230.39 less (per serving × 6, −230.40).
  _shanks: ('complete', '575.08', '3450.50'),
  _memphis: ('complete', '1070.60', '4282.38'),
};

void main() {
  test('matcherVersion 82 (v86 set it to 81, batch M84: rows move)', () {
    // RE-PIN (M85 batch, v87): matcherVersion 82 (was 81).
    expect(matcherVersion, 82);
  });

  group('matcher v86 (batch M84) — whole recipes', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('salt-v86-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: dir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      addTearDown(() {
        db.dispose();
        dir.deleteSync(recursive: true);
      });
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in [..._totals.keys, _potAuFeu]) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    String kcalOf(IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    test('each row its record, source, grams, energy and basis (the v86 '
        "replay's): D3b's gross, E2b's none on 169800, the converse's "
        'weighed', () {
      for (final (file, position, raw, fdcId, source, grams, kcal, basis)
          in _rows) {
        final recipe = recipes[file]!;
        final line = nutritionLines(recipe)[position];
        final row = _row(db, recipe.id, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, source),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(row), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    });

    test('the totals: the two gated recipes deduct the fat the steps skim '
        '(chinese 991.75 → 832.71, the shanks 613.48 → 575.08 /serving); '
        'memphis (no skim) unchanged', () {
      for (final MapEntry(key: file, value: want) in _totals.entries) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (
            n.status,
            n.caloriesPerServing?.toStringAsFixed(2),
            (batchTotalsOf(n)['energy'] ?? 0).toStringAsFixed(2),
          ),
          want,
          reason: file,
        );
      }
    });

    test('a second compute writes nothing: every row and total of the four '
        'recipes as the first compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(id)!.totalsJson;
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
          isNull,
        );
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
      }
    });
  });

  test('D3b: each share is the protein tracer on the recorded pair — the '
      "raw record's DETAIL, the braised record's HIT (cooked × P raw ÷ (P "
      'cooked × raw)); trans stays gross (167854 prints no 605; 172514 '
      'prints 0.642 against 0.524 — the five columns, as M72)', () async {
    final fdc = FixtureProvider(pending: {...pendingSearches});
    const columns = {
      'energy': '208',
      'fat': '204',
      'saturated': '606',
      'monounsaturated': '645',
      'polyunsaturated': '646',
    };
    final shares = <String>[];
    for (final (raw, query, cooked) in [
      (167853, 'st louis style spareribs', 167854),
      (172513, 'lamb shanks', 172514),
    ]) {
      final r = (await fdc.food(raw))!.nutrientsPer100g;
      final c = (await fdc.search(
        query,
      )).singleWhere((h) => h.fdcId == cooked).nutrientsPer100g!;
      expect(braisedKept[raw]!.keys, columns.keys, reason: '$raw');
      for (final MapEntry(key: column, value: n) in columns.entries) {
        final tracer = c[n]! * r['203']! / (c['203']! * r[n]!);
        expect(braisedKept[raw]![column], closeTo(tracer, 1e-12));
        shares.add(braisedKept[raw]![column]!.toStringAsFixed(6));
      }
      shares.add('trans ${r['605']} → ${c['605']}');
    }
    expect(shares, [
      '0.761918', '0.688373', '0.783760', '0.840178', '0.367141', //
      'trans 0.222 → null',
      '0.924475', '0.871075', '0.795143', '0.829340', '0.889220',
      'trans 0.524 → 0.642',
    ]);
  });

  group('E2b — the marrow guard, gate by gate', skip: skipIfNoCorpus, () {
    test(
      'a marrow record weighs a line whose head is not the bones: '
      '|2 written "1½ pounds marrow" or "1½ pounds bone marrow" (STATED; no '
      'corpus row but |2 sits on a marrow record) is 680.39 g on 169800, '
      'the real line and its singular "1½ pounds marrow bone" (STATED) none',
      () async {
        final (db, _) = _db();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final recipe = loadCorpusRecipe(_potAuFeu);
        final marrow = (await fdc.food(169800))!;
        expect(marrow.description, 'Caribou, bone marrow, raw (Alaska Native)');
        final real = nutritionLines(recipe)[2];
        expect(real.raw, '1½ pounds marrow bones');
        expect(lineGrams(db, real, marrow, recipe: recipe), isNull);
        // STATED (the recorded exception: no corpus line reaches it; 0092|2
        // the source): the singular "1½ pounds marrow bone" — no plural
        // 'bones' word, head 'bone' — gets no grams either: the gate reads
        // the head's key form, never the plural word.
        const single = '1½ pounds marrow bone';
        final one = parseIngredientLine(single);
        final oneLine = IngredientLine(
          raw: single,
          item: one.item,
          amounts: one.amounts,
        );
        expect(
          (one.item, headNounOf(normalizeItem(lineItemOf(oneLine)))),
          ('marrow bone', 'bone'),
        );
        final g1 = lineGrams(db, oneLine, marrow, recipe: recipe);
        expect(
          (g1?.grams.toStringAsFixed(2), g1?.source, g1?.basis),
          (null, null, null),
        );
        // "bone marrow" holds a 'bone' word but its head is 'marrow' (the
        // record's own food): the gate reads the head, never a substring.
        for (final raw in ['1½ pounds marrow', '1½ pounds bone marrow']) {
          final written = parseIngredientLine(raw);
          final g = lineGrams(
            db,
            IngredientLine(
              raw: raw,
              item: written.item,
              amounts: written.amounts,
            ),
            marrow,
            recipe: recipe,
          );
          expect(
            (raw, g?.grams.toStringAsFixed(2), g?.source, g?.basis),
            (
              raw,
              '680.39',
              GramSource.weight,
              'from 1 1/2 pound',
            ),
          );
        }
      },
    );

    test(
      "a step's printed amount reads first: |2 written amount-less \"marrow "
      'bones" and S1 "Place beef, 1½ pounds marrow bones, …" (STATED) is '
      '680.39 g from step 1 on 169800 — the guard sits after the recipe '
      'readers',
      () async {
        // STATED (the recorded exception: no corpus line reaches it): 0092's
        // own |2 and S1 ("Place beef, bones, onion, …"), the line's amount
        // moved into the step that adds it — the order the guard keeps
        // (`stepAmountGrams` before `_bonesNotMarrow`); the arm moved above
        // the recipe readers reads none.
        final (db, _) = _db();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final real = loadCorpusRecipe(_potAuFeu);
        final marrow = (await fdc.food(169800))!;
        final written = parseIngredientLine('marrow bones');
        expect((written.item, written.amounts.length), ('marrow bones', 0));
        final line = IngredientLine(
          raw: 'marrow bones',
          item: written.item,
          amounts: written.amounts,
        );
        const s1 = 'Place beef, bones, onion,';
        expect(real.steps.first.text, contains(s1));
        final recipe = real.copyWith(
          ingredients: [
            for (final g in real.ingredients)
              g.copyWith(
                items: [
                  for (final i in g.items)
                    i.raw == '1½ pounds marrow bones' ? line : i,
                ],
              ),
          ],
          steps: [
            for (final (n, s) in real.steps.indexed)
              n == 0
                  ? s.copyWith(
                      text: s.text.replaceFirst(
                        s1,
                        'Place beef, 1½ pounds marrow bones, onion,',
                      ),
                    )
                  : s,
          ],
        );
        final l = nutritionLines(recipe)[2];
        expect(l.raw, 'marrow bones');
        final g = lineGrams(db, l, marrow, recipe: recipe);
        expect(
          (g?.grams.toStringAsFixed(2), g?.source, g?.basis),
          (
            '680.39',
            GramSource.weight,
            'from step 1: 1½ pounds (no amount on the line)',
          ),
        );
      },
    );

    test("the converse, REAL: tortilla-soup|3's head is 'bone' too (\"… or 4 "
        'bone-in"), on 2646170 — no marrow record — weighed as at v85 (the '
        "census: 2 of the corpus's 14,567 lines read the head 'bone', this "
        'one and |2)', () async {
      final (db, _) = _db();
      final fdc = FixtureProvider(pending: {...pendingSearches});
      final recipe = loadCorpusRecipe(_tortilla);
      final line = nutritionLines(recipe)[3];
      expect(headNounOf(normalizeItem(lineItemOf(line))), 'bone');
      final g = lineGrams(db, line, await fdc.food(2646170), recipe: recipe);
      expect(
        (g?.grams.toStringAsFixed(2), g?.source, g?.basis),
        (
          '442.25',
          GramSource.weight,
          'from 1 1/2 pound × 0.65 edible · approximate (USDA AH-102 item 584: '
              'chicken breast, raw → meat 65 % (50–77))',
        ),
      );
    });

    // The owner gate (verify4 D1): every negative of the head gate above
    // has the head 'marrow', so a gate refusing only 'marrow' passed them
    // all. REAL: the cached 'bone-in chicken pieces' answer holds 169800 at
    // index 5 (snapshot 29 and the fixture) — a person can pick it on six
    // corpus lines (0133|0, 0141|15, 0142|1, 0631|13, 0632|17, 0633|6).
    test("the converse, REAL, on the marrow record itself: 0133|0's bone-in "
        "chicken pieces (head 'chicken') on 169800 — weighed as at v85, "
        "2267.96 g (mutant: the head gate reading 'not marrow' instead of "
        "'bone' — null)", () async {
      final (db, _) = _db();
      final fdc = FixtureProvider(pending: {...pendingSearches});
      final recipe = loadCorpusRecipe(
        '0133-slow-roasted-chicken-parts-with-shallot-garlic-pan-sauce.yaml',
      );
      final line = nutritionLines(recipe)[0];
      expect(
        line.raw,
        '5 pounds bone-in chicken pieces (4 split breasts and 4 leg '
        'quarters), trimmed',
      );
      expect(headNounOf(normalizeItem(lineItemOf(line))), 'chicken');
      final marrow = (await fdc.food(169800))!;
      expect(marrow.description, contains('bone marrow'));
      final g = lineGrams(db, line, marrow, recipe: recipe);
      expect(
        (g?.grams.toStringAsFixed(2), g?.source, g?.basis),
        ('2267.96', GramSource.weight, 'from 5 pound · no edible yield read'),
      );
    });

    test("a person's Confirm of |2 counts nothing (v85: its 680.39 g, 5,347.87 "
        "kcal, 891.31 more per serving), the basis the guard's; grams typed "
        'count and say so (STATED: 200 g typed, 262.00 more)', () async {
      for (final (body, status, grams, basis, added) in [
        (const {'confirmed': true}, 'confirmed', null, _marrow, '0.00'),
        (
          const {'confirmed': true, 'grams': 200.0},
          'confirmed',
          '200.00',
          'entered by hand',
          '262.00',
        ),
      ]) {
        final (db, _) = _db();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final recipe = await _compute(db, fdc, loadCorpusRecipe(_potAuFeu));
        final before = db.nutritionFor(recipe.id)!.caloriesPerServing!;
        await applyMatchOverride(db, fdc, recipe, 2, {
          'raw': '1½ pounds marrow bones',
          ...body,
        });
        final row = _row(db, recipe.id, 2);
        expect(
          (
            row.fdcId,
            row.status,
            row.grams?.toStringAsFixed(2),
            gramBasisFor(
              db,
              nutritionLines(recipe)[2],
              row,
              recipe: recipe,
            ),
            (db.nutritionFor(recipe.id)!.caloriesPerServing! - before)
                .toStringAsFixed(2),
          ),
          (169800, status, grams, basis, added),
          reason: '$body',
        );
      }
    });
  });

  // RULE C: E2b adds no step reader — a per-weighing predicate in
  // `lineGrams` (the record's description first, the head only on a marrow
  // record) and its basis in `gramBasisFor` on a row with no grams; it
  // memoizes nothing. The cap shapes (STATED, the house's exception: 400
  // repeated real lines under 0092's real steps): TRUE — 400 × "1½ pounds
  // marrow bones" (the cached 'marrow bones' answer: every row on 169800,
  // none weighed); QUIET — 400 × tortilla-soup|3's line (head 'bone', on
  // 2646170: every row weighed). Each through the compute (matchAndCompute)
  // and the GET (gramBasisFor on every stored row). Counts: each shape's
  // map exactly (the process-wide `names` aside) — QUIET equal to base
  // 785c568's; TRUE base's less the five families a weighed row reached
  // (`memo:skinSentences` and `allSentences` — the skin trip `lineGrams`
  // reads before resolving — and three readers only a weighed row
  // reaches, `memo:cutShare`, `memo:panFatLines` and
  // `memo:liftedFromMarinade`): the guard returns first. Clocks (fix86, two runs each, base → tree): TRUE 240 / 243 →
  // 209 / 177 ms, QUIET 768 / 748 → 801 / 766 ms — each under the
  // backstop.
  group('RULE C, the marrow guard at the caps', skip: skipIfNoCorpus, () {
    final base = loadCorpusRecipe(_potAuFeu);
    final shapes = {
      'E2b-TRUE': ('1½ pounds marrow bones', 169800, 0),
      'E2b-QUIET': (
        '2 bone-in, skin-on split chicken breasts (about 1½ pounds) or 4 bone-in, skin-on chicken thighs (about 1¼ pounds), skin removed and trimmed',
        2646170,
        400,
      ),
    };
    for (final MapEntry(key: shape, value: (raw, fdcId, weighed))
        in shapes.entries) {
      test('$shape: 400 rows on $fdcId, $weighed weighed; the counts exact, '
          'within the backstop', () async {
        final (db, _) = _db();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final r = base.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                for (var i = 0; i < 400; i++)
                  () {
                    final p = parseIngredientLine(raw);
                    return IngredientLine(
                      raw: raw,
                      item: p.item,
                      prep: p.prep,
                      amounts: p.amounts,
                    );
                  }(),
              ],
            ),
          ],
        );
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        expect(await matchAndCompute(db, fdc, stored), isNull);
        final rows = db.ingredientMatchesFor(stored.id);
        final lines = nutritionLines(stored);
        final bases = {
          for (final row in rows)
            gramBasisFor(db, lines[row.position], row, recipe: stored),
        };
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts)..remove('names');
        expectBounded(stored, counts, shape);
        expect(
          (
            rows.length,
            rows.where((m) => m.fdcId == fdcId).length,
            rows.where((m) => m.grams != null).length,
            fdcId == 169800 ? bases.single : bases.length,
          ),
          (400, 400, weighed, fdcId == 169800 ? _marrow : 1),
          reason: shape,
        );
        expect(counts, _capCounts[shape], reason: shape);
        expect(ms, lessThan(backstopMs), reason: shape);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// Each cap shape's counts on the tree (fix86 cost_tip.log, the second run;
/// the process-wide `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'E2b-TRUE': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 30,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 350,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
  },
  'E2b-QUIET': {
    'indexes': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 30,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 350,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:setsAsidePieces': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:cutShare': 1,
    'memo:panFatLines': 1,
    'memo:liftedFromMarinade': 1,
  },
};
