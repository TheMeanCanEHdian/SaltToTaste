// RULE C, matcher v29 (brief I3 — Run 059 O9, O12/S12/S14, O21): a cost
// unit IS the cost. The per-head scan is an exact-cost lookup over a
// per-step word index (every word's start and key, built once, O(text));
// a scan pays the words it visits (and a confirm's characters), counted
// EXACTLY as `namingPaid`; the inversion is the word index inverted, built
// when the paid scans reach 12 × the words (the constant measured on these
// units). The pairing's twin runs are pinned in the pairing section below.
//
// Real corpus recipes (0149 Easier Fried Chicken, 0241 Garlic-Studded
// Roast Pork Loin) and their real lines and steps. Synthesized, each a
// stated exception: Run 059 O9's shared-prefix shape at the editor caps
// (400 lines of one-word heads of 38 z's and a tag, 120 steps of words of
// 38 z's and "qq" — the words a head's prefix shares, which the corpus
// never writes); Run 059 O21's heads no step names (60 tokens on 0241);
// seeded random texts and heads over a small alphabet (plurals, "-ies",
// "garlic ", hyphens, digits, underscores, sentence breaks — the forms
// the corpus may not hold); two words of one key (a hash collision,
// searched for, never assumed).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:math';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v26_cost_test.dart' show capped, ln, pork;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';

const _fried = '0149-easier-fried-chicken.yaml';

/// Run 059 O9's shape: 400 one-word heads of [len] characters (len − 2 z's
/// and a two-letter tag) and 120 steps at the 10,000-character cap whose
/// words are len − 2 z's and "qq" (each sentence under 1,000 characters).
Recipe sharedPrefix(int len, [int k = 0]) {
  final base = loadCorpusRecipe(_fried);
  final prefix = 'z' * (len - 2);
  String tag(int i) =>
      '${String.fromCharCode(97 + i % 26)}${String.fromCharCode(97 + (i ~/ 26) % 26)}';
  final sentence =
      'Stir ${List.filled(880 ~/ (len + 1), '${prefix}qq').join(' ')} in. ';
  final step = (sentence * (10000 ~/ sentence.length + 1)).substring(0, 10000);
  return base.copyWith(
    id: 'o9-$len-$k',
    slug: 'o9-$len-$k',
    ingredients: [
      IngredientGroup(
        items: [for (var i = 0; i < 400; i++) ln('1 cup $prefix${tag(i)}')],
      ),
    ],
    steps: [
      for (var i = 0; i < 120; i++) RecipeStep(number: i + 1, text: step),
    ],
  );
}

/// The words of [r]'s steps as `\w+` reads them (the reference count).
int wordsOf(Recipe r) => [
  for (final s in r.steps) ...RegExp(r'\w+').allMatches(s.text.toLowerCase()),
].length;

/// What a head's confirms cost: its forms' characters (`_formsOf`).
int confirmOf(String head) =>
    (head.endsWith('y')
            ? [head, '${head.substring(0, head.length - 1)}ies']
            : [head, '${head}s', '${head}es'])
        .fold(0, (n, f) => n + f.length);

/// How many words of [r]'s steps a word-only [head]'s scan confirms: those
/// spelling one of its forms (the reference, by `\w+`).
int keyHitsOf(Recipe r, String head) {
  final forms = head.endsWith('y')
      ? {head, '${head.substring(0, head.length - 1)}ies'}
      : {head, '${head}s', '${head}es'};
  return [
    for (final s in r.steps)
      ...RegExp(r'\w+').allMatches(s.text.toLowerCase()).map((m) => m[0]),
  ].where(forms.contains).length;
}

