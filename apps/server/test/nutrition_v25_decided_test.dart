// RULE A (matcher v25, Run 055 I1): a decided row stores ONLY the person's
// decision (status, food, typed grams); the hold, the grams unless typed,
// their source and the `hold_note` are derived from the CURRENT recipe by
// one function ([derivedFor]) at every compute, every person's write and
// every read. Real corpus recipes (0129 Indoor Pulled Chicken, 1133 Chicken
// Francese, 0148 Crispy Fried Chicken), recorded FDC answers
// (FixtureProvider), never the network. Synthesized, each a stated
// exception: the steps edits (a dredge, a strain or a fry taken out, an
// eaten part re-amounted), a title edit, 1193 Crispy Tempeh's oil line and
// 0052's / 0300's salt lines each in a recipe of that one line with their
// real steps (the fixtures record no other line of them), and a stored row
// as an older matcher left it.
// ignore_for_file: lines_longer_than_80_chars
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
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

/// [r] with every step's [a] replaced by [b].
Recipe ed(Recipe r, String a, String b) => r.copyWith(
  steps: [for (final s in r.steps) s.copyWith(text: s.text.replaceAll(a, b))],
);

/// [r] with a title edit only (no nutrition input but the title).
Recipe retitled(Recipe r) => r.copyWith(title: '${r.title} (edited)');

/// 1133's steps with the dredge taken out (Run 055 O4's edit).
Recipe undredged1133(Recipe r) => ed(
  ed(
    r,
    'dredge cutlets in flour, shaking gently to remove excess',
    'toss cutlets with flour',
  ),
  'Spread remaining flour in shallow dish. ',
  '',
);

/// 0148's steps with the dredge taken out (the v22 rulings' edit).
Recipe undredged0148(Recipe r) => r.copyWith(
  steps: [
    for (final s in r.steps)
      s.copyWith(
        text: s.text
            .replaceAll('Place the flour in a shallow dish. ', '')
            .replaceAll(', shaking off the excess', '')
            .replaceAll('dredge in the flour', 'toss with the flour')
            .replaceAll(', shake off the excess', '')
            .replaceAll(', allowing the excess to drip off', ''),
      ),
  ],
);

/// 0129 Indoor Pulled Chicken with its braise no longer strained (the
/// cooking liquid kept whole: no partial pour-away).
Recipe unstrained0129(Recipe r) => ed(
  r,
  'Strain cooking liquid through fine-mesh strainer set over bowl (do not '
      'wash pot). ',
  '',
);

/// [r] with the corpus's own "1 cup water" line inserted first (v26, Run
/// 056 S1: every row moves down one; a water line is an engine rule row,
/// no search).
Recipe withWaterFirst(Recipe r) {
  const water = '1 cup water';
  final parsed = parseIngredientLine(water);
  final first = r.ingredients.first;
  return r.copyWith(
    ingredients: [
      first.copyWith(
        items: [
          IngredientLine(
            raw: water,
            item: parsed.item,
            amounts: parsed.amounts,
          ),
          ...first.items,
        ],
      ),
      ...r.ingredients.skip(1),
    ],
  );
}

const flour0148 = '4 cups (20 ounces) unbleached all-purpose flour';
const flour1133 = '¾ cup all-purpose flour, divided';
const smoke0129 = '1 tablespoon liquid smoke, divided';

int at(Recipe r, String raw) =>
    nutritionLines(r).indexWhere((line) => line.raw == raw);

IngredientMatchRow rowOf(SaltDatabase db, Recipe r, int position) =>
    db.ingredientMatchesFor(r.id).singleWhere((m) => m.position == position);

/// The decision and what it derives, as compared across paths.
(String, int?, double?, String?, String?) shape(IngredientMatchRow m) =>
    (m.status, m.fdcId, m.grams, m.gramSource, m.hold);

/// The matches GET's `hold_note` on line [position].
Future<String?> noteOf(SaltDatabase db, Recipe r, int position) async {
  final body = await matchesBody(
    db,
    FixtureProvider(pending: pendingSearches),
    r,
  );
  final item = (body['items']! as List)[position] as Map<String, Object?>;
  return (item['match']! as Map<String, Object?>)['hold_note'] as String?;
}

