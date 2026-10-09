// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v31: the CP10 rulings (2026-10-03). Q6: piece figures FDC does
/// not publish — ginger and citrus zest strips by their printed length,
/// the dried chipotle, whole spices, lemongrass, lasagna sheets and a
/// scallion bunch, each flagged with its source; star anise as anise seed.
/// Every row is a real corpus line at the record, grams, bucket and basis
/// the cache-only replay of snapshot 13 derives at v31; the answers are
/// recorded from snapshot 13 (tool/record_fdc_fixtures.dart --from-db),
/// never live.
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v31');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  // One line alone, computed on the recorded answers in a fresh database.
  Future<(SaltDatabase, IngredientMatchRow)> computeLine(
    IngredientLine line,
  ) async {
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
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
    return (db, db.ingredientMatchesFor('r').single);
  }

  // [stored]: the corpus line as the importer stores it (its amounts differ
  // from a re-parse of its raw: "1 (½-inch) piece ginger" is stored as a
  // bare count) — those rows need the corpus.
  Future<void> expectRows(
    List<(String, int, String, int?, String?, String, String?)> rows, {
    bool stored = false,
  }) async {
    for (final (file, position, raw, fdcId, grams, bucket, basis) in rows) {
      final line = stored
          ? nutritionLines(loadCorpusRecipe(file))[position]
          : lineOf(raw);
      expect(line.raw, raw, reason: file);
      final (db, row) = await computeLine(line);
      expect(row.fdcId, fdcId, reason: raw);
      expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
      expect(
        matchBucketFor(
          status: row.status,
          fdcId: row.fdcId,
          grams: row.grams,
          confidence: row.confidence,
          hold: row.hold,
          gramSource: row.gramSource,
        ).wire,
        bucket,
        reason: raw,
      );
      // RE-PIN (M47 batch, v49 Q6): read on the stored recipe, as the
      // matches GET reads it — a two-part zest row's basis needs the recipe
      // (whether a step strains the zest).
      expect(
        gramBasisFor(db, line, row, recipe: db.recipeByIdOrSlug('r')!.recipe),
        basis,
        reason: raw,
      );
    }
  }

  void expectCorpus(
    List<(String, int, String, int?, String?, String, String?)> rows,
  ) {
    for (final (file, position, raw, _, _, _, _) in rows) {
      final line = nutritionLines(loadCorpusRecipe(file))[position];
      expect(line.raw, raw, reason: file);
      expect(lineOf(raw).amounts, line.amounts, reason: raw);
      expect(
        normalizeItem(lineItemOf(lineOf(raw))),
        normalizeItem(lineItemOf(line)),
        reason: raw,
      );
    }
  }

  group('A (Q6 piece figures)', () {
    test('every ruled line lands on its grams, bucket and flagged basis; the '
        'unruled lines (the mild chile by the inch, the jujubes, the monkfish '
        'strips on a whole orange) and a garlic clove, a volume of '
        'peppercorns and a printed strip volume do not move', () async {
      await expectRows(_rowsA);
    });

    test('every row is a real corpus line at its position', () {
      expectCorpus(_rowsA);
    }, skip: skipIfNoCorpus);

    test('the lines the corpus stores as a bare count ("1 (½-inch) piece '
        'ginger") read the same figure; the monkfish strips, on the whole '
        'orange until v37, count on the peel by the strip', () async {
      await expectRows(_storedRowsA, stored: true);
    }, skip: skipIfNoCorpus);

    test('the per-inch figures read only their own records: each ruled '
        'key on its own record by the inch, and the same corpus line on '
        'another record never (stated exceptions: the monkfish strips '
        're-parsed with their strip unit on the whole orange the stored line '
        'matches; a ginger piece on ground ginger; a lemon strip on the '
        'whole lemon — the matcher gives none of them that record)', () async {
      final monkfish = nutritionLines(
        loadCorpusRecipe('1184-monkfish-tagine.yaml'),
      )[0];
      // The corpus stores a bare count; the re-parse counts strips.
      expect(monkfish.amounts.map((a) => a.unit), [null]);
      expect(lineOf(monkfish.raw).amounts.map((a) => (a.quantity, a.unit)), [
        ('3', 'strip'),
      ]);
      // (raw, its own record, its per-inch basis, another record).
      for (final (raw, own, basis, other) in [
        (
          monkfish.raw,
          169103,
          '3 strip × 2 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
          2709171,
        ),
        (
          '1 (2-inch) piece ginger, peeled, halved, and smashed',
          169231,
          '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
          170926,
        ),
        (
          '2 (2-inch) strips lemon zest',
          167749,
          '2 strip × 2 inch × 0.8 g per inch · approximate (the orange-peel strip figure, extended to lemon)',
          2709168,
        ),
      ]) {
        final parsed = parseIngredientLine(raw);
        Future<GramResolution?> on(int fdcId) async => resolveGrams(
          amounts: parsed.amounts,
          food: await FixtureProvider().food(fdcId),
          normalizedItem: normalizeItem(parsed.item ?? raw),
          raw: raw,
        );
        expect((await on(own))?.basis, basis, reason: raw);
        expect((await on(other))?.basis, isNull, reason: raw);
      }
    }, skip: skipIfNoCorpus);
  });

  group('B (Q7 groups, misc, anchovy paste, chorizo; the crumb coat)', () {
    test(
      'every Q7 line lands on its record, grams, bucket and flagged '
      'basis — the confit duck fat discarded (0 g), the roasting duck '
      'fat counted (76.80 g), "10 cornichons" 32 g not 800 g, the '
      'chili-garlic sauce on sriracha; the light sour cream counted on '
      'its record and Spanish chorizo on the Italian salami since v32',
      () async {
        await expectRows(_rowsB);
      },
    );

    test('every row is a real corpus line at its position', () {
      expectCorpus(_rowsB);
    }, skip: skipIfNoCorpus);

    test(
      'the corpus-stored lines (a re-parse reads another item)',
      () async {
        await expectRows(_storedRowsB, stored: true);
      },
      skip: skipIfNoCorpus,
    );

    test('the rank-as items and their flags are exactly the ruled ones; the '
        'light sour cream and the brioche buns are built since v32', () {
      expect(rankAsKeys, containsAll(_q7Items));
      expect(rankAsKeys, contains('low-fat sour cream'));
      expect(rankAsKeys, contains('brioche buns'));
      expect({
        for (final item in _q7Items)
          if (approximationRecords.containsKey(item))
            item: approximationRecords[item],
      }, _q7Flagged);
    });

    test(
      'the bread of a held breading is held with its flour (B4): the bread a '
      'frying recipe processes into the crumbs of its coat; since v33 a '
      'sauteed or baked breading that leaves an excess too',
      () {
        DiscardedMedium? mediumOf(String file, int position) {
          final recipe = loadCorpusRecipe(file);
          final line = nutritionLines(recipe)[position];
          return discardedMediumOf(
            recipe,
            line,
            normalizeItem(lineItemOf(line)),
          );
        }

        expect(
          mediumOf('0233-pork-schnitzel-breaded-pork-cutlets.yaml', 0),
          DiscardedMedium.coating,
        );
        expect(
          mediumOf('0114-breaded-chicken-cutlets.yaml', 2),
          DiscardedMedium.coating,
        );
        // Each term on its own (0114 edited, a stated exception: no corpus
        // recipe holds a fried breading whose bread it does not crumb): with
        // no step processing the bread, or no dredge sentence setting out
        // the crumbs, the bread is not shown to be the coat's — counted.
        final cutlets = loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml');
        const process =
            'Process the bread in a food processor until evenly '
            'fine-textured, 20 to 30 seconds. ';
        for (final cut in const [
          process,
          'Transfer the crumbs to a pie plate or shallow dish. ',
        ]) {
          final edited = cutlets.copyWith(
            steps: [
              for (final step in cutlets.steps)
                step.copyWith(text: step.text.replaceAll(cut, '')),
            ],
          );
          expect(
            edited.steps.map((s) => s.text).join(),
            isNot(contains(cut)),
            reason: cut,
          );
          final line = nutritionLines(edited)[2];
          expect(
            discardedMediumOf(edited, line, normalizeItem(lineItemOf(line))),
            isNull,
            reason: cut,
          );
        }
        // The frying term on its own (0114 edited, the same stated
        // exception): with its one frying sentence gone ("Discard the oil
        // in the skillet", [_fries]) the recipe sautés. Since v33 (the
        // dredge-reach ruling) its flour stays held by its excess sentence
        // ("dredge each cutlet in the flour, shaking off the excess") and
        // the bread with it; with that sentence gone too, neither is.
        const fryCut =
            'Discard the oil in the skillet and wipe the skillet clean with '
            'paper towels. ';
        const excessCut = ', shaking off the excess';
        Recipe cutting(List<String> cuts) => cutlets.copyWith(
          steps: [
            for (final step in cutlets.steps)
              step.copyWith(
                text: cuts.fold<String>(
                  step.text,
                  (t, cut) => t.replaceAll(cut, ''),
                ),
              ),
          ],
        );
        // RE-PIN (M52 batch, v53, Q24 b): with both gone the cutlets are
        // still browned in the 6 tablespoons of oil heated for them — a
        // shallow fry of a coated food, so both stay held; with the browning
        // gone too (the same stated exception), neither is.
        const brownCut = 'deep golden brown and ';
        for (final (cuts, held) in [
          ([fryCut], DiscardedMedium.coating),
          ([fryCut, excessCut], DiscardedMedium.coating),
          ([fryCut, excessCut, brownCut], null),
        ]) {
          final sauteed = cutting(cuts);
          final sauteedText = sauteed.steps.map((s) => s.text).join();
          for (final cut in cuts) {
            expect(sauteedText, isNot(contains(cut)));
          }
          expect(sauteedText, contains(process));
          expect(sauteedText, contains('Transfer the crumbs to a pie plate'));
          for (final position in const [3, 2]) {
            final line = nutritionLines(sauteed)[position];
            expect(
              discardedMediumOf(sauteed, line, normalizeItem(lineItemOf(line))),
              held,
              reason: 'sauteed 0114 $cuts, line $position',
            );
          }
        }
        // v33 (D2): a baked or sautéed breading that leaves an excess holds
        // its bread with its flour.
        for (final (file, position) in const [
          ('0122-chicken-kiev.yaml', 7),
          ('0206-crunchy-baked-pork-chops.yaml', 2),
          ('0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml', 13),
        ]) {
          expect(
            mediumOf(file, position),
            DiscardedMedium.coating,
            reason: file,
          );
        }
      },
      skip: skipIfNoCorpus,
    );
  });

  group('C (the held-media rulings, named recipes)', () {
    // A whole corpus recipe computed on the recorded answers.
    Future<(Recipe, List<IngredientMatchRow>)> computeRecipe(
      String file, [
      Recipe Function(Recipe)? edit,
    ]) async {
      final db = tempDb()
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
      final corpus = loadCorpusRecipe(file);
      final recipe = edit == null ? corpus : edit(corpus);
      db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h');
      await matchAndCompute(db, FixtureProvider(), recipe);
      return (recipe, db.ingredientMatchesFor(recipe.id));
    }

    test('each ruled line at its grams, hold and note; the eaten coconut oil '
        'of 0672 (its fryer oil zeroed by mass) and the fried ¾ cup of 0042 '
        'do not move', () async {
      for (final (file, position, fdcId, grams, hold, note) in _rowsC) {
        final (recipe, rows) = await computeRecipe(file);
        final row = rows.singleWhere((r) => r.position == position);
        expect(row.fdcId, fdcId, reason: '$file $position');
        expect(row.grams?.toStringAsFixed(2), grams, reason: '$file $position');
        expect(row.hold, hold, reason: '$file $position');
        expect(
          holdNoteOf(recipe, nutritionLines(recipe)[position], hold),
          note,
          reason: '$file $position',
        );
      }
    }, skip: skipIfNoCorpus);

    test('the rules stay on their recipes: the own-sentence frying oil of '
        '0491 stays zeroed though a step says "fry"; a poach whose later step uses '
        'the "remaining liquid" (0488 edited, a stated exception: no corpus '
        'recipe pours one away and uses it) holds nothing', () {
      DiscardedMedium? mediumOf(Recipe recipe, int position) {
        final line = nutritionLines(recipe)[position];
        return discardedMediumOf(
          recipe,
          line,
          normalizeItem(lineItemOf(line)),
        );
      }

      expect(
        mediumOf(
          loadCorpusRecipe('0491-spicy-mexican-shredded-pork-tostadas.yaml'),
          10,
        ),
        DiscardedMedium.fryingOil,
      );
      final enchiladas = loadCorpusRecipe('0488-enchiladas-verdes.yaml');
      final edited = enchiladas.copyWith(
        steps: [
          for (final (i, step) in enchiladas.steps.indexed)
            i == 2
                ? step.copyWith(
                    text: '${step.text} Stir in the remaining liquid.',
                  )
                : step,
        ],
      );
      expect(mediumOf(enchiladas, 4), DiscardedMedium.partialPourAway);
      expect(mediumOf(edited, 4), isNull);
    }, skip: skipIfNoCorpus);

    test('the parts eaten after a pour-away start at the step after it: '
        'the poach step’s own oil is the medium (0488 edited, a stated '
        'exception: its poach writes "Heat 1 teaspoon oil", an amount the '
        'later "remaining 2 teaspoons oil" does not repeat)', () async {
      const poach = 'Heat 2 teaspoons of the oil';
      final (recipe, rows) = await computeRecipe(
        '0488-enchiladas-verdes.yaml',
        (corpus) {
          expect(poach.allMatches(corpus.steps[0].text), hasLength(1));
          expect(
            corpus.steps[1].text,
            contains('the remaining 2 teaspoons oil'),
          );
          return corpus.copyWith(
            steps: [
              for (final (i, step) in corpus.steps.indexed)
                i == 0
                    ? step.copyWith(
                        text: step.text.replaceFirst(
                          poach,
                          'Heat 1 teaspoon oil',
                        ),
                      )
                    : step,
            ],
          );
        },
      );
      final oil = rows.singleWhere((r) => r.position == 0);
      expect(oil.hold, 'partial_pour_away');
      // The eaten part is the 2 teaspoons tossed with the vegetables, not
      // the poach step's teaspoon.
      expect(oil.grams?.toStringAsFixed(2), '9.07');
      expect(
        holdNoteOf(recipe, nutritionLines(recipe)[0], oil.hold),
        '¼ cup liquid; 2 teaspoons oil is used outside the braise, eaten',
      );
    }, skip: skipIfNoCorpus);
  });
}

