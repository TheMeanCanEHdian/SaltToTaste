// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v84 (batch M82; matcherVersion 79 — pieces and densities; prep51
// design_v2 §2 M82, decided under the 2026-10-07 standing authorization;
// zero requests): C1 the white sandwich-bread slice at ATK's two prints
// (45.36 g, the hearty loaf 40.50 g), C1b a slice of SR 174924 whose parsed
// prep removes the crusts keeps the record's own 12 g of 29 g, C2 the
// poblano at the corpus's "1 pound (3 to 4)" (129.6 g), C3a a counted
// garlic clove whose paren prints its volume weighs it on SR 169230, C5a
// all-purpose / whole-wheat flour at the corpus's 5 / 5½ ounces a cup on
// the portion-less records, C6a an extra-virgin olive oil at its record's
// own volume figure (748608 '100 milliliter' 90.7 g), C6b the drained
// oil-packed white tuna at SR 173708's drained share (321 g of 12.5 oz).
// Closer 1 (verify1 D1–D3, D6): C1 and C6a keyed on the prints' own words —
// 'white sandwich bread' (ruling4: the unsourced 28 g 'sandwich bread' is
// deleted — a potato loaf weighs on its record's own slice)
// and 'virgin olive oil' ('oil' itself record-first moved 145 rows on
// FNDDS's 14 g tablespoon and read "oil-cured black olives" on the olive's
// cup). Every row value is the fresh compute of the WHOLE recipe over
// recorded real FDC answers (FixtureProvider; SR 167943 and 175158 recorded
// from snapshot 29 for the two converses) and equals the v84 replay of
// snapshot 29 on every pinned field; a line weighed alone ([lineGrams], as
// the engine weighs it) where its recipe is not recorded, said so. Never the
// network. Every corpus line is real. STATED constructions (no corpus line
// reaches these gates): C1b's record gate — 0014's real crust-removed line
// on SR 167943 (a real recorded record, the pairing synthesized); C5a's
// plain 'flour' mark — a corpus flour the key reads at a volume alone (every
// such corpus line prints its weight: the line and the pairing synthesized,
// verify6 D11); C3a's
// piece gate — a clove line printing a weight beside its volume (a negative
// path, synthesized as CLAUDE.md allows), and its fallback — 0327's real
// line with no 169230 cached (a cache state); the cap shapes' 400 lines of
// real corpus clove lines (the house's cap-shape exception).

import 'dart:convert';
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

import 'nutrition_v26_cost_test.dart' show capLines, capped, ln;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _bread =
    'approximate (ATK: 1½ pounds high-quality white sandwich bread ≈ 15 slices)';
const _hearty =
    'approximate (ATK: 10 ounces hearty white sandwich bread ≈ 7 slices)';
const _crusts =
    "× 12/29 crusts removed (USDA: 'slice crust not eaten' 12 g of 'slice' 29 g)";
const _poblano =
    'approximate (ATK: 1 pound poblano chiles, as bought, ≈ 3 to 4)';
const _flour = 'approximate (ATK: 1 cup all-purpose flour = 5 ounces)';
const _wholeWheat = 'approximate (ATK: 1 cup whole-wheat flour = 5½ ounces)';
const _evooSibling = ' · nutrients of "Oil, olive, salad or cooking"';
const _garlic = ' · USDA portion of "Garlic, raw"';

/// The whole-recipe rows (file, section title or null, position, raw, fdc
/// id, source, grams, kcal, basis) — the v82 replay's value in each comment
/// where the row moved.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int,
  String,
  String,
  String,
  String?,
);

