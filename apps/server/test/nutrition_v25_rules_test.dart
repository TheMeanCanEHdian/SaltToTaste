// Matcher v25 (Run 055 I2, I4, I6): RULE B — a text rule reads a sentence
// that belongs to THIS line — on the oil rule; the `_asPrepared` head and
// the plus part's cheese form; the unpinned guards the pin-vacuity lenses
// found. Real corpus recipes throughout. Synthesized, each a stated
// exception (no corpus line or step says it): the typed steps and retyped
// lines below — a member- or admin-typed recipe is what Run 055 reached
// (S1 "bake at 375 degrees" on 0806, S2's aioli on 0690, O1's retyped
// oils on 0357/0491/1193, S3's negated and spaced "fry" forms on 0024,
// S11's "for deep-frying" oil on 0806, S12's quarter cups).

import 'dart:math' show min;

import 'package:logging/logging.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/layout_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v23_writepath_test.dart' as v23 show downgrade, fileDb;
import 'nutrition_writepath_test.dart' as wp;

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// [r] with the line [raw] retyped [to], parsed as the editor does.
Recipe _retyped(Recipe r, String raw, String to) => r.copyWith(
  ingredients: [
    for (final g in r.ingredients)
      g.copyWith(
        items: [
          for (final l in g.items)
            if (l.raw != raw)
              l
            else
              IngredientLine(
                raw: to,
                item: parseIngredientLine(to).item,
                amounts: parseIngredientLine(to).amounts,
              ),
        ],
      ),
  ],
);

/// [r] with a step [text] appended.
Recipe _plusStep(Recipe r, String text) => r.copyWith(
  steps: [
    ...r.steps,
    r.steps.last.copyWith(text: text),
  ],
);

/// [r] with every step's text passed through [edit].
Recipe _steps(Recipe r, String Function(String) edit) => r.copyWith(
  steps: [for (final s in r.steps) s.copyWith(text: edit(s.text))],
);

IngredientLine _line(Recipe r, String raw) =>
    nutritionLines(r).firstWhere((l) => l.raw == raw);

DiscardedMedium? _medium(Recipe r, String raw, {double? grams}) {
  final line = _line(r, raw);
  return discardedMediumOf(
    r,
    line,
    normalizeItem(lineItemOf(line)),
    grams: grams,
  );
}

/// What the engine writes for [raw] matched to [food] (auto, picked).
({double? grams, String? source, String? hold, String? note}) _out(
  Recipe r,
  String raw,
  FdcFood food,
) {
  final line = _line(r, raw);
  final o = engineOutcome(
    r,
    line,
    food,
    resolveGrams(
      amounts: line.amounts,
      food: food,
      normalizedItem: normalizeItem(lineItemOf(line)),
      raw: line.raw,
    ),
    picked: true,
  );
  return (
    grams: o.grams,
    source: o.source,
    hold: o.hold,
    note: holdNoteOf(r, line, o.hold),
  );
}

const _tempeh = '1193-crispy-tempeh-with-sambal-sauce.yaml';
const _bravas = '0690-patatas-bravas.yaml';
const _pita = '0806-pita-bread.yaml';

