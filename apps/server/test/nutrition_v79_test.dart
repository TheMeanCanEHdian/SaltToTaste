// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v79 (batch M79 — records read in L50; matcherVersion 76; prep50
// design_v2 §2 M79 as the planner corrected it (plan_figures.md C0–C13,
// CC5–CC9), the orchestrator's Q9 (a) at option A, Q9 (b) HOLD and Q10
// (b′); zero requests; reach PRE-Q18): rule 1 — crystallized ginger ranks
// as SR 167781 "Candied fruit" (matcher `_rankAs` reading the cached
// 'candied ginger' answer, `approximationRecords`), flagged (engine
// `trimStandInFlagOf`), weighed at a Branded label's ¼ cup, 30 g (grams
// `_densities` + `_approximateDensities`); candied peel HELD (no printed
// volume of the candied product). Rule 2 — Foundation 2747675 (seedless
// watermelon, no energy, no portion) reads SR 167765's nutrients AND cups
// (engine `nutrientSiblings`, grams `volumeSiblings` — the napa precedent).
// Rule 3 — both racks of lamb rank as the cached 'lamb rib separable lean
// and fat choice raw' answer (top 174321, a HIT) and engine
// `trimDepthRecords`' APPENDED `\btrimmed\b` entry moves the ⅛-inch SR
// 174377 first (its DETAIL; grams `ah102Meats[174377]`), deducted at the
// dry-heat pair its steps' cooking keeps (engine `dryHeatKept`, read by the
// NEW `_dryHeatOf` through `braisedKeptOf`'s ONE `recomputeTotals` arm):
// 0228 roasted (S1 heats the oven, S3 pours off the fat), 0622 broiled (S1
// heats the grill). THE INVARIANT: the deduction (`recomputeTotals`), the
// basis (`gramBasisFor`) and the GET sheet (`candidatesForLine`) read the
// same recipe. Every row value is the fresh compute of the WHOLE recipe
// over recorded real FDC answers (FixtureProvider) and equals the v79
// replay of snapshot 28 (rp43) on every pinned field EXCEPT where the
// fixtures hold a record as a search hit and the snapshot its detail (each
// stated at its pin; the same on the v78 tree). Never the network.
// Fixtures added (snapshot 28, --from-db on a fresh copy, JSON-equal; 0
// existing entries changed): foods 167765, 167781, 174377; searches 'lamb
// rib separable lean and fat choice raw' (the racks' rank-as answer) and,
// for the negatives' whole recipes, 'bell pepper', 'boneless half leg of
// lamb', 'hot smoked paprika', 'red or sweet onion', 'tube almond paste',
// 'turnips'; and, for the held vehicle the v7, v41 and accuracy pins now
// read (the watermelon is counted), the search 'medium-roast coffee beans'
// and the food 747430. Every line is a corpus line. STATED synthesized inputs: the
// step-less copy of 0228 (no step, no cooking: gross); the copy of 0228
// with 0622 S1's real grill sentence added (the grill wins over a roast —
// no corpus recipe prints a grill heat, an oven heat and a fat pour-off);
// the gate's hypothetical line–record pairs (a rack line on 174377 asked
// with OTHER real corpus recipes' steps — the gate reads only the steps);
// two hypothetical line–record pairs for the new arms' gates (the closer,
// verify1 D2 / D3): Struffoli's real candied-cherries line asked on 167781,
// and Roast Butterflied Leg of Lamb's real line ranked over the racks'
// rank-as answer; for the heat regexes' gates (the closer, verify2 D1) the
// rack line asked with 0613's and 0075-skillet-roasted-chicken-breasts' real
// steps (hypothetical pairs) and two copies of 0088 with one synthesized
// sentence each ("Heat the ovenproof skillet …", "Heat the grillpan …");
// the pour-off test's three negative forms (fat before the pour-off, fat
// past a period, no boundary after "off").

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _carrot = '0015-carrot-ginger-soup.yaml';
const _chutney =
    '0178-cranberry-chutney-with-apples-and-crystallized-ginger.yaml';
const _gingerbread = '0877-gingerbread-layer-cake.yaml';
const _slab = '1204-triple-berry-slab-pie-with-ginger-lemon-streusel.yaml';
const _watermelon = '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml';
const _roast = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
const _grilled = '0622-grilled-rack-of-lamb.yaml';
const _stollen = '1197-stollen.yaml';
const _struffoli = '1163-struffoli-neapolitan-honey-balls.yaml';
const _pumpkin = '0987-pumpkin-pie.yaml';
const _boneless =
    '0229-roast-boneless-leg-of-lamb-with-garlic-herb-and-bread-crumb-crust.yaml';
