// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v63 (batch M64 — corpus prints; matcherVersion 62; prep49
// design_v2 §2 M64, the owner's Q12 (a) under the standing authorization;
// zero requests; the bay, pear, pour-off, yield and strain readers read
// steps, so their reach is pre-Q18): kosher salt weighs half of table salt
// by volume (grams `_kosherSaltDensity` 0.60865 — SR 173468's '1 tsp' 6.0 g
// × ½, the corpus's "1 tablespoon kosher salt or 1½ teaspoons table salt";
// flake and coarse sea salt keep 0.72); a counted part set aside for another
// use is subtracted (engine `_partialUseOf`'s `pieces` arm: the pear half);
// "remove (the) bay leaf" discards the bay leaf (engine `_discardClauses`'
// remove arm, bay only) and a sub-gram piece prints its figure; a pour-off
// cuts the last oil-naming sentence before it in any earlier step (engine
// `_panOilAt`); a frying oil whose yield prints the oil out counts the
// difference of the printed volumes (engine `_yieldOilEaten`); "remove
// solids … discard" strains (H1, shipped on its condition). Every row value
// is the fresh compute of the WHOLE recipe (sections first) over recorded
// real FDC answers (FixtureProvider), equal to the v63 replay of snapshot 25
// (rp43, fix63 r2) on every pinned field and, on every row M64 must not
// move, to the v62 rows; never the network. Synthesized, STATED: the
// printed-yield flag test's four edits of the real 0053 YAML (closer 2: the
// yield's oil 1½ cups; the oil line 3 cups; the oil line "16 ounces (2
// cups)"; a yield printing no food and a bare oil, no towel in the
// steps) — and closer 3's four (verifier 3 D1/D2: the main recipe's
// servings printing its frying oil out; the section frying eggplant; the
// section's oil line as the corpus's plus line, with and without a step
// eating the tablespoon) — a person's edit of the hand-editable recipe;
// else none — the salt lines weighed alone (`resolveGrams`) are real corpus
// lines on the real SR 173468 record
// (sous-vide-rosemarymustard-seed-crusted-roast-beef|8,
// fougasse|8, ultranutty-pecan-bars|10, chocolate-caramel-layer-cake|25,
// browned-butter-blondies|10, beef-top-loin-roast-with-potatoes|1,
// garlic-and-olive-oil-mashed-potatoes|2), weighed outside their recipes.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title, position, raw, fdc id, confidence, grams, kcal,
/// basis) — an `auto` row of the fresh compute, no hold.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int,
  String,
  String,
  String,
  String,
);

const _crispSkinned = '0136-crisp-skinned-roast-chicken.yaml';
const _steakTacos = '0480-steak-tacos.yaml';
const _paiHuangGua = '0504-pai-huang-gua-smashed-cucumbers.yaml';
const _gravlax = '1148-gravlax.yaml';
const _pearCake = '0863-pear-walnut-upside-down-cake.yaml';
const _pasta = '0326-pasta-with-creamy-tomato-sauce.yaml';
const _adobo = '0128-filipino-chicken-adobo.yaml';
const _heartyBeef = '0006-hearty-beef-and-vegetable-stew.yaml';
const _carnitas = '0492-carnitas-mexican-pulled-pork.yaml';
const _paella = '0105-paella.yaml';
const _fortyCloves = '0452-chicken-with-40-cloves-of-garlic.yaml';
const _peppers = '0308-classic-stuffed-bell-peppers.yaml';
const _crispyBreasts =
    '0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml';
const _whiteChili = '0496-white-chicken-chili.yaml';
const _eggplant = '0053-crispy-thai-eggplant-salad.yaml';
const _guayTiew =
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml';
const _beerCan = '0640-grill-roasted-beer-can-chicken.yaml';
const _shallots = 'Fried Shallots and Fried Shallot Oil';
const _spiceRub = 'Spice Rub';

const String _kosher =
    " · kosher salt at half table salt's weight by volume (the corpus's own "
    '"1 tablespoon kosher salt or 1½ teaspoons table salt"; USDA SR 173468 '
    "'1 tsp' 6.0 g)";