/// What a person's write [body] on line [position] gives on a FRESH
/// database holding [recipe] computed: the reference every compute's
/// derivation must equal (one rule, the PUT's and the compute's).
Future<IngredientMatchRow> freshWrite(
  Recipe recipe,
  int position,
  Map<String, Object?> body,
) async {
  final db = wp.tempDb();
  final provider = FixtureProvider(pending: pendingSearches);
  wp.saveRecipe(db, recipe);
  await matchAndCompute(db, provider, recipe);
  await applyMatchOverride(db, provider, recipe, position, {
    'raw': nutritionLines(recipe)[position].raw,
    ...body,
  });
  return rowOf(db, recipe, position);
}

/// What a fresh database gives the SAME decision as a person's confirm of
/// [fdcId] on line [position] of [recipe]: a confirm there ([freshWrite]),
/// except on a zero-nutrient flavouring line — since matcher v37 a fresh
/// compute writes that line (0129's liquid smoke, once its strain is gone
/// and nothing holds it) as the class rule row on no food, so the same
/// decision there is a pick of [fdcId], its status the person's confirm.
Future<IngredientMatchRow> freshConfirm(
  Recipe recipe,
  int position,
  int? fdcId,
) async {
  final line = nutritionLines(recipe)[position];
  if (fdcId == null ||
      !isZeroNutrientFlavouring(
        normalizeItem(lineItemOf(weighedLine(recipe, line))),
      )) {
    return freshWrite(recipe, position, {'confirmed': true});
  }
  final picked = await freshWrite(recipe, position, {'fdc_id': fdcId});
  return picked.copyWith(status: 'confirmed');
}

/// [file]'s corpus recipe with its ingredients cut to the one line [raw]
/// (its real steps kept; the fixtures record no other line of it).
Recipe oneLine(String file, String raw) {
  final r = loadCorpusRecipe(file);
  final line = [
    for (final group in r.ingredients) ...group.items,
  ].singleWhere((line) => line.raw == raw);
  return r.copyWith(
    ingredients: [
      IngredientGroup(items: [line]),
    ],
    subsections: const [],
  );
}

/// A computed database holding [file]'s corpus recipe.
Future<(SaltDatabase, FixtureProvider, Recipe)> computed(String file) async {
  final db = wp.tempDb();
  final provider = FixtureProvider(pending: pendingSearches);
  final r = loadCorpusRecipe(file);
  wp.saveRecipe(db, r);
  await matchAndCompute(db, provider, r);
  return (db, provider, r);
}

/// Saves [edited] and computes it.
Future<void> editAndCompute(
  SaltDatabase db,
  NutritionProvider provider,
  Recipe edited,
) async {
  wp.saveRecipe(db, edited);
  await matchAndCompute(db, provider, edited);
}