const _butterflied =
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml';
const _curry = '0567-indian-curry.yaml';
const _arayes =
    '0579-grilled-arayes-grilled-lamb-stuffed-pitas-with-yogurt-sauce.yaml';
const _kebabs = '0620-grilled-lamb-kebabs.yaml';
const _kofte = '0622-grilled-lamb-kofte.yaml';
const _stew = '1070-irish-stew-with-carrots-and-turnips.yaml';
const _kousa = '1175-kousa-mihshi-lebanese-stuffed-squash.yaml';
const _shanks =
    '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml';
const _files = [
  _carrot, _chutney, _gingerbread, _slab, _watermelon, _roast, _grilled, //
  _stollen, _struffoli, _pumpkin, _boneless, _butterflied, _curry, _arayes,
  _kebabs, _kofte, _stew, _kousa, _shanks,
];

/// The design's pour-off regex (§2 M79), its `[^.]*` kept: the reference
/// [pourOffFatSentence] answers as.
final _design = RegExp(r'\bpour off\b[^.]*\bfat\b');

/// CC6's flag text, verbatim, and the label the density names.
const _gingerFlag =
    'approximate (FDC holds no crystallized ginger — a stand-in by class: SR '
    "167781 Candied fruit (322 kcal); weighed at a Branded label's ¼ cup of "
    'the product as sold, 30 g — FDC Branded 2132938 and three others; nine '
    '¼-cup labels print 28–50 g, every printed volume 0.47–1.01 g/mL)';
const _gingerLabel =
    "approximate (crystallized ginger labels (FDC Branded 2132938 CIBO VITA, 2106313 Sugar 'N Spice, "
    '1900068 Tree of Life, 1981078 Price Chopper; the modal of nine ¼-cup '
    'labels, 28–50 g): ¼ cup = 30 g)';
String _ginger(String volume) =>
    '$volume · $_gingerLabel · approximation (counted as Candied fruit) · '
    '$_gingerFlag';

/// The racks' flags (the brief's text; with no gate answer, its "…
/// counted gross (no step prints the cooking)" after the common prefix).
const _domestic =
    "approximate (USDA's domestic choice rib at ⅛\", unfrenched — the recipe "
    'prefers domestic lamb; ';
const _roastedFlag =
    '${_domestic}its roasted pair 174377 → 172552 keeps 70.1 % of the energy '
    'and 62.9 % of the fat by the protein tracer — the drippings, deducted; '
    "the frenched bones' trim not deducted)";
const _broiledFlag =
    '${_domestic}its broiled pair 174377 → 174378 keeps 65.9 % of the energy '
    'and 57.9 % of the fat by the protein tracer — the drippings, deducted; '
    "the frenched bones' trim not deducted)";
const _grossFlag = '${_domestic}counted gross (no step prints the cooking))';
const _ah102 =
    'approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → '
    'lean and fat meat, slightly trimmed 73 % (61–88), as measured '
    'unfrenched; a frenched rack yields less)';

/// (file, position, raw, fdc id, grams, gram source, kcal (the nutrient
/// sibling's where one is mapped; gross for the racks), basis) — the seven
/// rows M79 moves, as the v79 replay holds them.
const _reach = [
  (
    _carrot,
    2,
    '¼ cup minced crystallized ginger',
    167781,
    '30.00',
    'density',
    '96.60',
    '1/4 cup ≈ 59 mL',
  ),
  (
    _chutney,
    9,
    '⅓ cup minced crystallized ginger',
    167781,
    '40.00',
    'density',
    '128.80',
    '1/3 cup ≈ 79 mL',
  ),
  // "(optional)" — counted: M75's `_optionalLine` reads reference lines only.
  (
    _gingerbread,
    22,
    '¼ cup chopped crystallized ginger (optional)',
    167781,
    '30.00',
    'density',
    '96.60',
    '1/4 cup ≈ 59 mL',
  ),
  (
    _slab,
    3,
    '½ cup crystallized ginger, chopped fine',
    167781,
    '60.00',
    'density',
    '193.20',
    '1/2 cup ≈ 118 mL',
  ),
  (
    _watermelon,
    5,
    '6 cups 1½-inch seedless watermelon pieces',
    2747675,
    '918.00',
    'portion',
    '275.40',
    '6 cup · USDA portion of "Watermelon, raw" · nutrients of "Watermelon, raw"',
  ),
  (
    _roast,
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    174377,
    '1241.71',
    'weight',
    '4246.64',
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · $_ah102 · $_roastedFlag',
  ),
  (
    _grilled,
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    174377,
    '1076.15',
    'weight',
    '3680.42',
    '2 × 737 g (printed 1½–1¾ lb, the midpoint) × 0.73 edible · $_ah102 · $_broiledFlag',
  ),
];

