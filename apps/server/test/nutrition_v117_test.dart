// The v117 pins (batch M104, prep52 P5: the strain and discard step readers;
// matcherVersion 103). S1a: a chile line's strain head is 'chile'
// (`_strainHeadOf`, at the three `_strainedHeads.contains` sites; in
// `_strainedOut` it also names the mentions). S1b: "transfer the <x-y>
// mixture to" a pot carries a processor's lines there (`_addsMixture`).
// W1-D: a bone-in wing discarded by name reads as cured pork does (Q17):
// 0 g from a skimmed pot, else held `discarded_medium` (`fatKept`). W1-E:
// for ground stock meat, a mention after the strain whose sentence names a
// bone-in word is that part's line (`_strainedOut`'s `returned`, keyed by
// the meat flag too). The browning-fat dependent: hearty chicken noodle
// soup's oil re-sized from the breasts once the ground chicken counts 0 g.
// Corpus-backed groups skip without SALT_CORPUS_DIR; every corpus read sits
// inside a test body. The synthesized recipes are NEGATIVE-path inputs (the
// allowed exception), each naming its corpus source.
//
// Hand derivations (grams × the record's kcal per 100 g in the engine's
// order 208, else 958, else 957 — snapshot 33's cached details):
//   caldo-de-siete-mares|0: 51.00 g × 281 (SR 169396, 208) = 143.31 → 0.00
//     g, 0.00 kcal (strained out); per serving 423.54 − 143.31 / 6 = 399.66.
//   chinese-style-barbecued-spareribs|0: 48.00 g × 80 (SR 169231) = 38.40
//     → 0; |1: 24.00 g × 143 (1104647) = 34.32 → 0; per serving 832.71 −
//     72.72 / 6 = 820.59.
//   best-chicken-stew|3: 226.80 g × 172.792125 (2727568, 958) = 391.89 →
//     held, no grams; the recipe partial, 538.53 − 391.89 / 6 = 473.22.
//   hearty-chicken-noodle-soup|1: 453.59 g × 143 (SR 171116) = 648.64 → 0.
//   hearty-chicken-noodle-soup|0 (the dependent): 2 / 131.62 (FNDDS
//     2705972's oil per raw breast) × 442.25 g (|9, 2646170, the heaviest
//     counted meat row once |1 counts 0 g) ÷ fat 1.00 = 6.72 g (was × 453.59
//     = 6.89); × 900 (FNDDS 2710180) = 60.48 kcal (was 62.01). Per serving
//     501.29 − (648.64 + 1.53) / 4 = 338.75.
//   Batch: −143.31 − 38.40 − 34.32 − 391.89 − 648.64 − 1.53 = −1,258.09.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_cost_test.dart' show tok;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _caldo = '1207-caldo-de-siete-mares.yaml';
const _ribs = '0538-chinese-style-barbecued-spareribs.yaml';
const _stew = '0096-best-chicken-stew.yaml';
const _hearty = '0002-hearty-chicken-noodle-soup.yaml';

const _strained =
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)';
const _browning =
    'skimmed / poured off — only the fat the browned food keeps counted · approximation (browning fat: 1.52 g fat per 100 g of the raw chicken breast — USDA FNDDS 2705972 recipe: 2 g oil per 131.62 g raw chicken breast (the browned piece keeps a film; the steps skim / pour off the rest))';

/// The moved rows, every stored column the rules write (the replay's, on
/// snapshot 33): (file, position, raw start, record, description, status,
/// hold, gram source, confidence, grams, kcal, basis).
const _moved = [
  (
    _caldo,
    0,
    '3 dried ancho chiles',
    169396,
    'Peppers, ancho, dried',
    'auto',
    null,
    'discarded',
    '0.933333',
    '0.00',
    '0.00',
    _strained,
  ),
  (
    _ribs,
    0,
    '1 (6-inch) piece fresh ginger',
    169231,
    'Ginger root, raw',
    'auto',
    null,
    'discarded',
    '0.886667',
    '0.00',
    '0.00',
    _strained,
  ),
  (
    _ribs,
    1,
    '8 garlic cloves, peeled',
    1104647,
    'Garlic, raw',
    'auto',
    null,
    'discarded',
    '0.970000',
    '0.00',
    '0.00',
    _strained,
  ),
  (
    _stew,
    3,
    '1 pound chicken wings, halved at joint',
    2727568,
    'Chicken, wing, meat and skin, raw',
    'auto',
    'discarded_medium',
    null,
    '0.950000',
    null,
    null,
    null,
  ),
  (
    _hearty,
    1,
    '1 pound ground chicken',
    171116,
    'Chicken, ground, raw',
    'auto',
    null,
    'discarded',
    '1.000000',
    '0.00',
    '0.00',
    _strained,
  ),
  (
    _hearty,
    0,
    '1 tablespoon vegetable oil',
    2710180,
    'Vegetable oil, NFS',
    'auto',
    null,
    'discarded',
    '0.923333',
    '6.72',
    '60.48',
    _browning,
  ),
];

/// The moved recipes' statuses (the replay's) and per-serving figures on
/// the fixtures: the replay reads caldo 399.66 and the stew 473.22; the
/// fixtures' copies of 2346401 / 2684445 (caldo |14 |16: 297.60 / 911.72
/// kcal where snapshot 33's details give 297.43 / 910.27) and 2646171 /
/// 2346402 (the stew's |0 |14: 1,351.70 / 332.94 for 1,354.48 / 332.82)
/// carry other energies (measured row by row; no moved row reads them).
const _recipes = [
  // RE-PIN (M106 batch, v119): caldo-de-siete-mares|9 453.59 → 367.41 g (× 0.81, AH-102 item 2333; the replay 399.66 → 387.45) — was 399.93.
  (_caldo, 'complete', 387.72),
  (_ribs, 'complete', 820.59),
  (_stew, 'partial', 472.78),
  (_hearty, 'complete', 338.75),
];