/// C1 + C1b: the slices (mutants: 45.36 → 28 reads 0299|1 at 112.00; the
/// hearty key deleted reads 0299|6 at 362.88; the crusts arm dropped reads
/// 0014|6 at 136.08; its `crusts?` written `crusts` reads 0032|7 at 45.36).
/// The croutons print a cup: their own portion, unchanged (converse).
const List<_Row> _slices = [
  // v82: 112.00 g, 297.92 kcal (piece)
  (
    '0299-classic-grilled-cheese-sandwiches.yaml',
    null,
    1,
    '4 slices high-quality white sandwich bread',
    174924,
    'piece',
    '181.44',
    '482.63',
    '4 slice × 45.36 g each · $_bread',
  ),
  // v82: 224.00 g, 595.84 kcal (piece)
  (
    '0299-grown-up-grilled-cheese-sandwiches-with-cheddar-and-shallot.yaml',
    null,
    6,
    '8 slices hearty white sandwich bread',
    174924,
    'piece',
    '324.00',
    '861.84',
    '8 slice × 40.5 g each · $_hearty',
  ),
  (
    '0015-carrot-ginger-soup.yaml',
    'Buttery Croutons',
    2,
    '3 large slices high-quality sandwich bread, cut into ½-inch cubes (about 2 cups)',
    174924,
    'portion',
    '70.00',
    '186.20',
    '2 cup · USDA portion',
  ),
  // v82: 84.00 g, 223.44 kcal (piece)
  (
    '0014-creamless-creamy-tomato-soup.yaml',
    null,
    6,
    '3 slices high-quality white sandwich bread, crusts removed, torn into 1-inch pieces',
    174924,
    'piece',
    '56.31',
    '149.78',
    '3 slice × 45.36 g each · $_bread $_crusts',
  ),
  // v82: 28.00 g, 74.48 kcal (piece)
  (
    '0032-creamy-gazpacho-andaluz.yaml',
    null,
    7,
    '1 slice high-quality white sandwich bread, crust removed, torn into 1-inch pieces',
    174924,
    'piece',
    '18.77',
    '49.93',
    '1 slice × 45.36 g each · $_bread $_crusts',
  ),
];

/// C2: the poblano (mutant 129.6 → 45 reads 0489|1 at 180.00; the literal
/// the basis prints, 4 × 129.6 = 518.40 — the quotient 453.59 / 3.5 gives
/// 518.39); a weight print keeps its pound (converse).
const List<_Row> _poblanos = [
  // v82: 180.00 g, 50.38 kcal (piece)
  (
    '0489-roasted-poblano-and-black-bean-enchiladas.yaml',
    null,
    1,
    '4 poblano chiles, halved, stemmed, and seeded',
    2747662,
    'piece',
    '518.40',
    '145.10',
    '4 × 129.6 g each · $_poblano',
  ),
  (
    '0070-skillet-chicken-fajitas.yaml',
    null,
    10,
    '1 pound (3 to 4) poblano chiles, stemmed, halved, and seeded',
    2747662,
    'weight',
    '453.59',
    '126.96',
    'from 1 pound',
  ),
];

/// C3a: the clove (mutant: the arm dropped reads 0327|2 at 3.00); no volume
/// (0659|4), a second count before the paren (0491|2; the guard dropped:
/// 5.60), a sibling record that is no clove (0028|7, onions on SR 170000;
/// its "½-inch" after the comma trips the second-count guard too, so the
/// clove scope dropped alone keeps 140.00 — only both dropped read 206.25)
/// and a clove unit (0075|3, its item "garlic"; the clove scope dropped
/// reads its tablespoon on 1104647's portion) keep the count (converses).
const List<_Row> _cloves = [
  // v82: 3.00 g, 4.29 kcal (piece)
  (
    '0327-pasta-caprese.yaml',
    null,
    2,
    '1 small garlic clove, minced or pressed through a garlic press (about ½ teaspoon)',
    1104647,
    'portion',
    '1.40',
    '2.00',
    '1/2 teaspoon · USDA portion of "Garlic, raw"',
  ),
  (
    '0659-grilled-baba-ghanoush.yaml',
    null,
    4,
    '1 small garlic clove, minced',
    1104647,
    'piece',
    '3.00',
    '4.29',
    '1 × 3 g each',
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    2,
    '5 medium garlic cloves, 3 peeled and smashed and 2 minced or pressed through a garlic press (about 2 teaspoons)',
    1104647,
    'piece',
    '15.00',
    '21.45',
    '5 × 3 g each',
  ),
  (
    '0028-hearty-minestrone.yaml',
    null,
    7,
    '2 small onions, peeled and cut into ½-inch pieces (about 1½ cups)',
    790646,
    'piece',
    '140.00',
    '53.20',
    '2 × 70 g each',
  ),
  (
    '0075-chicken-under-a-brick-with-herb-roasted-potatoes.yaml',
    null,
    3,
    '3 cloves garlic, minced (about 1 tablespoon)',
    1104647,
    'piece',
    '9.00',
    '12.87',
    '3 clove × 3 g each',
  ),
];

/// C5a: whole-wheat flour (mutant 0.6590 → 0.54 reads 0792|4 at 23.95; the
/// all-purpose figure's pin is 0911|4, weighed alone below).
const List<_Row> _flours = [
  // v82: 23.95 g, 88.63 kcal (density)
  (
    '0792-rustic-dinner-rolls.yaml',
    null,
    4,
    '3 tablespoons whole-wheat flour',
    790085,
    'density',
    '29.24',
    '108.17',
    '3 tablespoon ≈ 44 mL · $_wholeWheat',
  ),
];