/// (corpus file, position, raw, fdc id, grams, bucket, basis) — A.
const List<(String, int, String, int?, String?, String, String?)> _rowsA = [
  (
    '0007-alcatra-portuguese-style-beef-stew.yaml',
    3,
    '5 allspice berries',
    171315,
    '0.50',
    'counted',
    '5 × 0.1 g each · approximate (reference figure: a whole allspice berry) · approximation (counted as Spices, allspice, ground)',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    4,
    '1 (4-inch) piece ginger, sliced into thin rounds',
    169231,
    '32.00',
    'counted',
    '1 piece × 4 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    7,
    '6 star anise pods',
    171316,
    '3.00',
    'counted',
    '6 × 0.5 g each · approximate (reference figure: a whole star anise) · approximation (counted as Spices, anise seed)',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    8,
    '6 whole cloves',
    171321,
    '0.60',
    'counted',
    '6 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    1,
    '2 lemongrass stalks, trimmed to bottom 6 inches',
    168573,
    '20.00',
    'counted',
    '2 × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    4,
    '1 (1-inch piece) ginger, peeled and chopped coarse',
    169231,
    '8.00',
    'counted',
    '1 × 1 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0067-skillet-lasagna.yaml',
    8,
    '10 curly-edged lasagna noodles, broken into 2-inch lengths',
    169736,
    '250.00',
    'counted',
    '10 × 25 g each · approximate (Ronzoni: 2 pieces = 50 g dry)',
  ),
  (
    '0129-mahogany-chicken-thighs.yaml',
    7,
    '1 (2-inch) piece ginger, peeled, halved, and smashed',
    169231,
    '16.00',
    'counted',
    '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0141-pollo-en-mole-poblano-chicken-in-puebla-style-mole.yaml',
    1,
    '½ dried chipotle chile, stemmed, seeded, and torn into ½-inch pieces (scant tablespoon)',
    168570,
    '2.30',
    'counted',
    '1/2 × 4.6 g each · approximate (ATK: ½ dried chipotle chile ≈ a scant tablespoon)',
  ),
  (
    '0209-red-winebraised-pork-chops.yaml',
    7,
    '1 (½-inch) piece ginger, peeled and crushed',
    169231,
    '4.00',
    'counted',
    '1 piece × 0.5 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
    5,
    '1 (1-inch) piece ginger, sliced into ½-inch-thick rounds and smashed',
    169231,
    '8.00',
    'counted',
    '1 piece × 1 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
    10,
    '2 (2-inch) strips lemon zest',
    167749,
    '3.20',
    'counted',
    '2 strip × 2 inch × 0.8 g per inch · approximate (the orange-peel strip figure, extended to lemon)',
  ),
  (
    '0268-oven-steamed-fish-with-scallions-and-ginger.yaml',
    1,
    '1 (3-inch) piece ginger, peeled, divided',
    169231,
    '24.00',
    'counted',
    '1 piece × 3 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0285-shrimp-cocktail.yaml',
    3,
    '4 peppercorns',
    170931,
    '0.20',
    'counted',
    '4 × 0.05 g each · approximate (reference figure: a whole peppercorn)',
  ),
  (
    '0285-shrimp-cocktail.yaml',
    4,
    '5 coriander seeds',
    170922,
    '0.05',
    'counted',
    '5 × 0.01 g each · approximate (reference figure: a coriander seed)',
  ),
  (
    '0368-baked-manicotti.yaml',
    14,
    '16 no-boil lasagna noodles',
    169736,
    '272.00',
    'counted',
    '16 × 17 g each · approximate (Barilla: a 9-ounce box of at least 15 sheets; 3 sheets = 51 g)',
  ),
  (
    '0371-simple-cheese-lasagna.yaml',
    19,
    '14 curly-edged lasagna noodles',
    169736,
    '350.00',
    'counted',
    '14 × 25 g each · approximate (Ronzoni: 2 pieces = 50 g dry)',
  ),
  (
    '0372-four-cheese-lasagna.yaml',
    15,
    '15 no-boil lasagna noodles',
    169736,
    '255.00',
    'counted',
    '15 × 17 g each · approximate (Barilla: a 9-ounce box of at least 15 sheets; 3 sheets = 51 g)',
  ),
  (
    '0373-vegetable-lasagna.yaml',
    23,
    '12 no-boil lasagna noodles',
    169736,
    '204.00',
    'counted',
    '12 × 17 g each · approximate (Barilla: a 9-ounce box of at least 15 sheets; 3 sheets = 51 g)',
  ),
  (
    '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
    15,
    '12 no-boil lasagna noodles',
    169736,
    '204.00',
    'counted',
    '12 × 17 g each · approximate (Barilla: a 9-ounce box of at least 15 sheets; 3 sheets = 51 g)',
  ),
  (
    '0376-biang-biang-mian-flat-hand-pulled-noodles-with-chili-oil-vinaigrette.yaml',
    10,
    '1 star anise pod',
    171316,
    '0.50',
    'counted',
    '1 × 0.5 g each · approximate (reference figure: a whole star anise) · approximation (counted as Spices, anise seed)',
  ),
  (
    '0422-chicken-canzanese.yaml',
    8,
    '4 whole cloves',
    171321,
    '0.40',
    'counted',
    '4 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0450-chicken-bouillabaisse.yaml',
    13,
    '1 strip orange zest (from 1 orange), about 3 inches long, cleaned of white pith',
    169103,
    '2.40',
    'counted',
    '1 strip × 3 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    21,
    '8 whole peppercorns',
    170931,
    '0.40',
    'counted',
    '8 × 0.05 g each · approximate (reference figure: a whole peppercorn)',
  ),
  (
    '0456-daube-provencal.yaml',
    15,
    '4 strips zest from 1 orange, each strip about 3 inches long, removed with a vegetable peeler, cleaned of white pith, and cut lengthwise into thin strips',
    169103,
    '9.60',
    'counted',
    '4 strip × 3 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
  (
    '0462-french-style-pork-stew.yaml',
    5,
    '2 whole cloves',
    171321,
    '0.20',
    'counted',
    '2 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0517-thai-style-chicken-soup.yaml',
    1,
    '3 stalks lemongrass, bottom 5 inches only, trimmed and sliced thin (see this page)',
    168573,
    '30.00',
    'counted',
    '3 stalk × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
  ),
  (
    '0526-san-bei-ji-three-cup-chicken.yaml',
    5,
    '1 (2-inch) piece ginger, peeled, halved lengthwise, and sliced into thin half-rounds',
    169231,
    '16.00',
    'counted',
    '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0534-mapo-tofu-sichuan-braised-tofu-with-beef.yaml',
    5,
    '1 (3-inch) piece ginger, peeled and cut into ¼-inch rounds',
    169231,
    '24.00',
    'counted',
    '1 piece × 3 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0535-chinese-braised-beef.yaml',
    7,
    '1 (2-inch) piece ginger, peeled, halved lengthwise, and crushed',
    169231,
    '16.00',
    'counted',
    '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0538-chinese-style-barbecued-spareribs.yaml',
    0,
    '1 (6-inch) piece fresh ginger, peeled and sliced thin',
    169231,
    '48.00',
    'counted',
    '1 piece × 6 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0540-pork-lo-mein.yaml',
    14,
    '2 bunches scallions, whites sliced thin, greens cut into 1-inch pieces',
    2709794,
    '210.00',
    'counted',
    '2 bunch × 7 × 15 g each · approximate (reference figure: 7 scallions a bunch)',
  ),
  (
    '0566-chicken-biryani.yaml',
    5,
    '10 cardamom pods, preferably green, smashed with a chef’s knife',
    170919,
    '2.00',
    'counted',
    '10 × 0.2 g each · approximate (reference figure: a green cardamom pod)',
  ),
  (
    '0566-chicken-biryani.yaml',
    7,
    '1 (2-inch) piece fresh ginger, peeled, cut into ½-inch-thick coins, and smashed',
    169231,
    '16.00',
    'counted',
    '1 piece × 2 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0567-indian-curry.yaml',
    1,
    '4 whole cloves',
    171321,
    '0.40',
    'counted',
    '4 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0567-indian-curry.yaml',
    2,
    '4 green cardamom pods',
    170919,
    '0.80',
    'counted',
    '4 × 0.2 g each · approximate (reference figure: a green cardamom pod)',
  ),
  (
    '0567-indian-curry.yaml',
    3,
    '8 whole black peppercorns',
    170931,
    '0.40',
    'counted',
    '8 × 0.05 g each · approximate (reference figure: a whole peppercorn)',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    5,
    '2 lemon grass stalks, trimmed to bottom 6 inches and minced',
    168573,
    '20.00',
    'counted',
    '2 × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
  ),
  (
    '0776-strawberries-and-grapes-with-balsamic-and-red-wine-reduction.yaml',
    6,
    '3 whole cloves',
    171321,
    '0.30',
    'counted',
    '3 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0851-baklava.yaml',
    5,
    '5 whole cloves',
    171321,
    '0.50',
    'counted',
    '5 × 0.1 g each · approximate (reference figure: a whole clove)',
  ),
  (
    '0959-bananas-foster.yaml',
    3,
    '1 (2-inch) strip zest from 1 lemon',
    167749,
    '1.60',
    'counted',
    '1 strip × 2 inch × 0.8 g per inch · approximate (the orange-peel strip figure, extended to lemon)',
  ),
  (
    '1089-shrimp-risotto.yaml',
    4,
    '15 black peppercorns',
    170931,
    '0.75',
    'counted',
    '15 × 0.05 g each · approximate (reference figure: a whole peppercorn)',
  ),
  (
    '1095-goan-pork-vindaloo.yaml',
    2,
    '1 (1½-inch) piece ginger, peeled and sliced crosswise ⅛ inch thick',
    169231,
    '12.00',
    'counted',
    '1 piece × 1.5 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '1096-chana-masala.yaml',
    2,
    '1 (1½-inch) piece ginger, peeled and chopped coarse',
    169231,
    '12.00',
    'counted',
    '1 piece × 1.5 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '1172-multicooker-hawaiian-oxtail-soup.yaml',
    1,
    '5 star anise pods',
    171316,
    '2.50',
    'counted',
    '5 × 0.5 g each · approximate (reference figure: a whole star anise) · approximation (counted as Spices, anise seed)',
  ),
  (
    '1194-lumpiang-shanghai-with-seasoned-vinegar.yaml',
    10,
    '1 (½-inch) piece ginger, peeled',
    169231,
    '4.00',
    'counted',
    '1 piece × 0.5 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0281-spanish-style-garlic-shrimp.yaml',
    5,
    '1 (2-inch) piece mild dried chile, such as New Mexico, roughly broken, seeds included',
    168570,
    null,
    'no_grams',
    null,
  ),
  (
    '1172-multicooker-hawaiian-oxtail-soup.yaml',
    6,
    '8 dried jujubes',
    168152,
    null,
    'no_grams',
    null,
  ),
  // RE-PIN (M47 batch, v49 Q6): the peel over a tablespoon plus juice is
  // two parts, peel and juice (no step strains the peel) — counted (was
  // held second_food at the peel's 24.00 g).
  (
    '0536-crispy-orange-beef.yaml',
    3,
    '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), plus ¼ cup juice (2 oranges)',
    169103,
    '86.00',
    'counted',
    'zest 1/4 cup · USDA portion + juice 1/4 cup · USDA portion',
  ),
  (
    '0129-mahogany-chicken-thighs.yaml',
    8,
    '6 garlic cloves, peeled and smashed',
    1104647,
    '18.00',
    'counted',
    '6 × 3 g each',
  ),
  (
    '0005-avgolemono-greek-chicken-and-rice-soup-with-egg-and-lemon.yaml',
    5,
    '1 teaspoon black peppercorns',
    170931,
    '2.91',
    'counted',
    '1 teaspoon ≈ 5 mL',
  ),
];

/// The corpus-stored lines of A (`expectRows`' `stored`).
const List<(String, int, String, int?, String?, String, String?)>
_storedRowsA = [
  (
    '0376-beijing-style-meat-sauce-and-noodles.yaml',
    8,
    '1 (½-inch) piece ginger, peeled and sliced into ⅛-inch rounds',
    169231,
    '4.00',
    'counted',
    '1 × 0.5 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '0376-biang-biang-mian-flat-hand-pulled-noodles-with-chili-oil-vinaigrette.yaml',
    7,
    '1 (1-inch) piece fresh ginger, peeled and sliced thin',
    169231,
    '8.00',
    'counted',
    '1 × 1 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml',
    5,
    '1 (4-inch) piece ginger, sliced into thin rounds',
    169231,
    '32.00',
    'counted',
    '1 × 4 inch × 8 g per inch · approximate (ATK: a 1-inch piece fresh ginger ≈ 1 tablespoon)',
  ),
  (
    '1184-monkfish-tagine.yaml',
    0,
    '3 (2-inch) strips orange zest, divided',
    // Since matcher v37 (the queue sweep, Z3) on the peel, a strip count:
    // until then the whole orange, 393 g (no ruling).
    169103,
    '4.80',
    'counted',
    '3 × 2 inch × 0.8 g per inch · approximate (ATK: 10 (3-inch) strips orange peel ≈ ¼ cup)',
  ),
];

/// (corpus file, position, raw, fdc id, grams, bucket, basis) — B.
const List<(String, int, String, int?, String?, String, String?)> _rowsB = [
  (
    '0007-alcatra-portuguese-style-beef-stew.yaml',
    9,
    '8 ounces Spanish-style chorizo sausage, cut into ¼-inch-thick rounds',
    174603,
    '226.80',
    'counted',
    'from 8 ounce · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '0007-tuscan-style-beef-stew.yaml',
    13,
    '1 teaspoon anchovy paste',
    2706232,
    '6.70',
    'counted',
    '1 teaspoon ≈ 5 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    14,
    '¼ cup fresh Thai basil leaves, torn if large (optional)',
    2709780,
    '6.00',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0025-hearty-spanish-style-lentil-and-chorizo-soup.yaml',
    4,
    '1½ pounds Spanish-style chorizo sausage, pricked with fork several times',
    174603,
    '680.39',
    'counted',
    'from 1 1/2 pound · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '0031-classic-gazpacho.yaml',
    3,
    '½ small sweet onion (such as Vidalia, Maui, or Walla Walla) or 2 large shallots, minced (about ½ cup)',
    170499,
    '80.00',
    'counted',
    '1/2 cup · USDA portion',
  ),
  (
    '0032-spanish-chilled-almond-and-garlic-soup.yaml',
    8,
    '⅛ teaspoon almond extract',
    173471,
    '0.53',
    'counted',
    '1/8 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0033-caldo-verde.yaml',
    1,
    '12 ounces Spanish-style chorizo sausage, cut into ½-inch pieces',
    174603,
    '340.19',
    'counted',
    'from 12 ounce · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '0044-mediterranean-chopped-salad.yaml',
    7,
    '½ cup pitted kalamata olives, chopped',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0046-cherry-tomato-salad-with-feta-and-olives.yaml',
    10,
    '½ cup chopped pitted kalamata olives',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0048-classic-greek-salad.yaml',
    14,
    '20 large pitted kalamata olives, quartered',
    2710090,
    '100.00',
    'counted',
    '20 · USDA per-item weight · approximation (counted as Olives, black)',
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    3,
    '2 tablespoons (⅞ ounce) palm sugar',
    2710260,
    '24.81',
    'counted',
    'from 7/8 ounce · approximation (counted as Sugar, brown)',
  ),
  (
    '0053-crispy-thai-eggplant-salad.yaml',
    13,
    '½ cup fresh Thai basil leaves',
    2709780,
    '12.00',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0056-austrian-style-potato-salad.yaml',
    7,
    '6 cornichons, minced (about 2 tablespoons)',
    2710078,
    '19.38',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Pickles, dill)',
  ),
  (
    '0061-italian-pasta-salad.yaml',
    9,
    '½ cup pitted kalamata olives, quartered',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0063-lentil-salad-with-olives-mint-and-feta.yaml',
    8,
    '½ cup pitted kalamata olives, chopped coarse',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0066-pasta-frittata-with-sausage-and-hot-peppers.yaml',
    9,
    '6 ounces angel hair pasta, broken in half',
    169736,
    '170.10',
    'counted',
    'from 6 ounce',
  ),
  (
    '0067-skillet-lasagna.yaml',
    7,
    '1 pound meatloaf mix',
    2514744,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0092-simple-pot-au-feu.yaml',
    11,
    '10 cornichons, minced',
    2710078,
    '32.00',
    'counted',
    '10 × 3.2 g each · approximate (ATK: 6 cornichons ≈ 2 tablespoons minced) · approximation (counted as Pickles, dill)',
  ),
  (
    '0096-best-chicken-stew.yaml',
    7,
    '2 teaspoons anchovy paste',
    2706232,
    '13.40',
    'counted',
    '2 teaspoon ≈ 10 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0106-paella-on-the-grill.yaml',
    15,
    '1 pound Spanish-style chorizo, cut into ½-inch pieces',
    174603,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '0127-coq-au-riesling.yaml',
    8,
    '2½ cups dry Riesling',
    173200,
    '592.00',
    'counted',
    '2 1/2 cup · USDA portion',
  ),
  (
    '0139-peruvian-roast-chicken-with-garlic-and-lime.yaml',
    10,
    '1 teaspoon minced habanero chile',
    2709798,
    '3.13',
    'counted',
    '1 teaspoon · USDA portion',
  ),
  (
    '0151-buffalo-wings.yaml',
    1,
    '½ cup Frank’s RedHot Original Sauce',
    2710093,
    '128.00',
    'counted',
    '1/2 cup · USDA portion',
  ),
  (
    '0209-red-winebraised-pork-chops.yaml',
    10,
    '¼ cup ruby port',
    2710692,
    '60.00',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0218-beef-tenderloin-with-smoky-potatoes-and-persillade-relish.yaml',
    11,
    '6 tablespoons minced cornichons plus 1 teaspoon brine',
    2710078,
    '58.13',
    'check',
    '6 tablespoon · USDA portion · approximation (counted as Pickles, dill)',
  ),
  (
    '0267-moroccan-fish-tagine.yaml',
    14,
    '2 tablespoons finely chopped preserved lemon',
    167749,
    '12.00',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Lemon peel, raw)',
  ),
  (
    '0274-red-snapper-ceviche-with-radishes-and-orange.yaml',
    4,
    '1 tablespoon ají amarillo chile paste',
    171186,
    '19.50',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '0282-spanish-style-toasted-pasta-with-shrimp.yaml',
    12,
    '½ teaspoon anchovy paste',
    2706232,
    '3.35',
    'counted',
    '1/2 teaspoon ≈ 2 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0283-greek-style-shrimp-with-tomatoes-and-feta.yaml',
    2,
    '3 tablespoons ouzo',
    2710699,
    '42.00',
    'counted',
    '3 tablespoon · USDA portion · approximation (counted as Brandy)',
  ),
  (
    '0306-meatloaf-with-brown-sugarketchup-glaze.yaml',
    0,
    '½ cup ketchup or chili sauce',
    2709733,
    '136.00',
    'counted',
    '1/2 cup · USDA portion',
  ),
  (
    '0306-meatloaf-with-brown-sugarketchup-glaze.yaml',
    14,
    '2 pounds meatloaf mix (50 percent ground chuck, 25 percent ground pork, 25 percent ground veal)',
    2514744,
    '907.18',
    'counted',
    'from 2 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0309-philly-cheesesteaks.yaml',
    1,
    '4 (8-inch) Italian sub rolls, split lengthwise',
    2707782,
    '424.00',
    'counted',
    '4 · USDA per-item weight · approximation (counted as Roll, multigrain)',
  ),
  (
    '0329-farfalle-with-tomatoes-olives-and-feta.yaml',
    3,
    '½ cup pitted kalamata olives, chopped coarse',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0331-spaghetti-puttanesca.yaml',
    7,
    '½ cup pitted kalamata olives, chopped coarse',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0340-summer-pasta-puttanesca.yaml',
    2,
    '1 tablespoon anchovy paste',
    2706232,
    '20.10',
    'counted',
    '1 tablespoon ≈ 15 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0340-summer-pasta-puttanesca.yaml',
    8,
    '½ cup pitted kalamata olives, chopped coarse',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    17,
    '1 pound meatloaf mix',
    2514744,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0354-fettuccine-with-slow-simmered-bolognese-sauce.yaml',
    4,
    '¾ pound meatloaf mix',
    2514744,
    '340.19',
    'counted',
    'from 3/4 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0355-pasta-with-streamlined-bolognese-sauce.yaml',
    9,
    '1¼ pounds meatloaf mix',
    2514744,
    '566.99',
    'counted',
    'from 1 1/4 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0373-vegetable-lasagna.yaml',
    21,
    '½ cup pitted kalamata olives, minced',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0374-lasagna-with-hearty-tomato-meat-sauce.yaml',
    3,
    '1 pound meatloaf mix',
    2514744,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Beef, ground, 80% lean meat / 20% fat, raw)',
  ),
  (
    '0402-frico.yaml',
    0,
    '1 pound Montasio or aged Asiago cheese, grated fine (about 8 cups)',
    325036,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Cheese, parmesan, grated)',
  ),
  (
    '0414-chicken-marsala.yaml',
    8,
    '1½ cups sweet Marsala (see note)',
    2710692,
    '360.00',
    'counted',
    '1 1/2 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0415-better-chicken-marsala.yaml',
    0,
    '2¼ cups dry Marsala',
    175112,
    '531.00',
    'counted',
    '2 1/4 cup · USDA portion · approximation (counted as Alcoholic beverage, wine, dessert, dry)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    10,
    '1 (750-milliliter) bottle Barolo wine',
    2710688,
    '750.00',
    'counted',
    '1 bottle · USDA portion',
  ),
  (
    '0434-salade-lyonnaise.yaml',
    6,
    '5 ounces chicory or escarole, torn into bite-size pieces (5 cups)',
    168413,
    '141.75',
    'counted',
    'from 5 ounce · approximation (counted as Escarole, cooked, boiled, drained, no salt added)',
  ),
  (
    '0439-pissaladiere.yaml',
    11,
    '½ cup niçoise olives, pitted and chopped coarse',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0450-chicken-bouillabaisse.yaml',
    14,
    '¼ cup pastis or Pernod',
    2710699,
    '56.00',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Brandy)',
  ),
  (
    '0455-chicken-provencal.yaml',
    16,
    '½ cup pitted niçoise olives',
    2710090,
    '67.50',
    'counted',
    '1/2 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0456-daube-provencal.yaml',
    14,
    '1 cup pitted niçoise olives, drained well',
    2710090,
    '135.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0459-modern-beef-burgundy.yaml',
    12,
    '1 teaspoon anchovy paste',
    2706232,
    '6.70',
    'counted',
    '1 teaspoon ≈ 5 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0467-pan-bagnat-provencal-tuna-sandwich.yaml',
    6,
    '¾ cup niçoise olives, pitted',
    2710090,
    '101.25',
    'counted',
    '3/4 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    8,
    '1 tablespoon ground chipotle powder',
    170932,
    '5.30',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Spices, pepper, red or cayenne)',
  ),
  (
    '0495-chili-con-carne.yaml',
    1,
    '3 medium New Mexican pods (about ¾ ounce), toasted and ground, or 3 tablespoons New Mexican chile powder',
    169396,
    '21.26',
    'counted',
    'from 3/4 ounce · approximation (counted as Peppers, ancho, dried)',
  ),
  (
    '0496-white-chicken-chili.yaml',
    5,
    '3 medium Anaheim chiles, stemmed, seeded, and cut into large pieces',
    169394,
    '138.00',
    'counted',
    '3 · USDA per-item weight · approximation (counted as Pepper, banana, raw)',
  ),
  (
    '0504-pai-huang-gua-smashed-cucumbers.yaml',
    2,
    '4 teaspoons Chinese black vinegar',
    172241,
    '19.91',
    'counted',
    '4 teaspoon ≈ 20 mL · approximation (counted as Vinegar, balsamic)',
  ),
  (
    '0506-chinese-pork-dumplings.yaml',
    14,
    'Chili oil',
    2710180,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Vegetable oil, NFS)',
  ),
  (
    '0506-pork-and-cabbage-dumplingswor-tip.yaml',
    2,
    '2 tablespoons mirin or sweet sherry',
    2710692,
    '29.28',
    'counted',
    '2 tablespoon ≈ 30 mL · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0506-pork-and-cabbage-dumplingswor-tip.yaml',
    4,
    '1 teaspoon chili oil (optional)',
    2710180,
    '4.53',
    'counted',
    '1 teaspoon ≈ 5 mL · approximation (counted as Vegetable oil, NFS)',
  ),
  (
    '0510-goi-cuo-n-vietnamese-summer-rolls.yaml',
    14,
    '1 cup Thai basil leaves',
    2709780,
    '24.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0518-hot-and-sour-soup.yaml',
    10,
    '5 tablespoons Chinese black vinegar',
    172241,
    '74.67',
    'counted',
    '5 tablespoon ≈ 74 mL · approximation (counted as Vinegar, balsamic)',
  ),
  (
    '0518-hot-and-sour-soup.yaml',
    11,
    '2 teaspoons chili oil',
    2710180,
    '9.07',
    'counted',
    '2 teaspoon ≈ 10 mL · approximation (counted as Vegetable oil, NFS)',
  ),
  (
    '0524-chicken-teriyaki.yaml',
    5,
    '2 tablespoons mirin or sweet sherry',
    2710692,
    '29.28',
    'counted',
    '2 tablespoon ≈ 30 mL · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0526-san-bei-ji-three-cup-chicken.yaml',
    11,
    '1 cup Thai basil leaves, large leaves halved lengthwise',
    2709780,
    '24.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0528-gongbao-jiding-sichuan-kung-pao-chicken.yaml',
    5,
    '1 tablespoon Chinese black vinegar',
    172241,
    '14.93',
    'counted',
    '1 tablespoon ≈ 15 mL · approximation (counted as Vinegar, balsamic)',
  ),
  (
    '0533-teriyaki-stir-fried-beef-with-green-beans-and-shiitakes.yaml',
    3,
    '1 tablespoon mirin or sweet sherry',
    2710692,
    '14.64',
    'counted',
    '1 tablespoon ≈ 15 mL · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0540-pork-lo-mein.yaml',
    17,
    '1 tablespoon Asian chili-garlic sauce',
    171186,
    '19.50',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '0540-sichuan-stir-fried-pork-in-garlic-sauce.yaml',
    3,
    '4 teaspoons Chinese black vinegar',
    172241,
    '19.91',
    'counted',
    '4 teaspoon ≈ 20 mL · approximation (counted as Vinegar, balsamic)',
  ),
  (
    '0544-stir-fried-shrimp-with-snow-peas-and-red-bell-pepper-in-hot-and-sour-sauce.yaml',
    7,
    '1 tablespoon Asian chili-garlic sauce',
    171186,
    '19.50',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '0551-panang-beef-curry.yaml',
    6,
    '1 Thai red chile, halved lengthwise (optional)',
    2709798,
    '15.00',
    'counted',
    '1 · USDA per-item weight',
  ),
  (
    '0552-stir-fried-thai-style-beef-with-chiles-and-shallots.yaml',
    4,
    '1 tablespoon Asian chili-garlic paste',
    171186,
    '19.50',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Sauce, hot chile, sriracha)',
  ),
  (
    '0553-pad-thai.yaml',
    14,
    '2 tablespoons chopped Thai salted preserved radish (optional)',
    2710099,
    '18.75',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Radishes, pickled)',
  ),
  (
    '0553-thai-style-stir-fried-noodles-with-chicken-and-broccolini.yaml',
    14,
    '10 ounces broccolini, florets cut into 1-inch pieces, stalks cut on bias into ½-inch pieces (5 cups)',
    747447,
    '283.50',
    'counted',
    'from 10 ounce · approximation (counted as Broccoli, raw)',
  ),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    7,
    '1 cup fresh Thai basil leaves',
    2709780,
    '24.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  (
    '0597-easy-grilled-boneless-pork-chops.yaml',
    4,
    '1 teaspoon anchovy paste',
    2706232,
    '6.70',
    'counted',
    '1 teaspoon ≈ 5 mL · approximate (ATK: 2 anchovy fillets ≈ 1 to 1½ teaspoons paste) · approximation (counted as Fish, anchovy)',
  ),
  (
    '0602-grilled-pork-tenderloin-with-grilled-pineapplered-onion-salsa.yaml',
    3,
    '½ teaspoon chipotle chile powder',
    170932,
    '0.90',
    'counted',
    '1/2 teaspoon · USDA portion · approximation (counted as Spices, pepper, red or cayenne)',
  ),
  (
    '0603-grilled-pork-tenderloin-with-grilled-tomatoginger-salsa.yaml',
    3,
    '½ teaspoon chipotle chile powder',
    170932,
    '0.90',
    'counted',
    '1/2 teaspoon · USDA portion · approximation (counted as Spices, pepper, red or cayenne)',
  ),
  (
    '0613-kansas-city-sticky-ribs.yaml',
    6,
    '1 tablespoon vegetable oil plus more for cooking grate',
    2710180,
    '14.00',
    'counted',
    '1 tablespoon · USDA portion',
  ),
  (
    '0632-jerk-chicken.yaml',
    3,
    '1–3 habanero chiles, stemmed, quartered, and seeds and ribs reserved, if using',
    2709798,
    '30.00',
    'counted',
    '1–3 · USDA per-item weight',
  ),
  (
    '0649-grilled-fish-tacos.yaml',
    1,
    '1 tablespoon ancho chile powder',
    171329,
    '6.80',
    'counted',
    '1 tablespoon · USDA portion · approximation (counted as Spices, paprika)',
  ),
  (
    '0649-grilled-fish-tacos.yaml',
    2,
    '2 teaspoons chipotle chile powder',
    170932,
    '3.60',
    'counted',
    '2 teaspoon · USDA portion · approximation (counted as Spices, pepper, red or cayenne)',
  ),
  (
    '0654-grilled-swordfish-skewers-with-tomato-scallion-caponata.yaml',
    13,
    '¼ cup pitted kalamata olives, chopped',
    2710090,
    '33.75',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0679-drunken-beans.yaml',
    9,
    '1 cup Mexican lager',
    2710616,
    '240.00',
    'counted',
    '1 cup · USDA portion',
  ),
  (
    '0695-mashed-potatoes-with-blue-cheese-and-port-caramelized-onions.yaml',
    5,
    '1 cup ruby port',
    2710692,
    '240.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0700-duck-fatroasted-potatoes.yaml',
    3,
    '6 tablespoons duck fat',
    173572,
    '76.80',
    'counted',
    '6 tablespoon · USDA portion · approximation (counted as Fat, goose)',
  ),
  (
    '0712-red-beans-and-rice.yaml',
    1,
    '1 pound (about 2 cups) dried small red beans, picked over and rinsed',
    173744,
    '453.59',
    'counted',
    'from 1 pound · approximation (counted as Beans, kidney, red, mature seeds, raw)',
  ),
  (
    '0726-eggs-piperade.yaml',
    9,
    '3 cubanelle peppers (3 to 4 ounces each), stemmed, seeded, and cut into ⅜-inch strips',
    169394,
    '297.67',
    'counted',
    // RE-PIN (M48): the basis names the range (3–4 oz, already read at its
    // midpoint; grams unchanged).
    '3 × 99 g (printed 3–4 oz, the midpoint) · approximation (counted as Pepper, banana, raw)',
  ),
  (
    '0729-shakshuka-eggs-in-spicy-tomato-and-roasted-red-pepper-sauce.yaml',
    15,
    '¼ cup pitted kalamata olives, sliced',
    2710090,
    '33.75',
    'counted',
    '1/4 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '0778-mexican-hot-chocolate.yaml',
    8,
    '¾ teaspoon ancho chile powder',
    171329,
    '1.72',
    'counted',
    '3/4 teaspoon · USDA portion · approximation (counted as Spices, paprika)',
  ),
  (
    '0798-almost-no-knead-bread.yaml',
    4,
    '6 tablespoons mild-flavored lager',
    2710616,
    '90.00',
    'counted',
    '6 tablespoon · USDA portion',
  ),
  (
    '0832-easy-holiday-sugar-cookies.yaml',
    3,
    '¼ teaspoon almond extract',
    173471,
    '1.05',
    'counted',
    '1/4 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0841-almond-biscotti.yaml',
    7,
    '1½ teaspoons almond extract',
    173471,
    '6.30',
    'counted',
    '1 1/2 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0845-chewy-brownies.yaml',
    1,
    '1½ teaspoons instant espresso (optional)',
    171893,
    '3.18',
    'counted',
    '1 1/2 teaspoon ≈ 7 mL',
  ),
  (
    '0856-angel-food-cake.yaml',
    7,
    '½ teaspoon almond extract',
    173471,
    '2.10',
    'counted',
    '1/2 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0870-best-almond-cake.yaml',
    8,
    '¾ teaspoon almond extract',
    173471,
    '3.15',
    'counted',
    '3/4 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0872-strawberry-cream-cake.yaml',
    10,
    '2 tablespoons kirsch',
    2710699,
    '28.00',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Brandy)',
  ),
  (
    '0875-summer-peach-cake.yaml',
    1,
    '5 tablespoons peach schnapps',
    2710623,
    '75.00',
    'counted',
    '5 tablespoon · USDA portion · approximation (counted as Liqueur)',
  ),
  (
    '0875-summer-peach-cake.yaml',
    12,
    '¼ teaspoon plus ⅛ teaspoon almond extract',
    173471,
    '1.58',
    'counted',
    '1/4 teaspoon · USDA portion + ⅛ teaspoon almond extract · approximation (counted as Vanilla extract)',
  ),
  (
    '0878-coconut-layer-cake.yaml',
    4,
    '1 teaspoon coconut extract',
    173471,
    '4.20',
    'counted',
    '1 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0878-coconut-layer-cake.yaml',
    11,
    '1 teaspoon coconut extract',
    173471,
    '4.20',
    'counted',
    '1 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0883-classic-white-layer-cake-with-butter-frosting-and-raspberry-almond-filling.yaml',
    4,
    '1 teaspoon almond extract',
    173471,
    '4.20',
    'counted',
    '1 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0943-frozen-yogurt.yaml',
    3,
    '3 tablespoons Lyle’s Golden Syrup',
    168837,
    '66.00',
    'counted',
    '3 tablespoon · USDA portion · approximation (counted as Syrups, corn, light)',
  ),
  (
    '0949-sour-cherry-cobbler.yaml',
    13,
    '¼ teaspoon almond extract',
    173471,
    '1.05',
    'counted',
    '1/4 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '0968-summer-berry-trifle.yaml',
    25,
    '1 tablespoon plus ½ cup cream sherry',
    2710692,
    '131.75',
    'counted',
    '1 tablespoon ≈ 15 mL + ½ cup cream sherry · approximation (counted as Wine, dessert, sweet)',
  ),
  (
    '0987-pumpkin-pie.yaml',
    6,
    '1 cup candied yams, drained',
    170071,
    '150.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Yam, raw)',
  ),
  (
    '1072-horiatiki-salata-hearty-greek-salad.yaml',
    8,
    '1 cup pitted kalamata olives',
    2710090,
    '135.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Olives, black)',
  ),
  (
    '1075-espinacas-con-garbanzos-andalusian-spinach-and-chickpeas.yaml',
    0,
    '1 loaf crusty bread, divided',
    2707614,
    '454.00',
    'counted',
    '1 loaf · USDA portion',
  ),
  (
    '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml',
    6,
    '6 cups duck fat, chicken fat, or vegetable oil for confit',
    173572,
    '0.00',
    'counted',
    'discarded in cooking — counted as 0 g · approximation (counted as Fat, goose)',
  ),
  (
    '1086-pasta-with-burst-cherry-tomato-sauce-and-fried-caper-crumbs.yaml',
    15,
    '12 ounces penne rigate, orecchiette, campanelle, or other short pasta',
    169736,
    '340.19',
    'counted',
    'from 12 ounce',
  ),
  (
    '1097-roasted-radishes-with-yogurt-tahini-sauce.yaml',
    12,
    '2 pounds radishes with their greens, radishes trimmed and halved lengthwise, 8 cups greens reserved',
    2709803,
    '907.18',
    'counted',
    'from 2 pound',
  ),
  (
    '1099-spanish-migas-with-fried-eggs.yaml',
    6,
    '6 ounces Spanish-style chorizo sausage, halved lengthwise and sliced ¼ inch thick',
    174603,
    '170.10',
    'counted',
    'from 6 ounce · approximation (counted as Salami, Italian, pork)',
  ),
  (
    '1099-spanish-migas-with-fried-eggs.yaml',
    9,
    '2 Cubanelle peppers, stemmed, seeded, and cut into ½-inch pieces',
    169394,
    '198.00',
    'counted',
    '2 × 99 g each · approximate (ATK: a Cubanelle pepper ≈ 3 to 4 ounces) · approximation (counted as Pepper, banana, raw)',
  ),
  (
    '1116-cranberry-curd-tart-with-almond-crust.yaml',
    12,
    '¾ teaspoon almond extract',
    173471,
    '3.15',
    'counted',
    '3/4 teaspoon · USDA portion · approximation (counted as Vanilla extract)',
  ),
  (
    '1120-cataplana-portuguese-seafood-stew.yaml',
    3,
    '12 ounces linguica sausage, quartered lengthwise and sliced ¼ inch thick',
    174584,
    '340.19',
    'counted',
    'from 12 ounce',
  ),
  (
    '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-casserole.yaml',
    1,
    '1 small Cubanelle pepper, stemmed, seeded, and chopped coarse',
    169394,
    '99.00',
    'counted',
    '1 × 99 g each · approximate (ATK: a Cubanelle pepper ≈ 3 to 4 ounces) · approximation (counted as Pepper, banana, raw)',
  ),
  (
    '1135-gnocchi-a-la-parisienne-with-arugula-tomatoes-and-olives.yaml',
    7,
    '20 pitted kalamata olives, quartered',
    2710090,
    '100.00',
    'counted',
    '20 · USDA per-item weight · approximation (counted as Olives, black)',
  ),
  (
    '1137-pakoras-south-asian-spiced-vegetable-fritters.yaml',
    8,
    '½ teaspoon Kashmiri chile powder',
    171329,
    '1.15',
    'counted',
    '1/2 teaspoon · USDA portion · approximation (counted as Spices, paprika)',
  ),
  (
    '1145-clbr-turkish-poached-eggs-with-yogurt-and-spiced-butter.yaml',
    6,
    '1 teaspoon pul biber or ground dried Aleppo pepper',
    171329,
    '2.32',
    'counted',
    '1 teaspoon ≈ 5 mL · approximate (paprika density) · approximation (counted as Spices, paprika)',
  ),
  (
    '1146-pa-amb-tomaquet-catalan-tomato-bread.yaml',
    2,
    '1 loaf ciabatta, halved horizontally and sliced crosswise 2 inches thick',
    2707614,
    '454.00',
    'counted',
    '1 loaf · USDA portion',
  ),
  (
    '1150-congee-chinese-rice-porridge.yaml',
    6,
    'Chili oil',
    2710180,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Vegetable oil, NFS)',
  ),
  (
    '1150-congee-chinese-rice-porridge.yaml',
    8,
    'Chinese black vinegar',
    172241,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Vinegar, balsamic)',
  ),
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml',
    14,
    'Chili oil',
    2710180,
    '0.00',
    'counted',
    'no amount on the line — counted as 0 g · approximation (counted as Vegetable oil, NFS)',
  ),
  (
    '1172-multicooker-hawaiian-oxtail-soup.yaml',
    10,
    '1 pound gai choy, trimmed and cut into 2-inch pieces',
    169256,
    '453.59',
    'counted',
    'from 1 pound',
  ),
  (
    '1173-classic-caesar-salad.yaml',
    2,
    '2 ounces ciabatta bread, cut into ¾-inch pieces (1½ cups)',
    2707614,
    '56.70',
    'counted',
    'from 2 ounce',
  ),
  (
    '1174-seared-halloumi-and-vegetable-salad-bowl.yaml',
    12,
    '1 cup jarred whole artichoke hearts packed in water, halved, rinsed, and patted dry',
    2709766,
    '150.00',
    'counted',
    '1 cup · USDA portion · approximation (counted as Artichoke)',
  ),
  (
    '1179-chicken-and-spiced-freekeh-with-cilantro-and-preserved-lemon.yaml',
    13,
    '2 tablespoons rinsed and minced preserved lemon',
    167749,
    '12.00',
    'counted',
    '2 tablespoon · USDA portion · approximation (counted as Lemon peel, raw)',
  ),
  (
    '1188-weeknight-pasta-bolognese.yaml',
    14,
    '1 pound dried pappardelle',
    169736,
    '453.59',
    'counted',
    'from 1 pound',
  ),
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    0,
    '12 ounces Fresno chiles, stemmed, seeded, and chopped coarse',
    2709798,
    '340.19',
    'counted',
    'from 12 ounce',
  ),
  (
    '1193-crispy-tempeh-with-sambal-sauce.yaml',
    9,
    '1½ cups fresh Thai or Italian basil leaves',
    2709780,
    '36.00',
    'counted',
    '1 1/2 cup · USDA portion · approximation (counted as Basil, raw)',
  ),
  // v32 (the live step): on 173443 "Sour cream, light", counted.
  (
    '0846-fudgy-low-fat-brownies.yaml',
    7,
    '2 tablespoons low-fat sour cream',
    173443,
    '28.69',
    'counted',
    '2 tablespoon ≈ 30 mL',
  ),
  (
    '0316-classic-french-fries.yaml',
    2,
    '¼ cup bacon fat, strained (optional)',
    172345,
    '51.60',
    'counted',
    '1/4 cup · USDA portion',
  ),
  (
    '0095-chicken-and-dumplings.yaml',
    19,
    '3 tablespoons reserved chicken fat',
    173564,
    '38.40',
    'counted',
    '3 tablespoon · USDA portion',
  ),
];

