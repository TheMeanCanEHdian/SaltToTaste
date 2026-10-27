// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v82 — the fixes of dual-fleet review Run 067/068 (pair B, the
// catch-up review of v55–v62 at 6ede11c): F1–F11 (union_B.md). Every row
// value is the fresh compute of the WHOLE recipe over recorded real FDC
// answers (FixtureProvider) and equals the v82 replay of snapshot 29 on
// every pinned field. Never the network. Every corpus line is real.
// STATED constructions (no corpus line reaches these paths):
// F1 0088's strain sentence written "… over the vegetables." (the strain
// itself names the solids: guarded); F2 0279's S5 reserve sentence written
// to heat the reserved oil itself and S6's heat sentence written without it;
// F3 0255's S1 toss sentence written to drain and rinse itself and the
// step's later drain and rinse sentences dropped; F3's memo key: 0255 with
// "1 quart plus 2 tablespoons peanut oil or canola oil" and a step brushing
// the fish with 2 tablespoons of the oil (the amount), and its oil line and
// S1 toss written "2 ounces" beside "2 pounds plus 2 ounces lard" and a step
// tossing the fish in 2 ounces of the lard (the head); F4 0304 with one dip
// sentence appended to S2 (the fleet's), with "stirring the mixture often"
// written into its first dip sentence, and "Set the steaks beside the egg
// mixture." before it; F5 0255 with "2 large eggs" and a dredge-head or
// milk line added and a whisk-and-dip pair opening S1 (the fleet's), and
// the starch line written before the flour and picked; F6 0279 with its
// frying steps written as a skillet cook (no coat shape: the H branch);
// closer 1 (verify1 D1–D5): F6 0407 with "Toss the eggplant slices with
// the flour until well combined." appended to S3's first sentence, that
// copy with S4–S6 dropped (no bake: the H branch), and the no-bake copy
// with 0003's "1 medium onion, minced" and 0028's "1 teaspoon paprika"
// stirred into the flour, the paprika named in the shake-to-coat sentence;
// F1's same-step clause 0088's S3 opened with "Add the vegetables."; F2's
// 0279's S6 heat sentence moved to the end of S5; F11's same-ingredient
// gate the chicken line written "4 pounds bone-in pork chops, trimmed";
// F10's memo item: 0239's pork roast text under the item 'boneless strip
// steak';
// closer 2 (verify2 D1–D5): F3 0255's S1 opened with "Drain the potatoes."
// or "Rinse the potatoes." (before the toss); F4 0304 with two dip
// sentences appended to S2, the middle one "stirring the mixture often";
// F10 the carried memo's key: 0239's pork roast line written "…, trimmed of
// all fat" and its text under 'boneless strip steak', and 0091's 'beef
// brisket' answer stored again without 173128 (a copy under another query
// holding it); the DECIDED cap shape voids the memos by storing a cached
// answer again, unchanged (the picks are real lines and records);
// closer 3 (verify3 D1–D3): F1 0088's S3 opened AND closed by "Add the
// vegetables."; F2 0279's S6 heat sentence at BOTH ends of S5; F10 0249's
// real line read with a decision on a cured record of its own answer (no
// corpus key carries one there; D2's picks are real lines and records);
// F10 a 'whole beef brisket' and a 'rack of lamb' line written without the
// trim (no corpus line of either key prints none), 0239's pork roast line
// written "…, trimmed of all fat" and its cached answer rewritten without
// its lean-only record (R2's memo); F11 crispy-fried-chicken's chicken line
// edited "4 pounds" → "10 pounds" and not yet computed (an admin's save);
// closer 4 (verify4 D1, D2): F3 0255's S1 sentence "Rinse well under cold
// running water." — and, separately, its drain sentence — moved before the
// toss, the other still after it; F7's picks (D1) are real lines and records
// through the real PUT (a person's 77 g typed on one);
// closer 5 (verify5 D1): 0279's shrimp |0 stored confirmed at base's F6
// outcome (0.00 g `discarded`, written directly — no tree path writes it);
// the order-C Confirms (0254, 0149) are real lines and records through the
// real PUT;
// the cost shapes (a real corpus line repeated, filler steps — the house's
// cap-shape exception).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v26_cost_test.dart' show capStep, capSteps, capped;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