const String _yieldFlag =
    "approximate (the difference of the yield's printed volumes: 2 cups in, "
    'about 1¾ cups out as shallot oil — the ¼ cup the shallots, the pan and '
    'the towel keep counted as eaten)';

const String _strained =
    'discarded in cooking — counted as 0 g · approximate (strained out and '
    'discarded — what it gives the liquid is not counted)';

/// R-D's pins (of its 90 rows on 173468, every one at its v62 grams × the
/// density ratio, pa_kosher_reach.tsv): the two lines printing the
/// conversion land their own table-salt alternative, 1½ × 6.0 = 9.00 g.
const List<_Row> _kosherRows = [
  (
    _crispSkinned,
    null,
    1,
    '1 tablespoon kosher salt or 1½ teaspoons table salt',
    173468,
    '1.000000',
    '9.00',
    '0.00',
    '1 tablespoon ≈ 15 mL$_kosher',
  ),
  (
    _steakTacos,
    null,
    8,
    '1 tablespoon kosher salt or 1½ teaspoons table salt',
    173468,
    '1.000000',
    '9.00',
    '0.00',
    '1 tablespoon ≈ 15 mL$_kosher',
  ),
  (
    _paiHuangGua,
    null,
    1,
    '1½ teaspoons kosher salt',
    173468,
    '1.000000',
    '4.50',
    '0.00',
    '1 1/2 teaspoon ≈ 7 mL$_kosher',
  ),
  (
    _gravlax,
    null,
    1,
    '¼ cup kosher salt',
    173468,
    '1.000000',
    '36.00',
    '0.00',
    '1/4 cup ≈ 59 mL$_kosher',
  ),
  (
    _eggplant,
    null,
    9,
    '1 teaspoon kosher salt',
    173468,
    '1.000000',
    '3.00',
    '0.00',
    '1 teaspoon ≈ 5 mL$_kosher',
  ),
  (
    _eggplant,
    _shallots,
    2,
    '½ teaspoon kosher salt',
    173468,
    '1.000000',
    '1.50',
    '0.00',
    '1/2 teaspoon ≈ 2 mL$_kosher',
  ),
  (
    _beerCan,
    _spiceRub,
    1,
    '2 tablespoons kosher salt',
    173468,
    '1.000000',
    '18.00',
    '0.00',
    '2 tablespoon ≈ 30 mL$_kosher',
  ),
];

/// The pear (P10), the 4 bay rows pinned of R4's 11, the pour-off (F9), the
/// shallot oil (the printed yield) and guay tiew's lemongrass (H1).
const List<_Row> _reach = [
  (
    _pearCake,
    null,
    4,
    '3 ripe but firm Bosc pears (8 ounces each)',
    167778,
    '0.864444',
    '442.25',
    '296.31',
    '3 × 227 g (printed weight) × 0.78 edible · approximate (USDA AH-102 item 1734: pears, raw whole → pared, cored flesh 78 % (40–88); the steps peel it) · 1 pear half saved for another use (step 2) — only the rest counted',
  ),
  (
    _pasta,
    null,
    3,
    '1 bay leaf',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 4) — counted as 0 g',
  ),
  (
    _adobo,
    null,
    5,
    '4 bay leaves',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    _heartyBeef,
    null,
    12,
    '2 bay leaves',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    _carnitas,
    null,
    2,
    '2 bay leaves',
    170917,
    '0.866667',
    '0.00',
    '0.00',
    'removed and discarded (step 2) — counted as 0 g',
  ),
  (
    _crispyBreasts,
    null,
    2,
    '2 tablespoons vegetable oil',
    2710180,
    '0.923333',
    '9.07',
    '81.62',
    '2 teaspoons kept (the steps pour off the rest)',
  ),
  (
    _eggplant,
    _shallots,
    1,
    '2 cups vegetable oil',
    2710180,
    '0.923333',
    '56.00',
    '504.00',
    'discarded in cooking — only the part the recipe keeps counted · $_yieldFlag',
  ),
  (
    _guayTiew,
    null,
    1,
    '2 lemongrass stalks, trimmed to bottom 6 inches',
    168573,
    '0.920000',
    '0.00',
    '0.00',
    _strained,
  ),
];

