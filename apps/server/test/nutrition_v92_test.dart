// Real corpus lines and sentences wrap across adjacent literals; the tables
// keep each one verbatim.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v92 (batch M89; matcherVersion 87 — the grilled pizza's repeat
// multiplier; prep51 design_v2 §1 Q5 option (c), ruled by the owner
// 2026-10-29; zero requests): a NEW step reader, `_repeatsOf` — a sentence
// "repeat with (the) remaining <N> <noun>" whose noun is a PIECE (never a
// unit of the shipped vocabulary, `isMeasureUnit`) and whose other words
// multiply nothing (once the phrase and a "for each <its noun>" are blanked)
// is a counted repeat: guard (ii) of `_stepAmountsAt` does not refuse it,
// and it repeats the work of its step — (2) printing no amount of the head,
// the step's earlier prints count × (1 + N); (3) printing its own, that
// print counts × (1 + N) and the step's earlier prints are left. The corpus
// reach is one line: ultimate-grilled-pizza|12 "Extra-virgin olive oil"
// (748608), 0 g → 80.47 g, 711.35 kcal — step 8's ¼ cup left, its "adding 1
// tablespoon oil … for each round" × 3, step 9's "1 tablespoon oil" × 3
// (the basis numbers the recipe's step LIST: 0398 prints two steps "6", the
// charcoal and the gas grill, so its printed 7 and 8 are list steps 8 and
// 9). Every figure is a fresh compute on the fixtures (FixtureProvider) and
// equals the v92 replay of snapshot 30 (fix92 gate1) on every pinned row
// field; the recipe's per serving reads 978.43 here, the replay 978.48 (the
// fixtures' 0.05 a serving below the replay's on the other rows, as
// nutrition_v71_test's 800.59 against the replay's 800.64 at v91). Never
// the network. Every corpus line and sentence is real; the STATED
// constructions (no corpus sentence reaches these gates — fix92's census,
// tools/repeat_sentences.tsv: 47 "repeat with (the) remaining <N> <noun>"
// sentences) are named where they stand: a number word, a weight unit, the
// two-word unit "fluid ounces", a "for each" naming another noun or the
// noun itself, a print after the repeat in its step, a non-repeat
// multiplying sentence before a repeat, a repeat naming the head in a step
// that prints none of it, a served print before a repeat
// (classic-gazpacho), and the cap shapes' repeated lines and
// steps (the house's cap-shape exception).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v26_cost_test.dart'
    show capLines, capStep, capSteps, capped, food;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _pizza = '0398-ultimate-grilled-pizza.yaml';
const _gazpacho = '0031-classic-gazpacho.yaml';
const _shortRibs = '0087-braised-beef-short-ribs.yaml';
const _philly = '0309-philly-cheesesteaks.yaml';
const _parmesan = '0419-parmesan-crusted-chicken-cutlets.yaml';
const _chips = '0610-smoky-pulled-pork-on-a-gas-grill.yaml';
const _saltimbocca = '0421-chicken-saltimbocca.yaml';
const _crab = '0289-best-crab-cakes.yaml';

/// The pizza's two repeats, as printed (list steps 8 and 9, 0-based 7, 8).
const _s7 =
    'Repeat with remaining 2 dough rounds, adding 1 tablespoon oil to baking '
    'sheet for each round and keeping grill cover closed when not in use to '
    'retain heat.';
const _s8 = 'Transfer pizza to cutting board; repeat with remaining 2 crusts.';

/// [sentence], asserted to be printed in step [step] (0-based) of [file].
String _real(String file, int step, String sentence) {
  expect(loadCorpusRecipe(file).steps[step].text, contains(sentence));
  return sentence;
}

/// A recorded record, as the engine reads it.
Future<FdcFood> _food(int fdcId) async =>
    (await FixtureProvider(pending: {...pendingSearches}).food(fdcId))!;