void main() {
  late FdcFood oil;
  setUpAll(() async => oil = (await FixtureProvider().food(2710180))!);
  _i4();
  _i6Backfill();
  _o12();
  _ruleBCost();

  group('RULE B (Run 055 I2): the oil rule belongs to the line', () {
    test("S1: an oven's 3xx degrees is not the oil's — 0806 Pita Bread's ¼ "
        'cup olive oil beside a typed "Brush the pitas with the oil and bake '
        'at 375 degrees" (or "heat the oven to 375 degrees") counts 56 g, '
        'and the recipe does not fry', () {
      for (final typed in const [
        'Brush the pitas with the oil and bake at 375 degrees until golden.',
        'Brush the pitas with the oil; heat the oven to 375 degrees.',
        'Toss the pitas with the oil and roast them to 375 degrees.',
        'Toss the pitas with the oil and air-fry them at 375 degrees.',
        'Brush the pitas with the oil and grill at 375 degrees.',
      ]) {
        final r = _plusStep(loadCorpusRecipe(_pita), typed);
        expect(_medium(r, '¼ cup extra-virgin olive oil'), isNull);
        final o = _out(r, '¼ cup extra-virgin olive oil', oil);
        expect((o.grams, o.source, o.hold), (56.0, 'portion', null));
        expect(friesForTest(r), isFalse, reason: typed);
      }
      // The oil's own heat still fries it (the Dutch oven is no oven).
      final fried = _plusStep(
        loadCorpusRecipe(_pita),
        'Heat the oil in a Dutch oven to 375 degrees.',
      );
      expect(
        _medium(fried, '¼ cup extra-virgin olive oil'),
        DiscardedMedium.fryingOil,
      );
      expect(friesForTest(fried), isTrue);
      // A fry "at" its temperature is the oil's too.
      expect(
        _medium(
          _plusStep(
            loadCorpusRecipe(_pita),
            'Fry the pitas in the oil at 350 degrees.',
          ),
          '¼ cup extra-virgin olive oil',
        ),
        DiscardedMedium.fryingOil,
      );
    }, skip: skipIfNoCorpus);

    test("S1's pour-off, judged: \"Pour off all but 1 tablespoon oil\" on the "
        "recipe's ONE ¼-cup oil is that oil's own sentence — its kept "
        'tablespoon (14 g) is what the dish eats, the rest poured away '
        '(0806, typed)', () {
      final r = _plusStep(
        loadCorpusRecipe(_pita),
        'Pour off all but 1 tablespoon oil from the skillet.',
      );
      final o = _out(r, '¼ cup extra-virgin olive oil', oil);
      expect((o.grams, o.source, o.hold), (14.0, 'discarded', null));
    }, skip: skipIfNoCorpus);

    test("S2: 0690 Patatas Bravas' sauce oil retyped \"½ cup extra-virgin "
        'olive oil" (an aioli) beside its 3 cups heated "to 375 degrees": '
        'the sentence names neither line, so the aioli is HELD '
        '`ambiguous_medium` with the sentence as its note — never zeroed — '
        'and the 3 cups stay frying oil by their mass', () {
      final r = _retyped(
        loadCorpusRecipe(_bravas),
        '1 tablespoon vegetable oil',
        '½ cup extra-virgin olive oil',
      );
      final aioli = _out(r, '½ cup extra-virgin olive oil', oil);
      expect(
        (aioli.grams, aioli.source, aioli.hold),
        (
          null,
          null,
          'ambiguous_medium',
        ),
      );
      expect(
        aioli.note,
        '"Heat oil in large Dutch oven over high heat to 375 degrees."',
      );
      final frying = _out(r, '3 cups vegetable oil', oil);
      expect(
        (frying.grams, frying.source, frying.hold),
        (
          0.0,
          'discarded',
          null,
        ),
      );
      // As written (a tablespoon), the sauce oil is no candidate: counted.
      final asWritten = loadCorpusRecipe(_bravas);
      expect(_medium(asWritten, '1 tablespoon vegetable oil'), isNull);
      expect(
        _medium(asWritten, '3 cups vegetable oil', grams: 654),
        DiscardedMedium.fryingOil,
      );
    }, skip: skipIfNoCorpus);

    test('O1: a second ¼-cup oil is never zeroed by a sentence that is not '
        "its own — 0357's sauce oil retyped ¼ cup beside \"Vegetable oil, "
        'for pan-frying" and "discard the oil left in the skillet" is held; '
        "0491's pork oil retyped ¼ cup counts (its tortilla oil's sentences "
        "name it); 1193's water retyped \"¼ cup toasted sesame oil\" holds "
        'both oils (no kept part counted twice)', () {
      final meatballs = _retyped(
        loadCorpusRecipe('0357-spaghetti-and-meatballs.yaml'),
        '2 tablespoons extra-virgin olive oil',
        '¼ cup extra-virgin olive oil',
      );
      final sauce = _out(meatballs, '¼ cup extra-virgin olive oil', oil);
      expect((sauce.grams, sauce.hold), (null, 'ambiguous_medium'));
      expect(sauce.note, contains('discard the oil left in the skillet'));

      final tostadas = _retyped(
        loadCorpusRecipe('0491-spicy-mexican-shredded-pork-tostadas.yaml'),
        '2 tablespoons olive oil',
        '¼ cup olive oil',
      );
      final pork = _out(tostadas, '¼ cup olive oil', oil);
      expect((pork.grams, pork.source, pork.hold), (56.0, 'portion', null));
      expect(
        _medium(tostadas, '¾ cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );

      final tempeh = _retyped(
        loadCorpusRecipe(_tempeh),
        '½ cup water',
        '¼ cup toasted sesame oil',
      );
      for (final raw in const [
        '1 cup vegetable oil',
        '¼ cup toasted sesame oil',
      ]) {
        final o = _out(tempeh, raw, oil);
        expect((o.grams, o.hold), (null, 'ambiguous_medium'), reason: raw);
        expect(o.note, startsWith('"Heat oil in 12-inch nonstick skillet'));
      }
    }, skip: skipIfNoCorpus);

    test("a sentence binds to a line by its kind's words or its own amount: "
        '1193 with the sesame oil, its heat retyped "Heat vegetable oil" — '
        'or "Heat 1 cup oil" — fries the vegetable oil alone (the pour-off '
        "then the vegetable oil's, its 2 tablespoons counted) and counts the "
        'sesame oil', () {
      final tempeh = _retyped(
        loadCorpusRecipe(_tempeh),
        '½ cup water',
        '¼ cup toasted sesame oil',
      );
      for (final heat in const ['Heat vegetable oil in', 'Heat 1 cup oil in']) {
        final r = _steps(tempeh, (t) => t.replaceAll('Heat oil in', heat));
        final vegetable = _out(r, '1 cup vegetable oil', oil);
        expect(
          (vegetable.grams, vegetable.source, vegetable.hold),
          (28.0, 'discarded', null),
          reason: heat,
        );
        final sesame = _out(r, '¼ cup toasted sesame oil', oil);
        expect((sesame.grams, sesame.hold), (56.0, null), reason: heat);
      }
    }, skip: skipIfNoCorpus);

    test("V3: a sentence binds by the OIL's own amount only — 0491 with its "
        'heat retyped "Stir 2 tablespoons lime juice into the salsa, then '
        'heat the oil …" keeps its ¾ cup frying oil (the lime juice\'s 2 '
        'tablespoons never binds the 2-tablespoon olive oil); with the pork '
        'oil retyped ¼ cup, "Stir ¼ cup lime juice …, then heat ¾ cup oil '
        '…" fries the ¾ cup alone and counts the ¼ cup', () {
      final base = loadCorpusRecipe(
        '0491-spicy-mexican-shredded-pork-tostadas.yaml',
      );
      const heat = 'Heat the vegetable oil in an 8-inch';
      final lime = _steps(
        base,
        (t) => t.replaceAll(
          heat,
          'Stir 2 tablespoons lime juice into the salsa, then heat the oil '
          'in an 8-inch',
        ),
      );
      expect(lime.steps, isNot(base.steps));
      final frying = _out(lime, '¾ cup vegetable oil', oil);
      expect(
        (frying.grams, frying.source, frying.hold),
        (0.0, 'discarded', null),
      );
      // Run 055 V3b: another food's amount with "oil" a few words later
      // still bound the fry through a 30-character window. The oil noun
      // phrase must FOLLOW the amount directly (synthesized steps, stated).
      for (final text in [
        'Add 2 tablespoons butter to the oil in an 8-inch',
        'Toss the salsa with 2 tablespoons lime juice; heat the oil in an '
                '8-inch'
            .trim(),
        'Stir 2 tablespoons lime juice into the oil, then heat it in an '
                '8-inch'
            .trim(),
      ]) {
        final r = _steps(base, (t) => t.replaceAll(heat, text));
        final out = _out(r, '¾ cup vegetable oil', oil);
        expect(
          (out.grams, out.source, out.hold),
          (0.0, 'discarded', null),
          reason: text,
        );
      }
      // The oil's own amount, with "of the" and its kind word between.
      final ofThe = _steps(
        base,
        (t) =>
            t.replaceAll(heat, 'Heat ¾ cup of the vegetable oil in an 8-inch'),
      );
      expect(_medium(ofThe, '¾ cup vegetable oil'), DiscardedMedium.fryingOil);
      final own = _steps(
        _retyped(base, '2 tablespoons olive oil', '¼ cup olive oil'),
        (t) => t.replaceAll(
          heat,
          'Stir ¼ cup lime juice into the salsa, then heat ¾ cup oil in an '
          '8-inch',
        ),
      );
      expect(_medium(own, '¾ cup vegetable oil'), DiscardedMedium.fryingOil);
      final pork = _out(own, '¼ cup olive oil', oil);
      expect((pork.grams, pork.source, pork.hold), (56.0, 'portion', null));
    }, skip: skipIfNoCorpus);

    test('a smaller line a sentence names keeps only that sentence: 1193 '
        'with its water retyped "2 tablespoons toasted sesame oil" and a '
        'typed "Heat the sesame oil to 350 degrees." — the sesame oil (under '
        'the quarter cup) counts, and the unnamed heat and pour-off stay the '
        "vegetable oil's (28 g kept)", () {
      final r = _plusStep(
        _retyped(
          loadCorpusRecipe(_tempeh),
          '½ cup water',
          '2 tablespoons toasted sesame oil',
        ),
        'Heat the sesame oil to 350 degrees.',
      );
      expect(_medium(r, '2 tablespoons toasted sesame oil'), isNull);
      final vegetable = _out(r, '1 cup vegetable oil', oil);
      expect(
        (vegetable.grams, vegetable.source, vegetable.hold),
        (
          28.0,
          'discarded',
          null,
        ),
      );
    }, skip: skipIfNoCorpus);

    test('a kind word binds only when no other oil line has it and the '
        'sentence says it OF the oil: 1193 with its water retyped "¼ cup '
        'vegetable oil" and its heat "Heat vegetable oil in …" holds both '
        '(both are vegetable); with "¼ cup toasted sesame oil" and "Heat oil '
        'with the sesame seeds in …" both are held too (the seeds are no '
        'oil)', () {
      final both = _steps(
        _retyped(
          loadCorpusRecipe(_tempeh),
          '½ cup water',
          '¼ cup vegetable oil',
        ),
        // No pour-off: the heat alone must not fry either line.
        (t) => t
            .replaceAll('Heat oil in', 'Heat vegetable oil in')
            .replaceAll(
              'Carefully pour off all but 2 tablespoons oil from pan. ',
              '',
            ),
      );
      final seeds = _steps(
        _retyped(
          loadCorpusRecipe(_tempeh),
          '½ cup water',
          '¼ cup toasted sesame oil',
        ),
        (t) => t.replaceAll(
          'Heat oil in',
          'Heat oil with the sesame seeds over low heat in',
        ),
      );
      for (final (r, raws) in [
        (both, const ['1 cup vegetable oil', '¼ cup vegetable oil']),
        (seeds, const ['1 cup vegetable oil', '¼ cup toasted sesame oil']),
      ]) {
        for (final raw in raws) {
          expect(_out(r, raw, oil).hold, 'ambiguous_medium', reason: raw);
        }
      }
    }, skip: skipIfNoCorpus);

    test('1193 as written: its one ¼-cup oil keeps "all but 2 tablespoons" '
        '— 28 g counted', () {
      final o = _out(loadCorpusRecipe(_tempeh), '1 cup vegetable oil', oil);
      expect((o.grams, o.source, o.hold), (28.0, 'discarded', null));
    }, skip: skipIfNoCorpus);

    test("S10: 0121's \"Pour off all but 2 teaspoons oil\" beside its 2 "
        'tablespoons (under the quarter cup): counted 28 g, never the kept 2 '
        "teaspoons — and a held line's own pour-off is no eaten part "
        '(1193 with a sesame oil that owns a typed "pour off all but 1 '
        'tablespoon oil from the toasted sesame oil skillet" by its words '
        "while the unnamed pour-off is either oil's: held, no "
        'grams)', () {
      final o = _out(
        loadCorpusRecipe(
          '0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-'
          'sauce.yaml',
        ),
        '2 tablespoons vegetable oil',
        oil,
      );
      expect((o.grams, o.source, o.hold), (28.0, 'portion', null));
      final tempeh = _steps(
        _retyped(
          loadCorpusRecipe(_tempeh),
          '½ cup water',
          '¼ cup toasted sesame oil',
        ),
        (t) => t
            .replaceAll('Heat oil in', 'Heat vegetable oil in')
            .replaceAll(
              'Serve.',
              'Pour off all but 1 tablespoon oil from the toasted sesame oil '
                  'skillet. Serve.',
            ),
      );
      for (final raw in const [
        '1 cup vegetable oil',
        '¼ cup toasted sesame oil',
      ]) {
        final held = _out(tempeh, raw, oil);
        expect(
          (held.grams, held.hold),
          (null, 'ambiguous_medium'),
          reason: raw,
        );
      }
    }, skip: skipIfNoCorpus);

    test('S11: the oil side of the one "for (deep) frying" signal — 0040 '
        'Arugula Salad\'s dressing oil retyped "1 cup vegetable oil for deep-frying" / "… for deep '
        'frying" / "… for frying" (218 g, under the mass rule; no dredge, no '
        'heat sentence) is frying oil, 0 g', () {
      for (final to in const [
        '1 cup vegetable oil for deep-frying',
        '1 cup vegetable oil for deep frying',
        '1 cup vegetable oil for frying',
      ]) {
        final r = _retyped(
          loadCorpusRecipe(
            '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
          ),
          '4 tablespoons extra-virgin olive oil',
          to,
        );
        expect(_medium(r, to, grams: 218), DiscardedMedium.fryingOil);
        final o = _out(r, to, oil);
        expect((o.grams, o.source), (0.0, 'discarded'), reason: to);
      }
    }, skip: skipIfNoCorpus);

    test("S12: a written ¼ cup sits ON the boundary — 1193's oil retyped "
        '"¼ cup vegetable oil" is frying oil (its own heat sentence), "3 '
        'tablespoons" is not; 0645 Barbecued Salmon\'s brine sugar '
        'retyped "¼ cup sugar" is brine sugar', () {
      final quarter = _retyped(
        loadCorpusRecipe(_tempeh),
        '1 cup vegetable oil',
        '¼ cup vegetable oil',
      );
      expect(
        _medium(quarter, '¼ cup vegetable oil'),
        DiscardedMedium.fryingOil,
      );
      final under = _retyped(
        loadCorpusRecipe(_tempeh),
        '1 cup vegetable oil',
        '3 tablespoons vegetable oil',
      );
      expect(_medium(under, '3 tablespoons vegetable oil'), isNull);
      // 0645's brine sugar is one only the quarter-cup arm reads (no
      // co-solute sentence): 0424 and 0461 are the library's others.
      final roast = _retyped(
        loadCorpusRecipe('0645-barbecued-salmon.yaml'),
        '1 cup sugar',
        '¼ cup sugar',
      );
      expect(_medium(roast, '¼ cup sugar'), DiscardedMedium.brineSugar);
    }, skip: skipIfNoCorpus);

    test('S3: "fry" spelled with a space after stir, air or dry, or negated '
        "(do not / don't / never), fries nothing; the hyphened frying verbs "
        'still fry (0024 Hearty Lentil Soup, which fries nothing, with one '
        'typed sentence)', () {
      final soup = loadCorpusRecipe('0024-hearty-lentil-soup.yaml');
      bool friesWith(String s) => friesForTest(_plusStep(soup, s));
      for (final s in const [
        'Stir fry the vegetables.',
        'Air fry the chicken at 400 degrees.',
        'Dry fry the spices.',
        'Oven fry the croutons.',
        'Do not fry the garlic.',
        "Don't fry the garlic.",
        'Don’t fry the garlic.',
        'Never fry the garlic.',
      ]) {
        expect(friesWith(s), isFalse, reason: s);
      }
      for (final s in const [
        'Fry the croutons until golden.',
        'Deep-fry the croutons.',
        'Pan-fry the croutons.',
      ]) {
        expect(friesWith(s), isTrue, reason: s);
      }
    }, skip: skipIfNoCorpus);
  });
}

double? _grams(String raw, FdcFood? food) {
  final p = parseIngredientLine(raw);
  return resolveGrams(
    amounts: p.amounts,
    food: food,
    normalizedItem: normalizeItem(p.item ?? raw),
    raw: raw,
  )?.grams;
}

void _i4() {
  group('I4 (Run 055 O6/S9/O7): what the amount measures', () {
    test("_asPrepared reads the item's noun phrase on 2708216 Popcorn, NFS "
        '("1 cup, popped" 14 g; "1 cup, unpopped, yields" 193 g): a sizing '
        'paren before the name is dropped, a qualifying one is a modifier, '
        'and a "from" is where it came from — the corpus line (0274 '
        "Red Snapper Ceviche's \"1 cup lightly salted popcorn\") and the "
        'typed shapes '
        '(no corpus line has them: a stated exception)', () async {
      final popcorn = (await FixtureProvider().food(2708216))!;
      for (final (raw, grams) in const [
        ('1 cup lightly salted popcorn', 14.0),
        ('6 cups (1 bag) popped popcorn', 84.0),
        ('6 cups (about) popped popcorn', 84.0),
        ('8 cups popped popcorn (from ⅓ cup kernels)', 112.0),
        ('8 cups popped popcorn from ⅓ cup kernels', 112.0),
        ('8 cups popped popcorn (⅓ cup kernels)', 112.0),
        ('½ cup popcorn (unpopped)', 96.5),
        ('½ cup popcorn (kernels)', 96.5),
        ('½ cup popcorn, unpopped', 96.5),
        ('⅓ cup popcorn kernels (8 cups popped)', 64.33),
      ]) {
        expect(_grams(raw, popcorn), closeTo(grams, 0.01), reason: raw);
      }
    });

    test("O7: a plus part's grated or shredded is read from its OWN words — "
        "the corpus's \"¼ cup grated Parmesan cheese plus 6 ounces, shredded "
        '(about 2 cups; see note)" (0419 Parmesan-Crusted Chicken Cutlets) '
        'and its '
        'printed restatement "… plus 2 cups shredded" weigh alike; a part '
        "naming no form takes the line's (typed shapes: a stated "
        'exception)', () {
      for (final (raw, grams) in const [
        (
          '¼ cup grated Parmesan cheese plus 6 ounces, shredded (about 2 '
              'cups; see note)',
          184.27,
        ),
        ('¼ cup grated Parmesan cheese plus 2 cups shredded', 184.28),
        (
          '1 ounce Parmesan, shredded (⅓ cup), plus 2 tablespoons grated',
          35.44,
        ),
        ('1 ounce Parmesan cheese, grated (½ cup), plus 2 tablespoons', 35.44),
      ]) {
        expect(_grams(raw, null), closeTo(grams, 0.01), reason: raw);
      }
    });
  });
}

void _i6Backfill() {
  // Corpus lines as text, recorded answers: no corpus file (Run 055 V5: CI
  // runs them).
  group('I6 (Run 055 S15/O11): the boot backfill never stops at a bad '
      'recipe', () {
    test(
      'an undecodable document is skipped, warned and retried; a row past '
      'its last line seeds an empty text list; a recipe never computed is '
      'not seeded, one with only match rows or only a total is — the '
      "boot's order: the bad recipe FIRST, so a throw would strand the rest "
      '(the undecodable doc is crafted, a stated negative-path exception)',
      () async {
        var (db, path) = v23.fileDb();
        final provider = FixtureProvider(pending: pendingSearches);
        for (final id in const ['a', 'b', 'e', 'f']) {
          await matchAndCompute(
            db,
            provider,
            wp.saveLines(db, [wp.oil, wp.onion], id: id),
          );
        }
        // b shortened with no compute: its row 1 stands past its last line.
        wp.saveLines(db, [wp.oil], id: 'b');
        wp.saveLines(db, [wp.oil, wp.onion], id: 'd'); // never computed
        db.dispose();
        v23.downgrade(path, 11);
        sqlite3.open(path)
          ..execute("UPDATE recipes SET doc = 'not json' WHERE id = 'a'")
          ..execute("DELETE FROM ingredient_matches WHERE recipe_id = 'e'")
          ..execute("DELETE FROM recipe_nutrition WHERE recipe_id = 'f'")
          ..dispose();
        db = SaltDatabase.open(path);
        addTearDown(db.dispose);
        final records = <LogRecord>[];
        final listening = Logger.root.onRecord.listen(records.add);
        addTearDown(listening.cancel);
        expect(db.recipesWithoutLayout(), ['a', 'b', 'e', 'f']);
        expect(backfillLayouts(db), 3);
        expect(db.layoutOf('a').texts, isNull);
        expect(db.layoutOf('b').lines, isEmpty);
        expect(db.layoutOf('e').lines, [wp.oil, wp.onion]);
        expect(db.layoutOf('f').lines, [wp.oil, wp.onion]);
        expect(db.layoutOf('d').texts, isNull);
        bool warnedA() => records.any(
          (r) => r.level == Level.WARNING && r.message.contains('skipped a:'),
        );
        expect(warnedA(), isTrue);
        records.clear();
        expect(backfillLayouts(db), 0);
        expect(warnedA(), isTrue, reason: 'retried at the next boot');
      },
    );

    test("the boot's re-key never throws out of a failed backfill: it logs it "
        '(recipe_layout dropped under the open database — a crafted '
        'negative-path exception)', () async {
      final (db, path) = v23.fileDb();
      addTearDown(db.dispose);
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [wp.oil, wp.onion]),
      );
      sqlite3.open(path)
        ..execute('DROP TABLE recipe_layout')
        ..dispose();
      final records = <LogRecord>[];
      final listening = Logger.root.onRecord.listen(records.add);
      addTearDown(listening.cancel);
      expect(() => rekeyAfterMatcherChange(db), returnsNormally);
      expect(
        records.where(
          (r) =>
              r.level == Level.SEVERE && r.message == 'Layout backfill failed',
        ),
        hasLength(1),
      );
    });

    test('seedLayout seeds nothing for a recipe with a layout or one that '
        'is gone, and draws no seq for either', () async {
      final (db, _) = v23.fileDb();
      addTearDown(db.dispose);
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [wp.oil, wp.onion]),
      );
      final before = db.layoutOf('r');
      expect(before.texts, isNotNull);
      expect(db.seedLayout('r', const []), isFalse);
      expect(db.layoutOf('r').seq, before.seq);
      expect(db.layoutOf('r').lines, before.lines);
      expect(db.seedLayout('gone', const []), isFalse);
      expect(db.layoutOf('gone').texts, isNull);
      // The next layout (an edit) draws the very next seq.
      layoutMatchRows(db, wp.saveLines(db, [wp.oil]));
      expect(
        db.layoutOf('r').seq,
        before.seq + 1,
        reason: 'neither refusal drew a seq from the counter',
      );
    });
  });
}