/// Rows M64 must not move, each equal to its v62 row but for R4b's basis
/// (the bay leaf's figure): paella's bay leaf ("if it can be easily
/// removed" — no "remove" clause), the 40-cloves bay leaf (never removed),
/// the carnitas onion in the bay leaves' own "remove" clause (bay only), the
/// stuffed peppers lifted out of their pot (bay only), white chicken chili's
/// oil (newly reached by the pour-off window: 1 tablespoon kept of its 1
/// tablespoon), the eggplant's main frying oil, and guay tiew's scallions
/// (the greens go in after the strain), chiles (one sliced, eaten) and
/// galangal (no strained head: weighed on ginger, kept — a stated gap).
const List<_Row> _negatives = [
  (
    _paella,
    null,
    13,
    '1 bay leaf',
    170917,
    '0.866667',
    '0.20',
    '0.63',
    '1 × 0.2 g each',
  ),
  (
    _fortyCloves,
    null,
    9,
    '1 bay leaf',
    170917,
    '0.866667',
    '0.20',
    '0.63',
    '1 × 0.2 g each',
  ),
  (
    _carnitas,
    null,
    1,
    '1 small onion, peeled and halved',
    790646,
    '0.936667',
    '70.00',
    '26.60',
    '1 × 70 g each',
  ),
  (
    _peppers,
    null,
    1,
    '4 medium red, yellow, or orange bell peppers (about 6 ounces each), ½ inch trimmed off tops, cores and seeds discarded',
    2258589,
    '0.660000',
    '680.39',
    // The record's first energy number, 957 30.8 (the replay's kcalPer100g
    // prices 209.38 — unchanged from v62 either way).
    '209.56',
    '4 × 170 g (printed weight)',
  ),
  (
    _whiteChili,
    null,
    2,
    '1 tablespoon vegetable oil',
    2710180,
    '0.923333',
    '14.00',
    '126.00',
    '1 tablespoon · USDA portion',
  ),
  (
    _eggplant,
    null,
    10,
    '2 cups vegetable oil',
    2710180,
    '0.923333',
    '40.82',
    '367.38',
    'discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 6.0 % of the raw eggplant\'s weight — derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in vegetable oil" (no record for eggplant; read as Fast foods, potato, french fried in vegetable oil))',
  ),
  (
    _guayTiew,
    null,
    2,
    '4 scallions, trimmed, white parts left whole, green parts cut into 1-inch lengths',
    2709794,
    '0.943333',
    '60.00',
    '19.20',
    '4 × 15 g each',
  ),
  (
    _guayTiew,
    null,
    4,
    '2 Thai chiles, stemmed (1 left whole, 1 sliced thin), divided, plus 2 Thai chiles, stemmed and sliced thin, for serving (optional)',
    2709798,
    '0.518333',
    '4.00',
    '1.36',
    '2 × 2 g each',
  ),
  (
    _guayTiew,
    null,
    5,
    '1 (2-inch) piece fresh galangal, peeled and sliced into ¼-inch-thick rounds',
    169231,
    '1.000000',
    '16.00',
    '12.80',
    "1 piece × 2 inch × 8 g per inch · approximate (ginger's figure (ATK's substitute for galangal)) · approximation (counted as Ginger root, raw)",
  ),
];