/// C6a: an extra-virgin olive oil on its record (mutants: the milliliter
/// alias dropped, or the key's record-first dropped, read 0407|9 at 27.21 —
/// critic C-7's two decimals); converses: a vegetable oil's own portion
/// (0407|7), a teaspoon of vegetable oil on FNDDS 2710180, which publishes
/// no teaspoon (0178|2: 'oil' record-first reads its tablespoon, 9.33), and
/// "oil-cured black olives" (1143 §1: 16.88 on the olive's cup). The
/// discarded 748608 rows (critic K-8): a printed kept part follows 0.907
/// (0126|2); the three kept with the bacon grease do not — rule B1's split
/// reads the pan's oil with no food (`_panOilGrams`, the one figure the
/// bacon row reads too), so they stay; 1133's frying oils share the food's
/// uptake (6.68 % of the raw breasts, 53.02 g, unchanged) by their full
/// grams, so the EVOO row gives 0.19 g to the vegetable oil (stated).
const List<_Row> _oils = [
  // v82: 27.21 g, 240.52 kcal (density)
  (
    '0407-eggplant-parmesan.yaml',
    null,
    9,
    '2 tablespoons extra-virgin olive oil',
    748608,
    'portion',
    '26.82',
    '237.12',
    '2 tablespoon · USDA portion$_evooSibling',
  ),
  (
    '0407-eggplant-parmesan.yaml',
    null,
    7,
    '6 tablespoons vegetable oil',
    2710180,
    'portion',
    '84.00',
    '756.00',
    '6 tablespoon · USDA portion',
  ),
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    null,
    2,
    '2 teaspoons vegetable oil',
    2710180,
    'density',
    '9.07',
    '81.62',
    '2 teaspoon ≈ 10 mL',
  ),
  (
    '1143-roasted-fennel.yaml',
    'Crunchy Oil-Cured Olives',
    0,
    '2 tablespoons coarsely chopped oil-cured black olives',
    2710090,
    'density',
    '27.21',
    '31.56',
    '2 tablespoon ≈ 30 mL',
  ),
  // v82: 9.07 g, 80.17 kcal (discarded)
  (
    '0126-pollo-en-pepitoria-spanish-braised-chicken-with-sherry-and-saffron.yaml',
    null,
    2,
    '1 tablespoon extra-virgin olive oil',
    748608,
    'discarded',
    '8.94',
    '79.04',
    '2 teaspoons kept (the steps pour off the rest)$_evooSibling',
  ),
  (
    '0332-pasta-with-tomato-bacon-and-onion.yaml',
    null,
    0,
    '2 tablespoons extra-virgin olive oil',
    748608,
    'discarded',
    '9.93',
    '87.81',
    '2 tablespoons kept with the bacon grease (the steps pour off the rest)$_evooSibling',
  ),
  (
    '0333-pasta-alla-gricia-rigatoni-with-pancetta-and-pecorino-romano.yaml',
    null,
    1,
    '1 tablespoon extra-virgin olive oil',
    748608,
    'discarded',
    '13.08',
    '115.64',
    '⅓ cup kept with the bacon grease (the steps pour off the rest)$_evooSibling',
  ),
  (
    '0434-salade-lyonnaise.yaml',
    null,
    1,
    '2 tablespoons extra-virgin olive oil',
    748608,
    'discarded',
    '11.07',
    '97.84',
    '2 tablespoons kept with the bacon grease (the steps pour off the rest)$_evooSibling',
  ),
  // v82: 26.13 g, 230.99 kcal (discarded)
  (
    '1133-chicken-francese.yaml',
    null,
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    'discarded',
    '25.94',
    '229.31',
    null,
  ),
  // v82: 26.89 g, 242.01 kcal (discarded)
  (
    '1133-chicken-francese.yaml',
    null,
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    'discarded',
    '27.08',
    '243.72',
    null,
  ),
];

/// C6b: the drained white tuna (mutant: the share dropped reads 0467|14 at
/// 368.54).
const List<_Row> _tuna = [
  // v82: 368.54 g, 685.49 kcal (weight)
  (
    '0467-pan-bagnat-provencal-tuna-sandwich.yaml',
    null,
    14,
    '2 (6½-ounce) jars oil-packed tuna, drained',
    175157,
    'weight',
    '333.84',
    '620.94',
    "2 × 184 g (printed weight) × 0.906 drained · approximate (drained weight: FDC's oil-packed light tuna can, 321 g of 12.5 oz)",
  ),
];

