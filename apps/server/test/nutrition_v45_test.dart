// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v45, part 1 (option A spent — the owner's live step on
// 2026-10-06, snapshot 20 = snapshot 19 + 11 searches + 9 details): each
// answer whose check (prep43 p2_spend §4) names a record the ranker does not
// put on top reads the line's OWN cached answer under that record's words
// (rank-as): "1 cup Coca-Cola" on 2710541 "Soft drink, cola", "¼ cup
// dairy-free sour cream" on 2705617 "Sour cream, imitation" (flagged), the
// coconut-milk yogurt on 2707569 (weighed by its own cup — 'coconut milk
// yogurt' is not the dairy 'yogurt' key's food); the three seed records
// that publish no volume portion read their siblings' cups (volumeSiblings).
// The answers that passed their checks land as they are; the six that
// awaited the owner's part-2 rulings moved in v46 and are pinned there
// (test/nutrition_v46_test.dart). Every value is the v45 replay's row (rp43
// on snapshot 20).
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider;
// entries added --from-db from snapshot 20), never the network. NO fixture
// records 171884 (the Minute Maid lemonade the brand word leads) or 173444
// (the dairy fat-free sour cream): a regression that asks either throws
// UnrecordedAnswer.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _ham = '0249-roast-fresh-ham.yaml';
const _baja = '1093-vegan-baja-style-cauliflower-tacos.yaml';
const _buffalo = '0672-buffalo-cauliflower-bites.yaml';
const _porkChops = '0597-easy-grilled-boneless-pork-chops.yaml';
const _broccoli = '1096-skillet-roasted-broccoli.yaml';
const _salmon = '0263-oven-roasted-salmon.yaml';
const _handPies = '1166-fruit-hand-pies.yaml';
const _sesameSalmon = '0261-sesame-crusted-salmon-with-lemon-and-ginger.yaml';
const _multigrain = '0809-multigrain-bread.yaml';
const _watermelon = '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml';

typedef _Pin = (
  String file,
  int? section,
  int position,
  String raw,
  int? fdcId,
  String description,
  String confidence,
  String? grams,
  String? gramSource,
  String status,
  String? basis,
);

