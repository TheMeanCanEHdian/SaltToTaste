// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v78 (batch M78 — the C4 recipes; matcherVersion 75; prep50
// design_v2 §2 M78, the owner's Q6 (c) and Q7 (c), 2026-10-15; zero
// requests). Rule 1 (pB R-D1): a nut or cheese coat layer `_layerInCrumb`
// rejects — a pressed crust — counts its WHOLE line outside the budget,
// flagged (parmesan-crusted|3, held before). Rule 2 (pC R-E4, F12): under
// C4, the fat lines a sauté heats between the first coat sentence and the
// first step that pours off the fat or wipes the skillet keep FNDDS
// 2705980's 2 g oil per 125.77 g raw breast as FAT grams, shared by the
// lines' fat (each line's whole grams × its record's total lipid, 204, on
// the record the totals read), each line at that one share of its whole
// grams. REACH (the v78 replay of snapshot 27): 7 rows — the design's five
// and chicken-francese|12/|13, whose S5 wipes the skillet after each batch
// (the design's "the fat makes the sauce" was a misreading: 0420's sauce is
// S2's saucepan; the orchestrator's ruling (a) of 2026-10-18, disclosed in
// API.md). Every row
// value is the fresh compute of the WHOLE recipe over recorded real FDC
// answers (FixtureProvider; fixtures recorded from snapshot 27 only) and
// equals the replay on every pinned field (per serving: the fresh figure,
// the replay's in the comment). Never the network. Every corpus line is
// real; STATED synthesized constructions (no corpus line reaches these
// gates), each built from corpus text under its own id: francese with ONE
// edit — "Bake the cutlets for 5 minutes." appended to S5 after its last
// wipe (C2, not C4 — the C4 gate); parmesan-crusted (0419) with TWO edits
// for the nut crust kind — its |3 replaced by 0117's real "1 cup almonds,
// chopped coarse", and its S2 rewritten by three replacements so that it
// names the almonds and no Parmesan or cheese (no crumb beside the layer);
// and saltimbocca with ONE edit, its pan line |5 replaced by another real
// corpus line — 0040's "4 tablespoons extra-virgin olive oil" (748608: the
// lipid read on its sibling) or 0258's "1 teaspoon olive oil" (the share's
// clamp at 1). The Confirm and Skip pins (verify2 D2) compute UNCHANGED
// corpus recipes under their own ids (the shared rows stay `auto`). The
// `fat > 0` guard has no reach on snapshot-27 fixtures (the one fat record
// without 204, 748608, is sibling-mapped).

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
const _parmesan = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _francese = '0420-chicken-francese.yaml';
const _saltimbocca = '0421-chicken-saltimbocca.yaml';
const _meuniere = '0466-fish-meuniere-with-browned-butter-and-lemon.yaml';
const _almond = '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml';
const _breaded = '0114-breaded-chicken-cutlets.yaml';

/// §1 Q6's flag, verbatim, after the line's own weighing.
const _crust =
    "1/4 cup ≈ 59 mL · grated, at ATK's printed 1 ounce = ½ cup + 6 ounces · approximate (a pressed cheese crust: no USDA record of a cheese crust, and the coat record's breading does not describe one — the line counted whole as printed; the part left in the dish is not deducted)";

/// §1 Q7's flag (its "…" pC's recipe figures) on a pan line of [food].
String _pan(String food, {bool butter = false}) =>
    'discarded in cooking — only the fat the sautéed food keeps counted · approximation (pan fat: 1.59 g fat per 100 g of the raw $food — USDA FNDDS 2705980 recipe: 2 g oil per 125.77 g raw chicken breast (no record for the fat a sautéed piece keeps; the steps pour off / wipe out the rest)${butter ? '; a butter line weighed by its own fat' : ''})';