IngredientLine _ln(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v82-');
  final db = SaltDatabase.open(
    ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath,
  )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

FixtureProvider _fdc() => FixtureProvider(pending: {...pendingSearches});

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(SaltDatabase db, FixtureProvider fdc, Recipe r) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

double _energy(SaltDatabase db, String id) =>
    ((jsonDecode(db.nutritionFor(id)!.totalsJson!) as Map)['energy'] as num)
        .toDouble();

String _sig(IngredientMatchRow r) =>
    '${r.status}|${r.fdcId}|${r.grams?.toStringAsFixed(2)}|${r.gramSource}|${r.hold}';

/// Every row of [id] and its energy (4 decimals): what PUT == recompute ==
/// compute compares.
String _state(SaltDatabase db, String id) => [
  for (final r in db.ingredientMatchesFor(id)) '${r.position} ${_sig(r)}',
  _energy(db, id).toStringAsFixed(4),
].join('\n');

/// A PUT on [position] of the STORED [id] with [body] (its line's raw added).
Future<void> _put(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
  int position,
  Map<String, Object?> body,
) async {
  final recipe = nutritionRecipeOf(db, id)!.recipe;
  await applyMatchOverride(db, fdc, recipe, position, {
    'raw': nutritionLines(recipe)[position].raw,
    ...body,
  });
}

/// After a person's writes: the stored state equals a plain recompute's
/// and a full compute's (G3 / G5 RULE A) — returned for the pins.
Future<String> _settled(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
) async {
  final put = _state(db, id);
  recomputeTotals(db, nutritionRecipeOf(db, id)!.recipe);
  expect(_state(db, id), put, reason: 'PUT == recompute ($id)');
  expect(
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
    isNull,
  );
  expect(_state(db, id), put, reason: 'PUT == compute ($id)');
  return put;
}

const _oil = FdcFood(
  fdcId: 172336,
  description: 'Oil, vegetable',
  dataType: 'sr_legacy_food',
  nutrientsPer100g: {},
  portions: [],
);

void main() {
  group('v82 (review Run 067/068 fixes)', skip: skipIfNoCorpus, () {
    guards();
    plans();
    persons();
    carries();
  });
  group('v82 cost (RULE C at the caps)', skip: skipIfNoCorpus, costShapes);
}

/// F1 (the strain-the-liquid guard), F2 (the reserved frying oil), F3 (the
/// rinsed plus part): each guard reads its LAST sentence once and answers by
/// position — as the tail scans read: a later sentence only, never the
/// guarded sentence itself (F2, F3) and the strain sentence itself included
/// (F1). The base forms equal the tree on 102,493 corpus line readings (the
/// recipes and six seeded variants each, the guards' own words spliced in —
/// the fixer's differential, fix82/repro).
void guards() {
  const ribs = '0088-slow-cooker-beer-braised-short-ribs.yaml';
  const strain = 'strain the liquid through a fine-mesh strainer into a bowl.';

  test('F1: the guard reads the strain sentence itself — 0088 strains its '
      'onions (real), and the same strain written "over the vegetables" '
      '(STATED) names the solids: guarded, nothing strained', () {
    final real = loadCorpusRecipe(ribs);
    final onions = nutritionLines(real)[4];
    expect(onions.raw, startsWith('3 pounds yellow onions'));
    DiscardedMedium? of(Recipe r) =>
        discardedMediumOf(r, onions, normalizeItem(lineItemOf(onions)));
    expect(of(real), DiscardedMedium.strainedSolid);
    final text = real.steps[2].text.replaceFirst(
      strain,
      'strain the liquid through a fine-mesh strainer over the vegetables.',
    );
    expect(text, isNot(real.steps[2].text));
    expect(
      of(
        real.copyWith(
          steps: [...real.steps]..[2] = real.steps[2].copyWith(text: text),
        ),
      ),
      isNull,
    );
  });

  test("F2: a reserve sentence's own heat is no reuse — 0279's real S5 / S6 "
      'keep 2 tablespoons of the frying oil (27.21 g); S5 written to heat the '
      'reserved oil itself and S6 without it (STATED) keeps none', () {
    final real = loadCorpusRecipe('0279-crispy-salt-and-pepper-shrimp.yaml');
    final oil = nutritionLines(real)[7];
    expect(oil.raw, '4 cups vegetable oil');
    expect(
      engineOutcome(real, oil, _oil, null).grams?.toStringAsFixed(2),
      '27.21',
    );
    final s5 = real.steps[4].text.replaceFirst(
      'After frying, reserve 2 tablespoons frying oil.',
      'After frying, reserve 2 tablespoons frying oil and heat reserved oil '
          'in 12-inch skillet.',
    );
    final s6 = real.steps[5].text.replaceFirst(
      'Heat reserved oil in 12-inch skillet over medium-high heat until '
          'shimmering.',
      'Heat the skillet over medium-high heat until shimmering.',
    );
    expect((s5, s6), isNot((real.steps[4].text, real.steps[5].text)));
    final edited = real.copyWith(
      steps: [...real.steps]
        ..[4] = real.steps[4].copyWith(text: s5)
        ..[5] = real.steps[5].copyWith(text: s6),
    );
    expect(
      engineOutcome(edited, nutritionLines(edited)[7], _oil, null).grams,
      0,
    );
  });

  // Closer 1 (verify1 D2): each guard's SAME-STEP clause — a sentence in
  // the guarded sentence's own step, before it (F1) or after it (F2).
  test("F1's same-step clause: a solids sentence EARLIER in the strain's own "
      'step comes before the strain — 0088\'s S3 opened with "Add the '
      'vegetables." (STATED) still strains the onions (the clause dropped: '
      'nothing strained)', () {
    final real = loadCorpusRecipe(ribs);
    final onions = nutritionLines(real)[4];
    final edited = real.copyWith(
      steps: [...real.steps]
        ..[2] = real.steps[2].copyWith(
          text: 'Add the vegetables. ${real.steps[2].text}',
        ),
    );
    expect(edited.steps[2].text, contains(strain));
    expect(
      discardedMediumOf(
        edited,
        nutritionLines(edited)[4],
        normalizeItem(lineItemOf(onions)),
      ),
      DiscardedMedium.strainedSolid,
    );
  });

  test(
    "F2's same-step clause: a heat sentence LATER in the reserve's own "
    "step comes after it — 0279's S6 heat sentence moved to the end of S5 "
    '(STATED) keeps the 2 tablespoons (27.21 g; the clause dropped: 0 g)',
    () {
      final real = loadCorpusRecipe('0279-crispy-salt-and-pepper-shrimp.yaml');
      const heat =
          'Heat reserved oil in 12-inch skillet over medium-high heat until '
          'shimmering.';
      final s6 = real.steps[5].text.replaceFirst(
        heat,
        'Heat the skillet over medium-high heat until shimmering.',
      );
      expect(s6, isNot(real.steps[5].text));
      final edited = real.copyWith(
        steps: [...real.steps]
          ..[4] = real.steps[4].copyWith(text: '${real.steps[4].text} $heat')
          ..[5] = real.steps[5].copyWith(text: s6),
      );
      expect(
        engineOutcome(
          edited,
          nutritionLines(edited)[7],
          _oil,
          null,
        ).grams?.toStringAsFixed(2),
        '27.21',
      );
    },
  );

  // Closer 3 (verify3 D1): the LAST match of the guarded step
  // (`_lastMatching` scans each step from its end) — a step holding the
  // guarded sentence between two solids (heat) sentences reads the later
  // one; the step's FIRST match alone strains (reuses nothing).
  test("F1's last match in the strain's own step (closer 3, verify3 D1): "
      '0088\'s S3 opened AND closed by "Add the vegetables." (STATED) — the '
      'closing solids sentence follows the strain: the onions are counted '
      "(the step's first match read: strainedSolid)", () {
    final real = loadCorpusRecipe(ribs);
    final onions = nutritionLines(real)[4];
    final edited = real.copyWith(
      steps: [...real.steps]
        ..[2] = real.steps[2].copyWith(
          text: 'Add the vegetables. ${real.steps[2].text} Add the vegetables.',
        ),
    );
    expect(edited.steps[2].text, contains(strain));
    expect(
      discardedMediumOf(
        edited,
        nutritionLines(edited)[4],
        normalizeItem(lineItemOf(onions)),
      ),
      isNull,
    );
  });

  test(
    "F2's last match in the reserve's own step (closer 3, verify3 D1): "
    "0279's S6 heat sentence moved to BOTH ends of S5 (STATED) — the closing "
    'heat follows the reserve: the 2 tablespoons kept (27.21 g; the '
    "step's first match read: 0 g)",
    () {
      final real = loadCorpusRecipe('0279-crispy-salt-and-pepper-shrimp.yaml');
      const heat =
          'Heat reserved oil in 12-inch skillet over medium-high heat until '
          'shimmering.';
      final s6 = real.steps[5].text.replaceFirst(
        heat,
        'Heat the skillet over medium-high heat until shimmering.',
      );
      expect(s6, isNot(real.steps[5].text));
      final edited = real.copyWith(
        steps: [...real.steps]
          ..[4] = real.steps[4].copyWith(
            text: '$heat ${real.steps[4].text} $heat',
          )
          ..[5] = real.steps[5].copyWith(text: s6),
      );
      expect(
        engineOutcome(
          edited,
          nutritionLines(edited)[7],
          _oil,
          null,
        ).grams?.toStringAsFixed(2),
        '27.21',
      );
    },
  );

  test(
    "F3: a toss sentence's own drain and rinse are no rinse — 0255's real "
    'S1 rinses the ¼ cup off (0 g); the toss written to drain and rinse '
    "itself, the step's later drain and rinse dropped (STATED), keeps it",
    () {
      final real = loadCorpusRecipe('0255-fish-and-chips.yaml');
      final oil = nutritionLines(real)[1];
      expect(oil.raw, '3 quarts plus ¼ cup peanut oil or canola oil');
      expect(engineOutcome(real, oil, _oil, null).grams, 0);
      final s1 = real.steps[0].text
          .replaceFirst(
            'toss with ¼ cup of the oil, and cover',
            'toss with ¼ cup of the oil, drain and rinse, and cover',
          )
          .replaceFirst(
            ' and drain the potatoes into a large mesh strainer set over a '
                'sink. Rinse well under cold running water.',
            '.',
          );
      expect(s1, isNot(real.steps[0].text));
      expect(s1, isNot(contains('Rinse well')));
      final edited = real.copyWith(
        steps: [...real.steps]..[0] = real.steps[0].copyWith(text: s1),
      );
      final kept = engineOutcome(edited, nutritionLines(edited)[1], _oil, null);
      expect(kept.grams, greaterThan(0));
    },
  );

  test("F3's LAST drain and LAST rinse (closer 2, verify2 D3; STATED): "
      '0255 with "Drain the potatoes." — or "Rinse the potatoes." — opening '
      "S1, before the toss: the step's later drain and rinse still come after "
      "it, the ¼ cup rinsed off (0 g; the step's FIRST drain or rinse read: "
      'kept)', () {
    final real = loadCorpusRecipe('0255-fish-and-chips.yaml');
    for (final opening in const [
      'Drain the potatoes. ',
      'Rinse the potatoes. ',
    ]) {
      final edited = real.copyWith(
        steps: [...real.steps]
          ..[0] = real.steps[0].copyWith(
            text: '$opening${real.steps[0].text}',
          ),
      );
      final oil = nutritionLines(edited)[1];
      expect(oil.raw, '3 quarts plus ¼ cup peanut oil or canola oil');
      expect(engineOutcome(edited, oil, _oil, null).grams, 0, reason: opening);
    }
  });

  // closer 4 (verify4 D2): each half of "the step's last drain AND its last
  // rinse after the toss" alone — every pin above moves the drain and the
  // rinse to the same side of the toss.
  for (final (moved, after) in const [
    ('Rinse well under cold running water. ', 'drain'),
    (
      'Carefully pull back the plastic wrap from the side farthest from you '
          'and drain the potatoes into a large mesh strainer set over a sink. ',
      'rinse',
    ),
  ]) {
    test("F3's ${after == 'drain' ? 'rinse' : 'drain'} half alone (closer 4, "
        "verify4 D2; STATED): 0255 with S1's sentence \"${moved.trim()}\" "
        'moved before the toss, its $after still after it — the ¼ cup kept '
        '(54.42 g; a ${after == 'drain' ? 'rinse' : 'drain'} anywhere in the '
        'step read: 0 g)', () {
      final real = loadCorpusRecipe('0255-fish-and-chips.yaml');
      final s1 = real.steps[0].text;
      expect(s1, contains(moved));
      final edited = real.copyWith(
        steps: [...real.steps]
          ..[0] = real.steps[0].copyWith(
            text: '$moved${s1.replaceFirst(moved, '')}',
          ),
      );
      final oil = nutritionLines(edited)[1];
      expect(oil.raw, '3 quarts plus ¼ cup peanut oil or canola oil');
      expect(
        engineOutcome(edited, oil, _oil, null).grams?.toStringAsFixed(2),
        '54.42',
      );
    });
  }

  test("F3's memo key (`memo:rinsedOff`: the plus part's amount and the "
      'head): 0255 with a second plus-part oil, "1 quart plus 2 tablespoons '
      'peanut oil or canola oil", and a step brushing the fish with its 2 '
      'tablespoons (STATED) — the ¼ cup rinsed off (0 g), the 2 tablespoons '
      "kept (27.21 g); and a lard line printing the oil's plus amount (the "
      'head, STATED) — in either order of reading', () {
    final real = loadCorpusRecipe('0255-fish-and-chips.yaml');
    for (final reversed in [false, true]) {
      final r = real.copyWith(
        id: '${real.id}-$reversed',
        ingredients: [
          real.ingredients.first.copyWith(
            items: [
              ...real.ingredients.first.items,
              _ln('1 quart plus 2 tablespoons peanut oil or canola oil'),
            ],
          ),
        ],
        steps: [
          ...real.steps,
          const RecipeStep(
            number: 7,
            text: 'Brush the fish with 2 tablespoons of the oil.',
          ),
        ],
      );
      final lines = nutritionLines(r);
      final read = <int, double?>{
        for (final i
            in reversed ? [lines.length - 1, 1] : [1, lines.length - 1])
          i: engineOutcome(r, lines[i], _oil, null).grams,
      };
      expect(read[1], 0, reason: 'reversed: $reversed');
      expect(
        read[lines.length - 1]?.toStringAsFixed(2),
        '27.21',
        reason: 'reversed: $reversed',
      );
    }
    // The head (STATED): the oil line and S1's toss written "2 ounces", and
    // a lard line whose plus part is the same "2 ounces", the fish tossed in
    // it with no drain or rinse — the oil's rinsed off (0 g), the lard's
    // kept (56.70 g), whichever fat is read first.
    final items = [...real.ingredients.first.items]
      ..[1] = _ln('3 quarts plus 2 ounces peanut oil or canola oil');
    final s1 = real.steps[0].text.replaceFirst(
      'toss with ¼ cup of the oil',
      'toss with 2 ounces of the oil',
    );
    expect(s1, isNot(real.steps[0].text));
    for (final reversed in [false, true]) {
      final r = real.copyWith(
        id: '${real.id}-head-$reversed',
        ingredients: [
          real.ingredients.first.copyWith(
            items: [...items, _ln('2 pounds plus 2 ounces lard')],
          ),
        ],
        steps: [
          real.steps[0].copyWith(text: s1),
          ...real.steps.skip(1),
          const RecipeStep(
            number: 7,
            text:
                'Fry the fish in the lard. Toss the fish with 2 ounces of the '
                'lard.',
          ),
        ],
      );
      final lines = nutritionLines(r);
      final read = <int, double?>{
        for (final i
            in reversed ? [lines.length - 1, 1] : [1, lines.length - 1])
          i: engineOutcome(r, lines[i], _oil, null).grams,
      };
      expect(read[1], 0, reason: 'head, reversed: $reversed');
      expect(
        read[lines.length - 1]?.toStringAsFixed(2),
        '56.70',
        reason: 'head, reversed: $reversed',
      );
    }
  });
}

/// F4 (a dip sentence is never a mixing sentence; the verb a whole word),
/// F5 (a dip is never off C5's B): a compute and a recompute plan alike.
void plans() {
  const steaks = '0304-chicken-fried-steaks.yaml';
  const dip =
      'Shake excess flour from each steak, then, using tongs, dip each steak '
      'into the egg mixture, turning to coat well and allowing the excess to '
      'drip off.';

  /// 0304 with its S2 edited by [edit]: the cube steaks |7's grams and the
  /// recipe's energy after a compute, a recompute writing nothing more.
  Future<(String, String)> steaksWith(String Function(String) edit) async {
    final db = _db();
    final fdc = _fdc();
    final c = loadCorpusRecipe(steaks);
    final text = edit(c.steps[1].text);
    final r = await _compute(
      db,
      fdc,
      c.copyWith(steps: [...c.steps]..[1] = c.steps[1].copyWith(text: text)),
    );
    final computed = _state(db, r.id);
    recomputeTotals(db, r);
    expect(_state(db, r.id), computed, reason: 'recompute == compute');
    return (
      _row(db, r.id, 7).grams!.toStringAsFixed(3),
      _energy(db, r.id).toStringAsFixed(1),
    );
  }

  test('F4: 0304 as printed — the cube steaks 850.485 g, 3,206.9 kcal (the '
      'baseline the edits below must keep)', () async {
    expect(loadCorpusRecipe(steaks).steps[1].text, contains(dip));
    expect(await steaksWith((t) => t), ('850.485', '3206.9'));
  });

  test("F4 (the fleet's, STATED): one more dip sentence appended to S2 — "
      'the first dip sentence ("… into the egg mixture …") is no mixing '
      'sentence: the steaks stay the coated food, 850.485 g (base 64.78 g '
      '`discarded`, 1,698.6 kcal, the recompute holding the coat)', () async {
    expect(
      await steaksWith(
        (t) =>
            '$t Dip each remaining steak into the egg mixture, allowing the '
            'excess to drip off.',
      ),
      ('850.485', '3206.9'),
    );
  });

  test('F4, the dip-sentence gate (STATED): the first dip written "into the '
      'egg mixture, stirring the mixture often," (a mixing word in a dip '
      'sentence) and a second dip appended — still no mix: 850.485 g', () async {
    expect(
      await steaksWith(
        (t) =>
            '${t.replaceFirst('into the egg mixture,', 'into the egg mixture, stirring the mixture often,')} '
            'Dip each remaining steak into the egg mixture, allowing the '
            'excess to drip off.',
      ),
      ('850.485', '3206.9'),
    );
  });

  test('F4, the dip-sentence gate on a LATER dip (closer 2, verify2 D4; '
      'STATED): two more dip sentences appended to S2, the middle one '
      '"… into the egg mixture, stirring the mixture often, …" — no dip '
      'sentence is a mix: 850.485 g (the first dip sentence alone gated: '
      '64.78 g `discarded`, 1,698.6 kcal)', () async {
    expect(
      await steaksWith(
        (t) =>
            '$t Dip each remaining steak into the egg mixture, stirring the '
            'mixture often, allowing the excess to drip off. Dip each '
            'remaining steak into the egg mixture, allowing the excess to '
            'drip off.',
      ),
      ('850.485', '3206.9'),
    );
  });

  test('F4, the whole-word gate (STATED): "Set the steaks beside the egg '
      'mixture." before the dip ("mixture", no mixing verb) — no mix: '
      '850.485 g', () async {
    expect(
      await steaksWith(
        (t) => t.replaceFirst(
          'Pat the steaks dry',
          'Set the steaks beside the egg mixture. Pat the steaks dry',
        ),
      ),
      ('850.485', '3206.9'),
    );
  });

  /// 0255 with "2 large eggs" and [second] added and a whisk-and-dip pair
  /// opening S1 (the fleet's): the state of every row after a compute, a
  /// recompute and a compute again — equal — and the flour |2 and energy.
  Future<(String, String)> fishWith(String second, String word) async {
    final db = _db();
    final fdc = _fdc();
    final c = loadCorpusRecipe('0255-fish-and-chips.yaml');
    final g = c.ingredients.single;
    final r = await _compute(
      db,
      fdc,
      c.copyWith(
        ingredients: [
          g.copyWith(items: [...g.items, _ln('2 large eggs'), _ln(second)]),
        ],
        steps: [...c.steps]
          ..[0] = c.steps[0].copyWith(
            text:
                'Whisk the eggs and $word in a small bowl. Dip each piece of '
                'fish into the egg mixture, allowing the excess to drip off. '
                '${c.steps[0].text}',
          ),
      ),
    );
    final computed = _state(db, r.id);
    recomputeTotals(db, r);
    expect(_state(db, r.id), computed, reason: 'recompute == compute');
    expect(await matchAndCompute(db, fdc, r), isNull);
    expect(_state(db, r.id), computed, reason: 'compute again');
    return (
      _row(db, r.id, 2).grams!.toStringAsFixed(2),
      _energy(db, r.id).toStringAsFixed(2),
    );
  }

  test("F5 (the fleet's, STATED): 0255 with a tapioca-starch egg dip — the "
      "dip line is never off C5's B: compute == recompute == compute, the "
      'flour |2 89.12 g, 3,632.74 kcal (base: the compute 67.71 / 3,451.64, '
      'the recompute 89.12 / 3,632.74)', () async {
    expect(
      await fishWith('¼ cup tapioca starch', 'tapioca starch'),
      ('89.12', '3632.74'),
    );
  });

  test("F5, the key's term (`_m52Key`'s offB never a dip's grams): the "
      'starch dip written before the dredge (|3), the flour |2 and the eggs '
      '|12 confirmed and the starch PICKED on its own record through the real '
      'PUT (STATED as above) — settled (PUT == recompute == compute); the '
      'plans counted exactly: the matches GET 1, a compute 3 (a key reading '
      "the picked dip's grams: 2 and 4)", () async {
    final db = _db();
    final fdc = _fdc();
    final c = loadCorpusRecipe('0255-fish-and-chips.yaml');
    final g = c.ingredients.single;
    final r = await _compute(
      db,
      fdc,
      c.copyWith(
        ingredients: [
          g.copyWith(
            items: [
              ...g.items.take(3),
              // Between the two confirmed rows: the compute rewrites it to
              // its engine form between their derivations.
              _ln('¼ cup tapioca starch'),
              ...g.items.skip(3),
              _ln('2 large eggs'),
            ],
          ),
        ],
        steps: [...c.steps]
          ..[0] = c.steps[0].copyWith(
            text:
                'Whisk the eggs and tapioca starch in a small bowl. Dip each '
                'piece of fish into the egg mixture, allowing the excess to '
                'drip off. ${c.steps[0].text}',
          ),
      ),
    );
    for (final p in [12, 2]) {
      await _put(db, fdc, r.id, p, {'confirmed': true});
    }
    // The starch dip picked on its own record: counted where the confirm's
    // copy is not — a key reading its grams off B misses.
    await _put(db, fdc, r.id, 3, {'fdc_id': _row(db, r.id, 3).fdcId});
    await _settled(db, fdc, r.id);
    m52PlanRuns = 0;
    await matchesBody(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
    final get = m52PlanRuns;
    m52PlanRuns = 0;
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
    expect((get, m52PlanRuns), (1, 3));
    expect(
      [
        for (final p in [2, 3, 12]) _sig(_row(db, r.id, p)),
      ],
      [
        'confirmed|789890|89.12|discarded|null',
        'overridden|169717|28.35|density|null',
        'confirmed|748967|100.00|discarded|null',
      ],
    );
  });

  test('F5, the control (STATED): the same dip of milk, no dredge head — '
      'idempotent at base and tree, 3,550.88 kcal', () async {
    final (_, kcal) = await fishWith('2 tablespoons milk', 'milk');
    expect(kcal, '3550.88');
  });
}

/// F6 (the coated food never a coat part), F7 (a CONFIRM the plan stops
/// covering is re-derived as the compute derives it — the v70 F9 revert
/// extended), F8 (confirmed parts key as dips: one plan), F11 (the stale
/// window reads the edited coated food as the totals count it).
void persons() {
  const shrimp = '0279-crispy-salt-and-pepper-shrimp.yaml';

  test(
    "F6: 0279's shell-on shrimp |0 confirmed, then picked on its own "
    "record, through the real PUT — the engine's weight, counted (base: "
    '0.00 g `discarded` for good, 1,465.37 → 410.40 kcal); settled',
    () async {
      final db = _db();
      final fdc = _fdc();
      final r = await _compute(db, fdc, loadCorpusRecipe(shrimp));
      final before = _row(db, r.id, 0);
      expect(_sig(before), 'auto|175179|680.39|weight|null');
      final energy = _energy(db, r.id).toStringAsFixed(2);
      await _put(db, fdc, r.id, 0, {'confirmed': true});
      expect(_sig(_row(db, r.id, 0)), 'confirmed|175179|680.39|weight|null');
      expect(_energy(db, r.id).toStringAsFixed(2), energy);
      await _settled(db, fdc, r.id);
      // The gate in `derivedFor`: the confirmed shrimp derives with no plan
      // of its own — the GET plans once (routed to the plan: twice).
      m52PlanRuns = 0;
      await matchesBody(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
      expect(m52PlanRuns, 1);
      await _put(db, fdc, r.id, 0, {'fdc_id': 175179});
      expect(_sig(_row(db, r.id, 0)), 'overridden|175179|680.39|weight|null');
      expect(_energy(db, r.id).toStringAsFixed(2), energy);
      await _settled(db, fdc, r.id);
    },
  );

  test("F6, the plan's own gate (STATED): 0279 with its frying steps "
      'written as a skillet cook (no coat shape — the coat held with no '
      "budget, H) — the engine's shrimp is no part of the coat: 680.39 g "
      '(base: held `coating`, no grams)', () async {
    final db = _db();
    final c = loadCorpusRecipe(shrimp);
    final r = await _compute(
      db,
      _fdc(),
      c.copyWith(
        steps: [
          c.steps[0],
          c.steps[1],
          const RecipeStep(
            number: 3,
            text:
                'Drain shrimp and pat dry with paper towels. Transfer shrimp '
                'to bowl, add 3 tablespoons cornstarch and 1 tablespoon '
                'peppercorn mixture, and toss until well combined.',
          ),
          const RecipeStep(
            number: 4,
            text:
                'Shake off excess cornstarch. Cook shrimp in 12-inch skillet '
                'until pink, about 3 minutes.',
          ),
        ],
      ),
    );
    expect(_sig(_row(db, r.id, 0)), 'auto|175179|680.39|weight|null');
    expect(_row(db, r.id, 8).hold, 'coating');
  });

  // Closer 1 (verify1 D1): the coated VEGETABLE ([_coatedVegetable]'s
  // row) is the coated food too — 0407's eggplant named with its flour in
  // a mixing sentence (STATED: one sentence appended to S3's first).
  const eggplant = '0407-eggplant-parmesan.yaml';
  Recipe tossed({bool bakes = true}) {
    final c = loadCorpusRecipe(eggplant);
    const first =
        'Combine the flour and 1 teaspoon pepper in a large zipper-lock bag; '
        'shake to combine.';
    final s3 = c.steps[2].text.replaceFirst(
      first,
      '$first Toss the eggplant slices with the flour until well combined.',
    );
    expect(s3, isNot(c.steps[2].text));
    return c.copyWith(
      id: '${c.id}-tossed',
      slug: '${c.slug}-tossed',
      steps: [
        ...c.steps.take(2),
        c.steps[2].copyWith(text: s3),
        if (bakes) ...c.steps.skip(3),
      ],
    );
  }

  test('F6, the coated vegetable (STATED): 0407 with "Toss the eggplant '
      'slices with the flour until well combined." appended to S3\'s first '
      "sentence — the engine's rows as 0407's own (eggplant |0 907.18 g, "
      '2,735.29 kcal); a Confirm, then a pick of |0 on its own record, keep '
      "the engine's weight, counted (before closer 1: a Confirm stored 0.00 g "
      '`discarded` for good, 1,938.5 kcal; a pick held it `coating`); '
      'settled', () async {
    final db = _db();
    final fdc = _fdc();
    final real = await _compute(db, fdc, loadCorpusRecipe(eggplant));
    final r = await _compute(db, fdc, tossed());
    expect(_state(db, r.id), _state(db, real.id));
    final before = _row(db, r.id, 0);
    expect(_sig(before), 'auto|${before.fdcId}|907.18|weight|null');
    expect(before.description, startsWith('Eggplant,'));
    expect(_energy(db, r.id).toStringAsFixed(2), '2735.29');
    await _put(db, fdc, r.id, 0, {'confirmed': true});
    expect(
      _sig(_row(db, r.id, 0)),
      'confirmed|${before.fdcId}|907.18|weight|null',
    );
    expect(_energy(db, r.id).toStringAsFixed(2), '2735.29');
    await _settled(db, fdc, r.id);
    // The gate in `derivedFor`: the confirmed eggplant derives with no plan
    // of its own — the GET plans once (routed to the plan: twice).
    m52PlanRuns = 0;
    await matchesBody(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
    expect(m52PlanRuns, 1);
    await _put(db, fdc, r.id, 0, {'fdc_id': before.fdcId});
    expect(
      _sig(_row(db, r.id, 0)),
      'overridden|${before.fdcId}|907.18|weight|null',
    );
    expect(_energy(db, r.id).toStringAsFixed(2), '2735.29');
    await _settled(db, fdc, r.id);
  });

  test("F6's plan gate, the coated vegetable (STATED): the same copy with "
      'S4–S6 dropped (no bake after the coat: no shape, the flour held with '
      "no budget, H) — the engine's eggplant is no part of the coat: 907.18 "
      'g counted (before closer 1: held `coating`, no grams)', () async {
    final db = _db();
    final r = await _compute(db, _fdc(), tossed(bakes: false));
    expect(_sig(_row(db, r.id, 0)), endsWith('|907.18|weight|null'));
    expect(_row(db, r.id, 5).hold, 'coating');
  });

  test("F6's coated-vegetable test, its two terms (STATED): the no-bake copy "
      'without the toss, 0003\'s "1 medium onion, minced" and 0028\'s "1 '
      'teaspoon paprika" stirred into the flour (S3: "Combine the flour, 1 '
      'teaspoon pepper, the onion, and the paprika …") and the paprika named '
      'where the eggplant is shaken to coat — neither is the coated food: '
      'the onion is on an Onions record no coating sentence names, the '
      'paprika named there on no vegetable record; both parts, held '
      '`coating` with the flour (the naming term dropped: the onion counted; '
      'the record term dropped: the paprika counted)', () async {
    final db = _db();
    final c = loadCorpusRecipe(eggplant);
    final s3 = c.steps[2].text
        .replaceFirst(
          'Combine the flour and 1 teaspoon pepper in',
          'Combine the flour, 1 teaspoon pepper, the onion, and the paprika in',
        )
        .replaceFirst(
          'in the bag with the flour; seal',
          'in the bag with the flour and paprika; seal',
        );
    expect(s3, contains('the paprika in'));
    expect(s3, contains('flour and paprika; seal'));
    final r = await _compute(
      db,
      _fdc(),
      c.copyWith(
        id: '${c.id}-parts',
        slug: '${c.slug}-parts',
        ingredients: [
          c.ingredients.first.copyWith(
            items: [
              ...c.ingredients.first.items,
              _ln('1 medium onion, minced'),
              _ln('1 teaspoon paprika'),
            ],
          ),
          ...c.ingredients.skip(1),
        ],
        steps: [
          ...c.steps.take(2),
          c.steps[2].copyWith(text: s3),
        ],
      ),
    );
    expect(
      [
        for (final p in [0, 5, 8, 9]) _sig(_row(db, r.id, p)),
      ],
      [
        'auto|2685577|907.18|weight|null',
        'auto|789890|null|null|coating',
        'auto|790646|null|null|coating',
        'auto|171329|null|null|coating',
      ],
    );
  });

  // F7: (recipe, the plan rows confirmed, the food skipped, each confirmed
  // row after the PUT == recompute == compute) — the Opus fleet's six, and
  // (closer 1, verify1 D3) the eaten part of a confirmed held coat: 0315's
  // flour, ¼ cup of it to the dish.
  for (final (file, confirmed, food, rows) in const [
    (
      '0511-shrimp-tempura.yaml',
      [5],
      1,
      ['5 confirmed|748967|50.00|piece|null'],
    ),
    (
      '0511-shrimp-tempura.yaml',
      [2, 4],
      1,
      [
        '2 confirmed|789890|212.62|weight|null',
        '4 confirmed|2710704|224.00|portion|null',
      ],
    ),
    (
      '1194-lumpiang-shanghai-with-seasoned-vinegar.yaml',
      [17],
      12,
      ['17 confirmed|2710180|0.00|discarded|null'],
    ),
    (
      '0288-maryland-crab-cakes.yaml',
      [9],
      0,
      ['9 confirmed|2710180|0.00|discarded|null'],
    ),
    (
      '0415-best-chicken-parmesan.yaml',
      [12],
      8,
      ['12 confirmed|748967|50.00|piece|null'],
    ),
    (
      '0114-breaded-chicken-cutlets.yaml',
      [3, 4],
      0,
      [
        '3 confirmed|789890|0.00|discarded|null',
        '4 confirmed|748967|0.00|discarded|null',
      ],
    ),
    (
      '0255-fish-and-chips.yaml',
      [2],
      9,
      ['2 confirmed|789890|0.00|discarded|null'],
    ),
    (
      '0315-oven-fried-onion-rings.yaml',
      [0],
      8,
      ['0 confirmed|789890|30.16|discarded|null'],
    ),
  ]) {
    test('F7: $file — $confirmed confirmed, then the food |$food skipped '
        'through the real PUT: each confirmed row re-derived as the compute '
        "derives it (base: the old plan's grams kept through every PUT); "
        'settled', () async {
      final db = _db();
      final fdc = _fdc();
      final r = await _compute(db, fdc, loadCorpusRecipe(file));
      for (final p in confirmed) {
        await _put(db, fdc, r.id, p, {'confirmed': true});
      }
      await _put(db, fdc, r.id, food, {'skipped': true});
      final state = await _settled(db, fdc, r.id);
      expect([
        for (final p in confirmed)
          state.split('\n').firstWhere((l) => l.startsWith('$p ')),
      ], rows);
    });
  }

  // closer 4 (verify4 D1, F7's sibling): a person's PICK of a plan row (no
  // grams typed) is derived on the PUT as the compute derives it — held
  // `coating` while its coat has no budget (M62 H: the hold a pick keeps),
  // the line's own weight once the coated food is back. Every path: the
  // PUT's stored rows == the matches GET == a recompute == a full compute.
  Future<String> settledWithGet(
    SaltDatabase db,
    FixtureProvider fdc,
    String id,
  ) async {
    final body = await matchesBody(db, fdc, nutritionRecipeOf(db, id)!.recipe);
    expect(
      [
        for (final it in (body['items']! as List).cast<Map<String, Object?>>())
          if (it['match'] case final Map<String, Object?> m)
            '${it['position']} ${(m['grams'] as num?)?.toStringAsFixed(2)} ${m['hold']}',
      ],
      [
        for (final r in db.ingredientMatchesFor(id))
          '${r.position} ${r.grams?.toStringAsFixed(2)} ${r.hold}',
      ],
      reason: 'GET == stored ($id)',
    );
    return _settled(db, fdc, id);
  }

  String at(String state, int p) =>
      state.split('\n').firstWhere((l) => l.startsWith('$p '));

  for (final (file, picked, food, before, held, kcal) in const [
    (
      '0114-breaded-chicken-cutlets.yaml',
      4,
      0,
      '4 overridden|748967|100.00|piece|null',
      '4 overridden|748967|null|null|coating',
      '126.0000',
    ),
    (
      '0255-fish-and-chips.yaml',
      3,
      9,
      '3 overridden|169698|63.88|density|null',
      '3 overridden|169698|null|null|coating',
      '1506.1605',
    ),
  ]) {
    test('F7, a pick (closer 4, verify4 D1): $file |$picked picked on its own '
        'record, then the coated food |$food skipped through the real PUT — '
        'held `coating` on the PUT, the GET, a recompute and a compute, '
        '$kcal kcal (base and v82 before: the PUT and a recompute kept the '
        "pick's grams — 0114 274.00, 0255 1,749.54 kcal)", () async {
      final db = _db();
      final fdc = _fdc();
      final r = await _compute(db, fdc, loadCorpusRecipe(file));
      await _put(db, fdc, r.id, picked, {
        'fdc_id': _row(db, r.id, picked).fdcId,
      });
      expect(at(await settledWithGet(db, fdc, r.id), picked), before);
      await _put(db, fdc, r.id, food, {'skipped': true});
      final state = await settledWithGet(db, fdc, r.id);
      expect(at(state, picked), held);
      expect(state.split('\n').last, kcal);
    });
  }

  test("F7, a pick freed (closer 4, verify4 D1): 0114's egg |4 picked, the "
      'cutlets |0 skipped, then un-skipped — and the cutlets skipped BEFORE '
      'the pick (the pick held at its own PUT), then un-skipped: the egg '
      'back at its own weight, 100.00 g, on every path (base: the second '
      'kept `coating` through the PUT and a recompute)', () async {
    for (final skipFirst in [false, true]) {
      final db = _db();
      final fdc = _fdc();
      final r = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
      );
      Future<void> pick() => _put(db, fdc, r.id, 4, {'fdc_id': 748967});
      if (!skipFirst) {
        await pick();
      }
      await _put(db, fdc, r.id, 0, {'skipped': true});
      if (skipFirst) {
        await pick();
      }
      expect(
        at(await settledWithGet(db, fdc, r.id), 4),
        '4 overridden|748967|null|null|coating',
        reason: 'skipFirst: $skipFirst',
      );
      await _put(db, fdc, r.id, 0, {'skipped': false});
      expect(
        at(await settledWithGet(db, fdc, r.id), 4),
        '4 overridden|748967|100.00|piece|null',
        reason: 'skipFirst: $skipFirst',
      );
    }
  });

  test('F7, a pick with grams typed (closer 4, verify4 D1): '
      "0114's egg |4 picked with 77 g typed, then the cutlets |0 skipped — "
      'the typed grams stand on every path (a pick the plan holds is one '
      'with no grams typed)', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
    );
    await _put(db, fdc, r.id, 4, {'fdc_id': 748967, 'grams': 77.0});
    await _put(db, fdc, r.id, 0, {'skipped': true});
    expect(
      at(await settledWithGet(db, fdc, r.id), 4),
      '4 overridden|748967|77.00|override|null',
    );
  });

  test("F7's pick arm, its cost (closer 4, verify4 D1): 0114's flour |3 "
      'and egg |4 picked (the flour keeps the coat hold a pick keeps, the egg '
      'counted whole), then the cutlets |0 skipped (the egg held with the '
      'coat) — a plain recompute in each state plans M52 once and reads no '
      'food a pick at rest does not need (the flour: base 6 food reads, the '
      "egg held: base 4 → 3); the arm's line test reads the picked flour's "
      'mixing sentences once each (`mixTests` 2, base 0; with the coat '
      "held, H's own 2 → 4)", () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0114-breaded-chicken-cutlets.yaml'),
    );
    Map<String, int?> counts() {
      stepIndexCounts.clear();
      knownFoodReads = 0;
      m52PlanRuns = 0;
      recomputeTotals(db, nutritionRecipeOf(db, r.id)!.recipe);
      return {
        'plans': m52PlanRuns,
        'knownFoodReads': knownFoodReads,
        'mixTests': stepIndexCounts['mixTests'],
        'memo:mayHoldCoat': stepIndexCounts['memo:mayHoldCoat'],
        'memo:mixes': stepIndexCounts['memo:mixes'],
      };
    }

    await _put(db, fdc, r.id, 3, {'fdc_id': 789890});
    await _put(db, fdc, r.id, 4, {'fdc_id': 748967});
    expect(counts(), {
      'plans': 1,
      'knownFoodReads': 6,
      'mixTests': 2,
      'memo:mayHoldCoat': 1,
      'memo:mixes': 2,
    });
    await _put(db, fdc, r.id, 0, {'skipped': true});
    expect(counts(), {
      'plans': 1,
      'knownFoodReads': 3,
      'mixTests': 4,
      'memo:mayHoldCoat': 1,
      'memo:mixes': 4,
    });
    expect(
      [
        for (final p in [3, 4]) _sig(_row(db, r.id, p)),
      ],
      [
        'overridden|789890|null|null|coating',
        'overridden|748967|null|null|coating',
      ],
    );
  });

  // closer 5 (verify5 D1, F7's Confirm in order C): the coated food skipped,
  // every M52 row confirmed (H holds the coat: each confirmed part resolves
  // to 0 g `discarded`, no hold), the food un-skipped — the coat has a
  // budget again and the plan no entry for a part, so the PUT re-derives
  // each confirmed part as the compute derives it (base and v82 before: the
  // PUT and a recompute kept the 0 g — 0254 943.56, 0149 2,550.27 kcal).
  for (final (file, food, confirmed, parts, kcal) in const [
    (
      '0254-crunchy-oven-fried-fish.yaml',
      11,
      [0, 5, 6, 7, 8, 9, 10],
      [
        '6 confirmed|748967|100.00|piece|null',
        '7 confirmed|2710204|41.40|portion|null',
        '8 confirmed|173472|10.00|portion|null',
        '9 confirmed|171329|1.16|density|null',
        '10 confirmed|170932|0.45|portion|null',
      ],
      '1382.5822',
    ),
    (
      '0149-easier-fried-chicken.yaml',
      7,
      [0, 3, 4, 5, 6, 8, 9, 10],
      [
        '0 confirmed|2705393|305.00|portion|null',
        '3 confirmed|170931|6.95|density|null',
        '4 confirmed|171325|3.11|density|null',
        '5 confirmed|171329|2.32|density|null',
        '6 confirmed|170932|0.45|portion|null',
        '9 confirmed|172804|9.07|density|null',
      ],
      '2721.7335',
    ),
  ]) {
    test(
      'F7, a Confirm freed (closer 5, verify5 D1): $file — the food '
      '|$food skipped, every M52 row ($confirmed) confirmed, the food '
      'un-skipped through the real PUT: each part H resolved to 0 g counted '
      'again, $kcal kcal on the PUT, the GET, a recompute and a compute',
      () async {
        final db = _db();
        final fdc = _fdc();
        final r = await _compute(db, fdc, loadCorpusRecipe(file));
        await _put(db, fdc, r.id, food, {'skipped': true});
        expect([
          for (final m in db.ingredientMatchesFor(r.id))
            if (m.status == 'auto' &&
                m.childRecipeId == null &&
                (m.gramSource == 'discarded' ||
                    const {
                      'coating',
                      'discarded_medium',
                      'partial_pour_away',
                    }.contains(m.hold)))
              m.position,
        ], confirmed);
        for (final p in confirmed) {
          await _put(db, fdc, r.id, p, {'confirmed': true});
        }
        final held = await settledWithGet(db, fdc, r.id);
        for (final row in parts) {
          final p = int.parse(row.split(' ').first);
          expect(
            at(held, p),
            '$p confirmed|${_row(db, r.id, p).fdcId}|0.00|discarded|null',
          );
        }
        await _put(db, fdc, r.id, food, {'skipped': false});
        final state = await settledWithGet(db, fdc, r.id);
        expect([
          for (final row in parts) at(state, int.parse(row.split(' ').first)),
        ], parts);
        expect(state.split('\n').last, kcal);
      },
    );
  }

  // closer 5 (verify5 D1): the confirm arm reads every coat-mixture line
  // ([_coatOfPart]), the coated food's too — derivedFor decides it as any
  // counted food, the same derivation. STATED state (no tree path writes
  // it): 0279's shrimp |0 stored as base's F6 Confirm left it, 0.00 g
  // `discarded`; a plain recompute (a PUT's) re-derives the engine's weight.
  test('F7, the confirm arm on the coated food (closer 5, verify5 D1; '
      "STATED: 0279's shrimp |0 stored confirmed at base's F6 outcome, 0.00 g "
      "`discarded`) — a recompute writes 680.39 g weight, a compute's; "
      'settled', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(db, fdc, loadCorpusRecipe(shrimp));
    final energy = _energy(db, r.id).toStringAsFixed(2);
    db.upsertIngredientMatch(
      _row(db, r.id, 0).copyWith(
        status: 'confirmed',
        grams: 0,
        gramSource: 'discarded',
        clearHold: true,
      ),
    );
    recomputeTotals(db, nutritionRecipeOf(db, r.id)!.recipe);
    expect(_sig(_row(db, r.id, 0)), 'confirmed|175179|680.39|weight|null');
    expect(_energy(db, r.id).toStringAsFixed(2), energy);
    await _settled(db, fdc, r.id);
  });

  // closer 5 (verify5 D1): the arm reads a coat-mixture line in either plan
  // form for an ENGINE row too (the v70 F9 rule's own scope: budgeted or
  // held). STATED state: 0254's eggs |6, counted whole under the fish's
  // budget (no plan entry), stored at a plan's 0.00 g `discarded`; a plain
  // recompute writes the compute's row.
  test(
    'F7, the arm on an engine part (closer 5, verify5 D1; STATED: '
    "0254's eggs |6 stored at a plan's 0.00 g `discarded` while the plan "
    "has no entry for it) — a recompute writes the compute's row; settled",
    () async {
      final db = _db();
      final fdc = _fdc();
      final r = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0254-crunchy-oven-fried-fish.yaml'),
      );
      final computed = _state(db, r.id);
      expect(_sig(_row(db, r.id, 6)), 'auto|748967|100.00|piece|null');
      db.upsertIngredientMatch(
        _row(db, r.id, 6).copyWith(grams: 0, gramSource: 'discarded'),
      );
      recomputeTotals(db, nutritionRecipeOf(db, r.id)!.recipe);
      expect(_state(db, r.id), computed);
      expect(await _settled(db, fdc, r.id), computed);
    },
  );

  test("F11 (folded into F7; the fleet's, STATED edit): "
      "crispy-fried-chicken's flour |8 confirmed (144.06 g), then its "
      'chicken line edited '
      '"4 pounds" → "10 pounds" and not yet computed — the GET reads the '
      'flour as stored (base: 0.00 g "poured away after your confirm"), a '
      'Confirm PUT in the window stores it and holds no dip (base: 0.00 g, '
      'the egg and buttermilk held `coating`, 3,329.77 → 2,723.81 kcal), a '
      'recompute writes nothing; the next compute equals a fresh compute of '
      'the edited recipe (360.15 g)', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0148-crispy-fried-chicken.yaml'),
    );
    await _put(db, fdc, r.id, 8, {'confirmed': true});
    expect(_sig(_row(db, r.id, 8)), 'confirmed|789890|144.06|discarded|null');
    Future<String> got() async {
      final body = await matchesBody(
        db,
        fdc,
        nutritionRecipeOf(db, r.id)!.recipe,
      );
      final m = ((body['items']! as List)[8] as Map)['match'] as Map;
      return '${(m['grams'] as num).toStringAsFixed(2)} ${m['hold_note']}';
    }

    expect(await got(), '144.06 eaten part counted after your confirm');
    final chicken = nutritionLines(r)[6];
    final raw = chicken.raw.replaceFirst('4 pounds', '10 pounds');
    expect(raw, isNot(chicken.raw));
    final edited = r.copyWith(
      ingredients: [
        for (final g in r.ingredients)
          g.copyWith(
            items: [
              for (final l in g.items) l.raw == chicken.raw ? _ln(raw) : l,
            ],
          ),
      ],
    );
    db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'edited');
    final window = _state(db, r.id);
    expect(await got(), '144.06 eaten part counted after your confirm');
    await _put(db, fdc, r.id, 8, {'confirmed': true});
    expect(_state(db, r.id), window, reason: 'a Confirm in the window');
    recomputeTotals(db, nutritionRecipeOf(db, r.id)!.recipe);
    expect(_state(db, r.id), window, reason: 'a recompute in the window');
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, r.id)!.recipe),
      isNull,
    );
    expect(_row(db, r.id, 8).grams?.toStringAsFixed(2), '360.15');
    // A fresh compute of the edited recipe, the flour confirmed the same.
    final fresh = _db();
    final again = await _compute(
      fresh,
      fdc,
      edited.copyWith(id: '${r.id}-fresh', slug: '${r.slug}-fresh'),
    );
    await _put(fresh, fdc, again.id, 8, {'confirmed': true});
    expect(
      _state(db, r.id),
      _state(fresh, again.id),
    );
  });

  test("F11's gate (an empty key matches no line): crispy-fried-chicken's "
      'flour |8 confirmed, then its chicken line written "2 tablespoons" '
      '(STATED: a line with no item, key "") and its stale row given the '
      'empty key (STATED) — another ingredient now, never read as the coated '
      'food: the GET reads the flour poured away (0.00 g)', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0148-crispy-fried-chicken.yaml'),
    );
    await _put(db, fdc, r.id, 8, {'confirmed': true});
    final chicken = nutritionLines(r)[6];
    final keyless = _ln('2 tablespoons');
    expect(lineKeyOf(keyless), '');
    final edited = r.copyWith(
      ingredients: [
        for (final g in r.ingredients)
          g.copyWith(
            items: [
              for (final l in g.items) l.raw == chicken.raw ? keyless : l,
            ],
          ),
      ],
    );
    final stale = _row(db, r.id, 6);
    db
      ..upsertRecipe(edited, sourceSlug: _source, contentHash: 'keyless')
      ..upsertIngredientMatch(stale.copyWith(itemKey: ''));
    expect(_row(db, r.id, 6).raw, chicken.raw);
    final body = await matchesBody(
      db,
      fdc,
      nutritionRecipeOf(db, r.id)!.recipe,
    );
    final m = ((body['items']! as List)[8] as Map)['match'] as Map;
    expect(
      '${(m['grams'] as num).toStringAsFixed(2)} ${m['hold_note']}',
      '0.00 poured away after your confirm',
    );
  });

  test("F11's same-ingredient gate (closer 1, verify1 D4; STATED): "
      "crispy-fried-chicken's flour |8 confirmed, then its chicken line "
      'written "4 pounds bone-in pork chops, trimmed" (another item key) and '
      "not yet computed — the stale chicken row is no longer the line's "
      'ingredient: the GET reads the flour poured away (0.00 g; the key '
      'equality dropped: 144.06 g, eaten part counted)', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0148-crispy-fried-chicken.yaml'),
    );
    await _put(db, fdc, r.id, 8, {'confirmed': true});
    final chicken = nutritionLines(r)[6];
    final pork = _ln('4 pounds bone-in pork chops, trimmed');
    expect(lineKeyOf(pork), isNot(_row(db, r.id, 6).itemKey));
    expect(lineKeyOf(pork), isNotEmpty);
    db.upsertRecipe(
      r.copyWith(
        ingredients: [
          for (final g in r.ingredients)
            g.copyWith(
              items: [
                for (final l in g.items) l.raw == chicken.raw ? pork : l,
              ],
            ),
        ],
      ),
      sourceSlug: _source,
      contentHash: 'pork',
    );
    expect(_row(db, r.id, 6).raw, chicken.raw);
    final body = await matchesBody(
      db,
      fdc,
      nutritionRecipeOf(db, r.id)!.recipe,
    );
    final m = ((body['items']! as List)[8] as Map)['match'] as Map;
    expect(
      '${(m['grams'] as num).toStringAsFixed(2)} ${m['hold_note']}',
      '0.00 poured away after your confirm',
    );
  });

  test('F8: the five coat-mixture parts of 0149 confirmed through the real '
      'PUT key as dips — the matches GET plans M52 once, a compute twice '
      '(base: 6 and 6, a plan per confirmed part); settled', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0149-easier-fried-chicken.yaml'),
    );
    const parts = [3, 4, 5, 6, 9];
    expect(
      [for (final p in parts) nutritionLines(r)[p].raw],
      [
        '3 teaspoons ground black pepper',
        '1 teaspoon garlic powder',
        '1 teaspoon paprika',
        '¼ teaspoon cayenne pepper',
        '2 teaspoons baking powder',
      ],
    );
    for (final p in parts) {
      await _put(db, fdc, r.id, p, {'confirmed': true});
    }
    await _settled(db, fdc, r.id);
    m52PlanRuns = 0;
    await matchesBody(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
    final get = m52PlanRuns;
    m52PlanRuns = 0;
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, r.id)!.recipe);
    expect((get, m52PlanRuns), (1, 2));
  });
}

