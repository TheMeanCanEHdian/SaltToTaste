// Real corpus lines wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v23's rules and grams (Run 053): grated hard cheese at the
/// corpus's printed conversion (G4), R2's dredge read from the directions
/// (G3), a pick on a line-held medium keeping its hold and a divided line's
/// eaten part (G6), the rank-as singular (G7) and `_asPrepared`'s scope.
/// Real corpus recipes on recorded FDC answers (FixtureProvider), never live.
void main() {
  test(
    'G4: grated Pecorino weighs what simple-cheese-lasagna prints beside it '
    '— "1 ounce Pecorino Romano cheese, grated (½ cup)" is 28.35 g, so its '
    '"¼ cup grated Pecorino Romano cheese" is half that (0.24 g/mL, never '
    "the table's 0.42: 24.84 g), and its basis names the conversion; a "
    "shredded line weighs the corpus's printed shredded pair, 3 ounces a "
    'cup (0.36: "1½ ounces Parmesan cheese, shredded (½ cup)"), Pecorino '
    'on it flagged; a "plus" part that prints its own weight weighs it '
    '(0403\'s "plus 3 ounces Parmesan, shredded (1 cup)" is 85.05 g, never '
    '1 cup by a density, 99.37 g)',
    () async {
      final db = wp.tempDb();
      final provider = FixtureProvider();
      final romano = (await provider.food(171249))!;
      final lasagna = nutritionLines(
        loadCorpusRecipe('0371-simple-cheese-lasagna.yaml'),
      );
      GramResolution? on(String raw, FdcFood food) =>
          lineGrams(db, lasagna.firstWhere((l) => l.raw == raw), food);
      final printed = on(
        '1 ounce Pecorino Romano cheese, grated (½ cup)',
        romano,
      )!;
      final quarter = on('¼ cup grated Pecorino Romano cheese', romano)!;
      expect(printed.grams, closeTo(28.35, 0.01));
      expect(quarter.grams.toStringAsFixed(2), '14.18');
      expect(quarter.grams * 2, closeTo(printed.grams, 0.01));
      expect(
        quarter.basis,
        "1/4 cup ≈ 59 mL · grated, at ATK's printed 1 ounce = ½ cup",
      );
      // The same key, shredded (0669 line 4): the corpus prints shredded
      // Parmesan only, so Pecorino weighs on it, flagged.
      final shredded = lineGrams(
        db,
        nutritionLines(
          loadCorpusRecipe(
            '0669-skillet-roasted-brussels-sprouts-with-lemon-and-pecorino-'
            'romano.yaml',
          ),
        ).firstWhere((l) => l.raw == '¼ cup shredded Pecorino Romano cheese'),
        romano,
      )!;
      expect(shredded.grams.toStringAsFixed(2), '21.26');
      expect(
        shredded.basis,
        "1/4 cup ≈ 59 mL · shredded, at ATK's printed 3 ounces = 1 cup · "
        'approximate (shredded Parmesan density)',
      );
      // Shredded Parmesan weighs what 0391 prints beside its own volume:
      // the line's ½ cup, read alone (synthesized: the weight dropped, a
      // stated exception), is its 1½ ounces.
      final parmesanFood = (await provider.food(325036))!;
      final pizza =
          nutritionLines(
            loadCorpusRecipe(
              '0391-pizza-al-taglio-with-arugula-and-fresh-mozzarella.yaml',
            ),
          ).firstWhere(
            (l) => l.raw == '1½ ounces Parmesan cheese, shredded (½ cup)',
          );
      final halfCup = parseIngredientLine('½ cup Parmesan cheese, shredded');
      expect(
        lineGrams(
          db,
          IngredientLine(
            raw: '½ cup Parmesan cheese, shredded',
            item: halfCup.item,
            amounts: halfCup.amounts,
          ),
          parmesanFood,
        )!.grams,
        closeTo(lineGrams(db, pizza, parmesanFood)!.grams, 0.01),
      );
      // A "plus" part printing its own weight: the soup's "(1 cup)" restates
      // it (the parse filed it under the rind).
      final soup = nutritionLines(
        loadCorpusRecipe(
          '0403-italian-chicken-soup-with-parmesan-dumplings.yaml',
        ),
      ).firstWhere((l) => l.raw.startsWith('1 Parmesan cheese rind, plus'));
      final plusPart = lineGrams(db, soup, parmesanFood)!;
      expect(
        (plusPart.grams.toStringAsFixed(2), plusPart.basis),
        ('85.05', 'from 3 ounce'),
      );
      // "(about 1 cup)" restates it the same (synthesized, a stated
      // exception: no corpus plus part prints one).
      final about = soup.raw.replaceFirst('(1 cup)', '(about 1 cup)');
      // (Its basis tells the rule from the shredded density, whose 1 cup
      // weighs the same.)
      expect(
        lineGrams(db, soup.copyWith(raw: about), parmesanFood)!.basis,
        'from 3 ounce',
      );
      // Only a part that prints a WEIGHT: a volume part's paren is the
      // line's total (0365 gnocchi), untouched.
      final gnocchi = nutritionLines(
        loadCorpusRecipe(
          '0365-potato-gnocchi-with-browned-butter-and-sage-sauce.yaml',
        ),
      ).firstWhere((l) => l.raw.startsWith('¾ cup plus 1 tablespoon (4'));
      final flour = lineGrams(db, gnocchi, await provider.food(789890))!;
      expect(
        (flour.grams.toStringAsFixed(2), flour.basis),
        (
          '113.40',
          'from 4 ounce',
        ),
      );
      // The same food's part is added once: 0419's line with its "(about
      // 2 cups; see note)" parsed as the soup's paren was (synthesized, a
      // stated exception: the corpus parse dropped it) still weighs ¼ cup
      // grated + 6 ounces — the restatement dropped, never the part twice;
      // and the line's own primary amount is never a restatement (the same
      // line read "2 cups grated …": its 2 cups stay).
      const crusted =
          '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 '
          'cups; see note)';
      final line = nutritionLines(
        loadCorpusRecipe('0419-parmesan-crusted-chicken-cutlets.yaml'),
      ).firstWhere((l) => l.raw == crusted);
      final paren = parseIngredientLine('2 cups').amounts.single;
      Amount secondary(Amount a) => Amount(
        measure: a.measure,
        quantity: a.quantity,
        unit: a.unit,
        approximate: a.approximate,
      );
      expect(
        lineGrams(
          db,
          line.copyWith(amounts: [...line.amounts, secondary(paren)]),
          parmesanFood,
        )!.grams.toStringAsFixed(2),
        '184.27',
      );
      final twoCups = crusted.replaceFirst('¼ cup', '2 cups');
      final cups = lineGrams(
        db,
        IngredientLine(
          raw: twoCups,
          item: line.item,
          amounts: [paren, secondary(paren)],
        ),
        parmesanFood,
      )!;
      expect(
        cups.grams,
        closeTo(2 * 236.59 * 28.35 / 118.29 + 6 * 28.3495, 0.1),
      );
      // Grated Parmesan the same (0.42 before: 24.84 g and 194.94 g): 0309
      // Philly Cheesesteaks, and 0419's grated quarter cup beside its
      // shredded 6 ounces (the weight part unchanged).
      final parmesan = (await provider.food(325036))!;
      for (final (file, raw, grams) in const [
        (
          '0309-philly-cheesesteaks.yaml',
          '¼ cup grated Parmesan cheese',
          '14.18',
        ),
        (
          '0419-parmesan-crusted-chicken-cutlets.yaml',
          '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 '
              'cups; see note)',
          '184.27',
        ),
      ]) {
        final line = nutritionLines(
          loadCorpusRecipe(file),
        ).firstWhere((l) => l.raw == raw);
        expect(
          lineGrams(db, line, parmesan)?.grams.toStringAsFixed(2),
          grams,
          reason: raw,
        );
      }
    },
    skip: skipIfNoCorpus,
  );

  test(
    '_asPrepared (Run 053 O3/O14): only a line naming the PREPARED form '
    "drops the record's unpopped portion — the ceviche's \"1 cup lightly "
    'salted popcorn" reads the popped cup (14 g); a line measuring the '
    'kernels keeps the yields cup (193 g a cup: the popped mass they make), '
    "as does a gelatin package's or a coconut's own yields portion",
    () async {
      final db = wp.tempDb();
      final provider = FixtureProvider();
      final popcorn = (await provider.food(2708216))!;
      double? grams(String raw, FdcFood food) =>
          lineGrams(db, wp.lineOf(raw), food)?.grams;
      // The corpus line (0274 Red Snapper Ceviche).
      final ceviche = nutritionLines(
        loadCorpusRecipe(
          '0274-red-snapper-ceviche-with-radishes-and-orange.yaml',
        ),
      ).firstWhere((l) => l.raw == '1 cup lightly salted popcorn');
      expect(lineGrams(db, ceviche, popcorn)?.grams, 14.0);
      // The keep side: lines no corpus recipe types (stated exception —
      // the O3 lines a person types), on the real records.
      for (final raw in const [
        '½ cup popcorn kernels',
        '½ cup unpopped popcorn',
        '½ cup popping corn',
      ]) {
        expect(grams(raw, popcorn), 96.5, reason: raw);
      }
      // The prepared side's other word, typed (no corpus line): popped corn
      // reads the popped cup.
      expect(grams('4 cups popped corn', popcorn), 56.0);
      // The record must have a popped portion to read instead: 2708216
      // without its '1 cup, popped' (a synthesized edit of the real record,
      // a stated exception) keeps the yields cup for the ceviche's line.
      final noPopped = FdcFood(
        fdcId: popcorn.fdcId,
        description: popcorn.description,
        dataType: popcorn.dataType,
        nutrientsPer100g: popcorn.nutrientsPer100g,
        portions: [
          for (final p in popcorn.portions)
            if (p.description != '1 cup, popped') p,
        ],
      );
      expect(lineGrams(db, ceviche, noPopped)?.grams, 193.0);
      expect(
        grams('1 package lemon gelatin', (await provider.food(2710310))!),
        540.0,
      );
      expect(grams('1 coconut', (await provider.food(2707572))!), 206.0);
    },
    skip: skipIfNoCorpus,
  );

  group('G3 (Run 053 O7/S5): R2 reads the fry from the directions', () {
    DiscardedMedium? mediumOf(Recipe r, String raw) {
      final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    test('held whatever the oil weighs: 0149 heats 1¾ cups (381 g) to 375 '
        'degrees, 0198 discards the oil it pan-fried in, 0288 pan-fries', () {
      for (final (file, raw) in const [
        (
          '0149-easier-fried-chicken.yaml',
          '2 cups unbleached all-purpose flour',
        ),
        ('0198-crispy-pan-fried-pork-chops.yaml', '⅔ cup cornstarch'),
        ('0288-maryland-crab-cakes.yaml', '¼ cup unbleached all-purpose flour'),
      ]) {
        expect(
          mediumOf(loadCorpusRecipe(file), raw),
          DiscardedMedium.coating,
          reason: file,
        );
      }
    }, skip: skipIfNoCorpus);

    test('NOT held: 0414 Marsala, a sauté whose coat no step shakes off. '
        'Since v33 (the dredge-reach ruling) a baked or sautéed dredge that '
        'leaves an excess — 0122 Kiev, 0206, 0254, 0418 piccata, 0420, '
        '0466 — is held (nutrition_v33_test.dart); since v53 (M52 Q24 b) '
        "0115 katsu's panko is held too: its cutlets are browned in the ¼ "
        'cup of oil heated for them, a shallow fry', () {
      expect(
        mediumOf(
          loadCorpusRecipe('0414-chicken-marsala.yaml'),
          '1 cup unbleached all-purpose flour',
        ),
        isNull,
      );
      // RE-PIN (M52 batch, v53): katsu was NOT held (pan-fried by its title
      // only); the shallow fry of a coated food is a fry (Q24 b).
      expect(
        mediumOf(
          loadCorpusRecipe(
            '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml',
          ),
          '2 cups panko bread crumbs',
        ),
        DiscardedMedium.coating,
      );
    }, skip: skipIfNoCorpus);

    test('the oil a held dredge fries in is frying oil by the same '
        'directions (closer D2), whatever it weighs: 0149 "1¾ cups vegetable '
        'oil" (381 g, "to 375 degrees"), 0198 "⅔ cup vegetable oil" '
        '("Discard the oil") — 0 g discarded; 0042\'s dressing tablespoons '
        'counted and 0288 held (v31); 0114 '
        'keeps the tablespoon beaten into the eggs; 0116 unchanged ("2 cups '
        '… for frying" zero, its egg-wash tablespoon counted); a sauté\'s '
        '¼ cup (0418 piccata, no fry) counted', () async {
      final oil = (await FixtureProvider().food(2710180))!;
      double? gramsOf(String file, String raw) {
        final r = loadCorpusRecipe(file);
        final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
        final whole = resolveGrams(
          amounts: line.amounts,
          food: oil,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        );
        final out = engineOutcome(r, line, oil, whole, picked: true);
        return out.source == 'discarded' ? out.grams : null;
      }

      for (final (file, raw) in const [
        ('0149-easier-fried-chicken.yaml', '1¾ cups vegetable oil'),
        ('0198-crispy-pan-fried-pork-chops.yaml', '⅔ cup vegetable oil'),
        ('0116-chicken-schnitzel.yaml', '2 cups vegetable oil for frying'),
      ]) {
        expect(
          mediumOf(loadCorpusRecipe(file), raw),
          DiscardedMedium.fryingOil,
          reason: file,
        );
        expect(gramsOf(file, raw), 0, reason: file);
      }
      // Since matcher v31 (the owner's R4 rulings): 0042's ¾ cup fries and
      // is discarded, its 2 tablespoons the dressing eats count ("1
      // tablespoon more oil", "the remaining 1 tablespoon oil" after the
      // last discard); 0288's pan-fry oil, fried by the verb alone, is
      // held for a person (ambiguous_medium), no longer zeroed.
      const almond =
          '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml';
      const almondOil = '¾ cup plus 2 tablespoons vegetable oil';
      expect(
        mediumOf(loadCorpusRecipe(almond), almondOil),
        DiscardedMedium.fryingOil,
      );
      expect(
        gramsOf(almond, almondOil),
        resolveGrams(
          amounts: parseIngredientLine('2 tablespoons vegetable oil').amounts,
          food: oil,
          normalizedItem: 'vegetable oil',
        )!.grams,
      );
      // RE-PIN (M52 batch, v53, Q24 b): heated for the coated cakes it
      // browns, 0288's oil is their frying oil (was ambiguous_medium).
      expect(
        mediumOf(
          loadCorpusRecipe('0288-maryland-crab-cakes.yaml'),
          '¼ cup vegetable oil',
        ),
        DiscardedMedium.fryingOil,
      );
      const cutlets = '0114-breaded-chicken-cutlets.yaml';
      const both = '1 tablespoon plus ¾ cup vegetable oil';
      expect(
        mediumOf(loadCorpusRecipe(cutlets), both),
        DiscardedMedium.fryingOil,
      );
      final tablespoon = resolveGrams(
        amounts: parseIngredientLine('1 tablespoon vegetable oil').amounts,
        food: oil,
        normalizedItem: 'vegetable oil',
      )!.grams;
      expect(gramsOf(cutlets, both), tablespoon);
      final r = loadCorpusRecipe(cutlets);
      final line = nutritionLines(r).firstWhere((l) => l.raw == both);
      expect(
        gramBasisFor(
          wp.tempDb(),
          line,
          IngredientMatchRow(
            recipeId: r.id,
            position: 5,
            raw: both,
            fdcId: oil.fdcId,
            description: oil.description,
            dataType: oil.dataType,
            confidence: 1,
            grams: tablespoon,
            gramSource: 'discarded',
            status: 'auto',
          ),
          recipe: r,
        ),
        'discarded in cooking — only "1 tablespoon" counted',
      );
      for (final (file, raw) in const [
        ('0116-chicken-schnitzel.yaml', '1 tablespoon vegetable oil'),
        ('0418-chicken-piccata.yaml', '4 tablespoons vegetable oil'),
      ]) {
        expect(mediumOf(loadCorpusRecipe(file), raw), isNull, reason: file);
      }
    }, skip: skipIfNoCorpus);

    test('the guards, on real recipes edited (synthesized, a stated '
        'exception: no library line reaches them) — a dredge "for dredging" '
        "in a recipe that does not fry (0418 piccata's flour so marked) "
        "leaves its sauté oil counted; a plus line's LARGER first part a "
        'step names is never the eaten part (0149 as "1¾ cups plus 1 '
        'tablespoon", heated as "1¾ cups oil": all of it 0 g)', () async {
      final piccata = loadCorpusRecipe('0418-chicken-piccata.yaml');
      final marked = piccata.copyWith(
        ingredients: [
          for (final group in piccata.ingredients)
            group.copyWith(
              items: [
                for (final line in group.items)
                  line.raw == '½ cup unbleached all-purpose flour'
                      ? line.copyWith(raw: '${line.raw} for dredging')
                      : line,
              ],
            ),
        ],
      );
      expect(
        mediumOf(marked, '½ cup unbleached all-purpose flour for dredging'),
        DiscardedMedium.coating,
      );
      expect(mediumOf(marked, '4 tablespoons vegetable oil'), isNull);
      final fried = loadCorpusRecipe('0149-easier-fried-chicken.yaml');
      const both = '1¾ cups plus 1 tablespoon vegetable oil';
      final parsed = parseIngredientLine(both);
      final edited = fried.copyWith(
        ingredients: [
          for (final group in fried.ingredients)
            group.copyWith(
              items: [
                for (final line in group.items)
                  line.raw == '1¾ cups vegetable oil'
                      ? IngredientLine(
                          raw: both,
                          item: parsed.item,
                          amounts: parsed.amounts,
                        )
                      : line,
              ],
            ),
        ],
        steps: [
          for (final step in fried.steps)
            step.copyWith(
              text: step.text.replaceAll('Heat the oil', 'Heat 1¾ cups oil'),
            ),
        ],
      );
      final line = nutritionLines(edited).firstWhere((l) => l.raw == both);
      final oil = (await FixtureProvider().food(2710180))!;
      final out = engineOutcome(
        edited,
        line,
        oil,
        resolveGrams(
          amounts: line.amounts,
          food: oil,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        ),
        picked: true,
      );
      expect((out.grams, out.source), (0, 'discarded'));
    }, skip: skipIfNoCorpus);

    test('1133 Francese has two fry signals, each enough alone — its oils '
        '"for frying" and "Discard oil." — and since v33 a third, its excess '
        'sentence (synthesized edits, a stated exception: each removes the '
        'others)', () {
      final francese = loadCorpusRecipe('1133-chicken-francese.yaml');
      const flour = '¾ cup all-purpose flour, divided';
      final noDiscard = francese.copyWith(
        steps: [
          for (final step in francese.steps)
            step.copyWith(text: step.text.replaceAll('Discard oil.', '')),
        ],
      );
      expect(mediumOf(noDiscard, flour), DiscardedMedium.coating);
      final noForFrying = francese.copyWith(
        ingredients: [
          for (final group in francese.ingredients)
            group.copyWith(
              items: [
                for (final line in group.items)
                  line.copyWith(raw: line.raw.replaceAll(' for frying', '')),
              ],
            ),
        ],
      );
      expect(mediumOf(noForFrying, flour), DiscardedMedium.coating);
      final neither = noForFrying.copyWith(steps: noDiscard.steps);
      // v33: with neither fry signal its excess sentence holds it ("dredge
      // cutlets in flour, shaking gently to remove excess"); without that
      // too, nothing does.
      expect(mediumOf(neither, flour), DiscardedMedium.coating);
      final noExcess = neither.copyWith(
        steps: [
          for (final step in neither.steps)
            step.copyWith(
              text: step.text.replaceAll(
                ', shaking gently to remove excess',
                '',
              ),
            ),
        ],
      );
      // RE-PIN (M52 batch, v53, Q24 b): a fourth — the coated cutlets
      // browned in the ⅓-cup oils heated for them; with the browning gone
      // too (the same stated exception), nothing holds it.
      expect(mediumOf(noExcess, flour), DiscardedMedium.coating);
      final noBrown = noExcess.copyWith(
        steps: [
          for (final step in noExcess.steps)
            step.copyWith(
              text: step.text.replaceAll('golden brown', 'cooked through'),
            ),
        ],
      );
      expect(mediumOf(noBrown, flour), isNull);
    }, skip: skipIfNoCorpus);
  });

  _divided();
  _sqlLists();
  _vocabulary();

  group('G6 (Run 053 O8, S7): every eaten-in-part hold at the PUT', () {
    // (file, position, hold): the corpus's held lines, one per kind.
    // RE-PIN (M52 batch, v53): the coat is 0418 piccata's sautéed dusting
    // (C4, still held); 0148's fried dredge is counted by the coat budget
    // since v53 (a person's pick on it still derives the hold:
    // nutrition_v24_rules_test H5(a)).
    const kinds = [
      ('0799-sourdough-starter.yaml', 0, 'starter_discard'),
      ('0129-mahogany-chicken-thighs.yaml', 1, 'partial_pour_away'),
      ('0418-chicken-piccata.yaml', 3, 'coating'),
    ];

    Future<(SaltDatabase, FixtureProvider, Recipe)> computed(
      String file,
    ) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe(file);
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      return (db, provider, r);
    }

    test('a pick alone keeps the hold (no grams, the picked food, '
        'overridden): 0 g would drop the eaten part with no flag', () async {
      for (final (file, i, hold) in kinds) {
        final (db, provider, r) = await computed(file);
        final held = db.ingredientMatchesFor(r.id)[i];
        expect(held.hold, hold, reason: file);
        await applyMatchOverride(db, provider, r, i, {
          'raw': held.raw,
          'fdc_id': held.fdcId,
        });
        final row = db.ingredientMatchesFor(r.id)[i];
        expect(
          (row.fdcId, row.grams, row.hold, row.status),
          (held.fdcId, null, hold, 'overridden'),
          reason: file,
        );
      }
    }, skip: skipIfNoCorpus);

    test('a pick alone keeps the hold through an amount edit too '
        '(editedDecisionRow): the compute writes what a pick on the edited '
        'line writes — overridden, no grams, the hold — never 0 g poured '
        'away; 0418 stays partial (the edit synthesized, a stated '
        'exception: the first amount changed)', () async {
      for (final (file, i, hold) in kinds) {
        final (db, provider, r) = await computed(file);
        final held = db.ingredientMatchesFor(r.id)[i];
        await applyMatchOverride(db, provider, r, i, {
          'raw': held.raw,
          'fdc_id': held.fdcId,
        });
        final edited = editedLine(r, held.raw);
        wp.saveRecipe(db, edited);
        await matchAndCompute(db, provider, edited);
        final row = db.ingredientMatchesFor(r.id)[i];
        expect(row.raw, isNot(held.raw), reason: file);
        expect(
          (row.fdcId, row.status, row.grams, row.gramSource, row.hold),
          (held.fdcId, 'overridden', null, null, hold),
          reason: file,
        );
        // The same outcome as a pick made on the edited line itself.
        final (db2, provider2, _) = await computed(file);
        wp.saveRecipe(db2, edited);
        await matchAndCompute(db2, provider2, edited);
        final line2 = db2.ingredientMatchesFor(r.id)[i];
        await applyMatchOverride(db2, provider2, edited, i, {
          'raw': line2.raw,
          'fdc_id': held.fdcId,
        });
        final picked = db2.ingredientMatchesFor(r.id)[i];
        expect(
          (picked.status, picked.grams, picked.gramSource, picked.hold),
          (row.status, row.grams, row.gramSource, row.hold),
          reason: file,
        );
        if (file.startsWith('0418')) {
          expect(db.nutritionFor(r.id)!.status, 'partial');
        }
      }
    }, skip: skipIfNoCorpus);

    test(
      'a pick with typed grams counts them and answers the hold',
      () async {
        for (final (file, i, _) in kinds) {
          final (db, provider, r) = await computed(file);
          final held = db.ingredientMatchesFor(r.id)[i];
          await applyMatchOverride(db, provider, r, i, {
            'raw': held.raw,
            'fdc_id': held.fdcId,
            'grams': 10,
          });
          final row = db.ingredientMatchesFor(r.id)[i];
          expect(
            (row.grams, row.gramSource, row.hold),
            (10, 'override', null),
            reason: file,
          );
        }
      },
      skip: skipIfNoCorpus,
    );

    test(
      'a confirm is poured away, 0 g (the confirm site), and stays so '
      'through an amount edit, the hold resolved (derivedFor, RULE A) — '
      'the edit synthesized (a stated exception): the first amount halved',
      () async {
        for (final (file, i, hold) in kinds) {
          final (db, provider, r) = await computed(file);
          final held = db.ingredientMatchesFor(r.id)[i];
          await applyMatchOverride(db, provider, r, i, {
            'raw': held.raw,
            'confirmed': true,
          });
          var row = db.ingredientMatchesFor(r.id)[i];
          expect((row.grams, row.gramSource), (0, 'discarded'), reason: file);
          final edited = editedLine(r, held.raw);
          wp.saveRecipe(db, edited);
          await matchAndCompute(db, provider, edited);
          row = db.ingredientMatchesFor(r.id)[i];
          expect(row.raw, isNot(held.raw), reason: file);
          // RULE A (v25, Run 055 I1): the confirm resolves the hold at the
          // PUT and at every compute alike — 0 g poured away, no hold.
          expect(
            (row.status, row.grams, row.gramSource, row.hold),
            ('confirmed', 0, 'discarded', null),
            reason: '$file $hold',
          );
        }
      },
      skip: skipIfNoCorpus,
    );

    test('RULE A (v25, Run 055 O5; was "a confirm reads the STORED hold '
        "too\"): 0799 and 0129 Mahogany with steps edited so today's detector "
        "no longer holds (synthesized, a stated exception: the feeding's "
        '"discard" and the strainer reworded) — a confirm is the food at its '
        'weight now, never 0 g poured away for a hold the recipe no longer '
        'has', () async {
      for (final (file, i, _) in kinds.take(2)) {
        final (db, provider, r) = await computed(file);
        final held = db.ingredientMatchesFor(r.id)[i];
        final edited = r.copyWith(
          steps: [
            for (final step in r.steps)
              step.copyWith(
                text: step.text
                    .replaceAll(RegExp('discard', caseSensitive: false), 'keep')
                    .replaceAll('strainer', 'sieve'),
              ),
          ],
        );
        final line = nutritionLines(edited)[i];
        expect(
          discardedMediumOf(edited, line, normalizeItem(lineItemOf(line))),
          isNull,
          reason: file,
        );
        wp.saveRecipe(db, edited);
        await applyMatchOverride(db, provider, edited, i, {
          'raw': held.raw,
          'confirmed': true,
        });
        final row = db.ingredientMatchesFor(r.id)[i];
        expect(row.grams, greaterThan(0), reason: file);
        expect(row.gramSource, isNot('discarded'), reason: file);
        expect(row.hold, isNull, reason: file);
      }
    }, skip: skipIfNoCorpus);
  });
}

