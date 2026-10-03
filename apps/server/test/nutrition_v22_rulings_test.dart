// The checkpoint 9 rulings (user, 2026-10-01), matcher v22: Q1 a sourdough
// starter's feeding flour is held (`starter_discard`), Q2 a fried food's
// dredge is held (`coating`) until a coating fraction is set, Q3 a dry cure
// rinsed off is 0 g discarded, Q4 a braise kept only in part is held
// (`partial_pour_away`, the kept part in `hold_note`). Every pin is a real
// corpus line; each rule's whole-library reach is pinned EXACTLY (the
// lines it trips), so a rule that widens or narrows fails here.
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

DiscardedMedium? mediumOf(Recipe r, int i) {
  final line = nutritionLines(r)[i];
  return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
}

/// Every library line's medium, decoded once: `<file>#<position>`.
final Map<String, DiscardedMedium?> _library = {
  for (final file
      in Directory(corpusRecipesDir).listSync().whereType<File>().where(
        (f) => f.path.endsWith('.yaml'),
      ))
    ...() {
      final name = file.uri.pathSegments.last;
      final r = loadCorpusRecipe(name);
      return {
        for (final (i, _) in nutritionLines(r).indexed)
          '${name.replaceAll('.yaml', '')}#$i': mediumOf(r, i),
      };
    }(),
};

/// The library lines whose medium is one of [media].
Set<String> libraryLinesOf(Set<DiscardedMedium> media) => {
  for (final MapEntry(:key, :value) in _library.entries)
    if (media.contains(value)) key,
};

