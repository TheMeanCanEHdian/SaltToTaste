// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v67 (batch M68 — the whole brisket at its printed trim, the two
// home-corned briskets flag-only; matcherVersion 66; prep49 design_v2 §2
// M68, the owner's Q1 (a) for the WHOLE cut and Q2 (c) for BOTH corned
// recipes, 2026-10-09; zero requests; records and titles only — no step is
// read): the whole brisket's lean-only 168607 moves to SR 168664 "Beef,
// brisket, whole, separable lean and fat, trimmed to 1/8" fat, all grades,
// raw" when the line prints "fat trimmed to ¼ inch" (engine
// `trimDepthRecords`), flagged at ⅛" with its rendered fat not deducted; a
// fresh flat 168743 in a recipe titled "corned beef" says the rinsed
// cure's sodium is not counted (`trimStandInFlagOf`'s title arm). R-B (the
// corned record 170199) is NOT built. Every row value is the fresh compute
// of the WHOLE recipe (sections first) over recorded real FDC answers
// (FixtureProvider; no fixture added — 'whole beef brisket' and 'beef
// brisket' were already recorded from the snapshots, 168664 and 168665
// hits in the former), equal to the v67 replay of snapshot 25 (rp43, fix67
// r1) on every pinned field and, on every row M68 must not move, to the
// v66 rows; never the network.
// Synthesized, STATED (no corpus line pairs them): `trimStandInFlagOf` is
// asked about real lines on records and titles they do not carry (the
// onion-braised line on 168664, 0090's salt line under its own title, the
// flat lines with no title).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title, position, raw, fdc id, description, confidence,
/// grams, status, hold, kcal, basis) — a row of the fresh compute.
typedef _Row = (
  String,
  String?,
  int,
  String,
  int?,
  String,
  String,
  String?,
  String,
  String?,
  String?,
  String?,
);

const _barbecued =
    '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml';
const _homeCorned = '0091-home-corned-beef-with-vegetables.yaml';
const _newEngland = '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml';
const _onion = '0223-onion-braised-beef-brisket.yaml';
const _pomegranate =
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
const _rack = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
const _grilledRack = '0622-grilled-rack-of-lamb.yaml';

const String _wholeFlag =
    "approximate (the printed ¼-inch fat cap counted at USDA's ⅛-inch trim, "
    'the deepest it publishes for brisket; the fat that renders into the '
    "separator is not deducted — USDA's own braised pair 168664 → 168665 "
    'keeps 93 % of the energy)';
const String _cornedFlag =
    "approximate (the steps cure and rinse the brisket — the cure's sodium "
    'is not counted; a rinsed cure counts 0 g, CP9)';
const String _pomegranateFlag =
    'approximate (the printed ¼-inch fat cap renders and is skimmed (step '
    '5); counted as the 0-inch trimmed flat)';
const String _rackYield =
    'approximate (USDA AH-102 item 1364: lamb rib loin (rack), bone in, raw '
    '→ lean and fat meat, slightly trimmed 73 % (61–88), as measured '
    'unfrenched; a frenched rack yields less)';
const String _flat =
    'Beef, brisket, flat half, boneless, separable lean and fat, trimmed to '
    '0" fat, choice, raw';
const String _discarded = 'discarded in cooking — counted as 0 g';

/// The three rows M68 moves (fix67 r1 vs the v66 rows): R-A's record and
/// flag, Q2 (c)'s two bases.
const List<_Row> _reach = [
  (
    _barbecued,
    null,
    10,
    '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch',
    168664,
    'Beef, brisket, whole, separable lean and fat, trimmed to 1/8" fat, all grades, raw',
    '0.886667',
    '4535.92',
    'auto',
    null,
    '11475.88',
    'from the printed weight (9–11 lb, the midpoint) · $_wholeFlag',
  ),
  (
    _homeCorned,
    null,
    0,
    '1 (4½- to 5-pound) beef brisket, flat cut',
    168743,
    _flat,
    '1.000000',
    '2154.56',
    'auto',
    null,
    '3641.21',
    'from the printed weight (4½–5 lb, the midpoint) · $_cornedFlag',
  ),
  (
    _newEngland,
    null,
    6,
    '1 (4- to 5-pound) beef brisket, flat cut, trimmed',
    168743,
    _flat,
    '1.000000',
    '2041.16',
    'auto',
    null,
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint) · $_cornedFlag',
  ),
];

