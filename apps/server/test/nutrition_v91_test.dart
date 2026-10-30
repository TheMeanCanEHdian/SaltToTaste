// Matcher v91 (batch M87; matcherVersion 86 — prep51 design_v2 §1 Q1
// option (b′), ruled by the owner 2026-10-29; zero requests): an UNMARKED
// line with an amount names its recipe's OWN section when the title's last
// TWO words are the last two of an item of three or more words (a shorter
// item keeps M76's whole-item tail) and the line's amount is the section's
// printed yield (share 1.0) — one test in the `_yieldTailOf` closure
// (engine.dart), so `namesOwnSection` (→ `isReferenceIn`, the stale hash,
// the parent test, `routedSectionKeysOf`) and the resolver's `_ownTitles`
// follow. The corpus reach is one line: fried-rice-with-shrimp-pork-and-
// shiitakes|9 "5 cups cold cooked white rice" (FNDDS 2708408, 790.00 g,
// 1,019.10 kcal at v90) reads its own "Basic White Rice" (MAKES ABOUT 5
// CUPS) at 1.0: 402.20 g, 1,486.68 kcal (the section's Foundation 2512381
// rice at 958 since v90). A ONE-word shared tail is refused. Every figure is
// a fresh compute on the fixtures and equals the v91 replay of snapshot 30
// (fix91 gate1). Never the network. Every corpus line is real; the
// synthesized cases (the floor, whole words, a title that IS the two words,
// the pair mid-title, a three-word item) are stated where they stand.

import 'dart:convert';
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

const _friedRice = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
const _beans = '0712-red-beans-and-rice.yaml';
const _satay = '0621-grilled-beef-satay.yaml';
const _mousse = '0935-fresh-strawberry-mousse.yaml';
const _burgers = '0309-juicy-grilled-turkey-burgers.yaml';
const _rice = 'Basic White Rice';

String _norm(String text) => foldAccents(
  text.toLowerCase(),
).replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

/// The trailing words [a] and [b] share (pF's `commonTail`).
int _sharedTail(String a, String b) {
  final x = a.split(' ');
  final y = b.split(' ');
  var k = 0;
  while (k < x.length &&
      k < y.length &&
      x[x.length - 1 - k] == y[y.length - 1 - k]) {
    k++;
  }
  return k;
}

(Recipe, IngredientLine, Subsection) _at(String file, int i, String title) {
  final recipe = loadCorpusRecipe(file);
  return (
    recipe,
    nutritionLines(recipe)[i],
    recipe.subsections.singleWhere((s) => s.title == title),
  );
}