void _divided() {
  test("G6 (Run 053 O9): a divided line's part used outside the medium is "
      "eaten — held with the line, its grams that part (as a plus line's): "
      '1133 Francese\'s "¾ cup all-purpose flour, divided" (1 teaspoon '
      'tossed with the butter for the sauce) and 0129 Indoor Pulled '
      'Chicken\'s "1 tablespoon liquid smoke, divided" ("remaining 1 '
      'teaspoon" added after the strain), and 0279\'s shrimp toss; a dredge '
      'with no such part (0148, 0198) stays held with none', () async {
    final provider = FixtureProvider();
    const notes = {
      '1133-chicken-francese.yaml':
          '1 teaspoon flour is used outside the dredge, eaten',
      '0129-indoor-pulled-chicken.yaml':
          '½ cup reserved defatted liquid; 1 teaspoon liquid smoke is used '
          'outside the braise, eaten',
      '0279-crispy-salt-and-pepper-shrimp.yaml':
          '3 tablespoons cornstarch is used outside the dredge, eaten',
    };
    for (final (file, raw, fdcId, hold, eaten) in [
      (
        '1133-chicken-francese.yaml',
        '¾ cup all-purpose flour, divided',
        789890,
        'coating',
        '1 teaspoon all-purpose flour',
      ),
      (
        '0129-indoor-pulled-chicken.yaml',
        '1 tablespoon liquid smoke, divided',
        167682,
        'partial_pour_away',
        '1 teaspoon liquid smoke',
      ),
      (
        '0148-crispy-fried-chicken.yaml',
        '4 cups (20 ounces) unbleached all-purpose flour',
        789890,
        'coating',
        null,
      ),
      // The same reading reaches one more line: 0279's 3 tablespoons
      // tossed onto the shrimp "until well combined" (eaten whole, as
      // 0536's toss is) apart from the 2 shaken off the jalapeños.
      (
        '0279-crispy-salt-and-pepper-shrimp.yaml',
        '5 tablespoons cornstarch',
        169698,
        'coating',
        '3 tablespoons cornstarch',
      ),
      // A step that dredges is the medium's whole: 0198's "remaining ⅓ cup
      // cornstarch" goes into the cornflake crumbs (a step with a shallow
      // dish), never eaten apart.
      (
        '0198-crispy-pan-fried-pork-chops.yaml',
        '⅔ cup cornstarch',
        169698,
        'coating',
        null,
      ),
    ]) {
      final r = loadCorpusRecipe(file);
      final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
      final food = (await provider.food(fdcId))!;
      final normalized = normalizeItem(lineItemOf(line));
      final whole = resolveGrams(
        amounts: line.amounts,
        food: food,
        normalizedItem: normalized,
        raw: line.raw,
      );
      final out = engineOutcome(r, line, food, whole, picked: true);
      final part = eaten == null
          ? null
          : resolveGrams(
              amounts: parseIngredientLine(eaten).amounts,
              food: food,
              normalizedItem: normalized,
            )!.grams;
      expect(out.hold, hold, reason: file);
      expect(out.grams, part, reason: file);
      // The GET's hold_note names the eaten part, as written (closer D5).
      expect(holdNoteOf(r, line, hold), notes[file], reason: file);
      if (part != null) {
        expect((part > 0, part < whole!.grams), (true, true), reason: file);
      }
    }
  }, skip: skipIfNoCorpus);

  test("the matches GET names a divided dredge's eaten part — since v53 "
      '(M52 Q2 a) counted with the coat budget, unheld: 1133 Francese #5 '
      '(its held reading, the eaten part and its hold_note, is the engine '
      "outcome's above)", () async {
    final db = wp.tempDb();
    final r = loadCorpusRecipe('1133-chicken-francese.yaml');
    wp.saveRecipe(db, r);
    final provider = FixtureProvider(pending: pendingSearches);
    await matchAndCompute(db, provider, r);
    final items = ((await matchesBody(db, provider, r))['items']! as List)
        .cast<Map<String, Object?>>();
    final match = items[5]['match']! as Map<String, Object?>;
    // RE-PIN (M52 batch, v53): was held `coating` at the eaten 2.51 g; now
    // the eaten teaspoon + f × the ¾ cup's dredge: B = 793.79 g of breasts
    // × C1 5.73 / 100 = 45.48 g carbohydrate → 61.35 g.
    expect(
      (match['hold'], match['hold_note'], match['gram_source']),
      (null, null, 'discarded'),
    );
    expect(match['grams'], closeTo(61.35, 0.01));
    expect(
      match['gram_basis'],
      'discarded in cooking — only the part the recipe keeps and the coat on '
      'the food counted · approximation (coat: 5.73 g carbohydrate per 100 g '
      'of the raw chicken breast — USDA FNDDS 2705975 recipe: 15 g breading '
      "per 104.76 g raw chicken breast; the dredge's excess not counted)",
    );
  }, skip: skipIfNoCorpus);
}

