// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v74 (batch M74 — the brisket flats; matcherVersion 72; prep50
// design_v2 §2 M74, the owner's Q1, 2026-10-15; zero requests; reach PRE-Q18
// — both rules read a recipe's own steps): Q1 (b) 0091's S1 "Trim fat on
// surface of brisket to ⅛ inch." moves its 0" flat (168743) to the ⅛-inch
// flat 173128 (engine `trimDepthRecord` + `_trimsFatTo`), deducted at its
// braised pair 173128 → 173130 with NO skim (the owner's ruling; the flag
// says the served cup is not counted); Q1 (a′) onion-braised's 0" flat at
// its own pair 168743 → SR 169440 (engine `braisedKept`), behind M72's
// `_defatsLiquid` (S6 skims the fat). THE INVARIANT: the deduction
// (`recomputeTotals`), the basis (`gramBasisFor`) and the GET sheet
// (`candidatesForLine`, which now takes the recipe) read the same recipe.
// Every row value is the fresh compute of the WHOLE recipe over recorded
// real FDC answers (FixtureProvider; no fixture added) and equals the v74
// replay of snapshot 27 (rp43) on every pinned field EXCEPT where the
// fixtures hold a record as a search hit and the snapshot its detail (the
// M72 / M73 note; identical on the v73 tree): the tacos' flank steak
// (Foundation 2646175: 1,208.82 here, 1,208.08 in the replay; the recipe
// 586.89 / 2,347.57 here, 586.71 / 2,346.84), 0090's
// totals (592.11 / 4,736.91 here, 592.10 / 4,736.82) and 0091's batch
// (5,024.10 here, 5,024.06; the gross rows 6,964.56 vs 6,964.52 — the
// brisket's 1,940.46 deduction is the same). Never the network.
// Synthesized, STATED: the step-less copy of 0091 (pre-Q18: no step, no
// move); the hostile-free reader inputs are real sentences.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _corned = '0091-home-corned-beef-with-vegetables.yaml';
const _onion = '0223-onion-braised-beef-brisket.yaml';
const _newEngland = '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml';
const _pomegranate =
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
const _barbecued =
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml';
const _tacos = '0582-tacos-al-carbon-grilled-steak-tacos.yaml';
const _files = [
  _newEngland,
  _corned,
  _onion,
  _pomegranate,
  _barbecued,
  _tacos,
];

/// The design's step regex (§2 M74), its `[^.]*` pair kept: the reference
/// [trimsFatSentence] answers as.
final _design = RegExp(
  r'^\s*trim fat\b[^.]*\bbrisket\b[^.]*\bto (⅛|¼)[- ]inch\b',
);

const _cure =
    "the steps cure and rinse the brisket — the cure's sodium is not counted; "
    'a rinsed cure counts 0 g, CP9';

/// §2 M74's flag texts, verbatim.
const _cornedFlag =
    "approximate (the steps trim the fat cap to ⅛ inch (step 1) — USDA's "
    '⅛-inch flat; its braised pair 173128 → 173130 keeps 67.6 % of the '
    'energy and 55.4 % of the fat by the protein tracer — the fat that '
    'renders into the cooking liquid, deducted (no step skims it: the steps '
    'serve 1 cup of the 2 quarts and the broth the vegetables cook in, not '
    'counted); $_cure)';
const _onionFlag =
    "approximate (USDA's braised pair 168743 → 169440 (flat, 0\" trim) "
    'keeps 82.0 % of the energy and 58.8 % of the fat by the protein tracer '
    '— the fat the steps skim, deducted; the steps name a fat layer the 0" '
    "record does not carry — the cap's depth is not printed)";

/// (file, position, raw, fdc id, grams, gross kcal, basis) — the two rows
/// M74 moves (0091|0: record, kcal, basis; onion-braised|0: basis only).
const _reach = [
  (
    _corned,
    0,
    '1 (4½- to 5-pound) beef brisket, flat cut',
    173128,
    '2154.56',
    '5989.68',
    'from the printed weight (4½–5 lb, the midpoint) · $_cornedFlag',
  ),
  (
    _onion,
    0,
    '1 (4- to 5-pound) beef brisket, preferably flat cut',
    168743,
    '2041.16',
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint) · $_onionFlag',
  ),
];

/// The negatives, as the v73 replay (= v74's) holds them.
const _negatives = [
  (
    _newEngland,
    6,
    '1 (4- to 5-pound) beef brisket, flat cut, trimmed',
    168743,
    '2041.16',
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint) · approximate ($_cure)',
  ),
  (
    _pomegranate,
    0,
    '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch',
    173128,
    '2041.16',
    '5674.44',
    'from the printed weight (4–5 lb, the midpoint) · approximate (the '
        "printed ¼-inch fat cap counted at USDA's ⅛-inch flat trim; USDA's "
        'braised pair 173128 → 173130 keeps 67.6 % of the energy and 55.4 % '
        'of the fat by the protein tracer — the fat the steps skim, deducted)',
  ),
  (
    _tacos,
    4,
    '1 (1½- to 1¾-pound) flank steak',
    2646175,
    '737.09',
    '1208.82',
    'from the printed weight (1½–1¾ lb, the midpoint)',
  ),
];