/// The design's negatives, unchanged (file, position, raw start, record,
/// grams or null, hold) — the v116 rows, byte-identical in the replay.
const _unmoved = [
  // S1a: the strain's other pepper heads (F3, §5 S1e) and the chile lines
  // a shipped guard keeps.
  (_caldo, 7, '1 teaspoon pepper', 170931, '2.30', null),
  (_caldo, 4, '2 teaspoons ground cumin', 170923, '4.24', null),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    4,
    '2 Thai chiles, stemmed',
    2709798,
    '4.00',
    null,
  ),
  (
    '0473-tortilla-soup.yaml',
    10,
    '½ medium jalapeño chile',
    2747661,
    '7.00',
    null,
  ),
  (
    '0274-red-snapper-ceviche-with-radishes-and-orange.yaml',
    4,
    '1 tablespoon ají amarillo chile paste',
    171186,
    '19.50',
    null,
  ),
  (
    '0376-biang-biang-mian-flat-hand-pulled-noodles-with-chili-oil-vinaigrette.yaml',
    4,
    '10–20 bird chiles, ground fine',
    168570,
    '7.50',
    null,
  ),
  (
    '0285-shrimp-cocktail.yaml',
    12,
    '1 teaspoon ancho or other mild chili powder',
    171319,
    '2.71',
    null,
  ),
  (
    '0517-thai-style-chicken-soup.yaml',
    13,
    '2 Thai, serrano, or jalapeño chiles',
    2709798,
    '30.00',
    null,
  ),
  // A discard of chile SKINS at the `_discardedByName` site.
  (
    '0497-chile-verde-con-cerdo-green-chili-with-pork.yaml',
    4,
    '5 poblano chiles',
    2747662,
    '648.00',
    null,
  ),
  (
    '0497-chile-verde-con-cerdo-green-chili-with-pork.yaml',
    7,
    '1 jalapeño chile, stemmed and halved',
    2747661,
    '14.00',
    null,
  ),
  // S1b: the ground pepper passes the strainer; the carry refused by the
  // shipped condition (another vessel, no pot word; and smooth).
  (_ribs, 8, '1 teaspoon ground pepper', 170931, '2.30', null),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    0,
    '25 garlic cloves, unpeeled',
    1104647,
    '75.00',
    null,
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    3,
    '1 tablespoon peppercorns',
    170931,
    '8.72',
    null,
  ),
  // W1-D: "Discard wingtips" names no wing; no discard clause.
  (
    '1125-roasted-and-glazed-chicken-wings.yaml',
    0,
    '4 pounds chicken wings',
    2727568,
    '907.18',
    null,
  ),
  (
    '0095-lighter-chicken-and-dumplings.yaml',
    9,
    '1 pound chicken wings',
    2727568,
    '226.80',
    null,
  ),
  // W1-E: the ground stock meat a shipped guard keeps.
  (
    '1175-kousa-mihshi-lebanese-stuffed-squash.yaml',
    1,
    '8 ounces ground lamb',
    2727570,
    '226.80',
    null,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    18,
    '6 ounces ground pork',
    2514745,
    '170.10',
    null,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    20,
    '6 ounces 85 percent lean ground beef',
    171796,
    '170.10',
    null,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    4,
    '4 ounces ground pork',
    2514745,
    null,
    'discarded_medium',
  ),
  (
    '0402-italian-wedding-soup.yaml',
    5,
    '4 ounces 85 percent lean ground beef',
    171796,
    null,
    'discarded_medium',
  ),
];

void main() {
  test('matcherVersion 107', () {
    // RE-PIN (M105 batch, v118): matcherVersion 104 (was 103).
    // RE-PIN (M106 batch, v119): matcherVersion 105 (was 104).
    // RE-PIN (M107 batch, v120): matcherVersion 106 (was 105).
    // RE-PIN (M108 batch, v121): matcherVersion 107 (was 106).
    expect(matcherVersion, 107);
  });
  group(
    'v117 (M104: the strain and discard step readers)',
    skip: skipIfNoCorpus,
    () {
      moved();
      unmoved();
      properties();
      person();
    },
  );
  synthesized();
  costs();
}

/// [file] stored and computed whole on the fixtures (its real steps).
Future<(SaltDatabase, Recipe)> _computed(String file) async {
  final (db, _) = a.pathDb();
  final r = loadCorpusRecipe(file);
  await d.editAndCompute(db, _fx, r);
  return (db, r);
}

/// Negatives whose recipes hold lines the fixtures have no search answer
/// for: computed with their real steps and only the line pinned (its
/// medium on the WHOLE recipe is the property's, [properties]).
const _alone = {
  '0473-tortilla-soup.yaml',
  '0274-red-snapper-ceviche-with-radishes-and-orange.yaml',
  '0376-biang-biang-mian-flat-hand-pulled-noodles-with-chili-oil-vinaigrette.yaml',
  '0095-lighter-chicken-and-dumplings.yaml',
};

/// [file]'s line [position] computed: whole, or alone ([_alone]) — its
/// recipe and the line's index in it.
Future<(SaltDatabase, Recipe, int)> _computedAt(
  String file,
  int position,
) async {
  if (!_alone.contains(file)) {
    final (db, r) = await _computed(file);
    return (db, r, position);
  }
  final (db, _) = a.pathDb();
  final corpus = loadCorpusRecipe(file);
  final r = corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
  await d.editAndCompute(db, _fx, r);
  return (db, r, 0);
}

String? _kcal(SaltDatabase db, IngredientMatchRow row) => row.grams == null
    ? null
    : (kcalPer100g(knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!) *
              row.grams! /
              100)
          .toStringAsFixed(2);

