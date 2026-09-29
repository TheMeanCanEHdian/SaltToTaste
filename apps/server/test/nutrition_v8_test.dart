import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Matcher v8 (checkpoint 5): every mechanism pinned WITHOUT the corpus —
/// real corpus lines and step texts embedded as strings (recipe named on
/// each), FDC answers from the recorded fixtures (test/fixtures/fdc, the
/// sweep snapshot's cached answers).
void main() {
  final provider = FixtureProvider();
  Future<List<RankedCandidate>> rank(
    String query, {
    bool dropConnectors = connectorTokensDropped,
  }) async => rankCandidates(
    query,
    await provider.search(query),
    dropConnectors: dropConnectors,
  );
  Future<FdcFood> food(int id) async => (await provider.food(id))!;

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  GramResolution? gramsOf(
    String raw, [
    FdcFood? on,
    // ignore: avoid_positional_boolean_parameters
    bool wholeBird = wholeBirdYieldOn,
  ]) {
    final line = lineOf(raw);
    return resolveGrams(
      amounts: line.amounts,
      food: on,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: raw,
      wholeBirdYield: wholeBird,
    );
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v8');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    SaltDatabase db,
    String id,
    List<String> raws, {
    List<String> steps = const [],
  }) {
    final recipe = Recipe(
      id: id,
      title: id,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  Future<Map<dynamic, dynamic>> matchOf(
    SaltDatabase db,
    Recipe recipe,
    int position,
  ) async {
    final items = (await matchesBody(db, provider, recipe))['items']! as List;
    return items[position] as Map;
  }

  Future<String?> basisOf(SaltDatabase db, Recipe recipe, int position) async =>
      ((await matchOf(db, recipe, position))['match'] as Map)['gram_basis']
          as String?;

  // Tinga de Pollo (0482): a second food no rule counts.
  const chipotle =
      '2 tablespoons minced canned chipotle chile in adobo sauce plus 2 '
      'teaspoons adobo sauce';
  // Italian-Style Grilled Chicken (0423).
  const lemon = '1 teaspoon grated lemon zest plus 2 tablespoons juice';
  // Duchess Potato Casserole (0447).
  const duchess = '1 large egg, separated, plus 2 large yolks';
  // Crisp-Skin High-Roast Butterflied Turkey (0165): its brine.
  // A LINE-held medium keyed like a plain line (brine sugars went to zero
  // under the user's ruling R3, 2026-09-28): Sesame-Lemon Cucumber Salad's
  // (0052) salt, rinsed off the cucumbers (R2), beside Wheat Berry Salad's
  // (1073) plain "½ teaspoon table salt" — both keyed 'table salt'.
  const rinsedSalt = '1 tablespoon table salt';
  const cucumberSteps =
      'Toss the cucumbers with the salt in a colander set over a large '
      'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag filled '
      'with water; drain for 1 to 3 hours. Rinse and pat dry.';
  const plainSalt = '½ teaspoon table salt';

  group('M1: a line hold never clears by key', () {
    test(
      'a confirm with apply_to_all on a second_food tail key reaches no '
      'sibling and leaves it held; an inherited decision keeps the hold',
      () async {
        final db = tempDb();
        final a = recipeOf(db, 'ra', [chipotle]);
        final b = recipeOf(db, 'rb', [chipotle]);
        for (final r in [a, b]) {
          await matchAndCompute(db, provider, r);
        }
        final before = db.ingredientMatchesFor('rb').single;
        expect(before.hold, 'second_food');
        final item = await matchOf(db, a, 0);
        expect((item['others'], item['others_lines']), (0, 0));
        final applied = await applyMatchOverride(db, provider, a, 0, {
          'confirmed': true,
          'apply_to_all': true,
        });
        expect((applied!.recipes, applied.lines), (0, 0));
        final after = db.ingredientMatchesFor('rb').single;
        expect(
          (after.hold, after.confidence, bucketOf(after)),
          ('second_food', before.confidence, MatchBucket.check),
        );
        // A recipe computed later inherits the decision (confidence 1) and
        // keeps the line hold: the decision names the chile, not the sauce.
        final c = recipeOf(db, 'rc', [chipotle]);
        await matchAndCompute(db, provider, c);
        final inherited = db.ingredientMatchesFor('rc').single;
        expect((inherited.confidence, inherited.hold), (1, 'second_food'));
        expect(bucketOf(inherited), MatchBucket.check);
      },
    );

    test('confirming a plain table salt reports 0 applied rinsed salts, and '
        'they stay held', () async {
      final db = tempDb();
      final plain = recipeOf(db, 'plain', [plainSalt]);
      final cucumbers = recipeOf(
        db,
        'cucumbers',
        [rinsedSalt],
        steps: [cucumberSteps],
      );
      for (final r in [plain, cucumbers]) {
        await matchAndCompute(db, provider, r);
      }
      final rinsed = db.ingredientMatchesFor('cucumbers').single;
      expect(rinsed.hold, 'discarded_medium');
      final item = await matchOf(db, plain, 0);
      expect(item['others'], 0);
      final applied = await applyMatchOverride(db, provider, plain, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied!.lines, 0);
      final after = db.ingredientMatchesFor('cucumbers').single;
      expect((after.hold, after.grams), ('discarded_medium', rinsed.grams));
      expect(bucketOf(after), MatchBucket.check);
    });

    test('a cured_for_fresh sibling is still reached and released', () async {
      final db = tempDb();
      // Roast Fresh Ham (0249). (Fresh oregano, this pin's line until v13,
      // counts on the dried spice now: the user's ruling R4.) v14 takes the
      // fresh shank half for it (checkpoint 8, B7), whose detail no snapshot
      // holds, so both rows are written as snapshot 12 stores them — the
      // state a live library holds until its next compute.
      const ham =
          '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
          'shank end, rinsed';
      final a = recipeOf(db, 'ra', [ham]);
      recipeOf(db, 'rb', [ham]);
      for (final id in ['ra', 'rb']) {
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: id,
            position: 0,
            raw: ham,
            itemKey: 'bone-in half ham with skin',
            fdcId: 168367,
            description:
                'Pork, cured, ham, rump, bone-in, separable lean and fat, '
                'unheated',
            dataType: 'SR Legacy',
            confidence: 0.5,
            grams: 3628.736,
            gramSource: 'weight',
            status: 'auto',
            hold: 'cured_for_fresh',
          ),
        );
      }
      expect((await matchOf(db, a, 0))['others'], 1);
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(applied!.lines, 1);
      final after = db.ingredientMatchesFor('rb').single;
      expect((after.hold, after.confidence), (null, 1));
      expect(bucketOf(after), MatchBucket.counted);
    });

    test('P3: the reach SQL — a held second_food or discarded_medium sibling '
        'is not in others or others_lines, a held dried_for_fresh one is', () {
      final db = tempDb();
      // Five recipes holding the 0423 line, their rows as the engine writes
      // them on one food: the holds are the only difference.
      IngredientMatchRow row(String id, String? hold, double confidence) =>
          IngredientMatchRow(
            recipeId: id,
            position: 0,
            raw: lemon,
            itemKey: 'k',
            fdcId: 167747,
            description: 'Lemon juice, raw',
            dataType: 'SR Legacy',
            confidence: confidence,
            grams: 30,
            gramSource: 'density',
            status: 'auto',
            hold: hold,
          );
      for (final (id, hold, confidence) in [
        ('r0', null, 0.95),
        ('r1', 'second_food', 0.95),
        ('r2', 'discarded_medium', 0.95),
        ('r3', 'dried_for_fresh', 0.95),
        // A line hold below the gate is not reached either.
        ('r4', 'second_food', 0.3),
      ]) {
        recipeOf(db, id, [lemon]);
        db.upsertIngredientMatchIfUndecided(row(id, hold, confidence));
      }
      const excluding = (recipeId: 'r0', position: 0);
      expect(
        [
          for (final target in db.undecidedMatchesForItemKey(
            'k',
            excluding: excluding,
            fdcId: 167747,
            belowConfidence: lowConfidence,
          ))
            (target.recipeId, target.hold),
        ],
        [('r3', 'dried_for_fresh')],
      );
      // On another food a line-held row is still out of the reach.
      expect(
        db
            .undecidedMatchesForItemKey(
              'k',
              excluding: excluding,
              belowConfidence: lowConfidence,
              fdcId: 1,
            )
            .length,
        1,
        reason: 'r3 only',
      );
    });

    test('P4: applied counts the rows whose bucket changed — a row re-held '
        'by a line hold is written but not applied', () async {
      final db = tempDb();
      final plain = recipeOf(db, 'plain', [plainSalt]);
      // An older build's rows, below the gate and unheld: the rinsed salt
      // (0052) and a plain salt line (1073).
      recipeOf(db, 'turkey', [rinsedSalt], steps: [cucumberSteps]);
      recipeOf(db, 'other', [plainSalt]);
      for (final id in ['turkey', 'other']) {
        db.upsertIngredientMatchIfUndecided(
          IngredientMatchRow(
            recipeId: id,
            position: 0,
            raw: id == 'turkey' ? rinsedSalt : plainSalt,
            itemKey: 'table salt',
            fdcId: 173468,
            description: 'Salt, table',
            dataType: 'SR Legacy',
            confidence: 0.3,
            grams: 10,
            gramSource: 'density',
            status: 'auto',
          ),
        );
      }
      await matchAndCompute(db, provider, plain);
      final applied = await applyDecisionToOthers(
        db,
        provider,
        itemKey: 'table salt',
        decided: await food(173468),
        excluding: (recipeId: plain.id, position: 0),
      );
      expect((applied.recipes, applied.lines), (1, 1));
      final reheld = db.ingredientMatchesFor('turkey').single;
      expect((reheld.hold, reheld.confidence), ('discarded_medium', 1));
      expect(bucketOf(reheld), MatchBucket.check);
      expect(
        bucketOf(db.ingredientMatchesFor('other').single),
        MatchBucket.counted,
      );
    });
  });

  group('M2: desiccated coconut', () {
    test('Triple-Coconut Macaroons (0831): 3 cups on 170170, sized 3 × 93 g '
        'from its shredded sibling (168586), fetched once', () async {
      final db = tempDb();
      final fixtures = FixtureProvider();
      const coconut =
          '3 cups unsweetened, shredded, desiccated (dried) coconut';
      final r = recipeOf(db, 'r1', [coconut]);
      expect(
        searchQueryFor(normalizeItem(lineItemOf(lineOf(coconut)))),
        'nuts coconut meat dried not sweetened',
      );
      await matchAndCompute(db, fixtures, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, bucketOf(row)), (170170, MatchBucket.counted));
      expect(row.grams, closeTo(279, 0.01));
      expect(fixtures.foodCalls, 2, reason: '170170 and its sibling');
      expect(
        await basisOf(db, r, 0),
        contains(
          '"Nuts, coconut meat, dried (desiccated), sweetened, '
          'shredded"',
        ),
      );
      expect(
        (await rank(
          'nuts coconut meat dried not sweetened',
        )).first.candidate.fdcId,
        170170,
      );
    });
  });

  group('M3: a salt dissolved with the brine salt is brine', () {
    // Home-Corned Beef with Vegetables (0091), its first step.
    const step =
        'Trim fat on surface of brisket to ⅛ inch. Dissolve salt, sugar, and '
        'curing salt in 4 quarts water in large container. Add brisket, 3 '
        'garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon '
        'peppercorns, and coriander seeds to brine. Weigh brisket down with '
        'plate, cover, and refrigerate for 6 days';
    const raws = [
      '¾ cup salt',
      '½ cup packed brown sugar',
      '2 teaspoons pink curing salt #1',
    ];

    test('the three brine lines at 0 g: salt, curing salt and — the '
        "user's ruling R3, 2026-09-28 — the brown sugar", () async {
      final db = tempDb();
      final r = recipeOf(db, 'corned', raws, steps: [step]);
      DiscardedMedium? of(int i, {bool bySentence = true}) {
        final line = nutritionLines(r)[i];
        return discardedMediumOf(
          r,
          line,
          normalizeItem(lineItemOf(line)),
          bySentence: bySentence,
        );
      }

      expect(
        [of(0), of(1), of(2)],
        [
          DiscardedMedium.brine,
          DiscardedMedium.brineSugar,
          DiscardedMedium.brine,
        ],
      );
      // 2 teaspoons alone are under the 3-tablespoon threshold.
      expect(of(2, bySentence: false), isNull);
      await matchAndCompute(db, provider, r);
      final rows = db.ingredientMatchesFor('corned');
      expect(
        [for (final row in rows) (row.grams, row.gramSource, row.hold)],
        [
          (0, 'discarded', null),
          (0, 'discarded', null),
          (0, 'discarded', null),
        ],
      );
    });
  });

  group('M4: the citrus and egg second foods count by rule', () {
    test('0423: the zest plus juice counts the juice on "Lemon juice, raw", '
        'the zest dropped, with a basis that says so', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [lemon]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.hold), (167747, null));
      expect(row.grams, closeTo(2 * 14.7868 * 1.03, 0.01));
      expect(row.confidence, greaterThanOrEqualTo(lowConfidence));
      expect(bucketOf(row), MatchBucket.counted);
      expect(
        await basisOf(db, r, 0),
        '2 tablespoon ≈ 30 mL · juice only (the zest is dropped)',
      );
    });

    test('juice first ("½ cup juice plus 2½ teaspoons grated zest from 3 '
        'lemons") keeps its juice grams and clears too', () {
      // Chilled Lemon Soufflé (0937).
      final line = lineOf(
        '½ cup juice plus 2½ teaspoons grated zest from 3 lemons',
      );
      expect(lineKeyOf(line), 'lemon zest plus juice');
      final rule = secondFoodRuleOf(line)!;
      expect(rule.fdcId, 167747);
      expect(rule.gramsOn(null)!.grams, closeTo(236.588 / 2 * 1.03, 0.01));
      // Over a tablespoon of peel is no garnish (Crispy Orange Beef, 0536):
      // held.
      expect(
        secondFoodRuleOf(
          lineOf(
            '10 (3-inch) strips orange peel, sliced thin lengthwise (¼ cup), '
            'plus ¼ cup juice (2 oranges)',
          ),
        ),
        isNull,
      );
    });

    test('Duchess Potato Casserole (0447): the egg and its yolks sum on the '
        'whole-egg record, 50 + 34 g', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [duchess]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect((row.fdcId, row.grams, row.hold), (748967, 84, null));
      expect(bucketOf(row), MatchBucket.counted);
      expect(
        await basisOf(db, r, 0),
        '1 × 50 g egg + 2 × 17 g yolk, summed on the whole egg',
      );
      // Led by a part, the line stays held (Coconut Layer Cake, 0878).
      expect(
        secondFoodRuleOf(
          lineOf('5 large egg whites plus 1 large egg, at room temperature'),
        ),
        isNull,
      );
    });

    test(
      'P1: both switches, on a real line each — off restores the hold',
      () async {
        final r = recipeOf(tempDb(), 'r1', [lemon, duchess]);
        final juice = await food(167747);
        final egg = await food(748967);
        final lines = nutritionLines(r);
        for (final (line, record, off) in [
          (lines[0], juice, (citrus: false, eggs: true)),
          (lines[1], egg, (citrus: true, eggs: false)),
        ]) {
          final on = engineOutcome(r, line, record, null, picked: true);
          expect(on.hold, isNull);
          expect(on.grams, isNotNull);
          final held = engineOutcome(
            r,
            line,
            record,
            null,
            picked: true,
            citrus: off.citrus,
            eggs: off.eggs,
          );
          expect(held.hold, 'second_food', reason: line.raw);
        }
        expect(citrusJuiceRuleOn, isTrue);
        expect(eggPartsMassSumOn, isTrue);
      },
    );

    test('keys: either order, "whole" and a "with" tail are one key', () {
      for (final (raw, key) in [
        (lemon, 'lemon zest plus juice'),
        // Chilled Lemon Soufflé (0937); Crêpes Suzette (0960); Quiche
        // Lorraine (0742); Almond Biscotti (0841).
        (
          '½ cup juice plus 2½ teaspoons grated zest from 3 lemons',
          'lemon zest plus juice',
        ),
        (
          '1¼ cups juice plus 1 tablespoon finely grated zest from 3 to 4 '
              'large oranges',
          'orange zest plus juice',
        ),
        ('2 large whole eggs plus 2 large egg yolks', 'egg plus yolk'),
        (
          '2 large eggs, plus 1 large white beaten with pinch salt',
          'egg plus white',
        ),
        (duchess, 'egg plus yolk'),
      ]) {
        expect(lineKeyOf(lineOf(raw)), key, reason: raw);
      }
    });

    test('a key decision leaves a rule line alone; a pick of the rule record '
        'on the line takes the rule grams', () async {
      final db = tempDb();
      final a = recipeOf(db, 'ra', [lemon]);
      final b = recipeOf(db, 'rb', [lemon]);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      // A person re-picks "Lemon peel, raw" on one line, for every line.
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 167749,
        'apply_to_all': true,
      });
      expect(applied!.lines, 0);
      expect(db.ingredientMatchesFor('rb').single.fdcId, 167747);
      // Picking the juice record back is the rule's grams, not the zest's.
      await applyMatchOverride(db, provider, a, 0, {'fdc_id': 167747});
      final row = db.ingredientMatchesFor('ra').single;
      expect((row.status, row.fdcId), ('overridden', 167747));
      expect(row.grams, closeTo(2 * 14.7868 * 1.03, 0.01));
    });
  });

  group('M5: coverage credits on recorded answers (matcher v8)', () {
    test('every credit moves its recorded line over the gate', () async {
      // Each query is a library line's (checkpoint-5 gate band); each was
      // below 0.5 on this answer before its credit.
      for (final (query, top) in [
        // chile → pepper, on the ranker's stems 'chil' and 'chile'.
        ('jalapeno chiles', 2747661),
        ('serrano chile', null),
        // zest → peel.
        ('lemon zest', 167749),
        // Spice qualifiers on a 'Spices,' record.
        ('smoked paprika', 171329),
        ('sweet paprika', 171329),
        ('ground cardamom', null),
        ('smoked hot paprika', 171329),
        // Descriptor words no record of the food carries.
        ('english cucumber', null),
        ('plum tomatoes', null),
        ('slivered almonds', null),
        ('saffron threads', null),
        ('pecorino romano', null),
        ('littleneck clams', null),
        ('ripe avocados', null),
        ('prewashed quinoa', null),
        // Easy Apple Strudel (0957), "1 medium McIntosh apple": "Apple,
        // raw". (The plural answer holds only Fuji and Gala among raw
        // apples: no credit there since matcher v9 — nutrition_v9_test.)
        ('mcintosh apple', 2709215),
        ('pearl barley', null),
        ('seedless raspberry jam', null),
        ('unseasoned rice vinegar', null),
      ]) {
        final ranked = await rank(query);
        expect(
          ranked.first.confidence,
          greaterThanOrEqualTo(lowConfidence),
          reason: query,
        );
        if (top != null) {
          expect(ranked.first.candidate.fdcId, top, reason: query);
        }
      }
    });

    test('precision stays literal: jalapeno chiles keep the Foundation raw '
        'record, not FNDDS "Peppers, jalapenos"', () async {
      final ranked = await rank('jalapeno chiles');
      expect(ranked.first.candidate.fdcId, 2747661);
      final fndds = ranked.indexWhere((c) => c.candidate.fdcId == 2710096);
      expect(fndds, anyOf(-1, greaterThan(0)));
    });

    test('the head guard: red plums are plums, not "Sangria, red"', () async {
      final ranked = await rank('red plums');
      expect(ranked.first.candidate.description, 'Plums, raw');
    });

    test('pods count the spice: cardamom pods', () async {
      expect(headNounOf('green cardamom pods'), 'cardamom');
      expect(
        (await rank('green cardamom pods')).first.candidate.description,
        'Spices, cardamom',
      );
    });

    test('lemon zest counts on the peel at its own teaspoon (2 g)', () async {
      expect(
        gramsOf('1 teaspoon grated lemon zest', await food(167749))!.grams,
        2,
      );
    });

    test('whole dried red chiles are never counted (Orange-Flavored Chicken, '
        '0525)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '8 small whole dried red chiles (optional)',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect(bucketOf(row), isNot(MatchBucket.counted));
    });
  });

  group('M6: volume grams from a cached SR sibling; parsed units', () {
    test('onion (Best Crab Cakes, 0289) and red onion (0055) on the Foundation '
        'records read "Onions, raw" (170000); pistachios (0050) read the dry '
        'roasted record (170185)', () async {
      for (final (raw, record, grams) in [
        ('½ cup chopped onion', 790646, 80.0),
        ('2 tablespoons minced red onion', 790577, 20.0),
        ('⅓ cup shelled pistachios, chopped', 2515379, 123 / 3),
      ]) {
        final db = tempDb();
        final fixtures = FixtureProvider();
        final line = lineOf(raw);
        final own = await food(record);
        expect(gramsOf(raw, own), isNull, reason: 'no volume portion: $raw');
        final (_, resolution) = await gramsFor(db, fixtures, own, line);
        expect(resolution!.grams, closeTo(grams, 0.01), reason: raw);
        expect(resolution.basis, contains('of "'), reason: raw);
        // Cached now: the next line asks nothing.
        final (_, again) = await gramsFor(db, fixtures, own, line);
        expect(again!.grams, resolution.grams);
        expect(fixtures.foodCalls, 2, reason: 'the record and its sibling');
      }
    });

    test('a size before a sprig is still a sprig: "2 small sprigs fresh '
        'rosemary" (0221) counts 0 g', () {
      final sprig = gramsOf('2 small sprigs fresh rosemary')!;
      expect((sprig.grams, sprig.source), (0, GramSource.unmeasured));
    });

    test('so are a medium and a large sprig: "1 medium sprig fresh rosemary '
        '(optional)" (0453, its only blocker), "1 large sprig fresh thyme" '
        '(0084) and "3 large sprigs fresh thyme" (0462)', () {
      for (final raw in [
        '1 medium sprig fresh rosemary (optional)',
        '1 large sprig fresh thyme',
        '3 large sprigs fresh thyme',
      ]) {
        final sprig = gramsOf(raw)!;
        expect(
          (sprig.grams, sprig.source),
          (0, GramSource.unmeasured),
          reason: raw,
        );
      }
    });
  });

  group('M7: rewrites to recorded stand-ins', () {
    test('each rewrite ranks its intended record first', () async {
      for (final (raw, target, top) in [
        // Hearty Minestrone (0028). Pancetta is an approximation the user
        // flagged: FDC's answer for 'pancetta' is [].
        (
          '3 ounces pancetta, cut into ¼-inch pieces',
          'pork cured bacon unprepared',
          168277,
        ),
        // Almond-Crusted Chicken (0042).
        ('½ cup panko (Japanese-style bread crumbs)', 'bread crumbs', 174928),
        // Classic Gingerbread Cake (0876).
        ('¾ cup stout, such as Guinness', 'beer', null),
        // Garlicky Shrimp Pasta (0346); Pasta Cacio e Uova (1131).
        (
          '1 pound mezze rigatoni, fusilli, or campanelle',
          'pasta dry enriched',
          169736,
        ),
        ('8 ounces (1½ cups) tubetti', 'pasta dry enriched', 169736),
        // Beef Wellington (1129).
        ('1 tablespoon Madeira', 'wine dessert dry', 175112),
        // Lumpiang Shanghai (1194).
        ('⅔ cup sukang maasim', 'vinegar', null),
      ]) {
        final query = searchQueryFor(normalizeItem(lineItemOf(lineOf(raw))));
        expect(query, target, reason: raw);
        final ranked = await rank(query);
        expect(ranked.first.confidence, greaterThanOrEqualTo(lowConfidence));
        if (top != null) {
          expect(ranked.first.candidate.fdcId, top, reason: raw);
        }
      }
      expect((await rank('beer')).first.candidate.description, 'Beer');
      expect((await rank('vinegar')).first.candidate.description, 'Vinegar');
    });
  });

  group('M8: normalizer leaks and small fixes', () {
    test('a dropped word leaves no connector, measure or adverb in the '
        'key', () {
      for (final (raw, key) in [
        // Mulligatawny Soup (0027); Cranberry Chutney (0178); Espinacas con
        // Garbanzos (1075); Thai-Style Chicken with Basil (0547); Foolproof
        // Vinaigrette (0038); Best Chicken Parmesan (0415); Easier Fried
        // Chicken (0149).
        ('1½ tablespoons minced or grated fresh ginger', 'ginger'),
        ('12 ounces (3 cups) fresh or frozen cranberries', 'cranberry'),
        ('1 small pinch saffron', 'saffron'),
        ('2 cups tightly packed fresh basil leaves', 'basil leaf'),
        ('1½ teaspoons very finely minced shallot', 'shallot'),
        ('¼ cup torn fresh basil', 'basil'),
        ('Dash of hot sauce', 'hot sauce'),
        // Paris-Brest (0908); Penne Arrabbiata (0334): the prep-only
        // segments leave the key.
        ('2 tablespoons toasted, skinned, and chopped hazelnuts', 'hazelnut'),
        ('¼ cup stemmed, patted dry, and minced pepperoncini', 'pepperoncini'),
        // A form segment is kept (Watermelon Salad with Cotija, 1071): the
        // cached query is the roasted one.
        (
          '5 tablespoons chopped roasted, salted pepitas, divided',
          'roasted with salt pepita',
        ),
      ]) {
        expect(lineKeyOf(lineOf(raw)), key, reason: raw);
      }
      // "very" stays before what is not a prep word: a very ripe banana.
      expect(normalizeItem('very ripe bananas'), 'very ripe bananas');
      // A colour segment is kept (Classic Stuffed Bell Peppers, 0308).
      expect(
        lineItemOf(
          const IngredientLine(
            raw:
                '4 medium red, yellow, or orange bell peppers (about 6 ounces '
                'each), ½ inch trimmed off tops, cores and seeds discarded',
            item: 'medium red',
          ),
        ),
        startsWith('red yellow or orange bell peppers'),
      );
    });

    test('the leaked keys read their cached siblings: hazelnuts count at '
        '0.99, pepperoncini is a truthful no-match', () async {
      expect((await rank('hazelnuts')).first.confidence, greaterThan(0.9));
      expect(await provider.search('pepperoncini'), isEmpty);
    });

    test('lollipop or popsicle sticks are equipment (Chocolate Cherry Pie '
        'Pops, 1206)', () {
      expect(
        isNonFood(normalizeItem('(4- to 6-inch) lollipop or popsicle sticks')),
        isTrue,
      );
    });

    test('a pinch with no dash portion says it is a sixteenth of the '
        'teaspoon, trimmed (Super Greens Soup, 0021)', () async {
      final cayenne = await food(170932);
      final pinch = gramsOf('Pinch cayenne pepper', cayenne)!;
      expect(pinch.grams, closeTo(1.8 / 16, 1e-9));
      expect(pinch.basis, 'pinch ≈ 1/16 tsp (USDA tsp portion)');
      // A record with a dash portion keeps its own (Turkey Tetrazzini, 0303:
      // "Salt, table" 173468 "dash" 0.4 g).
      final salt = gramsOf('Pinch table salt', await food(173468))!;
      expect((salt.grams, salt.basis), (0.4, 'pinch · USDA portion'));
    });
  });

  group('M9: whole birds and fetch hygiene', () {
    const chicken = '1 (4-pound) whole chicken, giblets discarded';
    const pieces =
        '3½ pounds bone-in, skin-on chicken pieces (split breasts cut in '
        'half, drumsticks, and/or thighs), trimmed';
    const hens = '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded';

    test('P1: a whole chicken (Pressure-Cooker Chicken Noodle Soup, 0004) '
        'counts 0.608 of its printed weight on 171447; off, the printed '
        'weight', () async {
      final bird = await food(171447);
      expect(wholeBirdYieldOn, isTrue);
      final on = gramsOf(chicken, bird)!;
      expect(on.grams, closeTo(4 * 453.592 * 276 / 453.592, 0.01));
      expect(on.basis, contains('× 0.61 edible (USDA ready-to-cook yield)'));
      final off = gramsOf(chicken, bird, false)!;
      expect(off.grams, closeTo(4 * 453.592, 0.01));
      // Off, the gross weight on a record with no refuse portion: labelled
      // approximate (checkpoint 6).
      expect(
        off.basis,
        endsWith('· approximate (gross weight, no USDA refuse portion)'),
      );
    });

    test('P1: pieces (Stovetop Roast Chicken, 0142) stay at gross weight, '
        'labelled approximate; off, the plain basis', () async {
      final bird = await food(171447);
      final on = gramsOf(pieces, bird)!;
      expect(on.grams, closeTo(3.5 * 453.592, 0.01));
      expect(
        on.basis,
        endsWith('· approximate (gross weight, no USDA refuse portion)'),
      );
      final off = gramsOf(pieces, bird, false)!;
      expect(off.grams, on.grams);
      expect(off.basis, on.basis);
    });

    test("P1: counted hens (Roasted Cornish Game Hens, 0147) are the record's "
        'own bird, 4 × 336 g; off, 4 × 1½ pounds', () async {
      final hen = await food(171507);
      final on = gramsOf(hens, hen)!;
      expect((on.grams, on.source), (4 * 336, GramSource.piece));
      expect(on.basis, '4 × 336 g (USDA edible bird portion)');
      expect(gramsOf(hens, hen, false)!.grams, closeTo(4 * 1.5 * 453.592, 0.1));
      // A turkey is no standard bird: Classic Roast Turkey (0154) keeps its
      // printed weight on 171081, whose "bird" is 5,002 g.
      final turkey = gramsOf(
        '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and '
        'reserved for gravy',
        await food(171081),
      )!;
      expect(turkey.grams, closeTo(14 * 453.592, 0.01));
    });

    test("a part record's ready-to-cook yield is never read: a whole turkey "
        'breast (Turkey Breast en Cocotte, 0173) on 171093', () async {
      final breast = gramsOf(
        '1 (5- to 7-pound) whole bone-in turkey breast, trimmed',
        await food(171093),
      )!;
      expect(breast.grams, closeTo(7 * 453.592, 0.01));
      expect(
        breast.basis,
        endsWith('· approximate (gross weight, no USDA refuse portion)'),
      );
      // Nor for a whole bird matched to the part record (Classic Roast
      // Turkey, 0154, on the breast's 171093): its "yield from 1 lb
      // ready-to-cook turkey" is the breast's share, not the bird's yield.
      final turkey = gramsOf(
        '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and '
        'reserved for gravy',
        await food(171093),
      )!;
      expect(turkey.grams, closeTo(14 * 453.592, 0.01));
    });

    test('a yield or drain detail is fetched only for SR Legacy: a '
        'Foundation can of chickpeas (Mediterranean Chopped Salad, 0044) '
        'asks nothing, an SR bird does', () async {
      FdcFood hit(FdcFood detail) => FdcFood(
        fdcId: detail.fdcId,
        description: detail.description,
        dataType: detail.dataType,
        nutrientsPer100g: detail.nutrientsPer100g,
        portions: const [],
      );
      final can = await food(2644288);
      expect(can.dataType, 'Foundation');
      final fixtures = FixtureProvider();
      await gramsFor(
        tempDb(),
        fixtures,
        hit(can),
        lineOf('1 (15-ounce) can chickpeas, drained and rinsed'),
      );
      expect(fixtures.foodCalls, 0);
      final (_, grams) = await gramsFor(
        tempDb(),
        fixtures,
        hit(await food(171447)),
        lineOf(chicken),
      );
      expect(fixtures.foodCalls, 1);
      expect(grams!.grams, closeTo(4 * 276, 0.01));
    });
  });

  group('M10: connector tokens (switch, measured apart)', () {
    test("P1: 'canola or vegetable oil' (Pan-Seared Salmon, 0256) is canola "
        'oil, not a Spanish rice mix; off, the old pick', () async {
      expect(connectorTokensDropped, isTrue);
      final on = await rank('canola or vegetable oil');
      expect(on.first.candidate.description, contains('canola'));
      expect(on.first.candidate.description, isNot(contains('rice')));
      final off = await rank('canola or vegetable oil', dropConnectors: false);
      expect(off.first.candidate.fdcId, 169777);
    });

    test('P1: an unqualified cut (Best Beef Stew, 0005) takes the lean-and-fat '
        'record; off, it ties with lean only — and the tie goes to lean and '
        "fat (v11), where FDC's order gave lean only", () async {
      final on = await rank('boneless chuck-eye roast');
      expect(on.first.candidate.description, contains('lean and fat'));
      expect(on.first.confidence, greaterThan(on[3].confidence));
      final off = await rank('boneless chuck-eye roast', dropConnectors: false);
      expect(off.first.candidate.description, contains('lean and fat'));
      expect(off[2].candidate.description, contains('lean only'));
      expect(off.first.confidence, off[2].confidence);
    });
  });

  group('M11: ranker and grams tidy-ups', () {
    test('plain long-grain rice is white (Avgolemono 0005, Rice Salad 0062, '
        'Rice Pilaf 0709); an onion stays yellow', () async {
      for (final query in [
        'long-grain rice',
        'long-grain or basmati rice',
        'basmati or long-grain rice',
      ]) {
        expect(
          (await rank(query)).first.candidate.fdcId,
          2512381,
          reason: query,
        );
      }
      expect((await rank('onion')).first.candidate.fdcId, 790646);
    });

    test("a volume portion in the line's unit, then the plain form, before "
        'the median', () async {
      // Carne Adovada (0494): "tsp, leaves" 1.0 g, not "tsp, ground" 1.8 g.
      expect(
        gramsOf('2 teaspoons dried Mexican oregano', await food(171328))!.grams,
        closeTo(2.0, 0.01),
      );
      // Pan-Seared Pork Chops (0199): "cup (not packed)" 145 g.
      expect(
        gramsOf('½ cup golden raisins', await food(168164))!.grams,
        closeTo(72.5, 0.01),
      );
      // Crisp Roast Butterflied Chicken (0144): its own "tbsp" 1.7 g.
      expect(
        gramsOf(
          '1 tablespoon minced fresh rosemary',
          await food(173473),
        )!.grams,
        closeTo(1.7, 0.01),
      );
      // A spice's plain form is ground: black pepper "tsp, ground" 2.3 g.
      expect(
        gramsOf('1 teaspoon pepper', await food(170931))!.grams,
        closeTo(2.3, 0.01),
      );
    });

    test('a cured record for a fresh meat is held as cured_for_fresh; a '
        "fresh oregano line counts on the dried spice (the user's ruling "
        'R4, 2026-09-28) (Roast Fresh Ham 0249; Ciambotta 0405)', () {
      expect(
        freshHoldOf(
          '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
              'shank end, rinsed',
          'Pork, cured, ham, rump, bone-in, separable lean only, unheated',
        ),
        'cured_for_fresh',
      );
      expect(
        freshHoldOf('⅓ cup fresh oregano leaves', 'Spices, oregano, dried'),
        isNull,
      );
      expect(
        freshHoldOf('1 teaspoon dried oregano', 'Spices, oregano, dried'),
        isNull,
      );
    });
  });

  group('refix round 1', () {
    test('a skinned line is not "meat and skin": whole chicken legs, skin '
        'removed (Oven-Fried Chicken, 0150), under both connector '
        'switches', () async {
      const raw =
          '4 whole chicken legs, separated into drumsticks and thighs and '
          'skin removed';
      expect(removesSkin(raw), isTrue);
      final answer = await provider.search('whole chicken legs');
      for (final drop in [true, false]) {
        final ranked = rankCandidates(
          'whole chicken legs',
          answer,
          skinless: removesSkin(raw),
          dropConnectors: drop,
        );
        expect(ranked.first.candidate.fdcId, 173619, reason: 'drop $drop');
      }
      // Without the dock the dropped 'and' ties the skin-on leg, first in
      // the answer: the regression.
      expect(
        rankCandidates('whole chicken legs', answer).first.candidate.fdcId,
        172378,
      );
      // Bone-in but skinned is meat only too (Juicy Grilled Turkey Burgers,
      // 0309): the bone-in dock on "meat only" is for a skin-on cut.
      const thigh =
          '1 (2-pound) bone-in turkey thigh, skinned, boned, trimmed, and cut '
          'into ½-inch pieces';
      expect(removesSkin(thigh), isTrue);
      final thighs = await provider.search('bone-in turkey thighs');
      for (final drop in [true, false]) {
        expect(
          rankCandidates(
            'bone-in turkey thigh',
            thighs,
            skinless: true,
            dropConnectors: drop,
          ).first.candidate.description,
          contains('meat only'),
          reason: 'drop $drop',
        );
      }
      // A line that names the skin keeps it (Simplified Cassoulet, 0461).
      expect(
        removesSkin(
          '10 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed and '
          'skin removed',
        ),
        isTrue,
      );
    });

    test('the engine wires the skin dock: matchAndCompute and the '
        'candidates list pick meat only for a skinned line, and a line that '
        'names the skin keeps its skin-on pick', () async {
      // Oven-Fried Chicken (0150), Juicy Grilled Turkey Burgers (0309),
      // Simplified Cassoulet (0461): without the call-site argument the
      // first two take the skin-on leg (172378) and "…thigh, meat and
      // skin"; without the names-skin exemption the third counts "Chicken,
      // skin (drumsticks and thighs)".
      const legs =
          '4 whole chicken legs, separated into drumsticks and thighs and '
          'skin removed';
      const thigh =
          '1 (2-pound) bone-in turkey thigh, skinned, boned, trimmed, and cut '
          'into ½-inch pieces';
      const thighs =
          '10 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed and '
          'skin removed';
      const raws = [legs, thigh, thighs];
      const picks = [173619, 174518, 2727567];
      final db = tempDb();
      final r = recipeOf(db, 'r1', raws);
      await matchAndCompute(db, provider, r);
      expect(
        [for (final row in db.ingredientMatchesFor('r1')) row.fdcId],
        [
          ...picks,
        ],
      );
      for (final (i, raw) in raws.indexed) {
        final listed = await candidatesForLine(
          db,
          provider,
          lineOf(raw),
          cacheOnly: true,
        );
        expect(listed.first.candidate.fdcId, picks[i], reason: raw);
      }
      expect(
        db.ingredientMatchesFor('r1').last.description,
        'Chicken, thigh, meat and skin, raw',
      );
    });

    test('"Turkey and gravy, frozen" is a dish: a whole frozen turkey (Roast '
        'Turkey for a Crowd, 0155) is not counted on it, under both '
        'connector switches', () async {
      for (final drop in [true, false]) {
        final ranked = await rank(
          'frozen butterball or kosher turkey',
          dropConnectors: drop,
        );
        final gravy = ranked.firstWhere((c) => c.candidate.fdcId == 171500);
        expect(gravy.docked, isTrue, reason: 'drop $drop');
        expect(ranked.first.candidate.fdcId, isNot(171500));
        expect(ranked.first.confidence, lessThan(lowConfidence));
      }
    });

    test("each fruit's zest plus juice counts on its OWN juice record: lime "
        '(Tinga de Pollo, 0482) and orange (Grilled Mojo-Marinated Skirt '
        'Steak, 0590)', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '1 teaspoon grated lime zest plus 2 tablespoons juice',
        '½ teaspoon grated orange zest plus ½ cup juice',
      ]);
      await matchAndCompute(db, provider, r);
      final rows = db.ingredientMatchesFor('r1');
      expect(
        [for (final row in rows) (row.fdcId, row.hold, bucketOf(row))],
        [
          (168156, null, MatchBucket.counted),
          (169098, null, MatchBucket.counted),
        ],
      );
      expect(rows[0].description, 'Lime juice, raw');
      expect(rows[1].description, startsWith('Orange juice, raw'));
    });

    test('eggs plus whites and yolks plus whites sum their parts too: Almond '
        'Biscotti (0841), Fluffy Yellow Layer Cake (0885)', () {
      for (final (raw, grams, basis) in [
        (
          '2 large eggs, plus 1 large white beaten with pinch salt',
          2 * 50 + 33,
          '2 × 50 g egg + 1 × 33 g white, summed on the whole egg',
        ),
        (
          '6 large egg yolks plus 3 large egg whites, at room temperature',
          6 * 17 + 3 * 33,
          '6 × 17 g yolk + 3 × 33 g white, summed on the whole egg',
        ),
      ]) {
        final rule = secondFoodRuleOf(lineOf(raw))!;
        expect(rule.fdcId, 748967, reason: raw);
        final resolved = rule.gramsOn(null)!;
        expect((resolved.grams, resolved.basis), (grams, basis), reason: raw);
      }
    });

    test(
      'the zest cap is one tablespoon: Crêpes Suzette (0960) at 1 '
      'tablespoon counts; Skillet-Roasted Chicken in Lemon Sauce (0142) at '
      '4 teaspoons and Lemon Pound Cake (0861) at 2 tablespoons stay held',
      () {
        expect(
          secondFoodRuleOf(
            lineOf(
              '1¼ cups juice plus 1 tablespoon finely grated zest from 3 to 4 '
              'large oranges',
            ),
          )?.fdcId,
          169098,
        );
        for (final raw in [
          '4 teaspoons grated lemon zest plus ¼ cup juice (2 lemons)',
          '2 tablespoons grated zest plus 2 teaspoons juice from 1 lemon',
        ]) {
          expect(secondFoodRuleOf(lineOf(raw)), isNull, reason: raw);
        }
      },
    );

    test("spice qualifiers are credited on a 'Spices,' record only: 80 "
        'percent lean ground chuck (Cincinnati Chili 0303), 90 percent lean '
        'ground sirloin (Skillet Tamale Pie 0072) and sweet Marsala (Chicken '
        'Marsala 0414) stay below the gate', () async {
      for (final query in [
        '80 percent lean ground chuck',
        '90 percent lean ground sirloin',
        'sweet marsala',
      ]) {
        final ranked = await rank(query);
        expect(
          ranked.first.confidence,
          lessThan(lowConfidence),
          reason: '$query: ${ranked.first.candidate.description}',
        );
      }
    });

    test('a counted sibling that takes the decided food is applied: a '
        'person re-picks "Sugars, brown" for every sugar line', () async {
      final db = tempDb();
      // Chicken Teriyaki (0524) and Chinese Barbecued Pork (0538): plain
      // sugar lines, counted on the engine's pick.
      final a = recipeOf(db, 'ra', ['½ cup sugar']);
      final b = recipeOf(db, 'rb', ['½ cup sugar']);
      for (final r in [a, b]) {
        await matchAndCompute(db, provider, r);
      }
      final before = db.ingredientMatchesFor('rb').single;
      expect(bucketOf(before), MatchBucket.counted);
      expect(before.fdcId, isNot(168833));
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 168833,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (1, 1));
      final after = db.ingredientMatchesFor('rb').single;
      expect((after.fdcId, bucketOf(after)), (168833, MatchBucket.counted));
    });

    test(
      'a search hit for counted hens fetches the bird portion though '
      'the line buys no refuse (Grill-Roasted Cornish Game Hens, 0641)',
      () async {
        final hen = await food(171507);
        final fixtures = FixtureProvider();
        final (_, grams) = await gramsFor(
          tempDb(),
          fixtures,
          FdcFood(
            fdcId: hen.fdcId,
            description: hen.description,
            dataType: hen.dataType,
            nutrientsPer100g: hen.nutrientsPer100g,
            portions: const [],
          ),
          lineOf('4 (1¼- to 1½-pound) whole Cornish game hens'),
        );
        expect(fixtures.foodCalls, 1);
        expect(grams!.grams, 4 * 336);
      },
    );

    test('a sweet pepper is no chile: whole dried red chiles (Orange-Flavored '
        'Chicken, 0525) stay in check below the gate', () async {
      final db = tempDb();
      final r = recipeOf(db, 'r1', [
        '8 small whole dried red chiles (optional)',
      ]);
      await matchAndCompute(db, provider, r);
      final row = db.ingredientMatchesFor('r1').single;
      expect(row.confidence, lessThan(lowConfidence));
      expect(bucketOf(row), MatchBucket.check);
      final sweet =
          rankCandidates(
            'whole dried red chile',
            await provider.search('whole dried red chiles'),
          ).firstWhere(
            (c) => c.candidate.description.contains('sweet'),
          );
      expect(sweet.confidence, lessThan(lowConfidence));
    });

    test('a pinned sentence rule needs a dissolve and a brine salt beside '
        'it (negative paths, synthesized: no library recipe has either)', () {
      final db = tempDb();
      DiscardedMedium? curing(List<String> raws, String step) {
        final r = recipeOf(
          db,
          'r${raws.length}${step.length}',
          raws,
          steps: [
            step,
          ],
        );
        final line = nutritionLines(r).last;
        return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
      }

      // 0091's lines, the curing salt named beside the brine salt without
      // dissolving.
      expect(
        curing(
          ['¾ cup salt', '2 teaspoons pink curing salt #1'],
          'Rub brisket with salt and curing salt. Add brisket to brine.',
        ),
        isNull,
      );
      // Dissolved beside a salt that is no brine.
      expect(
        curing(
          ['2 teaspoons salt', '2 teaspoons pink curing salt #1'],
          'Dissolve salt and curing salt in 4 quarts water. Add brisket to '
          'brine.',
        ),
        isNull,
      );
    });

    test('a query of credited qualifiers alone covers nothing, never 0 / 0 '
        '(negative path, synthesized: no library key is one)', () async {
      final pepper = await food(170931);
      final ranked = rankCandidates('ground', [
        FdcCandidate(
          fdcId: pepper.fdcId,
          description: pepper.description,
          dataType: pepper.dataType,
        ),
      ]);
      // 0 / 0 would clamp to a confidence of 1.
      expect(ranked.single.confidence, lessThan(lowConfidence));
    });

    test('a powder reads the dry portion before the median (Authentic '
        'Baguettes at Home, 0793: "cup dry mix" 98 g)', () async {
      expect(
        gramsOf(
          '1 teaspoon diastatic malt powder (optional)',
          await food(171874),
        )!.grams,
        closeTo(98 / 48, 0.001),
      );
    });
  });
}