/// The coat budgets C1 and C5a re-solve (design §0.5: M85 re-solves the
/// Parmesan part and M88 splits the dredge — each re-derives these on the v84
/// rows; pinned at the replay's figure, never a model's).
const List<_Row> _coats = [
  // v82: 77.68 g, 206.63 kcal (discarded)
  (
    '0122-chicken-kiev.yaml',
    null,
    7,
    '4 slices high-quality white sandwich bread, torn into quarters',
    174924,
    'discarded',
    '93.87',
    '249.69',
    null,
  ),
  // v82: 83.69 g, 306.31 kcal (discarded)
  (
    '0122-chicken-kiev.yaml',
    null,
    11,
    '1 cup unbleached all-purpose flour',
    789890,
    'discarded',
    '73.34',
    '268.42',
    null,
  ),
  (
    '0122-chicken-kiev.yaml',
    null,
    12,
    '3 large eggs, beaten',
    748967,
    'discarded',
    '116.88',
    '172.98',
    null,
  ),
  // v82: 29.01 g, 106.18 kcal (discarded)
  (
    '0114-breaded-chicken-cutlets.yaml',
    null,
    3,
    '¾ cup unbleached all-purpose flour',
    789890,
    'discarded',
    '25.43',
    '93.07',
    null,
  ),
  // v82: 40.36 g, 147.72 kcal (discarded)
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    8,
    '1 cup all-purpose flour',
    789890,
    'discarded',
    '41.53',
    '152.00',
    null,
  ),
  // v82: 8.01 g, 30.52 kcal (discarded)
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    null,
    9,
    '3 tablespoons cornstarch',
    169698,
    'discarded',
    '7.02',
    '26.75',
    null,
  ),
];

/// A recorded record, as the engine reads it.
Future<FdcFood> _food(int fdcId) async =>
    (await FixtureProvider(pending: {...pendingSearches}).food(fdcId))!;

/// The corpus line [file]|[position] (its section [section], else a main
/// line).
IngredientLine _corpusLine(String file, int position, {String? section}) {
  final recipe = loadCorpusRecipe(file);
  final from = section == null
      ? recipe
      : sectionOf(recipe, sectionKeyOf(recipe.id, section))!;
  return nutritionLines(from)[position];
}