/// The 7 rows M78 moves (file, position, raw, fdc id, grams, kcal, basis)
/// — the v77 replay's value in each comment.
final _reach = [
  // held `coating`, 0 g.
  (
    _parmesan,
    3,
    '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 cups; see note)',
    325036,
    '184.27',
    '775.78',
    _crust,
  ),
  // 18.14 g, 163.25 kcal.
  (
    _parmesan,
    6,
    '4 teaspoons olive oil',
    2710186,
    '6.76',
    '60.84',
    _pan('chicken breast'),
  ),
  // 28.36 g, 203.35 kcal.
  (
    _francese,
    12,
    '2 tablespoons unsalted butter',
    173430,
    '5.51',
    '39.51',
    _pan('chicken breast', butter: true),
  ),
  // 28.00 g, 252.00 kcal.
  (
    _francese,
    13,
    '2 tablespoons olive oil',
    2710186,
    '5.44',
    '48.96',
    _pan('chicken breast'),
  ),
  // 56.00 g, 504.00 kcal.
  (
    _saltimbocca,
    5,
    '4 tablespoons olive oil',
    2710186,
    '9.92',
    '89.28',
    _pan('chicken breast'),
  ),
  // 28.00 g, 252.00 kcal.
  (
    _meuniere,
    3,
    '2 tablespoons vegetable oil',
    2710180,
    '5.44',
    '48.96',
    _pan('flatfish'),
  ),
  // 28.36 g, 203.35 kcal.
  (
    _meuniere,
    4,
    '2 tablespoons unsalted butter, cut into 2 pieces',
    173430,
    '5.51',
    '39.51',
    _pan('flatfish', butter: true),
  ),
];

/// Rows M78 must not move (file, position, raw, grams, gram source) — each
/// equal to the v77 replay.
const _negatives = [
  // The other nut and cheese layers: joined by a crumb (`_layerInCrumb`)
  // or counted by `_coatLayer`.
  (_almond, 2, '1 cup sliced almonds', '79.97', 'discarded'),
  // RE-PIN (M80 batch, v80, M80-2): the two crumb-crust layers at FNDDS
  // 2706442's 12.12 — still parts joined by a crumb, never counted whole
  // (were 21.66 and 5.04 g at 3.18).
  (
    '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
    2,
    '1 cup almonds, chopped coarse',
    '82.55',
    'discarded',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    2,
    '1 ounce Parmesan cheese, grated (about ½ cup), plus extra for serving',
    '19.22',
    'discarded',
  ),
  (
    '0407-eggplant-parmesan.yaml',
    3,
    '2 ounces Parmesan cheese, grated (about 1 cup)',
    '19.33',
    'discarded',
  ),
  (
    '0415-best-chicken-parmesan.yaml',
    14,
    '1½ ounces Parmesan cheese, grated (¾ cup)',
    '42.52',
    'weight',
  ),
  // C4 recipes whose steps neither pour off the fat nor wipe the skillet.
  (
    '0418-chicken-piccata.yaml',
    4,
    '4 tablespoons vegetable oil',
    '56.00',
    'portion',
  ),
  (
    '0418-next-level-chicken-piccata.yaml',
    4,
    '¼ cup plus 1 teaspoon vegetable oil',
    '60.53',
    'portion',
  ),
  (
    '0414-chicken-marsala.yaml',
    7,
    '1 teaspoon tomato paste',
    '5.42',
    'density',
  ),
  (
    '0415-better-chicken-marsala.yaml',
    7,
    '¼ cup plus 1 teaspoon vegetable oil',
    '60.53',
    'portion',
  ),
  // The window's bounds: a fat before the dredge (francese's sauce butter,
  // S2), at the wipe sentence itself (meunière's browned butter, A13's
  // second mention) and after the pour-off (saltimbocca's sauce butter).
  (_francese, 0, '3 tablespoons unsalted butter', '42.54', 'density'),
  (
    _meuniere,
    5,
    '4 tablespoons (½ stick) unsalted butter, cut into 4 pieces',
    '56.72',
    'density',
  ),
  (
    _saltimbocca,
    8,
    '4 tablespoons (½ stick) unsalted butter, cut into 4 pieces and chilled',
    '56.72',
    'density',
  ),
  // A frying oil in a pour-off window keeps the frying-oil rule (closer 1,
  // verify1 D4): breaded-chicken-cutlets' uptake.
  (_breaded, 5, '1 tablespoon plus ¾ cup vegetable oil', '55.66', 'discarded'),
];

/// (file, status, per serving) after the compute — the replay's in each
/// comment (v77 → v78).
const _totals = [
  // 171.67 → 340.01 (partial → complete).
  (_parmesan, 'complete', '339.97'),
  // 438.34 → 346.62.
  (_francese, 'complete', '346.57'),
  // 511.56 → 407.88.
  (_saltimbocca, 'complete', '407.82'),
  // 349.73 → 258.01.
  (_meuniere, 'complete', '258.01'),
];

