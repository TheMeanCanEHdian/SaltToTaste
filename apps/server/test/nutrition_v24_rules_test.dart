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

DiscardedMedium? _mediumOf(Recipe r, String raw) {
  final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
  return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
}

/// [r] with the line [raw] retyped [to] (parsed as the editor does) and
/// every step's text passed through [steps].
Recipe _edited(
  Recipe r, {
  String? raw,
  String? to,
  String Function(String)? steps,
}) => r.copyWith(
  ingredients: [
    for (final group in r.ingredients)
      group.copyWith(
        items: [
          for (final line in group.items)
            if (line.raw != raw)
              line
            else if (to != null)
              IngredientLine(
                raw: to,
                item: parseIngredientLine(to).item,
                amounts: parseIngredientLine(to).amounts,
              ),
        ],
      ),
  ],
  steps: [
    for (final step in r.steps)
      step.copyWith(text: steps == null ? step.text : steps(step.text)),
  ],
);

/// Matcher v24's rules (Run 054): the oil rule reads the directions with or
/// without a dredge, `_fries` on frying verbs only, one "for (deep) frying"
/// signal (H3). Real corpus recipes on recorded FDC answers
/// (FixtureProvider), never live; edits of real recipes are stated
/// exceptions in their test names.
void main() {
  group('H3 (Run 054 O1/S1, O2/S2, Sonnet critic 3): the frying signal on '
      'both sides', () {
    late FdcFood oil;
    setUpAll(() async => oil = (await FixtureProvider().food(2710180))!);
    ({double? grams, String? source}) outcome(Recipe r, String raw) {
      final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
      final out = engineOutcome(
        r,
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
      return (grams: out.grams, source: out.source);
    }

    double gramsOf(String raw) {
      final line = parseIngredientLine(raw);
      return resolveGrams(
        amounts: line.amounts,
        food: oil,
        normalizedItem: normalizeItem(line.item ?? ''),
        raw: raw,
      )!.grams;
    }

    test('no dredge: 0491 Tostadas heats its ¾ cup vegetable oil "to 350 '
        'degrees" — frying oil, 0 g (its 2 tablespoons olive oil, a sauté, '
        'counted); 1193 Crispy Tempeh heats its cup "to 375 degrees" and '
        '"pour[s] off all but 2 tablespoons oil" — only the kept 2 '
        "tablespoons counted, never 0 g (O1's verifier)", () {
      final tostadas = loadCorpusRecipe(
        '0491-spicy-mexican-shredded-pork-tostadas.yaml',
      );
      expect(
        _mediumOf(tostadas, '¾ cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      expect(outcome(tostadas, '¾ cup vegetable oil'), (
        grams: 0,
        source: 'discarded',
      ));
      expect(_mediumOf(tostadas, '2 tablespoons olive oil'), isNull);
      final tempeh = loadCorpusRecipe(
        '1193-crispy-tempeh-with-sambal-sauce.yaml',
      );
      expect(
        _mediumOf(tempeh, '1 cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      final kept = outcome(tempeh, '1 cup vegetable oil');
      expect(kept.source, 'discarded');
      expect(kept.grams, gramsOf('2 tablespoons vegetable oil'));
      // 2 × the record's 14 g tablespoon (the v23 row: 224 g a cup).
      expect(kept.grams, 28);
    }, skip: skipIfNoCorpus);

    test("O1's exhaustive list of the counted ≥ ¼-cup oils of a frying "
        'recipe stays counted: 0040 (1 tablespoon fries the prosciutto, the '
        'rest dresses), 0500 (the rice toasted, then simmered), 0672 (the '
        "sauce's coconut oil), 0674 and 0675 (shallow-fried fritters, no "
        'temperature or discard sentence — ambiguous, left for the user)', () {
      for (final (file, raw) in const [
        (
          '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
          '4 tablespoons extra-virgin olive oil',
        ),
        ('0500-mexican-rice.yaml', '⅓ cup vegetable oil'),
        ('0672-buffalo-cauliflower-bites.yaml', '¼ cup coconut oil'),
        ('0674-corn-fritters.yaml', '¼ cup vegetable oil, plus more as needed'),
        (
          '0675-southern-corn-fritters.yaml',
          '1 teaspoon plus ½ cup vegetable oil',
        ),
      ]) {
        expect(_mediumOf(loadCorpusRecipe(file), raw), isNull, reason: file);
      }
    }, skip: skipIfNoCorpus);

    test('each own-sentence signal alone, on real recipes edited (synthesized, '
        'a stated exception: every library oil a sentence discards is frying '
        'oil by its dredge or its "for frying" too) — 0198 without its '
        'cornstarch (no dredge) still "Discard[s] the oil": ⅔ cup frying oil; '
        '1193 with no temperature still pours off all but 2 tablespoons', () {
      final chops = _edited(
        loadCorpusRecipe('0198-crispy-pan-fried-pork-chops.yaml'),
        raw: '⅔ cup cornstarch',
      );
      expect(
        _mediumOf(chops, '⅔ cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      final tempeh = _edited(
        loadCorpusRecipe('1193-crispy-tempeh-with-sambal-sauce.yaml'),
        steps: (t) => t.replaceAll(
          RegExp(r'\b3\d\d (?:and 3\d\d )?degrees'),
          'a high heat',
        ),
      );
      expect(
        _mediumOf(tempeh, '1 cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      expect(
        outcome(tempeh, '1 cup vegetable oil').grams,
        gramsOf('2 tablespoons vegetable oil'),
      );
    }, skip: skipIfNoCorpus);

    test(
      '_fries reads frying VERBS only: every library recipe O2 lists that says '
      '"fry" and fries nothing in oil reads false — among them 0540 Pork Lo '
      'Mein ("the cooked stir-fry mixture"), 0705 Thick-Cut Oven Fries '
      '("bottom of each fry"), 1131 Cacio e Uova ("garlic should not '
      'actively fry") — while 0148 ("fry until deep golden brown") and '
      '0288 ("pan-fry") and 0248 ("Continue to fry") fry',
      () {
        for (final file in const [
          '0024-hearty-lentil-soup.yaml',
          '0034-new-england-clam-chowder.yaml',
          '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
          '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
          '0205-smothered-pork-chops.yaml',
          '0451-coq-au-vin.yaml',
          '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
          '0495-chili-con-carne.yaml',
          '0500-mexican-rice.yaml',
          '0506-chinese-pork-dumplings.yaml',
          '0540-pork-lo-mein.yaml',
          '0542-mu-shu-pork.yaml',
          '0705-thick-cut-oven-fries.yaml',
          '1131-pasta-cacio-e-uova-pasta-with-cheese-and-eggs.yaml',
        ]) {
          expect(friesForTest(loadCorpusRecipe(file)), isFalse, reason: file);
        }
        for (final file in const [
          '0148-crispy-fried-chicken.yaml',
          '0288-maryland-crab-cakes.yaml',
          // Run 055 D2: an infinitive inside its sentence fries — "Continue
          // to fry, tilting skillet" (0 rows move: its oil line has no
          // amount); only a note OPENING its sentence ("To pan-fry, …",
          // 0506 above) does not.
          '0248-crispy-slow-roasted-pork-belly.yaml',
        ]) {
          expect(friesForTest(loadCorpusRecipe(file)), isTrue, reason: file);
        }
        // A hyphened frying verb fries; another word's hyphen and a
        // thermometer's name do not. No corpus step uses "deep-fry" as a
        // verb: the sentences are synthesized (a stated exception), on 0024's
        // real recipe, which fries nothing.
        final soup = loadCorpusRecipe('0024-hearty-lentil-soup.yaml');
        bool friesWith(String sentence) => friesForTest(
          soup.copyWith(
            steps: [
              for (final (i, s) in soup.steps.indexed)
                i == 0 ? s.copyWith(text: '${s.text} $sentence') : s,
            ],
          ),
        );
        expect(friesWith('Deep-fry the croutons.'), isTrue);
        expect(friesWith('Shallow-fry the croutons.'), isTrue);
        expect(friesWith('Oven-fry the croutons.'), isFalse);
        expect(friesWith('Clip a candy/deep-fry thermometer to pot.'), isFalse);
      },
      skip: skipIfNoCorpus,
    );

    test("S13: the oil line's \"for frying\" alone makes it frying oil — "
        '1123 Pastelón\'s "¾ cup vegetable oil for frying" (no dredge, no '
        'temperature, its "Discard excess oil" no discard of the oil); and '
        'only a SAME-food plus part counts toward the quarter cup — 0149 '
        'with its oil retyped "2 tablespoons vegetable oil plus ¼ cup bacon '
        'fat" (synthesized, a stated exception: no library oil line has '
        "another food's plus part) is 2 tablespoons, under it: counted", () {
      expect(
        _mediumOf(
          loadCorpusRecipe(
            '1123-pastelon-puerto-rican-sweet-plantain-and-picadillo-'
            'casserole.yaml',
          ),
          '¾ cup vegetable oil for frying',
        ),
        DiscardedMedium.fryingOil,
      );
      const other = '2 tablespoons vegetable oil plus ¼ cup bacon fat';
      final fried = _edited(
        loadCorpusRecipe('0149-easier-fried-chicken.yaml'),
        raw: '1¾ cups vegetable oil',
        to: other,
      );
      expect(plusPartOf(other)?.sameFood, isFalse);
      expect(
        headNounOf(
          normalizeItem(
            lineItemOf(
              nutritionLines(fried).firstWhere((l) => l.raw == other),
            ),
          ),
        ),
        'oil',
      );
      expect(_mediumOf(fried, other), isNull);
    }, skip: skipIfNoCorpus);

    test('the dredge reads "for deep frying" on the oil line again (0116 '
        'Schnitzel edited: its oil retyped "2 cups vegetable oil for deep '
        'frying" and its "to 350 degrees" removed — synthesized, a stated '
        'exception: no library line says "deep frying"): flour and crumbs '
        'held, the oil frying oil', () {
      final schnitzel = _edited(
        loadCorpusRecipe('0116-chicken-schnitzel.yaml'),
        raw: '2 cups vegetable oil for frying',
        to: '2 cups vegetable oil for deep frying',
        steps: (t) => t.replaceAll(' to 350 degrees', ''),
      );
      expect(friesForTest(schnitzel), isTrue);
      expect(
        _mediumOf(schnitzel, '½ cup all-purpose flour'),
        DiscardedMedium.coating,
      );
      expect(
        _mediumOf(schnitzel, '2 cups plain dried bread crumbs'),
        DiscardedMedium.coating,
      );
      expect(
        _mediumOf(schnitzel, '2 cups vegetable oil for deep frying'),
        DiscardedMedium.fryingOil,
      );
    }, skip: skipIfNoCorpus);
  });

  test('H6 (Run 054 O8): _asPrepared reads the MEASURED head, never a '
      "paren's source — lines no corpus recipe types (stated exceptions: "
      "the library's one popcorn line, 0274's \"1 cup lightly salted "
      'popcorn", is pinned in v23) on the real record 2708216 Popcorn, NFS: '
      'popped corn "from" kernels, and kettle or caramel corn, read the '
      'popped cup (14 g); a kernels line that says what it pops into keeps '
      'the yields cup (193 g: the popped mass the kernels make)', () async {
    final popcorn = (await FixtureProvider().food(2708216))!;
    double? grams(String raw) {
      final line = parseIngredientLine(raw);
      return resolveGrams(
        amounts: line.amounts,
        food: popcorn,
        normalizedItem: normalizeItem(line.item ?? ''),
        raw: raw,
      )?.grams;
    }

    expect(grams('8 cups popped popcorn (from ⅓ cup kernels)'), 112.0);
    expect(grams('10 cups popcorn (from ½ cup kernels)'), 140.0);
    expect(grams('8 cups popped popcorn from ⅓ cup kernels'), 112.0);
    expect(grams('8 cups popped popcorn (⅓ cup kernels)'), 112.0);
    expect(grams('4 cups kettle corn'), 56.0);
    expect(grams('4 cups caramel corn'), 56.0);
    expect(grams('½ cup popcorn kernels (about 8 cups popped)'), 96.5);
  });

  group('H7 grams (Run 054 O9/S7, O10/S6, Sonnet critic 2, O16)', () {
    late FdcFood parmesan;
    setUpAll(
      () async => parmesan = (await FixtureProvider().food(325036))!,
    );
    GramResolution? on(FdcFood? food, String raw) {
      final line = parseIngredientLine(raw);
      return resolveGrams(
        amounts: line.amounts,
        food: food,
        normalizedItem: normalizeItem(line.item ?? ''),
        raw: raw,
      );
    }

    test("a plus part of ANOTHER food restates that food only: 0403's rind "
        '(a count 325036 Cheese, parmesan, grated cannot weigh) takes the '
        "part's printed 3 ounces, 85.05 g; a primary that resolves weighs "
        'the line — "¼ cup grated Parmesan cheese plus 1 ounce Pecorino, '
        'grated (½ cup)" (synthesized, a stated exception: no library line '
        "pairs a measured primary with another food's weight) is the "
        "quarter cup's 14.18 g, never the Pecorino's 28.35", () {
      expect(
        on(
          parmesan,
          '1 Parmesan cheese rind, plus 3 ounces Parmesan, shredded (1 cup)',
        )?.grams,
        closeTo(85.05, 0.005),
      );
      expect(
        on(
          parmesan,
          '¼ cup grated Parmesan cheese plus 1 ounce Pecorino, grated (½ cup)',
        )?.grams,
        closeTo(14.18, 0.005),
      );
    });

    test('the printed grated / shredded figure reaches a volume PLUS part '
        "and a part weighed alone on its line's words, and wins over a "
        "record's own cup "
        '(API.md "whatever the record" made true) — lines and records no '
        'corpus recipe or cache carries (synthesized, stated: the corpus '
        'prints no volume plus part of a grated cheese, and 325036 has no '
        'cup): "1 ounce Parmesan cheese, grated (½ cup), plus 2 tablespoons" '
        'is 28.35 + 7.09 g; 325036 given an FNDDS-style "1 cup" 100 g '
        'portion weighs "¼ cup grated Parmesan cheese" 14.18 g and "¼ cup '
        'shredded Parmesan cheese" 21.26 g, never 25', () {
      expect(
        on(
          parmesan,
          '1 ounce Parmesan cheese, grated (½ cup), plus 2 tablespoons',
        )?.grams,
        closeTo(28.35 + 2 * 14.787 * 28.35 / 118.29, 0.01),
      );
      final cupped = FdcFood(
        fdcId: parmesan.fdcId,
        description: parmesan.description,
        dataType: 'Survey (FNDDS)',
        nutrientsPer100g: parmesan.nutrientsPer100g,
        portions: const [
          FdcPortion(gramWeight: 100, amount: 1, description: '1 cup'),
        ],
      );
      expect(
        on(cupped, '¼ cup grated Parmesan cheese')?.grams,
        closeTo(14.18, 0.005),
      );
      expect(
        on(cupped, '¼ cup shredded Parmesan cheese')?.grams,
        closeTo(21.26, 0.005),
      );
    });

    test("O16: a bare Pecorino line's basis names the figure it weighs on — "
        '"¼ cup Pecorino Romano cheese" (typed: no corpus line) is 24.84 g '
        'on Parmesan\'s 0.42, labelled "approximate (Parmesan density)", '
        'never "grated Parmesan"', () {
      final bare = on(null, '¼ cup Pecorino Romano cheese')!;
      expect(bare.grams, closeTo(24.84, 0.01));
      expect(bare.basis, endsWith(' · approximate (Parmesan density)'));
    });
  });

  test(
    "O7: a divided line's eaten part is a mention no other line of its "
    "ingredient writes — 1133 Francese's \"¾ cup all-purpose flour, "
    'divided" split by an edit into "¾ cup all-purpose flour" and "1 '
    'teaspoon all-purpose flour" (synthesized, a stated exception: the '
    'natural edit O7 names) leaves "Sprinkle cubes with 1 teaspoon flour" '
    'to the new line: the dredge is held with no eaten part and no note, '
    'never the teaspoon twice; unedited, the divided line keeps its note',
    () async {
      final francese = loadCorpusRecipe('1133-chicken-francese.yaml');
      IngredientLine typed(String raw) {
        final p = parseIngredientLine(raw);
        return IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
      }

      final split = francese.copyWith(
        ingredients: [
          for (final group in francese.ingredients)
            group.copyWith(
              items: [
                for (final line in group.items)
                  if (line.raw == '¾ cup all-purpose flour, divided') ...[
                    typed('¾ cup all-purpose flour'),
                    typed('1 teaspoon all-purpose flour'),
                  ] else
                    line,
              ],
            ),
        ],
      );
      final flour = (await FixtureProvider().food(789890))!;
      ({double? grams, String? hold, String? note}) of(Recipe r, String raw) {
        final line = nutritionLines(r).firstWhere((l) => l.raw == raw);
        final out = engineOutcome(
          r,
          line,
          flour,
          resolveGrams(
            amounts: line.amounts,
            food: flour,
            normalizedItem: normalizeItem(lineItemOf(line)),
            raw: line.raw,
          ),
          picked: true,
        );
        return (
          grams: out.grams,
          hold: out.hold,
          note: holdNoteOf(r, line, out.hold),
        );
      }

      expect(of(split, '¾ cup all-purpose flour'), (
        grams: null,
        hold: 'coating',
        note: null,
      ));
      expect(of(split, '1 teaspoon all-purpose flour').hold, isNull);
      final whole = of(francese, '¾ cup all-purpose flour, divided');
      expect(whole.hold, 'coating');
      expect(whole.grams, greaterThan(0));
      expect(whole.note, '1 teaspoon flour is used outside the dredge, eaten');
    },
    skip: skipIfNoCorpus,
  );

  test('O13: the first-part reading needs a step that names the first part '
      '— 0149 Easier Fried Chicken with its oil retyped "1 tablespoon plus 1¾ '
      'cups vegetable oil" (synthesized, a stated exception: no library '
      'line has a smaller first part no step names) is all frying oil, 0 g, '
      'never its tablespoon eaten', () async {
    final oil = (await FixtureProvider().food(2710180))!;
    const both = '1 tablespoon plus 1¾ cups vegetable oil';
    final r = _edited(
      loadCorpusRecipe('0149-easier-fried-chicken.yaml'),
      raw: '1¾ cups vegetable oil',
      to: both,
    );
    final line = nutritionLines(r).firstWhere((l) => l.raw == both);
    final out = engineOutcome(
      r,
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

  test("S13: the reach reads a row's hold on ITS line only — 0129 "
      'Mahogany Chicken Thighs computed (its sauce cornstarch unheld), '
      'then its stored line '
      'retyped "… for dredging" with no compute (synthesized, a stated '
      "exception): the stale row's text is not the line's, so the line's "
      "dredge hold is not that row's and the row stays reached", () async {
    final db = wp.tempDb();
    final provider = FixtureProvider(pending: pendingSearches);
    final mahogany = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
    wp.saveRecipe(db, mahogany);
    await matchAndCompute(db, provider, mahogany);
    const raw = '1 tablespoon cornstarch';
    final row = db
        .ingredientMatchesFor(mahogany.id)
        .firstWhere((r) => r.raw == raw);
    expect(row.hold, isNull);
    final key = row.itemKey!;
    List<IngredientMatchRow> reach() => decisionReach(
      db,
      key,
      excluding: (recipeId: 'elsewhere', position: 0),
    ).where((r) => r.recipeId == mahogany.id).toList();
    expect(reach().map((r) => r.position), [row.position]);
    wp.saveRecipe(
      db,
      _edited(mahogany, raw: raw, to: '$raw for dredging'),
    );
    expect(reach().map((r) => r.position), [row.position]);
  }, skip: skipIfNoCorpus);

  group('H5(a) (Run 054 Opus critic 2): ONE pick rule on an eaten-in-part '
      'hold', () {
    MatchBucket bucketOf(IngredientMatchRow m) => matchBucketFor(
      status: m.status,
      fdcId: m.fdcId,
      grams: m.grams,
      confidence: m.confidence,
      hold: m.hold,
      gramSource: m.gramSource,
    );

    Future<(SaltDatabase, FixtureProvider, Recipe, IngredientMatchRow)> picked(
      String file,
      int position,
    ) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe(file);
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final held = db.ingredientMatchesFor(r.id)[position];
      expect(held.hold, isNotNull, reason: file);
      await applyMatchOverride(db, provider, r, position, {
        'raw': held.raw,
        'fdc_id': held.fdcId,
      });
      return (db, provider, r, held);
    }

    test('a pick on a DIVIDED held line counts its eaten part and resolves '
        'the hold — 1133 Francese #5 (the teaspoon tossed with the butter), '
        '0279 Salt-and-Pepper Shrimp #8 (the 3 tablespoons tossed on the '
        'shrimp), 0129 Indoor Pulled Chicken #3 (the remaining teaspoon of '
        'liquid smoke): overridden, the eaten grams (discarded source), no '
        'hold, counted, the GET saying "eaten part counted after your pick"; '
        'a compute after it leaves the row as the pick wrote it', () async {
      for (final (file, i, part) in const [
        ('1133-chicken-francese.yaml', 5, '1 teaspoon all-purpose flour'),
        (
          '0279-crispy-salt-and-pepper-shrimp.yaml',
          8,
          '3 tablespoons cornstarch',
        ),
        ('0129-indoor-pulled-chicken.yaml', 3, '1 teaspoon liquid smoke'),
      ]) {
        final (db, provider, r, held) = await picked(file, i);
        final row = db.ingredientMatchesFor(r.id)[i];
        final food = (await provider.food(held.fdcId!))!;
        final eaten = resolveGrams(
          amounts: parseIngredientLine(part).amounts,
          food: food,
          normalizedItem: normalizeItem(lineItemOf(nutritionLines(r)[i])),
        )!.grams;
        expect(
          (row.status, row.grams, row.gramSource, row.hold),
          ('overridden', eaten, 'discarded', null),
          reason: file,
        );
        final items = ((await matchesBody(db, provider, r))['items']! as List)
            .cast<Map<String, Object?>>();
        final match = items[i]['match']! as Map<String, Object?>;
        expect(
          (match['hold'], match['hold_note']),
          (null, 'eaten part counted after your pick'),
          reason: file,
        );
        expect(bucketOf(row), MatchBucket.counted, reason: file);
        await matchAndCompute(db, provider, r);
        final again = db.ingredientMatchesFor(r.id)[i];
        expect(
          (again.grams, again.hold, again.updatedAt),
          (row.grams, null, row.updatedAt),
          reason: file,
        );
      }
    }, skip: skipIfNoCorpus);

    test('a pick on a NON-divided held line keeps the hold with no grams — '
        "0148 Crispy Fried Chicken #8's 4 cups of dredge flour: overridden, "
        "null grams, hold coating, the GET's note none, in review", () async {
      final (db, provider, r, held) = await picked(
        '0148-crispy-fried-chicken.yaml',
        8,
      );
      final row = db.ingredientMatchesFor(r.id)[8];
      expect(
        (row.fdcId, row.status, row.grams, row.hold),
        (held.fdcId, 'overridden', null, 'coating'),
      );
      expect(bucketOf(row), MatchBucket.noAmount);
      final items = ((await matchesBody(db, provider, r))['items']! as List)
          .cast<Map<String, Object?>>();
      expect((items[8]['match']! as Map)['hold_note'], isNull);
    }, skip: skipIfNoCorpus);
  });
}
