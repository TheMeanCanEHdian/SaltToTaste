// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v85 (batch M83; matcherVersion 80 — step readers; prep51
// design_v2 §2 M83, decided under the 2026-10-07 standing authorization;
// zero requests): B1a a sentence serving "each portion|serving|bowl … with
// (about) <amount> <head>" counts that print × the recipe's serves (guard
// (ii)'s one exception; classic-gazpacho|10 0 → 35.76 g); B4 a fat an add /
// combine sentence joins to the frying oil takes its mass share of the same
// uptake (the two french fries' bacon fat, 1.59 g and 2.52 g, the peanut
// oil the rest); B5 a strained line no step names by its head is read by
// its item's own word before the head (the porcini of braised-turkey|11 and
// italian-wedding-soup|3, 0 g `discarded`). Every row value is the fresh
// compute of the WHOLE recipe over recorded real FDC answers
// (FixtureProvider) and equals the v85 replay of snapshot 29 (fix85 g1) on
// every pinned field; the negatives equal the v84 rows. Never the network.
// Every corpus line is real. STATED constructions (no corpus line reaches
// these gates): B1a's gates — classic-gazpacho step 2's real sentence
// rewritten (another noun, another multiplier, the print before the phrase
// or not after "with", another food after "with", no "about", a
// capitalized "Each portion", no serves printed, a per-serving sentence
// without the print beside a print elsewhere); B5's gates —
// braised-turkey's real porcini line and step 2 rewritten (the line
// doubled, a hyphenated own word, the head named with the own word only
// after the strain), vietnamese-beef-pho's steps 1–2 naming its ground beef
// "ground meat" (the drained guard); the cap shapes' repeated lines and
// steps (the house's cap-shape exception). Closer 1 (verify1): the serves
// hash term, `_servedWith`'s end anchor and the drained guard's own word.
// Closer 2 (verify2): the hash's lower serves (gazpacho's SERVES written
// 6 TO 10 and 8 TO 12), the own word's position (the porcini line without
// "dried", and a bare "mushrooms") and an alternative item's last head.
// Closer 3 (verify3): a plain print beside the served one (gazpacho's step
// 1 written with "1 teaspoon olive oil"), the serving noun's word end
// ("each bowlful"), the item words counted per line (|11 written "dried
// porcini mushrooms or fresh porcini mushrooms") and the own word read as
// a food (step 2's porcini written "1 cup porcini broth"). Closer 4 = the
// owner gate (verify4 D1–D4): a later multiplying sentence after the served
// one ("Repeat with the remaining olive oil."), a second print in the served
// sentence ("and adding 1 teaspoon olive oil" refused; "and finishing with
// 1 teaspoon olive oil" both × 8), the phrase printed twice (refused —
// ruled) and a letter before the phrase ("the peach portion").

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v26_cost_test.dart'
    show capLines, capStep, capSteps, capped, food, ln;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _uptake =
    'discarded in cooking — only the oil the fried food absorbs counted · '
    "approximation (frying oil absorbed: 6.0 % of the raw potatoes' weight — "
    'derived from USDA SR Legacy 170698 "Fast foods, potato, french fried in '
    'vegetable oil")';
const _strained =
    'discarded in cooking — counted as 0 g · approximate (strained out and '
    'discarded — what it gives the liquid is not counted)';
const _porcini =
    ' · approximate (FDC holds no porcini — counted as dried shiitake)';

/// The whole-recipe rows (file, position, raw, fdc id, source, grams, kcal,
/// basis) — the v84 replay's value in each comment where the row moved.
typedef _Row = (String, int, String, int, String, String, String, String);

const _gazpacho = '0031-classic-gazpacho.yaml';
const _classic = '0316-classic-french-fries.yaml';
const _easier = '0317-easier-french-fries.yaml';
const _turkey = '0172-braised-turkey.yaml';
const _wedding = '0402-italian-wedding-soup.yaml';

/// B1a (mutants: "× serves" dropped reads 4.47 g; the per-serving arm
/// removed reads 0.00 g, "no amount on the line — counted as 0 g").
const List<_Row> _b1a = [
  // v84: 0.00 g, 0.00 kcal (unmeasured)
  (
    _gazpacho,
    10,
    'Extra-virgin olive oil, for serving',
    748608,
    'portion',
    '35.76',
    '316.16',
    'from step 2: about 1 teaspoon × 8 portions (no amount on the line) · '
        'nutrients of "Oil, olive, salad or cooking"',
  ),
];

