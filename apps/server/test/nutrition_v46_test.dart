// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v46, option A part 2 (the owner's 2026-10-07 rulings on the six
// answers that failed their checks; zero requests): mascarpone counts on
// heavy cream 2346386, potato starch on cornstarch 169698, brown rice flour
// on white rice flour 790214 — flagged rank-as reads of cached answers; the
// gluten-free flour blend completes and its two parents lose their partial
// flag — nutritional yeast stays on 2710005 "Yeast", flagged; frozen
// cranberries and frozen pineapple chunks are rewritten to the plain
// fruit's cached answer (171722, 2346398, unflagged). Every value is the
// v46 replay's row (rp43 on snapshot 20).
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider;
// entries added --from-db from snapshot 20), never the network. NO fixture
// records "brown rice flour" (withheld; the rank-as read never asks it):
// a regression that searches it throws UnrecordedAnswer.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _roulade = '0899-bittersweet-chocolate-roulade.yaml';
const _gfPizza = '0393-the-best-gluten-free-pizza.yaml';
const _gfCookies = '0819-gluten-free-chocolate-chip-cookies.yaml';
const _broccoli = '1096-skillet-roasted-broccoli.yaml';
const _pavlova = '0940-pavlova-with-fruit-and-whipped-cream.yaml';
const _handPies = '1166-fruit-hand-pies.yaml';

const _tiramisu = '0910-tiramisu.yaml';
const _summerTart = '0996-the-best-summer-fruit-tart.yaml';
const _cranSauce = '0177-classic-cranberry-sauce.yaml';
const _chutney =
    '0178-cranberry-chutney-with-apples-and-crystallized-ginger.yaml';
const _jellied = '1181-jellied-cranberry-sauce.yaml';
const _muffins = '0765-cranberry-pecan-muffins.yaml';
const _curdTart = '1116-cranberry-curd-tart-with-almond-crust.yaml';
const _fishTacos = '0649-grilled-fish-tacos.yaml';

const _blend = 'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend';

// The keys test's inputs. SYNTHESIZED — stated negative paths, near-misses
// of the ruled keys that no corpus line prints as an item (the reach test
// proves it):
const _keysSynthesized = [
  'sweet rice flour',
  'rice flour',
  'fresh yeast',
  'yeast',
  'canned pineapple chunks',
  'mascarpone cream',
];
// REAL — items the corpus prints (the reach test proves each one), whose
// real lines the replay leaves byte-equal or pins below:
const _keysReal = [
  'tapioca starch',
  'cornstarch',
  'white rice flour',
  'heavy cream',
  'dried cranberries',
  'cranberries',
  'pineapple',
  'espresso-mascarpone cream',
];
// M2's leftAlternative probe — synthesized; no corpus item reads it.
const _m2Probe = 'mascarpone or italian basil leaves';

typedef _Pin = (
  String file,
  int? section,
  int position,
  String raw,
  int fdcId,
  String description,
  String confidence,
  String grams,
  String gramSource,
  String basis,
  bool flagged,
);

