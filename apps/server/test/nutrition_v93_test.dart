// Matcher v93 (batch M91; matcherVersion 88 — doubanjiang on the miso
// record; prep51 design_v2 §1 Q7 (i) option (a), ruled by the owner
// 2026-10-29; zero requests): FDC holds no doubanjiang — the lines' own
// answers ('asian broad bean chili paste', 'asian broad-bean chili paste')
// hold chili stews and FNDDS 2710309 "Bean paste, sweetened", no miso, and
// landed SR 172110 "Chili with beans, microwavable bowls" at 0.09, below
// the gate, 0 kcal. Two `_rankAs` keys read the cached 'white miso' answer
// ranked under 'miso' (the shipped doenjang S3 form — never a query
// rewrite: M85's lesson) and two `approximationRecords` keys flag SR 172442
// "Miso" (198 kcal, tbsp 17 g, cup 275 g) through `isApproximation`. The
// corpus reach is the two lines, both spellings printed by the corpus:
// sichuan-stir-fried-pork-in-garlic-sauce|15 (hyphen) 30.50 g on 172110 →
// 34.00 g on 172442, 67.32 kcal; mapo-tofu-sichuan-braised-tofu-with-beef|6
// (space) 81.33 g → 91.67 g, 181.50 kcal. Every figure is a fresh compute on
// the fixtures (FixtureProvider) and equals the v93 replay of snapshot 30
// (fix93 gate1) on every pinned row field and on both recipes' per
// serving and total grams; the answers the two recipes' other lines read
// were recorded from snapshot 30 with tool/record_fdc_fixtures.dart
// --from-db ('soft tofu', 'fermented black beans', 'sichuan chili powder'
// and FNDDS 2707359's detail). Never the network. Every corpus line is
// real; nothing here is synthesized (the corpus prints both spellings).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _sichuan = '0540-sichuan-stir-fried-pork-in-garlic-sauce.yaml';
const _mapo = '0534-mapo-tofu-sichuan-braised-tofu-with-beef.yaml';
const _tilapia = '1083-sauteed-tilapia-with-chive-lemon-miso-butter.yaml';

/// The two lines and their normalized items (both spellings the corpus
/// prints: 0540 the hyphen, 0534 the space).
const _lines = [
  (
    _sichuan,
    15,
    '2 tablespoons Asian broad-bean chili paste',
    'asian broad-bean chili paste',
  ),
  (
    _mapo,
    6,
    '⅓ cup Asian broad bean chili paste',
    'asian broad bean chili paste',
  ),
];

