// Run 054's server write-path fixes (matcher v24): the step and line
// regexes linear on hostile text (H1, Sonnet critic 1). Real corpus
// recipes (1133 Chicken Francese's divided flour, 0129 Mahogany Chicken
// Thighs' poured-away braise), recorded FDC answers (FixtureProvider),
// never the network. Synthesized, a stated exception: the hostile step
// text the H1 pins append (a negative-path input no corpus recipe holds).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';
import 'dart:math' show min;

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/layout_backfill.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v23_writepath_test.dart'
    as v23
    show applyOil, downgrade, fileDb, quarter, standIn;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

/// [recipe] with [text] appended to step [at] (the last when null).
Recipe appended(Recipe recipe, String text, {int? at}) {
  final i = at ?? recipe.steps.length - 1;
  return recipe.copyWith(
    steps: [
      for (final (j, s) in recipe.steps.indexed)
        j == i ? s.copyWith(text: '${s.text} $text') : s,
    ],
  );
}

/// Milliseconds [read] takes, the best of three (a cold first run never
/// decides a pin).
int msOf(void Function() read) {
  var best = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    read();
    best = sw.elapsedMilliseconds < best ? sw.elapsedMilliseconds : best;
  }
  return best;
}

/// The cold milliseconds of [read] on a fresh copy of [r] (the per-recipe
/// index cold, as a first compute or GET meets it), the best of three,
/// after a COUNT pin: every family one cold [read] derives within its bound
/// ([expectBounded]; Run 056 O20 — these pins were a clock alone, and a
/// clock alone fails on load alone).
int cheap(Recipe r, void Function(Recipe) read) {
  Recipe fresh() => r.copyWith(steps: [...r.steps]);
  final first = fresh();
  stepIndexCounts.clear();
  read(first);
  expectBounded(first, Map.of(stepIndexCounts), r.id);
  var best = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final copy = fresh();
    final sw = Stopwatch()..start();
    read(copy);
    best = min(best, sw.elapsedMilliseconds);
  }
  return best;
}

