// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v62 (batch M63 — the 8-inch pita by FDC's per-area portion, the
// crab cake's own oil, the sirloin stand-in flag, the rack's retired hit
// read; matcherVersion 61; prep48 design_v2 §2 M63, §1 Q3, Q6, Q11, Q16, §6
// F3 and F11; the owner's rulings of 2026-10-08 under the 2026-10-07
// standing authorization, P10 outcome B; zero requests — live step L's L3–L5
// reads; no step is read, so no reach here is pre-Q18): a pita counted by its
// printed "(N-inch)" diameter on FNDDS 2707616 weighs the record's own '1
// surface inch' 2 g × π (N/2)² (grams `_perArea`), flagged "derived"; a
// fried crab absorbs FNDDS 2706549 "Crab, cake"'s own oil, 5 g per 65 g
// crab (engine `_friedClassOf`); a top sirloin roast on the lean-only petite
// roast 173408 says it stands in (`trimStandInFlagOf`); the rack's 174414 is
// weighed on its cached detail (the M56 `ah102MeatsOnHit` set retired).
// Every row value is the fresh compute of the WHOLE recipe over recorded real
// FDC answers (FixtureProvider; 14 searches and 3 foods — 174414, 171327,
// 2709787 — added --from-db from snapshot 24, JSON-equal, 0 existing entries
// changed), equal to the v62 replay of snapshot 24 (rp43, fix62 r1) on every
// pinned field and, on every row M63 must not move, to the v61 rows; never
// the network. Synthesized, STATED (no corpus line holds them): the lines
// the P10 key and diameter pins and the sirloin guard pins pass to
// `resolveGrams` and `trimStandInFlagOf`; the P10 id pin's pairing of the
// corpus line "4 (8-inch) pita breads" with the real SR 174915 hit (no corpus
// row sits on that record).

import 'dart:io';
import 'dart:math' show pi;

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

/// (file, position, raw, fdc id, confidence, grams, kcal (null: not pinned —
/// stated where it is), hold, basis) — an `auto` row of the fresh compute.
typedef _Row = (
  String,
  int,
  String,
  int?,
  String,
  String?,
  String?,
  String?,
  String?,
);

const _arayes =
    '0579-grilled-arayes-grilled-lamb-stuffed-pitas-with-yogurt-sauce.yaml';
const _souvlaki = '0636-grilled-chicken-souvlaki.yaml';
const _shakshuka =
    '0729-shakshuka-eggs-in-spicy-tomato-and-roasted-red-pepper-sauce.yaml';
const _fattoush =
    '0048-fattoush-pita-bread-salad-with-tomatoes-and-cucumber.yaml';
const _maryland = '0288-maryland-crab-cakes.yaml';
const _fennel = '0220-fennel-coriander-top-sirloin-roast.yaml';
const _cocotte = '0461-beef-en-cocotte-with-mushroom-sauce.yaml';
const _inexpensive =
    '0592-inexpensive-grill-roasted-beef-with-garlic-and-rosemary.yaml';
const _rack = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
const _grilledRack = '0622-grilled-rack-of-lamb.yaml';
const _poachedEggs =
    '1145-clbr-turkish-poached-eggs-with-yogurt-and-spiced-butter.yaml';
const _porkChops = '0597-easy-grilled-boneless-pork-chops.yaml';
const _watermelon = '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml';
const _quesadillas = '0472-quesadillas.yaml';
const _skilletFajitas = '0070-skillet-chicken-fajitas.yaml';
const _grilledFajitas = '0484-grilled-chicken-fajitas.yaml';
const _steakFajitas = '0485-steak-fajitas.yaml';
const _arugula =
    '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml';
const _canzanese = '0422-chicken-canzanese.yaml';
const _bestCrab = '0289-best-crab-cakes.yaml';
const _crabTowers = '0290-crab-towers-with-avocado-and-gazpacho-salsas.yaml';
const _panSeared = '0190-pan-seared-inexpensive-steaks.yaml';
const _newMexican = '0587-grilled-steak-with-new-mexican-chile-rub.yaml';