/// F10 (the Opus critic): a line-conditioned move never carries as the
/// ingredient's decision — [decisionRecordOf] names the record bought, and
/// each line the decision is carried to moves again on its own text and
/// recipe ([carriedFoodOf]) — the three-call invariant extended to the
/// decision carry. Zero requests (every move's target a hit of the line's
/// own cached answer).
void carries() {
  /// The FDC detail requests the last [pick] made (the fresh library holds
  /// no detail of a record no engine row read).
  var pickFetches = 0;

  /// [files] computed in one library, [confirm] (file, position) confirmed
  /// through the real PUT (or [pick]ed: its requests in [pickFetches]), then
  /// every other recipe computed again: the key's decision and each (file,
  /// position) row's record.
  Future<(int?, Map<String, int?>)> carried(
    List<String> files,
    (String, int) confirm,
    String key,
    List<(String, int)> read, {
    List<Recipe> extra = const [],
    int? pick,
  }) async {
    final db = _db();
    final fdc = _fdc();
    final ids = <String, String>{};
    for (final f in files) {
      ids[f] = (await _compute(db, fdc, loadCorpusRecipe(f))).id;
    }
    for (final r in extra) {
      ids[r.id] = (await _compute(db, fdc, r)).id;
    }
    final (file, position) = confirm;
    var asked = (fdc.searchCalls, fdc.foodCalls);
    await _put(
      db,
      fdc,
      ids[file]!,
      position,
      pick == null ? {'confirmed': true} : {'fdc_id': pick},
    );
    if (pick != null) {
      expect(fdc.searchCalls, asked.$1, reason: 'no search');
      pickFetches = fdc.foodCalls - asked.$2;
      asked = (fdc.searchCalls, fdc.foodCalls);
    }
    for (final MapEntry(key: f, value: id) in ids.entries) {
      if (f != file) {
        expect(
          await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe),
          isNull,
        );
      }
    }
    expect((fdc.searchCalls, fdc.foodCalls), asked, reason: 'zero requests');
    return (
      db.decisionFor(key)?.fdcId,
      {
        for (final (f, p) in read)
          '${f.endsWith('.yaml') ? f.substring(0, 4) : 'copy'}|$p': _row(
            db,
            ids[f]!,
            p,
          ).fdcId,
      },
    );
  }

  const ultimate = '0586-ultimate-charcoal-grilled-steaks.yaml';
  const panSeared = '0187-pan-seared-strip-steaks.yaml';

  test('F10, Q7\'s "fat caps removed" (171751): a Confirm of 0586|0 decides '
      "the strip steak bought (2727572) — 0187's line keeps it (base: the "
      'decision 171751 moved every strip line); a Confirm of 0187|0 carries '
      "2727572 to 0586, which moves again (base: Q7's move lost)", () async {
    for (final confirm in const [(ultimate, 0), (panSeared, 0)]) {
      final (decision, rows) = await carried(
        [ultimate, panSeared],
        confirm,
        'boneless strip steak',
        [(ultimate, 0), (panSeared, 0)],
      );
      expect(decision, 2727572, reason: confirm.$1);
      expect(rows, {'0586|0': 171751, '0187|0': 2727572}, reason: confirm.$1);
    }
  });

  const corned = '0091-home-corned-beef-with-vegetables.yaml';
  const pomegranate =
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
  const england = '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml';
  const onion = '0223-onion-braised-beef-brisket.yaml';
  for (final confirm in const [(corned, 0), (pomegranate, 0)]) {
    test('F10, the flat: a Confirm of ${confirm.$1.substring(0, 4)}|0 '
        "(173128 — 0091's by its step's printed trim, M74; 0224's by its "
        "line's ¼ inch, M70) decides the lean-only top bought (168657: R2 "
        '→ 168743, then the trim → 173128) — each brisket line lands as its '
        'own engine does: 0090|6 and 0223|0 on 168743, 0091|0 and 0224|0 on '
        '173128 (base: the decision 173128 on all four)', () async {
      final (decision, rows) = await carried(
        [corned, pomegranate, england, onion],
        confirm,
        'beef brisket',
        [(corned, 0), (pomegranate, 0), (england, 6), (onion, 0)],
      );
      expect(decision, 168657);
      expect(rows, {
        '0091|0': 173128,
        '0224|0': 173128,
        '0090|6': 168743,
        '0223|0': 168743,
      });
    });
  }

  test('F10, apply_to_all: 0224|0 (173128) confirmed to every brisket line '
      'through the real PUT, 0090|6 and 0223|0 left on 173128 by an earlier '
      'library (STATED: their engine rows rewritten) — the matches GET offers '
      'exactly what the write lands (the v81 F5 invariant): those two, each '
      "moved on its own text to 168743; never 0091|0, whose step's trim "
      'leaves it on 173128 (a row the decision leaves on its record is no '
      'offer, as a row on the decided food) — zero requests', () async {
    final db = _db();
    final fdc = _fdc();
    final ids = <String, String>{};
    for (final f in [corned, england, onion, pomegranate]) {
      ids[f] = (await _compute(db, fdc, loadCorpusRecipe(f))).id;
    }
    for (final (f, p) in [(england, 6), (onion, 0)]) {
      final row = _row(db, ids[f]!, p);
      expect(row.fdcId, 168743);
      db.upsertIngredientMatch(
        row.copyWith(
          fdcId: 173128,
          description: _row(db, ids[pomegranate]!, 0).description,
        ),
      );
    }
    final recipe = nutritionRecipeOf(db, ids[pomegranate]!)!.recipe;
    final item =
        ((await matchesBody(db, fdc, recipe))['items']! as List)[0] as Map;
    final asked = (fdc.searchCalls, fdc.foodCalls);
    final applied = await applyMatchOverride(db, fdc, recipe, 0, {
      'raw': item['raw'],
      'confirmed': true,
      'apply_to_all': true,
    });
    expect((fdc.searchCalls, fdc.foodCalls), asked, reason: 'zero requests');
    expect(
      (item['others'], item['others_lines']),
      (applied?.recipes ?? 0, applied?.lines ?? 0),
    );
    expect((applied?.recipes, applied?.lines), (2, 2));
    expect(
      {
        for (final (f, p) in [(corned, 0), (england, 6), (onion, 0)])
          f.substring(0, 4): _row(db, ids[f]!, p).fdcId,
      },
      {'0091': 173128, '0090': 168743, '0223': 168743},
    );
    expect(db.decisionFor('beef brisket')?.fdcId, 168657);
  });

  const grillRoasted = '0606-grill-roasted-pork-loin.yaml';
  test('F10, R2 alone (no trim): a Confirm of maple-glazed-pork-roast|4 '
      '(168381, the lean-and-fat sibling R2 moved its lean-only top 169194 '
      "to, v54) decides 169194 — the key's other line "
      '(grill-roasted-pork-loin|1, no "lean") moves to 168381 again (base: '
      'the decision '
      '168381)', () async {
    final (decision, rows) = await carried(
      [
        '0239-maple-glazed-pork-roast.yaml',
        grillRoasted,
      ],
      ('0239-maple-glazed-pork-roast.yaml', 4),
      'boneless blade-end pork loin roast',
      [('0239-maple-glazed-pork-roast.yaml', 4), (grillRoasted, 1)],
    );
    expect(decision, 169194);
    expect(rows, {'0239|4': 168381, '0606|1': 168381});
  });

  test("F10, R2's reverse memo (`leanOnlyReads`; Key: the line's text and "
      "item and the record): on 0239's computed library — its real line on "
      "168381 reads 169194; on 168314 (top loin, its answer's other "
      'lean-and-fat pair) 168315; on 168286 (center loin, no lean-only '
      'sibling there) itself; the line written "…, trimmed of all fat" '
      '(STATED: R2 never moves it) reads 168381 itself — each once', () async {
    final db = _db();
    final r = await _compute(
      db,
      _fdc(),
      loadCorpusRecipe('0239-maple-glazed-pork-roast.yaml'),
    );
    final line = nutritionLines(r)[4];
    expect(line.raw, startsWith('1 (2½-pound) boneless blade-end pork loin'));
    final trimmed = _ln('${line.raw}, trimmed of all fat');
    expect(lineKeyOf(trimmed), lineKeyOf(line));
    int? bought(IngredientLine l, int id) => decisionRecordOf(
      r,
      l,
      id,
      db: db,
      description: 'Pork, fresh, separable lean and fat',
    );
    stepIndexCounts.clear();
    expect(
      [
        bought(line, 168381),
        bought(line, 168314),
        bought(line, 168286),
        bought(trimmed, 168381),
        bought(line, 168381),
        bought(trimmed, 168381),
      ],
      [169194, 168315, 168286, 168381, 169194, 168381],
    );
    expect(stepIndexCounts['leanOnlyReads'], 4);
    // A cache write voids the memo (STATED: the line's cached answer
    // rewritten without its lean-only record — R2 has no top to undo).
    const query = 'boneless blade-end pork loin roast';
    final answer = jsonDecode(db.fdcSearchCacheGet(query)!) as List<dynamic>;
    db.fdcSearchCachePut(
      query,
      jsonEncode([
        for (final c in answer)
          if ((c as Map)['fdc_id'] != 169194) c,
      ]),
    );
    expect(bought(line, 168381), 168381);
  });

  test("F10, R2's reverse memo, the item coordinate (closer 1, verify1 D5; "
      "STATED): 0239's pork roast text under 0187's item 'boneless strip "
      "steak' reads that item's own cached answer — 168381 itself, asked "
      'first — and the real line then still 169194 (the item dropped from '
      'the key: 168381 for both)', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0239-maple-glazed-pork-roast.yaml'),
    );
    await _compute(db, fdc, loadCorpusRecipe(panSeared));
    final line = nutritionLines(r)[4];
    final steak = IngredientLine(
      raw: line.raw,
      item: 'boneless strip steak',
      prep: line.prep,
      amounts: line.amounts,
    );
    int? bought(IngredientLine l) => decisionRecordOf(
      r,
      l,
      168381,
      db: db,
      description: 'Pork, fresh, separable lean and fat',
    );
    stepIndexCounts.clear();
    expect([bought(steak), bought(line)], [168381, 169194]);
    expect(stepIndexCounts['leanOnlyReads'], 2);
  });

  test("F10, the reach's census: every move target — each trimDepthRecords "
      "entry's and the step-printed trim's 173128 — is a lean-and-fat record "
      '(the one pre-gate `_leftOnItsRecord` reads; a new entry breaking it '
      'fails here)', () {
    final targets = {
      for (final (_, pairs) in trimDepthRecords) ...pairs.values,
      173128,
    };
    expect(targets, {174414, 168664, 173128, 171751, 174377});
    // Each target's description as a recorded answer holds it.
    final searches =
        jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
            as Map<String, dynamic>;
    final described = <int, String>{
      for (final answer in searches.values)
        for (final c in answer as List<dynamic>)
          if (targets.contains((c as Map)['fdc_id']))
            c['fdc_id'] as int: c['description'] as String,
    };
    expect(described.keys.toSet(), targets);
    for (final MapEntry(key: id, value: d) in described.entries) {
      expect(
        d.toLowerCase(),
        contains('separable lean and fat'),
        reason: '$id',
      );
    }
  });

  test("F10, the reach: a row the decision's moves leave on its record is no "
      "offer — 0228|0's Confirm offers nothing (0622's trimmed rack lands "
      "174377 again; the trim's target read on the row's text), 0239|4's "
      "nothing (0606's line R2 moves back to 168381); 0622's row below the "
      'gate (STATED: its confidence rewritten 0.30) or held `no_nutrients` '
      '(STATED) is offered and written '
      'at confidence 1, on 174377 (the unoffered rows keep their engine '
      'scores, 0.98 and 0.70)', () async {
    const roast = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
    const grilled = '0622-grilled-rack-of-lamb.yaml';
    const maple = '0239-maple-glazed-pork-roast.yaml';
    Future<(Object?, Object?, int?)> offer(
      String file,
      int position,
      List<String> others, {
      void Function(SaltDatabase db, Map<String, String> ids)? before,
    }) async {
      final db = _db();
      final fdc = _fdc();
      final ids = <String, String>{};
      for (final f in [...others, file]) {
        ids[f] = (await _compute(db, fdc, loadCorpusRecipe(f))).id;
      }
      before?.call(db, ids);
      final recipe = nutritionRecipeOf(db, ids[file]!)!.recipe;
      final item =
          ((await matchesBody(db, fdc, recipe))['items']! as List)[position]
              as Map;
      final applied = await applyMatchOverride(db, fdc, recipe, position, {
        'raw': item['raw'],
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(
        (item['others'], item['others_lines']),
        (applied?.recipes ?? 0, applied?.lines ?? 0),
      );
      final first = others.first;
      final p = first == grilled ? 5 : 1;
      final row = _row(db, ids[first]!, p);
      return (item['others_lines'], row.fdcId, (row.confidence * 100).round());
    }

    expect(await offer(roast, 0, [grilled]), (0, 174377, 98));
    expect(
      await offer(
        roast,
        0,
        [grilled],
        before: (db, ids) {
          final row = _row(db, ids[grilled]!, 5);
          db.upsertIngredientMatch(row.copyWith(confidence: 0.3));
        },
      ),
      (1, 174377, 100),
    );
    // A food hold on the row (STATED: `no_nutrients` written): the write
    // resolves it — offered.
    expect(
      await offer(
        roast,
        0,
        [grilled],
        before: (db, ids) {
          final row = _row(db, ids[grilled]!, 5);
          db.upsertIngredientMatch(row.copyWith(hold: 'no_nutrients'));
        },
      ),
      (1, 174377, 100),
    );
    expect(
      await offer(maple, 4, ['0606-grill-roasted-pork-loin.yaml']),
      (0, 168381, 70),
    );
  });

  test(
    "F10, the reach's memo (Key: the row's text, its recipe where the "
    "step-printed trim reads it, the decided record): one request's reach "
    'of "beef brisket" for 168657 then 173128 — 0090|6 and 0223|0 (on '
    '168743) left out for 168657, reached for 173128; and 0223 written '
    "with 0091's line, its row on 173128 (STATED: an earlier library) — "
    "reached where 0091's own row, its steps trimming the brisket, is not",
    () async {
      final db = _db();
      final fdc = _fdc();
      final ids = <String, String>{};
      for (final f in [corned, england, onion]) {
        ids[f] = (await _compute(db, fdc, loadCorpusRecipe(f))).id;
      }
      List<String> reach(int fdcId, ReachMemo memo) => [
        for (final r in decisionReach(
          db,
          'beef brisket',
          excluding: (recipeId: 'none', position: -1),
          fdcId: fdcId,
          memo: memo,
        ))
          '${r.recipeId.substring(12, 16)}|${r.position}',
      ];
      final memo = ReachMemo();
      // 0091|0 is on 173128 itself: reached for 168657 only where its moves
      // leave it elsewhere — its steps trim the flat, so they do not.
      expect(reach(168657, memo), isEmpty);
      expect(reach(173128, memo), ['0090|6', '0223|0']);
      // The recipe coordinate: 0223's line written as 0091's, on 173128.
      final c = loadCorpusRecipe(onion);
      final raw = nutritionLines(loadCorpusRecipe(corned))[0].raw;
      final copy = await _compute(
        db,
        fdc,
        c.copyWith(
          ingredients: [
            for (final g in c.ingredients)
              g.copyWith(
                items: [
                  for (final l in g.items)
                    l.raw == nutritionLines(c)[0].raw ? _ln(raw) : l,
                ],
              ),
          ],
        ),
      );
      final row = _row(db, copy.id, 0);
      db.upsertIngredientMatch(
        row.copyWith(
          fdcId: 173128,
          description: _row(db, ids[corned]!, 0).description,
        ),
      );
      expect(_row(db, ids[corned]!, 0).fdcId, 173128);
      expect(reach(168657, ReachMemo()), ['0223|0']);
    },
  );

  test("F10, the reach's memo, the text coordinate: 0622's rack (frenched "
      'and trimmed: 174377 again, left out) beside a row of the bare line '
      '"2 racks of lamb (1¾ to 2 pounds each), rib bones frenched" on 174377 '
      '(STATED: a recipe holding it, its row written by an earlier library) '
      '— 172493 lands that one on 174321: reached', () async {
    const roast = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
    const grilled = '0622-grilled-rack-of-lamb.yaml';
    final db = _db();
    final fdc = _fdc();
    await _compute(db, fdc, loadCorpusRecipe(roast));
    final g = await _compute(db, fdc, loadCorpusRecipe(grilled));
    const bare = '2 racks of lamb (1¾ to 2 pounds each), rib bones frenched';
    final c = loadCorpusRecipe(roast);
    final copy = c.copyWith(
      id: '${c.id}-bare',
      slug: '${c.slug}-bare',
      ingredients: [
        for (final grp in c.ingredients)
          grp.copyWith(
            items: [
              for (final l in grp.items)
                l.raw.startsWith('2 racks of lamb') ? _ln(bare) : l,
            ],
          ),
      ],
    );
    db.upsertRecipe(
      copy,
      sourceSlug: _source,
      contentHash: contentHashOf(copy),
    );
    final rack = _row(db, g.id, 5);
    db.upsertIngredientMatch(
      IngredientMatchRow(
        recipeId: copy.id,
        position: 0,
        raw: bare,
        itemKey: rack.itemKey,
        fdcId: rack.fdcId,
        description: rack.description,
        dataType: rack.dataType,
        confidence: rack.confidence,
        grams: rack.grams,
        gramSource: rack.gramSource,
        status: rack.status,
      ),
    );
    expect(
      [
        for (final r in decisionReach(
          db,
          'rack of lamb',
          excluding: (recipeId: 'none', position: -1),
          fdcId: 172493,
        ))
          (r.raw, r.fdcId),
      ],
      [(bare, 174377)],
    );
  });

  test('F10, the whole brisket: a Confirm of 0595|10 (168664, the ⅛-inch '
      'record its "fat trimmed to ¼ inch" moves to, M68) decides 168607 — a '
      'copy of its line printing no trim (STATED) carries 168607 (base: '
      '168664)', () async {
    const whole = '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml';
    final c = loadCorpusRecipe(whole);
    final g = c.ingredients.first;
    final copy = c.copyWith(
      id: '${c.id}-untrimmed',
      slug: '${c.slug}-untrimmed',
      ingredients: [
        g.copyWith(
          items: [
            for (final l in g.items)
              l.raw ==
                      '1 (9- to 11-pound) whole beef brisket, fat trimmed to ¼ inch'
                  ? _ln('1 (9- to 11-pound) whole beef brisket')
                  : l,
          ],
        ),
        ...c.ingredients.skip(1),
      ],
    );
    expect(
      nutritionLines(copy)[10].raw,
      '1 (9- to 11-pound) whole beef brisket',
    );
    final (decision, rows) = await carried(
      [whole],
      (whole, 10),
      'whole beef brisket',
      [(whole, 10), (copy.id, 10)],
      extra: [copy],
    );
    expect(decision, 168607);
    expect(rows, {'0595|10': 168664, 'copy|10': 168607});
  });

  // closer 2 (verify2 D1 / D2): a PICK of a record the line's own moves
  // never reach decides that record — `decisionRecordOf`'s round trip
  // (the line's moves land a decision on the record bought back on the
  // pick) is every gate of the trim / R2 reverse: the phrase, the
  // step-printed trim, the target in the line's answer.
  test("F10, a pick the line's moves never reach (closer 2, verify2 D1): "
      '0228|0 ("fat trimmed to ⅛ to ¼ inch") picked to 174414 — the v55 '
      "entry's 172641 never re-lands there (0228's answer holds no 174414) "
      'so the decision is the pick, 174414, and 0622|5 is carried 174414 '
      '(the round trip dropped: 172641, a record nobody chose); apply_to_all '
      'writes the same', () async {
    const roast = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
    const grilled = '0622-grilled-rack-of-lamb.yaml';
    final (decision, rows) = await carried(
      [roast, grilled],
      (roast, 0),
      'rack of lamb',
      [(roast, 0), (grilled, 5)],
      pick: 174414,
    );
    expect(decision, 174414);
    expect(rows, {'0228|0': 174414, '0622|5': 174414});
    expect(pickFetches, 1, reason: "the pick's own detail, no other");
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(db, fdc, loadCorpusRecipe(roast));
    final other = await _compute(db, fdc, loadCorpusRecipe(grilled));
    expect(_row(db, other.id, 5).fdcId, 174377);
    final recipe = nutritionRecipeOf(db, r.id)!.recipe;
    final applied = await applyMatchOverride(db, fdc, recipe, 0, {
      'raw': nutritionLines(recipe)[0].raw,
      'fdc_id': 174414,
      'apply_to_all': true,
    });
    expect((applied?.recipes, applied?.lines), (1, 1));
    expect(db.decisionFor('rack of lamb')?.fdcId, 174414);
    expect(_row(db, other.id, 5).fdcId, 174414);
  });

  test("F10, the round trip's corpus picks (closer 2, verify2 D2 — the "
      "phrase and the step-printed trim are the round trip's, no gate of "
      'their own): 0187|0 (no "fat caps removed") picked to 171751 decides '
      "171751 (Q7's key 2727572 never moves there; the round trip dropped: "
      '2727572); 0223|0 and 0090|6 (no depth printed, no step trimming the '
      "brisket) picked to 173128 decide R2's lean-only 174057, which carries "
      'back to 173128 on every brisket line (the round trip dropped: 168657, '
      'carried to 168743)', () async {
    final (strip, strips) = await carried(
      [ultimate, panSeared],
      (panSeared, 0),
      'boneless strip steak',
      [(ultimate, 0), (panSeared, 0)],
      pick: 171751,
    );
    expect(strip, 171751);
    expect(strips, {'0586|0': 171751, '0187|0': 171751});
    for (final pick in const [(onion, 0), (england, 6)]) {
      final (decision, rows) = await carried(
        [corned, pomegranate, england, onion],
        pick,
        'beef brisket',
        [(corned, 0), (pomegranate, 0), (england, 6), (onion, 0)],
        pick: 173128,
      );
      expect(decision, 174057, reason: pick.$1);
      expect(rows, {
        '0091|0': 173128,
        '0224|0': 173128,
        '0090|6': 173128,
        '0223|0': 173128,
      }, reason: pick.$1);
    }
  });

  test("F10, R2's round trip (closer 2, verify2 D1 — the same claim on the "
      'R2 reverse): 0224|0 ("fat trimmed to ¼ inch") picked to the 0" '
      "flat 168743 decides 168743 — R2's lean-only 168657 lands on 168743 and "
      "the line's depth moves it on to 173128, never back (the round trip "
      'dropped: 168657, a record nobody chose); every other brisket line '
      'lands as its own engine does', () async {
    final (decision, rows) = await carried(
      [corned, pomegranate, england, onion],
      (pomegranate, 0),
      'beef brisket',
      [(corned, 0), (pomegranate, 0), (england, 6), (onion, 0)],
      pick: 168743,
    );
    expect(decision, 168743);
    expect(rows, {
      '0091|0': 173128,
      '0224|0': 168743,
      '0090|6': 168743,
      '0223|0': 168743,
    });
  });

  test("F10, the carried memo's step-printed trim arm (closer 3, verify3 "
      'D2; `arm`: only the 0" CHOICE flat 168743 no entry moved is '
      're-trimmed): 0090|6 picked to the SELECT 0" flat 169570 (a record of '
      "its own answer) decides R2's lean-only 168658, and every brisket "
      "line — 0091's, whose steps trim the brisket, too — keeps 169570; "
      '0223|0 picked to the 0" flat 169440 the same (the arm ungated: 0091 '
      'carried 173128, the CHOICE ⅛" flat — the pick lost)', () async {
    for (final (pick, id, decided) in const [
      ((england, 6), 169570, 168658),
      ((onion, 0), 169440, 170601),
    ]) {
      final (decision, rows) = await carried(
        [corned, pomegranate, england, onion],
        pick,
        'beef brisket',
        [(corned, 0), (pomegranate, 0), (england, 6), (onion, 0)],
        pick: id,
      );
      expect(decision, decided, reason: '$id');
      expect(rows, {
        '0091|0': id,
        '0224|0': id,
        '0090|6': id,
        '0223|0': id,
      }, reason: '$id');
    }
  });

  test("F10, the carry chain's first move (closer 3, verify3 D3; "
      "freshOverCured; STATED: a decision on a cured record of the line's "
      "own answer — the fresh-ham key holds 0249's one line, so no corpus "
      'key carries one there): 0249|0 ("bone-in fresh half ham") carries a '
      'decision on 168358 / 168347 / 169162 to its fresh record 168226 (the '
      'move dropped: the cured record), and a pick of 168358 there decides '
      "168358 (the move dropped: R2's lean-only 169176, whose carry lands "
      'back on 168358)', () async {
    final db = _db();
    final fdc = _fdc();
    final ham = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0249-roast-fresh-ham.yaml'),
    );
    final line = nutritionLines(ham)[0];
    expect(
      line.raw,
      '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably shank '
      'end, rinsed',
    );
    expect(_row(db, ham.id, 0).fdcId, 168226);
    FdcFood of(int id) => knownFood(db, id, line: line)!;
    expect(
      [
        for (final id in const [168358, 168347, 169162, 168226])
          carriedFoodOf(db, ham, line, of(id)).fdcId,
      ],
      [168226, 168226, 168226, 168226],
    );
    expect(
      decisionRecordOf(
        ham,
        line,
        168358,
        db: db,
        description: of(168358).description,
      ),
      168358,
    );
  });

  test("F10, the carried memo's key (closer 2, verify2 D5; `carriedReads`; "
      "Key: the line's text and item and the record decided; STATED: 0239's "
      'line written "…, trimmed of all fat" and its text under the item '
      "'boneless strip steak'): 169194 on the real line 168381 (R2), on the "
      'trimmed text 169194, under the steak item 169194 (its answer holds no '
      'sibling); 168315 on the real line 168314 — four reads, the repeat '
      "none; the step-printed trim read after the memo: 0091's flat 168743 → "
      '173128, and with 173128 gone from its answer, another answer holding it '
      '(STATED) '
      '168743', () async {
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(
      db,
      fdc,
      loadCorpusRecipe('0239-maple-glazed-pork-roast.yaml'),
    );
    await _compute(db, fdc, loadCorpusRecipe(panSeared));
    final c = await _compute(db, fdc, loadCorpusRecipe(corned));
    final line = nutritionLines(r)[4];
    final trimmed = _ln('${line.raw}, trimmed of all fat');
    expect(trimmed.item, line.item);
    final steak = IngredientLine(
      raw: line.raw,
      item: 'boneless strip steak',
      prep: line.prep,
      amounts: line.amounts,
    );
    stepIndexCounts.clear();
    expect(
      [
        for (final (l, id) in [
          (line, 169194),
          (trimmed, 169194),
          (steak, 169194),
          (line, 168315),
          (line, 169194),
        ])
          carriedFoodOf(db, r, l, knownFood(db, id, line: l)!).fdcId,
      ],
      [168381, 169194, 169194, 168314, 168381],
    );
    expect(stepIndexCounts['carriedReads'], 4);
    final flat = nutritionLines(c)[0];
    expect(flat.raw, '1 (4½- to 5-pound) beef brisket, flat cut');
    FdcFood carried() =>
        carriedFoodOf(db, c, flat, knownFood(db, 168743, line: flat)!);
    expect(carried().fdcId, 173128);
    // The answer FDC returns later without 173128, another cached answer
    // still holding its hit (STATED): the arm moves only to a record of the
    // line's own answer.
    const query = 'beef brisket';
    final answer = jsonDecode(db.fdcSearchCacheGet(query)!) as List<dynamic>;
    db.fdcSearchCachePut('beef brisket flat half', jsonEncode(answer));
    expect(knownFood(db, 173128)?.fdcId, 173128);
    db.fdcSearchCachePut(
      query,
      jsonEncode([
        for (final x in answer)
          if ((x as Map)['fdc_id'] != 173128) x,
      ]),
    );
    expect(carried().fdcId, 168743);
  });

  test('F10, the racks: a Confirm of 0228|0 (174377 by the "trimmed" entry, '
      'M79) decides the lean-only record bought (172493: R2 → 174321, then '
      "the trim) — 0622's rack prints \"trimmed\" and lands on 174377 "
      "(base: the decision 174377); a line printing no trim (STATED: 0228's "
      'written without it) carries 172493 to 174321, a hit of its own answer '
      '(base: 174377, the move carried)', () async {
    const roast = '0228-roast-rack-of-lamb-with-roasted-red-pepper-relish.yaml';
    const grilled = '0622-grilled-rack-of-lamb.yaml';
    final db = _db();
    final fdc = _fdc();
    final r = await _compute(db, fdc, loadCorpusRecipe(roast));
    final other = await _compute(db, fdc, loadCorpusRecipe(grilled));
    final asked = (fdc.searchCalls, fdc.foodCalls);
    await _put(db, fdc, r.id, 0, {'confirmed': true});
    expect(db.decisionFor('rack of lamb')?.fdcId, 172493);
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, other.id)!.recipe),
      isNull,
    );
    expect((fdc.searchCalls, fdc.foodCalls), asked, reason: 'zero requests');
    expect(_row(db, other.id, 5).fdcId, 174377);
    expect(_row(db, r.id, 0).fdcId, 174377);
    const bare = '2 racks of lamb (1¾ to 2 pounds each), rib bones frenched';
    final copy = r.copyWith(
      ingredients: [
        for (final g in r.ingredients)
          g.copyWith(
            items: [
              for (final l in g.items)
                l.raw.startsWith('2 racks of lamb') ? _ln(bare) : l,
            ],
          ),
      ],
    );
    final line = nutritionLines(copy)[0];
    expect(line.raw, bare);
    expect(lineKeyOf(line), 'rack of lamb');
    expect(
      carriedFoodOf(db, copy, line, knownFood(db, 172493, line: line)!).fdcId,
      174321,
    );
    expect((fdc.searchCalls, fdc.foodCalls), asked, reason: 'zero requests');
  });
}