void main() {
  group('RULE A: a confirm stands through every compute, its derived '
      'fields read from the recipe as it is (Run 055 S8, O5)', () {
    test("S8: 0129's divided liquid smoke confirmed — a title edit and a "
        'compute keep the row as the PUT wrote it (no hold comes back, no '
        'write); a steps edit that stops the strain re-weighs it as a '
        'confirm on the edited recipe writes it', () async {
      final (db, provider, r) = await computed(
        '0129-indoor-pulled-chicken.yaml',
      );
      final i = at(r, smoke0129);
      expect(rowOf(db, r, i).hold, 'partial_pour_away');
      await applyMatchOverride(db, provider, r, i, {
        'raw': smoke0129,
        'confirmed': true,
      });
      final confirmed = rowOf(db, r, i);
      // A confirm on a held medium: its eaten part (the "remaining 1
      // teaspoon liquid smoke" after the strain), no hold — 0 g poured away
      // only when the engine knows no eaten part.
      expect(
        (confirmed.status, confirmed.gramSource, confirmed.hold),
        ('confirmed', GramSource.discarded.name, null),
      );
      expect(confirmed.grams, closeTo(4.73, 0.01));
      expect(await noteOf(db, r, i), 'eaten part counted after your confirm');
      final titled = retitled(r);
      await editAndCompute(db, provider, titled);
      final again = rowOf(db, r, i);
      expect(shape(again), shape(confirmed));
      expect(again.updatedAt, confirmed.updatedAt, reason: 'no write');
      expect(nutritionIsFresh(db, titled), isTrue);
      final edited = unstrained0129(titled);
      expect(heldMediumLine(edited, nutritionLines(edited)[i]), isFalse);
      final fresh = await freshConfirm(edited, i, confirmed.fdcId);
      // Saved, not yet computed: the matches GET already reads the decision
      // on the recipe as it is (the same derivation, from the cache).
      wp.saveRecipe(db, edited);
      final body = await matchesBody(db, provider, edited);
      final shown =
          ((body['items']! as List)[i] as Map<String, Object?>)['match']!
              as Map<String, Object?>;
      expect(
        (shown['status'], shown['grams'], shown['gram_source'], shown['hold']),
        (fresh.status, fresh.grams, fresh.gramSource, fresh.hold),
      );
      await matchAndCompute(db, provider, edited);
      final after = rowOf(db, r, i);
      expect(shape(after), shape(fresh));
      expect(after.grams, isNot(confirmed.grams));
      expect(after.gramSource, isNot(GramSource.discarded.name));
      expect(await noteOf(db, edited, i), isNull);
    });

    for (final between in [true, false]) {
      test("O5: 0148's dredge flour confirmed (M52's C1d budget kept, "
          '144.06 g — verify2 D1), then the dredge taken out of the steps ${between ? 'after' : 'with no'} '
          'compute between — the flour is weighed either way', () async {
        final (db, provider, r) = await computed(
          '0148-crispy-fried-chicken.yaml',
        );
        final i = at(r, flour0148);
        await applyMatchOverride(db, provider, r, i, {
          'raw': flour0148,
          'confirmed': true,
        });
        // RE-PIN (M52 batch, v53 closer 2, verify2 D1): the confirm keeps
        // the engine's budget (was 0 g poured away).
        expect(shape(rowOf(db, r, i)), (
          'confirmed',
          789890,
          144.06,
          GramSource.discarded.name,
          null,
        ));
        expect(await noteOf(db, r, i), 'eaten part counted after your confirm');
        var base = r;
        if (between) {
          base = retitled(r);
          await editAndCompute(db, provider, base);
          expect(rowOf(db, r, i).hold, isNull, reason: 'no hold comes back');
        }
        final edited = undredged0148(base);
        await editAndCompute(db, provider, edited);
        final after = rowOf(db, r, i);
        expect(
          shape(after),
          shape(await freshWrite(edited, i, {'confirmed': true})),
        );
        expect(after.grams, closeTo(566.99, 0.01));
        expect(nutritionIsFresh(db, edited), isTrue);
      });
    }
  }, skip: skipIfNoCorpus);

  group("RULE A: a pick's derived fields follow the recipe (Run 055 O4, "
      'O8)', () {
    for (final (tag, start, after)
        in <(String, Recipe Function(Recipe), Recipe Function(Recipe))>[
          ('the dredge taken out', (r) => r, undredged1133),
          (
            'the eaten part re-amounted (1 teaspoon to 2 tablespoons)',
            (r) => r,
            (r) => ed(
              r,
              'Sprinkle cubes with 1 teaspoon flour',
              'Sprinkle cubes with 2 tablespoons flour',
            ),
          ),
          ('the dredge put back', undredged1133, (r) => r),
        ]) {
      test(
        "O4: 1133's divided flour picked, then $tag and a compute: the "
        'row is what a pick on the edited recipe writes, stamped fresh',
        () async {
          final provider = FixtureProvider(pending: pendingSearches);
          final db = wp.tempDb();
          final corpus = loadCorpusRecipe('1133-chicken-francese.yaml');
          final r = start(corpus);
          await editAndCompute(db, provider, r);
          final i = at(r, flour1133);
          await applyMatchOverride(db, provider, r, i, {
            'raw': flour1133,
            'fdc_id': 789890,
          });
          final picked = rowOf(db, r, i);
          // A pick on the divided line resolves its hold (its eaten part
          // counted); on the undredged line there is none.
          expect(picked.hold, isNull);
          final edited = after(corpus);
          await editAndCompute(db, provider, edited);
          final now = rowOf(db, r, i);
          final fresh = await freshWrite(edited, i, {'fdc_id': 789890});
          expect(shape(now), shape(fresh));
          expect(now.grams, isNot(picked.grams), reason: 'not vacuous');
          expect(await noteOf(db, edited, i), await () async {
            final db2 = wp.tempDb();
            final p2 = FixtureProvider(pending: pendingSearches);
            await editAndCompute(db2, p2, edited);
            await applyMatchOverride(db2, p2, edited, i, {
              'raw': flour1133,
              'fdc_id': 789890,
            });
            return noteOf(db2, edited, i);
          }());
          expect(nutritionIsFresh(db, edited), isTrue);
        },
      );
    }

    test(
      "O8, a decided line that BECOMES held: 0148's flour picked (and, "
      'apart, confirmed) on the undredged recipe, then the dredge put '
      'back — the pick keeps the coating hold with no grams, the confirm '
      "keeps the engine's C1d budget, 144.06 g, no hold (verify2 D1)",
      () async {
        final corpus = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
        final i = at(corpus, flour0148);
        for (final body in <Map<String, Object?>>[
          {'fdc_id': 789890},
          {'confirmed': true},
        ]) {
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          final r = undredged0148(corpus);
          await editAndCompute(db, provider, r);
          await applyMatchOverride(db, provider, r, i, {
            'raw': flour0148,
            ...body,
          });
          final before = rowOf(db, r, i);
          expect(before.hold, isNull);
          expect(before.grams, closeTo(566.99, 0.01));
          await editAndCompute(db, provider, corpus);
          final now = rowOf(db, r, i);
          expect(shape(now), shape(await freshWrite(corpus, i, body)));
          expect(
            (now.grams, now.hold),
            // RE-PIN (M52 batch, v53 closer 2, verify2 D1): was (0, null).
            body.containsKey('fdc_id') ? (null, 'coating') : (144.06, null),
            reason: '$body',
          );
        }
      },
    );

    test("O8, a decided line that STOPS being held: 0148's flour picked "
        '(the coating hold kept), then the dredge taken out — weighed, no '
        'hold, as a pick on the edited recipe writes it', () async {
      final (db, provider, r) = await computed(
        '0148-crispy-fried-chicken.yaml',
      );
      final i = at(r, flour0148);
      await applyMatchOverride(db, provider, r, i, {
        'raw': flour0148,
        'fdc_id': 789890,
      });
      expect((rowOf(db, r, i).grams, rowOf(db, r, i).hold), (null, 'coating'));
      final edited = undredged0148(r);
      await editAndCompute(db, provider, edited);
      final now = rowOf(db, r, i);
      expect(
        shape(now),
        shape(await freshWrite(edited, i, {'fdc_id': 789890})),
      );
      expect(now.hold, isNull);
    });
  }, skip: skipIfNoCorpus);

  group('RULE A on a policy-zeroed medium and a wholly poured-away one '
      '(Run 055 Sonnet critics 1 and 2)', () {
    const oil = '1 cup vegetable oil';
    Recipe tempeh() =>
        oneLine('1193-crispy-tempeh-with-sambal-sauce.yaml', oil);

    /// 1193 with its fry taken out: no frying heat, no pour-off.
    Recipe unfried(Recipe r) => ed(
      ed(
        ed(
          ed(r, ' to 375 degrees', ''),
          'Return oil to 375 degrees over medium-high heat',
          'Return skillet to medium-high heat',
        ),
        'maintain oil temperature between 350 and 375 degrees',
        'maintain heat',
      ),
      'Carefully pour off all but 2 tablespoons oil from pan. ',
      '',
    );

    bool frying(Recipe r) =>
        discardedMediumOf(
          r,
          nutritionLines(r).single,
          normalizeItem(lineItemOf(nutritionLines(r).single)),
        ) !=
        null;

    test("critic 1: 1193's frying oil confirmed, then a steps edit that "
        'stops the frying — re-weighed as a confirm on the edited recipe '
        'writes it (and back)', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = tempeh();
      expect(frying(r), isTrue);
      await editAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': oil,
        'confirmed': true,
      });
      final confirmed = rowOf(db, r, 0);
      final edited = unfried(r);
      expect(frying(edited), isFalse);
      await editAndCompute(db, provider, edited);
      final now = rowOf(db, r, 0);
      expect(
        shape(now),
        shape(await freshWrite(edited, 0, {'confirmed': true})),
      );
      expect(now.grams, greaterThan(confirmed.grams!));
      await editAndCompute(db, provider, r);
      expect(shape(rowOf(db, r, 0)), shape(confirmed));
    });

    test('critic 1, a matcher bump: a confirmed frying oil stored as an '
        'older matcher weighed it (the whole cup, synthesized) is '
        're-derived by the next compute — the decision kept', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = tempeh();
      await editAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': oil,
        'confirmed': true,
      });
      final confirmed = rowOf(db, r, 0);
      db.upsertIngredientMatch(
        confirmed.copyWith(grams: 224, gramSource: GramSource.portion.name),
      );
      await matchAndCompute(db, provider, r);
      expect(shape(rowOf(db, r, 0)), shape(confirmed));
    });

    for (final (file, raw, grams, note) in [
      (
        '0052-sesame-lemon-cucumber-salad.yaml',
        '1 tablespoon table salt',
        0.0,
        'poured away after your pick',
      ),
      (
        '0300-classic-macaroni-and-cheese.yaml',
        '1 tablespoon plus 1 teaspoon table salt',
        6.01,
        'eaten part counted after your pick',
      ),
    ]) {
      test('critic 2: a pick on a `discarded_medium` line ("$raw") resolves '
          'its hold at the PUT and stays resolved through a compute — '
          '${grams == 0 ? 'wholly poured away, 0 g' : 'its eaten part'}, '
          'said in hold_note', () async {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        final r = oneLine(file, raw);
        await editAndCompute(db, provider, r);
        expect(rowOf(db, r, 0).hold, 'discarded_medium');
        await applyMatchOverride(db, provider, r, 0, {
          'raw': raw,
          'fdc_id': 173468,
        });
        for (final path in ['PUT', 'compute']) {
          if (path == 'compute') {
            await editAndCompute(db, provider, retitled(r));
          }
          final row = rowOf(db, r, 0);
          expect(
            (row.status, row.gramSource, row.hold),
            ('overridden', GramSource.discarded.name, null),
            reason: path,
          );
          expect(row.grams, closeTo(grams, 0.01), reason: path);
          expect(await noteOf(db, r, 0), note, reason: path);
        }
      });
    }

    test("V2: a pick that KEEPS a hold shows the hold's own words — "
        "0129 Mahogany Chicken Thighs' \"1 cup soy sauce\" picked on its own "
        'food stays `partial_pour_away`, its GET note "1 cup defatted '
        'cooking liquid", through the PUT and a compute', () async {
      const soy = '1 cup soy sauce';
      final (db, provider, r) = await computed(
        '0129-mahogany-chicken-thighs.yaml',
      );
      final i = at(r, soy);
      final own = rowOf(db, r, i);
      expect(own.fdcId, isNotNull);
      expect(own.hold, 'partial_pour_away');
      await applyMatchOverride(db, provider, r, i, {
        'raw': soy,
        'fdc_id': own.fdcId,
      });
      for (final path in ['PUT', 'compute']) {
        if (path == 'compute') {
          await editAndCompute(db, provider, retitled(r));
        }
        final row = rowOf(db, r, i);
        expect(
          (row.status, row.hold),
          ('overridden', 'partial_pour_away'),
          reason: path,
        );
        expect(
          await noteOf(db, r, i),
          '1 cup defatted cooking liquid',
          reason: path,
        );
      }
    });

    test('V4: a pick keeps an `ambiguous_medium` hold (an eaten-in-part '
        "hold) with no grams — 0690 Patatas Bravas' sauce oil retyped \"½ "
        'cup extra-virgin olive oil" (an aioli, a stated synthesized retype) '
        'beside its 3 cups heated to 375 degrees (its two oil lines, its '
        'real steps), picked: never zeroed as poured away', () async {
      const aioli = '½ cup extra-virgin olive oil';
      // Its two oil lines with its real steps (the fixtures record no
      // other line of it).
      final base = oneLine('0690-patatas-bravas.yaml', '3 cups vegetable oil');
      final parsed = parseIngredientLine(aioli);
      final r = base.copyWith(
        ingredients: [
          IngredientGroup(
            items: [
              ...base.ingredients.single.items,
              IngredientLine(
                raw: aioli,
                item: parsed.item,
                amounts: parsed.amounts,
              ),
            ],
          ),
        ],
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await editAndCompute(db, provider, r);
      final i = at(r, aioli);
      expect(rowOf(db, r, i).hold, 'ambiguous_medium');
      await applyMatchOverride(db, provider, r, i, {
        'raw': aioli,
        'fdc_id': 2710180,
      });
      for (final path in ['PUT', 'compute']) {
        if (path == 'compute') {
          await editAndCompute(db, provider, retitled(r));
        }
        final row = rowOf(db, r, i);
        expect(
          (row.status, row.grams, row.hold),
          ('overridden', null, 'ambiguous_medium'),
          reason: path,
        );
        expect(
          await noteOf(db, r, i),
          '"Heat oil in large Dutch oven over high heat to 375 degrees."',
          reason: path,
        );
      }
    });
  }, skip: skipIfNoCorpus);

  group("RULE A's guards (Run 055 S17)", () {
    test("a save during the compute's awaits: the decided row's re-derived "
        "fields are NOT written over it (the fresh() gate) — 0148's picked "
        'flour keeps the coating hold the stored row has', () async {
      final db = wp.tempDb();
      final fixtures = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      final i = at(r, flour0148);
      // A pick before any compute (no search cached yet).
      await applyMatchOverride(db, fixtures, r, i, {
        'raw': flour0148,
        'fdc_id': 789890,
      });
      expect(rowOf(db, r, i).hold, 'coating');
      final edited = undredged0148(r);
      wp.saveRecipe(db, edited);
      final saving = _SaveOnFirstSearch(fixtures, () {
        wp.saveRecipe(db, retitled(edited));
      });
      await matchAndCompute(db, saving, edited);
      expect(saving.saved, isTrue, reason: 'the compute searched');
      final row = rowOf(db, r, i);
      expect((row.hold, row.grams), ('coating', null));
      expect(nutritionIsFresh(db, edited), isFalse);
    });

    test("a compute never changes a decision: 0711's picked plus-line oil, "
        'its Crispy Onions subsection renamed (synthesized) so the line is '
        "a sub-recipe made apart — the sub-recipe rule's 0 g, the pick's "
        'status and food kept', () async {
      const plus =
          '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe '
          'follows)';
      final corpus = loadCorpusRecipe(
        '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
      );
      final line = [
        for (final group in corpus.ingredients) ...group.items,
      ].singleWhere((line) => line.raw == plus);
      final r = corpus.copyWith(
        ingredients: [
          IngredientGroup(items: [line]),
        ],
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await editAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': plus,
        'fdc_id': 2710180,
      });
      expect(rowOf(db, r, 0).grams, 42);
      final apart = r.copyWith(
        subsections: [
          for (final sub in r.subsections)
            sub.title == 'Crispy Onions'
                ? sub.copyWith(title: 'Fried Shallots')
                : sub,
        ],
      );
      expect(
        subRecipeRowFor(apart, 0, nutritionLines(apart).single),
        isNotNull,
      );
      await editAndCompute(db, provider, apart);
      final now = rowOf(db, r, 0);
      expect(
        (now.status, now.fdcId, now.grams, now.gramSource),
        ('overridden', 2710180, 0, GramSource.unmeasured.name),
      );
    });

    test("grams a person typed on 1133's DIVIDED flour answer its hold — at "
        'the PUT, through a title edit and through an amount edit (¾ to 1 '
        'cup, synthesized; a medium line keeps typed grams)', () async {
      final (db, provider, r) = await computed('1133-chicken-francese.yaml');
      final i = at(r, flour1133);
      await applyMatchOverride(db, provider, r, i, {
        'raw': flour1133,
        'grams': 60,
      });
      final typed = rowOf(db, r, i);
      expect(
        (typed.grams, typed.gramSource, typed.hold),
        (60, GramSource.override.name, null),
      );
      await editAndCompute(db, provider, retitled(r));
      expect(shape(rowOf(db, r, i)), shape(typed));
      expect(rowOf(db, r, i).updatedAt, typed.updatedAt);
      const cup = '1 cup all-purpose flour, divided';
      final parsed = parseIngredientLine(cup);
      final amounted = r.copyWith(
        ingredients: [
          for (final group in r.ingredients)
            group.copyWith(
              items: [
                for (final item in group.items)
                  item.raw == flour1133
                      ? IngredientLine(
                          raw: cup,
                          item: parsed.item,
                          amounts: parsed.amounts,
                        )
                      : item,
              ],
            ),
        ],
      );
      await editAndCompute(db, provider, amounted);
      final now = rowOf(db, r, i);
      expect(now.raw, cup);
      expect(
        (now.grams, now.gramSource, now.hold),
        (60, GramSource.override.name, null),
      );
    });
  }, skip: skipIfNoCorpus);

  group('RULE A replay scenario: CONFIRMED rows on real recipes', () {
    for (final (file, edit) in <(String, Recipe Function(Recipe))>[
      ('1133-chicken-francese.yaml', undredged1133),
      ('0148-crispy-fried-chicken.yaml', undredged0148),
      ('0129-indoor-pulled-chicken.yaml', unstrained0129),
    ]) {
      // v26 (Run 056 S1): and with a line inserted before every confirmed
      // row in the same save, so each derived write lands at its row's NEW
      // position.
      for (final shift in [0, 1]) {
        test(
          '$file: every line with a food confirmed, a step edited${shift == 1 ? ' and a line inserted first' : ''} and the '
          'recipe recomputed — every decision stands and every derived '
          'field is what a confirm on the edited recipe writes',
          () async {
            final (db, provider, r) = await computed(file);
            final confirmed = <int>[];
            for (final m in db.ingredientMatchesFor(r.id)) {
              if (m.fdcId == null || m.status != 'auto') {
                continue;
              }
              try {
                await applyMatchOverride(db, provider, r, m.position, {
                  'raw': m.raw,
                  'confirmed': true,
                });
                confirmed.add(m.position);
              } on ZeroRowException {
                // A below-gate zero row: no confirm (Run 046).
              }
            }
            expect(confirmed.length, greaterThan(3));
            final edited = shift == 1 ? withWaterFirst(edit(r)) : edit(r);
            await editAndCompute(db, provider, edited);
            expect(nutritionIsFresh(db, edited), isTrue);
            for (final old in confirmed) {
              final position = old + shift;
              final now = rowOf(db, r, position);
              final fresh = await freshConfirm(edited, position, now.fdcId);
              expect(shape(now), shape(fresh), reason: '$file #$position');
              expect((now.status, now.fdcId), ('confirmed', fresh.fdcId));
            }
            // Re-deriving an unchanged recipe writes no decided row.
            final stamps = [
              for (final old in confirmed) rowOf(db, r, old + shift).updatedAt,
            ];
            await matchAndCompute(db, provider, edited);
            expect([
              for (final old in confirmed) rowOf(db, r, old + shift).updatedAt,
            ], stamps);
          },
        );
      }
    }
  }, skip: skipIfNoCorpus);
}

/// A provider that runs [onSearch] once, at its first search, then answers
/// from [inner]: a save during a compute's awaits.
class _SaveOnFirstSearch implements NutritionProvider {
  _SaveOnFirstSearch(this.inner, this.onSearch);

  final NutritionProvider inner;
  final void Function() onSearch;
  bool saved = false;

  @override
  Future<List<FdcCandidate>> search(String query) {
    if (!saved) {
      saved = true;
      onSearch();
    }
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}