/// A database holding [foods]' details, as a compute caches them.
SaltDatabase _cache(List<FdcFood> foods) {
  final dir = Directory.systemTemp.createTempSync('salt-v84-cache-');
  final db = SaltDatabase.open(
    ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath,
  );
  for (final f in foods) {
    db.fdcFoodCachePut(f.fdcId, jsonEncode(f.toJson()));
  }
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

void main() {
  test('matcherVersion 79 (v84, batch M82: rows move)', () {
    expect(matcherVersion, 79);
  });

  group('matcher v84 (batch M82) — whole recipes', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    Future<Recipe> compute(Recipe recipe) async {
      db.upsertRecipe(
        recipe,
        sourceSlug: _source,
        contentHash: contentHashOf(recipe),
      );
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

    const tables = {
      'C1 + C1b': _slices,
      'C2': _poblanos,
      'C3a': _cloves,
      'C5a': _flours,
      'C6a': _oils,
      'C6b': _tuna,
      'the coat budgets': _coats,
    };

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v84-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      // Snapshot 29's cache state (as v51 and v83 state it): rule B1's part
      // record 168322 lives only as a hit of the cached 'thin-sliced cooked
      // deli ham' answer (0332, 0333 and 0434 render bacon).
      db.fdcSearchCachePut(
        'thin-sliced cooked deli ham',
        jsonEncode([
          for (final c in await provider.search('thin-sliced cooked deli ham'))
            c.toJson(),
        ]),
      );
      for (final file in {
        for (final rows in tables.values)
          for (final r in rows) r.$1,
      }) {
        recipes[file] = await compute(loadCorpusRecipe(file));
      }
      // A section no host line routes (0015's croutons, 1143's olives) is
      // computed under its own key, as the per-recipe job does.
      for (final (file, section) in {
        for (final rows in tables.values)
          for (final r in rows)
            if (r.$2 != null) (r.$1, r.$2!),
      }) {
        final key = sectionKeyOf(recipes[file]!.id, section);
        if (db.ingredientMatchesFor(key).isEmpty) {
          expect(
            await matchAndCompute(
              db,
              provider,
              nutritionRecipeOf(db, key)!.recipe,
            ),
            isNull,
          );
        }
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Recipe recipeIn(String file, String? section) => section == null
        ? recipes[file]!
        : nutritionRecipeOf(
            db,
            sectionKeyOf(recipes[file]!.id, section),
          )!.recipe;

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    String kcalOf(IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    for (final MapEntry(key: rule, value: rows) in tables.entries) {
      test('$rule: each row its record, source, grams, energy and basis '
          "(the v84 replay's)", () {
        // ruling4 R1: chicken-francese-2's absorbed oil, |8 + |9, is the
        // uptake's mass — 53.02 g at v82 (26.13 + 26.89) and at v84 (25.94 +
        // 27.08): 748608's 0.907 moves only the split (`uptake * p.full /
        // oil`, 0.19 g to the vegetable-oil row), never the uptake. Mutant:
        // the uptake's grams over 99 instead of 100 reads 53.57.
        if (rule == 'C6a') {
          final id = recipes['1133-chicken-francese.yaml']!.id;
          expect(
            (rowIn(id, 8).grams! + rowIn(id, 9).grams!).toStringAsFixed(2),
            '53.02',
          );
        }
        for (final (
              file,
              section,
              position,
              raw,
              fdcId,
              source,
              grams,
              kcal,
              basis,
            )
            in rows) {
          final recipe = recipeIn(file, section);
          final line = nutritionLines(recipe)[position];
          final row = rowIn(recipe.id, position);
          final reason = '$file|${section ?? ''}|$position';
          expect(line.raw, raw, reason: reason);
          expect(
            (row.fdcId, row.status, row.hold, row.gramSource),
            (fdcId, 'auto', null, source),
            reason: reason,
          );
          expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
          expect(kcalOf(row), kcal, reason: reason);
          if (basis != null) {
            expect(
              gramBasisFor(db, line, row, recipe: recipe),
              basis,
              reason: reason,
            );
          }
        }
      });
    }
  });

  group(
    'matcher v84 (batch M82) — lines weighed alone ([lineGrams], as the '
    'engine weighs them; their recipes are not recorded)',
    skip: skipIfNoCorpus,
    () {
      for (final (rule, file, position, raw, fdcId, grams, basis) in [
        // C1 (ruling4 R3): a potato loaf is no white loaf, and the plain
        // 'sandwich bread' 28 g (unsourced, d614c2e) is deleted — its slice
        // weighs on SR 167943's own 'slice' 32 g (recorded from snapshot 29),
        // as individual-summer-berry-puddings|6 reads the same record at v82.
        // RE-PIN (v84, ruling4): v82 and closer 1–3 280.00 g `10 slice × 28 g
        // each`; the replay row is 320.00. Mutant: the plain key restored at
        // 28 reads 280.00.
        (
          'C1',
          '1196-french-toast-casserole.yaml',
          5,
          '10 slices potato sandwich bread, halved diagonally',
          167943,
          '320.00',
          '10 slice · USDA portion',
        ),
        // C5a: the corpus line L003 names (replay 35.44; 0.5991 rounded gives
        // the brief's 35.43 — the exact quotient 5 × 28.3495 / 236.588 is
        // 0.599132). Mutant 0.5991 → 0.51: 30.16.
        (
          'C5a',
          '0911-wicked-good-boston-cream-pie.yaml',
          4,
          '¼ cup all-purpose flour',
          789890,
          '35.44',
          '1/4 cup ≈ 59 mL · $_flour',
        ),
        // C5a converse: a weight print keeps its weight.
        (
          'C5a',
          '0911-wicked-good-boston-cream-pie.yaml',
          7,
          '1½ cups (7½ ounces) all-purpose flour',
          789890,
          '212.62',
          'from 7 1/2 ounce',
        ),
        // C5a, STATED consequences beyond the brief's enumerated reach
        // (verify2 D1, accepted: ruling4 R1): a weight-printed
        // line's "plus" part is a volume, weighed at the density
        // ([_resolveLine]'s plus part), so it reads the print too — "2 cups
        // (10 ounces)" is itself 5 ounces a cup. Replay rows (v82 at 0.51:
        // 286.01, 220.16, 156.83); mutant 0.5991 → 0.51 reads those.
        (
          'C5a',
          '0770-blueberry-boy-bait.yaml',
          0,
          '2 cups (10 ounces) plus 1 teaspoon unbleached all-purpose flour',
          789890,
          '286.45',
          'from 10 ounce + 1 teaspoon unbleached all-purpose flour',
        ),
        (
          'C5a',
          '0504-congyoubing-scallion-pancakes.yaml',
          7,
          '1½ cups (7½ ounces) plus 1 tablespoon all-purpose flour',
          789890,
          '221.48',
          'from 7 1/2 ounce + 1 tablespoon all-purpose flour',
        ),
        (
          'C5a',
          '0866-french-apple-cake.yaml',
          3,
          '1 cup (5 ounces) plus 2 tablespoons all-purpose flour',
          789890,
          '159.47',
          'from 5 ounce + 2 tablespoons all-purpose flour',
        ),
        // C6b converse: tuna in water, no "drained" (SR 175158 recorded from
        // snapshot 29; its replay row 340.19 g, unchanged).
        (
          'C6b',
          '0298-classic-tuna-salad.yaml',
          0,
          '2 (6-ounce) cans solid white tuna in water',
          175158,
          '340.19',
          '2 × 170 g (printed weight)',
        ),
        // C1b's piece gate (a real landing): the schnitzel's slices print
        // their cups, so the record's own cup weighs them — never × 12/29 (the
        // gate dropped: 57.93). Its replay row is the coat's share, 36.69.
        (
          'C1b',
          '0233-pork-schnitzel-breaded-pork-cutlets.yaml',
          0,
          '7 slices high-quality white sandwich bread, crusts removed, cut into ¾-inch cubes (about 4 cups)',
          174924,
          '140.00',
          '4 cup · USDA portion',
        ),
      ]) {
        test('$rule: $file|$position on $fdcId weighs $grams g', () async {
          final line = _corpusLine(file, position);
          expect(line.raw, raw);
          final recipe = loadCorpusRecipe(file);
          final food = await _food(fdcId);
          final got = lineGrams(_cache([food]), line, food, recipe: recipe)!;
          expect(got.grams.toStringAsFixed(2), grams);
          expect(got.basis, basis);
        });
      }

      // C1b's record gate (STATED: 0014|6's real crust-removed line on SR
      // 167943, a real recorded record — no corpus crust-removed slice lands
      // off 174924 as a piece; roast-chicken-with-warm-bread-salad|2 and
      // spanish-migas|3 print weights on 2707608 / 2707614): the share is
      // 174924's own two portions, so another record keeps the whole slice
      // (the gate dropped: 56.31).
      test("C1b: 0014|6's line on another record keeps the whole slice "
          '(STATED, the pairing synthesized)', () async {
        final line = _corpusLine('0014-creamless-creamy-tomato-soup.yaml', 6);
        final food = await _food(167943);
        final got = lineGrams(_cache([food]), line, food)!;
        expect(got.grams.toStringAsFixed(2), '136.08');
        expect(got.basis, '3 slice × 45.36 g each · $_bread');
      });

      // C3a's fallback (STATED cache state): with no SR 169230 cached the
      // clove keeps its count — never null (the fallback written `null`:
      // no grams). [gramsFor] fetches the sibling first on a compute (the
      // whole-recipe 0327|2 above computes on a fresh cache).
      test("C3a: 0327|2 with no 169230 cached keeps its clove's 3 g", () async {
        final line = _corpusLine('0327-pasta-caprese.yaml', 2);
        final food = await _food(1104647);
        final got = lineGrams(_cache([food]), line, food);
        expect(got?.grams.toStringAsFixed(2), '3.00');
        expect(got?.basis, '1 × 3 g each');
        final cached = lineGrams(
          _cache([food, await _food(169230)]),
          line,
          food,
        )!;
        expect(cached.grams.toStringAsFixed(2), '1.40');
        expect(cached.basis, '1/2 teaspoon$_garlic');
      });

      // C3a's piece gate (STATED SYNTHESIZED negative path — no corpus clove
      // line prints a weight beside a volume; chicken-with-40-cloves|2's
      // "(about 8 ounces)" prints no volume): a printed weight is the line's
      // own figure, read on its own record (the gate dropped: the sibling
      // reads the same weight first, 28.35 g, but the basis names a record it
      // did not read — 'from 1 ounce of "Garlic, raw"').
      test('C3a: a clove line printing its weight keeps the weight '
          '(STATED, synthesized)', () async {
        final line = ln(
          '1 ounce garlic cloves, peeled (about 3 tablespoons)',
        );
        final food = await _food(1104647);
        final got = lineGrams(
          _cache([food, await _food(169230)]),
          line,
          food,
        )!;
        expect(got.grams.toStringAsFixed(2), '28.35');
        expect(got.source, GramSource.weight);
        expect(got.basis, 'from 1 ounce');
      });

      // The record-first marks (the v37 form, STATED: a real line at its
      // position on a real recorded record carrying its own volume figure in
      // another unit — no corpus flour line lands on one, pC §C5a): the
      // record's figure wins, '· USDA portion' (record-first dropped: the
      // print's figure, each comment's).
      for (final (file, position, raw, grams, basis) in [
        // 'all-purpose flour' dropped: 8.86 '≈ 15 mL · $_flour'.
        (
          '0415-best-chicken-parmesan.yaml',
          13,
          '1 tablespoon all-purpose flour',
          '8.00',
          '1 tablespoon · USDA portion',
        ),
        // 'whole-wheat flour' dropped: 29.24 (0792|4's replay figure).
        (
          '0792-rustic-dinner-rolls.yaml',
          4,
          '3 tablespoons whole-wheat flour',
          '24.00',
          '3 tablespoon · USDA portion',
        ),
      ]) {
        test('C5a record-first: $file|$position on SR 169698 "Cornstarch" '
            'reads its cup (STATED, the pairing synthesized)', () async {
          final line = _corpusLine(file, position);
          expect(line.raw, raw);
          final food = await _food(169698);
          final got = resolveGrams(
            amounts: line.amounts,
            food: food,
            normalizedItem: normalizeItem(lineItemOf(line)),
            raw: line.raw,
          )!;
          expect(got.grams.toStringAsFixed(2), grams);
          expect(got.basis, basis);
        });
      }

      // The plain 'flour' key's mark (verify6 D11): every corpus line the
      // key reads — rye, semolina, almond, rice, buckwheat, instant flours —
      // prints its weight ("½ cup (2¾ ounces) rye flour", 0797), so none
      // reaches it; STATED, the line synthesized too (0797's item at a
      // volume in another unit than the record's cup). The mark dropped:
      // 17.72, the density.
      test("C5a record-first: the plain 'flour' key on SR 169698 reads its "
          'cup (STATED, the line synthesized)', () async {
        const raw = '2 tablespoons rye flour';
        final parsed = parseIngredientLine(raw);
        final got = resolveGrams(
          amounts: parsed.amounts,
          food: await _food(169698),
          normalizedItem: normalizeItem(parsed.item!),
          raw: raw,
        )!;
        expect(got.grams.toStringAsFixed(2), '16.00');
        expect(got.basis, '2 tablespoon · USDA portion');
      });
    },
  );

  test("the densities: ATK's printed cups and the kitchen 0.92 a record-less "
      'oil reads (the medium thresholds read these, engine RULE B)', () {
    expect(densityOf('all-purpose flour'), 5 * 28.3495 / 236.588);
    expect(densityOf('flour'), 5 * 28.3495 / 236.588);
    expect(densityOf('whole-wheat flour'), 5.5 * 28.3495 / 236.588);
    expect(densityOf('extra virgin olive oil'), 0.92);
    expect(densityOf('oil'), 0.92);
  });

  // RULE C (the brief's cost shapes): C3a reads the line's parsed amounts
  // and its item inside [lineGrams] — no step reader. 400 lines of one real
  // clove line under the recipe's own steps: TRUE 0327|2 (each line weighs
  // its ½ teaspoon on SR 169230), QUIET 0491|2 (the second count keeps the
  // five cloves). The compute and the GET count base's families exactly
  // (18c0c53, measured: COUNTS below); the TRUE compute fetches 169230
  // once more than base ([gramsFor]'s sibling fetch — base fetched it for
  // no line, so the lines kept 3 g); each under the backstop.
  group('RULE C, the clove volume at the caps', skip: skipIfNoCorpus, () {
    for (final (
          shape,
          file,
          position,
          grams,
          foodCalls,
          computeCounts,
          getCounts,
        )
        in _capShapes) {
      test('$shape: 400 × $file|$position — $grams g a line, $foodCalls food '
          'details fetched, the counts exact, within the backstop', () async {
        final dir = Directory.systemTemp.createTempSync('salt-v84-cap-');
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
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final base = loadCorpusRecipe(file);
        final raw = nutritionLines(base)[position].raw;
        final r = capped(base, List.filled(capLines, raw), [
          for (final s in base.steps) s.text,
        ]).copyWith(id: 'cap-$shape', slug: 'cap-$shape');
        db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        expect(await matchAndCompute(db, fdc, stored), isNull);
        final computeMs = sw.elapsedMilliseconds;
        final computed = Map.of(stepIndexCounts);
        expectBounded(stored, computed, '$shape compute');
        expect(computed, computeCounts, reason: '$shape compute');
        expect(computeMs, lessThan(backstopMs), reason: '$shape compute');
        expect(fdc.foodCalls, foodCalls, reason: '$shape compute');
        final rows = db.ingredientMatchesFor(r.id);
        expect(rows, hasLength(capLines));
        expect({for (final m in rows) m.grams?.toStringAsFixed(2)}, {grams});
        stepIndexCounts.clear();
        sw.reset();
        final body = await matchesBody(
          db,
          fdc,
          db.recipeByIdOrSlug(r.id)!.recipe,
        );
        final getMs = sw.elapsedMilliseconds;
        final got = Map.of(stepIndexCounts);
        expectBounded(stored, got, '$shape GET');
        expect(got, getCounts, reason: '$shape GET');
        expect(getMs, lessThan(backstopMs), reason: '$shape GET');
        expect(body['items']! as List, hasLength(capLines));
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// (shape, file, position, grams, food details fetched, compute counts, GET
/// counts) — the counts base's (18c0c53) exactly, measured twice on each
/// tree: TRUE compute 736 / 693 ms → 766 / 792 ms, GET 420 / 421 → 457 /
/// 476 ms (each line's ½ teaspoon weighed on the sibling, and its one
/// fetch: base fetched 1104647 only, its lines at 3.00 g); QUIET compute
/// 621 / 634 → 618 / 627 ms, GET 412 / 413 → 417 / 422 ms.
const List<
  (String, String, int, String, int, Map<String, int>, Map<String, int>)
>
_capShapes = [
  (
    'TRUE',
    '0327-pasta-caprese.yaml',
    2,
    '1.40',
    2,
    {
      'indexes': 1,
      'memo:skinSentences': 1,
      'allSentences': 1,
      'lower': 1,
      'sentences': 11,
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
      'words': 133,
      'memo:naming': 1,
      'memo:strainAt': 1,
      'memo:savesRemainder': 1,
      'memo:setAsideLine': 1,
      'memo:setsAsidePieces': 1,
      'memo:reservedWhole': 1,
      'memo:discards': 1,
      'memo:dips': 1,
      'memo:leftInBowl': 1,
      'memo:keptSolids': 1,
    },
    {
      'indexes': 1,
      'memo:starter': 1,
      'heads': 1,
      'memo:braise': 1,
      'memo:strain': 1,
      'lower': 1,
      'sentences': 11,
      'memo:pourAway': 1,
      'cheese': 1,
      'memo:brines': 1,
      'memo:wordHeads': 1,
      'memo:brineWords': 1,
      'memo:parting': 1,
      'words': 133,
      'memo:naming': 1,
      'memo:strainAt': 1,
      'memo:savesRemainder': 1,
      'memo:setAsideLine': 1,
      'memo:setsAsidePieces': 1,
      'memo:reservedWhole': 1,
      'memo:discards': 1,
      'memo:leftInBowl': 1,
      'memo:dips': 1,
      'memo:cutShare': 1,
      'memo:keptSolids': 1,
      'memo:panFatLines': 1,
      'memo:skinSentences': 1,
      'allSentences': 1,
      'memo:liftedFromMarinade': 1,
    },
  ),
  (
    'QUIET',
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    2,
    '15.00',
    1,
    {
      'indexes': 1,
      'memo:skinSentences': 1,
      'allSentences': 1,
      'lower': 1,
      'sentences': 16,
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
      'words': 288,
      'memo:naming': 1,
      'memo:strainAt': 1,
      'memo:savesRemainder': 1,
      'memo:setAsideLine': 1,
      'memo:setsAsidePieces': 1,
      'memo:reservedWhole': 1,
      'memo:discards': 1,
      'memo:dips': 1,
      'memo:leftInBowl': 1,
      'memo:keptSolids': 1,
    },
    {
      'indexes': 1,
      'memo:starter': 1,
      'heads': 1,
      'memo:braise': 1,
      'memo:strain': 1,
      'lower': 1,
      'sentences': 16,
      'memo:pourAway': 1,
      'cheese': 1,
      'memo:brines': 1,
      'memo:wordHeads': 1,
      'memo:brineWords': 1,
      'memo:parting': 1,
      'words': 288,
      'memo:naming': 1,
      'memo:strainAt': 1,
      'memo:savesRemainder': 1,
      'memo:setAsideLine': 1,
      'memo:setsAsidePieces': 1,
      'memo:reservedWhole': 1,
      'memo:discards': 1,
      'memo:leftInBowl': 1,
      'memo:dips': 1,
      'memo:cutShare': 1,
      'memo:keptSolids': 1,
      'memo:panFatLines': 1,
      'memo:skinSentences': 1,
      'allSentences': 1,
      'memo:liftedFromMarinade': 1,
    },
  ),
];