/// M63's reach (plan_figures §5 outcome B: exactly these 8 rows, +1,717.16
/// kcal per batch at the stored grams): P10's four pitas on 2707616 (57 g
/// each before, FNDDS's unnamed medium), the crab cake's frying oil (30.30 g
/// on the chicken breast's 6.68 % stand-in before), and the three top
/// sirloin roasts on 173408 (basis only, 0 kcal).
const List<_Row> _reach = [
  (
    _arayes,
    18,
    '4 (8-inch) pita breads',
    2707616,
    '0.990000',
    '402.12',
    '1105.84',
    null,
    "4 × 100.53 g each (8-inch round: 50.27 sq in × 2 g per surface inch) · approximate (derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the printed diameter's area, π × 4²)",
  ),
  (
    _souvlaki,
    16,
    '4 (8-inch) pitas',
    2707616,
    '0.890000',
    '402.12',
    '1105.84',
    null,
    "4 × 100.53 g each (8-inch round: 50.27 sq in × 2 g per surface inch) · approximate (derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the printed diameter's area, π × 4²)",
  ),
  (
    _shakshuka,
    0,
    '4 (8-inch) pita breads, divided',
    2707616,
    '0.990000',
    '402.12',
    '1105.84',
    null,
    "4 × 100.53 g each (8-inch round: 50.27 sq in × 2 g per surface inch) · approximate (derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the printed diameter's area, π × 4²)",
  ),
  (
    _fattoush,
    0,
    '2 (8-inch) pita breads',
    2707616,
    '0.990000',
    '201.06',
    '552.92',
    null,
    "2 × 100.53 g each (8-inch round: 50.27 sq in × 2 g per surface inch) · approximate (derived from USDA FNDDS 2707616 '1 surface inch' 2 g × the printed diameter's area, π × 4²)",
  ),
  (
    _maryland,
    9,
    '¼ cup vegetable oil',
    2710180,
    '0.923333',
    '34.88',
    '313.92',
    null,
    "discarded in cooking — only the oil the fried food absorbs counted · approximation (frying oil absorbed: 7.69 % of the raw crab's weight — USDA FNDDS 2706549 recipe: 5 g oil per 65 g raw crab)",
  ),
  (
    _fennel,
    0,
    '1 (5- to 6-pound) boneless top sirloin center-cut roast, trimmed',
    173408,
    '0.553333',
    '2494.76',
    '3293.08',
    null,
    "from the printed weight (5–6 lb, the midpoint) · approximate (lean only — FDC publishes no lean-and-fat top sirloin petite roast (search 2026-10-08); the roast's separable fat not counted)",
  ),
  (
    _cocotte,
    0,
    '1 (3- to 4-pound) top sirloin beef roast, trimmed and tied once around middle',
    173408,
    '0.870000',
    '1587.57',
    '2095.60',
    null,
    "from the printed weight (3–4 lb, the midpoint) · approximate (lean only — FDC publishes no lean-and-fat top sirloin petite roast (search 2026-10-08); the roast's separable fat not counted)",
  ),
  (
    _inexpensive,
    4,
    '1 (3- to 4-pound) top sirloin roast',
    173408,
    '0.857500',
    '1587.57',
    '2095.60',
    null,
    "from the printed weight (3–4 lb, the midpoint) · approximate (lean only — FDC publishes no lean-and-fat top sirloin petite roast (search 2026-10-08); the roast's separable fat not counted)",
  ),
];