/// The negatives, byte-equal to the v78 replay (= v79's): the fresh and
/// ground ginger beside the reach, the HELD candied peel (Q9 (b)) and
/// cherries, the candied yams (their 'candied yams' answer ALSO holds
/// 167781 — the rank words keep 170071), the racks' EVOO (M77's), and the
/// other lamb rows (four of them print "trimmed" on a top that is not
/// 174321 — the appended entry's key gate). (file, position, raw, fdc id,
/// grams, kcal) — null where the line has none.
const _negatives = [
  (_carrot, 3, '1 tablespoon grated fresh ginger', 169231, '7.98', '6.39'),
  (
    _chutney,
    2,
    '2 teaspoons finely grated fresh ginger',
    169231,
    '5.32',
    '4.26',
  ),
  (_gingerbread, 9, '2 tablespoons ground ginger', 170926, '10.94', '36.66'),
  (_slab, 5, '1 tablespoon ground ginger', 170926, '5.47', '18.33'),
  (_stollen, 6, '½ cup chopped candied lemon peel', 167749, '48.00', '22.56'),
  (_stollen, 7, '½ cup chopped candied orange peel', 169103, '48.00', '46.56'),
  (
    _struffoli,
    11,
    '2 tablespoons candied orange peel, chopped fine (optional)',
    169103,
    '12.00',
    '11.64',
  ),
  (_struffoli, 12, '8 candied cherries (optional)', 167563, null, null),
  (_pumpkin, 6, '1 cup candied yams, drained', 170071, '150.00', '177.00'),
  (_roast, 6, '¼ cup extra-virgin olive oil', 748608, '54.42', '481.03'),
  (
    _boneless,
    7,
    '1 (3½- to 4-pound) boneless half leg of lamb, trimmed and pounded to ¾-inch thickness',
    174406,
    '1700.97',
    '4320.46',
  ),
  (
    _butterflied,
    0,
    '1 (6- to 8-pound) butterflied leg of lamb',
    174315,
    '3175.14',
    '6382.04',
  ),
  (
    _curry,
    14,
    '1½ pounds boneless leg of lamb, trimmed and cut into ¾-inch cubes',
    172659,
    '680.39',
    '1272.33',
  ),
  // 2,146.46 in the replay: the fixtures hold Foundation 2727570 as a search
  // hit and the library its detail (the kofte and kousa the same).
  (_arayes, 17, '2 pounds ground lamb', 2727570, '907.18', '2150.03'),
  (
    _kebabs,
    1,
    '1 (2¼-pound) shank end boneless leg of lamb, trimmed and cut into 1-inch chunks',
    174315,
    '1020.58',
    '2051.37',
  ),
  (_kofte, 15, '1½ pounds ground lamb', 2727570, '680.39', '1612.52'),
  (
    _stew,
    0,
    '4½ pounds lamb shoulder chops, each 1 to 1½ inches thick',
    174875,
    '1341.81',
    '3689.99',
  ),
  (_kousa, 1, '8 ounces ground lamb', 2727570, '226.80', '537.51'),
  (
    _shanks,
    0,
    '6 (12- to 16-ounce) lamb shanks, trimmed',
    172513,
    '1666.95',
    '3050.52',
  ),
];

/// (file, status, per serving, stored batch energy) after the compute.
const _totals = [
  // 153.01 / 918.05 in the replay: the fixtures hold Foundation 2258586
  // (the carrots) as a search hit and the library its detail.
  (_carrot, 'complete', '153.02', '918.12'),
  (_chutney, 'complete', '471.63', '1414.90'),
  (_gingerbread, 'complete', '731.60', '8779.23'),
  // 8,439.10 in the replay: the berries' hits (Foundation 2346411 / 2346410:
  // +0.25 / −0.21 kcal); per serving the same.
  (_slab, 'complete', '468.84', '8439.13'),
  // 223.27 / 893.07 in the replay: the cotija's hit (2647443).
  (_watermelon, 'complete', '223.18', '892.73'),
  (_roast, 'complete', '886.76', '3547.05'),
  (_grilled, 'complete', '650.93', '2603.70'),
];

