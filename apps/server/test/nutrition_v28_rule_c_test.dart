// RULE C, matcher v28 (brief I4 — Run 058 O4/S8, O5/S10, O6/S11): the
// naming inversion is built by MEASURED amortisation — a head is scanned
// for alone until the per-head scans an index has paid reach the
// inversion's own cost (the v28 closer: v27's second-head gate and the
// v28 one-line declaration were proxies); the inversion itself is linear per sentence
// (each word confirmed at the word, never a rescan per word found); the
// matches GET resolves each row's food ONCE (`derivedFor`'s `resolved`);
// a pass asks FDC once per FOOD (`onePass`: every id asked and every miss
// remembered for the pass).
//
// Real corpus recipes (0149 Easier Fried Chicken, 0857 Rich Chocolate
// Bundt Cake, 0148 Crispy Fried Chicken, 0506's napa line) and recorded
// FDC answers (FixtureProvider), never the network. Synthesized, each a
// stated exception: the hostile cost shapes at the editor caps (0149's real
// lines and steps padded with distinct filler heads, as Run 058 O4's
// repro), a line repeated to the caps (400 rows on one retired food, 100
// napa rows), the retired id 999000111 (Run 057 S5's), FDC's "no such food"
// or a failure for one id (provider wrappers), and seeded random texts for
// the word-reading pin.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_cost_test.dart' show reachShape, tok;
import 'nutrition_v28_rule_a_test.dart'
    show FoodFault, dropFood, napa, napaId, napaSibling, poisoned;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _fried = '0149-easier-fried-chicken.yaml';

/// 0149 with its real lines and steps, padded to the editor caps with
/// distinct filler heads (Run 058 O4's shape; a stated exception).
Recipe friedAtCaps(int k) {
  final base = loadCorpusRecipe(_fried);
  final own = [for (final l in nutritionLines(base)) l.raw];
  final ws = [
    for (var i = 0; i < capLines - own.length; i++) 'z${tok(k)}${tok(i)}',
  ];
  final s = [
    for (var i = 0; i < ws.length; i += 60)
      'Stir the ${ws.sublist(i, (i + 60).clamp(0, ws.length)).join(', ')} into the pot. ',
  ].join();
  return capped(
    base,
    [...own, for (final w in ws) '1 cup $w'],
    [
      for (final st in base.steps) st.text,
      ...List.filled(
        capSteps - base.steps.length,
        (s * 20).substring(0, capStep),
      ),
    ],
  ).copyWith(id: 'o$k', slug: 'o-$k');
}

/// A provider whose searches find nothing (every row reached).
class _NoHits extends FixtureProvider {
  _NoHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) async => const [];
}

/// Every search answered with the recorded vegetable oil answer: every
/// line matched.
class _AllHits extends FixtureProvider {
  _AllHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) => super.search('vegetable oil');
}

/// Runs [onSearch] at each search, then finds nothing.
class _DeleteOnSearch extends _NoHits {
  _DeleteOnSearch(this.onSearch);
  final void Function() onSearch;
  @override
  Future<List<FdcCandidate>> search(String q) async {
    onSearch();
    return const [];
  }
}

/// The line of [r] whose text is [raw].
IngredientLine lineOf(Recipe r, String raw) =>
    nutritionLines(r).firstWhere((l) => l.raw == raw);

const _oil = '1¾ cups vegetable oil';

/// The v27 reading of `_wordsOf` (a whole-sentence [namesForTest] per form
/// found), as a set: the reference the linear reading must equal.
Set<String> wordsByRescan(String sentence) {
  final out = <String>{};
  for (final m in RegExp(r'\w+').allMatches(sentence)) {
    final t = m[0]!;
    for (final c in [
      t,
      if (t.endsWith('s')) t.substring(0, t.length - 1),
      if (t.endsWith('es')) t.substring(0, t.length - 2),
      if (t.endsWith('ies')) '${t.substring(0, t.length - 3)}y',
    ]) {
      if (c.isNotEmpty && namesForTest(sentence, c)) {
        out.add(c);
      }
    }
  }
  return out;
}