void main() {
  test('the SQL list of medium holds is the list', () {
    expect(
      SaltDatabase.mediumHoldsSql,
      mediumHolds.map((h) => "'$h'").join(', '),
    );
    expect(
      {for (final m in DiscardedMedium.values) m.hold},
      mediumHolds.toSet(),
    );
  });

  group('Q1: the starter feeding discard', () {
    test("0799's two flour lines are held starter_discard with no grams; "
        'the water is water', () async {
      final r = loadCorpusRecipe('0799-sourdough-starter.yaml');
      expect(mediumOf(r, 0), DiscardedMedium.starterDiscard);
      expect(mediumOf(r, 1), DiscardedMedium.starterDiscard);
      expect(mediumOf(r, 2), isNull, reason: nutritionLines(r)[2].raw);
      final out = engineOutcome(
        r,
        nutritionLines(r)[0],
        (await FixtureProvider().food(790085))!,
        const GramResolution(grams: 701.65, source: GramSource.weight),
        picked: true,
      );
      expect((out.grams, out.hold), (null, 'starter_discard'));
    }, skip: skipIfNoCorpus);

    test('no other library line is a starter discard (every other '
        '"discard" step — fat, solids, dough, whey — names no starter)', () {
      expect(libraryLinesOf({DiscardedMedium.starterDiscard}), {
        '0799-sourdough-starter#0',
        '0799-sourdough-starter#1',
      });
    }, skip: skipIfNoCorpus);
  });

  group("Q2: a fried food's dredge", () {
    test("0148's 4 cups of flour and 0116's flour and crumbs are held "
        '`coating` with no grams', () async {
      final chicken = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      expect(mediumOf(chicken, 8), DiscardedMedium.coating);
      final schnitzel = loadCorpusRecipe('0116-chicken-schnitzel.yaml');
      expect(mediumOf(schnitzel, 0), DiscardedMedium.coating);
      expect(mediumOf(schnitzel, 3), DiscardedMedium.coating);
      final flour = (await FixtureProvider().food(789890))!;
      const whole = GramResolution(grams: 566.99, source: GramSource.weight);
      final out = engineOutcome(
        chicken,
        nutritionLines(chicken)[8],
        flour,
        whole,
        picked: true,
      );
      expect((out.grams, out.hold), (null, 'coating'));
      // The hook: a fraction the user sets counts that share, unheld (the
      // 0.25 is the test's, never a production figure).
      final share = engineOutcome(
        chicken,
        nutritionLines(chicken)[8],
        flour,
        whole,
        picked: true,
        coating: 0.25,
      );
      expect(share.grams, closeTo(141.75, 0.01));
      expect((share.source, share.hold), ('weight', null));
      expect(coatingFraction, isNull);
    }, skip: skipIfNoCorpus);

    test('a batter is eaten whole: 0672 folds its cornstarch into the wet '
        'florets — counted; and so are a sauce thickener (0304 gravy flour, '
        "0525's 1 tablespoon plus 2 teaspoons), a fried dish's cornstarch "
        'tossed on whole (0536), and a dredge in a recipe that does not fry '
        '(0122 Kiev, 0418 piccata)', () {
      for (final (file, i, raw) in [
        ('0672-buffalo-cauliflower-bites.yaml', 5, '¾ cup cornstarch'),
        ('0304-chicken-fried-steaks.yaml', 12, '3 tablespoons unbleached'),
        ('0525-orange-flavored-chicken.yaml', 10, '2 teaspoons cornstarch'),
        ('0536-crispy-orange-beef.yaml', 2, '6 tablespoons cornstarch'),
        ('0122-chicken-kiev.yaml', 11, '1 cup unbleached'),
        ('0418-chicken-piccata.yaml', 3, '½ cup unbleached'),
      ]) {
        final r = loadCorpusRecipe(file);
        expect(nutritionLines(r)[i].raw, contains(raw));
        expect(
          mediumOf(r, i),
          isNull,
          reason: '$file ${nutritionLines(r)[i].raw}',
        );
      }
    }, skip: skipIfNoCorpus);

    test('a line that says "for dredging" is one whatever the steps say, '
        'and a fried food "dredged" in a line is one; '
        'sugar "for coating" is not (no dredge head)', () {
      // Synthesized lines (a stated exception): no corpus flour, starch or
      // crumb line says "for dredging" or "for coating"; the sugar's words
      // are 0816's real "plus ½ cup for coating".
      Recipe one(String raw) {
        final parsed = parseIngredientLine(raw);
        return Recipe(
          id: 'r',
          title: 'r',
          slug: 'r',
          source: const RecipeSource(name: 'Test', type: 'book'),
          ingredients: [
            IngredientGroup(
              items: [
                IngredientLine(
                  raw: raw,
                  item: parsed.item,
                  amounts: parsed.amounts,
                ),
              ],
            ),
          ],
        );
      }

      expect(
        mediumOf(one('1 cup all-purpose flour, for dredging'), 0),
        DiscardedMedium.coating,
      );
      // "dredge" alone, in a recipe that fries: no corpus dredge lacks the
      // other words (excess, a shallow dish), so the steps are synthesized.
      Recipe fried(String step) => Recipe(
        id: 'r',
        title: 'r',
        slug: 'r',
        source: const RecipeSource(name: 'Test', type: 'book'),
        ingredients: [
          IngredientGroup(
            items: [
              for (final raw in [
                '2 quarts vegetable oil for frying',
                '1 cup all-purpose flour',
              ])
                IngredientLine(
                  raw: raw,
                  item: parseIngredientLine(raw).item,
                  amounts: parseIngredientLine(raw).amounts,
                ),
            ],
          ),
        ],
        steps: [RecipeStep(number: 1, text: step)],
      );
      expect(
        mediumOf(fried('Dredge the cutlets in the flour. Fry in the oil.'), 1),
        DiscardedMedium.coating,
      );
      expect(
        mediumOf(fried('Toss the cutlets with the flour. Fry in the oil.'), 1),
        isNull,
      );
      expect(
        mediumOf(
          one('⅓ cup (2⅓ ounces) granulated sugar, plus ½ cup for coating'),
          0,
        ),
        isNull,
      );
    });

    test('the dredge lines of the library, exactly (v23: read from the '
        'directions — 0042, 0114, 0149, 0198 and 0288 fry too)', () {
      expect(libraryLinesOf({DiscardedMedium.coating}), {
        // v23 (Run 053 O7/S5): the oil discarded after the fry (0042 ½ cup
        // panko, 0114 ¾ cup flour, 0198 ⅔ cup cornstarch), the oil heated
        // to 375 degrees (0149 2 cups flour), "pan-fry" (0288 ¼ cup flour).
        '0042-almond-crusted-chicken-with-wilted-spinach-salad#3',
        '0114-breaded-chicken-cutlets#3',
        '0149-easier-fried-chicken#8',
        '0198-crispy-pan-fried-pork-chops#0',
        '0288-maryland-crab-cakes#8',
        '0116-chicken-schnitzel#0',
        '0116-chicken-schnitzel#3',
        '0148-crispy-fried-chicken#8',
        '0233-pork-schnitzel-breaded-pork-cutlets#1',
        '0255-fish-and-chips#2',
        '0279-crispy-salt-and-pepper-shrimp#8',
        '0304-chicken-fried-steaks#0',
        '0525-orange-flavored-chicken#13',
        '0527-karaage-japanese-fried-chicken-thighs#7',
        '1084-rhode-islandstyle-fried-calamari#2',
        '1133-chicken-francese#5',
        // v31 (B4, the CP10 rulings): the bread a held breading processes
        // into its crumbs, held with its flour.
        '0114-breaded-chicken-cutlets#2',
        '0233-pork-schnitzel-breaded-pork-cutlets#0',
      });
    }, skip: skipIfNoCorpus);
  });

  test('a new medium hold is a LINE hold at every site: a group of one in '
      "the queue, out of another line's reach, never cleared by a decision, "
      'and a confirm writes it poured away (0148 and 0116, their dredge '
      'flour)', () async {
    final db = wp.tempDb();
    final provider = FixtureProvider(pending: pendingSearches);
    final chicken = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
    final cutlets = loadCorpusRecipe('0116-chicken-schnitzel.yaml');
    for (final r in [chicken, cutlets]) {
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
    }
    final flour = db.ingredientMatchesFor(chicken.id)[8];
    expect((flour.hold, flour.grams), ('coating', null));
    final key = flour.itemKey!;
    expect(db.ingredientMatchesFor(cutlets.id)[0].hold, 'coating');
    expect(db.ingredientMatchesFor(cutlets.id)[0].itemKey, key);
    final groups = db
        .nutritionReviewGroups(limit: 200, offset: 0)
        .where((group) => group.itemKey == key)
        .toList();
    expect([for (final group in groups) group.lines], [1, 1]);
    final item =
        ((await matchesBody(db, provider, chicken))['items']! as List)[8]
            as Map;
    expect((item['others'], item['others_lines']), (0, 0));
    await applyMatchOverride(db, provider, chicken, 8, {
      'raw': nutritionLines(chicken)[8].raw,
      'confirmed': true,
    });
    final confirmed = db.ingredientMatchesFor(chicken.id)[8];
    expect(
      (confirmed.status, confirmed.grams, confirmed.gramSource),
      ('confirmed', 0, 'discarded'),
    );
    expect(db.ingredientMatchesFor(cutlets.id)[0].hold, 'coating');
    expect(
      db
          .nutritionReviewGroups(limit: 200, offset: 0)
          .singleWhere((group) => group.itemKey == key)
          .decided,
      isFalse,
    );
  }, skip: skipIfNoCorpus);

  group("a person's write on a new medium hold (0148's dredge flour)", () {
    const flour = '4 cups (20 ounces) unbleached all-purpose flour';

    Future<(SaltDatabase, FixtureProvider, Recipe)> computed() async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      expect(nutritionLines(r)[8].raw, flour);
      expect(db.ingredientMatchesFor(r.id)[8].hold, 'coating');
      return (db, provider, r);
    }

    test('a pick on it keeps the hold, no grams (the PUT pick site; v23, '
        'Run 053 O8 — every kind: nutrition_v23_rules_test G6)', () async {
      final (db, provider, r) = await computed();
      await applyMatchOverride(db, provider, r, 8, {
        'raw': flour,
        'fdc_id': 789890,
      });
      final row = db.ingredientMatchesFor(r.id)[8];
      expect(
        (row.grams, row.hold, row.status),
        (null, 'coating', 'overridden'),
      );
    }, skip: skipIfNoCorpus);

    test('RULE A (v25, Run 055 O5; was "the confirm site reads the stored '
        'hold too"): a confirm on a row whose stored hold the steps no longer '
        'give (a steps-only edit, synthesized) weighs the flour', () async {
      final (db, provider, r) = await computed();
      final steps = [
        for (final step in r.steps)
          step.copyWith(
            text: step.text
                .replaceAll('Place the flour in a shallow dish. ', '')
                .replaceAll(', shaking off the excess', '')
                .replaceAll('dredge in the flour', 'toss with the flour')
                .replaceAll(', shake off the excess', '')
                .replaceAll(', allowing the excess to drip off', ''),
          ),
      ];
      final edited = r.copyWith(steps: steps);
      expect(
        discardedMediumOf(
          edited,
          nutritionLines(edited)[8],
          normalizeItem(lineItemOf(nutritionLines(edited)[8])),
        ),
        isNull,
      );
      wp.saveRecipe(db, edited);
      await applyMatchOverride(db, provider, edited, 8, {
        'raw': flour,
        'confirmed': true,
      });
      // RULE A (v25, Run 055 O5): the hold is derived from the recipe as it
      // is — the stored hold no longer decides: the flour no step dredges
      // any more is weighed, the confirm is this food at its weight now.
      final row = db.ingredientMatchesFor(r.id)[8];
      expect((row.grams, row.gramSource, row.hold), (566.99, 'weight', null));
    }, skip: skipIfNoCorpus);

    test('a skip on it carried through an amount edit (4 → 5 cups, '
        'synthesized) stores no hold — the un-skip re-derives it (O13: the '
        "edited row's clearHold)", () async {
      final (db, provider, r) = await computed();
      await applyMatchOverride(db, provider, r, 8, {
        'raw': flour,
        'skipped': true,
      });
      final edited = r.copyWith(
        ingredients: [
          for (final group in r.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw == flour
                      ? IngredientLine(
                          raw:
                              '5 cups (25 ounces) unbleached all-purpose '
                              'flour',
                          item: item.item,
                          amounts: parseIngredientLine(
                            '5 cups (25 ounces) unbleached all-purpose flour',
                          ).amounts,
                        )
                      : item,
              ],
            ),
        ],
      );
      wp.saveRecipe(db, edited);
      await matchAndCompute(db, provider, edited);
      final row = db.ingredientMatchesFor(r.id)[8];
      expect((row.raw.startsWith('5 cups'), row.status), (true, 'skipped'));
      expect(row.hold, isNull);
    }, skip: skipIfNoCorpus);

    test('a confirmed row whose amount is edited (4 → 5 cups, synthesized) '
        'stays poured away, 0 g, its hold resolved (the compute site, '
        'derivedFor; RULE A, v25)', () async {
      final (db, provider, r) = await computed();
      await applyMatchOverride(db, provider, r, 8, {
        'raw': flour,
        'confirmed': true,
      });
      final parsed = parseIngredientLine(
        '5 cups (25 ounces) unbleached all-purpose flour',
      );
      final edited = r.copyWith(
        ingredients: [
          for (final group in r.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw == flour
                      ? IngredientLine(
                          raw:
                              '5 cups (25 ounces) unbleached all-purpose '
                              'flour',
                          item: parsed.item,
                          amounts: parsed.amounts,
                        )
                      : item,
              ],
            ),
        ],
      );
      wp.saveRecipe(db, edited);
      await matchAndCompute(db, provider, edited);
      final row = db.ingredientMatchesFor(r.id)[8];
      expect(row.raw, startsWith('5 cups'));
      // RULE A (v25, Run 055 I1): the confirm resolves the hold — still
      // poured away, 0 g, no hold.
      expect(
        (row.status, row.grams, row.gramSource, row.hold),
        ('confirmed', 0, 'discarded', null),
      );
    }, skip: skipIfNoCorpus);
  });

  group('Q3: a dry cure rinsed off', () {
    test("0090's ½ cup kosher salt is a rinsed cure: 0 g discarded, as "
        "0091's brine; 0168's dry brine (its EXCESS rinsed) and 0610's "
        'barbecue rub (never rinsed) stay counted', () async {
      final cure = loadCorpusRecipe(
        '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml',
      );
      expect(nutritionLines(cure)[0].raw, '½ cup kosher salt');
      expect(mediumOf(cure, 0), DiscardedMedium.brine);
      final out = engineOutcome(
        cure,
        nutritionLines(cure)[0],
        (await FixtureProvider().food(173468))!,
        const GramResolution(grams: 85.17, source: GramSource.density),
        picked: true,
      );
      expect((out.grams, out.source, out.hold), (0, 'discarded', null));
      final brine = loadCorpusRecipe(
        '0091-home-corned-beef-with-vegetables.yaml',
      );
      expect(mediumOf(brine, 1), DiscardedMedium.brine);
      final turkey = loadCorpusRecipe('0168-roast-salted-turkey.yaml');
      expect(nutritionLines(turkey)[1].raw, '5 tablespoons kosher salt');
      expect(mediumOf(turkey, 1), isNull);
      final rub = loadCorpusRecipe(
        '0610-smoky-pulled-pork-on-a-gas-grill.yaml',
      );
      expect(nutritionLines(rub)[0].raw, '5 teaspoons kosher salt');
      expect(mediumOf(rub, 0), isNull);
      expect(mediumOf(rub, 3), isNull, reason: nutritionLines(rub)[3].raw);
    }, skip: skipIfNoCorpus);
  });

  group('Q4: a braise kept only in part', () {
    test("0129 Mahogany's soy, sherry, sugar, molasses and vinegar are held "
        'partial_pour_away; the water, chicken, ginger, garlic and the '
        "sauce's cornstarch are not; the kept part is written", () {
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      for (final i in [1, 2, 3, 4, 5]) {
        expect(mediumOf(r, i), DiscardedMedium.partialPourAway);
        expect(
          keptLiquidOf(r, nutritionLines(r)[i]),
          '1 cup defatted cooking liquid',
        );
      }
      for (final i in [0, 6, 7, 8, 9]) {
        expect(mediumOf(r, i), isNull, reason: nutritionLines(r)[i].raw);
      }
    }, skip: skipIfNoCorpus);

    test("the rule's guards, each on 0129 Mahogany edited (synthesized, "
        'the stated exception: no library braise exercises them): a step '
        'using the "remaining" liquid keeps it all; a liquid the food is '
        'brought to a simmer in from the start, or a line a step only rubs '
        'on, is no braise mixture; a second line of the same food (the '
        "sauce's) is not the braise's", () {
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      Recipe withSteps(String Function(String) f, {List<String>? extra}) {
        final parsed = [
          for (final raw in extra ?? const <String>[])
            IngredientLine(
              raw: raw,
              item: parseIngredientLine(raw).item,
              amounts: parseIngredientLine(raw).amounts,
            ),
        ];
        return r.copyWith(
          ingredients: [
            for (final group in r.ingredients)
              group.copyWith(items: [...group.items, ...parsed]),
          ],
          steps: [
            for (final step in r.steps) step.copyWith(text: f(step.text)),
          ],
        );
      }

      bool soyHeld(Recipe x, [int i = 1]) =>
          mediumOf(x, i) == DiscardedMedium.partialPourAway;
      expect(soyHeld(r), isTrue);
      expect(
        soyHeld(
          withSteps(
            (t) => t.replaceAll(
              'Serve, passing reserved sauce separately.',
              'Serve with remaining cooking liquid.',
            ),
          ),
        ),
        isFalse,
      );
      expect(
        soyHeld(
          withSteps(
            (t) => t.replaceAll(
              'Whisk 1 cup water, soy sauce, sherry, sugar, molasses, and '
                  'vinegar together in ovensafe 12-inch skillet until sugar '
                  'is dissolved. Arrange chicken, skin side down, in soy '
                  'mixture and nestle',
              'Whisk 1 cup water, soy sauce, sherry, sugar, molasses, '
                  'vinegar, chicken, ginger, and garlic together in '
                  'ovensafe 12-inch skillet. Leave',
            ),
          ),
        ),
        isFalse,
      );
      expect(
        soyHeld(
          withSteps(
            (t) => t.replaceAll(
              'Whisk 1 cup water, soy sauce,',
              'Rub chicken with soy sauce. Place chicken on plate. Whisk 1 '
                  'cup water,',
            ),
          ),
        ),
        isFalse,
      );
      final second = withSteps((t) => t, extra: ['1 tablespoon soy sauce']);
      expect(soyHeld(second), isTrue);
      expect(soyHeld(second, nutritionLines(second).length - 1), isFalse);
    }, skip: skipIfNoCorpus);

    test('the GET says the kept part: hold_note on a held line, null on '
        'the others', () async {
      final db = wp.tempDb();
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      wp.saveRecipe(db, r);
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, provider, r);
      final items = ((await matchesBody(db, provider, r))['items']! as List)
          .cast<Map<String, Object?>>();
      Map<String, Object?> match(int i) =>
          items[i]['match']! as Map<String, Object?>;
      expect(match(1)['hold'], 'partial_pour_away');
      expect(match(1)['hold_note'], '1 cup defatted cooking liquid');
      expect(match(1)['grams'], isNull);
      expect(match(8)['hold_note'], isNull);
      expect(nutritionBody(db, r, forAdmin: true)['status'], 'partial');
    }, skip: skipIfNoCorpus);

    test('the poured-away braise lines of the library, exactly: 0129 '
        'Mahogany and 0129 Indoor Pulled Chicken ("½ cup reserved defatted '
        'liquid"), and since matcher v31 (the owner\'s R4 ruling) 0488\'s '
        'poach ("Remove ¼ cup liquid … discard the remaining liquid"); 0491 '
        '(pork, onion and water brought to a simmer together), '
        '0087/0209/0538 (the whole liquid reduced) are not', () {
      expect(libraryLinesOf({DiscardedMedium.partialPourAway}), {
        for (final i in [1, 2, 3, 4, 5]) '0129-mahogany-chicken-thighs#$i',
        for (final i in [0, 1, 2, 3, 4]) '0129-indoor-pulled-chicken#$i',
        for (final i in [0, 1, 2, 3, 4]) '0488-enchiladas-verdes#$i',
      });
    }, skip: skipIfNoCorpus);
  });
}