void main() {
  group('H1 (Run 054 Sonnet critic 1): the hold detectors are linear on a '
      'hostile step', () {
    // The two lines whose detectors scan step text by regex:
    // _eatenOutsideMedium (a coating's eaten part) and keptLiquidOf +
    // _eatenOutsideMedium (a braise's kept liquid).
    (Recipe, IngredientLine) flour() {
      final r = loadCorpusRecipe('1133-chicken-francese.yaml');
      return (
        r,
        nutritionLines(r).firstWhere((l) => l.raw.contains('flour, divided')),
      );
    }

    (Recipe, IngredientLine) braise() {
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      return (r, nutritionLines(r)[1]);
    }

    test("n = 80,000: a period-free '1 1 1 …' step (160 KB) reads within "
        'its count bounds and a 1,000 ms backstop for both detectors, and '
        'the notes are unchanged', () {
      // Ten times the 16 KB of v24 (Run 056 O20: a backstop far from both
      // the linear read and a quadratic one; a stated synthesized input).
      final hostile = '1 ' * 80000;
      final (fr, fl) = flour();
      final (br, bl) = braise();
      final fNote = holdNoteOf(fr, fl, 'coating');
      final bNote = holdNoteOf(br, bl, 'partial_pour_away');
      expect(fNote, isNotNull);
      final f2 = appended(fr, hostile, at: 0);
      final b2 = appended(br, hostile);
      final times = [
        cheap(f2, (r) => holdNoteOf(r, fl, 'coating')),
        cheap(b2, (r) => holdNoteOf(r, bl, 'partial_pour_away')),
        cheap(b2, (r) => keptLiquidOf(r, bl)),
      ];
      expect(times, everyElement(lessThan(1000)));
      expect(holdNoteOf(f2, fl, 'coating'), fNote);
      expect(holdNoteOf(b2, bl, 'partial_pour_away'), bNote);
    });

    test('the same 8,000 numbers in sentences UNDER the scanned bound '
        '(each read) stay linear: an overlapping amount run is quadratic '
        'per sentence and fails this bound about fivefold', () {
      // 40 sentences of 900 characters: under maxScannedSentence, so the
      // bound skips none and only the regex shape keeps this fast.
      final sentence = '${'1 ' * 449}1.';
      expect(sentence.length, lessThan(maxScannedSentence));
      // 400 sentences (ten times v24's 40; Run 056 O20, as above).
      final hostile = List.filled(400, sentence).join(' ');
      final (fr, fl) = flour();
      final (br, bl) = braise();
      final f2 = appended(fr, hostile, at: 0);
      final b2 = appended(br, hostile);
      // Measured at 40 sentences (v24): 13 ms linear, 385 ms with the overlap
      // restored; at 400 the tree reads 12 ms cold (Run 056), the overlap
      // ~3.9 s — the backstop sits ~100x and ~2.5x from each, the counts
      // beside it.
      final times = [
        cheap(f2, (r) => holdNoteOf(r, fl, 'coating')),
        cheap(b2, (r) => keptLiquidOf(r, bl)),
      ];
      expect(times, everyElement(lessThan(1500)));
    });

    test('a sentence longer than maxScannedSentence (1,000) is read for its '
        'first 1,000 characters (v25, Run 055 S7: the window): an eaten part '
        'named past them is not read', () {
      final (fr, fl) = flour();
      const mention = 'Sprinkle with 1 teaspoon flour.';
      // Francese's own eaten part named again past the bound: the note is
      // the corpus step's, never this padded one's.
      final padded = '${'x' * maxScannedSentence} $mention';
      expect(maxScannedSentence, 1000);
      final r = fr.copyWith(
        steps: [
          for (final s in fr.steps)
            s.copyWith(text: s.text.replaceAll('1 teaspoon flour', padded)),
        ],
      );
      expect(holdNoteOf(fr, fl, 'coating'), contains('1 teaspoon'));
      expect(holdNoteOf(r, fl, 'coating'), isNot(contains('1 teaspoon')));
    });
  }, skip: skipIfNoCorpus);

  group('H1: every other regex over step or line text is linear (each site '
      'Run 054 audited; hostile text synthesized, a stated exception)', () {
    test("a step of 'cooking liquid through …' (the strain's [^.]* run, "
        're-scanned from every start over a whole step at v23)', () {
      final r = loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml');
      final r2 = appended(r, 'cooking liquid through ' * 7000, at: 0);
      // Every line's read, as one compute reads them.
      final ms = cheap(r2, (r) {
        for (final l in nutritionLines(r)) {
          keptLiquidOf(r, l);
        }
      });
      expect(ms, lessThan(1000));
    });

    test("salt mentions after a long number run (the mention's written "
        'amount, read on the whole step prefix once per mention at v23)', () {
      final r = loadCorpusRecipe(
        '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
      );
      final r2 = appended(r, '${'1 ' * 2000}salt ' * 40, at: 0);
      final ms = cheap(r2, (r) {
        for (final line in nutritionLines(r)) {
          discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
        }
      });
      expect(ms, lessThan(1000));
    });

    test('a 1,000-character line raw (the cap) led by spaces or a number '
        'run: the sub-recipe test, the lost unit, the dozen, the sprig '
        "and the fresh herb's dried amount", () async {
      // Ten times the cap (Run 056 O20: a clock pin must not fail on load
      // alone — a regex has no count to pin, so the input is grown until a
      // quadratic run costs seconds while the linear one stays under 5 ms,
      // and the bound sits ~100x from each; a stated synthesized input of
      // a function-level pin).
      final spaces = '${' ' * 9900}1 x';
      final ones = '1${' 1' * 4950}x';
      for (final raw in [spaces, ones]) {
        expect(msOf(() => isSubRecipeReference(raw)), lessThan(500));
        expect(
          msOf(
            () => resolveGrams(
              amounts: const [
                Amount(measure: Measure.count, quantity: '1', primary: true),
              ],
              food: null,
              normalizedItem: 'x',
              raw: raw,
            ),
          ),
          lessThan(500),
        );
      }
      final db = wp.tempDb();
      final oregano = (await FixtureProvider().food(171328))!;
      for (final tail in [' ' * 9500, '1 ' * 4750]) {
        final line = IngredientLine(
          raw: '1 tablespoon minced fresh oregano or ${tail}x',
          amounts: const [
            Amount(
              measure: Measure.volume,
              quantity: '1',
              unit: 'tablespoon',
              primary: true,
            ),
          ],
          item: 'fresh oregano',
        );
        expect(msOf(() => lineGrams(db, line, oregano)), lessThan(500));
      }
    });

    test("resolveGrams on 998 spaces + '1!' and 999 spaces + '!' (Run 055 "
        "D1: the lead number regex of a bare count's lost unit was cubic in "
        'leading whitespace, 2 s a line; the lead run now has no space in '
        "its class), and on '(1' + 997 spaces + 'x' (the paren volume's "
        r"lazy run with a space beside its unit's [\s-]*, 21 ms unnormalized, "
        '0.3 ms on the raw resolveGrams normalizes once at its entry)', () {
      GramResolution? grams(String raw) => resolveGrams(
        amounts: const [
          Amount(measure: Measure.count, quantity: '1', primary: true),
        ],
        food: null,
        normalizedItem: 'x',
        raw: raw,
      );
      // Ten times the cap, as above (Run 056 O20).
      for (final raw in ['${' ' * 9980}1!', '${' ' * 9990}!']) {
        expect(msOf(() => grams(raw)), lessThan(500));
        // The regex itself, on a raw no entry normalized.
        expect(
          msOf(
            () => parsedUnitForTest(
              const Amount(measure: Measure.count, quantity: '1'),
              raw,
            ),
          ),
          lessThan(500),
        );
      }
      expect(msOf(() => grams('(1${' ' * 9970}x')), lessThan(500));
      // The engine's line regexes that open on a whitespace run (the
      // sub-recipe test's " or " split: 20 ms on 999 spaces at v24) start
      // only at a run's first space.
      expect(
        msOf(() => isSubRecipeReference('${' ' * 9990}!')),
        lessThan(500),
      );
    });
  }, skip: skipIfNoCorpus);

  group("H2 (Run 054 S4/O4/O15): the reach's hold detector runs once per "
      'reached line per stored version', () {
    test('1133 Francese beside 0148, 0129 and 0000: one GET runs the '
        'detector once per distinct reached row (never once per line per '
        'row) and decodes each reached recipe once (never once per row), a '
        'second GET runs it 0 times, and an edit of a reached recipe '
        're-reads only that recipe', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final tostadas = loadCorpusRecipe('1133-chicken-francese.yaml');
      final others = [
        loadCorpusRecipe('0148-crispy-fried-chicken.yaml'),
        loadCorpusRecipe('0129-mahogany-chicken-thighs.yaml'),
        // Two lines on the reached keys (salt and garlic): one recipe
        // reached through two rows (Run 055 S1).
        loadCorpusRecipe('0000-garlic-and-olive-oil-mashed-potatoes.yaml'),
      ];
      for (final r in [tostadas, ...others]) {
        wp.saveRecipe(db, r);
        await matchAndCompute(db, provider, r);
      }
      // A person picks another salt and another garlic record on 1133's
      // lines: its siblings on the old foods (0148's salt, 0129's garlic)
      // are what an apply-to-all from each line would reach.
      for (final (raw, fdcId) in [
        ('2 teaspoons table salt', 746775),
        ('1 garlic clove, minced', 169230),
      ]) {
        final at = nutritionLines(tostadas).indexWhere((l) => l.raw == raw);
        expect(at, isNonNegative, reason: raw);
        await applyMatchOverride(db, provider, tostadas, at, {
          'raw': raw,
          'fdc_id': fdcId,
        });
      }
      // The rows any line of 1133 could reach: undecided rows of its keys
      // in the other recipes (an upper bound on the distinct reached rows).
      final keys = {for (final l in nutritionLines(tostadas)) lineKeyOf(l)};
      final reachable = {
        for (final r in others)
          for (final row in db.ingredientMatchesFor(r.id))
            if (keys.contains(row.itemKey)) (r.id, row.position),
      };
      expect(reachable, isNotEmpty);
      reachHoldReads = 0;
      reachDecodes = 0;
      await matchesBody(db, provider, tostadas);
      final first = reachHoldReads;
      expect(first, greaterThan(0));
      expect(first, lessThanOrEqualTo(reachable.length));
      // One decode per reached RECIPE in a request (ReachMemo), never one
      // per reached row: 0000 is reached through its salt and its garlic.
      expect(
        reachDecodes,
        lessThanOrEqualTo({for (final k in reachable) k.$1}.length),
      );
      expect(reachDecodes, lessThan(first));
      reachHoldReads = 0;
      await matchesBody(db, provider, tostadas);
      expect(reachHoldReads, 0);
      // A steps edit of 0148 (its stored content hash moves): its reached
      // rows are read again, 1133's are not.
      final edited = others[0].copyWith(
        steps: [
          for (final (i, st) in others[0].steps.indexed)
            i == 0 ? st.copyWith(text: '${st.text} Serve.') : st,
        ],
      );
      wp.saveRecipe(db, edited);
      reachHoldReads = 0;
      await matchesBody(db, provider, tostadas);
      expect(reachHoldReads, greaterThan(0));
      expect(
        reachHoldReads,
        lessThanOrEqualTo(reachable.where((k) => k.$1 == edited.id).length),
      );
    });
  }, skip: skipIfNoCorpus);

  group('H4 (Run 054 S3, Opus critic 3, O3, O5): a recipe computed before '
      'migration 012 is seeded a real layout at boot; no first layout keeps '
      'seq 0', () {
    /// 'c' = [¼ cup oil, onion] computed, the database put back to version
    /// 11 and opened (012 and 013 run), then the boot's backfills.
    Future<SaltDatabase> upgraded(List<String> raws, {String id = 'c'}) async {
      var (db, path) = v23.fileDb();
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, raws, id: id),
      );
      db.dispose();
      v23.downgrade(path, 11);
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      // As the boot runs it (bootstrap → rekeyAfterMatcherChange).
      rekeyAfterMatcherChange(db);
      expect(db.layoutOf(id).texts, isNotNull);
      expect(db.nutritionFor(id)!.layoutSeq, db.layoutOf(id).seq);
      expect(backfillLayouts(db), 0);
      return db;
    }

    Future<
      ({
        int recipes,
        int lines,
        int failed,
        int completed,
        List<String> completedRecipes,
        int moved,
        int decided,
        int gone,
        int failedLines,
        int unavailable,
      })
    >
    applyQuarter(SaltDatabase db, Future<void> Function() during) async {
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches))
        ..onCall = during;
      return applyDecisionToOthers(
        db,
        provider,
        itemKey: lineKeyOf(wp.lineOf(v23.quarter)),
        decided: await v23.standIn(),
        excluding: (recipeId: 'a', position: 0),
      );
    }

    test(
      'S3: a seeded target deleted and re-created under its id (as '
      "[2 celery ribs]) during the apply's await — the write is refused "
      'and the line filed gone, never the oil row on the celery line',
      () async {
        final db = await upgraded([v23.quarter, wp.onion]);
        expect(db.layoutOf('c').seq, greaterThan(0));
        final res = await applyQuarter(db, () async {
          db.deleteRecipe('c');
          wp.saveLines(db, [wp.celery], id: 'c');
        });
        expect(res.lines, 0);
        expect(res.gone, 1);
        expect(res.failed, 0);
        expect(
          db.ingredientMatchesFor('c').where((r) => r.raw == v23.quarter),
          isEmpty,
        );
      },
    );

    test("S3's other side: re-created as [½ cup oil] (the same ingredient, "
        'another amount) — refused and moved (left for its compute), never '
        'gone', () async {
      final db = await upgraded([v23.quarter, wp.onion]);
      final res = await applyQuarter(db, () async {
        db.deleteRecipe('c');
        wp.saveLines(db, [wp.oil], id: 'c');
      });
      expect((res.lines, res.moved, res.gone), (0, 1, 0));
      expect(db.ingredientMatchesFor('c'), isEmpty);
    });

    test('O5: a seeded target deleted during the await is gone, never '
        'failed (no FK error at seq 0)', () async {
      final db = await upgraded([v23.quarter, wp.onion]);
      final res = await applyQuarter(db, () async => db.deleteRecipe('c'));
      expect(res.gone, 1);
      expect(res.failed, 0);
      expect(res.failedLines, 0);
    });

    test("Opus critic 3: on a seeded recipe, a line appended, a person's "
        'pick on it, the save reverted — stale, never fresh with the '
        "reverted line's food in the totals", () async {
      final db = await upgraded([wp.oil, wp.onion, wp.celery], id: 'r');
      final r = db.recipeByIdOrSlug('r')!.recipe;
      expect(nutritionIsFresh(db, r), isTrue);
      final appended = wp.saveLines(db, [
        wp.oil,
        wp.onion,
        wp.celery,
        v23.quarter,
      ]);
      await applyMatchOverride(
        db,
        FixtureProvider(pending: pendingSearches),
        appended,
        3,
        {
          'raw': v23.quarter,
          'fdc_id': 173468,
        },
      );
      final reverted = wp.saveLines(db, [wp.oil, wp.onion, wp.celery]);
      expect(nutritionIsFresh(db, reverted), isFalse);
      expect(nutritionBody(db, reverted, forAdmin: true)['status'], 'stale');
    });

    test(
      'O3: a plain recompute (the serving-basis PUT) on an edited recipe, '
      'then a revert — stale, its stamp keeps no hash it did not compute on',
      () async {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        await matchAndCompute(
          db,
          provider,
          wp.saveLines(db, [wp.oil, wp.onion, wp.celery]),
        );
        final edited = wp.saveLines(db, [wp.oil, wp.onion]);
        recomputeTotals(db, edited, servingBasis: 1);
        expect(db.nutritionFor('r')!.ingredientsHash, '');
        final reverted = wp.saveLines(db, [wp.oil, wp.onion, wp.celery]);
        expect(nutritionIsFresh(db, reverted), isFalse);
        expect(nutritionBody(db, reverted, forAdmin: true)['status'], 'stale');
        // On the inputs it was stamped on, a plain recompute keeps the stamp.
        await matchAndCompute(db, provider, reverted);
        recomputeTotals(db, reverted, servingBasis: 2);
        expect(nutritionIsFresh(db, reverted), isTrue);
      },
    );

    test('no seq-0 branch: without the backfill, a first layout that moves '
        'nothing still draws a seq from the counter', () async {
      var (db, path) = v23.fileDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(db, provider, wp.saveLines(db, [wp.oil, wp.onion]));
      db.dispose();
      v23.downgrade(path, 11);
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      layoutMatchRows(db, db.recipeByIdOrSlug('r')!.recipe);
      expect(db.layoutOf('r').seq, greaterThan(0));
    });

    test('the backfill is idempotent and seeds an empty text list when a '
        "row is not on its line (its old lines unknown): the pairing's "
        'own reading, and the next layout records the lines', () async {
      var (db, path) = v23.fileDb();
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        wp.saveLines(db, [wp.oil, wp.onion]),
      );
      wp.saveLines(db, [v23.quarter, wp.onion]);
      db.dispose();
      v23.downgrade(path, 11);
      db = SaltDatabase.open(path);
      addTearDown(db.dispose);
      expect(backfillLayouts(db), 1);
      expect(db.layoutOf('r').lines, isEmpty);
      final seeded = db.layoutOf('r').seq;
      expect(db.nutritionFor('r')!.layoutSeq, seeded);
      expect(backfillLayouts(db), 0);
      layoutMatchRows(db, db.recipeByIdOrSlug('r')!.recipe);
      expect(db.layoutOf('r').seq, greaterThan(seeded));
      expect(db.layoutOf('r').lines, [v23.quarter, wp.onion]);
    });
  }, skip: skipIfNoCorpus);

  group("H5(b) (Run 054 Opus critic 1): a decided row's hold is the "
      "engine's, re-derived on every compute", () {
    const flour = '4 cups (20 ounces) unbleached all-purpose flour';

    /// 0148's steps with the dredge taken out (the edit the v22 rulings
    /// pins use — a stated synthesized edit of a corpus recipe).
    Recipe undredged(Recipe r) => r.copyWith(
      steps: [
        for (final step in r.steps)
          step.copyWith(
            text: step.text
                .replaceAll('Place the flour in a shallow dish. ', '')
                .replaceAll(', shaking off the excess', '')
                .replaceAll('dredge in the flour', 'toss with the flour')
                .replaceAll(', shake off the excess', '')
                .replaceAll(', allowing the excess to drip off', ''),
          ),
      ],
    );

    test("0148's dredge flour picked (the hold kept), then a steps-only edit "
        'that stops the dredge and a compute: the hold is cleared and the '
        'flour weighed, the pick (food, status) untouched; a later confirm '
        'counts it, never 0 g poured away', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final at = nutritionLines(r).indexWhere((l) => l.raw == flour);
      expect(db.ingredientMatchesFor(r.id)[at].hold, 'coating');
      await applyMatchOverride(db, provider, r, at, {
        'raw': flour,
        'fdc_id': 789890,
      });
      final picked = db.ingredientMatchesFor(r.id)[at];
      expect((picked.status, picked.hold), ('overridden', 'coating'));
      final edited = undredged(r);
      expect(heldMediumLine(edited, nutritionLines(edited)[at]), isFalse);
      wp.saveRecipe(db, edited);
      await matchAndCompute(db, provider, edited);
      final after = db.ingredientMatchesFor(r.id)[at];
      expect(after.hold, isNull);
      expect((after.status, after.fdcId), ('overridden', 789890));
      expect(after.grams, greaterThan(0));
      expect(nutritionIsFresh(db, edited), isTrue);
      await applyMatchOverride(db, provider, edited, at, {
        'raw': flour,
        'confirmed': true,
      });
      final confirmed = db.ingredientMatchesFor(r.id)[at];
      expect(confirmed.grams, greaterThan(0));
      expect(confirmed.gramSource, isNot(GramSource.discarded.name));
    });

    test('grams a person typed on the held dredge answer its hold: a title '
        'edit and a compute give the row no engine hold back', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final at = nutritionLines(r).indexWhere((l) => l.raw == flour);
      await applyMatchOverride(db, provider, r, at, {
        'raw': flour,
        'grams': 60,
      });
      final typed = db.ingredientMatchesFor(r.id)[at];
      expect(typed.gramSource, GramSource.override.name);
      final edited = r.copyWith(title: '${r.title} (edited)');
      wp.saveRecipe(db, edited);
      await matchAndCompute(db, provider, edited);
      final after = db.ingredientMatchesFor(r.id)[at];
      expect((after.hold, after.grams), (typed.hold, 60.0));
    });

    test('an unchanged recipe recomputed leaves the picked row as the pick '
        'wrote it (no write when the hold is the same)', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      await matchAndCompute(db, provider, r);
      final at = nutritionLines(r).indexWhere((l) => l.raw == flour);
      await applyMatchOverride(db, provider, r, at, {
        'raw': flour,
        'fdc_id': 789890,
      });
      final picked = db.ingredientMatchesFor(r.id)[at];
      await matchAndCompute(db, provider, r);
      final again = db.ingredientMatchesFor(r.id)[at];
      expect(again.updatedAt, picked.updatedAt);
      expect(again.hold, 'coating');
    });
  }, skip: skipIfNoCorpus);

  group('H7 server pins (Run 054 S10, O14, S11)', () {
    test("S10: a person's serving basis (7 on a serves-4 recipe) survives a "
        're-match and a plain recompute', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r = wp.saveLines(db, [wp.oil, wp.onion], serves: 4);
      await matchAndCompute(db, provider, r);
      expect(db.nutritionFor('r')!.servingBasis, 4);
      recomputeTotals(db, r, servingBasis: 7);
      await matchAndCompute(db, provider, r);
      expect(db.nutritionFor('r')!.servingBasis, 7);
      recomputeTotals(db, r);
      expect(db.nutritionFor('r')!.servingBasis, 7);
    });

    test("O14/S11(b): c's only oil line saved at another amount and computed "
        "during b's fetch — moved (the same ingredient), never gone", () async {
      final db = wp.tempDb();
      final inner = FixtureProvider(pending: pendingSearches);
      final provider = wp.Gated(inner);
      await matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [v23.quarter], id: 'b'),
      );
      await matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [v23.quarter], id: 'c'),
      );
      provider.onCall = () async => matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [wp.oil], id: 'c'),
      );
      final res = await v23.applyOil(db, provider);
      expect((res.lines, res.decided, res.moved, res.gone), (1, 0, 1, 0));
    });

    test("S11(a): c [¼ cup oil, ¼ cup oil] deleted during b's fetch — gone "
        'counts both offered lines', () async {
      final db = wp.tempDb();
      final inner = FixtureProvider(pending: pendingSearches);
      final provider = wp.Gated(inner);
      await matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [v23.quarter], id: 'b'),
      );
      await matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [v23.quarter, v23.quarter], id: 'c'),
      );
      provider.onCall = () async => db.deleteRecipe('c');
      final res = await v23.applyOil(db, provider);
      expect((res.lines, res.gone, res.moved), (1, 2, 0));
    });

    // v27 (RULE A, Run 057 Opus critic 1): the totals are cache-only — c's
    // totals recompute with celery (in no cache) left out, stale; nothing
    // fails after the rows are written.
    test('S11(c): c [¼ cup oil, ¼ cup oil, celery], line 0 saved at ½ cup '
        "and computed during b's fetch (moved), celery gone from every cache "
        "and FDC failing — c's line 1 written, its totals recomputed "
        'without celery and stale, nothing failed', () async {
      final (db, path) = v23.fileDb();
      addTearDown(db.dispose);
      final inner = FixtureProvider(pending: pendingSearches);
      await matchAndCompute(
        db,
        inner,
        wp.saveLines(db, [v23.quarter], id: 'b'),
      );
      final c = wp.saveLines(db, [
        v23.quarter,
        v23.quarter,
        wp.celery,
      ], id: 'c');
      await matchAndCompute(db, inner, c);
      final celery = db.ingredientMatchesFor('c')[2].fdcId!;
      final provider = wp.Gated(_FailFood(inner, celery))
        ..onCall = () async {
          await matchAndCompute(
            db,
            inner,
            wp.saveLines(db, [wp.oil, v23.quarter, wp.celery], id: 'c'),
          );
          sqlite3.open(path)
            ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [celery])
            ..execute('DELETE FROM fdc_search_cache')
            ..dispose();
        };
      final res = await v23.applyOil(db, provider);
      expect(
        (res.lines, res.moved, res.failed, res.failedLines),
        (2, 1, 0, 0),
      );
      final stored = db.recipeByIdOrSlug('c')!.recipe;
      expect(nutritionIsFresh(db, stored), isFalse);
      expect(db.nutritionFor('c')!.status, 'partial');
    });
  }, skip: skipIfNoCorpus);

  // A sweep snapshot from before migration 012 (key-stripped, read through
  // a temp copy) when SALT_REVIEW_SNAPSHOT names one (snapshot 13).
  final snapshot = Platform.environment['SALT_REVIEW_SNAPSHOT'];
  group(
    'H4 on a real pre-012 snapshot',
    skip: snapshot == null || !File(snapshot).existsSync()
        ? 'set SALT_REVIEW_SNAPSHOT to a pre-012 sweep snapshot to run'
        : null,
    () {
      test('the upgrade and the boot seed every stamped recipe a distinct '
          'counter seq on its own lines, its stamp moved onto it, no row '
          'moved, idempotent on re-open; a recomputed unedited recipe stays '
          'fresh through a PUT and an apply-to-all turn', () async {
        final dir = Directory.systemTemp.createTempSync('salt-v24-snap');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/salt.db';
        File(snapshot!).copySync(path);
        var db = SaltDatabase.open(path);
        String rows() => [
          for (final id in db.allRecipeIds())
            for (final r in db.ingredientMatchesFor(id))
              '$id ${r.position} ${r.raw} ${r.status} ${r.fdcId} ${r.grams}',
        ].join('\n');
        final before = rows();
        final ids = db.recipesWithoutLayout();
        expect(ids, hasLength(db.allRecipeIds().length));
        rekeyAfterMatcherChange(db);
        expect(db.recipesWithoutLayout(), isEmpty);
        final seqs = <int>{};
        for (final id in ids) {
          final layout = db.layoutOf(id);
          final recipe = db.recipeByIdOrSlug(id)!.recipe;
          expect(layout.lines, [for (final l in nutritionLines(recipe)) l.raw]);
          expect(db.nutritionFor(id)!.layoutSeq, layout.seq);
          expect(seqs.add(layout.seq), isTrue);
        }
        expect(rows(), before);
        db.dispose();
        db = SaltDatabase.open(path);
        addTearDown(db.dispose);
        expect(backfillLayouts(db), 0);

        final provider = _NoNetwork();
        final id = db.allRecipeIds().firstWhere(
          (i) => db.recipeByIdOrSlug(i)!.recipe.slug == 'chicken-francese',
        );
        final r = db.recipeByIdOrSlug(id)!.recipe;
        final seq = db.layoutOf(id).seq;
        await matchAndCompute(db, provider, r);
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.layoutOf(id).seq, seq);
        final salt = nutritionLines(
          r,
        ).indexWhere((l) => l.raw.contains('salt'));
        final row = db.ingredientMatchesFor(id)[salt];
        await applyMatchOverride(db, provider, r, salt, {
          'raw': row.raw,
          'fdc_id': row.fdcId,
          'apply_to_all': true,
        });
        expect(nutritionIsFresh(db, r), isTrue);
        await applyMatchOverride(db, provider, r, 0, {
          'raw': nutritionLines(r)[0].raw,
          'confirmed': true,
        });
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.layoutOf(id).seq, seq);
        expect(provider.calls, 0);
      }, timeout: const Timeout(Duration(minutes: 5)));

      test(
        "H2's budget on the busiest GET: 0491 Tostadas' matches runs the "
        'medium detector at most once per distinct reached row (517 on '
        'snapshot 13; 1,033 runs at v23), and 0 times on the next GET',
        () async {
          final dir = Directory.systemTemp.createTempSync('salt-v24-snap');
          addTearDown(() => dir.deleteSync(recursive: true));
          File(snapshot!).copySync('${dir.path}/salt.db');
          final db = SaltDatabase.open('${dir.path}/salt.db');
          addTearDown(db.dispose);
          final r = db
              .recipeByIdOrSlug(
                db.allRecipeIds().firstWhere(
                  (i) =>
                      db.recipeByIdOrSlug(i)!.recipe.slug ==
                      'spicy-mexican-shredded-pork-tostadas',
                ),
              )!
              .recipe;
          reachHoldReads = 0;
          await matchesBody(db, _NoNetwork(), r);
          expect(reachHoldReads, lessThanOrEqualTo(517));
          reachHoldReads = 0;
          await matchesBody(db, _NoNetwork(), r);
          expect(reachHoldReads, 0);
        },
      );
    },
  );
}

/// No network: the snapshot's cache answers everything, or this throws.
class _NoNetwork implements NutritionProvider {
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw NutritionProviderException('no network: search "$query"');
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw NutritionProviderException('no network: food $fdcId');
  }
}

/// Fails [failing]'s detail fetch (FDC failing for it).
class _FailFood implements NutritionProvider {
  _FailFood(this.inner, this.failing);
  final NutritionProvider inner;
  final int failing;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) => fdcId == failing
      // FDC's own failure class (v28: a plain recompute resolves a food no
      // cache holds and reads a NutritionProviderException as "not now").
      ? throw const NutritionProviderException('FDC failing')
      : inner.food(fdcId);
}