/// Every stored column the rules write, the basis, and the GET's grams,
/// hold and `gram_basis` (A2: the act, not only the helper).
void moved() {
  for (final (
        file,
        position,
        raw,
        fdcId,
        description,
        status,
        hold,
        source,
        confidence,
        grams,
        kcal,
        basis,
      )
      in _moved) {
    test(
      '$file|$position: $fdcId ${grams ?? 'held'} `${source ?? hold}`',
      () async {
        final (db, r) = await _computed(file);
        final line = nutritionLines(r)[position];
        expect(line.raw, startsWith(raw));
        final row = d.rowOf(db, r, position);
        expect(
          (
            row.fdcId,
            row.description,
            row.status,
            row.hold,
            row.gramSource,
            row.confidence.toStringAsFixed(6),
            row.grams?.toStringAsFixed(2),
            _kcal(db, row),
          ),
          (fdcId, description, status, hold, source, confidence, grams, kcal),
        );
        expect(gramBasisFor(db, line, row, recipe: r), basis);
        final body = await matchesBody(db, _fx, r);
        final m = ((body['items']! as List)[position] as Map)['match'] as Map;
        expect(
          (
            (m['grams'] as num?)?.toStringAsFixed(2),
            m['hold'],
            m['gram_basis'],
          ),
          (grams, hold, basis),
        );
      },
    );
  }
  for (final (file, status, perServing) in _recipes) {
    test('$file: $status, $perServing a serving', () async {
      final (db, r) = await _computed(file);
      final label = db.nutritionFor(r.id)!;
      expect(
        (label.status, label.caloriesPerServing?.toStringAsFixed(2)),
        (status, perServing.toStringAsFixed(2)),
      );
    });
  }
}

/// The design's negatives keep their v116 rows.
void unmoved() {
  for (final (file, position, raw, fdcId, grams, hold) in _unmoved) {
    test('$file|$position unchanged: $fdcId ${grams ?? hold}', () async {
      final (db, r, at) = await _computedAt(file, position);
      expect(nutritionLines(r)[at].raw, startsWith(raw));
      final row = d.rowOf(db, r, at);
      expect(
        (row.fdcId, row.grams?.toStringAsFixed(2), row.hold),
        (fdcId, grams, hold),
      );
    });
  }
}

/// Every corpus recipe file, sorted.
List<String> _files() =>
    Directory(corpusRecipesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();

/// The shipped carry pattern before v117 (the property's reference).
final _oldCarry = RegExp(r'\badd (?:the )?(?:\w+ )?mixture\b');
final _otherVessel = RegExp(r'\bbowl\b|\bmixer\b|food processor|\bblender\b');
final _potWord = RegExp(r'\bpot\b|saucepan|dutch oven|skillet|roasting pan');
const _stockMeat = {'beef', 'pork', 'chicken', 'turkey', 'lamb', 'veal'};

String _sha(Iterable<String> lines) =>
    sha256.convert(utf8.encode(lines.join('\n'))).toString();

/// R6 / A5 — what each reader RETURNS on every input of its class, over
/// every corpus recipe's own lines and step sentences (the property's
/// limit: the titled sections' lines and steps are not looped; the Banana
/// Ketchup carry of lumpiang shanghai is held by the replay's sections,
/// byte-identical).
void properties() {
  test('the strain head, the carry and the three media on every corpus line '
      'and sentence', () {
    final chile = <String>[];
    final headMismatch = <String>[];
    final carry = <String>[];
    final carryPot = <String>[];
    final media = <String>[];
    final chileMedia = <String>[];
    final wingMedia = <String>[];
    final meatMedia = <String>[];
    for (final file in _files()) {
      final r = loadCorpusRecipe(file);
      for (final (i, sentences) in stepSentencesForTest(r).indexed) {
        for (final (j, s) in sentences.indexed) {
          if (addsMixtureForTest(s) && !_oldCarry.hasMatch(s)) {
            carry.add('$file|$i|$j');
            if (!_otherVessel.hasMatch(s) || _potWord.hasMatch(s)) {
              carryPot.add('$file|$i|$j');
            }
          }
          // The old pattern's sentences all stay matched (a widening).
          if (_oldCarry.hasMatch(s) && !addsMixtureForTest(s)) {
            carry.add('NARROWED $file|$i|$j');
          }
        }
      }
      for (final (k, line) in nutritionLines(r).indexed) {
        final normalized = normalizeItem(lineItemOf(line));
        final head = headNounOf(normalized);
        // The chile word read by another method: the item's own words.
        final words = normalized.split(RegExp('[^a-z]+')).toSet();
        final expected =
            head == 'pepper' &&
                words.intersection({
                  'chile',
                  'chili',
                  'chiles',
                  'chilis',
                }).isNotEmpty
            ? 'chile'
            : head;
        final strainHead = strainHeadOfForTest(line);
        if (strainHead != expected) headMismatch.add('$file|$k $strainHead');
        if (strainHead == 'chile') chile.add('$file|$k');
        final m = discardedMediumOf(r, line, normalized);
        if (m == DiscardedMedium.strainedSolid ||
            m == DiscardedMedium.removedAromatic ||
            m == DiscardedMedium.fatKept) {
          media.add('$file|$k|${m!.name}');
        }
        if (strainHead == 'chile' && m != null) {
          chileMedia.add('$file|$k|${m.name}');
        }
        if (head == 'wing' && m != null) wingMedia.add('$file|$k|${m.name}');
        if (_stockMeat.contains(head) &&
            line.raw.toLowerCase().contains(RegExp(r'\bground\b')) &&
            m != null) {
          meatMedia.add('$file|$k|${m.name}');
        }
      }
    }
    expect(headMismatch, isEmpty);
    expect(
      (chile.length, _sha(chile)),
      (
        91,
        '36e4e2c5bf10390612ad1112951151932aaa2540811aeb4b985a84563e5ebbd6',
      ),
    );
    expect(chileMedia, ['$_caldo|0|strainedSolid']);
    expect(wingMedia, [
      '$_stew|3|fatKept',
      '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml|1|partialUse',
    ]);
    expect(meatMedia, [
      '$_hearty|1|strainedSolid',
      '0010-vietnamese-beef-pho.yaml|0|strainedSolid',
      '0402-italian-wedding-soup.yaml|4|fatKept',
      '0402-italian-wedding-soup.yaml|5|fatKept',
    ]);
    expect(
      (carry.length, _sha(carry)),
      (
        171,
        '577666b5a76604ca284d090c03a344ebc91871819be54f8def9edfacf3280fc9',
      ),
    );
    expect(
      (carryPot.length, _sha(carryPot)),
      (
        71,
        'b688f852d1c50a2d350ee636ed6f9a7925763097b532529182a7d4eee05d270c',
      ),
    );
    expect(carryPot, contains('$_ribs|0|1'));
    final counts = <String, int>{};
    for (final x in media) {
      counts[x.split('|').last] = (counts[x.split('|').last] ?? 0) + 1;
    }
    expect(counts, {
      'strainedSolid': 145,
      'removedAromatic': 118,
      'fatKept': 7,
    });
    expect(
      _sha(media),
      '91378ff735e2d2982c56ea838951415b4e39ca5f3406dbcdc603184def035f36',
    );
    expect(
      media,
      containsAll([
        '$_caldo|0|strainedSolid',
        '$_ribs|0|strainedSolid',
        '$_ribs|1|strainedSolid',
        '$_stew|3|fatKept',
        '$_hearty|1|strainedSolid',
      ]),
    );
  });

  // Closer 1 (verify1 D1): `_keptSolidsOf`, S1a's third site, reads the
  // strain head for the class test AND the mentions. Over every corpus
  // recipe the one kept-solids strain is 0659's, shared by its garlic (|1)
  // and rosemary (|2). The family (STATED synthesized inputs, the A5
  // widening — no corpus kept-solids recipe holds a chile line): each of
  // the property's 91 corpus chile lines put at 0659|2, its step 1 naming a
  // bare "pepper" before the strain (a black pepper's mention): no chile
  // line ever shares the kept part — the garlic and rosemary alone, [1, 3].
  // Under the mentions read as 'pepper' (the round-1 tree) the chile took
  // that mention and shared.
  test('the kept-solids strain on every corpus recipe; no corpus chile '
      'line shares it through a "pepper" mention', () {
    final kept = <String>[];
    final chileLines = <IngredientLine>[];
    for (final file in _files()) {
      final r = loadCorpusRecipe(file);
      if (keptSolidsLinesForTest(r) case final k?) kept.add('$file $k');
      for (final line in nutritionLines(r)) {
        if (strainHeadOfForTest(line) == 'chile') chileLines.add(line);
      }
    }
    expect(kept, ['$_potatoes [1, 2]']);
    expect(chileLines, hasLength(91));
    final g = loadCorpusRecipe(_potatoes);
    final steps = [...g.steps];
    steps[0] = steps[0].copyWith(
      text: steps[0].text.replaceFirst(
        'Heat oil, garlic, rosemary,',
        'Heat oil, garlic, pepper, rosemary,',
      ),
    );
    final shares = <String>{
      for (final line in chileLines)
        '${keptSolidsLinesForTest(g.copyWith(
          ingredients: [
            IngredientGroup(items: [...nutritionLines(g)]..insert(2, line)),
          ],
          steps: steps,
        ))}',
    };
    expect(shares, {'[1, 3]'});
  });
}