void main() {
  test('matcherVersion 91 (v93 set it to 88, batch M91: two rows move)', () {
    // RE-PIN (M92 batch, v94): matcherVersion 89 (was 88).
    // RE-PIN (M93 batch, v95): matcherVersion 90 (was 89).
    // RE-PIN (M94 batch, v96): matcherVersion 91 (was 90).
    expect(matcherVersion, 91);
  });

  group('the keys on the corpus lines (no compute)', skip: skipIfNoCorpus, () {
    test('both spellings read the cached white-miso answer ranked under '
        "'miso' — the doenjang form — and flag 172442, never 172110", () {
      for (final (file, i, raw, item) in _lines) {
        final line = nutritionLines(loadCorpusRecipe(file))[i];
        expect(line.raw, raw, reason: file);
        expect(normalizeItem(line.item ?? line.raw), item, reason: file);
        expect(
          rankAsFor(item),
          (query: 'miso', answer: 'white miso'),
          reason: file,
        );
        expect(rankAsFor(item), rankAsFor('doenjang'), reason: file);
        expect(approximationRecords[item], 172442, reason: file);
        expect(
          isApproximation(
            item: item,
            raw: raw,
            fdcId: 172442,
            description: 'Miso',
          ),
          isTrue,
          reason: file,
        );
        expect(
          isApproximation(
            item: item,
            raw: raw,
            fdcId: 172110,
            description: 'Chili with beans, microwavable bowls',
          ),
          isFalse,
          reason: file,
        );
      }
    });

    test('a real miso line is no key: sauteed-tilapia|3 "2 tablespoons white '
        'miso" reads its own answer, unflagged', () {
      final line = nutritionLines(loadCorpusRecipe(_tilapia))[3];
      expect(line.raw, '2 tablespoons white miso');
      final item = normalizeItem(line.item ?? line.raw);
      expect(item, 'white miso');
      expect(rankAsFor(item), isNull);
      expect(approximationRecords[item], isNull);
      expect(
        isApproximation(
          item: item,
          raw: line.raw,
          fdcId: 172442,
          description: 'Miso',
        ),
        isFalse,
      );
    });
  });

  group('each line alone (the v37 S3 form)', skip: skipIfNoCorpus, () {
    test('the two keyed lines on 172442 flagged; the converse tilapia|3 '
        '"2 tablespoons white miso" on 172442 at 0.575, unflagged — its own '
        'answer, unchanged', () async {
      for (final (file, i, confidence, grams, basis) in const [
        (
          _sichuan,
          15,
          '1.000000',
          '34.00',
          '2 tablespoon · USDA portion · approximation (counted as Miso)',
        ),
        (
          _mapo,
          6,
          '1.000000',
          '91.67',
          '1/3 cup · USDA portion · approximation (counted as Miso)',
        ),
        (_tilapia, 3, '0.575000', '34.00', '2 tablespoon · USDA portion'),
      ]) {
        final line = nutritionLines(loadCorpusRecipe(file))[i];
        final dir = Directory.systemTemp.createTempSync('salt-v93-line');
        addTearDown(() => dir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${dir.path}/salt.db')
          ..upsertSource(slug: 'src', name: 'Test', type: 'book');
        addTearDown(db.dispose);
        final recipe = Recipe(
          id: 'r',
          title: 'r',
          slug: 'r',
          source: const RecipeSource(name: 'Test', type: 'book'),
          ingredients: [
            IngredientGroup(items: [line]),
          ],
        );
        db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
        await matchAndCompute(db, FixtureProvider(), recipe);
        final row = db.ingredientMatchesFor('r').single;
        expect(
          (
            row.fdcId,
            row.confidence.toStringAsFixed(6),
            row.grams?.toStringAsFixed(2),
            row.gramSource,
            row.status,
            row.hold,
          ),
          (172442, confidence, grams, 'portion', 'auto', null),
          reason: '$file|$i',
        );
        expect(gramBasisFor(db, line, row), basis, reason: '$file|$i');
      }
    });
  });

  group('matcher v93 (batch M91) — whole recipes', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      final dir = Directory.systemTemp.createTempSync('salt-v93-');
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
      for (final file in [_sichuan, _mapo]) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    IngredientMatchRow rowAt(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    test('P1: sichuan|15 and mapo-tofu|6 on SR 172442 "Miso" at 1.000000, '
        '`portion`, flagged (v92: 172110 at 0.09, 0 kcal)', () {
      for (final (file, i, confidence, grams, kcal, basis) in const [
        (
          _sichuan,
          15,
          '1.000000',
          '34.00',
          '67.32',
          '2 tablespoon · USDA portion · approximation (counted as Miso)',
        ),
        (
          _mapo,
          6,
          '1.000000',
          '91.67',
          '181.50',
          '1/3 cup · USDA portion · approximation (counted as Miso)',
        ),
      ]) {
        final recipe = recipes[file]!;
        final row = rowAt(recipe.id, i);
        final line = nutritionLines(recipe)[i];
        final reason = '$file|$i';
        expect(
          (
            row.fdcId,
            row.description,
            row.confidence.toStringAsFixed(6),
            row.grams?.toStringAsFixed(2),
            row.gramSource,
            row.status,
            row.hold,
          ),
          (172442, 'Miso', confidence, grams, 'portion', 'auto', null),
          reason: reason,
        );
        final food = knownFood(db, 172442)!;
        expect(
          (kcalPer100g(food) * row.grams! / 100).toStringAsFixed(2),
          kcal,
          reason: reason,
        );
        expect(gramBasisFor(db, line, row, recipe: recipe), basis);
      }
    });

    test('the recipes: mapo-tofu complete at 574.11 a serving (v92 partial '
        '528.74), sichuan 417.12 (v92 400.29; still partial — |10 baking '
        'soda has no grams)', () {
      for (final (file, status, perServing, grams) in const [
        (_mapo, 'complete', '574.11', 1977.0),
        (_sichuan, 'partial', '417.12', 988.2),
      ]) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (n.status, n.caloriesPerServing?.toStringAsFixed(2), n.totalGrams),
          (status, perServing, grams),
          reason: file,
        );
      }
    });

    test('a second compute writes nothing: every row and total as the first '
        'compute left it', () async {
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