/// A provider that remembers every detail it was asked for — the racks'
/// top-of-answer 174321 is a HIT only; a weight read on it would fetch.
class _Asked extends FixtureProvider {
  _Asked() : super(pending: {...pendingSearches});
  final List<int> asked = [];
  @override
  Future<FdcFood?> food(int fdcId) {
    asked.add(fdcId);
    return super.food(fdcId);
  }
}

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    expect(matcherVersion, 76);
  });

  test("dryHeatKept[174377]: SR 172552's (roasted) and SR 174378's "
      '(broiled) shares by the protein tracer (cooked × P raw ÷ (P cooked × '
      "raw)), the design's five columns each", () {
    expect(dryHeatKept.keys.toSet(), {174377});
    // Snapshot 28: the 174377 DETAIL (E 342, P 15.32, F 30.71, sat 13.43,
    // mono 12.6, poly 2.42) and the two cooked HITS (172552: 341, 21.8,
    // 27.5, 11.7, 11.6, 1.99; 174378: 340, 23.1, 26.8, 11.4, 11.0, 2.17); no
    // trans on any of the three (gross, as M72's).
    expect(dryHeatKept[174377], {
      'roasted': {
        'energy': 341 * 15.32 / (21.8 * 342),
        'fat': 27.5 * 15.32 / (21.8 * 30.71),
        'saturated': 11.7 * 15.32 / (21.8 * 13.43),
        'monounsaturated': 11.6 * 15.32 / (21.8 * 12.6),
        'polyunsaturated': 1.99 * 15.32 / (21.8 * 2.42),
      },
      'broiled': {
        'energy': 340 * 15.32 / (23.1 * 342),
        'fat': 26.8 * 15.32 / (23.1 * 30.71),
        'saturated': 11.4 * 15.32 / (23.1 * 13.43),
        'monounsaturated': 11.0 * 15.32 / (23.1 * 12.6),
        'polyunsaturated': 2.17 * 15.32 / (23.1 * 2.42),
      },
    });
    expect(
      {
        for (final MapEntry(:key, :value) in dryHeatKept[174377]!.entries)
          key: [for (final v in value.values) v.toStringAsFixed(6)],
      },
      {
        'roasted': ['0.700697', '0.629296', '0.612226', '0.646978', '0.577883'],
        'broiled': ['0.659325', '0.578764', '0.562958', '0.578987', '0.594691'],
      },
    );
    // A record in both maps would read the dry-heat pair alone.
    expect(
      braisedKept.keys.toSet().intersection(dryHeatKept.keys.toSet()),
      isEmpty,
    );
  });

  test("the pour-off test answers as the design's regex on the real "
      'sentences: 0228 S3 pours off fat; a pour-off of a liquid, or fat '
      'before the pour-off, reads nothing', () {
    for (final (sentence, expected) in const [
      // 0228 S3.
      (
        'Pour off all but 1 teaspoon fat from skillet and repeat with second rack.',
        true,
      ),
      // 0040 (the fat word after the pour-off).
      (
        'Pour off all but 3 tablespoons of the bacon fat left in the pan.',
        true,
      ),
      // 0143: "fat" after the pour-off — the design's regex reads it so.
      ('Pour off liquid from fat separator and reserve.', true),
      // 0142 (a pour-off of a liquid: no fat word).
      (
        'Pour off the liquid from the skillet into a 2-cup measuring cup and reserve.',
        false,
      ),
      // 0228 S1 (no pour-off).
      (
        'Adjust oven rack to middle position and heat oven to 250 degrees.',
        false,
      ),
    ]) {
      final s = sentence.toLowerCase();
      expect(pourOffFatSentence(s), expected, reason: sentence);
      expect(_design.hasMatch(s), expected, reason: sentence);
    }
    // STATED synthesized negatives (forms no corpus sentence prints): fat
    // before the pour-off, fat past a period, no boundary after "off".
    for (final s in const [
      'trim fat, then pour off the liquid',
      'pour off the liquid. reserve the fat',
      'pour offfat',
    ]) {
      expect(pourOffFatSentence(s), _design.hasMatch(s), reason: s);
      expect(pourOffFatSentence(s), isFalse, reason: s);
    }
  });

  // M79 closer 1 (verify1 D2): the 167781 arm's RAW gate — every corpus row
  // on 167781 is a crystallized-ginger line, so no corpus line reaches the
  // gate's false side. The STATED hypothetical pair: Struffoli's (1163) real
  // line (on SR 167563 in the library) asked on 167781.
  test("the 167781 stand-in text needs 'crystallized ginger' in the line: "
      "Struffoli's (1163) \"8 candied cherries (optional)\" asked on SR 167781 "
      '(a STATED hypothetical pair) carries none', () {
    expect(trimStandInFlagOf('8 candied cherries (optional)', 167781), isNull);
    expect(
      trimStandInFlagOf('¼ cup minced crystallized ginger', 167781),
      _gingerFlag,
    );
  });

  // M79 closer 1 (verify1 D3): the appended entry's PHRASE gate — both racks
  // print "trimmed" and no other corpus line tops on 174321, so no corpus
  // line reaches the gate's false side. The STATED hypothetical pair: Roast
  // Butterflied Leg of Lamb's (0230) real line (on SR 174315 in the library)
  // ranked over the racks' cached rank-as answer.
  test('the appended trim entry moves 174321 → 174377 only on a line that '
      "prints 'trimmed': over the cached 'lamb rib separable lean and fat "
      "choice raw' answer both racks move, 0230's \"1 (6- to 8-pound) "
      'butterflied leg of lamb" (a STATED hypothetical pair) keeps 174321 '
      'first', () async {
    const query = 'lamb rib separable lean and fat choice raw';
    final ranked = rankCandidates(query, await FixtureProvider().search(query));
    expect(ranked.first.candidate.fdcId, 174321);
    for (final (raw, top) in const [
      (
        '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
        174377,
      ),
      (
        '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
        174377,
      ),
      ('1 (6- to 8-pound) butterflied leg of lamb', 174321),
    ]) {
      expect(
        trimDepthRecord(raw, ranked).first.candidate.fdcId,
        top,
        reason: raw,
      );
    }
  });

  group('matcher v79 (batch M79)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    Future<Recipe> compute(
      SaltDatabase db,
      Recipe recipe,
      NutritionProvider provider,
    ) async {
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
      tempDir = Directory.systemTemp.createTempSync('salt-v79-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      for (final file in _files) {
        recipes[file] = await compute(db, loadCorpusRecipe(file), provider);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    IngredientLine lineIn(String file, int position) =>
        nutritionLines(recipes[file]!)[position];

    /// A row's kcal as the totals read it (its nutrient sibling's record
    /// where one is mapped), before any pair deduction.
    String kcalOf(SaltDatabase db, IngredientMatchRow row, IngredientLine l) {
      final sibling = nutrientSiblings[row.fdcId];
      final record = sibling == null
          ? knownFood(db, row.fdcId!, line: l)!
          : knownFood(db, sibling)!;
      return (kcalPer100g(record) * row.grams! / 100).toStringAsFixed(2);
    }

    test('M79 moves exactly its seven rows (record, grams, basis, flag); the '
        'negatives keep the v78 rows', () {
      for (final (file, position, raw, fdcId, grams, source, kcal, basis)
          in _reach) {
        final row = rowIn(file, position);
        final line = lineIn(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.gramSource, source, reason: reason);
        expect(kcalOf(db, row, line), kcal, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipes[file]),
          fdcId == 167781 ? _ginger(basis) : basis,
          reason: reason,
        );
      }
      for (final (file, position, raw, fdcId, grams, kcal) in _negatives) {
        final row = rowIn(file, position);
        final line = lineIn(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(
          row.grams == null ? null : kcalOf(db, row, line),
          kcal,
          reason: reason,
        );
      }
      // The ginger rows land at the gate's full confidence; the racks carry
      // their rank-as top's.
      for (final (file, position, _, _, _, _, _, _) in _reach.take(4)) {
        expect(rowIn(file, position).confidence, 1.0, reason: file);
      }
    });

    test('the totals: four ginger recipes and the watermelon salad complete; '
        'the racks 886.76 and 650.93 per serving', () {
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

    test('the deductions by hand: 0228 4,246.64 × (1 − 0.700697) = 1,271.03 '
        'kcal and its fat 381.33 → 239.97 g; 0622 3,680.42 × (1 − 0.659325) '
        '= 1,253.83 kcal and 330.48 → 191.27 g; protein gross', () {
      double per100(SaltDatabase db, int fdcId, IngredientLine l, String key) {
        final record = knownFood(
          db,
          nutrientSiblings[fdcId] ?? fdcId,
          line: l,
        )!;
        return key == 'energy'
            ? kcalPer100g(record)
            : nutrientDefs
                      .firstWhere((def) => def.key == key)
                      .fdcNumbers
                      .map((n) => record.nutrientsPer100g[n])
                      .nonNulls
                      .firstOrNull ??
                  0;
      }

      double gross(String file, String key) => [
        for (final r in db.ingredientMatchesFor(recipes[file]!.id))
          if (r.fdcId != null && (r.grams ?? 0) > 0)
            per100(db, r.fdcId!, lineIn(file, r.position), key) *
                r.grams! /
                100,
      ].fold(0, (n, k) => n + k);
      for (final (file, position, cooking, kcal, fat, kept) in const [
        (_roast, 0, 'roasted', '1271.03', '381.33', '239.97'),
        (_grilled, 5, 'broiled', '1253.83', '330.48', '191.27'),
      ]) {
        final row = rowIn(file, position);
        final line = lineIn(file, position);
        final share = dryHeatKept[174377]![cooking]!;
        final stored = batchTotalsOf(db.nutritionFor(recipes[file]!.id)!);
        double rowOf(String key) =>
            per100(db, 174377, line, key) * row.grams! / 100;
        expect(
          (rowOf('energy') * (1 - share['energy']!)).toStringAsFixed(2),
          kcal,
          reason: file,
        );
        expect(
          (gross(file, 'energy') - stored['energy']!).toStringAsFixed(2),
          kcal,
          reason: file,
        );
        expect(rowOf('fat').toStringAsFixed(2), fat, reason: file);
        expect(
          (rowOf('fat') * share['fat']!).toStringAsFixed(2),
          kept,
          reason: file,
        );
        for (final key in const [
          'fat',
          'saturated',
          'monounsaturated',
          'polyunsaturated',
        ]) {
          expect(
            (gross(file, key) - stored[key]!).toStringAsFixed(6),
            (rowOf(key) * (1 - share[key]!)).toStringAsFixed(6),
            reason: '$file $key',
          );
        }
        // Protein, sodium and cholesterol stay gross (the drippings are fat).
        for (final key in const ['protein', 'sodium', 'cholesterol']) {
          expect(
            (gross(file, key) - stored[key]!).abs(),
            lessThan(1e-6),
            reason: '$file $key',
          );
        }
      }
    });

    test(
      'THE INVARIANT on both racks — the deduction (recomputeTotals), the '
      'basis (the GET) and the sheet (candidatesForLine, the GET) read the '
      'same recipe: all on 174377 with the cooking its steps print',
      () async {
        for (final (file, position, cooking, flag, perServing) in const [
          (_roast, 0, 'roasted', _roastedFlag, '886.76'),
          (_grilled, 5, 'broiled', _broiledFlag, '650.93'),
        ]) {
          final recipe = recipes[file]!;
          final line = lineIn(file, position);
          expect(recomputeTotals(db, recipe), isTrue, reason: file);
          expect(
            db.nutritionFor(recipe.id)!.caloriesPerServing!.toStringAsFixed(2),
            perServing,
            reason: file,
          );
          expect(
            braisedKeptOf(line.raw, 174377, recipe),
            dryHeatKept[174377]![cooking],
            reason: file,
          );
          expect(
            trimStandInFlagOf(line.raw, 174377, recipe: recipe),
            flag,
            reason: file,
          );
          final items =
              (await matchesBody(db, provider, recipe))['items']!
                  as List<Map<String, Object?>>;
          final match = items[position]['match']! as Map<String, Object?>;
          expect(match['fdc_id'], 174377, reason: file);
          expect(match['gram_basis'], endsWith(flag), reason: file);
          final sheet = items[position]['candidates']! as List<Object?>;
          expect(
            (sheet.first! as Map<String, Object?>)['fdc_id'],
            174377,
            reason: file,
          );
          final ranked = await candidatesForLine(
            db,
            provider,
            line,
            cacheOnly: true,
            recipe: recipe,
          );
          expect(ranked.first.candidate.fdcId, 174377, reason: file);
          // The move reads the line ("trimmed"), not the recipe: alone the
          // line still leads with 174377 — the COOKING is what the recipe
          // gives, and with none the basis says gross.
          final alone = await candidatesForLine(
            db,
            provider,
            line,
            cacheOnly: true,
          );
          expect(alone.first.candidate.fdcId, 174377, reason: file);
          expect(
            [for (final c in alone.take(3)) c.candidate.fdcId],
            [174377, 174321, 172493],
            reason: file,
          );
          expect(braisedKeptOf(line.raw, 174377, null), isNull, reason: file);
          expect(trimStandInFlagOf(line.raw, 174377), _grossFlag, reason: file);
          expect(
            gramBasisFor(db, line, rowIn(file, position)),
            endsWith(_grossFlag),
            reason: file,
          );
        }
      },
    );

    test("the gate's answers (`_dryHeatOf`, read through braisedKeptOf): a "
        'grill heat → broiled (0622; 0591 heats a grill AND an oven, no fat '
        'pour-off); an oven heat AND a fat pour-off → roasted (0228); an oven '
        'alone (0005) or a pour-off alone (0088) → none, gross — the STATED '
        "hypothetical pairs: 0228's rack line on 174377 asked with other real "
        "recipes' steps; and the grill wins over a roast (a STATED synthesized "
        "copy of 0228 with 0622 S1's real grill sentence added: no corpus "
        "recipe prints all three); the heat regexes' own gates (verify2 D1): "
        '"heat the grill" → broiled (0613), "heat the oven" + a pour-off → '
        'roasted (0075), STATED hypothetical pairs; an oven or grill WORD is '
        'no heat (STATED synthesized copies of 0088; and the REAL 0656, a grill '
        'named but never heated → none)', () {
      final rack = lineIn(_roast, 0).raw;
      final roast = recipes[_roast]!;
      Recipe withStep(Recipe r, String text) => r.copyWith(
        steps: [
          ...r.steps,
          RecipeStep(number: r.steps.length + 1, text: text),
        ],
      );
      final both = withStep(roast, 'Heat grill until hot, about 5 minutes.');
      // M79 closer 2 (verify2 D1): the `(?:the )?` of `_heatsGrill` /
      // `_heatsOven` and their trailing `\b`. Neither rack prints "the"
      // (0228 "heat oven", 0622 "Heat grill"), so no row reaches the
      // alternatives' true side: STATED hypothetical pairs — 0228's rack
      // line asked with Kansas City Sticky Ribs' (0613) real steps (S3 "Heat
      // the grill until hot …"; no fat pour-off → broiled) and with
      // Skillet-Roasted Chicken Breasts with Potatoes' (0075) real steps (S1
      // "heat the oven to 450 degrees", S5 "pour off any fat in the skillet"
      // → roasted). No corpus sentence prints "heat (the) oven" or "heat
      // (the) grill" running on into a longer word, so the trailing
      // boundaries' false side is a STATED synthesized case: 0088 (a pour-off
      // alone → none) with one sentence added naming an oven word
      // ("ovenproof") or a grill word ("grillpan") — no heat, still none.
      final slow = loadCorpusRecipe(
        '0088-slow-cooker-beer-braised-short-ribs.yaml',
      );
      for (final (label, recipe, cooking) in [
        (_roast, roast, 'roasted'),
        (_grilled, recipes[_grilled]!, 'broiled'),
        (
          '0591',
          loadCorpusRecipe('0591-grill-roasted-beef-short-ribs.yaml'),
          'broiled',
        ),
        ('0005', loadCorpusRecipe('0005-best-beef-stew.yaml'), null),
        ('0088', slow, null),
        // The owner's gate pin (verify4 O1): a REAL recipe on the grill
        // regex's false side — 0656 S3 "Place cauliflower, cut side down, on
        // grill over medium-high heat" names a grill and never heats one;
        // `\bgrill\b` alone would answer broiled here (eight corpus documents
        // reach this side; the v26 filler was the only pin).
        (
          '0656 (a grill named, never heated — the real false side)',
          loadCorpusRecipe('0656-grilled-cauliflower.yaml'),
          null,
        ),
        ('0228 + a grill (synthesized)', both, 'broiled'),
        (
          '0613 (hypothetical pair)',
          loadCorpusRecipe('0613-kansas-city-sticky-ribs.yaml'),
          'broiled',
        ),
        (
          '0075 (hypothetical pair)',
          loadCorpusRecipe(
            '0075-skillet-roasted-chicken-breasts-with-potatoes.yaml',
          ),
          'roasted',
        ),
        (
          '0088 + an oven word (synthesized)',
          withStep(slow, 'Heat the ovenproof skillet over medium-high heat.'),
          null,
        ),
        (
          '0088 + a grill word (synthesized)',
          withStep(slow, 'Heat the grillpan over medium-high heat.'),
          null,
        ),
      ]) {
        expect(
          braisedKeptOf(rack, 174377, recipe),
          cooking == null ? isNull : dryHeatKept[174377]![cooking],
          reason: label,
        );
        expect(
          trimStandInFlagOf(rack, 174377, recipe: recipe),
          switch (cooking) {
            'roasted' => _roastedFlag,
            'broiled' => _broiledFlag,
            _ => _grossFlag,
          },
          reason: label,
        );
      }
      // The pair is the record's: the same steps on another record read
      // none (the M72 / M74 maps keep their own gates).
      expect(braisedKeptOf(rack, 174414, roast), isNull);
      expect(braisedKeptOf(rack, 172641, recipes[_grilled]), isNull);
    });

    test('pre-Q18: a STATED synthesized step-less copy of 0228 keeps its rack '
        'on 174377 (the move reads the line) at GROSS — no step, no cooking, '
        'the flag says so', () async {
      final alone = library('salt-v79-alone-');
      final stepless = recipes[_roast]!.copyWith(steps: const []);
      final copy = await compute(
        alone,
        stepless,
        FixtureProvider(pending: {...pendingSearches}),
      );
      final row = alone
          .ingredientMatchesFor(copy.id)
          .singleWhere((m) => m.position == 0);
      final line = nutritionLines(copy)[0];
      expect(row.fdcId, 174377);
      expect(row.grams, rowIn(_roast, 0).grams);
      expect(braisedKeptOf(line.raw, 174377, copy), isNull);
      expect(
        gramBasisFor(alone, line, row, recipe: copy),
        '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · $_ah102 · '
        '$_grossFlag',
      );
      // Gross: the stored energy is the rows' sum (the 1,271.03 kept).
      final stored = batchTotalsOf(alone.nutritionFor(copy.id)!)['energy']!;
      final original = batchTotalsOf(
        db.nutritionFor(recipes[_roast]!.id)!,
      )['energy']!;
      expect((stored - original).toStringAsFixed(2), '1271.03');
    });

    test(
      "the keys: the four ginger lines' normalized item is 'crystallized "
      "ginger', both racks' 'racks of lamb', each read through its rank-as; "
      "the racks' compute never asks for the HIT-only 174321 (zero "
      'requests: the trim entry moves off it before any weight read)',
      () async {
        for (final (file, position, _, _, _, _, _, _) in _reach) {
          final item = normalizeItem(lineItemOf(lineIn(file, position)));
          final expected = switch (file) {
            _watermelon => null,
            _roast || _grilled => 'racks of lamb',
            _ => 'crystallized ginger',
          };
          if (expected == null) {
            continue;
          }
          expect(item, expected, reason: file);
        }
        expect(rankAsFor('crystallized ginger'), (
          query: 'candied fruit',
          answer: 'candied ginger',
        ));
        expect(rankAsFor('racks of lamb'), (
          query: 'lamb rib separable lean and fat choice raw',
          answer: 'lamb rib separable lean and fat choice raw',
        ));
        expect(approximationRecords['crystallized ginger'], 167781);
        expect(approximationRecords.containsKey('racks of lamb'), isFalse);
        final asked = _Asked();
        final fresh = library('salt-v79-asked-');
        for (final file in const [_roast, _grilled]) {
          await compute(fresh, loadCorpusRecipe(file), asked);
        }
        expect(asked.asked, contains(174377));
        expect(asked.asked, isNot(contains(174321)));
      },
    );

    test("the census: exactly four corpus lines read 'crystallized ginger', "
        "two 'racks of lamb' and one the seedless watermelon (sections "
        'included)', () {
      final files =
          Directory(corpusRecipesDir)
              .listSync()
              .map((f) => f.uri.pathSegments.last)
              .where((f) => f.endsWith('.yaml'))
              .toList()
            ..sort();
      final hits = <String, List<String>>{};
      for (final file in files) {
        final r = loadCorpusRecipe(file);
        for (final (label, rec) in [
          (file, r),
          for (final sub in r.subsections.where((s) => s.title != null))
            ('$file|${sub.title}', sectionRecipeOf(r, sub)),
        ]) {
          for (final (i, line) in nutritionLines(rec).indexed) {
            final item = normalizeItem(lineItemOf(line));
            if (item == 'crystallized ginger' ||
                item == 'racks of lamb' ||
                line.raw.toLowerCase().contains('watermelon')) {
              (hits[item] ??= []).add('$label|$i');
            }
          }
        }
      }
      expect(hits, {
        'crystallized ginger': [
          '$_carrot|2',
          '$_chutney|9',
          '$_gingerbread|22',
          '$_slab|3',
        ],
        'racks of lamb': ['$_roast|0', '$_grilled|5'],
        '1 1 2-inch seedless watermelon pieces': ['$_watermelon|5'],
      });
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
