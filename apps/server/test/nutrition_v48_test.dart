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

/// Batch M48 (matcherVersion 47; the owner's 2026-10-07 re-ruling of
/// checkpoint 9 Q5, prep47 design_v2 §1 Q1 = (c)): every printed weight
/// RANGE reads its midpoint — hyphenated, "A to B" with a fraction, the en
/// dash, a spaced mixed number — as the whole-number "A to B" and a bare
/// range already did; reversed bounds keep the larger; the basis names the
/// range, no approximation flag. Each line is a real corpus line; the
/// in-recipe rows are the cache-only replay of snapshot 21 at M48.
void main() {
  // The engine's own unit figures (grams.dart `_weightUnitGrams`).
  const ounce = 28.3495;
  const pound = 453.592;

  GramResolution? gramsOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return resolveGrams(
      amounts: parsed.amounts,
      food: null,
      normalizedItem: normalizeItem(parsed.item ?? raw),
      raw: raw,
    );
  }

  group('the rule', () {
    test('every spelling reads its midpoint', () {
      for (final (raw, grams) in [
        // Hyphenated (was the top, B2).
        ('8 (5- to 7-ounce) bone-in chicken thighs, trimmed', 6 * ounce),
        (
          '1 (12- to 14-pound) turkey, giblets and neck reserved for gravy, if making',
          13 * pound,
        ),
        // A fraction, hyphenated and "to" (was the top, the switch's false).
        ('1 (3½- to 4-pound) whole chicken', 3.75 * pound),
        (
          '1¾–2 cups (8¾ to 10 ounces) unbleached all-purpose flour, plus extra for the work surface',
          9.375 * ounce,
        ),
        // The en dash (was "22 pounds" alone: the regex never saw the range).
        (
          '1 turkey (12–22 pounds gross weight), rinsed thoroughly, giblets and neck reserved for gravy, if making',
          17 * pound,
        ),
        // A spaced mixed number (would read ½ to 4 without the fold).
        (
          '1 (3 ½- to 4-pound) boneless beef chuck-eye roast, pulled into 2 pieces at natural seam and trimmed of large pieces of fat',
          3.75 * pound,
        ),
        // Whole-number "A to B": the midpoint it always read.
        (
          '4 (5 to 6-ounce) boneless, skinless chicken breasts, trimmed',
          5.5 * ounce,
        ),
      ]) {
        expect(parenWeightGrams(raw), closeTo(grams, 1e-6), reason: raw);
      }
    });

    test('one range, one figure: the hyphenated twin reads its "to" twin', () {
      expect(
        parenWeightGrams(
          '4 (10- to 12-ounce) bone-in split chicken breasts, trimmed',
        ),
        parenWeightGrams('4 (10 to 12-ounce) bone-in, split chicken breasts'),
      );
      expect(
        parenWeightGrams('4 (10 to 12-ounce) bone-in, split chicken breasts'),
        closeTo(11 * ounce, 1e-6),
      );
    });

    test('reversed bounds keep the larger (the corpus typo "14⅔ to 6½")', () {
      expect(
        parenWeightGrams('2⅔–3 cups (14⅔ to 6½ ounces) bread flour'),
        closeTo((14 + 2 / 3) * ounce, 1e-6),
      );
      expect(
        gramsOf('2⅔–3 cups (14⅔ to 6½ ounces) bread flour')!.basis,
        'from the printed weight',
      );
    });

    // STATED SYNTHESIZED negatives (closer round 1, verify1 D1 + obs. 1): the
    // corpus prints no other reversed range and no other spaced mixed
    // number in a parenthesis, so these inputs cannot come from it.
    test('reversed bounds keep the larger on every path, not the paren '
        'alone (v47 read a bare one at its midpoint)', () {
      final bare = gramsOf('6½–4 ounces bread flour')!;
      expect(bare.grams, closeTo(6.5 * ounce, 1e-6)); // v47: 5¼ oz
      expect(bare.basis, 'from 6 1/2–4 ounce'); // no "(the midpoint)"
      expect(countOf(parseIngredientLine('3–2 lemons').amounts), 3); // v47: 2.5
    });

    test('a spaced mixed number folds outside a range too', () {
      expect(
        parenWeightGrams('1 (1 ½-pound) butternut squash'),
        closeTo(1.5 * pound, 1e-6), // v47 and unfolded: ½ lb
      );
    });

    // STATED SYNTHESIZED inputs (closer round 2, verify2 D1): the corpus raws
    // print no ASCII fraction, but the editor and other libraries do ("3
    // 1/2") and the raw is never normalized, so these spellings cannot come
    // from the corpus. Before: a bound's number held no space, so "(3 1/2-
    // to 4-pound)" read "1/2- to 4" — ½–4 lb at its midpoint, 2.25 lb.
    test('an ASCII mixed-number bound reads whole, both bounds', () {
      for (final (raw, grams, basis) in [
        (
          '1 (3 1/2- to 4-pound) whole chicken',
          3.75 * pound,
          'from the printed weight (3 1/2–4 lb, the midpoint)',
        ),
        (
          '1 whole chicken (3 1/2–4 pounds)',
          3.75 * pound,
          'from the printed weight (3 1/2–4 lb, the midpoint)',
        ),
        (
          '4 (1 1/4- to 1 1/2-pound) Cornish game hens',
          4 * 1.375 * pound,
          '4 × 624 g (printed 1 1/4–1 1/2 lb, the midpoint)',
        ),
        // A single weight follows (was ½ lb).
        (
          '1 (3 1/2-pound) whole chicken',
          3.5 * pound,
          'from the printed weight',
        ),
      ]) {
        final resolved = gramsOf(raw)!;
        expect(resolved.grams, closeTo(grams, 1e-6), reason: raw);
        expect(resolved.basis, basis, reason: raw);
      }
    });

    test('the basis names the range read at its midpoint; no flag', () {
      for (final (raw, grams, basis) in [
        (
          '8 (5- to 7-ounce) bone-in chicken thighs, trimmed',
          8 * 6 * ounce,
          '8 × 170 g (printed 5–7 oz, the midpoint)',
        ),
        (
          '1 turkey (12–22 pounds gross weight), rinsed thoroughly, giblets and neck reserved for gravy, if making',
          17 * pound,
          'from the printed weight (12–22 lb, the midpoint)',
        ),
        (
          '1 (3½- to 4½-pound) boneless eye-round roast',
          4 * pound,
          'from the printed weight (3½–4½ lb, the midpoint)',
        ),
        (
          '1¾–2 cups (8¾ to 10 ounces) unbleached all-purpose flour, plus extra for the work surface',
          9.375 * ounce,
          'from the printed weight (8¾–10 oz, the midpoint)',
        ),
        (
          '4 (5 to 6-ounce) boneless, skinless chicken breasts, trimmed',
          4 * 5.5 * ounce,
          '4 × 156 g (printed 5–6 oz, the midpoint)',
        ),
        // A bare range: the amount as written, then the midpoint.
        (
          '1½–2 pounds bone-in chicken thighs',
          1.75 * pound,
          'from 1 1/2–2 pound (the midpoint)',
        ),
        (
          '14–16 ounces (⅛-inch-wide) rice noodles',
          15 * ounce,
          'from 14–16 ounce (the midpoint)',
        ),
        // A single printed weight names no range.
        (
          '1 (4-pound) whole chicken, giblets discarded',
          4 * pound,
          'from the printed weight',
        ),
        (
          '4 (6-ounce) skinless cod fillets, about 1 inch thick',
          4 * 6 * ounce,
          '4 × 170 g (printed weight)',
        ),
      ]) {
        final resolved = gramsOf(raw)!;
        expect(resolved.grams, closeTo(grams, 1e-6), reason: raw);
        expect(resolved.basis, basis, reason: raw);
        expect(resolved.basis, isNot(contains('approximat')), reason: raw);
      }
    });

    test('the two roasts the fixtures hold no answer for, at the resolver: '
        'neither reads its record (no yield), so the replay figure stands', () {
      for (final (raw, grams, basis) in [
        // slow-roasted-beef|0, v47 2,041.16 (4½ lb).
        (
          '1 (3½- to 4½-pound) boneless eye-round roast',
          '1814.37',
          'from the printed weight (3½–4½ lb, the midpoint)',
        ),
        // pressure-cooker-pot-roast|0, the spaced mixed number: v47
        // 1,814.37 (4 lb); 1,020.58 (½ to 4) without the fold.
        (
          '1 (3 ½- to 4-pound) boneless beef chuck-eye roast, pulled into 2 pieces at natural seam and trimmed of large pieces of fat',
          '1700.97',
          'from the printed weight (3½–4 lb, the midpoint)',
        ),
      ]) {
        final resolved = gramsOf(raw)!;
        expect(resolved.grams.toStringAsFixed(2), grams, reason: raw);
        expect(resolved.basis, basis, reason: raw);
      }
    });
  });

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v48');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  /// [file]'s line at [position], alone in a recipe with its steps and prep
  /// notes, matched and computed on the fixtures (as v43's pins).
  Future<(SaltDatabase, Recipe)> computed(String file, int position) async {
    final from = loadCorpusRecipe(file);
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from.prepNotes,
      steps: from.steps,
      ingredients: [
        IngredientGroup(items: [nutritionLines(from)[position]]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, recipe);
  }

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('each ranged line at its record, grams and basis (the M48 replay '
        'of snapshot 21; v47 in the comment)', () async {
      const thigh =
          '× 0.70 edible · approximate (USDA AH-102 item 586: chicken thigh, raw → meat and skin 70 % (63–81))';
      const breast =
          '× 0.74 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat and skin 74 % (59–84))';
      const turkey =
          '× 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))';
      for (final (file, position, raw, fdcId, grams, basis) in [
        // Audit L103's 953 g (v47 1,111.30, 8 × 198 g).
        (
          '1092-poulet-au-vinaigre-chicken-with-vinegar.yaml',
          0,
          '8 (5- to 7-ounce) bone-in chicken thighs, trimmed',
          2727567,
          '952.54',
          '8 × 170 g (printed 5–7 oz, the midpoint) $thigh',
        ),
        // v47 4,137.40 (14 lb).
        (
          '0156-old-fashioned-stuffed-turkey.yaml',
          0,
          '1 (12- to 14-pound) turkey, giblets and neck reserved for gravy, if making',
          171081,
          '3841.87',
          'from the printed weight (12–14 lb, the midpoint) $turkey',
        ),
        // The en dash: v47 6,501.63 (22 lb).
        (
          '0169-roasted-brined-turkey.yaml',
          1,
          '1 turkey (12–22 pounds gross weight), rinsed thoroughly, giblets and neck reserved for gravy, if making',
          171081,
          '5023.98',
          'from the printed weight (12–22 lb, the midpoint) $turkey',
        ),
        // A fraction, hyphenated: v47 1,104.00 (4 lb).
        (
          '0640-grill-roasted-beer-can-chicken.yaml',
          2,
          '1 (3½- to 4-pound) whole chicken',
          171447,
          '1035.00',
          'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
        ),
        // The spelling-parity pair: v47 1,006.97 and 923.06.
        (
          '0076-skillet-roasted-chicken-breasts-with-harissa-mint-carrots.yaml',
          0,
          '4 (10- to 12-ounce) bone-in split chicken breasts, trimmed',
          2727569,
          '923.06',
          '4 × 312 g (printed 10–12 oz, the midpoint) $breast',
        ),
        (
          '0075-skillet-roasted-chicken-breasts-with-potatoes.yaml',
          0,
          '4 (10 to 12-ounce) bone-in, split chicken breasts',
          2727569,
          '923.06',
          '4 × 312 g (printed 10–12 oz, the midpoint) $breast',
        ),
        // A fraction "to": v47 283.50 (10 oz).
        (
          '0383-crisp-thin-crust-pizza.yaml',
          0,
          '1¾–2 cups (8¾ to 10 ounces) unbleached all-purpose flour, plus extra for the work surface',
          789890,
          '265.78',
          'from the printed weight (8¾–10 oz, the midpoint)',
        ),
        // Unchanged grams, the basis names the range (v47 "(printed weight)").
        (
          '0042-almond-crusted-chicken-with-wilted-spinach-salad.yaml',
          0,
          '4 (5 to 6-ounce) boneless, skinless chicken breasts, trimmed',
          2646170,
          '623.69',
          '4 × 156 g (printed 5–6 oz, the midpoint)',
        ),
        // A bare range, unchanged grams (v47 "from 1 1/2–2 pound × …").
        (
          '1178-chicken-teriyaki.yaml',
          0,
          '1½–2 pounds bone-in chicken thighs',
          2727567,
          '555.65',
          'from 1 1/2–2 pound (the midpoint) $thigh',
        ),
        // Unchanged: the reversed typo, and a hen weighed by FDC's bird.
        (
          '0795-pane-francese.yaml',
          3,
          '2⅔–3 cups (14⅔ to 6½ ounces) bread flour',
          168913,
          '415.79',
          'from the printed weight',
        ),
        (
          '0147-roasted-cornish-game-hens.yaml',
          0,
          '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded',
          171507,
          '1344.00',
          '4 × 336 g (USDA edible bird portion)',
        ),
      ]) {
        final (db, recipe) = await computed(file, position);
        final line = recipe.ingredients.single.items.single;
        expect(line.raw, raw, reason: file);
        final row = db.ingredientMatchesFor('r').single;
        expect(row.fdcId, fdcId, reason: raw);
        expect(row.hold, isNull, reason: raw);
        expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: raw,
        );
      }
    });
  });
}