/// The corpus-stored lines of B.
const List<(String, int, String, int?, String?, String, String?)>
_storedRowsB = [
  (
    '1099-spanish-migas-with-fried-eggs.yaml',
    3,
    '5 (¾-inch-thick) slices rustic, crusty bread (9 ounces), bottom crust removed, cut into ½- to ¾-inch cubes (5 cups)',
    2707614,
    '255.15',
    'counted',
    'from 9 ounce',
  ),
  (
    '1155-champagne-cocktail.yaml',
    2,
    '5½ fluid ounces (½ cup plus 3 tablespoons) champagne, chilled',
    2710689,
    '165.35',
    'counted',
    '163 ml · USDA portion · approximation (counted as Wine, white)',
  ),
];

/// Every Q7 rank-as item v31 builds.
const List<String> _q7Items = [
  'kalamata olives',
  'nicoise olives',
  'ruby port',
  'cream sherry',
  'sweet marsala',
  'mirin or sweet sherry',
  'dry marsala',
  'dry riesling',
  'barolo wine',
  'fluid ounces champagne',
  'kirsch',
  'peach schnapps',
  'almond extract',
  'coconut extract',
  'ancho chile powder',
  'chipotle chile powder',
  'ground chipotle powder',
  'kashmiri chile powder',
  'pul biber or ground dried aleppo pepper',
  'aji amarillo chile paste',
  'spanish-style chorizo',
  'spanish-style chorizo sausage',
  'linguica sausage',
  'thai basil leaves',
  'thai or italian basil leaves',
  'meatloaf mix',
  'duck fat',
  'chili oil',
  'vegetable oil more for cooking grate',
  'chinese black vinegar',
  'anaheim chiles',
  'angel hair pasta',
  'asian chili-garlic paste',
  'broccolini',
  'candied yams',
  'chicory or escarole',
  'ciabatta',
  'ciabatta bread',
  'cornichons',
  'crusty bread',
  'rustic crusty bread',
  'cubanelle peppers',
  'cubanelle pepper',
  'dried pappardelle',
  'dried red beans',
  'frank s redhot original sauce',
  'fresno chiles',
  'gai choy',
  'habanero chiles',
  'habanero chile',
  'instant espresso',
  'italian sub rolls',
  'jarred whole artichoke hearts in water',
  'ketchup or chili sauce',
  'lyle s golden syrup',
  'mexican lager',
  'mild-flavored lager',
  'montasio or aged asiago cheese',
  'new mexican pods',
  'ouzo',
  'pastis or pernod',
  'palm sugar',
  'penne rigate',
  'preserved lemon',
  'radishes with their greens',
  'sweet onion or 2 shallots',
  'thai red chile',
  'thai with salt preserved radish',
  'anchovy paste',
  'asian chili-garlic sauce',
];