void main() {
  group('matcher v45 (option A, part 1)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v45-');
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

    var alones = 0;

    /// [file]'s line at [position] — of its section number [section], else
    /// a main line — ALONE in its recipe (a section line under the
    /// section's own key), computed on the fixtures; its one row, the
    /// recipe it was computed in, the line and what the compute returned
    /// (null, or the provider failure a withheld answer leaves).
    Future<(IngredientMatchRow, Recipe, IngredientLine, Object?)> at(
      String file,
      int? section,
      int position,
    ) async {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      final host = db.recipeByIdOrSlug(recipe.id)!.recipe;
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
      final failed = await matchAndCompute(db, provider, one);
      return (db.ingredientMatchesFor(one.id).single, one, line, failed);
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
            status,
            basis,
          )
          in pins) {
        provider = FixtureProvider();
        final (row, one, line, failed) = await at(file, section, position);
        final reason = '$file|$section|$position';
        expect(failed, isNull, reason: reason);
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
          (fdcId, description, confidence, grams, gramSource, status, null),
          reason: reason,
        );
        expect(gramBasisFor(db, line, row, recipe: one), basis, reason: reason);
      }
    }

    test('R1–R4: each line lands the record its check names — record, '
        'grams, status, basis (computed alone; nothing asks 171884 / '
        '173444)', () async {
      await pinAll([
        // R1 (A6): the cola soft drink, by its fl-oz portions (no cup).
        (
          _ham,
          2,
          0,
          '1 cup Coca-Cola',
          2710541,
          'Soft drink, cola',
          '0.990000',
          '248.00',
          'portion',
          'auto',
          '1 cup · USDA portion',
        ),
        // R2 (A5): imitation sour cream, flagged.
        (
          _baja,
          0,
          1,
          '¼ cup dairy-free sour cream',
          2705617,
          'Sour cream, imitation',
          '0.990000',
          '60.00',
          'portion',
          'auto',
          '1/4 cup · USDA portion · approximation (counted as Sour cream, imitation)',
        ),
        // R3 (A1): the coconut-milk yogurt, by its own '1 cup' 226 g.
        (
          _buffalo,
          0,
          1,
          '2 tablespoons unsweetened plain coconut milk yogurt',
          2707569,
          'Yogurt, coconut milk',
          '0.990000',
          '28.25',
          'portion',
          'auto',
          '2 tablespoon · USDA portion',
        ),
        // R4: the three seed records read their siblings' cups.
        (
          _porkChops,
          2,
          6,
          '¼ cup pepitas, toasted',
          2515380,
          'Seeds, pumpkin seeds (pepitas), raw',
          '0.920000',
          '29.50',
          'portion',
          'auto',
          '1/4 cup · USDA portion of "Seeds, pumpkin and squash seed kernels, roasted, with salt added"',
        ),
        (
          _broccoli,
          0,
          0,
          '2 tablespoons toasted sesame seeds, divided',
          170151,
          'Seeds, sesame seeds, whole, roasted and toasted',
          '0.880000',
          '16.00',
          'portion',
          'auto',
          '2 tablespoon · USDA portion of "Sesame seeds"',
        ),
        (
          _broccoli,
          1,
          0,
          '2 tablespoons raw sunflower seeds, toasted',
          2515381,
          'Seeds, sunflower seed, kernel, raw',
          '1.000000',
          '16.75',
          'portion',
          'auto',
          '2 tablespoon · USDA portion of "Seeds, sunflower seed kernels, toasted, without salt"',
        ),
      ]);
      expect(volumeSiblings[2515380], 169415);
      expect(volumeSiblings[2515381], 170154);
      expect(volumeSiblings[170151], 2707586);
      expect(approximationRecords['dairy-free sour cream'], 2705617);
      for (final (item, fdcId, flagged) in [
        ('coca-cola', 2710541, false),
        ('dairy-free sour cream', 2705617, true),
        ('unsweetened plain coconut milk yogurt', 2707569, false),
      ]) {
        expect(
          isApproximation(
            item: item,
            raw: item,
            fdcId: fdcId,
            description: null,
          ),
          flagged,
          reason: item,
        );
      }
    });

    test("the rank-as reads: the line's own cached answer under the "
        "record's words, the record first ≥ the gate — where the line's "
        'own words put the record the check rejects', () async {
      for (final (item, words, fdcId, ownTop) in [
        ('coca-cola', 'soft drink cola', 2710541, 171884),
        ('dairy-free sour cream', 'sour cream imitation', 2705617, 173444),
        (
          'unsweetened plain coconut milk yogurt',
          'yogurt coconut milk',
          2707569,
          2259793,
        ),
      ]) {
        expect(
          lineSearchFor(db, item, item),
          (query: words, answer: item),
          reason: item,
        );
        final answer = await provider.search(item);
        final top = rankCandidates(words, answer).first;
        expect(
          (top.candidate.fdcId, top.confidence.toStringAsFixed(6)),
          (fdcId, '0.990000'),
          reason: item,
        );
        expect(
          rankCandidates(item, answer).first.candidate.fdcId,
          ownTop,
          reason: item,
        );
      }
    });

    test('the rank-as keys are the exact items: a diet cola, a cola syrup or '
        'a dairy sour cream line (synthesized negative paths — the corpus '
        'prints none) never reads them', () {
      for (final item in [
        'diet coca-cola',
        'coca-cola syrup',
        'cola',
        'sour cream',
        'light sour cream',
        'coconut milk',
        'plain yogurt',
      ]) {
        expect(
          rankAsFor(item)?.query,
          isNot(
            anyOf(
              'soft drink cola',
              'sour cream imitation',
              'yogurt coconut milk',
            ),
          ),
          reason: item,
        );
      }
    });

    test('the reach: the corpus prints ONE line of each rank-as item '
        '(main lines and every section)', () {
      final counts = <String, List<String>>{};
      const items = {
        'coca-cola',
        'dairy-free sour cream',
        'unsweetened plain coconut milk yogurt',
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
            if (items.contains(item)) {
              (counts[item] ??= []).add('${recipe.slug}|$where|${line.raw}');
            }
          }
        }
      }
      expect(counts, {
        'coca-cola': [
          'roast-fresh-ham|Coca-Cola Glaze with Lime and Jalapeño|1 cup Coca-Cola',
        ],
        'dairy-free sour cream': [
          'vegan-baja-style-cauliflower-tacos|Vegan Cilantro Sauce|¼ cup dairy-free sour cream',
        ],
        'unsweetened plain coconut milk yogurt': [
          'buffalo-cauliflower-bites|Ranch Dressing|2 tablespoons unsweetened plain coconut milk yogurt',
        ],
      });
    });

    test(
      'the answers that passed their checks land as they are (no rule)',
      () async {
        await pinAll([
          // A7: 100 % pineapple juice, its cup.
          (
            _ham,
            1,
            0,
            '1 cup pineapple juice',
            2709329,
            'Pineapple juice, 100%',
            '0.923333',
            '248.00',
            'portion',
            'auto',
            '1 cup · USDA portion',
          ),
          // A8: the trailing cup paren is the prepared amount.
          (
            _salmon,
            0,
            0,
            '4 tangerines, rind and pith removed and segments cut into ½-inch pieces (about 1 cup)',
            2709175,
            'Tangerine, raw',
            '0.910000',
            '195.00',
            'portion',
            'auto',
            '1 cup · USDA portion',
          ),
          // A11: frozen cherries, weighed.
          (
            _handPies,
            0,
            0,
            '10 ounces frozen cherries, thawed, juice reserved, cut into approximate ½-inch pieces',
            2709233,
            'Cherries, frozen',
            '0.990000',
            '283.50',
            'weight',
            'auto',
            'from 10 ounce',
          ),
          // The vegan mayonnaise reads (v44 S5) on 2710205's portions.
          (
            _buffalo,
            0,
            0,
            '½ cup vegan mayonnaise',
            2710205,
            'Vegan mayonnaise',
            '0.990000',
            '112.50',
            'portion',
            'auto',
            '1/2 cup · USDA portion',
          ),
          (
            _baja,
            0,
            0,
            '¼ cup vegan mayonnaise',
            2710205,
            'Vegan mayonnaise',
            '0.990000',
            '56.25',
            'portion',
            'auto',
            '1/4 cup · USDA portion',
          ),
        ]);
      },
    );

    test(
      "the main library's seed lines keep their own records' portions "
      '(the siblings are keyed on the three portion-less records only)',
      () async {
        await pinAll([
          (
            _sesameSalmon,
            null,
            1,
            '¾ cup sesame seeds',
            2707586,
            'Sesame seeds',
            '0.990000',
            '96.00',
            'portion',
            'auto',
            '3/4 cup · USDA portion',
          ),
          (
            _multigrain,
            null,
            8,
            '¾ cup unsalted pumpkin seeds or sunflower seeds',
            170154,
            'Seeds, sunflower seed kernels, toasted, without salt',
            '0.643333',
            '100.50',
            'portion',
            'auto',
            '3/4 cup · USDA portion',
          ),
          (
            _watermelon,
            null,
            8,
            '5 tablespoons chopped roasted, salted pepitas, divided',
            169415,
            'Seeds, pumpkin and squash seed kernels, roasted, with salt added',
            '0.700000',
            '36.88',
            'portion',
            'auto',
            '5 tablespoon · USDA portion',
          ),
        ]);
        for (final record in [169415, 170154, 2707586]) {
          expect(volumeSiblings[record], isNull, reason: '$record');
        }
      },
    );
  });
}
