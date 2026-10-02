// Run 055 I3 (matcher v25, RULE C): a detector costs O(total text) per
// recipe, END TO END — every line, every detector a compute and a matches
// GET read — never per regex. Real corpus recipes (0000 Garlic and Olive
// Oil Mashed Potatoes, 0129 Mahogany Chicken Thighs, 0491 Spicy Mexican
// Shredded Pork Tostadas, 1133 Chicken Francese), recorded FDC answers
// (FixtureProvider), never the network. Synthesized, a stated exception:
// the hostile step text and lines appended to them (negative-path inputs
// no corpus recipe holds — S4, O2, O3, O9, S6, S7, S16, S18 — each within
// the editor's caps: 120 steps of 10,000 characters, 1,000-character
// lines). Each time pin's bound is generous (the v24 cost of each shape is
// stated beside it); a COUNT pin beside it says the work was done once.
// ignore_for_file: lines_longer_than_80_chars
import 'package:logging/logging.dart';
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

/// Every detector a compute and a matches GET read, over every line of [r]
/// (the medium, the hold, the kept liquid, both notes).
void readAll(Recipe r) {
  for (final line in nutritionLines(r)) {
    final eaten = weighedLine(r, line);
    discardedMediumOf(r, eaten, normalizeItem(lineItemOf(eaten)));
    heldMediumLine(r, eaten);
    keptLiquidOf(r, line);
    holdNoteOf(r, line, 'coating');
    holdNoteOf(r, line, 'partial_pour_away');
  }
}

/// Milliseconds [readAll] takes on a FRESH Recipe each run — the per-recipe
/// index cold, as a first compute or GET meets it — the best of three.
int msCold(Recipe Function() make) {
  var best = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final r = make();
    final sw = Stopwatch()..start();
    readAll(r);
    best = sw.elapsedMilliseconds < best ? sw.elapsedMilliseconds : best;
  }
  return best;
}

/// [recipe] with [texts] as more steps.
Recipe withSteps(Recipe recipe, List<String> texts) => recipe.copyWith(
  steps: [
    ...recipe.steps,
    for (final (i, text) in texts.indexed)
      RecipeStep(number: recipe.steps.length + i + 1, text: text),
  ],
);

/// [unit] repeated to at most [n] characters.
String fill(String unit, int n) => unit * (n ~/ unit.length);

/// The counts of one [readAll] of a fresh [make].
Map<String, int> countsOf(Recipe Function() make) {
  final r = make();
  stepIndexCounts.clear();
  readAll(r);
  return Map.of(stepIndexCounts);
}

/// The salt mentions of [texts] as `_ownMentions` locates them.
int saltMentions(Iterable<String> texts) => texts
    .map(
      (t) => RegExp(r'\bsalt\b(?!\s+pork)').allMatches(t.toLowerCase()).length,
    )
    .fold(0, (a, b) => a + b);

const potatoes = '0000-garlic-and-olive-oil-mashed-potatoes.yaml';