void _sqlLists() {
  test('S9: starter_discard and partial_pour_away in the three SQL lists — '
      "0799's held all-purpose flour and 0129 Mahogany's held soy sauce "
      'beside an unheld line of the same key (a one-line recipe of a real '
      'corpus line, a stated exception): each held row a group of one, out '
      "of the other line's reach, and never marked decided by its "
      'decision', () async {
    for (final (file, i, other) in const [
      ('0799-sourdough-starter.yaml', 1, '1 cup all-purpose flour'),
      ('0129-mahogany-chicken-thighs.yaml', 1, '2 tablespoons soy sauce'),
    ]) {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe(file);
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      // A second copy (synthesized, the digest's "second sourdough starter
      // recipe") saved again with its steps reworded so today's detector
      // no longer holds the line (as in the confirm pin above), its rows
      // not yet recomputed: only the STORED hold keeps it out.
      final copy = r.copyWith(id: 'r2', slug: 'r2');
      wp.saveRecipe(db, copy);
      await matchAndCompute(db, provider, copy);
      final reworded = copy.copyWith(
        steps: [
          for (final step in copy.steps)
            step.copyWith(
              text: step.text
                  .replaceAll(RegExp('discard', caseSensitive: false), 'keep')
                  .replaceAll('strainer', 'sieve'),
            ),
        ],
      );
      final line = nutritionLines(reworded)[i];
      expect(
        discardedMediumOf(reworded, line, normalizeItem(lineItemOf(line))),
        isNull,
        reason: file,
      );
      wp.saveRecipe(db, reworded);
      final o = wp.saveLines(db, [other], id: 'o');
      await matchAndCompute(db, provider, o);
      final held = db.ingredientMatchesFor(r.id)[i];
      final plain = db.ingredientMatchesFor('o').single;
      expect(held.hold, isNotNull, reason: file);
      expect((plain.hold, plain.itemKey), (null, held.itemKey), reason: file);
      final key = held.itemKey!;
      List<int> groupLines() => [
        for (final group in db.nutritionReviewGroups(limit: 500, offset: 0))
          if (group.itemKey == key) group.lines,
      ]..sort();
      // The group-of-one key: the two held rows are two groups.
      expect(groupLines(), [1, 1], reason: file);
      // The reach: the unheld line's offer counts no held row.
      final item =
          ((await matchesBody(db, provider, o))['items']! as List).single
              as Map;
      expect((item['others'], item['others_lines']), (0, 0), reason: file);
      await applyMatchOverride(db, provider, o, 0, {
        'raw': other,
        'fdc_id': plain.fdcId,
        'apply_to_all': true,
      });
      for (final id in [r.id, 'r2']) {
        final after = db.ingredientMatchesFor(id)[i];
        expect(
          (after.hold, after.status, after.grams),
          (held.hold, 'auto', held.grams),
          reason: '$file $id',
        );
      }
      // The decided flag: the decision on the key never marks it decided.
      for (final group
          in db
              .nutritionReviewGroups(limit: 500, offset: 0)
              .where((g) => g.itemKey == key)) {
        expect(group.decided, isFalse, reason: file);
      }
    }
  }, skip: skipIfNoCorpus);
}