/// A database holding nothing, as a line weighed alone reads it.
SaltDatabase _emptyDb() {
  final dir = Directory.systemTemp.createTempSync('salt-v92-');
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

/// [recipe] with the first [from] of step [step] (0-based) written [to].
Recipe _rewrite(Recipe recipe, int step, String from, String to) {
  expect(recipe.steps[step].text, contains(from));
  return recipe.copyWith(
    steps: [
      for (final (i, s) in recipe.steps.indexed)
        i == step ? s.copyWith(text: s.text.replaceFirst(from, to)) : s,
    ],
  );
}

/// [r]'s line [position] weighed alone on 748608 (grams, basis) — null when
/// nothing is read.
Future<(String, String?)?> _weigh(Recipe r, int position) async {
  final g = lineGrams(
    _emptyDb(),
    nutritionLines(r)[position],
    await _food(748608),
    recipe: r,
  );
  return g == null ? null : (g.grams.toStringAsFixed(2), g.basis);
}

void main() {
  test('matcherVersion 87 (v92, batch M89: one row moves)', () {
    expect(matcherVersion, 87);
  });

  group('clause (1): the counted repeat on real sentences', skip: skipIfNoCorpus, () {
    test(
      'P1: the pizza\'s two repeats each count 2 — step 8 once its "for '
      'each round" is blanked (mutants: the blank dropped, or its plural '
      'test "round" + s dropped — the sentence refuses), step 9 as printed',
      () {
        expect(repeatsOfForTest(_real(_pizza, 7, _s7)), 2);
        expect(repeatsOfForTest(_real(_pizza, 8, _s8)), 2);
      },
    );

    test(
      'THE NOUN GUARD: a unit of the shipped vocabulary refuses — '
      'braised-beef-short-ribs step 1 "Repeat with the remaining 1 '
      'tablespoon oil and the remaining meat." reads none (its "the '
      'remaining meat" multiplies too, so the unit refusal dropped still '
      'reads none there); philly-cheesesteaks step 4 "Repeat with remaining '
      '1 tablespoon oil and sliced meat." none (mutant: the unit refusal '
      'dropped reads 1); parmesan-crusted-chicken-cutlets step 3 "… 2 '
      'teaspoons oil and chicken." none (mutant: the plural strip dropped '
      'reads 2); smoky-pulled-pork step 2 "… 2 cups unsoaked chips." none',
      () {
        for (final (file, step, sentence) in const [
          (
            _shortRibs,
            0,
            'Repeat with the remaining 1 tablespoon oil and the remaining meat.',
          ),
          (
            _philly,
            3,
            'Repeat with remaining 1 tablespoon oil and sliced meat.',
          ),
          (
            _parmesan,
            2,
            'Repeat with the remaining 2 teaspoons oil and chicken.',
          ),
          (_chips, 1, 'Repeat with remaining 2 cups unsoaked chips.'),
        ]) {
          expect(repeatsOfForTest(_real(file, step, sentence)), isNull);
        }
      },
    );

    test('the other words multiply: a piece-noun repeat beside "the '
        'remaining 2 tablespoons oil" refuses — chicken-saltimbocca step 3, '
        'best-crab-cakes step 6 (mutant: the residue test dropped reads 4 '
        'each)', () {
      for (final (file, step, sentence) in const [
        (
          _saltimbocca,
          2,
          'Add the remaining 2 tablespoons oil to the skillet and repeat with '
              'the remaining 4 cutlets.',
        ),
        (
          _crab,
          5,
          'Wipe out skillet and repeat with remaining 4 cakes and remaining 2 '
              'tablespoons oil.',
        ),
      ]) {
        expect(repeatsOfForTest(_real(file, step, sentence)), isNull);
      }
    });

    // STATED (fix92 census: no corpus counted repeat prints a number word
    // the vocabulary holds — the one, "five bread rounds", is no
    // `_numberWords` entry — a weight unit, or a "for each" naming another
    // noun or the noun's own singular): the pizza's step 9 sentence and
    // step 8's per-round phrase rewritten.
    test('STATED: a number word counts ("remaining two crusts" 2; mutant: '
        'the number words dropped from the pattern); a weight unit refuses '
        '("remaining 2 pounds" none; mutant: the weight units dropped from '
        '`isMeasureUnit`); "for each" another noun multiplies ("… for each '
        'batch" none; mutant: every "for each" blanked); "for each" the noun '
        'itself is the repeat\'s ("2 fish, adding … for each fish" 2; mutant: '
        'the exact-noun test dropped)', () {
      expect(
        repeatsOfForTest(_s8.replaceFirst('2 crusts', 'two crusts')),
        2,
      );
      expect(
        repeatsOfForTest(_s8.replaceFirst('2 crusts', '2 pounds dough')),
        isNull,
      );
      expect(
        repeatsOfForTest(_s7.replaceFirst('for each round', 'for each batch')),
        isNull,
      );
      expect(
        repeatsOfForTest(
          'Repeat with remaining 2 fish, adding 1 tablespoon oil for each fish.',
        ),
        2,
      );
    });

    // STATED (closer1, verify1 D1; the census: no corpus step prints
    // "repeat with (the) remaining <N> fluid …" — the vocabulary's one
    // two-word unit, `_volumeUnitMl['fluid ounce']`, reaches no corpus
    // sentence): the guard reads the two words together, so "fluid ounces"
    // refuses as "tablespoons" does (mutant: the two-word test dropped
    // reads 2 on both).
    test('STATED: a two-word unit refuses ("remaining 2 fluid ounces" '
        'none, with or without a following noun)', () {
      expect(repeatsOfForTest('Repeat with remaining 2 fluid ounces.'), isNull);
      expect(
        repeatsOfForTest('Repeat with remaining 2 fluid ounces oil.'),
        isNull,
      );
    });

    test('the corpus census: every step sentence of every recipe and '
        'section read — the counted repeats are exactly the piece-noun ones '
        'whose other words multiply nothing; the 21 recipes printing a unit '
        'there read none', () {
      final unitPattern = RegExp(
        r'\brepeat with (?:the )?remaining [\d½⅓⅔¼¾⅛]+ (?:tablespoons?|teaspoons?|cups?)\b',
      );
      final hits = <String>[];
      final unitRecipes = <String>{};
      for (final file
          in Directory(corpusRecipesDir)
              .listSync()
              .map((f) => f.uri.pathSegments.last)
              .where((f) => f.endsWith('.yaml'))
              .toList()
            ..sort()) {
        final r = loadCorpusRecipe(file);
        for (final (label, steps) in [
          (file, r.steps),
          for (final s in r.subsections)
            ('$file|${s.title}', s.steps ?? const []),
        ]) {
          for (final (k, step) in steps.indexed) {
            for (final sentence in step.text.toLowerCase().split(
              RegExp(r'(?<=\.)\s+'),
            )) {
              final n = repeatsOfForTest(sentence);
              if (n != null) {
                hits.add('$label|${k + 1}: $n');
              }
              if (unitPattern.hasMatch(sentence)) {
                expect(n, isNull, reason: '$label|${k + 1}');
                unitRecipes.add(label);
              }
            }
          }
        }
      }
      expect(unitRecipes, hasLength(21));
      expect(hits, _counted);
    });
  });

  // Clauses (2) and (3) on pizza|12 weighed alone on 748608 (as the engine
  // weighs it, [lineGrams]): 1 tablespoon = 13.41 g, ¼ cup = 53.65 g (M82's
  // 0.907 g/mL).
  group('clauses (2) and (3) on pizza|12', skip: skipIfNoCorpus, () {
    final pizza = loadCorpusRecipe(_pizza);

    test(
      'the real steps: 6 tablespoons, 80.47 g — step 8\'s "adding 1 '
      'tablespoon oil … for each round" × 3 with its ¼ cup left (clause 3), '
      'step 9\'s "Drizzle top of 1 crust with 1 tablespoon oil." × 3 '
      '(clause 2); the public reading names the two kept prints (mutants: '
      '× (1 + N) read × 1, 26.82 g; the base kept, 134.12 g; clause (2) '
      'dropped, 53.65 g; the guard-(ii) exception dropped reads nothing)',
      () async {
        final line = nutritionLines(pizza)[12];
        expect(line.raw, 'Extra-virgin olive oil');
        expect(line.amounts, isEmpty);
        _real(_pizza, 7, 'Pour ¼ cup oil onto center of rimmed baking sheet.');
        _real(_pizza, 8, 'Drizzle top of 1 crust with 1 tablespoon oil.');
        expect(stepAmountsOf(pizza, line), [
          (step: 7, amount: '1 tablespoon'),
          (step: 8, amount: '1 tablespoon'),
        ]);
        expect(await _weigh(pizza, 12), (
          '80.47',
          'from steps 8, 9: 1 tablespoon × 3 + 1 tablespoon × 3 (the ¼ cup '
              'base left; no amount on the line)',
        ));
      },
    );

    test('the negatives on the same recipe: |4 "Vegetable oil" reads step '
        '2\'s 1 tablespoon once, |11 "Sugar" step 3\'s ½ teaspoon — no '
        'repeat in either step', () {
      for (final (position, prints) in const [
        (4, [(step: 1, amount: '1 tablespoon')]),
        (11, [(step: 2, amount: '½ teaspoon')]),
      ]) {
        expect(stepAmountsOf(pizza, nutritionLines(pizza)[position]), prints);
      }
    });

    // STATED: step 9's closing sentence written with a print after the
    // repeat (no corpus step prints the head after its counted repeat).
    test(
      'STATED: a print after the repeat in its step counts once — "Cut '
      'into wedges and serve." written "Drizzle with 1 tablespoon oil, cut '
      'into wedges and serve." reads 7 tablespoons, 93.88 g (mutant: every '
      "print of the step under the step's first repeat — × 3, 120.70 g)",
      () async {
        final r = _rewrite(
          pizza,
          8,
          'Cut into wedges and serve.',
          'Drizzle with 1 tablespoon oil, cut into wedges and serve.',
        );
        expect(await _weigh(r, 12), (
          '93.88',
          'from steps 8, 9: 1 tablespoon × 3 + 1 tablespoon × 3 + 1 tablespoon '
              '(the ¼ cup base left; no amount on the line)',
        ));
      },
    );

    // STATED: step 8's pour written to multiply (no corpus counted repeat
    // follows another named multiplying sentence in its step).
    test('STATED: a multiplying sentence that is no repeat still refuses '
        'before a repeat — "Pour ¼ cup oil onto center of each rimmed baking '
        'sheet." reads nothing (mutant: the exception taken for any repeat at '
        'or after the sentence)', () {
      final r = _rewrite(
        pizza,
        7,
        'onto center of rimmed baking sheet',
        'onto center of each rimmed baking sheet',
      );
      expect(stepAmountsOf(r, nutritionLines(r)[12]), isEmpty);
    });

    // STATED: step 9 written to print no oil but name it in its repeat (no
    // corpus counted repeat names the head in a step printing none of it).
    test(
      'STATED: a repeat naming the head in a step that prints none of it '
      'refuses nothing — step 9\'s drizzle written "with oil" and its '
      'repeat "repeat with remaining 2 crusts and more oil" reads step 8 '
      "alone, 1 tablespoon × 3, 40.23 g (mutant: a multiplying sentence's "
      'step left unscanned for repeats — the repeat refuses, nothing)',
      () async {
        final r = _rewrite(
          _rewrite(
            pizza,
            8,
            'Drizzle top of 1 crust with 1 tablespoon oil.',
            'Drizzle top of 1 crust with oil.',
          ),
          8,
          'repeat with remaining 2 crusts.',
          'repeat with remaining 2 crusts and more oil.',
        );
        expect(await _weigh(r, 12), (
          '40.23',
          'from step 8: 1 tablespoon × 3 (the ¼ cup base left; no amount on the '
              'line)',
        ));
      },
    );

    // STATED: classic-gazpacho's served sentence followed by a repeat (no
    // corpus step prints both).
    test('STATED: a served print keeps its serves under a later repeat — '
        'gazpacho step 2 with "Repeat with remaining 2 bowls." appended reads '
        "about 1 teaspoon × 8 portions, 35.76 g (mutant: the repeat's count "
        'before the serves — × 3, 13.41 g)', () async {
      final r = _rewrite(
        loadCorpusRecipe(_gazpacho),
        1,
        'topping with the desired garnishes.',
        'topping with the desired garnishes. Repeat with remaining 2 bowls.',
      );
      final line = nutritionLines(r)[10];
      expect(line.raw, 'Extra-virgin olive oil, for serving');
      expect(await _weigh(r, 10), (
        '35.76',
        'from step 2: about 1 teaspoon × 8 portions (no amount on the line)',
      ));
    });
  });

  group('matcher v92 (batch M89) — whole recipes', skip: skipIfNoCorpus, () {
    late SaltDatabase db;
    late FixtureProvider fdc;
    final recipes = <String, Recipe>{};

    setUpAll(() async {
      fdc = FixtureProvider(pending: {...pendingSearches});
      final dir = Directory.systemTemp.createTempSync('salt-v92-');
      db = SaltDatabase.open(
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
      for (final file in {_pizza, for (final n in _negatives) n.$1}) {
        recipes[file] = await _compute(db, fdc, loadCorpusRecipe(file));
      }
    });

    IngredientMatchRow rowAt(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    test('P1: pizza|12 on 748608, `portion`, 80.47 g, 711.35 kcal (v91: 0.00 '
        'g `unmeasured`), its basis naming both repeats; |4 and |11 as at '
        'v91; the recipe 978.43 a serving (v91 here 800.59; the replay 800.64 '
        '→ 978.48)', () {
      final recipe = recipes[_pizza]!;
      for (final (position, fdcId, source, grams, kcal, basis) in const [
        (
          12,
          748608,
          'portion',
          '80.47',
          '711.35',
          'from steps 8, 9: 1 tablespoon × 3 + 1 tablespoon × 3 (the ¼ cup '
              'base left; no amount on the line) · nutrients of "Oil, olive, '
              'salad or cooking"',
        ),
        (
          4,
          2710180,
          'portion',
          '14.00',
          '126.00',
          'from step 2: 1 tablespoon (no amount on the line)',
        ),
        (
          11,
          746784,
          'portion',
          '2.00',
          '7.70',
          'from step 3: ½ teaspoon (no amount on the line)',
        ),
      ]) {
        final row = rowAt(recipe.id, position);
        final line = nutritionLines(recipe)[position];
        final reason = 'pizza|$position';
        expect(
          (row.fdcId, row.status, row.hold, row.gramSource),
          (fdcId, 'auto', null, source),
          reason: reason,
        );
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        final food = knownFood(db, nutrientSiblings[fdcId] ?? fdcId)!;
        expect(
          (kcalPer100g(food) * row.grams! / 100).toStringAsFixed(2),
          kcal,
          reason: reason,
        );
        expect(gramBasisFor(db, line, row, recipe: recipe), basis);
      }
      final n = db.nutritionFor(recipe.id)!;
      expect(
        (n.status, n.caloriesPerServing?.toStringAsFixed(2), n.totalGrams),
        ('complete', '978.43', 1332.1),
      );
    });

    test('the five guard-(ii) rows pB named stay 0 g (the v91 rows): '
        'flavourings and lines whose steps print another food', () {
      for (final (file, position, raw, fdcId, status, basis) in _negatives) {
        final recipe = recipes[file]!;
        final row = rowAt(recipe.id, position);
        final line = nutritionLines(recipe)[position];
        expect(line.raw, raw, reason: file);
        expect(
          (row.fdcId, row.status, row.grams?.toStringAsFixed(2)),
          (fdcId, status, '0.00'),
          reason: file,
        );
        expect(stepAmountsOf(recipe, line), isEmpty, reason: file);
        expect(gramBasisFor(db, line, row, recipe: recipe), basis);
      }
    });

    test('a second compute writes nothing: every row and total as the first '
        'compute left it', () async {
      for (final file in recipes.keys) {
        final id = recipes[file]!.id;
        List<Object?> rowsOf() => [
          for (final m in db.ingredientMatchesFor(id))
            (m.position, m.fdcId, m.grams, m.gramSource, m.status, m.hold),
        ];
        final rows = rowsOf();
        final totals = db.nutritionFor(id)!.totalsJson;
        expect(
          await matchAndCompute(db, fdc, db.recipeByIdOrSlug(id)!.recipe),
          isNull,
        );
        expect(rowsOf(), rows, reason: file);
        expect(db.nutritionFor(id)!.totalsJson, totals, reason: file);
        expect(
          nutritionIsFresh(
            db,
            db.recipeByIdOrSlug(id)!.recipe,
            db.nutritionFor(id),
          ),
          isTrue,
          reason: file,
        );
      }
    });
  });

  // RULE C, the repeat reader at the caps, at the loop level (every line's
  // stepAmountsOf and lineGrams on no record, as nutrition_v85_test's B1a
  // shapes read theirs). Synthesized, a stated exception: the repeated
  // lines and the steps. On 0398's recipe: 400 amount-less lines of 400
  // distinct heads (nutrition_v26_cost_test's `food`) under 120 steps of
  // 10,000 characters of the pizza's own step 9 pair, "Drizzle top of 1
  // crust with 1 tablespoon <head>. Transfer pizza to cutting board; repeat
  // with remaining 2 <noun>." — TRUE (noun "crusts": a piece, every print ×
  // 3) and QUIET (noun "tablespoons": the unit guard refuses every repeat,
  // the prints read × 1 as at v91). The reader's work: `_repeatsOf` once per
  // sentence of a step holding a print, inside `memo:stepAmounts` (once per
  // index); the counted repeats counted (`repeats`, TRUE only). Counts: each
  // shape's map exactly (the process-wide `names` aside), measured on the
  // tree; base a43ba1e's maps equal them but for TRUE's `repeats`. Clocks:
  // fix92 cost_base / cost_tip (two runs each, base → tree) in fix.md; each
  // under the backstop.
  group('RULE C, the repeat reader at the caps', skip: skipIfNoCorpus, () {
    Recipe shape(String noun) {
      final base = loadCorpusRecipe(_pizza);
      final heads = [for (var i = 0; i < capLines; i++) food(i)];
      String step(int k) {
        final s = StringBuffer();
        var i = k * 37 % capLines;
        while (true) {
          final t =
              'Drizzle top of 1 crust with 1 tablespoon ${heads[i]}. Transfer '
              'pizza to cutting board; repeat with remaining 2 $noun. ';
          if (s.length + t.length > capStep) {
            break;
          }
          s.write(t);
          i = (i + 1) % capLines;
        }
        return s.toString();
      }

      return capped(base, heads, [for (var k = 0; k < capSteps; k++) step(k)]);
    }

    for (final (name, noun, times, grams) in const [
      ('TRUE', 'crusts', ' × 3', '925.40'),
      ('QUIET', 'tablespoons', '', '308.47'),
    ]) {
      test(
        '$name: 400 lines read, the counts exact, within the backstop',
        () async {
          final db = _emptyDb();
          final r = shape(noun);
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          var reads = 0;
          for (final line in nutritionLines(r)) {
            if (stepAmountsOf(r, line).isNotEmpty) {
              reads++;
            }
            lineGrams(db, line, null, recipe: r);
          }
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts)..remove('names');
          expectBounded(r, counts, name);
          expect(reads, capLines, reason: name);
          expect(counts, _capCounts[name], reason: name);
          expect(ms, lessThan(backstopMs), reason: name);
          // Not vacuous: the first line weighed on 748608 reads each print
          // × 3 under TRUE, × 1 under QUIET.
          final g = lineGrams(
            db,
            nutritionLines(r).first,
            await _food(748608),
            recipe: r,
          );
          // Its 23 prints in 23 of the 120 steps, 1 tablespoon each (13.41 g).
          expect(g!.grams.toStringAsFixed(2), grams, reason: name);
          expect(
            g.basis,
            'from steps 1, 10, 11, 21, 22, 32, 33, 43, 44, 54, 55, 64, 65, 75, 76, '
            '86, 87, 97, 98, 108, 109, 118, 119: '
            '${List.filled(8, '1 tablespoon$times').join(' + ')} + … (23 in '
            'all) (no amount on the line)',
            reason: name,
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  });
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
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

/// pB B1's five guard-(ii) rows beside pizza|12 and classic-gazpacho|10
/// (pB_tools/b1_reach.tsv): flavourings (0 kcal by rule) and lines whose
/// steps print another food — file, position, raw, record, status, basis
/// (the v91 rows).
const List<(String, int, String, int?, String, String)> _negatives = [
  (
    '0129-indoor-pulled-chicken.yaml',
    8,
    'Hot sauce',
    2710093,
    'auto',
    'no amount on the line — counted as 0 g',
  ),
  (
    '0246-indoor-pulled-pork-with-sweet-and-tangy-barbecue-sauce.yaml',
    2,
    '3 tablespoons plus 2 teaspoons liquid smoke',
    null,
    'confirmed',
    'flavouring, no nutrients — counted as 0 g',
  ),
  (
    '0664-bread-and-butter-pickles.yaml',
    11,
    '½ teaspoon Ball Pickle Crisp',
    null,
    'confirmed',
    'flavouring, no nutrients — counted as 0 g',
  ),
  (
    '0896-torta-caprese.yaml',
    8,
    'Confectioners’ sugar (optional)',
    169656,
    'auto',
    'no amount on the line — counted as 0 g',
  ),
  (
    '1201-rainbow-cake.yaml',
    8,
    'Gel food dye (red, orange, yellow, green, blue, and purple)',
    null,
    'confirmed',
    'flavouring, no nutrients — counted as 0 g',
  ),
];

/// The corpus's counted repeats ("<file>(|<section>)|<step>: N"): 22
/// sentences in 20 recipes, none in a section — every piece-noun repeat of
/// fix92's census whose other words multiply nothing (pizza step 8's once
/// its "for each round" is blanked). Only pizza|12 is an amount-less line a
/// step of these prints (the replay's one row).
const List<String> _counted = [
  '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml|2: 6',
  '0189-pan-seared-thick-cut-steaks.yaml|2: 2',
  '0198-crispy-pan-fried-pork-chops.yaml|2: 7',
  '0201-pan-seared-thick-cut-pork-chops.yaml|3: 2',
  '0201-pan-seared-thick-cut-pork-chops.yaml|4: 2',
  '0206-crunchy-baked-pork-chops.yaml|4: 3',
  '0254-crunchy-oven-fried-fish.yaml|3: 3',
  '0299-grown-up-grilled-cheese-sandwiches-with-cheddar-and-shallot.yaml|3: 2',
  '0311-smashed-burgers.yaml|3: 2',
  '0314-black-bean-burgers.yaml|5: 3',
  '0396-grilled-tomato-and-cheese-pizza.yaml|8: 2',
  '0398-ultimate-grilled-pizza.yaml|8: 2',
  '0398-ultimate-grilled-pizza.yaml|9: 2',
  '0455-chicken-provencal.yaml|1: 4',
  '0499-huevos-rancheros.yaml|3: 3',
  '0727-perfect-fried-eggs.yaml|1: 2',
  '0729-shakshuka-eggs-in-spicy-tomato-and-roasted-red-pepper-sauce.yaml|3: 7',
  '0810-new-york-bagels.yaml|7: 4',
  '0820-chocolate-chip-cookie-ice-cream-sandwiches.yaml|5: 8',
  '1099-spanish-migas-with-fried-eggs.yaml|1: 3',
  '1101-pupusas-with-quick-salsa-and-curtido.yaml|6: 4',
  '1147-fresh-bulk-sausage.yaml|5: 3',
];

/// Each cap shape's counts on the tree (fix92 cost_tip, the second run; the
/// process-wide `names` aside).
const Map<String, Map<String, int>> _capCounts = {
  'TRUE': {
    'heads': 1,
    'indexes': 1,
    'memo:stepAmountsAt': 400,
    'memo:labelScope': 1,
    'memo:stepAmounts': 1,
    'lower': 1,
    'sentences': 19530,
    'words': 184395,
    'memo:naming': 12,
    'memo:namingAll': 1,
    'memo:named': 388,
    'stepPrints': 9705,
    'repeats': 9705,
    'stepPrintsWalked': 9705,
    'memo:stepAmountGrams': 400,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
  'QUIET': {
    'heads': 1,
    'indexes': 1,
    'memo:stepAmountsAt': 400,
    'memo:labelScope': 1,
    'memo:stepAmounts': 1,
    'lower': 1,
    'sentences': 18770,
    'words': 177175,
    'memo:naming': 12,
    'memo:namingAll': 1,
    'memo:named': 388,
    'stepPrints': 9325,
    'stepPrintsWalked': 9325,
    'memo:stepAmountGrams': 400,
    'memo:skinSentences': 1,
    'allSentences': 1,
  },
};