/// B4 (mutants: the fryer gate restored reads |2 0.00 g and |1 55.11 /
/// 68.04 g; the pF R3 basis restored alone reads |2 "… counted as 0 g ·
/// part of the frying medium …" at 1.59 g). 2 quarts of peanut oil weigh
/// 1,741.29 g ("2 quart ≈ 1893 mL" × 0.92 — 2710187 prints no quart), 6
/// cups its own 224 g cup: the bacon's ¼ cup (51.60 g — 12 × SR 172345's
/// one portion, '1 tsp' 4.3 g; it prints no cup) takes 51.60 / 1,792.89
/// and 51.60 / 1,395.60 of the uptake.
const List<_Row> _b4 = [
  // v84: 55.11 g, 495.99 kcal
  (
    _classic,
    1,
    '2 quarts peanut oil',
    2710187,
    'discarded',
    '53.53',
    '481.77',
    _uptake,
  ),
  // v84: 0.00 g, 0.00 kcal, "… counted as 0 g · part of the frying medium (…)"
  (
    _classic,
    2,
    '¼ cup bacon fat, strained (optional)',
    172345,
    'discarded',
    '1.59',
    '14.26',
    _uptake,
  ),
  // v84: 68.04 g, 612.36 kcal
  (
    _easier,
    1,
    '6 cups peanut oil',
    2710187,
    'discarded',
    '65.52',
    '589.68',
    _uptake,
  ),
  // v84: 0.00 g, 0.00 kcal, "… counted as 0 g · part of the frying medium (…)"
  (
    _easier,
    2,
    '¼ cup bacon fat, strained (optional)',
    172345,
    'discarded',
    '2.52',
    '22.60',
    _uptake,
  ),
];

/// B5 (mutants: the own-word fallback dropped reads |11 14.17 g and |3 7.09
/// g `weight`; the head found by `lastIndexOf` — not its written forms —
/// reads the same: "dried porcini mushrooms" writes the head plural).
const List<_Row> _b5 = [
  // v84: 14.17 g, 41.96 kcal (weight), "from 1/2 ounce · approximate (FDC holds no porcini …)"
  (
    _turkey,
    11,
    '½ ounce dried porcini mushrooms, rinsed',
    168436,
    'discarded',
    '0.00',
    '0.00',
    '$_strained$_porcini',
  ),
  // v84: 7.09 g, 20.98 kcal (weight)
  (
    _wedding,
    3,
    '¼ ounce dried porcini mushrooms, rinsed',
    168436,
    'discarded',
    '0.00',
    '0.00',
    '$_strained$_porcini',
  ),
];

/// The negatives — each equal to its v84 row on every field. B1a:
/// mulligatawny's "spoon a dollop of yogurt into each bowl" prints no
/// amount; pizza|12's "Repeat with remaining 2 dough rounds, adding 1
/// tablespoon oil to baking sheet for each round" multiplies by "repeat",
/// "remaining" and "each round" (guard (ii) refuses, Q5 is the owner's).
/// B4: chicken-francese-2's two frying oils join no fat (25.94 + 27.08 g of
/// the 53.02 g uptake, the v84 split); dakgangjeong|0's sesame oil is no
/// frying medium (prep50's negative). B5: guay-tiew|2's own word "green"
/// ("scallions" → "green onions") is first named after the strain, so the
/// fallback reaches it and refuses; caldo-de-siete-mares|0's anchos (head
/// `pepper`) are no strained class.
const List<_Row> _negatives = [
  (
    '0027-mulligatawny-soup.yaml',
    16,
    'Plain yogurt',
    2259793,
    'unmeasured',
    '0.00',
    '0.00',
    'no amount on the line — counted as 0 g',
  ),
  (
    '0398-ultimate-grilled-pizza.yaml',
    12,
    'Extra-virgin olive oil',
    748608,
    'unmeasured',
    '0.00',
    '0.00',
    'no amount on the line — counted as 0 g',
  ),
  (
    '1133-chicken-francese.yaml',
    8,
    '⅓ cup extra-virgin olive oil for frying',
    748608,
    'discarded',
    '25.94',
    '229.31',
    'discarded in cooking — only the oil the fried food absorbs counted · '
        'nutrients of "Oil, olive, salad or cooking" · approximation (frying '
        "oil absorbed: 6.68 % of the raw chicken breast's weight — USDA FNDDS "
        '2705975 recipe: 7 g oil per 104.76 g raw chicken breast)',
  ),
  (
    '1133-chicken-francese.yaml',
    9,
    '⅓ cup vegetable oil for frying',
    2710180,
    'discarded',
    '27.08',
    '243.72',
    'discarded in cooking — only the oil the fried food absorbs counted · '
        "approximation (frying oil absorbed: 6.68 % of the raw chicken breast's "
        'weight — USDA FNDDS 2705975 recipe: 7 g oil per 104.76 g raw chicken '
        'breast)',
  ),
  (
    '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
    0,
    '1 tablespoon toasted sesame oil',
    2710190,
    'portion',
    '14.00',
    '123.76',
    '1 tablespoon · USDA portion',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    2,
    '4 scallions, trimmed, white parts left whole, green parts cut into 1-inch lengths',
    2709794,
    'piece',
    '60.00',
    '19.20',
    '4 × 15 g each',
  ),
  (
    '1207-caldo-de-siete-mares.yaml',
    0,
    '3 dried ancho chiles, stemmed, seeded, and torn into ½-inch pieces (¾ cup)',
    169396,
    'piece',
    '51.00',
    '143.31',
    '3 · USDA per-item weight',
  ),
];