/// [r] edited (the S13/O13 pins' synthesized edits): its steps through
/// [steps], its lines' text through [lines] (re-parsed), [extra] lines
/// appended.
Recipe _edit(
  Recipe r, {
  String Function(String)? steps,
  String Function(String)? lines,
  List<String> extra = const [],
}) {
  IngredientLine parsed(String raw) {
    final p = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
  }

  return r.copyWith(
    ingredients: [
      for (final group in r.ingredients)
        group.copyWith(
          items: [
            for (final item in group.items)
              lines == null || lines(item.raw) == item.raw
                  ? item
                  : parsed(lines(item.raw)),
            if (identical(group, r.ingredients.first))
              for (final raw in extra) parsed(raw),
          ],
        ),
    ],
    steps: [
      for (final step in r.steps)
        step.copyWith(text: steps == null ? step.text : steps(step.text)),
    ],
  );
}

DiscardedMedium? _mediumOf(Recipe r, String raw, {bool bySentence = true}) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(
    r,
    line,
    normalizeItem(lineItemOf(line)),
    bySentence: bySentence,
  );
}

void _vocabulary() {
  group("S13/O13: the detectors' kept words and guards, each on a real "
      'recipe edited (synthesized, the stated exception: no library line '
      'reaches them)', () {
    test("R2 'starch' (the ruling's own word): 0527 Karaage's dredge as "
        'potato starch is held; a line "for coating" is one', () {
      final karaage = _edit(
        loadCorpusRecipe('0527-karaage-japanese-fried-chicken-thighs.yaml'),
        steps: (t) => t.replaceAll('cornstarch', 'potato starch'),
        lines: (raw) => raw.replaceAll('cornstarch', 'potato starch'),
      );
      expect(
        _mediumOf(karaage, '1¼ cups potato starch'),
        DiscardedMedium.coating,
      );
      final forCoating = _edit(
        loadCorpusRecipe('0122-chicken-kiev.yaml'),
        lines: (raw) => raw == '1 cup unbleached all-purpose flour'
            ? '1 cup unbleached all-purpose flour, for coating'
            : raw,
      );
      expect(
        _mediumOf(
          forCoating,
          '1 cup unbleached all-purpose flour, for coating',
        ),
        DiscardedMedium.coating,
      );
    }, skip: skipIfNoCorpus);

    test('R4: the braise mixture is opened BEFORE the strain (a "whisk … '
        'add" pair after it names no braise line), and the kept part is '
        'written AFTER it (a pre-strain "1 cup cooking liquid" keeps '
        'nothing) — 0129 Mahogany edited', () {
      final mahogany = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      final honey = _edit(
        mahogany,
        extra: ['2 tablespoons honey'],
        steps: (t) => t.replaceAll(
          'Pour sauce into bowl and set aside for serving.',
          'Pour sauce into bowl and set aside for serving. Whisk honey '
              'into sauce. Add chicken to sauce.',
        ),
      );
      expect(_mediumOf(honey, '1 cup soy sauce'), isNotNull);
      expect(_mediumOf(honey, '2 tablespoons honey'), isNull);
      final early = _edit(
        mahogany,
        steps: (t) => t
            .replaceAll(
              'Pour 1 cup defatted cooking liquid',
              'Pour defatted cooking liquid',
            )
            .replaceAll(
              'simmer for 5 minutes.',
              'simmer for 5 minutes. Reserve 1 cup cooking liquid.',
            ),
      );
      expect(_mediumOf(early, '1 cup soy sauce'), isNull);
    }, skip: skipIfNoCorpus);

    test("R3 on 0090's rub: a sugar the rub sentence names is a rinsed "
        'cure too (brineSugar), one it never names is not; a sentence that '
        'only mentions a rinse ("Do not rinse …") is none; a rinse in the '
        "rub's own step counts", () {
      final beef = loadCorpusRecipe(
        '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml',
      );
      final named = _edit(
        beef,
        extra: ['¼ cup sugar'],
        steps: (t) => t.replaceAll(
          'Rub each side evenly with salt mixture.',
          'Rub each side evenly with salt and sugar mixture.',
        ),
      );
      expect(_mediumOf(named, '¼ cup sugar'), DiscardedMedium.brineSugar);
      expect(_mediumOf(named, '½ cup kosher salt'), DiscardedMedium.brine);
      final unnamed = _edit(beef, extra: ['¼ cup sugar']);
      expect(
        _mediumOf(unnamed, '¼ cup sugar'),
        isNot(DiscardedMedium.brineSugar),
      );
      final notRinsed = _edit(
        beef,
        steps: (t) => t.replaceAll(
          'Rinse brisket and pat it dry.',
          'Do not rinse brisket; pat it dry.',
        ),
      );
      expect(
        _mediumOf(notRinsed, '½ cup kosher salt'),
        isNot(DiscardedMedium.brine),
      );
      final oneStep = beef.copyWith(
        steps: [
          beef.steps.first.copyWith(
            text: [for (final step in beef.steps) step.text].join(' '),
          ),
        ],
      );
      expect(_mediumOf(oneStep, '½ cup kosher salt'), DiscardedMedium.brine);
    }, skip: skipIfNoCorpus);

    test('the head-only read other rules make of another line '
        "(bySentence: false) never sees a sentence ruling: 0090's rinsed "
        "cure, 0799's feeding", () {
      expect(
        _mediumOf(
          loadCorpusRecipe(
            '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml',
          ),
          '½ cup kosher salt',
          bySentence: false,
        ),
        isNull,
      );
      expect(
        _mediumOf(
          loadCorpusRecipe('0799-sourdough-starter.yaml'),
          '4½ cups (24¾ ounces) whole-wheat flour',
          bySentence: false,
        ),
        isNull,
      );
    }, skip: skipIfNoCorpus);
  });
}

/// [r] with its line [raw]'s leading amount replaced by a different one —
/// the synthesized amount edit of the G6 pins.
Recipe editedLine(Recipe r, String raw) {
  final next = raw
      .replaceFirst('4½ cups (24¾ ounces)', '4 cups (22 ounces)')
      .replaceFirst('1 cup soy sauce', '¾ cup soy sauce')
      .replaceFirst('4 cups (20 ounces)', '5 cups (25 ounces)')
      // RE-PIN (M52 batch, v53): G6's coat is 0418 piccata's dusting.
      .replaceFirst('½ cup unbleached', '¾ cup unbleached');
  final parsed = parseIngredientLine(next);
  return r.copyWith(
    ingredients: [
      for (final group in r.ingredients)
        group.copyWith(
          items: [
            for (final item in group.items)
              item.raw == raw
                  ? IngredientLine(
                      raw: next,
                      item: parsed.item,
                      amounts: parsed.amounts,
                    )
                  : item,
          ],
        ),
    ],
  );
}