const _potatoes = '0659-grilled-potatoes-with-garlic-and-rosemary.yaml';

/// One moved row of each rule and a record of the same recipe to pick.
const _people = [
  (_caldo, 0, 170931),
  (_ribs, 0, 1104647),
  (_stew, 3, 2646171),
  (_hearty, 1, 2646170),
];

String _g(double? x) => x?.toStringAsFixed(2) ?? '-';

/// sw8's state: each row's record, grams, source, hold, status; the stored
/// energy.
String _state(SaltDatabase db, String id) {
  final rows = db.ingredientMatchesFor(id)
    ..sort((x, y) => x.position.compareTo(y.position));
  final t = db.nutritionFor(id)?.totalsJson;
  final e = t == null
      ? null
      : ((jsonDecode(t) as Map)['energy'] as num?)?.toDouble();
  return [
    for (final r in rows)
      [
        r.position,
        r.fdcId,
        _g(r.grams),
        r.gramSource,
        r.hold,
        r.status,
      ].join(':'),
    'E=${_g(e)}',
  ].join(' ');
}

/// R4: each verb through the real PUT on one moved row of each rule —
/// stored == recomputeTotals == a full compute == the GET's grams and hold;
/// the row each verb leaves and the GET's `gram_basis` (measured on the
/// v117 tree).
void person() {
  test('a person decision on a moved row (confirm, typed grams, skip and '
      'back, pick its own record, pick another): stored == recompute == '
      'compute == the GET', () async {
    final got = <String, String>{};
    for (final (file, position, other) in _people) {
      for (final (verb, puts)
          in <(String, List<Map<String, Object?>> Function(int own))>[
            (
              'confirm',
              (own) => [
                {'confirmed': true},
              ],
            ),
            (
              'typed',
              (own) => [
                {'grams': 77},
              ],
            ),
            (
              'skip-back',
              (own) => [
                {'skipped': true},
                {'skipped': false},
              ],
            ),
            (
              'pick-same',
              (own) => [
                {'fdc_id': own},
              ],
            ),
            (
              'pick-other',
              (own) => [
                {'fdc_id': other},
              ],
            ),
          ]) {
        final reason = '$file|$position $verb';
        final (db, r) = await _computed(file);
        final raw = nutritionLines(r)[position].raw;
        final own = d.rowOf(db, r, position).fdcId!;
        String? refused;
        for (final body in puts(own)) {
          try {
            await applyMatchOverride(db, _fx, r, position, {
              'raw': raw,
              ...body,
            });
          } on ValidationException catch (e) {
            refused = e.message;
          }
        }
        final s1 = _state(db, r.id);
        final items = (await matchesBody(db, _fx, r))['items']! as List;
        final m = (items[position] as Map)['match'] as Map;
        final row = d.rowOf(db, r, position);
        expect(
          (_g((m['grams'] as num?)?.toDouble()), m['hold']),
          (_g(row.grams), row.hold),
          reason: '$reason GET',
        );
        recomputeTotals(db, r);
        expect(_state(db, r.id), s1, reason: '$reason recompute');
        await matchAndCompute(db, _fx, r);
        expect(_state(db, r.id), s1, reason: '$reason compute');
        got[reason] = [
          refused,
          row.fdcId,
          _g(row.grams),
          row.gramSource,
          row.hold,
          row.status,
          m['gram_basis'],
          s1.split(' ').last,
        ].join(' ¦ ');
      }
    }
    expect(got, _personStates);
  });
}

