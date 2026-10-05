// Run 050 U1–U3: a person's typed grams through an amount edit, a skip and
// an un-skip. Real corpus lines (the recipe named on each), recorded FDC
// answers (FixtureProvider), no corpus needed; the amount edits ("4
// onions", "3 cups") are synthesized, a stated exception (lineKeyOf proven
// equal).
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-unskip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db')
      ..upsertSource(slug: 'src', name: 'Test', type: 'book');
    addTearDown(db.dispose);
    return db;
  }

  /// Recipe 'r' of one line [raw], saved (over any earlier version).
  Recipe save(
    SaltDatabase db,
    String raw, {
    List<Subsection> subsections = const [],
  }) {
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      subsections: subsections,
      ingredients: [
        IngredientGroup(items: [lineOf(raw)]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$raw');
    return recipe;
  }

  IngredientMatchRow row(SaltDatabase db) =>
      db.ingredientMatchesFor('r').single;

  test('U1: "1 onion, chopped" (Quinoa and Vegetable Stew, 0012) typed at '
      '40 g, skipped, amount-edited to "4 onions, chopped" and computed: the '
      "un-skip counts four onions' grams, never the old 40 g", () async {
    final db = tempDb();
    final provider = FixtureProvider();
    final one = save(db, '1 onion, chopped');
    expect(
      lineKeyOf(lineOf('4 onions, chopped')),
      lineKeyOf(one.ingredients.first.items.single),
    );
    await matchAndCompute(db, provider, one);
    final each = row(db).grams!;
    await applyMatchOverride(db, provider, one, 0, {
      'confirmed': true,
      'grams': 40,
    });
    await applyMatchOverride(db, provider, one, 0, {'skipped': true});
    final four = save(db, '4 onions, chopped');
    await matchAndCompute(db, provider, four);
    expect(row(db).status, 'skipped');
    await applyMatchOverride(db, provider, four, 0, {'skipped': false});
    expect(row(db).gramSource, isNot('override'));
    expect(row(db).grams, closeTo(4 * each, 0.01));
    await matchAndCompute(db, provider, four);
    expect(row(db).grams, closeTo(4 * each, 0.01));
  });

  test('U1, derived grams: "½ cup extra-virgin olive oil" (Acquacotta, '
      '0405) skipped, amount-edited to "1 cup" and computed: the skipped row '
      "carries the cup's grams, and the un-skip counts them", () async {
    final db = tempDb();
    final provider = FixtureProvider();
    final half = save(db, '½ cup extra-virgin olive oil');
    expect(
      lineKeyOf(lineOf('1 cup extra-virgin olive oil')),
      lineKeyOf(half.ingredients.first.items.single),
    );
    await matchAndCompute(db, provider, half);
    final halfGrams = row(db).grams!;
    await applyMatchOverride(db, provider, half, 0, {'skipped': true});
    final cup = save(db, '1 cup extra-virgin olive oil');
    await matchAndCompute(db, provider, cup);
    expect(row(db).status, 'skipped');
    expect(row(db).grams, closeTo(2 * halfGrams, 0.01));
    expect(db.nutritionFor('r')!.totalGrams, 0);
    await applyMatchOverride(db, provider, cup, 0, {'skipped': false});
    expect(row(db).grams, closeTo(2 * halfGrams, 0.01));
    expect(db.nutritionFor('r')!.totalGrams, closeTo(2 * halfGrams, 0.05));
  });

  test('U2: a pick with typed grams on a sub-recipe the recipe makes apart '
      '— "10 cups Vanilla Frosting (recipe follows)" (Rainbow Cake, 1201) '
      'on "Butter, without salt" at 500 g (synthesized grams: a stated '
      'exception) — survives a skip and an un-skip', () async {
    final db = tempDb();
    final provider = FixtureProvider();
    // v41: with 1201's own section — the section rule row.
    final cake = save(
      db,
      '10 cups Vanilla Frosting (recipe follows)',
      subsections: const [Subsection(title: 'Vanilla Frosting')],
    );
    await matchAndCompute(db, provider, cake);
    expect(row(db).description, subRecipeNote);
    await applyMatchOverride(db, provider, cake, 0, {
      'fdc_id': 173430,
      'grams': 500,
    });
    await applyMatchOverride(db, provider, cake, 0, {'skipped': true});
    await applyMatchOverride(db, provider, cake, 0, {'skipped': false});
    final got = row(db);
    expect(
      (got.status, got.fdcId, got.grams, got.gramSource),
      ('overridden', 173430, 500, 'override'),
    );
  });

  test('U3: "2 cups vegetable oil for frying" (a policy-zeroed medium) typed '
      'at 20 g keeps the 20 g through an amount edit to "3 cups", as a held '
      'medium keeps them', () async {
    final db = tempDb();
    final provider = FixtureProvider();
    final two = save(db, '2 cups vegetable oil for frying');
    await matchAndCompute(db, provider, two);
    expect(row(db).grams, 0);
    await applyMatchOverride(db, provider, two, 0, {
      'confirmed': true,
      'grams': 20,
    });
    final three = save(db, '3 cups vegetable oil for frying');
    await matchAndCompute(db, provider, three);
    final got = row(db);
    expect(
      (got.raw, got.grams, got.gramSource),
      (three.ingredients.first.items.single.raw, 20, 'override'),
    );
  });
}