void _o12() {
  test("O12: a divided line's eaten part is dropped only for ANOTHER line "
      "of its food writing that very amount — 1133 Francese's \"¾ cup "
      'flour, divided" keeps "Sprinkle cubes with 1 teaspoon flour" beside '
      'a typed "1 cup cake flour" (same number, another unit), "2 teaspoons '
      'cake flour" (same unit, another number) or "1 teaspoon salt" '
      '(another food); a typed "1 teaspoon cake flour" takes it (typed '
      'lines: a stated exception)', () {
    const flour = '¾ cup all-purpose flour, divided';
    String? note(String? typed) {
      final r0 = loadCorpusRecipe('1133-chicken-francese.yaml');
      final r = typed == null
          ? r0
          : r0.copyWith(
              ingredients: [
                for (final (i, g) in r0.ingredients.indexed)
                  i > 0
                      ? g
                      : g.copyWith(
                          items: [
                            ...g.items,
                            IngredientLine(
                              raw: typed,
                              item: parseIngredientLine(typed).item,
                              amounts: parseIngredientLine(typed).amounts,
                            ),
                          ],
                        ),
              ],
            );
      return holdNoteOf(r, _line(r, flour), 'coating');
    }

    expect(note(null), contains('1 teaspoon flour'));
    for (final typed in const [
      '1 cup cake flour',
      '2 teaspoons cake flour',
      '1 teaspoon salt',
    ]) {
      expect(note(typed), contains('1 teaspoon flour'), reason: typed);
    }
    expect(note('1 teaspoon cake flour'), isNull);
  }, skip: skipIfNoCorpus);
}