/// Measured on the v117 tree: a Confirm, a pick of the row's own record or
/// of another keeps the line's medium (0 g, the shipped "poured away"
/// basis of a person-decided discarded row); typed grams count; skip and
/// back restores the engine's row (the wing held again).
const Map<String, String> _personStates = {
  // RE-PIN (M106 batch, v119): caldo-de-siete-mares|9 453.59 → 367.41 g (× 0.81, AH-102 item 2333) — the caldo entries' E was 2399.58 (typed 2615.95).
  '1207-caldo-de-siete-mares.yaml|0 confirm':
      'null ¦ 169396 ¦ 0.00 ¦ discarded ¦ null ¦ confirmed ¦ poured away — counted as 0 g ¦ E=2326.32',
  '1207-caldo-de-siete-mares.yaml|0 typed':
      'null ¦ 169396 ¦ 77.00 ¦ override ¦ null ¦ overridden ¦ entered by hand ¦ E=2542.69',
  '1207-caldo-de-siete-mares.yaml|0 skip-back':
      'null ¦ 169396 ¦ 0.00 ¦ discarded ¦ null ¦ auto ¦ discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) ¦ E=2326.32',
  '1207-caldo-de-siete-mares.yaml|0 pick-same':
      'null ¦ 169396 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=2326.32',
  '1207-caldo-de-siete-mares.yaml|0 pick-other':
      'null ¦ 170931 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=2326.32',
  '0538-chinese-style-barbecued-spareribs.yaml|0 confirm':
      'null ¦ 169231 ¦ 0.00 ¦ discarded ¦ null ¦ confirmed ¦ poured away — counted as 0 g ¦ E=4923.53',
  '0538-chinese-style-barbecued-spareribs.yaml|0 typed':
      'null ¦ 169231 ¦ 77.00 ¦ override ¦ null ¦ overridden ¦ entered by hand ¦ E=4985.13',
  '0538-chinese-style-barbecued-spareribs.yaml|0 skip-back':
      'null ¦ 169231 ¦ 0.00 ¦ discarded ¦ null ¦ auto ¦ discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) ¦ E=4923.53',
  '0538-chinese-style-barbecued-spareribs.yaml|0 pick-same':
      'null ¦ 169231 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=4923.53',
  '0538-chinese-style-barbecued-spareribs.yaml|0 pick-other':
      'null ¦ 1104647 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=4923.53',
  '0096-best-chicken-stew.yaml|3 confirm':
      'null ¦ 2727568 ¦ 0.00 ¦ discarded ¦ null ¦ confirmed ¦ poured away — counted as 0 g ¦ E=2836.66',
  '0096-best-chicken-stew.yaml|3 typed':
      'null ¦ 2727568 ¦ 77.00 ¦ override ¦ null ¦ overridden ¦ entered by hand ¦ E=2969.87',
  '0096-best-chicken-stew.yaml|3 skip-back':
      'null ¦ 2727568 ¦ - ¦ null ¦ discarded_medium ¦ auto ¦ null ¦ E=2836.66',
  '0096-best-chicken-stew.yaml|3 pick-same':
      'null ¦ 2727568 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=2836.66',
  '0096-best-chicken-stew.yaml|3 pick-other':
      'null ¦ 2646171 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=2836.66',
  '0002-hearty-chicken-noodle-soup.yaml|1 confirm':
      'null ¦ 171116 ¦ 0.00 ¦ discarded ¦ null ¦ confirmed ¦ poured away — counted as 0 g ¦ E=1354.98',
  '0002-hearty-chicken-noodle-soup.yaml|1 typed':
      'null ¦ 171116 ¦ 77.00 ¦ override ¦ null ¦ overridden ¦ entered by hand ¦ E=1465.09',
  '0002-hearty-chicken-noodle-soup.yaml|1 skip-back':
      'null ¦ 171116 ¦ 0.00 ¦ discarded ¦ null ¦ auto ¦ discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) ¦ E=1354.98',
  '0002-hearty-chicken-noodle-soup.yaml|1 pick-same':
      'null ¦ 171116 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=1354.98',
  '0002-hearty-chicken-noodle-soup.yaml|1 pick-other':
      'null ¦ 2646170 ¦ 0.00 ¦ discarded ¦ null ¦ overridden ¦ poured away — counted as 0 g ¦ E=1354.98',
};

IngredientLine _lineOf(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
}

/// A recipe of [raws] and [steps] (STATED synthesized negative-path recipes:
/// each test names the corpus lines and sentences it re-texts).
Recipe _synth(List<String> raws, List<String> steps) => Recipe(
  id: 'v117',
  title: 'v117',
  slug: 'v117',
  source: const RecipeSource(name: 'Test', type: 'book'),
  steps: [
    for (final (i, s) in steps.indexed) RecipeStep(number: i + 1, text: s),
  ],
  ingredients: [
    IngredientGroup(items: [for (final raw in raws) _lineOf(raw)]),
  ],
);

DiscardedMedium? _medium(Recipe r, int k) {
  final line = nutritionLines(r)[k];
  return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
}