/// Their flagged approximations.
const Map<String, int> _q7Flagged = {
  'kalamata olives': 2710090,
  'nicoise olives': 2710090,
  'ruby port': 2710692,
  'cream sherry': 2710692,
  'sweet marsala': 2710692,
  'mirin or sweet sherry': 2710692,
  'dry marsala': 175112,
  'fluid ounces champagne': 2710689,
  'kirsch': 2710699,
  'peach schnapps': 2710623,
  'almond extract': 173471,
  'coconut extract': 173471,
  'ancho chile powder': 171329,
  'chipotle chile powder': 170932,
  'ground chipotle powder': 170932,
  'kashmiri chile powder': 171329,
  'pul biber or ground dried aleppo pepper': 171329,
  'aji amarillo chile paste': 171186,
  'spanish-style chorizo': 174603,
  'spanish-style chorizo sausage': 174603,
  'thai basil leaves': 2709780,
  'thai or italian basil leaves': 2709780,
  'meatloaf mix': 2514744,
  'duck fat': 173572,
  'chili oil': 2710180,
  'chinese black vinegar': 172241,
  'anaheim chiles': 169394,
  'asian chili-garlic paste': 171186,
  'broccolini': 747447,
  'candied yams': 170071,
  'chicory or escarole': 168413,
  'cornichons': 2710078,
  'cubanelle peppers': 169394,
  'cubanelle pepper': 169394,
  'dried red beans': 173744,
  'italian sub rolls': 2707782,
  'jarred whole artichoke hearts in water': 2709766,
  'lyle s golden syrup': 168837,
  'montasio or aged asiago cheese': 325036,
  'new mexican pods': 169396,
  'ouzo': 2710699,
  'pastis or pernod': 2710699,
  'palm sugar': 2710260,
  'preserved lemon': 167749,
  'thai with salt preserved radish': 2710099,
  'anchovy paste': 2706232,
  'asian chili-garlic sauce': 171186,
};

