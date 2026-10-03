// Run 057 I4 (matcher v27, RULE C — the index is paid by the caller that
// amortises it; bounds that bind): the shapes that make every bound BIND
// (Run 057 S4/S12/S7/O9/S8/O7) — distinct dissolved salts beside distinct
// brine salts, real "plus" parts with distinct amounts, a dredge whose
// lines each write a distinct amount a step also writes, identical frying
// oils with a pour-off, and a reach over many cap recipes each read for
// ONE line — each pinned by COUNT (a memo per call, a pair loop or a
// per-name scan fails a count, never only a clock); each clock is a
// backstop at least 5× the measured tree (Run 057 O12).
//
// Real corpus recipes (0241 Garlic-Studded Roast Pork Loin, 0148 Crispy
// Fried Chicken) with recorded FDC answers (FixtureProvider), never the
// network. Synthesized, a stated exception: the hostile lines and steps put
// in them at the editor caps (negative-path cost inputs no corpus recipe
// holds — the Run 057 digests' shapes).
// ignore_for_file: lines_longer_than_80_chars
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show readAll;
import 'nutrition_v26_cost_test.dart'
    show capLines, capStep, capSteps, capped, chicken, pork;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

/// A distinct word of letters only (a head the naming index reads by word).
String tok(int i) {
  const a = 'abcdefghijklmnopqrstuvwxyz';
  return 'q${a[i % 26]}${a[(i ~/ 26) % 26]}${a[(i ~/ 676) % 26]}';
}

/// 120 steps of [sentence]s at the step cap, [first] first.
List<String> steps(String first, String Function(int) sentence) {
  var k = 0;
  String step() {
    final b = StringBuffer();
    while (true) {
      final s = sentence(k);
      if (b.length + s.length > capStep) {
        return '$b';
      }
      b.write(s);
      k++;
    }
  }

  return [first, for (var i = 1; i < capSteps; i++) step()];
}

/// Each binding shape at the caps, made afresh (a cold index).
final Map<String, Recipe Function()> shapes = {
  // S12: 200 distinct brine salts by volume beside 199 distinct small
  // salts, ~1,000-character sentences dissolving ~90 small salts each —
  // v26: memo:dissolvedWith 200 × 199, 104 s a GET.
  'dissolve-distinct': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < 200; i++) '1/4 cup ${tok(1000 + i)} salt',
      for (var i = 0; i < 199; i++) '1 teaspoon ${tok(i)} salt',
    ],
    steps(
      'Dissolve the salt in 2 quarts water; submerge the pork in the brine.',
      (k) => k % 90 == 89
          ? '${tok(k % 199)} salt in the water. '
          : '${k % 90 == 0 ? 'Dissolve ' : ''}${tok(k % 199)} salt, ',
    ),
  ),
  // S4: 200 '1 cup salt for brine<i>' beside 200 '1 teaspoon salt for
  // small<i>', sentences dissolving the small ones — v26: 200 × 200.
  'dissolve-for': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < 200; i++) '1 cup salt for brine$i',
      for (var i = 0; i < 199; i++) '1 teaspoon salt for small$i',
    ],
    steps(
      'Submerge the pork in the brine with the salt.',
      (k) => k % 40 == 0
          ? 'Dissolve the salt for small${k % 199} for small${(k + 1) % 199}. '
          : 'for small${k % 199} ',
    ),
  ),
  // S7: 400 REAL plus parts (no ", for frying" tail), each a distinct
  // amount, a quarter of them written in a step beside the oil.
  'plus-real': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines; i++)
        '2 cups plus ${101 + i} teaspoons vegetable oil',
    ],
    steps(
      'Heat the oil to 350 degrees and fry the pork.',
      (k) => 'Stir ${101 + (k % 100) * 4} teaspoons oil into the sauce. ',
    ),
  ),
  // O9/S8: 399 dredge flour lines each writing a distinct amount a step
  // also writes, among 46,000 distinct written amounts.
  'eaten-distinct': () {
    var n = 1;
    return capped(
      loadCorpusRecipe(chicken),
      [
        for (var i = 0; i < capLines - 1; i++)
          '${i + 1} cups all-purpose flour',
        '1 teaspoon salt',
      ],
      steps(
        'Heat the oil to 350 degrees. Dredge the pork in the flour. Fry.',
        (_) => 'Stir ${n++} cups flour in. ',
      ),
    );
  },
  // keptOil: 398 identical frying oils, a pour-off keeping a part.
  'kept-oil': () => capped(
    loadCorpusRecipe(pork),
    [
      for (var i = 0; i < capLines - 2; i++) '3 cups vegetable oil',
      '1 tablespoon olive oil',
      '1 teaspoon salt',
    ],
    steps(
      'Heat the vegetable oil to 350 degrees and fry the pork. '
      'Carefully pour off all but 2 tablespoons oil from pan.',
      (_) => 'Stir 1 tablespoon oil into the sauce. ',
    ),
  ),
};