/// Where each of [patterns] first occurs in each of [texts], by `indexOf`
/// (the naive reference for the Aho–Corasick index).
Map<String, List<(int, int)>> occurrencesByScan(
  List<String> texts,
  Iterable<String> patterns,
) => {
  for (final p in patterns.toSet())
    if ([
          for (final (t, text) in texts.indexed)
            if (text.indexOf(p) case final i when i >= 0) (t, i),
        ]
        case final at when at.isNotEmpty)
      p: at,
};

void main() {
  group('I4(a) O4/S8: the naming inversion built by MEASURED amortisation '
      '(v28 closer)', () {
    test("0149's oil line asks two heads (oil, flour): read alone it scans "
        'each alone and builds no inversion; so does a reader of all its '
        'lines (ten heads cost less than the inversion of a corpus '
        'recipe)', () {
      final r = loadCorpusRecipe(_fried);
      stepIndexCounts.clear();
      heldMediumLine(r, weighedLine(r, lineOf(r, _oil)));
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
      expect(stepIndexCounts['memo:naming'], 2);
      for (final line in nutritionLines(r)) {
        heldMediumLine(r, weighedLine(r, line));
      }
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
    });

    test('at the caps: the per-head scan and the inversion answer alike for '
        "every head; the steps a head's pattern finds nothing in are never "
        "read by sentence; 0149's eight heads stay per-head, every head "
        'read builds the inversion ONCE', () {
      final scan = friedAtCaps(0);
      final heads = wordHeadsForTest(scan).toList();
      stepIndexCounts.clear();
      for (final h in ['buttermilk', 'hot', 'pepper', 'powder', 'paprika']) {
        namingByScanForTest(scan, h);
      }
      // v29 (Run 059 O9): the scan reads no sentence at all — each head
      // visits the steps' words once (an int compare), what it pays.
      expect(stepIndexCounts['namingReads'] ?? 0, 0);
      expect(stepIndexCounts['words'], wordCountForTest(scan));
      final built = friedAtCaps(0);
      stepIndexCounts.clear();
      for (final h in [
        'buttermilk',
        'hot',
        'pepper',
        'powder',
        'paprika',
        'part',
        'flour',
        'oil',
      ]) {
        namingForTest(built, h);
      }
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
      for (final h in heads) {
        namingForTest(built, h);
      }
      expect(stepIndexCounts['memo:namingAll'], 1);
      // v29 (Run 059 O9, the unit exact): the build comes when the scans
      // paid reach 12 × the words — each scan pays every word once, plus
      // its confirms' characters (0149's 8 heads ~0.0003 × the words, a
      // filler named in every step ~0.1 ×): 12 scans, then the inversion.
      expect(stepIndexCounts['memo:naming'], 12);
      // reachShape: 'garlic' in no step (the words exactly), then fillers
      // (the words and ~0.1 × in confirms): 12 scans.
      final reach = reachShape(0);
      stepIndexCounts.clear();
      for (final h in wordHeadsForTest(reach)) {
        namingForTest(reach, h);
      }
      expect(stepIndexCounts['memo:namingAll'], 1);
      expect(stepIndexCounts['memo:naming'], 12);
      for (final h in heads) {
        expect(
          namingForTest(built, h),
          namingByScanForTest(scan, h),
          reason: h,
        );
      }
    });

    test('every corpus recipe: the per-head lookup (v29, Run 059 O9: the '
        "word index's scan, and the word index inverted) finds exactly the "
        'sentences `_names` finds, for every head of the recipe', () {
      var heads = 0;
      for (final f in Directory(corpusRecipesDir).listSync()) {
        if (!f.path.endsWith('.yaml')) continue;
        final r = loadCorpusRecipe(f.uri.pathSegments.last);
        final sentences = [
          for (final step in r.steps)
            step.text.toLowerCase().split(RegExp(r'(?<=\.)\s+')),
        ];
        for (final h in {
          ...wordHeadsForTest(r),
          for (final l in nutritionLines(r)) ...[
            normalizeItem(lineItemOf(l)),
            ?headNounOf(normalizeItem(lineItemOf(l))),
          ],
        }) {
          heads++;
          final expected = [
            for (final (i, step) in sentences.indexed)
              for (final (j, s) in step.indexed)
                if (namesForTest(s, h)) (i, j),
          ];
          expect(namingByScanForTest(r, h), expected, reason: '${r.id}: $h');
          expect(
            namingByInversionForTest(r, h),
            h.isNotEmpty && RegExp(r'^\w').hasMatch(h) ? expected : isEmpty,
            reason: '${r.id}: $h (inverted)',
          );
        }
      }
      expect(heads, greaterThan(10000));
    });

    test(
      'the compute of a cap recipe whose every line is matched (each '
      "line's detectors ask its head) builds its own inversion, once",
      () async {
        final db = wp.tempDb();
        final r = friedAtCaps(0);
        wp.saveRecipe(db, r);
        stepIndexCounts.clear();
        await matchAndCompute(
          db,
          _AllHits(),
          db.recipeByIdOrSlug(r.id)!.recipe,
        );
        expect(stepIndexCounts['memo:namingAll'], 1);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('the oil reach over 21 cap recipes: the reach of every one of '
        "0149's ten keys builds "
        'NONE (8 heads per reached recipe); the GET builds only the viewed '
        "recipe's two (its rows, the reach's copy read for its 400 keys) — "
        'v27/v28: one per reached recipe, 22; the apply-to-all none', () async {
      final db = wp.tempDb();
      final p = _NoHits();
      for (var k = 0; k < 21; k++) {
        final r = friedAtCaps(k);
        wp.saveRecipe(db, r);
        await matchAndCompute(db, p, db.recipeByIdOrSlug(r.id)!.recipe);
      }
      final stored = db.recipeByIdOrSlug('o0')!.recipe;
      final lines = nutritionLines(stored);
      final at = lines.indexWhere((l) => l.raw == _oil);
      // The oil key's reach alone: 20 recipes, each read for ONE line.
      stepIndexCounts.clear();
      final reach = decisionReach(
        db,
        lineKeyOf(lines[at]),
        excluding: (recipeId: stored.id, position: at),
      );
      expect(reach.map((row) => row.recipeId).toSet(), hasLength(20));
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
      expect(stepIndexCounts['memo:naming'], 40);
      // Every key 0149's lines share, one request's memo: 20 recipes each
      // read for its ten lines.
      stepIndexCounts.clear();
      final memo = ReachMemo();
      final own = nutritionLines(loadCorpusRecipe(_fried)).length;
      for (var i = 0; i < own; i++) {
        decisionReach(
          db,
          lineKeyOf(lines[i]),
          excluding: (recipeId: stored.id, position: i),
          memo: memo,
        );
      }
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
      expect(stepIndexCounts['memo:naming'], lessThanOrEqualTo(20 * own));
      // The GET: the viewed recipe's own rows and the reach's copy of it.
      stepIndexCounts.clear();
      var sw = Stopwatch()..start();
      await matchesBody(db, p, db.recipeByIdOrSlug('o0')!.recipe);
      expect(stepIndexCounts['memo:namingAll'], 2);
      expect(sw.elapsedMilliseconds, lessThan(backstopMs));
      // The apply-to-all on the oil line: one line per target recipe.
      stepIndexCounts.clear();
      sw = Stopwatch()..start();
      final applied = await applyMatchOverride(db, p, stored, at, {
        'raw': _oil,
        'fdc_id': 2710180,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (20, 20));
      expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
      expect(sw.elapsedMilliseconds, lessThan(backstopMs));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, skip: skipIfNoCorpus);

  group(
    'I4(a) the inversion reads each word AT the word (linear per sentence)',
    () {
      test('every corpus sentence: the same words as the v27 rescan, every '
          'word form wanted', () {
        var sentences = 0;
        for (final f in Directory(corpusRecipesDir).listSync()) {
          if (!f.path.endsWith('.yaml')) continue;
          final r = loadCorpusRecipe(f.uri.pathSegments.last);
          for (final step in r.steps) {
            for (final s in step.text.toLowerCase().split(
              RegExp(r'(?<=\.)\s+'),
            )) {
              sentences++;
              expect(
                wordsOfForTest(s, (_) => true).toSet(),
                wordsByRescan(s),
                reason: s,
              );
            }
          }
        }
        expect(sentences, greaterThan(20000));
      });

      test('seeded random texts of plurals, "-ies", "garlic " and word '
          'boundaries (synthesized: the forms the corpus may not hold)', () {
        const vocab = [
          'garlic',
          'clove',
          'cloves',
          'berry',
          'berries',
          'berr',
          'tomato',
          'tomatoes',
          'tomatos',
          'egg',
          'eggs',
          'egges',
          'turkey',
          'turkeys',
          'turkeies',
          'oil',
          'oils',
          'x_y',
          'a1',
          'ies',
          'y',
          'es',
          's',
          'garlics',
          'salt',
          'kosher',
        ];
        const seps = [' ', ', ', '-', '_', '.', '  ', "'", ' garlic '];
        final rng = Random(28028);
        for (var k = 0; k < 4000; k++) {
          final b = StringBuffer();
          for (var w = rng.nextInt(12) + 1; w > 0; w--) {
            b
              ..write(vocab[rng.nextInt(vocab.length)])
              ..write(seps[rng.nextInt(seps.length)]);
          }
          final s = '$b';
          expect(
            wordsOfForTest(s, (_) => true).toSet(),
            wordsByRescan(s),
            reason: s,
          );
        }
      });

      test('a sentence naming 60 wanted heads is read with no rescan per head '
          '(v27: 60 whole-sentence scans)', () {
        final heads = [for (var i = 0; i < 60; i++) 'z${tok(0)}${tok(i)}'];
        final s = 'stir the ${heads.join(', ')} into the pot.';
        namesScans = 0;
        expect(
          wordsOfForTest(s, heads.toSet().contains).toSet(),
          heads.toSet(),
        );
        expect(namesScans, 0);
      });
    },
    skip: skipIfNoCorpus,
  );

  group(
    "I4(b) O5/S10: the matches GET resolves each row's food ONCE",
    () {
      test("0857 with every matched line's grams typed: the GET reads each "
          "row's food once (and its nutrient record once where it has one) — "
          'v27: twice per typed row, three times on a food no cache holds; and '
          'with the flour gone from every cache, still once', () async {
        final (db, path) = a.pathDb();
        final fixture = FixtureProvider(pending: pendingSearches);
        final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
        await d.editAndCompute(db, fixture, r);
        final lines = nutritionLines(r);
        for (final (i, line) in lines.indexed) {
          if (d.rowOf(db, r, i).fdcId != null) {
            await applyMatchOverride(db, fixture, r, i, {
              'raw': line.raw,
              'grams': 100,
            });
          }
        }
        int expected() => [
          for (final row in db.ingredientMatchesFor(r.id))
            if (row.fdcId case final id?) nutrientSiblings[id] == null ? 1 : 2,
        ].fold(0, (s, n) => s + n);
        knownFoodReads = 0;
        await matchesBody(db, fixture, r);
        expect(knownFoodReads, expected());
        expect(expected(), greaterThan(10));
        // The flour leaves every cache: its row is resolved once all the same.
        dropFood(path, d.rowOf(db, r, d.at(r, a.flour0857)).fdcId!);
        knownFoodReads = 0;
        await matchesBody(db, fixture, r);
        expect(knownFoodReads, expected());
        // The derivation alone (the compute's, the PUT's): its typed fast
        // path and its decided food share ONE read (v27: two on a food no
        // cache holds).
        final i = d.at(r, a.flour0857);
        knownFoodReads = 0;
        final out = await derivedFor(
          db,
          FixtureProvider(
            pending: pendingSearches,
            superseded: {d.rowOf(db, r, i).fdcId!},
          ),
          r,
          i,
          lines[i],
          d.rowOf(db, r, i),
        );
        expect(out.row.hold, foodGoneHold);
        expect(knownFoodReads, 1);
      });
    },
    skip: skipIfNoCorpus,
  );

  group('I4(c) O6/S11: ONE request per FOOD per pass', () {
    test("400 typed rows (0148's first line to the caps) on one retired food: "
        'the compute asks FDC ONCE (v27: 400), every row held food_gone, '
        'fresh; the next compute asks nothing', () async {
      final base = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      final raw = nutritionLines(base).first.raw;
      final r = capped(base, List.filled(capLines, raw), [
        for (final st in base.steps) st.text,
      ]).copyWith(id: 'gone400', slug: 'gone-400');
      final db = wp.tempDb();
      wp.saveRecipe(db, r);
      final gone = FoodFault(_NoHits(), {poisoned}, gone: true);
      await matchAndCompute(db, gone, r);
      for (final (i, line) in nutritionLines(r).indexed) {
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: r.id,
            position: i,
            raw: line.raw,
            fdcId: poisoned,
            description: 'Retired food',
            dataType: 'SR Legacy',
            confidence: 1,
            grams: 10,
            gramSource: 'override',
            status: 'overridden',
            itemKey: lineKeyOf(line),
          ),
          layoutSeq: db.layoutSeqOf(r.id),
        );
      }
      expect(await computeUntilFresh(db, gone, r), 1);
      expect(gone.asked, 1);
      expect(
        db.ingredientMatchesFor(r.id).map((row) => row.hold).toSet(),
        {foodGoneHold},
      );
      expect(nutritionIsFresh(db, r), isTrue);
      await computeUntilFresh(db, gone, r);
      expect(gone.asked, 1);
    });

    test('100 napa rows (2727583) whose nutrient record 169979 is in no '
        'cache: the apply-to-all asks for the sibling ONCE while FDC fails '
        'it (every target `unavailable`, v28 rule A, left as they were); '
        'then, every line on napa and the record retired, the compute asks '
        'ONCE (v28 rule A without the pass: 100)', () async {
      final (db, path) = a.pathDb();
      final fixture = FixtureProvider(pending: pendingSearches);
      final r = wp.saveLines(db, List.filled(100, napa));
      await matchAndCompute(db, _NoHits(), r);
      dropFood(path, napaSibling);
      final down = FoodFault(fixture, {napaSibling});
      final applied = await applyMatchOverride(db, down, r, 0, {
        'raw': napa,
        'fdc_id': napaId,
        'apply_to_all': true,
      });
      expect((applied!.unavailable, applied.lines), (99, 0));
      expect(down.asked, 1);
      expect(
        db.ingredientMatchesFor(r.id).where((row) => row.fdcId == napaId),
        hasLength(1),
        reason: 'the targets were not weighed: left as they were',
      );
      // FDC up, every line takes napa; then the record is retired.
      final (db2, path2) = a.pathDb();
      final r2 = wp.saveLines(db2, List.filled(100, napa));
      await applyMatchOverride(db2, fixture, r2, 0, {
        'raw': napa,
        'fdc_id': napaId,
        'apply_to_all': true,
      });
      expect(
        db2.ingredientMatchesFor(r2.id).map((row) => row.fdcId).toSet(),
        {napaId},
      );
      dropFood(path2, napaSibling);
      final retired = FoodFault(fixture, {napaSibling}, gone: true);
      await matchAndCompute(db2, retired, r2);
      expect(retired.asked, 1);
    });
  }, skip: skipIfNoCorpus);

  group('I6 O11/S19: the Aho–Corasick occurrence index equals a scan per '
      'pattern', () {
    test("'kosher salt' beside 'salt', 'plus 2 tablespoons' beside "
        "'2 tablespoons' and 'tablespoons' (a pattern ending inside another: "
        'the dictionary and chain links)', () {
      const texts = [
        'dissolve the kosher salt and the salt in water.',
        'whisk in remaining 2 tablespoons oil, plus 2 tablespoons water.',
        'season with salt.',
        'no names here.',
      ];
      const patterns = [
        'kosher salt',
        'salt',
        'plus 2 tablespoons',
        '2 tablespoons',
        'tablespoons',
        'sugar',
      ];
      final got = occurrencesForTest(texts, patterns);
      expect(got, occurrencesByScan(texts, patterns));
      expect(got['salt'], [(0, 20), (2, 12)]);
      expect(got['kosher salt'], [(0, 13)]);
      expect(got['2 tablespoons'], [(1, 19)]);
      expect(got['plus 2 tablespoons'], [(1, 38)]);
      expect(got.containsKey('sugar'), isFalse);
    });

    test('seeded random texts over a small alphabet, overlapping and nested '
        'patterns (synthesized: the failure, dictionary and chain links each '
        'exercised)', () {
      final rng = Random(5811);
      String word(int n) => String.fromCharCodes([
        for (var i = 0; i < n; i++) 97 + rng.nextInt(3),
      ]);
      for (var k = 0; k < 3000; k++) {
        final texts = [
          for (var t = rng.nextInt(4) + 1; t > 0; t--)
            [
              for (var w = rng.nextInt(8); w >= 0; w--) word(rng.nextInt(6)),
            ].join(' '),
        ];
        final patterns = {
          for (var p = rng.nextInt(6) + 2; p > 0; p--) word(rng.nextInt(4) + 1),
        };
        expect(
          occurrencesForTest(texts, patterns),
          occurrencesByScan(texts, patterns),
          reason: '$texts $patterns',
        );
      }
    });

    test("every corpus recipe's steps, every line's item and head noun as "
        "the patterns (the dissolve and plus readers' searched names)", () {
      var recipes = 0;
      for (final f in Directory(corpusRecipesDir).listSync()) {
        if (!f.path.endsWith('.yaml')) continue;
        final r = loadCorpusRecipe(f.uri.pathSegments.last);
        final texts = [for (final st in r.steps) st.text.toLowerCase()];
        final patterns = {
          for (final line in nutritionLines(r)) ...[
            normalizeItem(lineItemOf(line)),
            ?headNounOf(normalizeItem(lineItemOf(line))),
          ],
        }..remove('');
        expect(
          occurrencesForTest(texts, patterns),
          occurrencesByScan(texts, patterns),
          reason: f.path,
        );
        recipes++;
      }
      expect(recipes, greaterThan(1000));
    });
  }, skip: skipIfNoCorpus);

  group("I6 O12/S22: migration 015's stored totals, read back after two "
      'rebases', () {
    test('0857 computed at its basis, rebased 12 → 13 → 14 → 12: every '
        'nutrient is the STORED unrounded totals over the basis (never the '
        "rounded label times the old basis, never '{}'), the totals kept "
        'as stored, and the round trip lands the first label', () async {
      final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      final db = wp.tempDb();
      wp.saveRecipe(db, r);
      await matchAndCompute(db, FixtureProvider(pending: pendingSearches), r);
      final first = db.nutritionFor(r.id)!;
      expect(first.servingBasis, 12);
      expect(first.totalsJson, isNotNull);
      final totals = {
        for (final MapEntry(:key, :value)
            in (jsonDecode(first.totalsJson!) as Map<String, dynamic>).entries)
          key: (value as num).toDouble(),
      };
      expect(totals.length, greaterThan(10));
      var computedAt = first.computedAt;
      for (final basis in [13, 14]) {
        rebaseNutrition(db, r.id, basis);
        final now = db.nutritionFor(r.id)!;
        expect(now.servingBasis, basis);
        // `computed_at` moves on every nutrition write (the review queue's
        // fingerprint reads it; Run 058 O17(e)).
        expect(now.computedAt, isNot(computedAt));
        computedAt = now.computedAt;
        expect(jsonDecode(now.totalsJson!), totals);
        final label = jsonDecode(now.nutrientsJson) as Map<String, dynamic>;
        expect(label.keys.toSet(), totals.keys.toSet());
        for (final MapEntry(:key, :value) in totals.entries) {
          expect(
            (label[key] as Map<String, dynamic>)['amount'],
            double.parse((value / basis).toStringAsFixed(2)),
            reason: '$key at $basis',
          );
        }
        expect(
          now.caloriesPerServing,
          double.parse((totals['energy']! / basis).toStringAsFixed(2)),
        );
      }
      rebaseNutrition(db, r.id, 12);
      expect(db.nutritionFor(r.id)!.nutrientsJson, first.nutrientsJson);
    });
  }, skip: skipIfNoCorpus);

  group('I6 named gaps (Run 058 O14, S25, O17, S24)', () {
    test("S24: a recipe deleted during its compute's awaits ends the passes "
        '(the pass gate reads no deleted recipe; synthesized: the delete '
        "inside the compute's first search)", () async {
      final db = wp.tempDb();
      final r = loadCorpusRecipe(_fried);
      wp.saveRecipe(db, r);
      var deleted = false;
      final p = _DeleteOnSearch(() {
        if (!deleted) {
          deleted = db.deleteRecipe(r.id);
        }
      });
      expect(await computeUntilFresh(db, p, r), 1);
      expect(deleted, isTrue);
      expect(db.recipeByIdOrSlug(r.id), isNull);
    });

    /// A decided row on [line] of [r] for [poisoned] (no cache holds it).
    IngredientMatchRow decided(
      Recipe r,
      IngredientLine line, {
      required String raw,
      String status = 'confirmed',
      String? hold,
      double? grams,
      bool typed = false,
    }) => IngredientMatchRow(
      recipeId: r.id,
      position: nutritionLines(r).indexOf(line),
      raw: raw,
      fdcId: poisoned,
      description: 'Retired food',
      dataType: 'SR Legacy',
      confidence: 1,
      grams: grams,
      gramSource: typed ? 'override' : null,
      status: status,
      hold: hold,
      itemKey: lineKeyOf(line),
    );

    test("O17(a): FDC failing the decided food, a person's row keeps its "
        'LINE hold — in_shell and second_food as much as a medium hold '
        '(synthesized: the hold on a decided row of 0149, the retired id, '
        'the failure)', () async {
      final r = loadCorpusRecipe(_fried);
      final line = nutritionLines(r).first;
      final down = FoodFault(_NoHits(), {poisoned});
      for (final hold in ['in_shell', 'second_food', 'coating']) {
        final out = await derivedFor(
          wp.tempDb(),
          down,
          r,
          0,
          line,
          decided(r, line, raw: line.raw, hold: hold),
        );
        expect(out.unavailable, isNotNull);
        expect(out.row.hold, hold);
      }
    });

    test('O17(b): FDC failing, a SKIP whose typed grams sit on a frying oil '
        "line an amount edit carried keeps them (0149's oil: a medium by the "
        'food-free reading) (synthesized: the typed 77 g, the old '
        'amount)', () async {
      final r = loadCorpusRecipe(_fried);
      final oil = lineOf(r, _oil);
      expect(
        discardedMediumOf(r, oil, normalizeItem(lineItemOf(oil))),
        isNotNull,
      );
      final down = FoodFault(_NoHits(), {poisoned});
      final kept = await derivedFor(
        wp.tempDb(),
        down,
        r,
        nutritionLines(r).indexOf(oil),
        oil,
        decided(
          r,
          oil,
          raw: '2 cups vegetable oil',
          status: 'skipped',
          grams: 77,
          typed: true,
        ),
      );
      expect((kept.unavailable != null, kept.row.grams), (true, 77));
    });

    test("O14: a brine item whose first occurrence sits inside the salt's own "
        "mention ('salt' in 'the kosher salt') and recurs after it: the "
        'kosher salt is dissolved with the brine salt — synthesized lines '
        'and step (the corpus writes no such sentence)', () {
      const brineStep =
          'Dissolve the kosher salt and the salt in 4 quarts cold water in '
          'large container. Submerge chicken in brine, cover, and '
          'refrigerate for 1 hour.';
      final r = capped(
        loadCorpusRecipe(_fried),
        [
          '½ cup salt',
          '1 teaspoon kosher salt',
        ],
        [brineStep],
      );
      for (final line in nutritionLines(r)) {
        expect(
          discardedMediumOf(r, line, normalizeItem(lineItemOf(line))),
          DiscardedMedium.brine,
          reason: line.raw,
        );
      }
    });

    test('S25: a head of non-word characters is scanned for alone, never '
        'read off the inversion (which holds word heads only): '
        "'half-and-half' after the inversion is built (synthesized lines and "
        'steps)', () {
      // At the caps (0149's padding), so reading every head pays for the
      // inversion (v28 closer: a small recipe never builds it).
      final padded = friedAtCaps(0);
      final r = capped(
        padded,
        [
          '1 cup half-and-half',
          '1¾ cups vegetable oil',
          '3 cups unbleached all-purpose flour',
          for (final l in nutritionLines(padded)) ...[
            if (l.raw.startsWith('1 cup z')) l.raw,
          ],
        ].take(capLines).toList(),
        [
          'Whisk the half-and-half and the flour together.',
          'Heat the oil to 350 degrees.',
          for (final st in padded.steps.skip(2)) st.text,
        ],
      );
      stepIndexCounts.clear();
      for (final h in wordHeadsForTest(r)) {
        namingForTest(r, h);
      }
      expect(stepIndexCounts['memo:namingAll'], 1);
      expect(namingForTest(r, 'oil'), isNotEmpty);
      expect(namingForTest(r, 'half-and-half'), [(0, 0)]);
    });
  }, skip: skipIfNoCorpus);

  group('I5 O18/S28: a run of twins is laid out in its own order', () {
    // Run 058 O18's repro, as the gap oracle's seed 41487 saved it (the
    // oracle's lines and its synthesized decisions: stated exceptions).
    const pec = 'Grated Pecorino Romano cheese';
    const salt = '2 teaspoon salt';
    const oil = '1 cup extra-virgin olive oil';
    IngredientLine parsed(String raw) {
      final p = parseIngredientLine(raw);
      return IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
    }

    IngredientMatchRow row(int pos, String raw, String tok) =>
        IngredientMatchRow(
          recipeId: 'r',
          position: pos,
          raw: raw,
          fdcId: tok.startsWith('P') ? 173468 : null,
          description: null,
          dataType: null,
          confidence: 0.9,
          grams: tok.startsWith('P') ? double.parse(tok.substring(2)) : null,
          gramSource: null,
          status: tok == 'S'
              ? 'skipped'
              : tok.startsWith('P')
              ? 'overridden'
              : 'auto',
          itemKey: lineKeyOf(parsed(raw)),
        );

    test('seed 41487: the save of three edits on fourteen lines (eleven '
        'twins) ends inside the budget (v27: 10,000, the cap; 39,789 '
        "unbounded) with the exact layout — the deleted salt's pick "
        'dropped, P:1006 on its own line', () {
      const before = [
        (pec, 'P:1007'),
        (salt, '-'),
        (pec, 'P:1006'),
        (pec, '-'),
        (pec, '-'),
        (salt, 'P:1003'),
        (pec, 'S'),
        (pec, 'P:1009'),
        (oil, 'P:1005'),
        (pec, '-'),
        (pec, '-'),
        (pec, 'P:1010'),
        (pec, '-'),
        (pec, '-'),
      ];
      final rows = [for (final (i, (t, k)) in before.indexed) row(i, t, k)];
      final laid = [for (final (t, _) in before) t];
      final after = [
        pec,
        pec,
        pec,
        salt,
        pec,
        pec,
        pec,
        pec,
        pec,
        oil,
        pec,
        pec,
        pec,
        pec,
      ].map(parsed).toList();
      final got = pairRowsToLines(rows, after, laidOut: laid);
      // The count, not only the cap (measured 4,916: each half of the
      // twin rule — the run order and the bound that reads it — is needed;
      // v29, a run ONE item: 2,760).
      expect(pairingExpansions, lessThanOrEqualTo(3000));
      expect(
        [for (final r in got) r?.position],
        [0, null, 9, 1, 2, 3, 4, 6, 7, 8, 10, 11, 12, 13],
      );
    });
  });
}