void _ruleBCost() {
  test('RULE B costs O(text) (RULE C): 40 oil lines of distinct kinds on 40 '
      'legal 10,000-character steps of frying sentences — each naming one '
      'kind, or none (every line then held, the note built once) — every '
      "line's medium and note under 200 ms (synthesized hostile input, a "
      'stated exception)', () {
    final base = loadCorpusRecipe(
      '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    );
    // Kind words of letters only: "kindab", "kindac", ….
    final kinds = [
      for (var i = 0; i < 40; i++)
        String.fromCharCodes([
          ...'kind'.codeUnits,
          97 + i ~/ 26,
          97 + i % 26,
        ]),
    ];
    Recipe make({required bool named}) {
      final steps = [
        for (var i = 0; i < 40; i++)
          (named
                  ? 'Heat the ${kinds[i]} oil and 3 cups water to 350 degrees. '
                  : 'Heat the oil to 350 degrees. ') *
              (10000 ~/ 60),
      ];
      return base.copyWith(
        ingredients: [
          ...base.ingredients,
          IngredientGroup(
            items: [
              for (final k in kinds)
                IngredientLine(
                  raw: '¼ cup $k oil',
                  item: '$k oil',
                  amounts: parseIngredientLine('¼ cup $k oil').amounts,
                ),
            ],
          ),
        ],
        steps: [
          for (final (i, t) in steps.indexed)
            RecipeStep(number: i + 1, text: t),
        ],
      );
    }

    for (final named in const [true, false]) {
      var best = 1 << 30;
      late List<DiscardedMedium?> media;
      for (var run = 0; run < 3; run++) {
        final r = make(named: named);
        final sw = Stopwatch()..start();
        media = [
          for (final l in nutritionLines(r))
            discardedMediumOf(r, l, normalizeItem(lineItemOf(l))),
        ];
        for (final l in nutritionLines(r)) {
          holdNoteOf(r, l, 'ambiguous_medium');
        }
        best = min(best, sw.elapsedMilliseconds);
      }
      expect(
        media.where((m) => m == DiscardedMedium.ambiguousMedium),
        hasLength(named ? 0 : 41),
        reason: '$named',
      );
      expect(best, lessThan(200), reason: 'named: $named');
    }
    // The 41 held lines' note is one sentence of one step, split once (Run
    // 055 C15: the memo could be deleted with every test green).
    final r = make(named: false);
    stepIndexCounts.clear();
    for (final l in nutritionLines(r)) {
      holdNoteOf(r, l, 'ambiguous_medium');
    }
    expect(stepIndexCounts['rawSentences'], 1);
  }, skip: skipIfNoCorpus);
}