/// (corpus file, position, fdc id, grams, hold, hold note) — C, each the
/// cache-only replay's row.
const List<(String, int, int, String?, String?, String?)> _rowsC = [
  // 0488 Enchiladas Verdes: the poaching set, held; the kept ¼ cup and each
  // part eaten outside the poach in its note (the garlic's teaspoon has no
  // grams: 1104647 publishes no volume portion).
  (
    '0488-enchiladas-verdes.yaml',
    0,
    2710180,
    '9.07',
    'partial_pour_away',
    '¼ cup liquid; 2 teaspoons oil is used outside the braise, eaten',
  ),
  (
    '0488-enchiladas-verdes.yaml',
    1,
    790646,
    null,
    'partial_pour_away',
    '¼ cup liquid',
  ),
  (
    '0488-enchiladas-verdes.yaml',
    2,
    1104647,
    null,
    'partial_pour_away',
    '¼ cup liquid; 1 teaspoon garlic is used outside the braise, eaten',
  ),
  (
    '0488-enchiladas-verdes.yaml',
    3,
    170923,
    null,
    'partial_pour_away',
    '¼ cup liquid',
  ),
  (
    '0488-enchiladas-verdes.yaml',
    4,
    171609,
    null,
    'partial_pour_away',
    '¼ cup liquid',
  ),
  // The poached chicken and the sauce's tomatillos count.
  ('0488-enchiladas-verdes.yaml', 5, 2646170, '453.59', null, null),
  ('0488-enchiladas-verdes.yaml', 6, 168566, '680.39', null, null),
  // 0042: the two tablespoons the dressing eats count; the fried ¾ cup not
  // — RE-PIN (M52 batch, v53, Q3 a): save the oil its breasts absorb, 28.00
  // + 623.69 g × O1a 6.68 % (USDA FNDDS 2705975) = 69.66 g.
  (
    '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
    7,
    2710180,
    '69.66',
    null,
    null,
  ),
  // 0674, 0675: fried by the verb alone — held, the sentence the note.
  // RE-PIN (M52 batch, v53, Q24 b): 0288's oil, heated for the coated cakes
  // it browns, is a frying oil — 453.59 g of crab × O1a 6.68 % (a flagged
  // stand-in) = 30.30 g, unheld.
  // RE-PIN (M63 batch, v62, Q11): 453.59 g of crab × FNDDS 2706549 "Crab,
  // cake"'s own 7.69 % (5 g oil per 65 g crab) = 34.88 g (was 30.30).
  (
    '0288-maryland-crab-cakes.yaml',
    9,
    2710180,
    '34.88',
    null,
    null,
  ),
  (
    '0674-corn-fritters.yaml',
    8,
    2710180,
    null,
    'ambiguous_medium',
    '"Fry until golden brown, about 1 minute."',
  ),
  // Its teaspoon sautés the corn: the eaten part, held with the line.
  (
    '0675-southern-corn-fritters.yaml',
    1,
    2710180,
    '4.53',
    'ambiguous_medium',
    '"Fry until deep golden brown on both sides, 2 to 3 minutes per side."',
  ),
  // 0672: the sauce's coconut oil counts; the fryer oil is zeroed by mass.
  ('0672-buffalo-cauliflower-bites.yaml', 0, 171412, '54.42', null, null),
];