void main() {
  // Needs no corpus file (Run 055 V5: CI runs it).
  group('RULE C, corpus-free', () {
    test('normalizeItem is linear: a 2,000-character number run and 2,000 '
        "unclosed '(' (S6: the run re-walked from each of its words, 28 ms; "
        'the lazy paren run re-read from each "(", 23 ms at v24)', () {
      for (final item in ['1 ' * 1000, '(' * 2000, '1/2 ' * 500]) {
        normalizeItem(item);
        final sw = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          normalizeItem(item);
        }
        expect(sw.elapsedMicroseconds / 5, lessThan(5000), reason: item);
      }
    });
  });

  group('RULE C (Run 055 I3): every detector of every line, end to end, on '
      'a hostile recipe', () {
    test("a salt line on 40 legal 10,000-character steps of 'Rub … with salt "
        "and sugar' after a rinse (S4: 39 s at v24 — the later steps re-split "
        'per rub sentence): under 200 ms, no cure; the steps indexed and the mentions '
        'located once for the whole recipe', () {
      final base = loadCorpusRecipe(potatoes);
      final rub = fill('Rub the potatoes with salt and sugar. ', 10000);
      Recipe make() =>
          withSteps(base, ['Rinse the potatoes.', ...List.filled(40, rub)]);
      final r = make();
      final salt = nutritionLines(r).firstWhere((l) => l.raw.contains('salt'));
      expect(
        discardedMediumOf(r, salt, normalizeItem(lineItemOf(salt))),
        isNull,
      );
      expect(msCold(make), lessThan(200));
      final counts = countsOf(make);
      final texts = make().steps.map((s) => s.text);
      expect(counts['indexes'], 1);
      expect(
        counts['sentences'],
        texts
            .map((t) => t.split(RegExp(r'(?<=\.)\s+')).length)
            .reduce((a, b) => a + b),
      );
      expect(counts['mentions'], saltMentions(texts));
    });

    test('10 legal steps of ten 997-character sentences naming water, a '
        'boil, a whisk, a submerge, a colander and 189 salts each (1,890 '
        'mentions a step, inside the window): under 200 ms — a mention finds its '
        'sentence and every match after it by binary search (O2/O9/S18: two '
        'regex scans of the step, a lower-casing and a re-split per mention, '
        '3.7 s on ONE such step at v24)', () {
      final base = loadCorpusRecipe(potatoes);
      final sentence =
          'Bring water to a boil, whisk, submerge in a colander, ${'salt ' * 188}salt.';
      expect(sentence.length, lessThanOrEqualTo(maxScannedSentence));
      final step = List.filled(10, sentence).join(' ');
      expect(step.length, lessThanOrEqualTo(10000));
      // 18,900 mentions: linear, ~1 µs a mention a detector pass.
      Recipe make() => withSteps(base, List.filled(10, step));
      expect(msCold(make), lessThan(200));
      final counts = countsOf(make);
      expect(counts['indexes'], 1);
      expect(counts['mentions'], saltMentions(make().steps.map((s) => s.text)));
      expect(counts['mentions'], greaterThanOrEqualTo(10 * 1890));
    });

    test('a salt mention in each of 450 sentences before 8 legal steps of '
        "'Drain the xyz.' (O3: every later step re-scanned per mention, "
        '1.5 s at v24): under 200 ms; the later drains read once', () {
      final base = loadCorpusRecipe(potatoes);
      Recipe make() => withSteps(base, [
        'Bring 4 quarts water to boil. ${'Add 2 teaspoons salt. ' * 450}',
        'Stir.',
        ...List.filled(8, 'Drain the xyz. ' * 660),
      ]);
      expect(msCold(make), lessThan(200));
      final counts = countsOf(make);
      expect(counts['drained'], 1);
      expect(counts['indexes'], 1);
    });

    test('450 salt mentions in cooking water before a step lifting the food '
        'out with a slotted spoon: whether that step lifts from the water is '
        'read once (Run 055 C12: the `_lifted` memo, re-read per mention, '
        'could be deleted with every test green)', () {
      final base = loadCorpusRecipe(potatoes);
      Recipe make() => withSteps(base, [
        'Bring 4 quarts water to boil. ${'Add 2 teaspoons salt. ' * 450}',
        'Lift the potatoes from the water with a slotted spoon.',
      ]);
      final counts = countsOf(make);
      expect(counts['mentions'], greaterThanOrEqualTo(450));
      expect(counts['lifted'], 1);
    });

    test(
      "10 legal steps of 600 short 'Whisk the salt.' sentences (6,000 "
      'mixing mentions, each its own sentence): under 200 ms — what each '
      'later sentence does is read once per step, never re-read per '
      'mention (S4/O9: the rest of the step re-split per mention at v24)',
      () {
        final base = loadCorpusRecipe(potatoes);
        final step = 'Whisk the salt. ' * 600;
        expect(step.length, lessThanOrEqualTo(10000));
        Recipe make() => withSteps(base, List.filled(10, step));
        expect(msCold(make), lessThan(200));
        expect(countsOf(make)['mentions'], greaterThanOrEqualTo(6000));
      },
    );

    test('a period-free 10,000-character step with 2,000 salt mentions (S4 '
        'shape B, S18: 3–6 s at v24) is read for its first 1,000 characters '
        '— the rest ignored, and a log line says so: under 200 ms, and only '
        "the window's mentions located", () {
      final base = loadCorpusRecipe(potatoes);
      final step = 'salt ' * 2000;
      expect(step.length, 10000);
      Recipe make() => withSteps(base, [step]);
      final logs = <String>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen((r) => logs.add(r.message));
      addTearDown(sub.cancel);
      expect(msCold(make), lessThan(200));
      final counts = countsOf(make);
      expect(
        counts['mentions'],
        saltMentions([
          ...base.steps.map((s) => s.text),
          step.substring(0, maxScannedSentence),
        ]),
      );
      expect(
        logs,
        contains(
          'recipe ${base.id}: step ${base.steps.length + 1} has a sentence '
          'over 1000 characters; the nutrition rules read its first 1000',
        ),
      );
    });

    test('a sentence past the window is READ for its first 1,000 characters '
        '(S7: v24 read it as none, so a step typed without full stops lost '
        "every step rule): 1133's eaten flour named inside an over-long "
        'sentence is still its eaten part', () {
      final r = loadCorpusRecipe('1133-chicken-francese.yaml');
      final flour = nutritionLines(
        r,
      ).firstWhere((l) => l.raw.contains('flour, divided'));
      final long = r.copyWith(
        steps: [
          for (final s in r.steps)
            s.copyWith(
              text: s.text.replaceAll(
                '1 teaspoon flour',
                '1 teaspoon flour ${'x' * maxScannedSentence}',
              ),
            ),
        ],
      );
      expect(long.steps, isNot(r.steps));
      expect(holdNoteOf(r, flour, 'coating'), contains('1 teaspoon flour'));
      expect(holdNoteOf(long, flour, 'coating'), contains('1 teaspoon flour'));
    });

    test("keptLiquidOf's bounded amount run is READ on hostile sentences: 20 "
        'legal steps of ten 997-character number sentences naming the liquid '
        "between 0129's strain and its kept liquid (S16: the v24 pin put "
        'them after the kept sentence, so the bound never ran): under 200 '
        'ms, the kept liquid '
        'unchanged', () {
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      final line = nutritionLines(r)[1];
      // Each names the liquid, so the kept-liquid run reads all of it.
      final hostile = List.filled(10, '${'1 ' * 494}1 liquid.').join(' ');
      expect(hostile.length, lessThanOrEqualTo(10000));
      Recipe make() => r.copyWith(
        steps: [
          ...r.steps.take(3),
          for (var i = 0; i < 20; i++) RecipeStep(number: 4 + i, text: hostile),
          ...r.steps.skip(3),
        ],
      );
      expect(keptLiquidOf(r, line), '1 cup defatted cooking liquid');
      expect(keptLiquidOf(make(), line), '1 cup defatted cooking liquid');
      expect(msCold(make), lessThan(200));
    });

    test('40 oil lines of a cup in 0491 on 40 legal steps of frying '
        'sentences naming the oil (S5: every oil line re-split and re-read '
        'every step at v24): under 200 ms, each copy of its ¾ cup still '
        'frying oil', () {
      final base = loadCorpusRecipe(
        '0491-spicy-mexican-shredded-pork-tostadas.yaml',
      );
      final oil = nutritionLines(
        base,
      ).firstWhere((l) => l.raw.contains('vegetable oil'));
      final fry = fill(
        'Heat the oil to 350 degrees and fry the tortillas. ',
        10000,
      );
      Recipe make() => withSteps(
        base.copyWith(
          ingredients: [
            ...base.ingredients,
            IngredientGroup(items: List.filled(40, oil)),
          ],
        ),
        List.filled(40, fry),
      );
      final r = make();
      expect(
        nutritionLines(r).where(
          (l) =>
              discardedMediumOf(r, l, normalizeItem(lineItemOf(l))) ==
              DiscardedMedium.fryingOil,
        ),
        hasLength(41),
      );
      expect(msCold(make), lessThan(200));
    });

    test('a second read of the same recipe derives nothing again: the step '
        'index, the heads, the cheese test, the mentions and the later '
        'drains are memoised per Recipe instance (Run 055 S16: each memo '
        'could be deleted with every test green)', () {
      final r = withSteps(loadCorpusRecipe(potatoes), [
        'Bring 4 quarts water to boil. Add 2 teaspoons salt.',
        'Stir.',
        'Drain the potatoes.',
      ]);
      stepIndexCounts.clear();
      readAll(r);
      final first = Map.of(stepIndexCounts);
      expect(first['indexes'], 1);
      expect(first['heads'], 1);
      expect(first['drained'], 1);
      expect(first['mentions'], greaterThan(0));
      // One list per salt line and reading (in cooking water or not).
      expect(first['lineMentions'], lessThanOrEqualTo(2));
      readAll(r);
      expect(stepIndexCounts, first);
    });
  }, skip: skipIfNoCorpus);

  group('RULE C through the full compute and the matches GET', () {
    test('ten legal 1,000-character lines through the full compute (S6: ~140 '
        'ms a pass per line at v24, ~10 passes): the steps indexed and split '
        'once, the line keyed once (a 2,000 ms backstop beside the '
        "recipe's own compute)", () async {
      final base = loadCorpusRecipe(potatoes);
      final raw = '1 cup flour plus ${'1 ' * 491}';
      final item = 'flour plus ${'1 ' * 244}';
      expect(raw.length, lessThanOrEqualTo(1000));
      final hostile = base.copyWith(
        ingredients: [
          ...base.ingredients,
          IngredientGroup(
            items: [
              for (var i = 0; i < 10; i++)
                IngredientLine(
                  raw: raw,
                  item: item,
                  amounts: const [
                    Amount(
                      measure: Measure.volume,
                      quantity: '1',
                      unit: 'cup',
                      primary: true,
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      final provider = _NoHitsFor(normalizeItem(item));
      Future<(int, Map<String, int>, int)> computeMs(Recipe r) async {
        final db = wp.tempDb();
        wp.saveRecipe(db, r);
        stepIndexCounts.clear();
        keyReads = 0;
        final sw = Stopwatch()..start();
        await matchAndCompute(db, provider, r);
        return (sw.elapsedMilliseconds, Map.of(stepIndexCounts), keyReads);
      }

      await computeMs(base); // warm
      final (plain, _, _) = await computeMs(base);
      final (ms, counts, keys) = await computeMs(hostile);
      // The counts say the work was done once (Run 055 V6: the 200 ms bound,
      // 97 ms idle, failed under load); the clock is a generous backstop.
      expect(counts['indexes'], 1);
      expect(
        counts['sentences'],
        hostile.steps
            .map((s) => s.text.split(RegExp(r'(?<=\.)\s+')).length)
            .reduce((a, b) => a + b),
      );
      expect(counts['heads'], 1);
      expect(keys, lessThanOrEqualTo(1), reason: 'one new text, keyed once');
      expect(
        ms - plain,
        lessThan(2000),
        reason: 'plain $plain ms, hostile $ms ms',
      );
    });

    test(
      "0491 Tostadas' matches GET (the busiest of snapshot 13): under 200 "
      'ms on a fresh recipe instance, its steps indexed once per instance',
      () async {
        const file = '0491-spicy-mexican-shredded-pork-tostadas.yaml';
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe(file);
        wp.saveRecipe(db, r);
        await matchAndCompute(db, provider, r);
        var best = 1 << 30;
        for (var i = 0; i < 3; i++) {
          final fresh = loadCorpusRecipe(file);
          stepIndexCounts.clear();
          reachDecodes = 0;
          final sw = Stopwatch()..start();
          await matchesBody(db, provider, fresh);
          best = sw.elapsedMilliseconds < best ? sw.elapsedMilliseconds : best;
          // Its own steps once, and once more for each recipe the reach
          // decodes (0491 itself, read back from the database, on the first
          // GET only: the reach caches holds by content hash).
          expect(stepIndexCounts['indexes'], 1 + reachDecodes);
          expect(reachDecodes, i == 0 ? 1 : 0);
        }
        expect(best, lessThan(200));
      },
    );

    test('V1: the matches GET is linear in same-key lines — 0241 '
        'Garlic-Studded Roast Pork Loin plus 160 identical legal '
        '1,000-character lines (16 s before: each line re-read every '
        "same-key row's text), naming a second food or not, and 40 distinct "
        "ones: under 500 ms, each text read and keyed once, each key's "
        'reach read once, and every line reaching each OTHER same-key '
        'line', () async {
      final base = loadCorpusRecipe('0241-garlic-studded-roast-pork-loin.yaml');
      for (final (second, n, distinct) in const [
        (true, 160, false),
        (false, 160, false),
        (true, 40, true),
        (false, 40, true),
      ]) {
        final shape = 'second $second, $n, distinct $distinct';
        final lead = second ? '1 cup flour plus ' : '1 cup flour ';
        final item = second
            ? 'flour plus ${'1 ' * 244}'
            : 'flour ${'1 ' * 244}';
        final hostile = base.copyWith(
          ingredients: [
            ...base.ingredients,
            IngredientGroup(
              items: [
                for (var i = 0; i < n; i++)
                  IngredientLine(
                    raw: '$lead${'1 ' * 488}${distinct ? i : 0}',
                    item: item,
                    amounts: const [
                      Amount(
                        measure: Measure.volume,
                        quantity: '1',
                        unit: 'cup',
                        primary: true,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
        final lines = nutritionLines(hostile);
        expect(lines.last.raw.length, lessThanOrEqualTo(1000));
        expect(namesSecondFood(lines.last.raw), second, reason: shape);
        final db = wp.tempDb();
        wp.saveRecipe(db, hostile);
        final provider = _NoHitsFor(normalizeItem(item));
        await matchAndCompute(db, provider, hostile);
        secondFoodReads = 0;
        reachScans = 0;
        keyReads = 0;
        plusPartReads = 0;
        final sw = Stopwatch()..start();
        final body = await matchesBody(db, provider, hostile);
        final ms = sw.elapsedMilliseconds;
        final texts = {for (final l in lines) l.raw}.length;
        final items = (body['items']! as List).cast<Map<String, Object?>>();
        // A reach per key and food (its row's), never per line.
        final reaches = {
          for (final (i, l) in lines.indexed)
            (lineKeyOf(l), (items[i]['match'] as Map?)?['fdc_id']),
        }.length;
        expect(secondFoodReads, lessThanOrEqualTo(texts), reason: shape);
        expect(plusPartReads, lessThanOrEqualTo(texts), reason: shape);
        // A text keyed as a line and as a stored row's own text.
        expect(keyReads, lessThanOrEqualTo(2 * texts), reason: shape);
        expect(reachScans, lessThanOrEqualTo(reaches), reason: shape);
        for (final it in items.skip(lines.length - n)) {
          expect(
            (it['others'], it['others_lines']),
            second ? (0, 0) : (1, n - 1),
            reason: shape,
          );
        }
        expect(ms, lessThan(500), reason: shape);
      }
    });
  }, skip: skipIfNoCorpus);
}

/// The recorded answers, and no hits for the one synthesized [query] (a
/// stated exception: a hostile line FDC was never asked about).
class _NoHitsFor extends FixtureProvider {
  _NoHitsFor(this.query) : super(pending: pendingSearches);

  final String query;

  @override
  Future<List<FdcCandidate>> search(String q) async =>
      q == query ? const [] : super.search(q);
}