/// (file, status, per serving, stored batch energy) after the compute.
const _totals = [
  (_newEngland, 'complete', '592.11', '4736.91'),
  (_corned, 'complete', '628.01', '5024.10'),
  (_onion, 'complete', '588.82', '3532.95'),
  (_pomegranate, 'complete', '794.35', '4766.11'),
  (_barbecued, 'complete', '697.49', '12554.79'),
  // 586.71 / 2,346.84 in the replay (the flank steak's hit, above).
  (_tacos, 'partial', '586.89', '2347.57'),
];

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    expect(matcherVersion, 72);
  });

  test("braisedKept[168743]: SR 169440's shares by the protein tracer "
      "(cooked × P raw ÷ (P cooked × raw)), the design's five", () {
    expect(braisedKept.keys.toSet(), {173128, 168664, 168743, 170827});
    // Snapshot 27's hits in the cached 'beef brisket' answer: P 20.2 → 32.2,
    // E 169 → 221, F 9.86 → 9.24, sat 3.7 → 3.64, mono 4.77 → 3.98, poly
    // 0.398 → 0.341 (169440 publishes no trans: gross, as M72's).
    expect(braisedKept[168743], {
      'energy': 221 * 20.2 / (32.2 * 169),
      'fat': 9.24 * 20.2 / (32.2 * 9.86),
      'saturated': 3.64 * 20.2 / (32.2 * 3.7),
      'monounsaturated': 3.98 * 20.2 / (32.2 * 4.77),
      'polyunsaturated': 0.341 * 20.2 / (32.2 * 0.398),
    });
    expect(
      [for (final v in braisedKept[168743]!.values) v.toStringAsFixed(6)],
      ['0.820354', '0.587883', '0.617156', '0.523432', '0.537486'],
    );
  });

  test("the step reader answers as the design's regex on the real "
      "sentences: 0091 S1 prints ⅛; the tacos' steak trim names no brisket; "
      'a depth-less or mid-step trim reads nothing', () {
    for (final (sentence, depth) in const [
      ('Trim fat on surface of brisket to ⅛ inch.', '⅛'),
      // 0582 S1 (a steak, no brisket).
      ('Trim fat deposits on steak to ⅛-inch thickness.', null),
      // 0091 S7 (no "trim fat" opening).
      (
        'While vegetables cook, transfer beef to carving board and slice ¼ inch thick against grain.',
        null,
      ),
    ]) {
      final s = sentence.toLowerCase();
      expect(trimsFatSentence(s), depth, reason: sentence);
      expect(_design.firstMatch(s)?[1], depth, reason: sentence);
    }
  });

  group('matcher v74 (batch M74)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    Future<Recipe> compute(SaltDatabase db, Recipe recipe) async {
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      final stored = db.recipeByIdOrSlug(recipe.id)!.recipe;
      for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
        expect(
          await matchAndCompute(
            db,
            provider,
            nutritionRecipeOf(db, key)!.recipe,
          ),
          isNull,
        );
      }
      expect(await matchAndCompute(db, provider, stored), isNull);
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    SaltDatabase library(String prefix) {
      final dir = Directory.systemTemp.createTempSync(prefix);
      final opened = SaltDatabase.open(
        ServerConfig(
          dataDir: dir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      addTearDown(() {
        opened.dispose();
        dir.deleteSync(recursive: true);
      });
      return opened;
    }

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v74-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      for (final file in _files) {
        recipes[file] = await compute(db, loadCorpusRecipe(file));
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    String kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine l) =>
        (kcalPer100g(knownFood(db, row.fdcId!, line: l)!) * row.grams! / 100)
            .toStringAsFixed(2);

    test('M74 moves exactly its two rows (0091|0 to the ⅛-inch flat, '
        "onion-braised|0's basis); the negatives keep v73's", () {
      for (final (file, position, raw, fdcId, grams, kcal, basis) in [
        ..._reach,
        ..._negatives,
      ]) {
        final line = nutritionLines(recipes[file]!)[position];
        final row = rowIn(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(db, row, line), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipes[file]),
          basis,
          reason: reason,
        );
      }
      // The whole brisket at M72's share (its line prints the depth).
      final whole = rowIn(_barbecued, 10);
      expect(whole.fdcId, 168664);
      expect(
        gramBasisFor(
          db,
          nutritionLines(recipes[_barbecued]!)[10],
          whole,
          recipe: recipes[_barbecued],
        ),
        endsWith('the fat that renders into the separator, deducted)'),
      );
      // 0091's cure lines stay discarded at 0 g (Q2 (c)).
      for (final position in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final row = rowIn(_corned, position);
        expect(row.gramSource, 'discarded', reason: '$position');
        expect(row.grams, 0, reason: '$position');
      }
    });

    test('the totals: 0091 628.01 and onion-braised 588.82 per serving; '
        '0090, 0224, 0595 and the tacos unchanged', () {
      for (final (file, status, perServing, energy) in _totals) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (
            n.status,
            n.caloriesPerServing?.toStringAsFixed(2),
            (batchTotalsOf(n)['energy'] ?? 0).toStringAsFixed(2),
          ),
          (status, perServing, energy),
          reason: file,
        );
      }
    });

    test('the deductions by hand: 0091 5,989.68 × (1 − 0.676033) = '
        "1,940.46 kcal (no skim — the owner's Q1 (b)); onion-braised "
        "3,449.57 × (1 − 0.820354) = 619.70 beside its wine's Q25 165.28", () {
      double gross(String file) => [
        for (final r in db.ingredientMatchesFor(recipes[file]!.id))
          if (r.fdcId != null && (r.grams ?? 0) > 0)
            kcalPer100g(
                  knownFood(
                    db,
                    r.fdcId!,
                    line: nutritionLines(recipes[file]!)[r.position],
                  )!,
                ) *
                r.grams! /
                100,
      ].fold(0, (n, k) => n + k);
      double stored(String file) =>
          batchTotalsOf(db.nutritionFor(recipes[file]!.id)!)['energy']!;
      double row(String file) {
        final r = rowIn(file, 0);
        return kcalPer100g(
              knownFood(db, r.fdcId!, line: nutritionLines(recipes[file]!)[0])!,
            ) *
            r.grams! /
            100;
      }

      // The replay's KCAL CHECK lines: rows 6,964.52 (6,964.56 over the
      // fixtures) / 4,317.93 gross.
      expect(gross(_corned).toStringAsFixed(2), '6964.56');
      expect(gross(_onion).toStringAsFixed(2), '4317.93');
      final corned = row(_corned) * (1 - braisedKept[173128]!['energy']!);
      expect(corned.toStringAsFixed(2), '1940.46');
      expect(
        (gross(_corned) - stored(_corned)).toStringAsFixed(2),
        corned.toStringAsFixed(2),
      );
      final onion = row(_onion) * (1 - braisedKept[168743]!['energy']!);
      expect(onion.toStringAsFixed(2), '619.70');
      expect(
        (gross(_onion) - stored(_onion) - onion).toStringAsFixed(2),
        '165.28',
      );
    });

    test('THE INVARIANT on 0091 — the deduction (recomputeTotals), the basis '
        '(the GET) and the sheet (candidatesForLine, the GET) read the same '
        'recipe: all on 173128 at 628.01 per serving', () async {
      final recipe = recipes[_corned]!;
      final line = nutritionLines(recipe)[0];
      expect(recomputeTotals(db, recipe), isTrue);
      expect(
        db.nutritionFor(recipe.id)!.caloriesPerServing!.toStringAsFixed(2),
        '628.01',
      );
      expect(braisedKeptOf(line.raw, 173128, recipe), braisedKept[173128]);
      final items =
          (await matchesBody(db, provider, recipe))['items']!
              as List<Map<String, Object?>>;
      final match = items[0]['match']! as Map<String, Object?>;
      expect(match['fdc_id'], 173128);
      expect(match['gram_basis'], endsWith(_cornedFlag));
      final sheet = items[0]['candidates']! as List<Object?>;
      expect((sheet.first! as Map<String, Object?>)['fdc_id'], 173128);
      final ranked = await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: true,
        recipe: recipe,
      );
      expect(ranked.first.candidate.fdcId, 173128);
      // Without the recipe the line alone leads with the 0" flat — the
      // recipe is what moves it.
      final alone = await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: true,
      );
      expect(alone.first.candidate.fdcId, 168743);
      expect({for (final c in alone) c.candidate.fdcId}, contains(173128));
    });

    test("the gates: onion-braised's 0\" pair only where its steps skim; 0090 "
        'skims scum (no pair); a 0" flat standing in for a PRINTED cap '
        "(0224's line, M56 R1d's fallback) stays gross, as its flag says", () {
      final onion = nutritionLines(recipes[_onion]!)[0].raw;
      expect(
        braisedKeptOf(onion, 168743, recipes[_onion]),
        braisedKept[168743],
      );
      expect(braisedKeptOf(onion, 168743, null), isNull);
      final newEngland = nutritionLines(recipes[_newEngland]!)[6].raw;
      expect(braisedKeptOf(newEngland, 168743, recipes[_newEngland]), isNull);
      final flat = nutritionLines(recipes[_pomegranate]!)[0].raw;
      expect(braisedKeptOf(flat, 168743, recipes[_pomegranate]), isNull);
      expect(
        trimStandInFlagOf(flat, 168743, recipe: recipes[_pomegranate]),
        'approximate (the printed ¼-inch fat cap renders and is skimmed '
        '(step 5); counted as the 0-inch trimmed flat)',
      );
      // 0091's own line on the 0" record (a person's pick) reads no pair:
      // its steps skim nothing; the corned clause stays.
      final corned = nutritionLines(recipes[_corned]!)[0].raw;
      expect(braisedKeptOf(corned, 168743, recipes[_corned]), isNull);
      expect(
        trimStandInFlagOf(
          corned,
          168743,
          title: recipes[_corned]!.title,
          recipe: recipes[_corned],
        ),
        'approximate ($_cure)',
      );
      // onion-braised's line on 173128 (no printed depth, no trim step):
      // no pair, no flag (M72's pin stands).
      expect(braisedKeptOf(onion, 173128, recipes[_onion]), isNull);
      expect(trimStandInFlagOf(onion, 173128, recipe: recipes[_onion]), isNull);
    });

    test('pre-Q18: a STATED synthesized step-less copy of 0091 stays on the '
        '0" flat (no step, no move, no pair) with its corned flag', () async {
      final alone = library('salt-v74-alone-');
      final original = recipes[_corned]!;
      final stepless = original.copyWith(steps: const []);
      alone.upsertRecipe(
        stepless,
        sourceSlug: _source,
        contentHash: stepless.id,
      );
      final copy = alone.recipeByIdOrSlug(stepless.id)!.recipe;
      expect(
        await matchAndCompute(
          alone,
          FixtureProvider(pending: {...pendingSearches}),
          copy,
        ),
        isNull,
      );
      final row = alone
          .ingredientMatchesFor(copy.id)
          .singleWhere((m) => m.position == 0);
      final line = nutritionLines(copy)[0];
      expect(row.fdcId, 168743);
      expect(row.grams, rowIn(_corned, 0).grams);
      expect(braisedKeptOf(line.raw, 173128, copy), isNull);
      expect(
        gramBasisFor(alone, line, row, recipe: copy),
        'from the printed weight (4½–5 lb, the midpoint) · approximate ($_cure)',
      );
      expect(
        (await candidatesForLine(
          alone,
          provider,
          line,
          cacheOnly: true,
          recipe: copy,
        )).first.candidate.fdcId,
        168743,
      );
    });

    test('the census: exactly one corpus step sentence (0091 S1) trims a '
        "brisket's fat to a printed depth — the reader and the design's "
        'regex agree on every sentence (sections included)', () {
      final files =
          Directory(corpusRecipesDir)
              .listSync()
              .map((f) => f.uri.pathSegments.last)
              .where((f) => f.endsWith('.yaml'))
              .toList()
            ..sort();
      final hits = <String>[];
      var sentences = 0;
      for (final file in files) {
        final r = loadCorpusRecipe(file);
        for (final (label, rec) in [
          (file, r),
          for (final sub in r.subsections.where((s) => s.title != null))
            ('$file|${sub.title}', sectionRecipeOf(r, sub)),
        ]) {
          for (final (i, step) in rec.steps.indexed) {
            for (final s in step.text.toLowerCase().split(
              RegExp(r'(?<=\.)\s+'),
            )) {
              sentences++;
              final depth = trimsFatSentence(s);
              expect(depth, _design.firstMatch(s)?[1], reason: '$label|$i: $s');
              if (depth != null) {
                hits.add('$label|${i + 1}|$depth');
              }
            }
          }
        }
      }
      expect(sentences, greaterThan(10000));
      expect(hits, ['$_corned|1|⅛']);
    });

    test('a second recompute writes nothing — rows and totals', () {
      for (final file in _files) {
        final recipe = recipes[file]!;
        for (final id in [
          recipe.id,
          ...sectionChildKeysOf(db, recipe, ResolverMemo(db)),
        ]) {
          final stored = nutritionRecipeOf(db, id)!.recipe;
          List<(int, double?, String?, String?, int?)> rows() => [
            for (final r in db.ingredientMatchesFor(id))
              (r.position, r.grams, r.hold, r.updatedAt, r.fdcId),
          ];
          expect(recomputeTotals(db, stored), isTrue, reason: id);
          final before = rows();
          final totals = batchTotalsOf(db.nutritionFor(id)!);
          expect(recomputeTotals(db, stored), isTrue, reason: id);
          expect(rows(), before, reason: id);
          expect(batchTotalsOf(db.nutritionFor(id)!), totals, reason: id);
        }
      }
    });
  });
}