void main() {
  group('I3(a) O9: the per-head scan is an exact-cost lookup', () {
    for (final len in [40, 900]) {
      test(
        'Run 059 O9 at $len-character heads: a whole-recipe read scans 12 '
        'heads, each paying exactly the words it visits (no word confirms), '
        'then builds the inversion once; fd34433 104–110 ms (40) and '
        '494–505 ms (900), v28 420–428 / 484–488, v29 64–87 / 463–471 '
        '(fix29/rulec/o9bench.dart)',
        () {
          final r = sharedPrefix(len);
          final words = wordsOf(r);
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          for (final l in nutritionLines(r)) {
            discardedMediumOf(r, l, normalizeItem(lineItemOf(l)));
            heldMediumLine(r, l);
          }
          expect(sw.elapsedMilliseconds, lessThan(backstopMs));
          expect(wordCountForTest(r), words);
          expect(stepIndexCounts['words'], words);
          expect(stepIndexCounts['memo:naming'], 12);
          expect(stepIndexCounts['memo:namingAll'], 1);
          // The units ARE the words visited: twelve scans of every word.
          expect(namingPaidForTest(r), 12 * words);
          expect(stepIndexCounts['namingReads'] ?? 0, 0);
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: skipIfNoCorpus,
      );
    }

    test("0149's real heads: each scan pays the words plus, per word "
        "spelling one of the head's forms, the forms' characters — EXACTLY "
        r'(the reference counts by `\w+`)', () {
      final r = loadCorpusRecipe(_fried);
      final words = wordsOf(r);
      final heads = wordHeadsForTest(r).toList();
      var expected = 0;
      for (final h in heads) {
        namingByScanForTest(r, h);
        expected += words + keyHitsOf(r, h) * confirmOf(h);
        expect(namingPaidForTest(r), expected, reason: h);
      }
      expect(heads.where((h) => keyHitsOf(r, h) > 0), isNotEmpty);
    }, skip: skipIfNoCorpus);

    test('Run 059 O21: the `<` boundary — 0241 re-lined with 60 heads no '
        'step names: each scan pays exactly the words, so the twelfth '
        'lands ON 12 × the words and is the last; the thirteenth head '
        'builds the inversion (`<=` would scan it too)', () {
      final base = loadCorpusRecipe(pork);
      String tok(int i) =>
          String.fromCharCodes([113, 122, 97 + i % 26, 97 + i ~/ 26]);
      final r = capped(
        base,
        [
          for (var i = 0; i < 60; i++) '1 cup ${tok(i)}',
        ],
        ['Stir everything together in a bowl until smooth.'],
      ).copyWith(id: 'o21', slug: 'o21');
      stepIndexCounts.clear();
      for (final line in nutritionLines(r)) {
        heldMediumLine(r, weighedLine(r, line));
      }
      expect(stepIndexCounts['memo:naming'], 12);
      expect(stepIndexCounts['memo:namingAll'], 1);
      expect(namingPaidForTest(r), 12 * wordsOf(r));
    }, skip: skipIfNoCorpus);
  });

  group('I3(a) the lookup answers as `_names` does', () {
    test('seeded random texts and heads (2,000 seeds): the scan and the '
        'inversion find exactly the sentences `_names` finds — plurals, '
        '"-ies", "garlic ", hyphenated and digit heads, heads opening on no '
        'word character, sentence breaks of every width', () {
      const tokens = [
        'oil', 'oils', 'oiles', 'Oil', 'berry', 'berries', 'berrys', //
        'garlic', 'clove', 'cloves', 'a-b', 'a', 'b', 'x_y', 'x', 'y', //
        '12', '1', 'half-and-half', 'half', 'and', '%', '-', '_', 'an', 'c0',
      ];
      const gaps = [
        ' ',
        ' ',
        ' ',
        ', ',
        '-',
        '.',
        '. ',
        '.  ',
        '.\n',
        ' (',
        ') ',
        '_',
      ];
      const heads = [
        'oil', 'oils', 'berry', 'berrie', 'clove', 'garlic', 'a-b', 'a', //
        'b', 'x_y', 'x', '12', '1', 'half-and-half', 'half', 'and', 'oi', //
        '-x', '%', 'a-', 'b.', 'y', 'x y', 'garlic oil', 'an', 'c0', '-', //
        'b. x', 'x.', 'oil.  half',
      ];
      final base = loadCorpusRecipe(pork);
      var found = 0;
      for (var seed = 0; seed < 2000; seed++) {
        final rnd = Random(seed);
        String step() => [
          for (var i = 0; i < 40; i++)
            '${tokens[rnd.nextInt(tokens.length)]}${gaps[rnd.nextInt(gaps.length)]}',
        ].join();
        final steps = [step(), step(), step()];
        final r = base.copyWith(
          id: 'rnd$seed',
          steps: [
            for (final (i, t) in steps.indexed)
              RecipeStep(number: i + 1, text: t),
          ],
        );
        for (final h in heads) {
          final expected = [
            for (final (i, t) in steps.indexed)
              for (final (j, s)
                  in t.toLowerCase().split(RegExp(r'(?<=\.)\s+')).indexed)
                if (namesForTest(s, h)) (i, j),
          ];
          found += expected.length;
          expect(namingByScanForTest(r, h), expected, reason: '$seed: $h');
          expect(
            namingByInversionForTest(r, h),
            RegExp(r'^\w').hasMatch(h) ? expected : isEmpty,
            reason: '$seed: $h (inverted)',
          );
        }
      }
      expect(found, greaterThan(100000));
    });

    test('two words of ONE key ("c0" and "an": 31 × 99 + 48 = 31 × 97 + '
        '110, the key restated and the collision searched for) never name '
        'each other: the key that agrees is confirmed at the word, and the '
        "confirm's characters are paid", () {
      final r = capped(
        loadCorpusRecipe(pork),
        [
          '1 cup an',
        ],
        ['Stir the c0 into the pot.'],
      ).copyWith(id: 'c0', slug: 'c0');
      expect(namingByScanForTest(r, 'an'), isEmpty);
      expect(namingPaidForTest(r), wordsOf(r) + confirmOf('an'));
      expect(namingByInversionForTest(r, 'an'), isEmpty);
      expect(namingByScanForTest(r, 'c0'), [(0, 0)]);
    }, skip: skipIfNoCorpus);
  }, skip: skipIfNoCorpus);

  group('I3(b) O12/S12/S14: a run of twins is ONE item', () {
    const acqua = '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml';
    late Map<String, IngredientLine> real;
    setUpAll(() {
      real = {
        for (final l in nutritionLines(loadCorpusRecipe(acqua))) l.raw: l,
      };
    });
    const salt = 'Salt and pepper';
    const oil = '½ cup extra-virgin olive oil';
    const oilQuarter = '¼ cup extra-virgin olive oil';
    const pec = 'Grated Pecorino Romano cheese';
    // A row laid out at [pos] on [raw]: a pick with distinct typed grams
    // ([grams]), a skip ('S') or none.
    IngredientMatchRow row(int pos, String raw, [Object? grams]) =>
        IngredientMatchRow(
          recipeId: 'r',
          position: pos,
          raw: raw,
          fdcId: grams is num ? 173468 : null,
          description: null,
          dataType: null,
          confidence: 0.9,
          grams: grams is num ? grams.toDouble() : null,
          gramSource: grams is num ? 'override' : null,
          status: grams is num
              ? 'overridden'
              : grams == 'S'
              ? 'skipped'
              : 'auto',
          itemKey: lineKeyOf(real[raw]!),
        );

    final shapes = <String, (List<String>, List<int?>)>{
      'replace0': (
        [oil, ...List.filled(399, salt)],
        [null, for (var i = 1; i < 400; i++) i],
      ),
      'delete0': (List.filled(399, salt), [for (var i = 0; i < 399; i++) i]),
      'insert0': (
        [oil, ...List.filled(400, salt)],
        [null, for (var i = 0; i < 400; i++) i],
      ),
      'replaceMid': (
        [...List.filled(200, salt), oil, ...List.filled(199, salt)],
        [
          for (var i = 0; i < 200; i++) i,
          null,
          for (var i = 201; i < 400; i++) i,
        ],
      ),
      'deleteMid': (List.filled(399, salt), [for (var i = 0; i < 399; i++) i]),
      'insertMid': (
        [...List.filled(200, salt), oil, ...List.filled(200, salt)],
        [
          for (var i = 0; i < 200; i++) i,
          null,
          for (var i = 200; i < 400; i++) i,
        ],
      ),
      'appendEnd': (
        [...List.filled(400, salt), oil],
        [for (var i = 0; i < 400; i++) i, null],
      ),
    };
    for (final MapEntry(key: name, value: (after, want)) in shapes.entries) {
      test('400 decided twins, one edit ($name): the search never branches '
          'on a twin — at most 1,000 expansions (v28: 10,000, the budget, '
          '1.0–4.3 s) and 100 ms; the decisions kept in order, rows on '
          'their own positions, a surplus dropped from the end', () {
        final rows = [for (var i = 0; i < 400; i++) row(i, salt, 1000 + i)];
        final lines = [for (final t in after) real[t]!];
        final laid = List.filled(400, salt);
        var ms = 1 << 30;
        late List<IngredientMatchRow?> got;
        for (var k = 0; k < 3; k++) {
          final sw = Stopwatch()..start();
          got = pairRowsToLines(rows, lines, laidOut: laid);
          ms = min(ms, sw.elapsedMilliseconds);
        }
        expect(pairingExpansions, lessThanOrEqualTo(1000));
        expect(ms, lessThanOrEqualTo(100));
        expect([for (final r in got) r?.position], want);
      }, skip: skipIfNoCorpus);
    }

    test(
      'a run giving fewer rows than it has keeps its DECISIONS first, in '
      'order, wherever they stood (four twins, the 2nd a pick and the 4th '
      'a skip, saved as two: both kept; three picks saved as two: the '
      'first two, rows on their own positions — the surplus from the end)',
      () {
        List<int?> pair(List<Object?> decisions, int keep) => [
          for (final r in pairRowsToLines(
            [for (final (i, d) in decisions.indexed) row(i, salt, d)],
            List.filled(keep, real[salt]!),
            laidOut: List.filled(decisions.length, salt),
          ))
            r?.position,
        ];
        expect(pair([null, 1001, null, 'S'], 2), [1, 3]);
        expect(pair([1000, 1001, 1002], 2), [0, 1]);
        // The pick kept; of the rest, the row on its own line (row 0).
        expect(pair([null, null, 1002], 2), [0, 2]);
        // Lines past the run's start (another food first): the pick kept,
        // and of the rest the row that lands on its own line — not the
        // leaf's first undecided row (rows 0 and 1 on lines 1 and 2).
        expect(
          [
            for (final r in pairRowsToLines(
              [row(0, salt, 1000), row(1, salt), row(2, salt)],
              [real[oil]!, real[salt]!, real[salt]!],
              laidOut: List.filled(3, salt),
            ))
              r?.position,
          ],
          [null, 0, 2],
        );
      },
    );

    test('Run 059 S12: n twins, every other one decided, a line inserted in '
        'the middle — the budget never reached (v28 at n = 200: 10,000, '
        '~2.2 s)', () {
      for (final n in [20, 50, 100, 200, 400]) {
        final rows = [
          for (var i = 0; i < n; i++) row(i, oil, i.isEven ? 1000 + i : null),
        ];
        final lines = [
          for (var i = 0; i <= n; i++) real[i == n ~/ 2 ? salt : oil]!,
        ];
        final got = pairRowsToLines(rows, lines);
        expect(pairingExpansions, lessThanOrEqualTo(2 * n + 2), reason: '$n');
        expect(got.nonNulls.length, n, reason: '$n');
      }
    });

    test('the twin fuzz: 2,000 saves of 12–15 lines over three texts and an '
        'amount variant, one to three edits each — the budget never reached '
        '(v28: S12 measured 111 in 30,000), never a row twice, every row on '
        'a line of its text or ingredient', () {
      final texts = [salt, oil, pec, oilQuarter];
      var hits = 0;
      var maxExp = 0;
      for (var seed = 0; seed < 2000; seed++) {
        final rnd = Random(seed);
        final before = [
          for (var i = 0; i < 12 + rnd.nextInt(4); i++) texts[rnd.nextInt(3)],
        ];
        final rows = [
          for (final (i, t) in before.indexed)
            row(i, t, switch (rnd.nextInt(3)) {
              0 => 1000 + i,
              1 => 'S',
              _ => null,
            }),
        ];
        final after = [...before];
        for (var e = 0; e <= rnd.nextInt(3); e++) {
          final at = rnd.nextInt(after.length);
          final t = texts[rnd.nextInt(texts.length)];
          switch (rnd.nextInt(4)) {
            case 0:
              after.insert(at, t);
            case 1:
              if (after.length > 1) after.removeAt(at);
            case 2:
              after[at] = t;
            default:
              after.insert(rnd.nextInt(after.length), after.removeAt(at));
          }
        }
        final lines = [for (final t in after) real[t]!];
        final got = pairRowsToLines(rows, lines, laidOut: before);
        maxExp = max(maxExp, pairingExpansions);
        if (pairingExpansions >= pairingBudget) hits++;
        final taken = got.nonNulls.map((r) => r.position).toList();
        expect(taken.toSet().length, taken.length, reason: '$seed');
        for (final (at, r) in got.indexed) {
          if (r != null) {
            expect(
              r.raw == after[at] || r.itemKey == lineKeyOf(lines[at]),
              isTrue,
              reason: '$seed: $at',
            );
          }
        }
      }
      expect(hits, 0, reason: 'max expansions $maxExp');
    });
  }, skip: skipIfNoCorpus);

  test(
    'a twin run is ONE text AND one key set (Run 059 T03): two rows of '
    "0857's salt line, the second STORED under the flour line's key (the "
    'curated-item case, synthesized), and the recipe now the flour line '
    'alone — the line takes the row its key names, never the twin before '
    'it',
    () {
      final corpus = {
        for (final l in nutritionLines(
          loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml'),
        ))
          l.raw: l,
      };
      const salt = '1 teaspoon table salt';
      const flour = '1¾ cups (8¾ ounces) unbleached all-purpose flour';
      IngredientMatchRow row(int pos, String keyOf) => IngredientMatchRow(
        recipeId: 'r',
        position: pos,
        raw: salt,
        fdcId: null,
        description: null,
        dataType: null,
        confidence: 0.9,
        grams: null,
        gramSource: null,
        status: 'auto',
        itemKey: lineKeyOf(corpus[keyOf]!),
      );
      expect(lineKeyOf(corpus[salt]!), isNot(lineKeyOf(corpus[flour]!)));
      final paired = pairRowsToLines(
        [row(0, salt), row(1, flour)],
        [corpus[flour]!],
      );
      expect(paired.single?.position, 1);
    },
    skip: skipIfNoCorpus,
  );
}