/// 1207 caldo de siete mares' S1.0 / S2.4 sentences, re-texted.
const _toastAnchos =
    'Toast anchos in dutch oven until fragrant; transfer to food processor.';
const _addAncho = 'Add ancho mixture to pot and cook until darkened.';
const _strainBroth = 'Strain broth through fine-mesh strainer; discard solids.';

/// 0002 hearty chicken noodle soup's S1–S2 shape, re-texted: the ground
/// chicken browned, the broth strained and skimmed, a bone-in mention after.
List<String> _stockSteps(String after) => [
  'Heat oil in dutch oven. Add ground chicken and cook until no longer pink.',
  'Strain broth through fine-mesh strainer; discard solids. Skim the fat from the surface.',
  after,
];

void synthesized() {
  group('v117 synthesized negative paths (STATED: no corpus line reaches '
      'them)', () {
    // K5: no corpus pepper-head line spells "chili" / "chilis" (the
    // property's 91 chile lines) — 1207|0 re-texted. The strain head reads
    // every spelling; the strained answer needs a mention, and the own-word
    // reader (`_ownWordOf`, the forms of 'chile') finds none for a "chili"
    // line: it stays counted (STATED: a limit, reach 0 on the corpus).
    // ("chilis" is not a 'pepper' head at all: `headNounOf` keeps it.)
    for (final (raw, strainHead, medium) in [
      ('3 dried ancho chilis, stemmed', 'chilis', null),
      ('3 dried ancho chili, stemmed', 'chile', null),
      ('3 dried ancho chile, stemmed', 'chile', DiscardedMedium.strainedSolid),
      ('3 dried ancho chiles, stemmed', 'chile', DiscardedMedium.strainedSolid),
    ]) {
      test('S1a: "$raw" reads the $strainHead head; strained: $medium', () {
        final r = _synth([raw], [_toastAnchos, _addAncho, _strainBroth]);
        expect(strainHeadOfForTest(nutritionLines(r).single), strainHead);
        expect(_medium(r, 0), medium);
      });
    }
    test(
      'S1a: a bell pepper keeps its head (no chile word; 1207 re-texted)',
      () {
        final r = _synth(
          ['1 red bell pepper, halved'],
          ['Add bell pepper halves to pot.', _strainBroth],
        );
        expect(strainHeadOfForTest(nutritionLines(r).single), 'pepper');
      },
    );
    // m10: best chicken stew (0096) has no skim; its S5 "Discard wings"
    // with a skim sentence added before it: the wing is 0 g.
    test('W1-D: a wing discarded from a skimmed pot counts 0 g '
        '(removedAromatic; 0096 re-texted)', () {
      const line = '1 pound chicken wings, halved at joint';
      const brown = 'Brown wings in dutch oven.';
      const discard =
          'Discard wings and season stew with up to 2 tablespoons extra wine.';
      expect(
        _medium(_synth([line], [brown, discard]), 0),
        DiscardedMedium.fatKept,
      );
      expect(
        _medium(
          _synth([line], [brown, 'Skim the fat from the surface.', discard]),
          0,
        ),
        DiscardedMedium.removedAromatic,
      );
      // "Discard wingtips" (1125's) names no wing.
      expect(
        _medium(_synth([line], [brown, 'Discard wingtips.']), 0),
        isNull,
      );
    });
    // W1-E, every word of the bone-in list (0002's after-strain sentences
    // name breasts, skin, bones and shredded; the rest no corpus sentence
    // after a ground stock meat's strain names).
    for (final word in [
      'skin',
      'bone',
      'bones',
      'shredded',
      'shred',
      'breast',
      'breasts',
      'thigh',
      'thighs',
      'leg',
      'legs',
      'drumstick',
      'drumsticks',
      'wing',
      'wings',
    ]) {
      test('W1-E: "$word" after the strain is another line\'s', () {
        final r = _synth(
          ['1 pound ground chicken'],
          _stockSteps('Add the $word chicken to the broth.'),
        );
        expect(_medium(r, 0), DiscardedMedium.strainedSolid);
      });
    }
    test('W1-E: a plain mention after the strain returns the meat; a word '
        'holding a bone-in word inside another does not count', () {
      for (final after in [
        'Add the cooked chicken to the broth.',
        'Add the chickenskins chicken to the broth.',
      ]) {
        final r = _synth(['1 pound ground chicken'], _stockSteps(after));
        expect(_medium(r, 0), isNull, reason: after);
      }
    });
    // The list's own boundaries and its scope (mutant m11b: a "mixture"
    // added; the owner-gate neighbours: either \b dropped) — 0002's after
    // sentence re-texted; no corpus sentence after a ground stock meat's
    // strain reads so.
    for (final after in [
      'Add the chicken mixture to the broth.',
      'Add the chickenskin chicken to the broth.',
      'Add the skinny chicken to the broth.',
    ]) {
      test('W1-E: "$after" returns the meat (no bone-in WORD)', () {
        final r = _synth(['1 pound ground chicken'], _stockSteps(after));
        expect(_medium(r, 0), isNull);
      });
    }
    // The chile word's boundaries: a 'pepper' head whose item holds the
    // letters inside another word keeps its head (no corpus line: the
    // property's 0 mismatches).
    // Owner gate (three one-site neighbours passed the file; each differs on
    // NO corpus line — measured over the corpus's 16,510 lines: 0 of the
    // 1,194 'pepper' lines name the chile word in the raw line and not in
    // the item; 5 lines name wings in their raw text under another head and
    // none of them has a medium; the media property, the recipes' own
    // lines, holds under each): what each reader READS. The verifier's two
    // neighbours after them (the chile word off the authored item
    // un-normalized; the wing as a word of the item, not its head) differ on
    // no corpus line either: one more input each.
    test(
      "S1a: the chile word is the ITEM's, not a prep word of the raw line",
      () {
        // 1207|0 re-texted to a bell pepper whose prep names a chile.
        final line = _lineOf(
          '1 red bell pepper, stemmed, seeded, and cut into strips the size '
          'of a chile',
        );
        expect(normalizeItem(lineItemOf(line)), 'red bell pepper');
        expect(strainHeadOfForTest(line), 'pepper');
        // …nor an alternative the authored item carries in parentheses.
        const authored = IngredientLine(
          raw: '1 red bell pepper (or 2 Anaheim chiles), stemmed and seeded',
          item: 'red bell pepper (or 2 Anaheim chiles)',
        );
        expect(normalizeItem(lineItemOf(authored)), 'red bell pepper');
        expect(strainHeadOfForTest(authored), 'pepper');
      },
    );
    test("W1-E: the bone-in word is read in the mention's own SENTENCE, not "
        'its step', () {
      // 0002's after-strain step re-texted: the meat named in one sentence,
      // a bone-in part in the next (and the other order).
      for (final after in [
        'Add the cooked chicken to the broth. Shred the breasts.',
        'Shred the breasts. Add the cooked chicken to the broth.',
      ]) {
        final r = _synth(['1 pound ground chicken'], _stockSteps(after));
        expect(_medium(r, 0), isNull, reason: after);
      }
    });
    test("W1-D: the discarded part is the line's HEAD, not a word of its "
        'raw text', () {
      // 0156|0's corpus line (head 'thigh'; its raw names wings) with 0096's
      // discard sentence re-texted to it: no bone-in part of the list.
      const thighs =
          '6 turkey thighs, trimmed, or 9 wings, separated at the joints';
      final r = _synth(
        [thighs],
        ['Brown turkey thighs in dutch oven.', 'Discard thighs and season.'],
      );
      expect(headNounOf(normalizeItem(lineItemOf(_lineOf(thighs)))), 'thigh');
      expect(_medium(r, 0), isNull);
      // …nor a word of the item that is not its head (0096's line re-texted
      // to wing tips, head 'tip', its discard naming the tips).
      const tips = '1 pound chicken wing tips';
      expect(headNounOf(normalizeItem(lineItemOf(_lineOf(tips)))), 'tip');
      expect(
        _medium(
          _synth(
            [tips],
            [
              'Brown chicken wing tips in dutch oven.',
              'Discard tips and season stew.',
            ],
          ),
          0,
        ),
        isNull,
      );
    });
    test('S1a: "Chilean" is no chile word', () {
      final r = _synth(['1 Chilean red bell pepper'], [_strainBroth]);
      expect(strainHeadOfForTest(nutritionLines(r).single), 'pepper');
    });
    // Closer 1 (verify1 D1, mutant K3b's input): the kept-solids strain
    // (0659, the corpus's one) with tortilla-soup|10's "½ medium jalapeño
    // chile" put at |2 and its step 1 naming "jalapeño pepper". The strain
    // head reads the chile's mentions under 'chile' — none ([_headsOf]
    // keeps 'pepper'; the site reads no own word) — so it shares nothing:
    // the garlic (9 × 3 g = 27 g) and rosemary (1 tsp × 0.7 g, SR 173473)
    // share the kept 3 × 2.8 = 8.40 g pro rata — 8.40 × 27 / 27.7 = 8.19,
    // × 0.7 / 27.7 = 0.21 — and the chile counts whole, ½ × 14 g = 7.00 g
    // (the round-1 tree, mentions under 'pepper': 6.54 / 1.69 / 0.17). Its
    // own medium is none: a STATED limit (its own word "jalapeño" finds no
    // mention either) — it stays counted, as at base.
    test('S1a: a chile line beside the kept-solids strain shares nothing '
        '(0659 + 0473|10)', () async {
      final (db, _) = a.pathDb();
      final g = loadCorpusRecipe(_potatoes);
      final jal = nutritionLines(
        loadCorpusRecipe('0473-tortilla-soup.yaml'),
      )[10];
      final steps = [...g.steps];
      steps[0] = steps[0].copyWith(
        text: steps[0].text.replaceFirst(
          'Heat oil, garlic, rosemary,',
          'Heat oil, garlic, jalapeño pepper, rosemary,',
        ),
      );
      final r = g.copyWith(
        ingredients: [
          IngredientGroup(items: [...nutritionLines(g)]..insert(2, jal)),
        ],
        steps: steps,
      );
      expect(keptSolidsLinesForTest(r), [1, 3]);
      expect(discardedMediumOf(r, jal, normalizeItem(lineItemOf(jal))), null);
      await d.editAndCompute(db, _fx, r);
      expect(
        _state(db, r.id),
        '0:2710186:56.00:portion:null:auto '
        '1:1104647:8.19:discarded:null:auto '
        '2:2747661:7.00:piece:null:auto '
        '3:173473:0.21:discarded:null:auto '
        '4:null:-:null:null:confirmed '
        '5:2346402:907.18:weight:null:auto '
        '6:169994:6.00:portion:null:auto E=1185.35',
      );
      final rows = {
        for (final m in db.ingredientMatchesFor(r.id)) m.position: m,
      };
      expect(
        gramBasisFor(db, nutritionLines(r)[2], rows[2]!, recipe: r),
        '1/2 × 14 g each',
      );
    }, skip: skipIfNoCorpus);
    // S1b: the carrying condition (no other vessel, or a pot word) and the
    // verb's inflections — 0538's S1.0 / S1.1 re-texted (K8; the owner-gate
    // neighbour without `\w*`).
    for (final (carry, medium) in [
      (
        'Transfer ginger-garlic mixture from food processor to dutch oven.',
        DiscardedMedium.strainedSolid,
      ),
      (
        'Transferring ginger-garlic mixture to dutch oven.',
        DiscardedMedium.strainedSolid,
      ),
      ('Transfer ginger-garlic mixture to large bowl.', null),
    ]) {
      test('S1b: "$carry" carries: ${medium != null}', () {
        final r = _synth(
          ['8 garlic cloves, peeled'],
          [
            'Pulse garlic in food processor until finely chopped.',
            carry,
            'Strain braising liquid through fine-mesh strainer, pressing on solids; discard solids.',
          ],
        );
        expect(_medium(r, 0), medium);
      });
    }
    // W1-D's scope: the wing alone (one head; a neck or back discarded by
    // name stays counted — the ruled reach, no corpus line of its own head).
    for (final (raw, discard) in [
      ('1 turkey neck', 'Discard neck.'),
      ('1 pound chicken backs', 'Discard backs.'),
    ]) {
      test('W1-D: "$raw" + "$discard" stays counted (the wing alone)', () {
        final r = _synth(
          [raw],
          ['Brown $raw in dutch oven.'.replaceFirst('1 ', ''), discard],
        );
        expect(_medium(r, 0), isNull);
      });
    }
    // The memo key carries the meat flag: a cured line and a ground line of
    // one head share the name (0402's ground pork beside a salt pork line,
    // 0096's bacon re-texted), each read in either order.
    test('W1-E: the returned memo is keyed by the meat flag (both orders)', () {
      for (final order in [
        [0, 1],
        [1, 0],
      ]) {
        final r = _synth(
          ['4 ounces salt pork', '8 ounces ground pork'],
          [
            'Cook salt pork in dutch oven. Add ground pork and cook.',
            'Strain broth through fine-mesh strainer; discard solids. Skim the fat from the surface.',
            'Add the shredded pork to the broth.',
          ],
        );
        final got = {for (final k in order) k: _medium(r, k)};
        expect(got, {
          0: null,
          1: DiscardedMedium.strainedSolid,
        }, reason: '$order');
      }
    });
  });
}