void main() {
  group('matcher v46 (option A, part 2)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v46-');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider();
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Recipe stored(String file) {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    var alones = 0;

    /// [file]'s line at [position] — of its section number [section], else
    /// a main line — ALONE in its recipe (a section line under the
    /// section's own key), computed on the fixtures; its one row, the
    /// recipe it was computed in and the line.
    Future<(IngredientMatchRow, Recipe, IngredientLine)> at(
      String file,
      int? section,
      int position,
    ) async {
      final host = stored(file);
      final from = section == null
          ? host
          : sectionOf(
              host,
              sectionKeyOf(host.id, host.subsections[section].title ?? ''),
            )!;
      final line = nutritionLines(from)[position];
      final id = 'r${alones++}';
      final one = section == null
          ? host.copyWith(
              id: id,
              slug: id,
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            )
          : from.copyWith(
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            );
      if (section == null) {
        db.upsertRecipe(one, sourceSlug: _source, contentHash: id);
      }
      expect(await matchAndCompute(db, provider, one), isNull);
      return (db.ingredientMatchesFor(one.id).single, one, line);
    }

    Future<void> pinAll(List<_Pin> pins) async {
      for (final (
            file,
            section,
            position,
            raw,
            fdcId,
            description,
            confidence,
            grams,
            gramSource,
            basis,
            flagged,
          )
          in pins) {
        final (row, one, line) = await at(file, section, position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
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
          (fdcId, description, confidence, grams, gramSource, 'auto', null),
          reason: reason,
        );
        expect(gramBasisFor(db, line, row, recipe: one), basis, reason: reason);
        expect(
          isApproximation(
            item: normalizeItem(lineItemOf(line)),
            raw: raw,
            fdcId: row.fdcId,
            description: row.description,
          ),
          flagged,
          reason: reason,
        );
      }
    }

    test('R1–R6: each line lands the ruled record — record, confidence, '
        'grams, basis; flagged on 1–4, unflagged on 5–6 (computed alone; '
        'nothing asks "brown rice flour")', () async {
      await pinAll([
        // R1: mascarpone on heavy cream, by the printed weights.
        (
          _roulade,
          0,
          3,
          '16½ ounces mascarpone cheese (generous 2 cups)',
          2346386,
          'Cream, heavy',
          '1.000000',
          '467.77',
          'weight',
          'from 16 1/2 ounce · approximation (counted as Cream, heavy)',
          true,
        ),
        (
          _tiramisu,
          null,
          6,
          '1½ pounds mascarpone (generous 3 cups)',
          2346386,
          'Cream, heavy',
          '1.000000',
          '680.39',
          'weight',
          'from 1 1/2 pound · approximation (counted as Cream, heavy)',
          true,
        ),
        (
          _summerTart,
          null,
          9,
          '6 ounces (¾ cup) mascarpone, room temperature',
          2346386,
          'Cream, heavy',
          '1.000000',
          '170.10',
          'weight',
          'from 6 ounce · approximation (counted as Cream, heavy)',
          true,
        ),
        // R2: potato starch on cornstarch.
        (
          _gfPizza,
          0,
          2,
          '7 ounces (1⅓ cups) potato starch',
          169698,
          'Cornstarch',
          '1.000000',
          '198.45',
          'weight',
          'from 7 ounce · approximation (counted as Cornstarch)',
          true,
        ),
        // R3: brown rice flour on white rice flour.
        (
          _gfPizza,
          0,
          1,
          '7½ ounces (1⅔ cups) brown rice flour',
          790214,
          'Flour, rice, white, unenriched',
          '1.000000',
          '212.62',
          'weight',
          'from 7 1/2 ounce · approximation (counted as Flour, rice, white, unenriched)',
          true,
        ),
        // R4: nutritional yeast — record, confidence and grams unchanged.
        (
          _broccoli,
          1,
          1,
          '1 tablespoon nutritional yeast',
          2710005,
          'Yeast',
          '0.565000',
          '12.00',
          'portion',
          '1 tablespoon · USDA portion · approximation (counted as Yeast)',
          true,
        ),
        // R5: frozen cranberries on the raw fruit.
        (
          _pavlova,
          0,
          1,
          '6 ounces (1½ cups) frozen cranberries',
          171722,
          'Cranberries, raw',
          '0.920000',
          '170.10',
          'weight',
          'from 6 ounce',
          false,
        ),
        // R6: frozen pineapple chunks on the raw fruit.
        (
          _handPies,
          2,
          0,
          '10 ounces frozen pineapple chunks, thawed, juice reserved, cut into approximate ½-inch pieces',
          2346398,
          'Pineapple, raw',
          '0.970000',
          '283.50',
          'weight',
          'from 10 ounce',
          false,
        ),
      ]);
      expect(
        {
          for (final item in [
            'mascarpone cheese',
            'mascarpone',
            'potato starch',
            'brown rice flour',
            'nutritional yeast',
            'frozen cranberries',
            'frozen pineapple chunks',
          ])
            item: approximationRecords[item],
        },
        {
          'mascarpone cheese': 2346386,
          'mascarpone': 2346386,
          'potato starch': 169698,
          'brown rice flour': 790214,
          'nutritional yeast': 2710005,
          'frozen cranberries': null,
          'frozen pineapple chunks': null,
        },
      );
    });

    test(
      "the reads: a rank-as item reads the stand-in's cached answer, a "
      "rewritten one the plain fruit's — the record first ≥ the gate, "
      "where the line's own answer put the record its check rejects",
      () async {
        // The mechanism each ruling names (the brief; API.md): rank-as for
        // rulings 1–3 (the item's own search key kept), the record left as
        // it is for 4, a REWRITE of the search for 5–6. Read alone, the
        // line's search below is the same under either mechanism, but the
        // admin search (searchCandidates reads searchQueryFor) and
        // leftAlternative's food nouns (the rewrite table) do not, so a swap
        // would move them.
        expect(
          {
            for (final k in [
              'mascarpone cheese',
              'mascarpone',
              'potato starch',
              'brown rice flour',
              'nutritional yeast',
              'frozen cranberries',
              'frozen pineapple chunks',
            ])
              k: (searchQueryFor(k), rankAsFor(k)),
          },
          {
            'mascarpone cheese': (
              'mascarpone cheese',
              (query: 'cream heavy', answer: 'heavy cream'),
            ),
            'mascarpone': (
              'mascarpone',
              (query: 'cream heavy', answer: 'heavy cream'),
            ),
            'potato starch': (
              'potato starch',
              (query: 'cornstarch', answer: 'cornstarch'),
            ),
            'brown rice flour': (
              'brown rice flour',
              (query: 'white rice flour', answer: 'white rice flour'),
            ),
            'nutritional yeast': ('nutritional yeast', null),
            'frozen cranberries': ('cranberries', null),
            'frozen pineapple chunks': ('pineapple', null),
          },
        );
        for (final (item, key, query, answer, fdcId, top, ownTop) in [
          (
            'mascarpone cheese',
            'mascarpone cheese',
            'cream heavy',
            'heavy cream',
            2346386,
            '1.000000',
            (2705720, '0.465000'),
          ),
          (
            'mascarpone',
            'mascarpone',
            'cream heavy',
            'heavy cream',
            2346386,
            '1.000000',
            null,
          ),
          (
            'potato starch',
            'potato starch',
            'cornstarch',
            'cornstarch',
            169698,
            '1.000000',
            (174099, '0.256364'),
          ),
          (
            'brown rice flour',
            'brown rice flour',
            'white rice flour',
            'white rice flour',
            790214,
            '1.000000',
            null,
          ),
          (
            'frozen cranberries',
            'frozen cranberry',
            'cranberries',
            'cranberries',
            171722,
            '0.920000',
            (173653, '0.000000'),
          ),
          (
            'frozen pineapple chunks',
            'frozen pineapple chunk',
            'pineapple',
            'pineapple',
            2346398,
            '0.970000',
            (169946, '0.890000'),
          ),
        ]) {
          expect(
            lineSearchFor(db, item, key),
            (query: query, answer: answer),
            reason: item,
          );
          final ranked = rankCandidates(query, await provider.search(answer));
          expect(
            (
              ranked.first.candidate.fdcId,
              ranked.first.confidence.toStringAsFixed(6),
            ),
            (fdcId, top),
            reason: item,
          );
          expect(belowConfidenceGate(ranked.first.confidence), isFalse);
          if (ownTop != null) {
            final own = rankCandidates(item, await provider.search(item)).first;
            expect(
              (own.candidate.fdcId, own.confidence.toStringAsFixed(6)),
              ownTop,
              reason: item,
            );
          }
        }
        // Why the words: under the record's own words white rice flour ties
        // 169714 at 1.0; under "pineapple raw" FNDDS 2709260 ties the
        // Foundation 2346398 and is listed first; under the line's own words
        // the 'pineapple' answer tops the sweetened chunks the rewrite leaves.
        final rice = rankCandidates(
          'flour rice white unenriched',
          await provider.search('white rice flour'),
        );
        expect(
          [
            for (final r in rice.take(2))
              (r.candidate.fdcId, r.confidence.toStringAsFixed(6)),
          ],
          [(790214, '1.000000'), (169714, '1.000000')],
        );
        final pineapple = await provider.search('pineapple');
        expect(
          rankCandidates('pineapple raw', pineapple).first.candidate.fdcId,
          2709260,
        );
        expect(
          rankCandidates(
            'frozen pineapple chunks',
            pineapple,
          ).first.candidate.fdcId,
          169946,
        );
      },
    );

    test('the keys are the exact items: near-misses read none of them '
        '(stated negative paths: sweet rice flour, rice flour, fresh yeast, '
        'yeast, canned pineapple chunks and mascarpone cream are synthesized, '
        'and so is the M2 probe — the corpus prints none of them; tapioca '
        'starch, dried cranberries, cranberries, pineapple and '
        'espresso-mascarpone cream are real items); nor do the stand-ins’ '
        'own foods — cornstarch, white rice flour, heavy cream — so their '
        'flag stays on the ruled item', () {
      for (final item in [..._keysSynthesized, ..._keysReal]) {
        expect(
          rankAsFor(item)?.answer,
          isNot(anyOf('heavy cream', 'cornstarch', 'white rice flour')),
          reason: item,
        );
        expect(
          searchQueryFor(item),
          item == 'cranberries' || item == 'pineapple'
              ? item
              : isNot(anyOf('cranberries', 'pineapple')),
          reason: item,
        );
        expect(
          approximationRecords[item],
          isNot(anyOf(2346386, 169698, 790214, 2710005)),
          reason: item,
        );
      }
      // M2: the two rewrite keys are multi-word; the one-word rank-as key
      // 'mascarpone' is no rewrite key or target, so never a leftAlternative
      // food noun.
      expect(
        queryRewriteKeys,
        isNot(anyElement(isIn(['cranberries', 'pineapple']))),
      );
      expect(searchQueryFor('mascarpone'), 'mascarpone');
      expect(
        leftAlternative(_m2Probe, (_) => false),
        isNull,
      );
    });

    test('the reach: the corpus prints exactly these lines of each key '
        '(main lines and every section); the keys test states its inputs '
        'truly — no synthesized one is a corpus item, every real one is', () {
      final found = <String, List<String>>{};
      final printed = <String>{};
      const items = {
        'mascarpone cheese',
        'mascarpone',
        'potato starch',
        'brown rice flour',
        'nutritional yeast',
        'frozen cranberries',
        'frozen pineapple chunks',
      };
      for (final file in Directory(corpusRecipesDir).listSync()) {
        if (file is! File || !file.path.endsWith('.yaml')) continue;
        final recipe = loadCorpusRecipe(file.uri.pathSegments.last);
        for (final (where, from) in [
          ('', recipe),
          for (final sub in recipe.subsections)
            (sub.title ?? '', sectionRecipeOf(recipe, sub)),
        ]) {
          for (final line in nutritionLines(from)) {
            final item = normalizeItem(lineItemOf(line));
            printed.add(item);
            if (items.contains(item)) {
              (found[item] ??= []).add('${recipe.slug}|$where|${line.raw}');
            }
          }
        }
      }
      for (final list in found.values) {
        list.sort();
      }
      expect(found, {
        'mascarpone cheese': [
          'bittersweet-chocolate-roulade|Espresso-Mascarpone Cream|16½ ounces mascarpone cheese (generous 2 cups)',
        ],
        'mascarpone': [
          'the-best-summer-fruit-tart||6 ounces (¾ cup) mascarpone, room temperature',
          'tiramisu||1½ pounds mascarpone (generous 3 cups)',
        ],
        'potato starch': [
          'the-best-gluten-free-pizza|$_blend|7 ounces (1⅓ cups) potato starch',
        ],
        'brown rice flour': [
          'the-best-gluten-free-pizza|$_blend|7½ ounces (1⅔ cups) brown rice flour',
        ],
        'nutritional yeast': [
          'skillet-roasted-broccoli|Smoky Sunflower Seed Topping|1 tablespoon nutritional yeast',
        ],
        'frozen cranberries': [
          'pavlova-with-fruit-and-whipped-cream|Orange, Cranberry, and Mint Topping|6 ounces (1½ cups) frozen cranberries',
        ],
        'frozen pineapple chunks': [
          'fruit-hand-pies|Pineapple Hand Pie Filling|10 ounces frozen pineapple chunks, thawed, juice reserved, cut into approximate ½-inch pieces',
        ],
      });
      expect(
        [..._keysSynthesized, _m2Probe].where(printed.contains),
        isEmpty,
        reason: 'a stated-synthesized input is a corpus item',
      );
      expect(
        _keysReal.where((item) => !printed.contains(item)),
        isEmpty,
        reason: 'a stated-real input is no corpus item',
      );
    });

    test(
      "the main cranberry and pineapple lines keep their record — 'cranberries' "
      "and 'pineapple' are rewrite TARGETS only, never keys; the stand-ins' "
      'own white rice flour and heavy cream lines read their record unflagged',
      () async {
        await pinAll([
          // R3's stand-in food, the line beside brown rice flour in the blend.
          (
            _gfPizza,
            0,
            0,
            '24 ounces (4½ cups plus ⅓ cup) white rice flour',
            790214,
            'Flour, rice, white, unenriched',
            '1.000000',
            '680.39',
            'weight',
            'from 24 ounce',
            false,
          ),
          // R1's stand-in food, the line beside mascarpone in the cream.
          (
            _roulade,
            0,
            0,
            '½ cup heavy cream',
            2346386,
            'Cream, heavy',
            '1.000000',
            '119.48',
            'density',
            '1/2 cup ≈ 118 mL',
            false,
          ),
          (
            _cranSauce,
            null,
            3,
            '1 (12-ounce) bag cranberries, picked through',
            171722,
            'Cranberries, raw',
            '0.920000',
            '340.19',
            'weight',
            'from the printed weight',
            false,
          ),
          (
            _chutney,
            null,
            7,
            '12 ounces (3 cups) fresh or frozen cranberries',
            171722,
            'Cranberries, raw',
            '0.920000',
            '340.19',
            'weight',
            'from 12 ounce',
            false,
          ),
          (
            _jellied,
            null,
            1,
            '12 ounces (3 cups) fresh or frozen cranberries',
            171722,
            'Cranberries, raw',
            '0.920000',
            '340.19',
            'weight',
            'from 12 ounce',
            false,
          ),
          (
            _muffins,
            null,
            14,
            '2 cups fresh cranberries',
            171722,
            'Cranberries, raw',
            '0.920000',
            '200.00',
            'portion',
            '2 cup · USDA portion',
            false,
          ),
          (
            _curdTart,
            null,
            0,
            '1 pound (4 cups) fresh or frozen cranberries',
            171722,
            'Cranberries, raw',
            '0.920000',
            '453.59',
            'weight',
            'from 1 pound',
            false,
          ),
          (
            _fishTacos,
            null,
            11,
            '1 pineapple, peeled, quartered lengthwise, cored, and each quarter halved lengthwise',
            2346398,
            'Pineapple, raw',
            '0.970000',
            '905.00',
            'piece',
            '1 × 905 g each',
            false,
          ),
        ]);
      },
    );

    test('the parents: the gluten-free flour blend completes (5 of 5) and '
        'both its parents read it whole, unflagged; the roulade reads its '
        'Espresso-Mascarpone Cream complete', () async {
      Future<String> computeSection(String file, String title) async {
        final key = sectionKeyOf(stored(file).id, title);
        expect(
          await matchAndCompute(
            db,
            provider,
            nutritionRecipeOf(db, key)!.recipe,
          ),
          isNull,
        );
        return key;
      }

      final blend = await computeSection(_gfPizza, _blend);
      final cream = await computeSection(_roulade, 'Espresso-Mascarpone Cream');
      for (final (key, lines, grams) in [
        (blend, 5, 1197.8),
        (cream, 4, 636.7),
      ]) {
        final n = db.nutritionFor(key)!;
        expect(
          (n.status, n.matchedCount, n.totalCount, n.totalGrams),
          ('complete', lines, lines, grams),
          reason: key,
        );
      }
      for (final (file, position, child, share, grams, basis) in [
        (
          _gfPizza,
          0,
          blend,
          '0.380952',
          '456.30',
          'from the recipe $_blend: 456 g, 1,655 kcal',
        ),
        (
          _gfCookies,
          0,
          blend,
          '0.190476',
          '228.15',
          'from the recipe $_blend: 228 g, 827 kcal',
        ),
        (
          _roulade,
          10,
          cream,
          '1.000000',
          '636.70',
          'from the recipe Espresso-Mascarpone Cream: 637 g, 2,207 kcal',
        ),
      ]) {
        final recipe = stored(file);
        final line = nutritionLines(recipe)[position];
        final memo = ResolverMemo(db);
        final row = referenceRowFor(db, recipe, position, line, memo);
        final reason = '$file|$position';
        expect(
          (
            row.childRecipeId,
            row.childShare?.toStringAsFixed(6),
            row.grams?.toStringAsFixed(2),
            row.hold,
          ),
          (child, share, grams, null),
          reason: reason,
        );
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
        expect(
          compositeFlagOf(db, recipe, line, row, memo),
          isNull,
          reason: reason,
        );
      }
    });
  });
}