/// The corpus recipes whose steps put a fat line in a pan-fat window
/// ([panFatLinesOf]) — a census of the whole corpus. The C4 four are entries
/// 5–8 (`_parmesan`, `_francese`, `_saltimbocca`, `_meuniere`); the window
/// weighs only under C4, so the other eight weigh nothing by it (no row of
/// theirs moves in the v78 replay).
const _census = {
  '0070-skillet-chicken-fajitas.yaml': {11},
  '0235-maple-glazed-pork-tenderloin.yaml': {11},
  '0282-spanish-style-toasted-pasta-with-shrimp.yaml': {0},
  '0289-best-crab-cakes.yaml': {14},
  _parmesan: {6},
  _francese: {12, 13},
  _saltimbocca: {5},
  _meuniere: {3, 4},
  '0513-sung-choy-bao-chicken-lettuce-wraps.yaml': {8, 11},
  '0557-bo-luc-lac-shaking-beef.yaml': {10},
  '1124-blackened-chicken.yaml': {10, 11},
  '1178-chicken-teriyaki.yaml': {6},
};

/// [row] with gram source [source] — the same row in its other form.
IngredientMatchRow _withSource(IngredientMatchRow row, String source) =>
    IngredientMatchRow(
      recipeId: row.recipeId,
      position: row.position,
      raw: row.raw,
      fdcId: row.fdcId,
      description: row.description,
      dataType: row.dataType,
      confidence: row.confidence,
      grams: row.grams,
      gramSource: source,
      status: row.status,
      hold: row.hold,
    );

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    // RE-PIN (M79 batch, v79): matcherVersion 76 (was 75).
    // RE-PIN (M80 batch, v80): matcherVersion 77 (was 76).
    expect(matcherVersion, 77);
  });

  test("the records: FNDDS 2705980's oil (the share's 2 / 125.77); total "
      'lipid 204 — butter 81.11, the two oils 100; 748608 prints none and '
      'reads its sibling', () async {
    final provider = FixtureProvider();
    for (final (id, fat) in const [
      (173430, 81.11),
      (2710186, 100.0),
      (2710180, 100.0),
      (171413, 100.0),
    ]) {
      expect((await provider.food(id))!.nutrientsPer100g['204'], fat);
    }
    expect((await provider.food(748608))!.nutrientsPer100g['204'], isNull);
    expect(nutrientSiblings[748608], 171413);
    expect((2 / 125.77 * 100).toStringAsFixed(4), '1.5902');
  });

  group('the census (no compute)', skip: skipIfNoCorpus, () {
    test('exactly 12 corpus recipes put a fat line in a pan-fat window — no '
        'frying oil among them (verify1 D4: 0042|7, 0114|5, 0115|4 and '
        '1133|8/|9 keep the fryer pass)', () {
      final found = <String, Set<int>>{};
      for (final f in Directory(corpusRecipesDir).listSync()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.yaml')) {
          continue;
        }
        final pans = panFatLinesOf(loadCorpusRecipe(name));
        if (pans.isNotEmpty) {
          found[name] = pans;
        }
      }
      expect(found, _census);
    });
  });

  group('matcher v78 (batch M78)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

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

    /// A computed copy of [corpus] under a new id (STATED synthesized).
    Future<Recipe> variant(Recipe corpus, String id) => compute(
      corpus.copyWith(id: '${corpus.id}-$id', slug: '${corpus.slug}-$id'),
    );

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v78-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      for (final file in {
        for (final r in _reach) r.$1,
        for (final r in _negatives) r.$1,
      }) {
        recipes[file] = await compute(loadCorpusRecipe(file));
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    IngredientMatchRow rowOf(String file, int position) =>
        rowIn(recipes[file]!.id, position);

    String kcalOf(IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    String? basisOf(Recipe recipe, int position) => gramBasisFor(
      db,
      nutritionLines(recipe)[position],
      rowIn(recipe.id, position),
      recipe: recipe,
    );

    test('the 7 rows: the crust counted whole, the pan fat at the one share '
        '— record, grams, energy, status, hold and basis', () {
      for (final (file, position, raw, fdcId, grams, kcal, basis) in _reach) {
        final recipe = recipes[file]!;
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(nutritionLines(recipe)[position].raw, raw, reason: reason);
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, 'discarded'),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(row), kcal, reason: reason);
        expect(basisOf(recipe, position), basis, reason: reason);
      }
    });

    test('the totals: parmesan-crusted turns complete; the four recipes per '
        'serving', () {
      for (final (file, status, perServing) in _totals) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
          (status, perServing),
          reason: file,
        );
      }
    });

    test('the negatives keep their v77 rows', () {
      for (final (file, position, raw, grams, source) in _negatives) {
        final row = rowOf(file, position);
        final reason = '$file|$position';
        expect(
          nutritionLines(recipes[file]!)[position].raw,
          raw,
          reason: reason,
        );
        expect(
          (row.grams?.toStringAsFixed(2), row.gramSource),
          (grams, source),
          reason: reason,
        );
        expect(basisOf(recipes[file]!, position), isNot(contains('pan fat')));
      }
    });

    test("the fat-content split: meunière's 9.918 g of fat (623.69 g of "
        'sole × 2 / 125.77) over 28.00 g of oil at 100 % and 28.36 g of '
        'butter at 81.11 % — the butter 5.51 g, not the 4.99 g an oil '
        'reading gives (STATED: the oil reading is arithmetic, no row)', () {
      final sole = rowOf(_meuniere, 1).grams!;
      expect(sole.toStringAsFixed(2), '623.69');
      final fat = sole * 2 / 125.77;
      expect(fat.toStringAsFixed(3), '9.918');
      final kept = fat / (28.00 * 1.00 + 28.36 * 0.8111);
      expect((kept * 28.36).toStringAsFixed(2), '5.51');
      expect((kept * 28.00).toStringAsFixed(2), '5.44');
      expect((fat / (28.00 + 28.36) * 28.36).toStringAsFixed(2), '4.99');
      expect(rowOf(_meuniere, 4).grams, 5.51);
      expect(rowOf(_meuniere, 3).grams, 5.44);
      // Francese: the same breast weight, butter and oil — the same split.
      expect(rowOf(_francese, 7).grams!.toStringAsFixed(2), '623.69');
    });

    test('the GET: a pan line and the crust show the row basis', () async {
      for (final (file, position, basis) in [
        (_saltimbocca, 5, _pan('chicken breast')),
        (_meuniere, 4, _pan('flatfish', butter: true)),
        (_parmesan, 3, _crust),
      ]) {
        final items =
            ((await matchesBody(db, provider, recipes[file]!))['items']!
                    as List)
                .cast<Map<String, Object?>>();
        final item = items.singleWhere((i) => i['position'] == position);
        expect(
          (item['match']! as Map<String, Object?>)['gram_basis'],
          basis,
          reason: '$file|$position',
        );
      }
    });

    test("the M52 key (verify1 D4): a pan line's engine and planned forms "
        "key alike (saltimbocca|5); a frying oil's medium bit is keyed "
        '(breaded-chicken-cutlets|5, outside every pan-fat window)', () {
      for (final (file, position, alike) in [
        (_saltimbocca, 5, true),
        (_breaded, 5, false),
      ]) {
        final recipe = recipes[file]!;
        final rows = db.ingredientMatchesFor(recipe.id);
        String keyAs(String source) => m52KeyOf(recipe, [
          for (final r in rows)
            r.position == position ? _withSource(r, source) : r,
        ]);
        expect(
          keyAs('discarded') == keyAs('portion'),
          alike,
          reason: '$file|$position',
        );
      }
      expect(panFatLinesOf(recipes[_breaded]!), isEmpty);
    });

    /// [corpus] with its line [position] (one group) replaced by the real
    /// corpus line [raw] of [from] (STATED synthesized).
    Recipe withLine(Recipe corpus, int position, String from, String raw) {
      final line = nutritionLines(
        loadCorpusRecipe(from),
      ).firstWhere((l) => l.raw == raw);
      final group = corpus.ingredients.single;
      return corpus.copyWith(
        ingredients: [
          group.copyWith(
            items: [
              for (final (i, l) in group.items.indexed)
                i == position ? line : l,
            ],
          ),
        ],
      );
    }

    test('the C4 gate — STATED synthesized: francese with "Bake the cutlets '
        'for 5 minutes." after its last wipe reads C2 (a bake after the '
        "coat), so the window's lines keep their whole grams", () async {
      final corpus = loadCorpusRecipe(_francese);
      const wipe = 'Wipe out the skillet with paper towels.';
      expect(corpus.steps[4].text, endsWith(wipe));
      final baked = await variant(
        corpus.copyWith(
          steps: [
            for (final (i, s) in corpus.steps.indexed)
              i == 4
                  ? s.copyWith(
                      text: '${s.text} Bake the cutlets for 5 minutes.',
                    )
                  : s,
          ],
        ),
        'baked',
      );
      expect(panFatLinesOf(baked), {12, 13});
      for (final (position, grams) in const [(12, '28.36'), (13, '28.00')]) {
        final row = rowIn(baked.id, position);
        expect(row.grams?.toStringAsFixed(2), grams, reason: '$position');
        expect(row.gramSource, isNot('discarded'), reason: '$position');
      }
      // The coat is budgeted (C2), not C4's 3.18.
      expect(rowIn(baked.id, 9).gramSource, 'discarded');
      // The coat is budgeted at C2 (the same 2705980 figure, without C4's
      // "no record for a sautéed flour dusting" reading).
      expect(basisOf(baked, 9), isNot(contains('sautéed flour dusting')));
    });

    test('the nut crust — STATED synthesized: parmesan-crusted whose crust '
        'line is the real "1 cup almonds, chopped coarse" (0117) and whose '
        'S2 names the almonds where it named the shredded Parmesan — no crumb '
        'beside them (`_layerInCrumb` rejects the layer): |3 counts its '
        'whole line, flagged a nut crust', () async {
      final corpus = withLine(
        loadCorpusRecipe(_parmesan),
        3,
        '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
        '1 cup almonds, chopped coarse',
      );
      final s2 = corpus.steps[1].text;
      final edited = s2
          .replaceFirst(' and the ¼ cup grated Parmesan', '')
          .replaceFirst('the 2 cups shredded Parmesan', 'the almonds')
          .replaceFirst(
            'the shredded Parmesan mixture, pressing gently so that the '
                'cheese adheres',
            'the almond mixture, pressing gently so that the almonds adhere',
          );
      expect(edited, isNot(contains('Parmesan')));
      expect(edited, isNot(contains('cheese')));
      final pressed = await variant(
        corpus.copyWith(
          steps: [
            for (final (i, s) in corpus.steps.indexed)
              i == 1 ? s.copyWith(text: edited) : s,
          ],
        ),
        'almond-crust',
      );
      final row = rowIn(pressed.id, 3);
      expect(
        (row.fdcId, row.hold, row.gramSource),
        (170567, null, 'discarded'),
      );
      expect(row.grams?.toStringAsFixed(2), '143.00');
      expect(
        basisOf(pressed, 3),
        "1 cup · USDA portion · approximate (a pressed nut crust: no USDA record of a nut crust, and the coat record's breading does not describe one — the line counted whole as printed; the part left in the dish is not deducted)",
      );
    });

    test('the lipid on the record the totals read — STATED synthesized: '
        "saltimbocca's pan line as the real \"4 tablespoons extra-virgin "
        'olive oil" (748608 prints no 204; its sibling SR 171413 100 %) — '
        'the same share as the olive oil', () async {
      final evoo = await variant(
        withLine(
          loadCorpusRecipe(_saltimbocca),
          5,
          '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
          '4 tablespoons extra-virgin olive oil',
        ),
        'evoo',
      );
      final row = rowIn(evoo.id, 5);
      expect((row.fdcId, row.gramSource), (748608, 'discarded'));
      expect(row.grams?.toStringAsFixed(2), '9.92');
      // 53.66 g whole × 9.918 / 53.66 g of fat (171413's 100 %): the
      // olive oil's 9.92; the basis names the sibling (M77).
      expect(
        basisOf(evoo, 5),
        'discarded in cooking — only the fat the sautéed food keeps counted · nutrients of "Oil, olive, salad or cooking" · approximation (pan fat: 1.59 g fat per 100 g of the raw chicken breast — USDA FNDDS 2705980 recipe: 2 g oil per 125.77 g raw chicken breast (no record for the fat a sautéed piece keeps; the steps pour off / wipe out the rest))',
      );
    });

    test("the share's clamp — STATED synthesized: saltimbocca's pan line as "
        'the real "1 teaspoon olive oil" (4.53 g, under the 9.918 g of fat '
        'the breast keeps) — the line kept whole, never more', () async {
      final small = await variant(
        withLine(
          loadCorpusRecipe(_saltimbocca),
          5,
          '0258-broiled-salmon-with-mustard-and-crisp-dilled-crust.yaml',
          '1 teaspoon olive oil',
        ),
        'small',
      );
      final row = rowIn(small.id, 5);
      expect((row.fdcId, row.gramSource), (2710186, 'discarded'));
      expect(row.grams?.toStringAsFixed(2), '4.53');
      // min(1, 9.918 / 4.53) = 1: the whole line, never the 9.92 g share.
      expect(basisOf(small, 5), _pan('chicken breast'));
    });

    test("a person's Confirm of a pan line is the plan's grams (verify2 D2: "
        '`_panFatAt` in `derivedFor`) — the stored row, the derivation and '
        'the GET agree: saltimbocca|5 9.92 g, meunière|4 5.51 g, `discarded`, '
        'the pan basis; the per serving unmoved', () async {
      for (final (file, position, grams, basis, perServing) in [
        (_saltimbocca, 5, '9.92', _pan('chicken breast'), '407.82'),
        (_meuniere, 4, '5.51', _pan('flatfish', butter: true), '258.01'),
      ]) {
        final recipe = await variant(loadCorpusRecipe(file), 'confirm');
        final line = nutritionLines(recipe)[position];
        await applyMatchOverride(db, provider, recipe, position, {
          'raw': line.raw,
          'confirmed': true,
        });
        final stored = rowIn(recipe.id, position);
        final derived = (await derivedFor(
          db,
          provider,
          recipe,
          position,
          line,
          stored,
        )).row;
        final item =
            ((await matchesBody(db, provider, recipe))['items']! as List)
                    .cast<Map<String, Object?>>()
                    .singleWhere((i) => i['position'] == position)['match']!
                as Map<String, Object?>;
        final reason = '$file|$position';
        for (final form in <(Object?, String?, Object?)>[
          (stored.status, stored.grams?.toStringAsFixed(2), stored.gramSource),
          (
            derived.status,
            derived.grams?.toStringAsFixed(2),
            derived.gramSource,
          ),
          (
            item['status'],
            (item['grams'] as num?)?.toStringAsFixed(2),
            item['gram_source'],
          ),
        ]) {
          expect(form, ('confirmed', grams, 'discarded'), reason: reason);
        }
        expect(item['gram_basis'], basis, reason: reason);
        expect(
          db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
          perServing,
          reason: reason,
        );
      }
    });

    test('a pan row the plan no longer covers (verify2 D2: `_panFatAt` in '
        '`_unplannedOf`): a person skips the only coated food, no budget '
        'is left, and the recompute returns each pan line to its whole '
        'line — parmesan-crusted|6 18.14 g `density`, meunière|3 28.00 g '
        '`portion` and |4 28.36 g `density` (per serving 40.81 and 217.11: '
        'the pan lines whole, the coated food gone)', () async {
      for (final (file, food, pans, perServing) in [
        (_parmesan, 0, [(6, '18.14', 'density')], '40.81'),
        (
          _meuniere,
          1,
          [(3, '28.00', 'portion'), (4, '28.36', 'density')],
          '217.11',
        ),
      ]) {
        final recipe = await variant(loadCorpusRecipe(file), 'skip');
        for (final (position, _, _) in pans) {
          expect(rowIn(recipe.id, position).gramSource, 'discarded');
        }
        await applyMatchOverride(db, provider, recipe, food, {
          'raw': nutritionLines(recipe)[food].raw,
          'skipped': true,
        });
        expect(recomputeTotals(db, recipe), isTrue, reason: file);
        for (final (position, grams, source) in pans) {
          final row = rowIn(recipe.id, position);
          expect(
            (
              row.status,
              row.hold,
              row.grams?.toStringAsFixed(2),
              row.gramSource,
            ),
            ('auto', null, grams, source),
            reason: '$file|$position',
          );
        }
        expect(
          db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
          perServing,
          reason: file,
        );
      }
    });

    test('a second recompute writes nothing — rows and totals', () {
      for (final recipe in recipes.values) {
        List<(int, double?, String?, String?, String?)> rows() => [
          for (final r in db.ingredientMatchesFor(recipe.id))
            (r.position, r.grams, r.gramSource, r.hold, r.updatedAt),
        ];
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        final before = rows();
        final totals = batchTotalsOf(db.nutritionFor(recipe.id)!);
        expect(recomputeTotals(db, recipe), isTrue, reason: recipe.slug);
        expect(rows(), before, reason: recipe.slug);
        expect(batchTotalsOf(db.nutritionFor(recipe.id)!), totals);
      }
    });
  });
}