/// Rows M63 keeps byte for byte (each equal to the v61 row): the rack on its
/// now-cached detail (the retired hit read — the same AH-102 row, the same
/// energy: the hit's 237.0 and the detail's 237.0 kcal), the grilled rack on
/// NZ 172641 (no printed depth), the crab cake's coat (no cake k: the
/// record's 5 g of crumbs are a binder — M58 S's stand-in suffix stays).
const List<_Row> _kept = [
  (
    _rack,
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    174414,
    '0.539697',
    '1241.71',
    '2942.85',
    null,
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  (
    _grilledRack,
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    172641,
    '0.539697',
    '1076.15',
    '1818.69',
    null,
    '2 × 737 g (printed 1½–1¾ lb, the midpoint) × 0.73 edible · approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw → lean and fat meat, slightly trimmed 73 % (61–88), as measured unfrenched; a frenched rack yields less)',
  ),
  (
    _maryland,
    8,
    '¼ cup unbleached all-purpose flour',
    789890,
    '0.950000',
    '30.16',
    '110.39',
    null,
    "discarded in cooking — only the coat on the food counted · approximation (coat: 5.73 g carbohydrate per 100 g of the raw crab — USDA FNDDS 2705975 recipe: 15 g breading per 104.76 g raw chicken breast (no record for crab; read as Chicken breast, fried, coated, prepared skinless, coating eaten, from raw); the dredge's excess not counted)",
  ),
];

/// Rows the four reads must not reach (each equal to the v61 row): the pita
/// line with no amount; the pepitas (never `\bpitas?\b`) — watermelon|8
/// here, and the pork chops' relish SECTION row "¼ cup pepitas, toasted" in
/// [_pepitaRelish] (the host's |6 below is its sub-recipe line, kept as the
/// host side of that section — no M63 rule reads it); the "(N-inch)"
/// flour tortillas on 2707824 (no surface inch — a later item); prosciutto
/// weight lines on 2705879 (a surface inch, a weight line); the crab cakes'
/// oil counted whole (best-crab-cakes|14, measured tablespoons) and a crab
/// that is not fried; the top sirloin STEAKS (2727574, 174707 — not
/// 173408). kcal not pinned on crab-towers|7 and pan-seared|1: a fresh
/// compute reads 275.56 / 1,270.06 kcal against the replay's 275.54 /
/// 1,271.36 — the energy source of the test's cache, not M63 (their grams,
/// record and basis are pinned).
const List<_Row> _negatives = [
  (
    _poachedEggs,
    8,
    'Pita, flatbread, or crusty bread',
    2707616,
    '0.890000',
    '0.00',
    '0.00',
    null,
    'no amount on the line — counted as 0 g',
  ),
  (
    _porkChops,
    6,
    '1 recipe relish (optional) (recipes follow)',
    null,
    '1.000000',
    '0.00',
    '0.00',
    'choose_recipe',
    'a sub-recipe — counted as 0 g',
  ),
  (
    _watermelon,
    8,
    '5 tablespoons chopped roasted, salted pepitas, divided',
    169415,
    '0.700000',
    '36.88',
    '211.66',
    null,
    '5 tablespoon · USDA portion',
  ),
  (
    _quesadillas,
    0,
    '2 (8-inch) flour tortillas',
    2707824,
    '0.990000',
    '52.00',
    '159.12',
    null,
    '2 × 26 g each',
  ),
  (
    _skilletFajitas,
    20,
    '8–12 (6-inch) flour tortillas, warmed',
    2707824,
    '0.990000',
    '260.00',
    '795.60',
    null,
    '8–12 × 26 g each',
  ),
  (
    _grilledFajitas,
    11,
    '8–12 (6-inch) flour tortillas',
    2707824,
    '0.990000',
    '260.00',
    '795.60',
    null,
    '8–12 × 26 g each',
  ),
  (
    _steakFajitas,
    5,
    '8–12 (6-inch) flour tortillas',
    2707824,
    '0.990000',
    '260.00',
    '795.60',
    null,
    '8–12 × 26 g each',
  ),
  (
    _arugula,
    1,
    '2 ounces thinly sliced prosciutto, cut into ¼-inch strips',
    2705879,
    '0.890000',
    '56.70',
    '110.56',
    null,
    'from 2 ounce',
  ),
  (
    _canzanese,
    1,
    '2 ounces prosciutto (¼ inch thick), cut into ¼-inch cubes (see note)',
    2705879,
    '0.890000',
    '56.70',
    '110.56',
    null,
    'from 2 ounce',
  ),
  (
    _bestCrab,
    14,
    '¼ cup vegetable oil',
    2710180,
    '0.923333',
    '56.00',
    '504.00',
    null,
    '1/4 cup · USDA portion',
  ),
  (
    _crabTowers,
    7,
    '12 ounces lump or backfin Atlantic blue crabmeat, carefully picked over to remove cartilage and shell fragments',
    2684446,
    '0.907143',
    '340.19',
    null,
    null,
    'from 12 ounce',
  ),
  (
    _panSeared,
    1,
    '2 1-pound whole boneless shell sirloin steaks (top butt) or whole flap meat steaks, each about 1¼ inches thick',
    2727574,
    '1.000000',
    '907.18',
    null,
    null,
    '2 × 454 g (printed weight)',
  ),
  (
    _newMexican,
    5,
    '2 (1½- to 1¾-pound) boneless shell sirloin steaks, 1 to 1¼ inches thick',
    174707,
    '0.600357',
    '1474.17',
    '2933.61',
    null,
    '2 × 737 g (printed 1½–1¾ lb, the midpoint)',
  ),
];

/// The pepitas negative of plan_figures §1 (closer 1, verifier D1): the
/// pork chops' "Orange, Jicama, and Pepita Relish" SECTION row |6 (a section
/// recipe's own rows — `rowIn` with its title), equal to the v61 row.
const _pepitaSection = 'Orange, Jicama, and Pepita Relish';
const List<_Row> _pepitaRelish = [
  (
    _porkChops,
    6,
    '¼ cup pepitas, toasted',
    2515380,
    '0.920000',
    '29.50',
    '163.61',
    null,
    '1/4 cup · USDA portion of "Seeds, pumpkin and squash seed kernels, roasted, with salt added"',
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

const String _sirloinFlag =
    "approximate (lean only — FDC publishes no lean-and-fat top sirloin petite roast (search 2026-10-08); the roast's separable fat not counted)";

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    // RE-PIN (M66 batch, v65): matcherVersion 64 (was 63).
    expect(matcherVersion, 64);
  });

  test('the sirloin stand-in flag is keyed on 173408 and a line that does '
      'not ask for lean (STATED synthesized lines)', () {
    const roast = '1 (3- to 4-pound) top sirloin roast';
    expect(trimStandInFlagOf(roast, 173408), _sirloinFlag);
    // A line asking for lean is what the record is: no flag.
    expect(trimStandInFlagOf('$roast, lean', 173408), isNull);
    // A word holding "lean" is not the word (\blean\b).
    expect(trimStandInFlagOf('$roast, cleaned', 173408), _sirloinFlag);
    // Another record says nothing; the brisket arm is the shipped one.
    expect(trimStandInFlagOf(roast, 174695), isNull);
    expect(trimStandInFlagOf(roast, null), isNull);
    expect(
      trimStandInFlagOf(
        '1 (4-pound) beef brisket, fat trimmed to ¼ inch',
        168743,
      ),
      'approximate (the printed ¼-inch fat cap renders and is skimmed '
      '(step 5); counted as the 0-inch trimmed flat)',
    );
  });

  group('matcher v62 (batch M63)', skip: skipIfNoCorpus, () {
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
      tempDir = Directory.systemTemp.createTempSync('salt-v62-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _) in [
        ..._reach,
        ..._kept,
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

    /// Each [rows] entry in its whole recipe (or its [section]): the
    /// record, the confidence, the grams, the energy, the hold and the
    /// basis; `auto`.
    void expectRows(List<_Row> rows, {String? section}) {
      for (final (
            file,
            position,
            raw,
            fdcId,
            confidence,
            grams,
            kcal,
            hold,
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
        expect(row.hold, hold, reason: reason);
        if (kcal != null) {
          expect(
            _kcalOf(db, row, line).toStringAsFixed(2),
            kcal,
            reason: reason,
          );
        }
        expect(
          basisIn(file, position, section: section),
          basis,
          reason: reason,
        );
      }
    }

    String g2(double v) => v.toStringAsFixed(2);

    test('M63 reaches exactly its 8 rows (plan_figures §5 outcome B)', () {
      expect(_reach, hasLength(8));
      expectRows(_reach);
    });

    test("P10: an 8-inch pita weighs 2707616's '1 surface inch' 2 g × π × "
        '4² (100.53 g), `piece`, flagged "derived" — not the medium 57 g', () {
      const each = pi * 4 * 4 * 2.0;
      expect(g2(each), '100.53');
      for (final (file, position, count) in [
        (_arayes, 18, 4),
        (_souvlaki, 16, 4),
        (_shakshuka, 0, 4),
        (_fattoush, 0, 2),
      ]) {
        final row = rowIn(file, position);
        expect(row.fdcId, 2707616, reason: file);
        expect(row.gramSource, 'piece', reason: file);
        expect(g2(row.grams!), g2(count * each), reason: file);
        expect(
          basisIn(file, position),
          '$count × 100.53 g each (8-inch round: 50.27 sq in × 2 g per '
          'surface inch) · approximate (derived from USDA FNDDS 2707616 '
          "'1 surface inch' 2 g × the printed diameter's area, π × 4²)",
          reason: file,
        );
      }
      // The record's own '1 surface inch' portion is the figure's 2 g.
      final pita = knownFood(db, 2707616)!;
      expect(
        [
          for (final p in pita.portions)
            if (p.description == '1 surface inch') p.gramWeight,
        ],
        [2.0],
      );
    });

    test('P10 reads the "(N-inch)" diameter only, on the pita word only '
        '(STATED synthesized lines on the real 2707616 record)', () {
      final pita = knownFood(db, 2707616)!;
      GramResolution? grams(String raw) {
        final parsed = parseIngredientLine(raw);
        return resolveGrams(
          amounts: parsed.amounts,
          food: pita,
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        );
      }

      // A 6-inch pita scales by its own area: π × 3² × 2 = 56.55 g.
      expect(g2(grams('4 (6-inch) pita breads')!.grams), g2(4 * pi * 9 * 2));
      // "about 8 inches long" is a length, never a diameter.
      expect(
        grams('4 pita breads, about 8 inches long')!.basis,
        isNot(contains('surface inch')),
      );
      // Pepitas are not pitas (`\bpitas?\b`).
      expect(
        grams('4 (8-inch) pepitas')?.basis ?? '',
        isNot(contains('surface inch')),
      );
    });

    test("P10 is keyed to 2707616's id, never the 'Bread, pita' prefix: "
        "another pita record never takes 2707616's per-area figure (closer "
        '1, verifier D2; STATED synthesized line on the real SR 174915 hit '
        "of the recorded 'pita breads' answer)", () {
      final sr = knownFood(db, 174915)!;
      expect(sr.description.toLowerCase(), startsWith('bread, pita'));
      const raw = '4 (8-inch) pita breads';
      final parsed = parseIngredientLine(raw);
      expect(
        resolveGrams(
              amounts: parsed.amounts,
              food: sr,
              normalizedItem: normalizeItem(parsed.item ?? raw),
              raw: raw,
            )?.basis ??
            '',
        isNot(contains('surface inch')),
      );
    });

    test('the crab cake fries in its own read oil: FNDDS 2706549, 5 g per '
        '65 g crab (7.69 %) × the 1 pound of crab', () {
      final crab = rowIn(_maryland, 0);
      expect(crab.fdcId, 2684446);
      expect(g2(crab.grams!), '453.59');
      expect(g2(rowIn(_maryland, 9).grams!), g2(crab.grams! * 7.69 / 100));
      expect(g2(5 / 65 * 100), '7.69');
      // The coat stays on the chicken breast's read coat (no cake k).
      expect(basisIn(_maryland, 8), contains('(no record for crab; read as'));
      expect(basisIn(_maryland, 9), isNot(contains('no record for crab')));
    });

    test("the rack is weighed on 174414's cached detail (no refuse "
        'portion) by its AH-102 row, byte-equal to v61', () {
      expectRows(_kept.where((r) => r.$1 == _rack).toList());
      expect(db.fdcFoodCacheGet(174414), isNotNull);
      final rack = knownFood(db, 174414)!;
      expect(
        [for (final p in rack.portions) p.description],
        unorderedEquals(['oz', 'chop']),
      );
      expect(ah102Meats[174414], ah102Meats[172641]);
    });

    test('the rows M63 keeps and must not reach equal v61', () {
      expectRows(_kept);
      expectRows(_negatives);
    });

    test('the pepitas in the relish SECTION stay on their seed record '
        r'(never `\bpitas?\b`), equal to v61', () {
      expectRows(_pepitaRelish, section: _pepitaSection);
    });

    test('the matches GET shows each reach basis', () async {
      for (final (file, position, _, _, _, _, _, _, basis) in _reach) {
        final items =
            (await matchesBody(db, provider, recipes[file]!))['items']!
                as List<Map<String, Object?>>;
        final match = items[position]['match'] as Map<String, Object?>?;
        expect(match?['gram_basis'], basis, reason: '$file|$position');
      }
    });

    test('the five recipes move kcal per serving only', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      // A fresh compute here; the unchanged v61 tree's fresh compute in
      // the comment, then the replay's v61 → v62 — the same move (+119.71 a
      // serving for 4 pitas, +59.86 for 2, +10.30 for the crab oil); the
      // absolute figures differ by the energy the fixtures' cache reads.
      expect(of(_arayes), (
        'complete',
        '1134.19',
      )); // 1,014.48; 1,013.59 → 1,133.30
      expect(of(_souvlaki), ('complete', '687.14')); // 567.43; 567.49 → 687.20
      expect(of(_shakshuka), ('complete', '654.65')); // 534.94; 534.91 → 654.62
      expect(of(_fattoush), ('complete', '390.16')); // 330.30; 330.26 → 390.11
      // Partial on its unmatched Old Bay, as at v61.
      expect(of(_maryland), ('partial', '334.26')); // 323.96; 323.95 → 334.26
      // The three sirloin recipes move nothing but a basis.
      expect(of(_fennel).$1, 'complete');
    });

    test('a second recompute writes nothing', () {
      for (final file in const [
        _arayes,
        _fattoush,
        _maryland,
        _fennel,
        _rack,
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