/// The salt lines weighed alone on SR 173468 (real corpus lines, outside
/// their recipes): (raw, grams, basis). The five flake / coarse sea salts
/// keep the round 0.72 under their own name (no suffix), table salt its
/// 1.22, and a plus line ends with kosher's suffix.
const List<(String, String, String)> _salts = [
  ('2 tablespoons flake sea salt', '21.29', '2 tablespoon ≈ 30 mL'),
  ('2 teaspoons coarse sea salt, divided', '7.10', '2 teaspoon ≈ 10 mL'),
  ('½ teaspoon flake sea salt (optional)', '1.77', '1/2 teaspoon ≈ 2 mL'),
  (
    '¼-½ teaspoon coarse sea salt (optional)',
    '1.33',
    '1/4-1/2 teaspoon ≈ 2 mL',
  ),
  (
    '¼–½ teaspoon flake sea salt, crumbled (optional)',
    '1.33',
    '1/4–1/2 teaspoon ≈ 2 mL',
  ),
  ('2⅛ teaspoons table salt', '12.78', '2 1/8 teaspoon ≈ 10 mL'),
  (
    '2 tablespoons plus 2 teaspoons kosher salt, divided',
    '24.00',
    '2 tablespoon ≈ 30 mL + 2 teaspoons kosher salt$_kosher',
  ),
];

/// The row's energy, as the totals read it (the record's first energy
/// number, else its Atwater sum): grams × kcal per 100 g.
double _kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine line) {
  final grams = row.grams ?? 0;
  if (grams <= 0) {
    return 0;
  }
  expect(nutrientSiblings[row.fdcId], isNull);
  final food = knownFood(db, row.fdcId!, line: line)!;
  for (final number in nutrientDefs.first.fdcNumbers) {
    if (food.nutrientsPer100g[number] case final per100?) {
      return per100 * grams / 100;
    }
  }
  return kcalPer100g(food) * grams / 100;
}