void main() {
  test('matcherVersion 87 (v91 set it to 86, batch M87: one row moves)', () {
    // RE-PIN (M89 batch, v92): matcherVersion 87 (was 86).
    expect(matcherVersion, 87);
  });

  group(
    'the two-word shared tail on the corpus lines (no compute)',
    skip: skipIfNoCorpus,
    () {
      test('fried-rice|9 names its own "Basic White Rice" by the two words '
          "both end in, at its printed yield; M76's whole-item tail alone does "
          'not reach it', () {
        final (recipe, line, sub) = _at(_friedRice, 9, _rice);
        final item = referenceItemOf(line);
        expect(
          line.raw,
          '5 cups cold cooked white rice, large clumps broken up with fingers',
        );
        expect(item, 'cold cooked white rice');
        expect(sub.servings, 'MAKES ABOUT 5 CUPS');
        expect(_norm(_rice), isNot(endsWith(' $item')));
        expect(_sharedTail(item, _norm(_rice)), 2);
        expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
        expect(isSubRecipeReference(line.raw), isFalse);
        expect(yieldNamesOwnSection(line, item, sub), isTrue);
        expect(namesOwnSection(recipe, line), isTrue);
        expect(isReferenceIn(recipe, line), isTrue);
      });

      test('the converses on their real lines: the yield guard and the '
          'two-word floor each keep a shared tail off', () {
        for (final (file, i, title, raw, words, share) in const [
          // Two words shared, but SERVES 4 TO 6 reads no share.
          (
            _friedRice,
            10,
            'Fried Rice with Peas and Bean Sprouts',
            '1 cup bean sprouts',
            2,
            null,
          ),
          // One word ("cream") and half the yield.
          (
            _mousse,
            5,
            'Lemon Whipped Cream',
            '½ cup heavy cream, chilled',
            1,
            0.5,
          ),
        ]) {
          final (recipe, line, sub) = _at(file, i, title);
          final item = referenceItemOf(line);
          expect(line.raw, raw);
          expect(_sharedTail(item, _norm(title)), words, reason: file);
          expect(parseShare(line.raw, line.amounts, sub.servings), share);
          expect(yieldNamesOwnSection(line, item, sub), isFalse, reason: file);
          expect(namesOwnSection(recipe, line), isFalse, reason: file);
        }
        // juicy-grilled-turkey-burgers|4: one word ("sauce") against every
        // one of its sauces.
        final burgers = loadCorpusRecipe(_burgers);
        final soy = nutritionLines(burgers)[4];
        expect(soy.raw, '1 tablespoon soy sauce');
        final sauces = [
          for (final sub in burgers.subsections)
            if (_sharedTail('soy sauce', _norm(sub.title ?? '')) > 0) sub,
        ];
        // Malt Vinegar–Molasses, Chile-Lime and Apricot-Mustard Burger Sauce,
        // each MAKES ABOUT 1 CUP.
        expect(sauces, hasLength(3));
        for (final sub in sauces) {
          expect(_sharedTail('soy sauce', _norm(sub.title!)), 1);
          expect(yieldNamesOwnSection(soy, 'soy sauce', sub), isFalse);
        }
        expect(namesOwnSection(burgers, soy), isFalse);
      });

      test('the two-word floor: a ONE-word shared tail is refused even at the '
          'full yield — STATED synthesized (no corpus line reaches it: every '
          'one-word pair reads a share other than 1.0): grilled-beef-satay '
          '(0621)\'s real line |2 "3 tablespoons fish sauce" against its own '
          '"Peanut Sauce" with the yield printed "MAKES 3 TABLESPOONS" (the '
          'corpus prints MAKES ABOUT 1½ CUPS) — it stays fish sauce', () {
        final (recipe, line, real) = _at(_satay, 2, 'Peanut Sauce');
        expect(line.raw, '3 tablespoons fish sauce');
        expect(real.servings, 'MAKES ABOUT 1½ CUPS');
        final sub = real.copyWith(servings: 'MAKES 3 TABLESPOONS');
        final rewritten = recipe.copyWith(
          subsections: [
            for (final s in recipe.subsections)
              s.title == 'Peanut Sauce' ? sub : s,
          ],
        );
        expect(_sharedTail('fish sauce', 'peanut sauce'), 1);
        // Not vacuous: the yield guard alone would let it through.
        expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
        expect(yieldNamesOwnSection(line, 'fish sauce', sub), isFalse);
        expect(namesOwnSection(rewritten, line), isFalse);
        expect(isReferenceIn(rewritten, line), isFalse);
      });

      test(
        'the pair is whole words at the END of the title and may be the whole '
        "title — STATED synthesized retitlings of fried-rice (0521)'s own "
        'section (the corpus title is "Basic White Rice"; no corpus title is '
        'the two words alone, fuses them or holds them mid-title): "White '
        'Rice" names it (the title IS the two words); "Basic Offwhite Rice" '
        'does not ("offwhite" is not the word "white"); "Basic White Rice '
        'Pilaf" does not (the two words are not its tail)',
        () {
          final (recipe, line, real) = _at(_friedRice, 9, _rice);
          for (final (title, names) in const [
            ('White Rice', true),
            ('Basic Offwhite Rice', false),
            // closer1 (verify1 D3): the pair after a word but not at the end
            // (a title that STARTS with it would not tell `endsWith` from
            // `contains`).
            ('Basic White Rice Pilaf', false),
          ]) {
            final sub = real.copyWith(title: title);
            final rewritten = recipe.copyWith(
              subsections: [
                for (final s in recipe.subsections) s.title == _rice ? sub : s,
              ],
            );
            expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
            expect(
              yieldNamesOwnSection(line, 'cold cooked white rice', sub),
              names,
              reason: title,
            );
            expect(namesOwnSection(rewritten, line), names, reason: title);
          }
        },
      );

      test('an item of exactly THREE words routes on its last two — STATED '
          'synthesized (verify1 D2; no corpus line reaches it: the reach '
          "below is one line, a four-word item): fried-rice (0521)'s real "
          'line |9 and its real "Basic White Rice" (MAKES ABOUT 5 CUPS) read '
          'with the item "cooked white rice" in place of the line\'s "cold '
          'cooked white rice" — it names the section', () {
        final (_, line, sub) = _at(_friedRice, 9, _rice);
        const item = 'cooked white rice';
        expect(item.split(' '), hasLength(3));
        // Not vacuous: M76's whole-item tail alone does not reach it.
        expect(_norm(_rice), isNot(endsWith(' $item')));
        expect(_sharedTail(item, _norm(_rice)), 2);
        expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
        expect(yieldNamesOwnSection(line, item, sub), isTrue);
      });

      test('the corpus reach: of every main line × own-section pair sharing '
          "two or more trailing words that M76's whole-item tail does not "
          'reach, exactly fried-rice|9 names its section; no one-word pair '
          'reads the full yield (so only the synthesized case above pins the '
          'floor)', () {
        final hits = <String>[];
        final oneWordAtYield = <String>[];
        var twoWordPairs = 0;
        for (final file
            in Directory(corpusRecipesDir)
                .listSync()
                .map((f) => f.uri.pathSegments.last)
                .where((f) => f.endsWith('.yaml'))) {
          final recipe = loadCorpusRecipe(file);
          for (final (i, line) in nutritionLines(recipe).indexed) {
            final item = referenceItemOf(line);
            if (item.isEmpty || line.amounts.isEmpty) {
              continue;
            }
            for (final sub in recipe.subsections) {
              final title = _norm(sub.title ?? '');
              final k = _sharedTail(item, title);
              final key = '${recipe.slug}|$i → ${sub.title}';
              if (k == 1 &&
                  !title.endsWith(' $item') &&
                  !isSubRecipeReference(line.raw) &&
                  parseShare(line.raw, line.amounts, sub.servings) == 1.0) {
                oneWordAtYield.add(key);
              }
              if (k < 2 || title.endsWith(' $item')) {
                continue;
              }
              twoWordPairs++;
              if (yieldNamesOwnSection(line, item, sub)) {
                hits.add(key);
              }
            }
          }
        }
        expect(hits, ['fried-rice-with-shrimp-pork-and-shiitakes|9 → $_rice']);
        expect(oneWordAtYield, isEmpty);
        // Not vacuous: 49 such pairs (marked lines, prose sections, a two-word
        // item equal to its title, and the yields no line reads at 1.0).
        expect(twoWordPairs, 49);
      });
    },
  );

  group('matcher v91 (batch M87) — whole recipes', skip: skipIfNoCorpus, () {
    // One database: red-beans-and-rice|14 "Basic White Rice (this page)"
    // routes to the same section (its first parent, rule WB), so the
    // section's parents are read with both hosts computed.
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      final dir = Directory.systemTemp.createTempSync('salt-v91-');
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
      for (final file in [_friedRice, _beans, _mousse, _burgers]) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    String batchKcal(String id) =>
        ((jsonDecode(db.nutritionFor(id)!.totalsJson!) as Map)['energy'] as num)
            .toStringAsFixed(2);

    IngredientMatchRow rowAt(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    test('P1: fried-rice|9 is a `recipe` row on its own "Basic White Rice" '
        'at 1.000000 — 402.20 g, 1,486.68 kcal (v90: 2708408 790.00 g, '
        '1,019.10) — and the recipe reads 697.16 a serving (v90 580.26)', () {
      final recipe = recipes[_friedRice]!;
      final key = sectionKeyOf(recipe.id, _rice);
      final line = nutritionLines(recipe)[9];
      final row = rowAt(recipe.id, 9);
      expect(
        (
          row.fdcId,
          row.childRecipeId,
          row.childShare?.toStringAsFixed(6),
          row.grams?.toStringAsFixed(2),
          row.gramSource,
          row.status,
          row.hold,
        ),
        (null, key, '1.000000', '402.20', 'recipe', 'auto', null),
      );
      expect(batchKcal(key), '1486.68');
      expect(
        gramBasisFor(db, line, row, recipe: recipe),
        'from the recipe Basic White Rice: 402 g, 1,487 kcal',
      );
      final n = db.nutritionFor(recipe.id)!;
      expect(
        (n.status, n.caloriesPerServing?.toStringAsFixed(2)),
        ('complete', '697.16'),
      );
    });

    test("the section's parents: fried-rice joins red-beans-and-rice — each "
        'host routes a row to it and makes it a child', () {
      final key = sectionKeyOf(recipes[_friedRice]!.id, _rice);
      expect(
        [
          for (final file in [_beans, _friedRice])
            if (db
                .ingredientMatchesFor(recipes[file]!.id)
                .any((m) => m.childRecipeId == key))
              recipes[file]!.slug,
        ],
        ['red-beans-and-rice', 'fried-rice-with-shrimp-pork-and-shiitakes'],
      );
      for (final file in [_beans, _friedRice]) {
        expect(
          routedSectionKeysOf(db, recipes[file]!, ResolverMemo(db)),
          contains(key),
          reason: file,
        );
      }
    });

    test("the converse rows stay their foods (the v90 replay's): "
        'fried-rice|10 bean sprouts, fresh-strawberry-mousse|5 heavy cream, '
        'juicy-grilled-turkey-burgers|4 soy sauce', () {
      for (final (file, i, fdcId, grams) in const [
        (_friedRice, 10, 2709768, '90.00'),
        (_mousse, 5, 2346386, '119.48'),
        (_burgers, 4, 2707442, '16.00'),
      ]) {
        final row = rowAt(recipes[file]!.id, i);
        expect(
          (row.fdcId, row.childRecipeId, row.grams?.toStringAsFixed(2)),
          (fdcId, null, grams),
          reason: '$file|$i',
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
              m.childRecipeId,
              m.childShare,
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