/// A recorded record, as the engine reads it.
Future<FdcFood> _food(int fdcId) async =>
    (await FixtureProvider(pending: {...pendingSearches}).food(fdcId))!;

/// A database holding nothing, as a line weighed alone reads it.
SaltDatabase _emptyDb() {
  final dir = Directory.systemTemp.createTempSync('salt-v85-');
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

/// [recipe] with the first [from] of step [step] (0-based) written [to].
Recipe _rewrite(Recipe recipe, int step, String from, String to) {
  expect(recipe.steps[step].text, contains(from));
  return recipe.copyWith(
    steps: [
      for (final (i, s) in recipe.steps.indexed)
        i == step ? s.copyWith(text: s.text.replaceFirst(from, to)) : s,
    ],
  );
}

void main() {
  test('matcherVersion 80 (v85, batch M83: rows move)', () {
    expect(matcherVersion, 80);
  });

  group('matcher v85 (batch M83) — whole recipes', skip: skipIfNoCorpus, () {
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
      'B1a': _b1a,
      'B4': _b4,
      'B5': _b5,
      'the negatives': _negatives,
    };

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v85-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      for (final file in {
        for (final rows in tables.values)
          for (final r in rows) r.$1,
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

    String kcalOf(IngredientMatchRow row) {
      final food = knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!;
      return (kcalPer100g(food) * (row.grams ?? 0) / 100).toStringAsFixed(2);
    }

    for (final MapEntry(key: rule, value: rows) in tables.entries) {
      test('$rule: each row its record, source, grams, energy and basis '
          "(the v85 replay's)", () {
        for (final (file, position, raw, fdcId, source, grams, kcal, basis)
            in rows) {
          final recipe = recipes[file]!;
          final line = nutritionLines(recipe)[position];
          final row = rowIn(recipe.id, position);
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
    }

    test("B4: the uptake is unchanged — the fries absorb SR 170698's 6.0 % "
        'of the raw potatoes either way (v84: classic 55.11 g on |1 alone, '
        'easier 68.04 g); the plan rounds each fryer alone (53.53 + 1.59 = '
        '55.12)', () {
      String sum(String file) {
        final id = recipes[file]!.id;
        return (rowIn(id, 1).grams! + rowIn(id, 2).grams!).toStringAsFixed(2);
      }

      expect(sum(_classic), '55.12');
      expect(sum(_easier), '68.04');
    });

    test('a second compute writes nothing: every row of the five reached '
        'recipes as the first compute left it', () async {
      for (final file in [_gazpacho, _classic, _easier, _turkey, _wedding]) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final before = rowsOf();
        expect(
          await matchAndCompute(db, provider, db.recipeByIdOrSlug(id)!.recipe),
          isNull,
        );
        expect(rowsOf(), before, reason: file);
        expect(
          nutritionIsFresh(
            db,
            db.recipeByIdOrSlug(id)!.recipe,
            db.nutritionFor(id),
          ),
          isTrue,
        );
      }
    });

    // The group's last test: it edits the stored gazpacho.
    test('B1a: the serves are hashed — "SERVES 4" written over SERVES 8 TO '
        "10 stales gazpacho's stamp, and its recompute counts |10 × 4 under "
        'the stored basis 8, 17.88 g (closer 1, verify1 D1: unhashed, the '
        'stamp read fresh while the recompute moved the row; mutant: the '
        '`serves` term dropped); a recipe whose steps print no "each '
        'portion|serving|bowl" hashes a serves edit as before (mutant: the '
        'term on every recipe)', () async {
      final memo = ResolverMemo(db);
      final fries = recipes[_classic]!;
      expect(
        ingredientsHashOf(
          fries.copyWith(serves: const Serves(min: 2, max: 2)),
          memo,
        ),
        ingredientsHashOf(fries, memo),
      );
      final id = recipes[_gazpacho]!.id;
      expect(db.nutritionFor(id)!.servingBasis, 8);
      final edited = db
          .recipeByIdOrSlug(id)!
          .recipe
          .copyWith(servings: 'SERVES 4', serves: const Serves(min: 4, max: 4));
      db.upsertRecipe(
        edited,
        sourceSlug: _source,
        contentHash: contentHashOf(edited),
      );
      final stored = db.recipeByIdOrSlug(id)!.recipe;
      expect(nutritionIsFresh(db, stored, db.nutritionFor(id)), isFalse);
      expect(await matchAndCompute(db, provider, stored), isNull);
      final row = rowIn(id, 10);
      expect(row.grams?.toStringAsFixed(2), '17.88');
      expect(
        gramBasisFor(db, nutritionLines(stored)[10], row, recipe: stored),
        'from step 2: about 1 teaspoon × 4 portions (no amount on the line) · '
        'nutrients of "Oil, olive, salad or cooking"',
      );
      // The batch's 4 teaspoons over the stored basis 8 (the label serving
      // an eighth of the batch): 107.86 kcal, was 127.63.
      final label = db.nutritionFor(id)!;
      expect(
        (label.servingBasis, label.caloriesPerServing?.toStringAsFixed(2)),
        (8, '107.86'),
      );
      expect(
        nutritionIsFresh(db, db.recipeByIdOrSlug(id)!.recipe, label),
        isTrue,
      );
    });
  });

  // B1a's gates, each on classic-gazpacho step 2's real sentence ("Serve
  // cold, drizzling each portion with about 1 teaspoon olive oil and
  // topping with the desired garnishes.") — STATED rewrites: no other
  // corpus sentence serves an amount-less line "each portion … with" (pB's
  // census, b1_reach.tsv: gazpacho|10 is the one). The line weighed alone
  // ([lineGrams], as the engine weighs it) on 748608, recorded.
  group('B1a — the per-serving arm, gate by gate', skip: skipIfNoCorpus, () {
    const sentence =
        'Serve cold, drizzling each portion with about 1 teaspoon olive oil';
    final gazpacho = loadCorpusRecipe(_gazpacho);

    Future<(String, String?)?> read(Recipe r) async {
      final line = nutritionLines(r)[10];
      expect(line.raw, 'Extra-virgin olive oil, for serving');
      final g = lineGrams(_emptyDb(), line, await _food(748608), recipe: r);
      return g == null ? null : (g.grams.toStringAsFixed(2), g.basis);
    }

    List<({int step, String amount})> prints(Recipe r) =>
        stepAmountsOf(r, nutritionLines(r)[10]);

    test('the real sentence: 1 teaspoon × the 8 the recipe serves (SERVES 8 '
        'TO 10 — the lower number), "about" kept in the basis', () async {
      expect(gazpacho.serves?.min, 8);
      expect(gazpacho.steps[1].text, contains(sentence));
      expect(await read(gazpacho), (
        '35.76',
        'from step 2: about 1 teaspoon × 8 portions (no amount on the line)',
      ));
      // The public reading names the print once (its count is the weigh's).
      expect(prints(gazpacho), [(step: 1, amount: '1 teaspoon')]);
    });

    test(
      'the serving nouns: "each serving" and "each bowl" read as "each '
      'portion" does (mutants: either noun dropped from [_eachServing])',
      () async {
        for (final (noun, plural) in [
          ('serving', 'servings'),
          ('bowl', 'bowls'),
        ]) {
          final r = _rewrite(gazpacho, 1, 'each portion', 'each $noun');
          expect(await read(r), (
            '35.76',
            'from step 2: about 1 teaspoon × 8 $plural (no amount on the line)',
          ));
        }
      },
    );

    test('the hash reads the phrase case-blind: step 2 written "Serve cold. '
        'Each portion is drizzled with about 1 teaspoon olive oil" — the arm '
        'reads it on the lower-cased index, and a serves edit moves the hash '
        '(closer 1, verify1 D1; mutant: [_eachServing] case-sensitive — the '
        'raw "Each" leaves the serves unhashed)', () async {
      final r = _rewrite(
        gazpacho,
        1,
        'Serve cold, drizzling each portion with',
        'Serve cold. Each portion is drizzled with',
      );
      expect(await read(r), (
        '35.76',
        'from step 2: about 1 teaspoon × 8 portions (no amount on the line)',
      ));
      final memo = ResolverMemo(_emptyDb());
      expect(
        ingredientsHashOf(
          r.copyWith(serves: const Serves(min: 4, max: 4)),
          memo,
        ),
        isNot(ingredientsHashOf(r, memo)),
      );
    });

    test('the hash reads the LOWER serves, the one the arm counts by: '
        'SERVES 8 TO 10 written 6 TO 10 (the lower number alone) moves the '
        'hash and the read × 6; written 8 TO 12 (the upper alone) moves '
        'neither (closer 2, verify2 D2; mutant: the `serves` term reads '
        '`max` — the lower-only edit leaves the stamp fresh while the '
        'recompute counts × 6)', () async {
      final memo = ResolverMemo(_emptyDb());
      final hash = ingredientsHashOf(gazpacho, memo);
      final lower = gazpacho.copyWith(
        servings: 'SERVES 6 TO 10',
        serves: const Serves(min: 6, max: 10),
      );
      expect(ingredientsHashOf(lower, memo), isNot(hash));
      expect(await read(lower), (
        '26.82',
        'from step 2: about 1 teaspoon × 6 portions (no amount on the line)',
      ));
      final upper = gazpacho.copyWith(
        servings: 'SERVES 8 TO 12',
        serves: const Serves(min: 8, max: 12),
      );
      expect(ingredientsHashOf(upper, memo), hash);
      expect(await read(upper), (
        '35.76',
        'from step 2: about 1 teaspoon × 8 portions (no amount on the line)',
      ));
    });

    test('no "about": the print as printed (mutant: group 1 of '
        '[_servedWith] read always — the basis says "about")', () async {
      final r = _rewrite(gazpacho, 1, 'with about 1', 'with 1');
      expect(await read(r), (
        '35.76',
        'from step 2: 1 teaspoon × 8 portions (no amount on the line)',
      ));
    });

    test('refused as at v84 — another noun (pizza|12\'s "each round", a '
        '"bowlful" — the noun ends at a word boundary), another multiplier '
        '("the remaining soup"), the print before the phrase, a print after '
        'it not served "with", a "with" another food stands between ("with '
        'chives and 1 teaspoon") — each reads nothing (mutants: the noun '
        'alternation widened, its trailing word boundary dropped — closer 3, '
        'verify3 D2 — the other-multiplier test dropped, the window opened '
        'before the phrase, "with" widened, [_servedWith]\'s end anchor '
        'dropped — closer 1, verify1 m6)', () {
      for (final (from, to) in [
        ('each portion', 'each round'),
        ('each portion', 'each bowlful'),
        ('Serve cold,', 'Serve the remaining soup cold,'),
        (
          'drizzling each portion with about 1 teaspoon olive oil',
          'drizzling with about 1 teaspoon olive oil over each portion',
        ),
        ('each portion with about', 'each portion and adding about'),
        ('with about 1 teaspoon', 'with chives and 1 teaspoon'),
      ]) {
        expect(prints(_rewrite(gazpacho, 1, from, to)), isEmpty, reason: to);
      }
    });

    test('no serves printed: the sentence refuses (mutant: the serves gate '
        'dropped reads "× 0 portions")', () {
      final r = gazpacho.copyWith(serves: null);
      expect(r.serves, isNull);
      expect(prints(r), isEmpty);
    });

    test('a per-serving sentence naming the head without its print, the '
        'print in another sentence: refused, as guard (ii) refuses (mutant: '
        "the sentence's own-print test dropped reads step 1's 1 teaspoon "
        '× 1, 4.47 g)', () {
      final r = _rewrite(
        _rewrite(
          gazpacho,
          1,
          'with about 1 teaspoon olive oil',
          'with olive oil',
        ),
        0,
        'Let stand until',
        'Add 1 teaspoon olive oil and let stand until',
      );
      expect(prints(r), isEmpty);
    });

    // STATED (closer 3, verify3 D1): gazpacho prints its oil once, in the
    // per-serving sentence; step 1 written with a plain print beside it.
    test('a plain print beside the served one: only the served print counts '
        '× the serves — step 1 written "Add 1 teaspoon olive oil and let '
        'stand until" reads 1 + 1 × 8 teaspoons (mutant: every print × the '
        'serves once one is served — 16 teaspoons, 71.53 g)', () async {
      final r = _rewrite(
        gazpacho,
        0,
        'Let stand until',
        'Add 1 teaspoon olive oil and let stand until',
      );
      expect(prints(r), [
        (step: 0, amount: '1 teaspoon'),
        (step: 1, amount: '1 teaspoon'),
      ]);
      expect(await read(r), (
        '40.23',
        'from steps 1, 2: 1 teaspoon + about 1 teaspoon × 8 portions (no '
            'amount on the line)',
      ));
    });

    // STATED (verify4 D1, D3, D4 — closed in the owner gate): no corpus
    // sentence prints the serving phrase twice or a letter before it (the
    // verifier's scans: 0 and 0), and none follows a served sentence with a
    // later named multiplying one. The phrase printed twice is REFUSED
    // (ruled: the brief's "the sentence's only multiplying word is that
    // phrase" reads the phrase once — a second print is another multiplier).
    test('refused: a later multiplying sentence naming the head ("Repeat '
        'with the remaining olive oil." after the served sentence — guard '
        '(ii) walks past the served sentence to it; mutant: the walk stops '
        'at the first named sentence, `named.take(1)`, reads 35.76 g), the '
        'phrase printed twice ("topping each portion with the desired '
        'garnishes"; mutant: every phrase blanked before the multiplier '
        'test, `replaceAll`, reads 35.76 g), a letter before the phrase '
        '("the peach portion"; mutant: [_eachServing]\'s leading word '
        'boundary dropped reads 35.76 g)', () {
      for (final (from, to) in [
        (
          'topping with the desired garnishes.',
          'topping with the desired garnishes. Repeat with the remaining '
              'olive oil.',
        ),
        (
          'topping with the desired garnishes',
          'topping each portion with the desired garnishes',
        ),
        ('each portion', 'the peach portion'),
      ]) {
        expect(prints(_rewrite(gazpacho, 1, from, to)), isEmpty, reason: to);
      }
    });

    // STATED (verify4 D2): gazpacho's sentence prints its oil once; a
    // second print in the same sentence, served "with" or not.
    test(
      'every print in the served sentence must follow "with": "… and '
      'adding 1 teaspoon olive oil" refuses the sentence, "… and finishing '
      'with 1 teaspoon olive oil" counts both × 8 (71.53 g; mutant: only '
      'the first print tested, `mine.take(1)` — 40.23 g either way)',
      () async {
        expect(
          prints(
            _rewrite(
              gazpacho,
              1,
              'with about 1 teaspoon olive oil',
              'with about 1 teaspoon olive oil and adding 1 teaspoon olive oil',
            ),
          ),
          isEmpty,
        );
        final r = _rewrite(
          gazpacho,
          1,
          'with about 1 teaspoon olive oil',
          'with about 1 teaspoon olive oil and finishing with 1 teaspoon '
              'olive oil',
        );
        expect(prints(r), [
          (step: 1, amount: '1 teaspoon'),
          (step: 1, amount: '1 teaspoon'),
        ]);
        expect(await read(r), (
          '71.53',
          'from step 2: about 1 teaspoon × 8 portions + 1 teaspoon × 8 '
              'portions (no amount on the line)',
        ));
      },
    );
  });

  // B5's gates, each on braised-turkey's real porcini line (|11) and step
  // 2's real "Toss the onions, celery, carrots, garlic, bay leaves, thyme,
  // parsley, porcini, and 2 tablespoons of the melted butter" — STATED
  // rewrites: the corpus's two porcini lines are the fallback's only reach
  // (pB's census, b5_rows.tsv), so its refusals need a constructed line or
  // step. guay-tiew|2 (above, real) is the one corpus refusal: its own
  // word "green" ("scallions" normalizes to "green onions") is first named
  // in step 3's "scallion greens", after the strain.
  group('B5 — the own-word fallback, gate by gate', skip: skipIfNoCorpus, () {
    final turkey = loadCorpusRecipe(_turkey);

    DiscardedMedium? medium(Recipe r, int position) {
      final line = nutritionLines(r)[position];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    /// [recipe] with its porcini line (|11) written [raws].
    Recipe lines(Recipe recipe, List<String> raws) {
      final group = recipe.ingredients.first;
      expect(group.items[11].raw, '½ ounce dried porcini mushrooms, rinsed');
      return recipe.copyWith(
        ingredients: [
          group.copyWith(
            items: [
              ...group.items.take(11),
              for (final raw in raws) ln(raw),
              ...group.items.skip(12),
            ],
          ),
          ...recipe.ingredients.skip(1),
        ],
      );
    }

    test('the real line: strained out by its own word "porcini"', () {
      expect(medium(turkey, 11), DiscardedMedium.strainedSolid);
    });

    test('another line carries the word — the line doubled: neither is read '
        'by it (mutant: "no other line" widened to "some line")', () {
      const raw = '½ ounce dried porcini mushrooms, rinsed';
      final r = lines(turkey, [raw, raw]);
      expect(medium(r, 11), isNull);
      expect(medium(r, 12), isNull);
    });

    test('an own word that is no word-only token ("porcini-style", the line '
        'and step 2 written so): not read (mutant: the word-only test '
        'dropped)', () {
      final r = _rewrite(
        lines(turkey, ['½ ounce dried porcini-style mushrooms, rinsed']),
        1,
        'parsley, porcini,',
        'parsley, porcini-style,',
      );
      expect(medium(r, 11), isNull);
    });

    // STATED (closer 2, verify2 D1 / D3): the corpus's two porcini lines
    // both print "dried porcini mushrooms", so the own word's position and
    // an alternative item need |11 written so.
    test('the own word is the word before the head: the line written '
        'without "dried" ("porcini mushrooms", the head second) is strained '
        'out by "porcini"; a bare-head item ("mushrooms", the head first) '
        'has no own word — not read (mutant: `at < 2` — the one-word own '
        'word refused)', () {
      expect(
        medium(lines(turkey, ['½ ounce porcini mushrooms, rinsed']), 11),
        DiscardedMedium.strainedSolid,
      );
      expect(
        medium(lines(turkey, ['½ ounce mushrooms, rinsed']), 11),
        isNull,
      );
    });

    test('an alternative item reads the word before the LAST head, as '
        "[_joinsFryingOil]'s lastIndexOf does: \"dried porcini mushrooms "
        'or shiitake mushrooms" reads "shiitake", which no step names — not '
        'read (mutant: the first head — "porcini", strained out)', () {
      const raw =
          '½ ounce dried porcini mushrooms or shiitake mushrooms, rinsed';
      final r = lines(turkey, [raw]);
      final line = nutritionLines(r)[11];
      expect(
        normalizeItem(lineItemOf(line)).split(' '),
        containsAllInOrder([
          'porcini',
          'mushrooms',
          'shiitake',
          'mushrooms',
        ]),
      );
      expect(medium(r, 11), isNull);
    });

    // STATED (closer 3, verify3 D3): the corpus's two porcini lines print
    // "porcini" once each, so a line carrying it twice needs |11 written so.
    test('the item words are counted per line: "dried porcini mushrooms or '
        'fresh porcini mushrooms" carries "porcini" twice on ONE line, on no '
        'other — strained out by it (mutant: the per-line word set dropped — '
        "the line's own repeat counts as another line, not read)", () {
      const raw =
          '½ ounce dried porcini mushrooms or fresh porcini mushrooms, rinsed';
      final r = lines(turkey, [raw]);
      expect(
        normalizeItem(lineItemOf(nutritionLines(r)[11])),
        'dried porcini mushrooms or porcini mushrooms',
      );
      expect(medium(r, 11), DiscardedMedium.strainedSolid);
    });

    // STATED (closer 3, verify3 D4): step 2's real "porcini" written as a
    // liquid — no corpus step names the own word only in a liquid phrase.
    test('the own word is read as a food: step 2 naming only "1 cup porcini '
        'broth" (a liquid, no mention of the dried porcini) — not read '
        '(mutant: the word read through [_naming], the broth a mention — '
        'strained out)', () {
      final r = _rewrite(
        turkey,
        1,
        'parsley, porcini, and',
        'parsley, 1 cup porcini broth, and',
      );
      expect(medium(r, 11), isNull);
    });

    test("the guards read the own word's mentions: step 7 naming the "
        'porcini again after the strain returns it to the dish — counted, as '
        'a head named after its strain is (mutant: the returned guard reads '
        "the head's mentions, none, and strains it)", () {
      final r = _rewrite(
        turkey,
        6,
        'Carve the turkey and serve,',
        'Carve the turkey and serve with the porcini,',
      );
      expect(medium(r, 11), isNull);
    });

    test(
      'a head the steps name keeps its own mentions — step 2 naming '
      '"porcini mushrooms", the word alone again after the strain: '
      'strained by the head (mutant: the fallback read whenever the line '
      "has an own word — the word's mention after the strain returns it)",
      () {
        final r = _rewrite(
          _rewrite(
            turkey,
            1,
            'parsley, porcini,',
            'parsley, porcini mushrooms,',
          ),
          6,
          'Carve the turkey and serve,',
          'Carve the turkey and serve with the porcini,',
        );
        expect(medium(r, 11), DiscardedMedium.strainedSolid);
      },
    );

    // STATED rewrite (closer 1, verify1 m13): no corpus stock-meat line
    // reaches the fallback (on snapshot 29 the B5 revert moves only the two
    // porcini rows, fix85 attribution), so vietnamese-beef-pho's real
    // "1 pound 85 percent lean ground beef" (|0) has its steps 1–2's
    // "ground beef" written "ground meat": no step names the head `beef`,
    // and the own word "ground" is drained in step 1 ("Drain ground meat in
    // colander") before step 3's strain.
    test("the stock-meat guard reads the own word's mentions: the pho's "
        'ground beef named only as "ground meat" is blanched and drained '
        'before the strain — strained out, as by its head (mutant: the '
        'drained memo keyed on the head reads no mention: `fatKept`)', () {
      final pho = loadCorpusRecipe('0010-vietnamese-beef-pho.yaml');
      expect(nutritionLines(pho)[0].raw, '1 pound 85 percent lean ground beef');
      expect(medium(pho, 0), DiscardedMedium.strainedSolid);
      final r = pho.copyWith(
        steps: [
          for (final (i, s) in pho.steps.indexed)
            i < 2
                ? s.copyWith(
                    text: s.text.replaceAll('ground beef', 'ground meat'),
                  )
                : s,
        ],
      );
      expect(r.steps.any((s) => s.text.contains('beef')), isFalse);
      expect(medium(r, 0), DiscardedMedium.strainedSolid);
    });
  });

  // RULE C, M83's two readers at the caps, at the loop level (every line's
  // discardedMediumOf, stepAmountsOf and lineGrams on no record, as
  // nutrition_v26_cost_test's shapes read their detectors — the cap
  // shapes' heads are synthesized, so no recorded search answers them).
  // Synthesized, a stated exception: the repeated lines and the steps.
  // B1a (on 0031's recipe, SERVES 8 TO 10): 400 amount-less lines of 400
  // distinct heads (nutrition_v26_cost_test's `food`) under 120 steps of
  // 10,000 characters of "<lead>, drizzling each portion with about 1
  // teaspoon <head>." — TRUE (lead "Serve": every line reads its prints ×
  // 8) and QUIET (lead "Serve the remaining soup": another multiplier, every
  // sentence refuses). B5 (on 0172's steps, the strain at step 5): TRUE —
  // 400 lines "½ ounce dried <word> mushrooms, rinsed" of 400 distinct own
  // words, each tossed in by a sentence of its own before the strain (399
  // strained out; "pepper" is named again after the strain, in step 6's
  // seasoning); QUIET — 400 copies of the real porcini line (the word
  // carried by every line: the fallback refuses at its "no other line"
  // test); AMOUNTLESS — 400 "Dried porcini mushrooms" (the brief's literal
  // shape: an amount-less line returns at `_strainedOut`'s first gate and
  // never reaches the fallback). Counts: each shape's map exactly (the
  // process-wide `names` compile count aside), measured on the tree; base
  // a5ea2da's maps equal them but for each reader's own work — B1a TRUE
  // `memo:stepAmountGrams` 400 (base refuses, weighing none); B5 TRUE the
  // 400 own words' `memo:foodNaming` / `memo:namedAfterStrain` and the
  // naming inversion they trigger (`memo:namingAll` 1, `memo:named` 390,
  // `memo:naming` 1 → 12) plus the guards they reach (`memo:liftsVegetables`,
  // `memo:smooth`); B5 QUIET `memo:itemWords` 1 alone; B1a QUIET and
  // AMOUNTLESS equal base. Clocks (fix85, two runs each, base → tree): B1a
  // TRUE 165 / 124 → 219 / 156 ms (the 400 lines weighed and their 17,344
  // prints' "with" windows — no base equivalent); B1a QUIET 104 / 110 →
  // 110 / 108; B5 TRUE 37 / 29 → 43 / 33; B5 QUIET 28 / 25 → 27 / 27;
  // AMOUNTLESS 18 / 18 → 19 / 19 — each under the backstop.
  group(
    'RULE C, the per-serving and own-word readers at the caps',
    skip: skipIfNoCorpus,
    () {
      Recipe b1a(String lead) {
        final base = loadCorpusRecipe(_gazpacho);
        final heads = [for (var i = 0; i < capLines; i++) food(i)];
        String step(int k) {
          final s = StringBuffer();
          var i = k * 37 % capLines;
          while (true) {
            final t =
                '$lead, drizzling each portion with about 1 teaspoon '
                '${heads[i]}. ';
            if (s.length + t.length > capStep) {
              break;
            }
            s.write(t);
            i = (i + 1) % capLines;
          }
          return s.toString();
        }

        return capped(base, heads, [
          for (var k = 0; k < capSteps; k++) step(k),
        ]);
      }

      Recipe b5(List<String> raws, List<String> words) {
        final base = loadCorpusRecipe(_turkey);
        final steps = [for (final s in base.steps) s.text];
        final half = (words.length + 1) ~/ 2;
        return capped(base, raws, [
          ...steps.take(2),
          for (final part in [words.take(half), words.skip(half)])
            [for (final w in part) 'Toss in the $w. '].join(),
          ...steps.skip(2),
        ]);
      }

      final shapes = <String, (Recipe Function(), int, int)>{
        'B1a-TRUE': (() => b1a('Serve'), 400, 0),
        'B1a-QUIET': (() => b1a('Serve the remaining soup'), 0, 0),
        'B5-TRUE': (
          () => b5(
            [
              for (var i = 0; i < capLines; i++)
                '½ ounce dried ${food(i)} mushrooms, rinsed',
            ],
            [for (var i = 0; i < capLines; i++) food(i)],
          ),
          0,
          399,
        ),
        'B5-QUIET': (
          () => b5(
            List.filled(capLines, '½ ounce dried porcini mushrooms, rinsed'),
            ['porcini'],
          ),
          0,
          0,
        ),
        'B5-AMOUNTLESS': (
          () =>
              b5(List.filled(capLines, 'Dried porcini mushrooms'), ['porcini']),
          0,
          0,
        ),
      };

      for (final MapEntry(key: shape, value: (make, read, strained))
          in shapes.entries) {
        test('$shape: $read lines read, $strained strained out, the counts '
            'exact, within the backstop', () {
          final db = _emptyDb();
          final r = make();
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          var reads = 0;
          var strains = 0;
          for (final line in nutritionLines(r)) {
            final n = normalizeItem(lineItemOf(line));
            if (discardedMediumOf(r, line, n) ==
                DiscardedMedium.strainedSolid) {
              strains++;
            }
            if (stepAmountsOf(r, line).isNotEmpty) {
              reads++;
            }
            lineGrams(db, line, null, recipe: r);
          }
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts)..remove('names');
          expectBounded(r, counts, shape);
          expect((reads, strains), (read, strained), reason: shape);
          expect(counts, _capCounts[shape], reason: shape);
          expect(ms, lessThan(backstopMs), reason: shape);
        }, timeout: const Timeout(Duration(minutes: 3)));
      }
    },
  );
}

/// Each cap shape's counts on the tree (fix85 cost_tip3.log, the second run;
/// the process-wide `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'B1a-TRUE': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 17464,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 156096,
    'memo:naming': 12,
    'memo:strainAt': 1,
    'memo:stepAmountsAt': 400,
    'memo:labelScope': 1,
    'memo:stepAmounts': 1,
    'memo:namingAll': 1,
    'memo:named': 400,
    'stepPrints': 17344,
    'stepPrintsWalked': 17344,
    'memo:stepAmountGrams': 400,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
  'B1a-QUIET': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 13713,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 163116,
    'memo:naming': 12,
    'memo:strainAt': 1,
    'memo:stepAmountsAt': 400,
    'memo:labelScope': 1,
    'memo:stepAmounts': 1,
    'memo:namingAll': 1,
    'memo:named': 400,
    'stepPrints': 13593,
    'stepPrintsWalked': 13593,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
  'B5-TRUE': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 427,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'ends': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 2019,
    'memo:naming': 12,
    'memo:strainAt': 1,
    'memo:foodNaming': 401,
    'memo:itemWords': 1,
    'memo:namedAfterStrain': 400,
    'memo:liftsVegetables': 1,
    'memo:smooth': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'memo:namingAll': 1,
    'memo:named': 390,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
  },
  'B5-QUIET': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 28,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'ends': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 423,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:foodNaming': 1,
    'memo:itemWords': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
  'B5-AMOUNTLESS': {
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 28,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'ends': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 423,
    'memo:naming': 1,
    'memo:strainAt': 1,
    'memo:stepAmountsAt': 400,
    'memo:labelScope': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
};
