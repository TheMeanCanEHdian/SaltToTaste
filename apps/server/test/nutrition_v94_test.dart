// Matcher v94 (batch M92; matcherVersion 89 — the braised turkey; prep51
// design_v2 §1 Q8 option (b″) / §2 M92, ruled by the owner 2026-10-29;
// zero requests): no braised turkey record is cached, so two `braisedKept`
// keys read the ROASTED same-cut SR pairs by the protein tracer — 171093
// "Turkey, all classes, breast, meat and skin, raw" (DETAIL) → SR 171492
// "…, cooked, roasted" (a HIT in 'bone-in turkey breast') and 171533
// "Turkey, retail parts, thigh, meat and skin, raw" (DETAIL) → SR 171137
// "…, cooked, roasted" (a HIT in 'bone-in turkey thigh') — behind M72's
// recipe-wide gate AND a NEW line-order gate for these two keys only
// (`_lineOrderGated`): the row's line is named strictly before the recipe's
// first defatting sentence (`_firstDefatOf`, `memo:defatsLiquid`'s one
// scan). The doctrine: a served breast is never deducted —
// turkey-and-gravy-for-a-crowd|16, first named in S6 after S4's fat
// separator, stays gross. The rows stay GROSS; the totals deduct (M84's D3b
// form). M72's and M84's keys carry no gate. Every whole-recipe figure is a
// fresh compute on the recorded fixtures (FixtureProvider) and equals the
// v94 replay of snapshot 30 (fix94 gate1) on every pinned field. Never the
// network. Every corpus line is real.
// STATED constructions (no corpus line reaches the gate's boundary — the
// census, pinned below: the corpus's 12 rows on the two records, 5 of them
// in the 3 recipes with a defatting sentence, each first named in a step
// before it or, the crowd's breast, in a later step): braised-turkey's REAL
// steps with S4's "the breast registers" written "the white meat registers"
// (the breast line then unnamed) and the breast named once more — in S5,
// before or in its real "Transfer the liquid to a fat separator …", or in
// S7 ("Carve the breast"), after it, alone or before a second defatting
// sentence; the cap shapes' 400 repeated real lines (the house's cap-shape
// exception) under hostile steps.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _braised = '0172-braised-turkey.yaml';
const _crowd = '0163-turkey-and-gravy-for-a-crowd.yaml';
const _confit = '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml';

const _breast =
    '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, trimmed';

/// Every corpus row on the two keyed records (the v93 replay's 12), the
/// record, and whether the totals deduct it (the line named before the
/// first defatting sentence; the seven last: no defatting sentence).
const List<(String, int, String, int, bool)> _corpusRows = [
  (_braised, 2, _breast, 171093, true),
  (_braised, 3, '4 pounds turkey drumsticks and thighs, trimmed', 171533, true),
  (_crowd, 12, '4 (1½- to 2-pound) turkey leg quarters, trimmed', 171533, true),
  (
    _crowd,
    16,
    '2 (5- to 6-pound) bone-in turkey breasts, trimmed',
    171093,
    false,
  ),
  (_confit, 5, '4 pounds bone-in turkey thighs', 171533, true),
  (
    '0162-roast-whole-turkey-breast-with-gravy.yaml',
    0,
    '1 (5- to 7- pound) bone-in turkey breast',
    171093,
    false,
  ),
  (
    '1125-roast-whole-turkey-breast-with-gravy.yaml',
    0,
    '1 (5- to 7-pound) bone-in turkey breast',
    171093,
    false,
  ),
  ('0162-slow-roasted-turkey-with-gravy.yaml', 6, _breast, 171093, false),
  (
    '0162-slow-roasted-turkey-with-gravy.yaml',
    7,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171533,
    false,
  ),
  (
    '0173-turkey-breast-en-cocotte-with-pan-gravy.yaml',
    0,
    '1 (6- to 7-pound) whole bone-in turkey breast',
    171093,
    false,
  ),
  (
    '0176-grillroasted-boneless-turkey-breast.yaml',
    1,
    '1 (5- to 7-pound) whole bone-in turkey breast, trimmed',
    171093,
    false,
  ),
  (
    '1126-porchetta-style-turkey-breast.yaml',
    8,
    '1 (7- to 8-pound) bone-in turkey breast',
    171093,
    false,
  ),
];