/// Rows M68 must not move, equal to the v66 rows: the FLAT's ¼-inch cap
/// (deferred to L49), the flat with no depth and no corned title, the
/// rack's two records, and the two corned recipes' cure rows (`discarded`
/// 0 g — the cure is never counted twice).
const List<_Row> _negatives = [
  (
    _pomegranate,
    null,
    0,
    '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch',
    168743,
    _flat,
    '1.000000',
    '2041.16',
    'auto',
    null,
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint) · $_pomegranateFlag',
  ),
  (
    _onion,
    null,
    0,
    '1 (4- to 5-pound) beef brisket, preferably flat cut',
    168743,
    _flat,
    '1.000000',
    '2041.16',
    'auto',
    null,
    '3449.57',
    'from the printed weight (4–5 lb, the midpoint)',
  ),
  (
    _rack,
    null,
    0,
    '2 racks of lamb (1¾ to 2 pounds each), fat trimmed to ⅛ to ¼ inch, rib bones frenched',
    174414,
    'Lamb, Australian, imported, fresh, rib chop/rack roast, frenched, bone-in, separable lean and fat, trimmed to 1/8" fat, raw',
    '0.539697',
    '1241.71',
    'auto',
    null,
    '2942.85',
    '2 × 850 g (printed 1¾–2 lb, the midpoint) × 0.73 edible · $_rackYield',
  ),
  (
    _grilledRack,
    null,
    5,
    '2 (1½- to 1¾-pound) racks of lamb (8 ribs each), frenched and trimmed',
    172641,
    'Lamb, New Zealand, imported, rack - fully frenched, separable lean and fat, raw',
    '0.539697',
    '1076.15',
    'auto',
    null,
    '1818.69',
    '2 × 737 g (printed 1½–1¾ lb, the midpoint) × 0.73 edible · $_rackYield',
  ),
  (
    _newEngland,
    null,
    0,
    '½ cup kosher salt',
    173468,
    'Salt, table',
    '1.000000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    1,
    '¾ cup salt',
    173468,
    'Salt, table',
    '0.900000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    2,
    '½ cup packed brown sugar',
    168833,
    'Sugars, brown',
    '1.000000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    3,
    '2 teaspoons pink curing salt #1',
    173468,
    'Salt, table',
    '1.000000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    4,
    '6 garlic cloves, peeled',
    1104647,
    'Garlic, raw',
    '0.970000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    5,
    '6 bay leaves',
    170917,
    'Spices, bay leaf',
    '0.866667',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    6,
    '5 allspice berries',
    171315,
    'Spices, allspice, ground',
    '0.933333',
    '0.00',
    'auto',
    null,
    null,
    '$_discarded · approximation (counted as Spices, allspice, ground)',
  ),
  (
    _homeCorned,
    null,
    7,
    '2 tablespoons peppercorns',
    170931,
    'Spices, pepper, black',
    '1.000000',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
  ),
  (
    _homeCorned,
    null,
    8,
    '1 tablespoon coriander seeds',
    170922,
    'Spices, coriander seed',
    '0.933333',
    '0.00',
    'auto',
    null,
    null,
    _discarded,
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

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M69 batch, v68): matcherVersion 67 (was 66).
    expect(matcherVersion, 67);
  });

  test('R-A: the trim pairs gain the whole brisket only (the flat waits for '
      'L49)', () {
    expect(
      {for (final (_, pairs) in trimDepthRecords) ...pairs},
      {172641: 174414, 168607: 168664, 2727572: 171751},
    );
    final (phrase, pairs) = trimDepthRecords.first;
    expect(pairs[168607], 168664);
    expect(pairs.containsKey(168743), isFalse);
    expect(
      phrase.hasMatch(
        '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch',
      ),
      isTrue,
    );
  });

  test('the stand-in arms: 168664 on the printed ¼-inch cap; 168743 under a '
      '"corned beef" title (real lines and titles; the record and title '
      'pairings they do not carry STATED synthesized)', () {
    const whole =
        '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch';
    const onion = '1 (4- to 5-pound) beef brisket, preferably flat cut';
    const homeCorned = '1 (4½- to 5-pound) beef brisket, flat cut';
    const newEngland = '1 (4- to 5-pound) beef brisket, flat cut, trimmed';
    const pomegranate =
        '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ¼ inch';
    const homeCornedTitle = 'Home-Corned Beef with Vegetables';
    const newEnglandTitle = 'New England–Style Home-Corned Beef and Cabbage';
    expect(trimStandInFlagOf(whole, 168664), _wholeFlag);
    expect(trimStandInFlagOf(whole, 168607), isNull);
    expect(trimStandInFlagOf(onion, 168664), isNull);
    expect(
      trimStandInFlagOf(homeCorned, 168743, title: homeCornedTitle),
      _cornedFlag,
    );
    expect(
      trimStandInFlagOf(newEngland, 168743, title: newEnglandTitle),
      _cornedFlag,
    );
    expect(trimStandInFlagOf(homeCorned, 168743), isNull);
    expect(
      trimStandInFlagOf(onion, 168743, title: 'Onion-Braised Beef Brisket'),
      isNull,
    );
    expect(
      trimStandInFlagOf('½ cup kosher salt', 173468, title: newEnglandTitle),
      isNull,
    );
    // The printed cap's arm comes first: the pomegranate flat keeps its
    // shipped flag under any title.
    expect(
      trimStandInFlagOf(
        pomegranate,
        168743,
        title: 'Braised Brisket with Pomegranate, Cumin, and Cilantro',
      ),
      _pomegranateFlag,
    );
  });

  group('matcher v67 (batch M68)', skip: skipIfNoCorpus, () {
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
      tempDir = Directory.systemTemp.createTempSync('salt-v67-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: pendingSearches);
      for (final (file, _, _, _, _, _, _, _, _, _, _, _) in [
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

    IngredientMatchRow rowIn(String file, int position) => db
        .ingredientMatchesFor(recipes[file]!.id)
        .singleWhere((m) => m.position == position);

    String? basisIn(String file, int position) => gramBasisFor(
      db,
      nutritionLines(recipes[file]!)[position],
      rowIn(file, position),
      recipe: recipes[file],
    );

    /// Each [rows] entry in its whole recipe: the record, the description,
    /// the confidence, the grams, the status, the hold, the energy and the
    /// basis.
    void expectRows(List<_Row> rows) {
      for (final (
            file,
            _,
            position,
            raw,
            fdcId,
            description,
            confidence,
            grams,
            status,
            hold,
            kcal,
            basis,
          )
          in rows) {
        final line = nutritionLines(recipes[file]!)[position];
        final row = rowIn(file, position);
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.description, description, reason: reason);
        expect(row.confidence.toStringAsFixed(6), confidence, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.status, status, reason: reason);
        expect(row.hold, hold, reason: reason);
        if (kcal != null) {
          expect(
            _kcalOf(db, row, line).toStringAsFixed(2),
            kcal,
            reason: reason,
          );
        }
        expect(basisIn(file, position), basis, reason: reason);
      }
    }

    String g2(double v) => v.toStringAsFixed(2);

    test(
      'M68 reaches exactly its 3 rows (design_v2 §2 M68, R-B not built)',
      () {
        expect(_reach, hasLength(3));
        expectRows(_reach);
        expect(rowIn(_barbecued, 10).gramSource, 'weight');
      },
    );

    test("R-A by hand on the recorded 'whole beef brisket' hits: 168664 at "
        '253 kcal (11,475.88) vs 168607 at 157 (7,121.39); the braised pair '
        '168664 → 168665 keeps 93 % of the energy by the protein tracer; the '
        'rendered-fat deduction is NOT built', () async {
      final hits = {
        for (final c in await provider.search('whole beef brisket'))
          c.fdcId: c.nutrientsPer100g!,
      };
      final raw = hits[168664]!;
      final braised = hits[168665]!;
      expect([raw['208'], raw['203'], raw['204']], [253.0, 18.4, 19.1]);
      expect(
        [braised['208'], braised['203'], braised['204']],
        [331.0, 25.8, 24.5],
      );
      expect(hits[168607]!['208'], 157.0);
      final grams = rowIn(_barbecued, 10).grams!;
      expect(g2(grams * 2.53), '11475.88');
      expect(g2(grams * 1.57), '7121.39');
      expect(g2(grams * (2.53 - 1.57)), '4354.48');
      final yieldShare = raw['203']! / braised['203']!;
      final energyKept = yieldShare * braised['208']! / raw['208']!;
      final fatKept = yieldShare * braised['204']! / raw['204']!;
      expect(yieldShare.toStringAsFixed(3), '0.713');
      expect((100 * energyKept).toStringAsFixed(1), '93.3');
      expect((100 * fatKept).toStringAsFixed(1), '91.5');
      // The gap (design §2 M68, Q1 (b), not proposed for one row): the
      // pair's share on the row's energy. design_v2 prints −766.59 on a
      // share it rounded to 0.9332 (2.3606 kcal/g taken as 2.361).
      expect(g2(grams * 2.53 * (1 - energyKept)), '768.29');
    });

    test('the title arm reads the recipe title: exactly the two corned '
        'recipes', () {
      final cornedBeef = RegExp(r'\bcorned beef\b', caseSensitive: false);
      expect(
        {
          for (final MapEntry(:key, :value) in recipes.entries)
            if (cornedBeef.hasMatch(value.title)) key,
        },
        {_homeCorned, _newEngland},
      );
      expect(recipes[_homeCorned]!.title, 'Home-Corned Beef with Vegetables');
      expect(
        recipes[_newEngland]!.title,
        'New England–Style Home-Corned Beef and Cabbage',
      );
    });

    test('the rows M68 must not reach equal v66; the cure rows stay '
        '`discarded` 0 g', () {
      expect(_negatives, hasLength(13));
      expectRows(_negatives);
      for (final (file, _, position, _, _, _, _, grams, _, _, _, _)
          in _negatives) {
        if (grams == '0.00') {
          expect(
            rowIn(file, position).gramSource,
            'discarded',
            reason: '$file|$position',
          );
        }
      }
    });

    test('the sheet ranks as the compute does (candidatesForLine): the '
        "whole brisket's first candidate is 168664 at the top's confidence; "
        'the corned flats keep 168743 first (R-B not built)', () async {
      for (final (file, position, fdcId, confidence) in const [
        (_barbecued, 10, 168664, '0.886667'),
        (_homeCorned, 0, 168743, '1.000000'),
        (_newEngland, 6, 168743, '1.000000'),
      ]) {
        final first = (await candidatesForLine(
          db,
          provider,
          nutritionLines(recipes[file]!)[position],
          cacheOnly: true,
        )).first;
        expect(first.candidate.fdcId, fdcId, reason: '$file|$position');
        expect(first.confidence.toStringAsFixed(6), confidence);
      }
    });

    test('the matches GET shows each reach basis', () async {
      for (final (file, _, position, _, _, _, _, _, _, _, _, basis) in _reach) {
        final items =
            (await matchesBody(db, provider, recipes[file]!))['items']!
                as List<Map<String, Object?>>;
        final match = items[position]['match'] as Map<String, Object?>?;
        expect(match?['gram_basis'], basis, reason: '$file|$position');
      }
    });

    test('per serving: only the barbecued brisket moves', () {
      (String, String) of(String file) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        return (n.status, n.caloriesPerServing!.toStringAsFixed(2));
      }

      // A fresh compute here; the replay's v66 → v67 in the comment.
      expect(of(_barbecued), ('complete', '740.17')); // 498.26 → 740.17
      // Unmoved (v66 = v67): the corned rows' bases only.
      expect(of(_homeCorned), ('complete', '577.01'));
      // 592.10 in the replay: a fresh compute counts some of its lines on
      // search hits whose energies FDC rounds (M65's note); M68 moves no
      // kcal in this recipe.
      expect(of(_newEngland), ('complete', '592.11'));
      expect(of(_onion), ('complete', '692.11'));
      expect(of(_pomegranate), ('complete', '729.93'));
    });

    test('a second recompute writes nothing', () {
      for (final recipe in recipes.values) {
        List<(int, double?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.updatedAt),
        ];
        final before = rows();
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.id);
        expect(rows(), before, reason: recipe.id);
      }
    });
  });
}