/// [capSteps] steps of [sentence]s at the step cap, [last] closing the last.
List<String> _capSteps(String Function(int) sentence, List<String> last) {
  var k = 0;
  String fill(int room) {
    final out = <String>[];
    var n = 0;
    while (true) {
      final s = sentence(k);
      if (n + s.length + 1 > room) break;
      out.add(s);
      n += s.length + 1;
      k++;
    }
    return out.join(' ');
  }

  final tail = last.join(' ');
  return [
    for (var i = 0; i < capSteps - 1; i++) fill(capStep),
    '${fill(capStep - tail.length - 1)} $tail',
  ];
}

/// RULE C: each reader of this batch answers once per index — the quiet
/// and true-path cap shapes, memo counts pinned exactly (base vs tip in
/// docs/API.md "Matcher v117").
void costs() {
  group('v117 RULE C caps (corpusless)', () {
    for (final (shape, raw, sentence, last, medium, memos) in [
      (
        'S1a chile true',
        (int i) => '1 dried ${tok(i)} chile',
        (int k) => 'Toast ${tok(k % capLines)} in dutch oven.',
        [_strainBroth],
        DiscardedMedium.strainedSolid,
        {'memo:strainAt': 1, 'memo:namedAfterStrain': capLines},
      ),
      (
        'S1a chile quiet',
        (int i) => '1 dried ${tok(i)} chile',
        (int k) => 'Toast ${tok(k % capLines)} in dutch oven.',
        ['Serve.'],
        null,
        {'memo:strainAt': 1},
      ),
      (
        'S1b carry true',
        (int i) => '1 garlic clove',
        (int k) => 'Pulse garlic in food processor.',
        ['Transfer ginger-garlic mixture to dutch oven.', _strainBroth],
        DiscardedMedium.strainedSolid,
        {'memo:strainAt': 1, 'memo:addsMixture': 1},
      ),
      (
        'S1b carry quiet',
        (int i) => '1 garlic clove',
        (int k) => 'Pulse garlic in food processor.',
        ['Transfer ginger-garlic mixture to large bowl.', _strainBroth],
        null,
        {'memo:strainAt': 1, 'memo:addsMixture': 1},
      ),
      (
        'W1-E meat true',
        (int i) => '1 pound ground chicken',
        (int k) => 'Add ground chicken to dutch oven.',
        [
          _strainBroth,
          'Skim the fat from the surface.',
          'Add the shredded chicken.',
        ],
        DiscardedMedium.strainedSolid,
        {'memo:strainAt': 1, 'memo:namedAfterStrain': 1},
      ),
      (
        'W1-E meat quiet',
        (int i) => '1 pound ground chicken',
        (int k) => 'Add ground chicken to dutch oven.',
        [
          _strainBroth,
          'Skim the fat from the surface.',
          'Add the cooked chicken.',
        ],
        null,
        {'memo:strainAt': 1, 'memo:namedAfterStrain': 1},
      ),
      (
        'W1-D wing true',
        (int i) => '1 pound chicken wings',
        (int k) => 'Brown wings in dutch oven.',
        ['Discard wings.'],
        DiscardedMedium.fatKept,
        {'memo:discards': 1},
      ),
      (
        'W1-D wing quiet',
        (int i) => '1 pound chicken wings',
        (int k) => 'Brown wings in dutch oven.',
        ['Discard wingtips.'],
        null,
        {'memo:discards': 1},
      ),
    ]) {
      test(
        '$shape: ${memos.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
        () {
          final r = _synth(
            [for (var i = 0; i < capLines; i++) raw(i)],
            _capSteps(sentence, last),
          );
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          final got = <DiscardedMedium?>{};
          for (var k = 0; k < capLines; k++) {
            got.add(_medium(r, k));
          }
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts)..remove('names');
          expectBounded(r, counts, 'v117 $shape');
          // ignore: avoid_print
          print('v117 $shape ${ms}ms $counts');
          expect(got, {medium});
          for (final MapEntry(:key, :value) in memos.entries) {
            expect(counts[key], value, reason: key);
          }
          expect(ms, lessThan(backstopMs), reason: '$shape: ${ms}ms');
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