/// RULE C at the editor caps (120 steps × 10,000 characters, 400 lines):
/// each new reader once per index, its TRUE path exercised beside the quiet
/// one, the counts pinned EXACTLY on the compute, the GET and the
/// recompute; each path under the backstop. STATED synthesized cost inputs
/// (the house's cap-shape exception): real corpus recipes and lines,
/// repeated, under filler steps.
void costShapes() {
  Future<({Map<String, Map<String, int?>> seen, SaltDatabase db})> shape(
    String name,
    Recipe r,
    List<String> families, {
    FutureOr<void> Function(SaltDatabase db, Recipe stored)? before,
  }) async {
    final db = wp.tempDb();
    final provider = FixtureProvider(pending: pendingSearches);
    wp.saveRecipe(db, r);
    Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
    if (before != null) {
      await matchAndCompute(db, provider, stored());
      await before(db, stored());
    }
    final seen = <String, Map<String, int?>>{};
    for (final (step, run) in <(String, Future<Object?> Function())>[
      ('compute', () => matchAndCompute(db, provider, stored())),
      ('GET', () => matchesBody(db, provider, stored())),
      ('recompute', () async => recomputeTotals(db, stored())),
    ]) {
      stepIndexCounts.clear();
      m52PlanRuns = 0;
      knownFoodReads = 0;
      final sw = Stopwatch()..start();
      await run();
      final ms = sw.elapsedMilliseconds;
      final counts = Map.of(stepIndexCounts);
      expectBounded(r, counts, '$name $step', copies: counts['indexes'] ?? 1);
      expect(ms, lessThan(backstopMs), reason: '$name $step: $counts');
      seen[step] = {
        for (final f in families)
          f: switch (f) {
            'plans' => m52PlanRuns,
            'knownFoodReads' => knownFoodReads,
            _ => counts[f],
          },
      };
    }
    return (seen: seen, db: db);
  }

  Map<String, Map<String, int?>> every(Map<String, int?> counts) => {
    'compute': counts,
    'GET': counts,
    'recompute': counts,
  };

  // F1: 0088's real lines; every sentence strains the cooking liquid. TRUE:
  // the last step names the vegetables — every strain is guarded, the last
  // solids sentence read once (base: the tail rebuilt per strain, 615 s).
  // QUIET: no solids sentence — the first strain counts at once.
  for (final loud in [true, false]) {
    test(
      'STRAIN ${loud ? 'TRUE' : 'QUIET'}: 120 × 10,000-character steps of '
      '"Strain the cooking liquid." after the own steps of 0088 (its S3 '
      'strains the liquid)${loud ? ', the last ending "Add the vegetables." '
                '(every strain guarded: the onions counted)' : ' (S3 strains '
                'the onions)'}: the last solids sentence once per index',
      () async {
        const end = ' Add the vegetables.';
        final base = loadCorpusRecipe(
          '0088-slow-cooker-beer-braised-short-ribs.yaml',
        );
        final r = base.copyWith(
          steps: [
            ...base.steps,
            for (var i = base.steps.length; i < capSteps; i++)
              RecipeStep(
                number: i + 1,
                text: loud && i == capSteps - 1
                    ? '${fill('Strain the cooking liquid. ', capStep - end.length)}$end'
                    : fill('Strain the cooking liquid. ', capStep),
              ),
          ],
        );
        final onions = nutritionLines(r)[4];
        expect(
          discardedMediumOf(r, onions, normalizeItem(lineItemOf(onions))),
          loud ? isNull : DiscardedMedium.strainedSolid,
        );
        final (:seen, db: _) = await shape(
          'STRAIN',
          r,
          ['indexes', 'memo:strainAt', 'lastMatching'],
        );
        // EXACTLY: the guard's last sentence once per index; the recompute
        // of TRUE plans no strained row.
        expect(seen, {
          'compute': {'indexes': 1, 'memo:strainAt': 1, 'lastMatching': 1},
          'GET': {'indexes': 1, 'memo:strainAt': 1, 'lastMatching': 1},
          'recompute': loud
              ? {'indexes': 1, 'memo:strainAt': null, 'lastMatching': null}
              : {'indexes': 1, 'memo:strainAt': 1, 'lastMatching': 1},
        });
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  // F2: 0523's real lines (its '½ cup vegetable oil' a frying candidate);
  // 120 steps of "Reserve 2 tablespoons oil." TRUE (the reserve guard read):
  // HEATED — the last step heats the reserved oil, every reserve sentence a
  // pour-off; UNHEATED — none heats it (base: every later sentence rebuilt
  // per reserve sentence, 110 s). QUIET: "Reserve 2 tablespoons of oil."
  // (no reserve of the frying oil: the guard never read).
  for (final (name, filler, end) in const [
    (
      'RESERVE HEATED',
      'Reserve 2 tablespoons oil. ',
      ' Heat reserved oil in skillet.',
    ),
    ('RESERVE UNHEATED', 'Reserve 2 tablespoons oil. ', ''),
    ('RESERVE QUIET', 'Reserve 2 tablespoons of oil. ', ''),
  ]) {
    test('$name: 120 × 10,000-character steps of "${filler.trim()}"'
        '${end.isEmpty ? '' : ', the last ending "${end.trim()}"'} over '
        "0523's lines: the heat's last sentence once per fat", () async {
      final base = loadCorpusRecipe(
        '0523-nasi-goreng-indonesian-style-fried-rice.yaml',
      );
      final r = base.copyWith(
        subsections: const [],
        steps: [
          for (var i = 0; i < capSteps; i++)
            RecipeStep(
              number: i + 1,
              text: i == capSteps - 1
                  ? '${fill(filler, capStep - end.length)}$end'
                  : fill(filler, capStep),
            ),
        ],
      );
      final oil = nutritionLines(r).firstWhere(
        (l) => l.raw == '½ cup vegetable oil',
      );
      // The predicate's answer: HEATED keeps the reserved 2 tablespoons.
      expect(
        engineOutcome(r, oil, _oil, null).grams?.toStringAsFixed(2),
        name == 'RESERVE HEATED' ? '27.21' : isNull,
      );
      final (:seen, db: _) = await shape(name, r, [
        'indexes',
        'memo:oilOwners',
        'lastMatching',
      ]);
      // EXACTLY: the owners once per index and fat, the heat's last
      // sentence once per owners derivation (none where no sentence
      // reserves the frying oil); an UNHEATED or QUIET recompute reads no
      // owner (the oil row's plan form is the compute's).
      expect(seen, {
        'compute': {
          'indexes': 1,
          'memo:oilOwners': 1,
          'lastMatching': name == 'RESERVE QUIET' ? null : 1,
        },
        'GET': {
          'indexes': 1,
          'memo:oilOwners': 1,
          'lastMatching': name == 'RESERVE QUIET' ? null : 1,
        },
        'recompute': name == 'RESERVE HEATED'
            ? {'indexes': 1, 'memo:oilOwners': 1, 'lastMatching': 1}
            : {'indexes': 1, 'memo:oilOwners': null, 'lastMatching': null},
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // F3: 0255's real lines and steps, its plus-part oil repeated to the
  // 400-line cap, under 114 filler steps of "Toss with ¼ cup of the oil."
  // before its six (base: the rest of each step rescanned per toss sentence,
  // per line, twice — 249 s). TRUE: the real S1 drains and rinses after its
  // toss (every line's ¼ cup rinsed off). QUIET: the filler and S1 stir
  // ("Stir with ¼ cup of the oil.") — no toss: no tail read, the ¼ cup
  // counted.
  for (final (name, filler) in const [
    ('RINSE TRUE', 'Toss with ¼ cup of the oil. '),
    ('RINSE QUIET', 'Stir with ¼ cup of the oil. '),
  ]) {
    test('$name: 400 lines, 390 of them 0255\'s "3 quarts plus ¼ cup peanut '
        'oil or canola oil", under 114 × 10,000-character steps of '
        '"${filler.trim()}" and its own six: the rinse read once per amount '
        'and head, the tails once per index', () async {
      final base = loadCorpusRecipe('0255-fish-and-chips.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      final r = capped(
        base,
        [
          for (final l in own) l.raw,
          for (var i = own.length; i < 400; i++)
            '3 quarts plus ¼ cup peanut oil or canola oil',
        ],
        [
          for (var i = base.steps.length; i < capSteps; i++)
            fill(filler, capStep),
          for (final st in base.steps)
            filler.startsWith('Stir')
                ? st.text.replaceFirst('toss with ¼ cup', 'stir with ¼ cup')
                : st.text,
        ],
      );
      // The predicate's answer: TRUE rinses the ¼ cup off, QUIET counts it.
      expect(
        engineOutcome(
          r,
          nutritionLines(r).last,
          _oil,
          null,
        ).grams?.toStringAsFixed(2),
        name == 'RINSE TRUE' ? '0.00' : '54.42',
      );
      final (:seen, db: _) = await shape(name, r, [
        'indexes',
        'memo:rinsedOff',
        'memo:rinseTails',
      ]);
      // EXACTLY: the rinse once per amount and head (390 lines, one
      // derivation), the tails once per index — only where a toss is read.
      expect(
        seen,
        every({
          'indexes': 1,
          'memo:rinsedOff': 1,
          'memo:rinseTails': name == 'RINSE TRUE' ? 1 : null,
        }),
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // F9: 0672's real lines, its cauliflower group's "1 pound cauliflower
  // florets, cut into 1½-inch pieces" repeated to the cap (the critic's
  // probe at n = 389): each counted row's record read once per plan.
  test('CAULIFLOWER: 0672 with its cauliflower line 389 times — each counted '
      "row's carbohydrate read once per plan (base: once per fried "
      'cauliflower row, 161,214 reads at n = 399)', () async {
    final base = loadCorpusRecipe('0672-buffalo-cauliflower-bites.yaml');
    final group = base.ingredients[1];
    final cauli = group.items.firstWhere(
      (l) => l.raw.startsWith('1 pound cauliflower'),
    );
    final others =
        [
          for (final g in base.ingredients) ...g.items,
        ].length -
        1;
    final r = base.copyWith(
      ingredients: [
        base.ingredients[0],
        group.copyWith(
          items: [
            ...group.items.where((l) => !identical(l, cauli)),
            for (var i = others; i < 400; i++) cauli,
          ],
        ),
        ...base.ingredients.skip(2),
      ],
    );
    final (:seen, :db) = await shape('CAULIFLOWER', r, [
      'indexes',
      'plans',
      'knownFoodReads',
    ]);
    expect(nutritionLines(r), hasLength(400));
    // EXACTLY: one plan a path; the records read linear in the rows (the
    // compute reads its foods from the match's stand-ins).
    expect(seen, {
      'compute': {'indexes': 1, 'plans': 1, 'knownFoodReads': 14},
      'GET': {'indexes': 1, 'plans': 1, 'knownFoodReads': 1189},
      'recompute': {'indexes': 1, 'plans': 1, 'knownFoodReads': 792},
    });
    expect(
      {
        for (final m in db.ingredientMatchesFor(r.id))
          if (m.raw == cauli.raw) m.fdcId,
      },
      {2685573},
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  // F10: 0239's real lines and its R2-moved pork roast line (168381)
  // repeated to the cap: the matches GET's offer undoes R2 per row — once
  // per line text and record (base: no reverse; before the memo, 400 ranks,
  // the GET +75 %).
  test("LEANFAT: 0239 with its pork roast line 390 more times — R2's reverse "
      'read once per line text and record on the GET', () async {
    final base = loadCorpusRecipe('0239-maple-glazed-pork-roast.yaml');
    final own = [for (final g in base.ingredients) ...g.items];
    final roast = own[4].raw;
    expect(roast, startsWith('1 (2½-pound) boneless blade-end pork loin'));
    final r = capped(
      base,
      [
        for (final l in own) l.raw,
        for (var i = own.length; i < 400; i++) roast,
      ],
      [for (final st in base.steps) st.text],
    );
    final (:seen, :db) = await shape('LEANFAT', r, [
      'indexes',
      'leanOnlyReads',
    ]);
    expect(
      {
        for (final m in db.ingredientMatchesFor(r.id))
          if (m.raw == roast) m.fdcId,
      },
      {168381},
    );
    expect(seen, {
      'compute': {'indexes': 1, 'leanOnlyReads': null},
      // One index: the offer reaches none of the roast rows (each left on
      // 168381 by its own R2 move — `_leftOnItsRecord`).
      'GET': {'indexes': 1, 'leanOnlyReads': 1},
      'recompute': {'indexes': 1, 'leanOnlyReads': null},
    });
  }, timeout: const Timeout(Duration(minutes: 5)));

  // closer 2 (verify2 D5): the compute's carried decision — 0239's real
  // pork roast line confirmed through the real PUT (a decision on the key:
  // R2's lean-only 169194 bought) and 390 copies carried it, each moved to
  // 168381 by R2 on its own text: the moves read once per line text and
  // record (`carriedReads`; base had no carry move, the tree before the
  // memo ranked the answer 391 times: compute 255 → 795 ms) and the moved
  // food once (`knownFoodReads`: the 391 decided reads stay, as base's).
  test('DECIDED: 0239 with its pork roast line 390 more times, |4 '
      "confirmed (the key's decision) — the decision's moves once per line "
      'text and record', () async {
    final base = loadCorpusRecipe('0239-maple-glazed-pork-roast.yaml');
    final own = [for (final g in base.ingredients) ...g.items];
    final roast = own[4].raw;
    expect(roast, startsWith('1 (2½-pound) boneless blade-end pork loin'));
    final r = capped(
      base,
      [
        for (final l in own) l.raw,
        for (var i = own.length; i < 400; i++) roast,
      ],
      [for (final st in base.steps) st.text],
    );
    final (:seen, :db) = await shape(
      'DECIDED',
      r,
      ['indexes', 'carriedReads', 'leanOnlyReads', 'knownFoodReads'],
      before: (db, stored) async {
        await _put(db, _fdc(), stored.id, 4, {'confirmed': true});
        expect(
          db.decisionFor(lineKeyOf(nutritionLines(stored)[4]))?.fdcId,
          169194,
        );
        // The PUT's own round trip filled the memo: one cache write (the
        // line's answer stored again, unchanged) voids it, so the measured
        // compute reads cold.
        const query = 'boneless blade-end pork loin roast';
        db.fdcSearchCachePut(query, db.fdcSearchCacheGet(query)!);
      },
    );
    expect(
      {
        for (final m in db.ingredientMatchesFor(r.id))
          if (m.raw == roast) (m.status, m.fdcId),
      },
      {('confirmed', 168381), ('auto', 168381)},
    );
    // EXACTLY: the compute reads the moves once (the memo dropped: 391) and
    // the moved 168381 once beside the 391 decided reads and the other
    // lines' (base, the decision 168381 unmoved: 400); the GET and the
    // recompute read what base reads, the memo warm from the compute.
    expect(seen, {
      'compute': {
        'indexes': 1,
        'carriedReads': 1,
        'leanOnlyReads': null,
        'knownFoodReads': 401,
      },
      'GET': {
        'indexes': 1,
        'carriedReads': null,
        'leanOnlyReads': 1,
        'knownFoodReads': 801,
      },
      'recompute': {
        'indexes': 1,
        'carriedReads': null,
        'leanOnlyReads': null,
        'knownFoodReads': 400,
      },
    });
  }, timeout: const Timeout(Duration(minutes: 5)));

  // F8: 0149's real lines and its "1 teaspoon paprika" (a part of the coat's
  // mixture) repeated to the cap, under steps whisking the flour and the
  // paprika; every row then confirmed (the fleet's state: a person's
  // Confirm of each line, no grams typed).
  test(
    'CONFIRMED PARTS: 0149 with 390 more "1 teaspoon paprika" lines '
    'whisked into the coat, every row confirmed — one plan on the GET',
    () async {
      final base = loadCorpusRecipe('0149-easier-fried-chicken.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      final r = capped(
        base,
        [
          for (final l in own) l.raw,
          for (var i = own.length; i < 400; i++) '1 teaspoon paprika',
        ],
        [
          for (final st in base.steps) st.text,
          for (var i = base.steps.length; i < capSteps; i++)
            fill('Whisk the flour and paprika together. ', capStep),
        ],
      );
      final (:seen, :db) = await shape(
        'CONFIRMED PARTS',
        r,
        ['indexes', 'plans', 'm52Keys'],
        before: (db, stored) {
          for (final m in db.ingredientMatchesFor(stored.id)) {
            if (m.status == 'auto' && m.fdcId != null) {
              db.upsertIngredientMatch(m.copyWith(status: 'confirmed'));
            }
          }
        },
      );
      expect(
        db.ingredientMatchesFor(r.id).where((m) => m.status == 'confirmed'),
        hasLength(400),
      );
      // EXACTLY: the GET plans once (base: one plan per confirmed part) and
      // builds one key — each confirmed part keys alike in O(1) (a full key
      // per part: 395); the compute keys each derivation (its pass slot).
      expect(seen, {
        'compute': {'indexes': 1, 'plans': 3, 'm52Keys': 396},
        'GET': {'indexes': 1, 'plans': 1, 'm52Keys': 1},
        'recompute': {'indexes': 1, 'plans': 1, 'm52Keys': null},
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // closer 5 (verify5 D1): the same cap shape, the chicken |7 skipped, every
  // M52 row confirmed (H resolves each part to 0 g `discarded`), then the
  // REAL un-skip PUT — the TRUE path: each confirmed part re-derived once
  // (its food read once, the coat's mixing sentences once each — the
  // memoised `_coatOfPart`), the plan run again on the reverted rows (the
  // v70 revert's second pass); the next recompute is the compute's own
  // state, quiet. Base kept every part at 0 g (3 food reads, 1 plan) — the
  // residual is the re-derivation a compute does, count-pinned and stated
  // (API.md).
  test(
    'CONFIRMED PARTS FREED: the same shape, the chicken |7 skipped, every '
    'M52 row confirmed, then un-skipped through the real PUT — each part '
    're-derived once, the next recompute quiet',
    () async {
      final base = loadCorpusRecipe('0149-easier-fried-chicken.yaml');
      final own = [for (final g in base.ingredients) ...g.items];
      final r = capped(
        base,
        [
          for (final l in own) l.raw,
          for (var i = own.length; i < 400; i++) '1 teaspoon paprika',
        ],
        [
          for (final st in base.steps) st.text,
          for (var i = base.steps.length; i < capSteps; i++)
            fill('Whisk the flour and paprika together. ', capStep),
        ],
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      wp.saveRecipe(db, r);
      Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
      await matchAndCompute(db, provider, stored());
      await _put(db, provider, r.id, 7, {'skipped': true});
      for (final m in db.ingredientMatchesFor(r.id)) {
        if (m.status == 'auto' &&
            m.fdcId != null &&
            (m.gramSource == 'discarded' || m.hold == 'coating')) {
          db.upsertIngredientMatch(m.copyWith(status: 'confirmed'));
        }
      }
      recomputeTotals(db, stored());
      int resolved() => db
          .ingredientMatchesFor(r.id)
          .where(
            (m) =>
                m.status == 'confirmed' &&
                m.grams == 0 &&
                m.gramSource == 'discarded',
          )
          .length;
      expect(resolved(), 396);
      final seen = <String, Map<String, int?>>{};
      for (final (step, run) in <(String, Future<Object?> Function())>[
        ('PUT', () => _put(db, provider, r.id, 7, {'skipped': false})),
        ('recompute', () async => recomputeTotals(db, stored())),
      ]) {
        stepIndexCounts.clear();
        m52PlanRuns = 0;
        knownFoodReads = 0;
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        expectBounded(r, counts, 'FREED $step', copies: counts['indexes'] ?? 1);
        expect(ms, lessThan(backstopMs), reason: 'FREED $step: $counts');
        seen[step] = {
          'indexes': counts['indexes'],
          'plans': m52PlanRuns,
          'knownFoodReads': knownFoodReads,
          'mixTests': counts['mixTests'],
          'memo:mixes': counts['memo:mixes'],
          'memo:coatMixes': counts['memo:coatMixes'],
        };
      }
      // The frying oil's 0 g is the compute's too (base: 395 left at 0 g).
      expect(resolved(), 1);
      final put = _state(db, r.id);
      expect(await matchAndCompute(db, provider, stored()), isNull);
      expect(_state(db, r.id), put, reason: 'PUT == compute');
      expect(seen, {
        'PUT': {
          'indexes': 1,
          'plans': 2,
          'knownFoodReads': 797,
          'mixTests': 30775,
          'memo:mixes': 30775,
          'memo:coatMixes': 1,
        },
        'recompute': {
          'indexes': 1,
          'plans': 1,
          'knownFoodReads': 400,
          'mixTests': null,
          'memo:mixes': null,
          'memo:coatMixes': null,
        },
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