/// Every line's [engineOutcome] on [food] — the compute's per-line read
/// with a food, which [readAll] (no food) never reaches: the eaten plus
/// part ([plusPartOf]) and the kept frying oil.
void readOutcomes(Recipe r, FdcFood food) {
  for (final line in nutritionLines(r)) {
    engineOutcome(
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
  }
}

/// O7's reach shape (recipe [k] of a library): 399 distinct one-word heads
/// of its own — distinct per recipe, so only line 0, '1 cup garlic', is
/// reached from another recipe — and 120 cap steps naming them all.
Recipe reachShape(int k) {
  final ws = [for (var i = 0; i < capLines - 1; i++) 'z${tok(k)}${tok(i)}'];
  final sentences = [
    for (var i = 0; i < ws.length; i += 60)
      'Stir the ${ws.sublist(i, (i + 60).clamp(0, ws.length)).join(', ')} into the pot. ',
  ].join();
  final step = (sentences * 20).substring(0, capStep);
  return capped(loadCorpusRecipe(pork), [
    '1 cup garlic',
    for (final w in ws) '1 cup $w',
  ], List.filled(capSteps, step)).copyWith(id: 'reach$k', slug: 'reach-$k');
}

/// Recorded answers, every search answering nothing: every line
/// unmatched, so the reach reaches every same-key row.
class _NoHits extends FixtureProvider {
  _NoHits() : super(pending: pendingSearches);
  @override
  Future<List<FdcCandidate>> search(String q) async => const [];
}

/// The vegetable oil food the recorded answers hold (FDC 2710180).
Future<FdcFood> oil() async => (await FixtureProvider().food(2710180))!;

void main() {
  group('RULE C bounds that BIND (Run 057 S4/S12/S7/O9/S8)', () {
    for (final shape in shapes.keys) {
      test('$shape: every family within its bound with a food and without, '
          'within the backstop', () async {
        final food = await oil();
        final r = shapes[shape]!();
        stepIndexCounts.clear();
        final sw = Stopwatch()..start();
        readAll(r);
        readOutcomes(r, food);
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        expectBounded(r, counts, shape);
        expect(counts['indexes'], 1);
        expect(ms, lessThan(backstopMs), reason: '$shape: $counts');
      });
    }

    test("O9/S8: the dredge's eaten order and the kept oil derived once per "
        'head and medium (per text) — a per-call memo derives 399 / 398 '
        'against bounds of 24 / 27', () async {
      for (final shape in ['eaten-distinct', 'kept-oil']) {
        final r = shapes[shape]!();
        stepIndexCounts.clear();
        readAll(r);
        readOutcomes(r, await oil());
        final family = shape == 'kept-oil' ? 'memo:keptOil' : 'memo:eatenOrder';
        expect(stepIndexCounts[family], 1, reason: shape);
      }
    });

    test('O9: the eaten-distinct dredge end to end with recorded answers '
        '(the lines matched, so every engine read runs): the compute and '
        'the matches GET, each family within its bound per index', () async {
      final r = shapes['eaten-distinct']!();
      final db = wp.tempDb();
      wp.saveRecipe(db, r);
      final provider = FixtureProvider(pending: pendingSearches);
      for (final (name, run) in <(String, Future<Object?> Function())>[
        (
          'compute',
          () =>
              matchAndCompute(db, provider, db.recipeByIdOrSlug(r.id)!.recipe),
        ),
        (
          'GET',
          () => matchesBody(db, provider, db.recipeByIdOrSlug(r.id)!.recipe),
        ),
      ]) {
        stepIndexCounts.clear();
        reachDecodes = 0;
        final sw = Stopwatch()..start();
        await run();
        final ms = sw.elapsedMilliseconds;
        final counts = Map.of(stepIndexCounts);
        expectBounded(r, counts, name, copies: counts['indexes'] ?? 1);
        expect(
          counts['memo:eatenOrder'],
          lessThanOrEqualTo(counts['indexes']!),
          reason: name,
        );
        expect(ms, lessThan(backstopMs), reason: name);
      }
    });

    test('S4/S12/S7: one inverted index per recipe for the dissolved salts '
        'and the plus amounts — every text read once, every salt answered '
        'once', () async {
      for (final (shape, index) in [
        ('dissolve-distinct', 'memo:dissolveIndex'),
        ('dissolve-for', 'memo:dissolveIndex'),
        ('plus-real', 'memo:plusIndex'),
      ]) {
        final r = shapes[shape]!();
        stepIndexCounts.clear();
        readAll(r);
        readOutcomes(r, await oil());
        final c = Map.of(stepIndexCounts);
        expect(c[index], 1, reason: shape);
        expect(c['memo:dissolvingWith'] ?? 0, 0, reason: shape);
        // The first plus line scans for its own names alone (at most its
        // three: its plus lead, its written lead, its head); the second
        // builds the index (the closer's D11, as `namingAll`).
        expect(
          c['memo:plusSteps'] ?? 0,
          shape == 'plus-real' ? lessThanOrEqualTo(3) : 0,
          reason: shape,
        );
        expect(
          c['occurrenceScans'],
          shape == 'plus-real'
              ? lessThanOrEqualTo(4 * capSteps)
              : lessThanOrEqualTo(c['sentences']!),
          reason: shape,
        );
        expect(
          c['memo:dissolvedWith'] ?? 0,
          lessThanOrEqualTo(capLines),
          reason: '$shape: once per salt, never per (salt, brine item)',
        );
      }
    });
  }, skip: skipIfNoCorpus);

  group(
    'RULE C: the naming inversion paid by its amortiser (Run 057 O7)',
    () {
      test(
        'a one-line reader of a plus line scans for its own names: '
        "plus-real's first line read alone builds no plus index (at most "
        'its three names, each one native scan of the steps); a second '
        "line builds it (the closer's D11: the PUT paid the whole index)",
        () async {
          final r = shapes['plus-real']!();
          final food = await oil();
          void read(IngredientLine line) => engineOutcome(
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
          stepIndexCounts.clear();
          read(nutritionLines(r).first);
          expect(stepIndexCounts['memo:plusIndex'] ?? 0, 0);
          expect(stepIndexCounts['memo:plusSteps'], inInclusiveRange(1, 3));
          expect(
            stepIndexCounts['occurrenceScans'],
            lessThanOrEqualTo(3 * capSteps),
          );
          read(nutritionLines(r)[1]);
          expect(stepIndexCounts['memo:plusIndex'], 1);
        },
      );

      test('a one-line reader scans for its one head; the inversion is '
          'built once the per-head scans paid reach its cost (v28 closer: '
          'measured, not the second head)', () {
        final r = reachShape(0);
        stepIndexCounts.clear();
        heldMediumLine(r, weighedLine(r, nutritionLines(r).first));
        expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
        expect(stepIndexCounts['memo:naming'], 1);
        heldMediumLine(r, weighedLine(r, nutritionLines(r)[1]));
        expect(stepIndexCounts['memo:namingAll'] ?? 0, 0);
        expect(stepIndexCounts['memo:naming'], 2);
        for (final line in nutritionLines(r)) {
          heldMediumLine(r, weighedLine(r, line));
        }
        expect(stepIndexCounts['memo:namingAll'], 1);
        // Each filler head is in every step, so each scan reads the text
        // and its sentences: built within the first few dozen heads.
        expect(stepIndexCounts['memo:naming'], lessThan(40));
      });

      test('the matches GET over a reach of 3 cap recipes, and the '
          'apply-to-all: each reached recipe read for ONE line builds no '
          'inversion (v26: one per reached recipe, 7.1 s / 13.9 s at 39 '
          'reached rows)', () async {
        final db = wp.tempDb();
        final provider = _NoHits();
        for (var k = 0; k < 4; k++) {
          final r = reachShape(k);
          wp.saveRecipe(db, r);
          await matchAndCompute(
            db,
            provider,
            db.recipeByIdOrSlug(r.id)!.recipe,
          );
        }
        final stored = db.recipeByIdOrSlug('reach0')!.recipe;
        for (final (name, run) in <(String, Future<Object?> Function())>[
          ('GET', () => matchesBody(db, provider, stored)),
          (
            'apply-to-all',
            () => applyMatchOverride(db, provider, stored, 0, {
              'raw': '1 cup garlic',
              'fdc_id': 173468,
              'apply_to_all': true,
            }),
          ),
        ]) {
          stepIndexCounts.clear();
          reachDecodes = 0;
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          // The GET's reach decodes the 3 others and the request's own recipe
          // (its rows are reached too: position -1 excludes none); the apply
          // then reads the holds by version, and decodes each target it
          // weighs.
          if (name == 'GET') {
            expect(reachDecodes, 4);
          }
          // The inversion: the request's own recipe, and the reach's copy of
          // it (read for every line's key) — never a recipe reached for one
          // line (v26: 2 + 3).
          expect(
            stepIndexCounts['memo:namingAll'] ?? 0,
            lessThanOrEqualTo(2),
            reason: name,
          );
          expect(ms, lessThan(backstopMs), reason: name);
        }
      });
    },
    skip: skipIfNoCorpus,
  );
}