/// [recipe] with the first [from] of step [step] written [to].
Recipe _rewrite(Recipe recipe, int step, String from, String to) {
  expect(recipe.steps[step].text, contains(from));
  return recipe.copyWith(
    steps: [
      for (final (i, s) in recipe.steps.indexed)
        i == step ? s.copyWith(text: s.text.replaceFirst(from, to)) : s,
    ],
  );
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

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v94-');
  final db = SaltDatabase.open(
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
  return db;
}

void main() {
  test(
    "matcherVersion 92 (v94 set it to 89, batch M92: three recipes' totals move)",
    () {
      // RE-PIN (M93 batch, v95): matcherVersion 90 (was 89).
      // RE-PIN (M94 batch, v96): matcherVersion 91 (was 90).
      // RE-PIN (M95 batch, v97): matcherVersion 92 (was 91).
      expect(matcherVersion, 92);
    },
  );

  test('the shares: the protein tracer on the recorded pairs — the raw '
      "record's DETAIL, the roasted record's HIT (cooked × P raw ÷ (P cooked "
      "× raw)); the thigh's saturated share above 1, kept; trans stays "
      'gross (171093 prints no 605; 171533 → 171137 0.106 → 0.138)', () async {
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
      (171093, 'bone-in turkey breast', 171492),
      (171533, 'bone-in turkey thigh', 171137),
    ]) {
      final r = (await fdc.food(raw))!.nutrientsPer100g;
      final c = (await fdc.search(
        query,
      )).singleWhere((h) => h.fdcId == cooked).nutrientsPer100g!;
      expect(braisedKept[raw]!.keys, columns.keys, reason: '$raw');
      shares.add('P ${r['203']} → ${c['203']}');
      for (final MapEntry(key: column, value: n) in columns.entries) {
        final tracer = c[n]! * r['203']! / (c['203']! * r[n]!);
        expect(braisedKept[raw]![column], closeTo(tracer, 1e-12));
        shares.add(braisedKept[raw]![column]!.toStringAsFixed(6));
      }
      shares.add('trans ${r['605']} → ${c['605']}');
    }
    expect(shares, [
      'P 21.89 → 28.7',
      '0.918176', '0.805091', '0.838590', '0.702503', '0.827043', //
      'trans null → null',
      'P 19.54 → 24.0',
      '0.925419', '0.844387', '1.010031', '0.976239', '0.978725',
      'trans 0.106 → 0.138',
    ]);
  });

  group('the gate on the corpus rows (no compute)', skip: skipIfNoCorpus, () {
    test('each of the 12 rows on 171093 / 171533 deducts exactly where its '
        'line is named before the first defatting sentence: braised-turkey|2 '
        "|3, crowd|12, confit|5; the crowd's served breast |16 (named in S6, "
        "after S4's fat separator) and the seven rows of recipes that "
        'defat nothing stay gross; with no position (the flag) none '
        'deducts', () {
      for (final (file, position, raw, fdcId, deducts) in _corpusRows) {
        final recipe = loadCorpusRecipe(file);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          braisedKeptOf(raw, fdcId, recipe, position: position),
          deducts ? braisedKept[fdcId] : isNull,
          reason: reason,
        );
        expect(braisedKeptOf(raw, fdcId, recipe), isNull, reason: reason);
        expect(trimStandInFlagOf(raw, fdcId, recipe: recipe), isNull);
      }
    });

    test("the header's census: of the 12 rows, 5 sit in the 3 recipes whose "
        'steps defat (the recipe-wide gate, read through the ungated D3b key '
        "167853), each line's first naming step (before or after the first "
        "defatting sentence: the gate pin above); braised-turkey's two lines "
        'first named in S4, never S2', () {
      final census = <String>[];
      for (final (file, position, raw, _, _) in _corpusRows) {
        final recipe = loadCorpusRecipe(file);
        if (braisedKeptOf(raw, 167853, recipe) == null) {
          continue;
        }
        final heads = [
          for (final line in nutritionLines(recipe))
            headNounOf(normalizeItem(lineItemOf(line))),
        ];
        final head = heads[position]!;
        // No other line shares the head, so the line's mentions are the
        // head's naming (`_lineMentionsOf`'s unique arm).
        expect(heads.where((h) => h == head), hasLength(1));
        final first = namingForTest(recipe, head).first.$1 + 1;
        census.add('$file|$position S$first');
      }
      expect(census, [
        '$_braised|2 S4',
        '$_braised|3 S4',
        '$_crowd|12 S2',
        '$_crowd|16 S6',
        '$_confit|5 S1',
      ]);
    });

    test("M72's and M84's keys carry no line-order gate: their real rows "
        'deduct with no position (braised-beef-short-ribs|0 on 170827, '
        'chinese-style-barbecued-spareribs|9 on 167853, '
        'braised-lamb-shanks|0 on 172513)', () {
      for (final (file, position, fdcId) in const [
        ('0087-braised-beef-short-ribs.yaml', 0, 170827),
        ('0538-chinese-style-barbecued-spareribs.yaml', 9, 167853),
        (
          '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml',
          0,
          172513,
        ),
      ]) {
        final recipe = loadCorpusRecipe(file);
        final raw = nutritionLines(recipe)[position].raw;
        expect(braisedKeptOf(raw, fdcId, recipe), braisedKept[fdcId]);
        expect(
          braisedKeptOf(raw, fdcId, recipe, position: position),
          braisedKept[fdcId],
        );
      }
    });
  });

  // STATED (no corpus line reaches the boundary — the header's census):
  // braised-turkey's REAL steps, S4's one naming of the breast ("the breast
  // registers 160 degrees") written "the white meat registers", and the
  // breast named once more where each case says. S5's fourth sentence, the
  // REAL "Transfer the liquid to a fat separator and allow to settle for 5
  // minutes.", is the first defatting sentence (step 5, sentence 4). The
  // thighs line (|3, named in S4's "legs and thighs") deducts in every case.
  group('the line-order gate, gate by gate', skip: skipIfNoCorpus, () {
    final turkey = loadCorpusRecipe(_braised);
    Recipe unnamed() => _rewrite(
      loadCorpusRecipe(_braised),
      3,
      'the breast registers',
      'the white meat registers',
    );
    Map<String, double>? kept(Recipe r, int k) => braisedKeptOf(
      nutritionLines(r)[k].raw,
      k == 2 ? 171093 : 171533,
      r,
      position: k,
    );

    test("the breast line's head is 'breast', the thighs line's named in S4 "
        '(the real recipe: both deduct)', () {
      final line = nutritionLines(turkey)[2];
      expect(headNounOf(normalizeItem(lineItemOf(line))), 'breast');
      expect(kept(turkey, 2), braisedKept[171093]);
      expect(kept(turkey, 3), braisedKept[171533]);
    });

    for (final (name, edits, deducts) in [
      (
        'never named: gross (mutant: an unnamed line read as before)',
        const <(int, String, String)>[],
        false,
      ),
      (
        'named BEFORE the defatting sentence, in its own step (S5\'s "Discard '
            'the vegetables from under the breast."): deducts',
        const [
          (
            4,
            'Discard the vegetables.',
            'Discard the vegetables from under the breast.',
          ),
        ],
        true,
      ),
      (
        'named IN the defatting sentence ("Transfer the liquid from the '
            'breast to a fat separator …"): gross — the boundary, the '
            'conservative side (mutant: `_before` read as at-or-before)',
        const [
          (
            4,
            'Transfer the liquid to a fat separator',
            'Transfer the liquid from the breast to a fat separator',
          ),
        ],
        false,
      ),
      (
        'named AFTER it (S7 "Carve the breast and serve …"): gross',
        const [(6, 'Carve the turkey', 'Carve the breast')],
        false,
      ),
      (
        'named between the FIRST defatting sentence and a second (S7 "Carve '
            'the breast … Skim the fat from the gravy."): gross — the first '
            'one gates (mutant: the last defatting sentence read)',
        const [
          (6, 'Carve the turkey', 'Carve the breast'),
          (
            6,
            'passing the gravy separately.',
            'passing the gravy separately. Skim the fat from the gravy.',
          ),
        ],
        false,
      ),
    ]) {
      test(name, () {
        var r = unnamed();
        for (final (step, from, to) in edits) {
          r = _rewrite(r, step, from, to);
        }
        expect(kept(r, 2), deducts ? braisedKept[171093] : isNull);
        expect(kept(r, 3), braisedKept[171533]);
      });
    }

    test('memo:defatsLiquid: the first defatting sentence read ONCE per index '
        'for both rows (the same scan M72 made); with no position nothing is '
        'read — not even the index', () {
      final r = loadCorpusRecipe(_braised);
      stepIndexCounts.clear();
      expect(braisedKeptOf(_breast, 171093, r), isNull);
      expect(stepIndexCounts, isEmpty);
      expect(kept(r, 2), braisedKept[171093]);
      expect(kept(r, 3), braisedKept[171533]);
      expect(kept(r, 2), braisedKept[171093]);
      expect(stepIndexCounts['memo:defatsLiquid'], 1);
      expect(stepIndexCounts['indexes'], 1);
    });
  });

  group('matcher v94 (batch M92) — whole recipes', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      db = _db();
      fdc = FixtureProvider(pending: {...pendingSearches});
      for (final file in [_braised, _crowd, _confit]) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    test(
      'the rows stay GROSS (the v93 rows exactly): record, grams, energy',
      () {
        for (final (file, position, fdcId, grams, kcal) in const [
          (_braised, 2, 171093, '1817.11', '2852.86'),
          (_braised, 3, 171533, '1360.78', '2190.85'),
          (_crowd, 12, 171533, '2254.35', '3629.51'),
          (_crowd, 16, 171093, '3331.37', '5230.25'),
          (_confit, 5, 171533, '1487.78', '2395.33'),
        ]) {
          final id = recipes[file]!.id;
          final row = db
              .ingredientMatchesFor(id)
              .singleWhere((m) => m.position == position);
          expect(
            (
              row.fdcId,
              row.status,
              row.hold,
              row.gramSource,
              row.grams?.toStringAsFixed(2),
              (kcalPer100g(knownFood(db, fdcId)!) * row.grams! / 100)
                  .toStringAsFixed(2),
            ),
            (fdcId, 'auto', null, 'weight', grams, kcal),
            reason: '$file|$position',
          );
        }
      },
    );

    test('the totals deduct (v93 → v94 per serving): braised-turkey 575.75 → '
        '536.07 (|2 −233.43, |3 −163.40), the crowd 568.27 → 553.24 (|12 '
        '−270.69; |16 gross), confit 510.86 → 481.09 (|5 −178.65); the '
        "thigh's saturated share above 1 adds", () {
      for (final (file, perServing, energy, fat, saturated) in const [
        (_braised, '536.07', '5360.70', '260.03', '92.23'),
        (_crowd, '553.24', '9958.24', '526.32', '189.69'),
        (_confit, '481.09', '2886.52', '116.58', '35.99'),
      ]) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        final totals = batchTotalsOf(n);
        expect(
          (
            n.status,
            n.caloriesPerServing?.toStringAsFixed(2),
            totals['energy']!.toStringAsFixed(2),
            totals['fat']!.toStringAsFixed(2),
            totals['saturated']!.toStringAsFixed(2),
          ),
          ('complete', perServing, energy, fat, saturated),
          reason: file,
        );
      }
    });

    test('a second compute writes nothing: every row and total of the three '
        'recipes as the first compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (
              m.position,
              m.fdcId,
              m.confidence,
              m.grams,
              m.gramSource,
              m.status,
              m.hold,
            ),
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

  // RULE C (no new sentence scan: `memo:defatsLiquid`'s one scan keeps where
  // it stopped; the gate reads `_lineMentionsOf`, the per-head naming memo).
  // STATED: 400 copies of confit|5's REAL line (the cap-shape exception)
  // under 120 × 10,000-character steps — every sentence names the thighs —
  // and one step of fat-separator sentences, LAST (TRUE: every row named
  // before it, deducted) or FIRST (QUIET: every row named after it, gross).
  // Base vs tip (fix94 cost probe, the same shapes): compute + 1
  // memo:defatsLiquid, the GET identical (the flag passes no position), the
  // recompute + 1 memo:defatsLiquid, + 1 memo:naming and the index's words
  // (215,089, the `_StepIndex.words` build the compute and the GET already
  // make) — the counts below are the tip's, exactly. M72's own cap shape
  // (nutrition_v26_cost_test, 400 short-rib lines) counts EQUAL on base and
  // tip on all three paths.
  group('RULE C, the line-order gate at the caps', skip: skipIfNoCorpus, () {
    for (final (shape, loud, energy) in const [
      ('TRUE', true, '886673.30'),
      ('QUIET', false, '958131.45'),
    ]) {
      test('$shape: 400 rows on 171533, the first defatting sentence '
          '${loud ? 'after' : 'before'} every naming; the counts exact, '
          'within the backstop', () async {
        final base = loadCorpusRecipe(_confit);
        const raw = '4 pounds bone-in turkey thighs';
        expect(nutritionLines(base)[5].raw, raw);
        final r = capped(
          base,
          [for (var i = 0; i < capLines; i++) raw],
          [
            for (var i = 0; i < capSteps; i++)
              fill(
                (loud ? i == capSteps - 1 : i == 0)
                    ? 'Pour the liquid into a fat separator. '
                    : 'Arrange the turkey thighs in the dish. ',
                capStep,
              ),
          ],
        );
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        Future<void> timed(String step, Future<Object?> Function() run) async {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts)..remove('names');
          expectBounded(r, counts, '$shape $step');
          expect(counts, _capCounts['$shape $step'], reason: '$shape $step');
          expect(ms, lessThan(backstopMs), reason: '$shape $step');
        }

        await timed('compute', () => matchAndCompute(db, provider, stored()));
        await timed('GET', () => matchesBody(db, provider, stored()));
        await timed('recompute', () async => recomputeTotals(db, stored()));
        final rows = db.ingredientMatchesFor(r.id);
        expect(rows.where((m) => m.fdcId == 171533).length, 400);
        expect(
          batchTotalsOf(db.nutritionFor(r.id)!)['energy']!.toStringAsFixed(2),
          energy,
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// Each cap shape's counts on the tree (fix94 cost probe; the
/// process-wide `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'TRUE compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 30847,
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
    'words': 215089,
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
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
  },
  'TRUE GET': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 30847,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 215089,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:leftInBowl': 1,
    'memo:dips': 1,
    'memo:cutShare': 1,
    'memo:keptSolids': 1,
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:panFatLines': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:liftedFromMarinade': 1,
  },
  'TRUE recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 30847,
    'memo:leftInBowl': 1,
    'heads': 1,
    'memo:keptSolids': 1,
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
    'words': 215089,
    'memo:naming': 1,
  },
  'QUIET compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 30847,
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
    'words': 215089,
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
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
  },
  'QUIET GET': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 30847,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 215089,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:leftInBowl': 1,
    'memo:dips': 1,
    'memo:cutShare': 1,
    'memo:keptSolids': 1,
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:panFatLines': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:liftedFromMarinade': 1,
  },
  'QUIET recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 30847,
    'memo:leftInBowl': 1,
    'heads': 1,
    'memo:keptSolids': 1,
    // RE-PIN (M94 batch, v96): + the browning-fat reader's memo, once
    // per index (every `_m52Plan` reads it).
    'memo:browningFat': 1,
    'memo:defatsLiquid': 1,
    'words': 215089,
    'memo:naming': 1,
  },
};