String _g2(double v) => v.toStringAsFixed(2);

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    // RE-PIN (M66 batch, v65): matcherVersion 64 (was 63).
    // RE-PIN (M67 batch, v66): matcherVersion 65 (was 64).
    // RE-PIN (M68 batch, v67): matcherVersion 66 (was 65).
    expect(matcherVersion, 66);
  });

  test("kosher salt's figure is half of SR 173468's '1 tsp' 6.0 g by "
      'volume', () {
    expect((6.0 / 4.92892 * 0.5).toStringAsFixed(5), '0.60865');
    // The brine salt's 44 mL threshold in kosher grams (was 31.7 at 0.72).
    expect(_g2(44 * 0.60865), '26.78');
  });

  group('matcher v63 (batch M64)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    /// [recipe] stored and computed whole, its sections first, as the
    /// replay does; the stored recipe.
    Future<Recipe> compute(Recipe recipe) async {
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

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v63-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _) in [
        ..._kosherRows,
        ..._reach,
        ..._negatives,
      ]) {
        if (!recipes.containsKey(file)) {
          recipes[file] = await compute(loadCorpusRecipe(file));
        }
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    /// [file]'s stored recipe, or its [section]'s (by title).
    Recipe recipeIn(String file, String? section) => section == null
        ? recipes[file]!
        : nutritionRecipeOf(
            db,
            sectionKeyOf(recipes[file]!.id, section),
          )!.recipe;

    IngredientMatchRow rowIn(String file, int position, {String? section}) => db
        .ingredientMatchesFor(recipeIn(file, section).id)
        .singleWhere((m) => m.position == position);

    String? basisIn(String file, int position, {String? section}) =>
        gramBasisFor(
          db,
          nutritionLines(recipeIn(file, section))[position],
          rowIn(file, position, section: section),
          recipe: recipeIn(file, section),
        );

    /// Each [rows] entry in its whole recipe (or its section): the record,
    /// the confidence, the grams, the energy and the basis; `auto`, no
    /// hold.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            confidence,
            grams,
            kcal,
            basis,
          )
          in rows) {
        final line = nutritionLines(recipeIn(file, section))[position];
        final row = rowIn(file, position, section: section);
        final reason = '$file|${section ?? ''}|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(_g2(_kcalOf(db, row, line)), kcal, reason: reason);
        expect(
          basisIn(file, position, section: section),
          basis,
          reason: reason,
        );
      }
    }

    test('R-D: kosher salt weighs half of table salt by volume, with its '
        'suffix — the two lines printing the conversion land their own '
        'table-salt alternative, 9.00 g', () {
      expectRows(_kosherRows);
      // "1½ teaspoons table salt" on 173468's own '1 tsp' 6.0 g.
      expect(_g2(1.5 * 6.0), rowIn(_crispSkinned, 1).grams!.toStringAsFixed(2));
    });

    test('R-D: flake and coarse sea salt keep 0.72, table salt 1.22, and a '
        "plus line ends with kosher's suffix (real lines weighed alone on "
        'SR 173468)', () {
      final salt = knownFood(db, 173468)!;
      for (final (raw, grams, basis) in _salts) {
        final parsed = parseIngredientLine(raw);
        final resolved = resolveGrams(
          amounts: parsed.amounts,
          food: salt,
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        )!;
        expect(_g2(resolved.grams), grams, reason: raw);
        expect(resolved.source, GramSource.density, reason: raw);
        expect(resolved.basis, basis, reason: raw);
      }
    });

    test(
      'M64 reaches its pear, bay, pour-off, shallot-oil and strain rows',
      () {
        expectRows(_reach);
      },
    );

    test('P10: one pear half of six saved — 3 × 227 g × 0.78 × 5/6', () {
      expect(
        _g2(rowIn(_pearCake, 4).grams!),
        _g2(3 * 226.796185 * 0.78 * 5 / 6),
      );
      expect(rowIn(_pearCake, 4).gramSource, 'discarded');
    });

    test("the printed oil yield: ¼ cup of 2 cups on 2710180's 224 g cup; "
        'the routed parent reads the section total STORED at 1 dp (511.10 '
        'g) × ⅓ — 170.37 g, 276.86 kcal', () {
      final oil = rowIn(_eggplant, 1, section: _shallots);
      expect(_g2(oil.grams!), _g2(0.25 * 224));
      final key = sectionKeyOf(recipes[_eggplant]!.id, _shallots);
      final child = db.nutritionFor(key)!;
      expect(child.totalGrams!.toStringAsFixed(2), '511.10');
      final parent = rowIn(_eggplant, 14);
      expect(parent.childRecipeId, key);
      expect(parent.gramSource, 'recipe');
      expect(_g2(parent.grams!), '170.37');
      expect(_g2(parent.grams!), _g2(child.totalGrams! * parent.childShare!));
      expect(
        _g2(batchTotalsOf(child)['energy']! * parent.childShare!),
        '276.86',
      );
      expect(
        basisIn(_eggplant, 14),
        'from the recipe Fried Shallots and Fried Shallot Oil: 170 g, 277 kcal',
      );
      // The Spice Rub's kosher line moves its routed parent's grams only.
      final rub = sectionKeyOf(recipes[_beerCan]!.id, _spiceRub);
      final beerCan = rowIn(_beerCan, 3);
      expect(beerCan.childRecipeId, rub);
      expect(db.nutritionFor(rub)!.totalGrams!.toStringAsFixed(2), '107.40');
      expect(_g2(beerCan.grams!), '20.14');
      expect(
        _g2(
          batchTotalsOf(db.nutritionFor(rub)!)['energy']! * beerCan.childShare!,
        ),
        '49.74',
      );
    });

    test('the printed-yield flag names the prints it subtracts (closer 2, '
        'verifier 2 D1) — STATED synthesized edits of the real 0053 YAML, '
        "a person's edit of the hand-editable recipe", () async {
      const line =
          '    - raw: 2 cups vegetable oil\n'
          '      amounts:\n'
          '      - measure: volume\n'
          "        quantity: '2'\n";
      final text = File('$corpusRecipesDir/$_eggplant').readAsStringSync();
      expect(line.allMatches(text), hasLength(1)); // the section's line
      const flag =
          'discarded in cooking — only the part the recipe keeps counted · '
          "approximate (the difference of the yield's printed volumes: ";
      for (final (edit, grams, basis)
          in <(String Function(String), String, String)>[
            (
              (s) => s.replaceFirst(
                'ABOUT 1¾ CUPS FRIED SHALLOT OIL',
                'ABOUT 1½ CUPS FRIED SHALLOT OIL',
              ),
              '112.00',
              '2 cups in, about 1½ cups out as shallot oil — the ½ cup the '
                  'shallots, the pan and the towel keep counted as eaten)',
            ),
            (
              (s) => s.replaceFirst(
                line,
                line
                    .replaceFirst('2 cups', '3 cups')
                    .replaceFirst("'2'", "'3'"),
              ),
              '280.00',
              '3 cups in, about 1¾ cups out as shallot oil — the 1¼ cups the '
                  'shallots, the pan and the towel keep counted as eaten)',
            ),
            // The volume a weight-first line prints is the amount subtracted;
            // its ¼ cup weighs at oil's 0.92 g/mL (59.15 mL × 0.92), as the
            // line weighs by its ounces and no portion of 2710180 is read.
            (
              (s) => s
                  .replaceFirst(
                    line,
                    '    - raw: 16 ounces (2 cups) vegetable oil\n'
                    '      amounts:\n'
                    '      - measure: weight\n'
                    "        quantity: '16'\n"
                    '        unit: ounce\n'
                    '        approximate: false\n'
                    '        primary: true\n'
                    '      - measure: volume\n'
                    "        quantity: '2'\n",
                  )
                  .replaceFirst(
                    '        unit: cup\n        approximate: false\n'
                        '        primary: true\n      item: vegetable oil',
                    '        unit: cup\n        approximate: false\n'
                        '        primary: false\n      item: vegetable oil',
                  ),
              '54.42',
              '2 cups in, about 1¾ cups out as shallot oil — the ¼ cup the '
                  'shallots, the pan and the towel keep counted as eaten)',
            ),
            // A yield printing no food and a bare oil, no towel in the steps.
            (
              (s) => s
                  .replaceFirst(
                    'MAKES ABOUT 1½ CUPS FRIED SHALLOTS AND ABOUT 1¾ CUPS '
                        'FRIED SHALLOT OIL',
                    'SERVES 4 AND ABOUT 1¾ CUPS OIL',
                  )
                  .replaceAll('towel', 'rack'),
              '56.00',
              '2 cups in, about 1¾ cups out as oil — the ¼ cup the food and '
                  'the pan keep counted as eaten)',
            ),
          ]) {
        final dir = Directory.systemTemp.createTempSync('salt-v63-yield-');
        final edited = SaltDatabase.open(
          ServerConfig(
            dataDir: dir.path,
            logLevel: Level.WARNING,
            trustProxy: false,
          ).dbPath,
        )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
        try {
          final changed = edit(text);
          expect(changed, isNot(text));
          final recipe = RecipeYamlCodec.decode(changed).recipe;
          edited.upsertRecipe(recipe, sourceSlug: _source, contentHash: grams);
          final key = sectionKeyOf(recipe.id, _shallots);
          final section = nutritionRecipeOf(edited, key)!.recipe;
          expect(await matchAndCompute(edited, provider, section), isNull);
          final row = edited
              .ingredientMatchesFor(section.id)
              .singleWhere((m) => m.position == 1);
          expect(row.grams!.toStringAsFixed(2), grams, reason: basis);
          expect(
            gramBasisFor(
              edited,
              nutritionLines(section)[1],
              row,
              recipe: section,
            ),
            '$flag$basis',
          );
        } finally {
          edited.dispose();
          dir.deleteSync(recursive: true);
        }
      }
    });

    test("a printed yield's part is all the oil eaten: no uptake on top, and "
        'a plus line names what it counts (closer 3, verifier 3 D1/D2) — '
        "STATED synthesized edits of the real 0053 YAML, a person's edit of "
        'the hand-editable recipe', () async {
      const oilLine =
          '    - raw: 2 cups vegetable oil\n'
          '      amounts:\n'
          '      - measure: volume\n'
          "        quantity: '2'\n";
      const oilItem = '        primary: true\n      item: vegetable oil\n';
      final text = File('$corpusRecipesDir/$_eggplant').readAsStringSync();
      expect(oilLine.allMatches(text), hasLength(1)); // the section's line
      expect(
        '$oilItem      prep: null\n    - raw: ½ teaspoon kosher salt'
            .allMatches(text),
        hasLength(1),
      ); // the section's item
      // The corpus's own plus encoding (pork-schnitzel: "2 cups plus 1
      // tablespoon vegetable oil", item "plus 1 tablespoon vegetable oil"),
      // on the section's line.
      String plus(String s) => s
          .replaceFirst(
            oilLine,
            oilLine.replaceFirst(
              '2 cups vegetable oil',
              '2 cups plus 1 tablespoon vegetable oil',
            ),
          )
          .replaceFirst(
            '$oilItem      prep: null\n    - raw: ½ teaspoon kosher salt',
            '        primary: true\n      item: plus 1 tablespoon vegetable '
                'oil\n      prep: null\n    - raw: ½ teaspoon kosher salt',
          );
      String flag(String oil, String food) =>
          " · approximate (the difference of the yield's printed volumes: 2 "
          'cups in, about 1¾ cups out as $oil — the ¼ cup the $food, the pan '
          'and the towel keep counted as eaten)';
      const keeps = 'discarded in cooking — only the part the recipe keeps';
      // (edit, section (null: the main recipe), position, grams, basis)
      for (final (edit, section, position, grams, basis)
          in <(String Function(String), String?, int, String, String)>[
            // D1: the MAIN recipe prints its frying oil out; the eggplant it
            // fries (6.0 % uptake, 40.82 g unedited) is inside the ¼ cup.
            (
              (s) => s.replaceFirst(
                'servings: SERVES 2 TO 3\n',
                'servings: SERVES 2 TO 3 AND ABOUT 1¾ CUPS FRYING OIL\n',
              ),
              null,
              10,
              '56.00',
              '$keeps counted${flag('frying oil', 'food')}',
            ),
            // D1: the section fries an uptake food (eggplant) in its oil.
            (
              (s) => s
                  .replaceFirst(
                    '    - raw: 1 pound shallots, peeled\n',
                    '    - raw: 1 pound large Japanese eggplants, peeled\n',
                  )
                  .replaceFirst(
                    '      item: shallots\n      prep: peeled\n',
                    '      item: large Japanese eggplants\n      prep: peeled\n',
                  )
                  .replaceFirst(
                    'Combine shallots and oil in medium saucepan and heat over '
                        'high heat,',
                    'Heat oil in medium saucepan to 375 degrees. Fry eggplant '
                        'over high heat,',
                  ),
              _shallots,
              1,
              '56.00',
              '$keeps counted${flag('shallot oil', 'shallots')}',
            ),
            // D2: a plus part no step eats is not named; the yield's is.
            (
              plus,
              _shallots,
              1,
              '56.00',
              '$keeps counted${flag('shallot oil', 'shallots')}',
            ),
            // D2: a plus part a step eats is named beside the yield's part.
            (
              (s) => plus(s).replaceFirst(
                'Slide shallots off paper towel directly onto sheet;',
                'Drizzle 1 tablespoon oil over shallots. Slide shallots off '
                    'paper towel directly onto sheet;',
              ),
              _shallots,
              1,
              '70.00',
              'discarded in cooking — only "plus 1 tablespoon vegetable oil" '
                  'and the part the recipe keeps counted'
                  '${flag('shallot oil', 'shallots')}',
            ),
          ]) {
        final dir = Directory.systemTemp.createTempSync('salt-v63-kept-');
        final edited = SaltDatabase.open(
          ServerConfig(
            dataDir: dir.path,
            logLevel: Level.WARNING,
            trustProxy: false,
          ).dbPath,
        )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
        try {
          final changed = edit(text);
          expect(changed, isNot(text));
          final recipe = RecipeYamlCodec.decode(changed).recipe;
          edited.upsertRecipe(recipe, sourceSlug: _source, contentHash: basis);
          final stored = edited.recipeByIdOrSlug(recipe.id)!.recipe;
          for (final key in sectionChildKeysOf(
            edited,
            stored,
            ResolverMemo(edited),
          )) {
            expect(
              await matchAndCompute(
                edited,
                provider,
                nutritionRecipeOf(edited, key)!.recipe,
              ),
              isNull,
            );
          }
          expect(await matchAndCompute(edited, provider, stored), isNull);
          final target = section == null
              ? stored
              : nutritionRecipeOf(
                  edited,
                  sectionKeyOf(recipe.id, section),
                )!.recipe;
          final row = edited
              .ingredientMatchesFor(target.id)
              .singleWhere((m) => m.position == position);
          expect(row.status, 'auto', reason: basis);
          expect(row.hold, isNull, reason: basis);
          expect(row.grams!.toStringAsFixed(2), grams, reason: basis);
          expect(
            gramBasisFor(
              edited,
              nutritionLines(target)[position],
              row,
              recipe: target,
            ),
            basis,
          );
          final items =
              (await matchesBody(edited, provider, target))['items']!
                  as List<Map<String, Object?>>;
          expect(
            (items[position]['match']! as Map)['gram_basis'],
            basis,
            reason: 'GET',
          );
        } finally {
          edited.dispose();
          dir.deleteSync(recursive: true);
        }
      }
    });

    test("the rows M64 must not move equal v62 (R4b prints the bay leaf's "
        'figure)', () {
      expectRows(_negatives);
    });

    test('R4 is the bay leaf only: a "remove" clause naming the stuffed '
        'peppers (lifted out of their pot to be filled) or the carnitas '
        "onion (in the bay leaves' own clause) never zeroes them", () {
      expect(
        [
          _g2(rowIn(_peppers, 1).grams!),
          _g2(rowIn(_carnitas, 1).grams!),
          _g2(rowIn(_carnitas, 2).grams!),
        ],
        ['680.39', '70.00', '0.00'],
      );
    });

    test('the matches GET shows each reach basis', () async {
      for (final (file, section, position, _, _, _, _, _, basis) in [
        ..._kosherRows,
        ..._reach,
      ]) {
        final items =
            (await matchesBody(db, provider, recipeIn(file, section)))['items']!
                as List<Map<String, Object?>>;
        final match = items[position]['match'] as Map<String, Object?>?;
        expect(
          match?['gram_basis'],
          basis,
          reason: '$file|${section ?? ''}|$position',
        );
      }
    });

    test('the recipes move kcal per serving', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      expect(
        [
          for (final file in const [
            _pearCake,
            _crispyBreasts,
            _eggplant,
            _adobo,
            _pasta,
            _heartyBeef,
            _carnitas,
            _guayTiew,
          ])
            of(file),
        ],
        // A fresh compute here; the unchanged v62 tree's fresh compute in
        // the comment, then the replay's v62 → v63 — the same move (the
        // absolute figures differ by the energy the fixtures' cache reads).
        const [
          ('complete', '525.79'), // 533.20; 533.20 → 525.79 (P10)
          ('partial', '404.07'), // 489.26; 489.04 → 403.85 (F9)
          ('complete', '504.00'), // 420.00; 419.95 → 503.95 (the yield)
          ('complete', '670.38'), // 671.01; 670.73 → 670.11 (bay)
          ('complete', '748.47'), // 748.63; 748.58 → 748.42 (bay)
          ('partial', '678.50'), // 678.81; 678.78 → 678.46 (bay)
          ('complete', '715.06'), // 715.27; 715.27 → 715.06 (bay)
          ('partial', '596.80'), // 601.75; 601.77 → 596.82 (H1)
        ],
      );
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _pearCake,
        _adobo,
        _crispyBreasts,
        _eggplant,
        _guayTiew,
        _crispSkinned,
      ]) {
        final recipe = recipes[file]!;
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        expect(rows(), before, reason: file);
      }
    });
  });
}
