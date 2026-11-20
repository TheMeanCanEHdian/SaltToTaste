// The v122 pins (batch M109, two parts; matcherVersion 108).
//
// PART S — the spelling / record keys (matcher.dart `_rankAs`, one piece
// row, the shipped skin move): R1 'turnip' reads the weighed lines' answer
// and words ('turnips', 'turnips') — farmhouse-vegetable-and-barley-soup|16
// on Foundation 2747674 "Turnips, raw", its 120 g the piece table's
// cross-record 'turnip' row (FNDDS 2709809's '1 whole' 120 g): 120 × 33.9816
// kcal/100 g (2747674's 957; no 208, no 958) = 40.78. R2 'portobello
// mushroom caps' reads the counted caps' answer and words: spaghetti-with-
// quick-mushroom-ragu|3 on SR 169255, 226.80 × 22 / 100 = 49.90. R3 'bone-in
// turkey thigh' is a skin MOVE key: both spellings rank SR 171533 "…, meat
// and skin, raw" ('turkey thigh meat and skin raw'), and engine.dart's
// `_skinlessRecords` (171533: 174518) moves a skin-discarding line to the
// meat-only record — juicy-grilled-turkey-burgers|0 unchanged (174518 at
// 0.962857), turkey-thigh-confit-with-citrus-mustard-sauce|5's stored
// confidence 0.545714 → 0.962857 (its ranked top under the new words) and
// nothing else. R4 'assertive greens' → kale (a flagged stand-in,
// `approximationRecords`): quick-cooked-tough-greens|1 on Foundation 323505,
// v119's 'stemmed' share: 907.18 × 0.64 = 580.60 g × 35 / 100 = 203.21.
//
// PART C — the rinsed cure (engine.dart `discardedMediumOf`'s wrapper over
// the shipped `_discardedMediumBody`, `_rinsedCureLines`, `_mixtureLinesAt`)
// and the scraped-off note (`_scrapedOffLines`, `_scrapedOffFlag` in
// `m50FlagOf`). Corpus-backed groups skip without SALT_CORPUS_DIR; every
// corpus read sits inside a test body or setUpAll (the file loads
// corpusless).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _farmhouse = '0030-farmhouse-vegetable-and-barley-soup.yaml';
const _buttery = '0667-buttery-spring-vegetables.yaml';
const _stew = '0006-hearty-beef-and-vegetable-stew.yaml';
const _ragu = '0343-spaghetti-with-quick-mushroom-ragu.yaml';
const _burgers = '0309-juicy-grilled-turkey-burgers.yaml';
const _confit = '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml';
const _greens = '0685-quick-cooked-tough-greens.yaml';
const _corned = '0090-new-englandstyle-home-corned-beef-and-cabbage.yaml';
const _miso = '0259-miso-marinated-salmon.yaml';
const _tacos = '0480-steak-tacos.yaml';
const _gravlax = '1148-gravlax.yaml';

void main() {
  test('matcherVersion 108', () => expect(matcherVersion, 108));
  group('v122 (M109)', skip: skipIfNoCorpus, () {
    partS();
    personPath();
    ownPicks();
    keyProperty();
    partC();
    scraped();
    cureProperty();
  });
  caps();
  synthesized();
}

/// [file]'s line [position] ALONE in its recipe (the real steps).
Recipe _one(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

/// The row's kcal on its record (each record here has a fixture detail).
Future<String?> _kcal(IngredientMatchRow row) async {
  final grams = row.grams;
  if (grams == null || row.fdcId == null) return null;
  final food = (await _fx.food(row.fdcId!))!;
  return (kcalPer100g(food) * grams / 100).toStringAsFixed(2);
}

/// Every stored column the rules write, the kcal and the basis.
Future<String> _columnsOf(SaltDatabase db, Recipe r, int position) async {
  final row = d.rowOf(db, r, position);
  return [
    row.fdcId,
    row.description,
    row.status,
    row.hold ?? '',
    row.gramSource,
    row.confidence.toStringAsFixed(6),
    row.grams?.toStringAsFixed(2),
    await _kcal(row),
    gramBasisFor(db, nutritionLines(r)[position], row, recipe: r),
  ].join('\t');
}

/// A database holding each (file, position) line ALONE in its recipe,
/// computed on the fixtures (the recipe ids are the corpus ids).
Future<(SaltDatabase, List<Recipe>)> _alone(List<(String, int)> lines) async {
  final (db, _) = a.pathDb();
  final out = <Recipe>[];
  for (final (file, position) in lines) {
    final r = _one(file, position);
    await d.editAndCompute(db, _fx, r);
    out.add(r);
  }
  return (db, out);
}

/// R7: PART S's moved rows (and the two turkey rows, one unmoved), each
/// computed alone in its recipe: every stored column, the kcal and the
/// basis — the values of the v122 replay's rows (snapshot 33).
const _partS = [
  (
    _farmhouse,
    16,
    "2747674\tTurnips, raw\tauto\t\tpiece\t0.970000\t120.00\t40.78\t1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
  ),
  (
    _ragu,
    3,
    '169255\tMushrooms, portabella, raw\tauto\t\tweight\t1.000000\t226.80\t49.90\tfrom 8 ounce',
  ),
  (
    _greens,
    1,
    '323505\tKale, raw\tauto\t\tweight\t0.970000\t580.60\t203.21\tfrom 2 pound × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed)) · approximation (counted as Kale, raw)',
  ),
  // R3: the confit's stored confidence alone moves (0.545714 at v121).
  (
    _confit,
    5,
    '171533\tTurkey, retail parts, thigh, meat and skin, raw\tauto\t\tweight\t0.962857\t1487.78\t2395.33\tfrom 4 pound × 0.82 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat and skin 82 % (77–85))',
  ),
  // R3: unmoved — ranked onto 171533, moved to 174518 by the skin move.
  (
    _burgers,
    0,
    '174518\tTurkey, retail parts, thigh, meat only, raw\tauto\t\tweight\t0.962857\t698.53\t810.30\tfrom the printed weight × 0.77 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat 77 % (76–80))',
  ),
];

void partS() {
  for (final (file, position, want) in _partS) {
    test('R7: $file|$position — every stored column', () async {
      final (db, rs) = await _alone([(file, position)]);
      expect(await _columnsOf(db, rs.single, 0), want);
    });
  }
  test('A2: the matches GET reads the turnip count row', () async {
    final (db, rs) = await _alone([(_farmhouse, 16)]);
    final body = await matchesBody(db, _fx, rs.single);
    final m = ((body['items']! as List).single as Map)['match'] as Map;
    expect(
      (
        m['fdc_id'],
        (m['grams'] as num?)?.toStringAsFixed(2),
        m['hold'],
        m['status'],
        m['gram_basis'],
      ),
      (
        2747674,
        '120.00',
        null,
        'auto',
        "1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
      ),
    );
  });
  // R3 (closer round 1): the record follows the line's OWN skin words, not
  // its spelling — the two crossings no corpus line prints (a STATED
  // synthesized exception: the corpus's two lines are the burgers' skinned
  // singular and the confit's skin-on plural, each pinned above). The
  // confit's plural line with the burgers' "skinned", in the confit's own
  // steps: 4 lb × 453.592 (grams.dart's pound) × 0.77 = 1,397.06 g on SR 174518 × 116 kcal /
  // 100 g (208) = 1,620.59; the burgers' singular line without its skin
  // words, in the burgers' own steps: 2 × 453.592 × 0.82 = 743.89 g on SR
  // 171533 × 161 / 100 (208) = 1,197.66.
  for (final (file, position, raw, want) in [
    (
      _confit,
      5,
      '4 pounds bone-in turkey thighs, skinned',
      '174518\tTurkey, retail parts, thigh, meat only, raw\tauto\t\tweight\t0.962857\t1397.06\t1620.59\tfrom 4 pound × 0.77 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat 77 % (76–80))',
    ),
    (
      _burgers,
      0,
      '1 (2-pound) bone-in turkey thigh',
      '171533\tTurkey, retail parts, thigh, meat and skin, raw\tauto\t\tweight\t0.962857\t743.89\t1197.66\tfrom the printed weight × 0.82 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat and skin 82 % (77–85))',
    ),
  ]) {
    test('R3: "$raw" lands the record its own skin words say', () async {
      final (db, _) = a.pathDb();
      final one = _one(file, position);
      final line = nutritionLines(one).single;
      final r = one.copyWith(
        ingredients: [
          IngredientGroup(items: [line.copyWith(raw: raw)]),
        ],
      );
      await d.editAndCompute(db, _fx, r);
      expect(await _columnsOf(db, r, 0), want);
    });
  }
}

/// The row's (record, grams, status, hold, confidence, basis).
String _person(SaltDatabase db, Recipe r) {
  final row = d.rowOf(db, r, 0);
  return '${row.fdcId}|${row.grams?.toStringAsFixed(2)}|${row.status}|'
      '${row.hold}|${row.confidence.toStringAsFixed(6)}|'
      '${gramBasisFor(db, nutritionLines(r).single, row, recipe: r)}';
}

/// R7: the person path as an act — for each key, a Confirm + apply_to_all
/// on each spelling's row; the other row of the key re-points nothing.
/// Measured first by a printing probe on the base 9fd3e55 and on the tip
/// (each on its own replayed snapshot-33 database, calls 0): at the base the
/// same Confirms re-pointed the other spelling (the moved rows' kcal) —
/// turnip −33.60 (the count line onto 2747674 with no grams) / −61.05 (the
/// three weighed rows onto 2709809), portobello −9.12 / +3.38, turkey
/// −774.74 (the confit onto 174518) / +387.36 (the burger onto 171533); at
/// the tip 0 rows re-pointed.
void personPath() {
  for (final (key, deciding, other, applied, otherAfter) in [
    (
      'turnip (the weighed line decides)',
      (_buttery, 0),
      (_farmhouse, 16),
      '0/0',
      "2747674|120.00|auto|null|0.970000|1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
    ),
    (
      'turnip (the count line decides)',
      (_farmhouse, 16),
      (_buttery, 0),
      '0/0',
      '2747674|453.59|auto|null|0.970000|from 1 pound',
    ),
    (
      'portobello mushroom cap (the count line decides)',
      (_stew, 3),
      (_ragu, 3),
      '0/0',
      '169255|226.80|auto|null|1.000000|from 8 ounce',
    ),
    (
      'portobello mushroom cap (the weighed line decides)',
      (_ragu, 3),
      (_stew, 3),
      '0/0',
      "169255|84.00|auto|null|1.000000|1 × 84 g each · approximate (FDC's 'piece whole' portion read as one cap)",
    ),
    (
      'bone-in turkey thigh (the skinned line decides: 171533 stored)',
      (_burgers, 0),
      (_confit, 5),
      '0/0',
      '171533|1487.78|auto|null|0.962857|from 4 pound × 0.82 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat and skin 82 % (77–85))',
    ),
    (
      // The apply reaches the burger (171533 carried, moved back to 174518
      // by the skin move): its record, grams and basis unchanged, the
      // carried write's confidence 1.000000.
      'bone-in turkey thigh (the skin-on line decides)',
      (_confit, 5),
      (_burgers, 0),
      '1/1',
      '174518|698.53|auto|null|1.000000|from the printed weight × 0.77 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat 77 % (76–80))',
    ),
  ]) {
    test('R7: $key — Confirm + apply_to_all re-points no row', () async {
      final (db, rs) = await _alone([deciding, other]);
      final out = await applyMatchOverride(db, _fx, rs.first, 0, {
        'confirmed': true,
        'apply_to_all': true,
      });
      expect('${out?.lines ?? 0}/${out?.recipes ?? 0}', applied);
      expect(_person(db, rs.last), otherAfter);
    });
  }
}

/// A13: a person's own pick on the turnip count row — its own record, FNDDS
/// 2709809 (the record it left) and a third record (SR 168454 "Rutabagas,
/// raw", cached in snapshot 33): each 120 g by the piece table.
void ownPicks() {
  for (final (fdcId, want, kcal) in [
    (
      2747674,
      "2747674|120.00|overridden|null|1.000000|1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
      '40.78',
    ),
    (
      2709809,
      // The piece table's 'turnip' row precedes the record's own '1 whole'
      // (the same 120 g): at the base this pick read "1 · USDA per-item
      // weight" — the basis alone differs.
      "2709809|120.00|overridden|null|1.000000|1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
      '33.60',
    ),
    (
      168454,
      "168454|120.00|overridden|null|1.000000|1 × 120 g each · approximate (FNDDS 2709809's '1 whole' portion read as one turnip)",
      '44.40',
    ),
  ]) {
    test(
      'A13: pick $fdcId on farmhouse-vegetable-and-barley-soup|16',
      () async {
        final (db, rs) = await _alone([(_farmhouse, 16)]);
        await applyMatchOverride(db, _fx, rs.single, 0, {'fdc_id': fdcId});
        expect(_person(db, rs.single), want);
        expect(await _kcal(d.rowOf(db, rs.single, 0)), kcal);
      },
    );
  }
}

/// The corpus files, sorted, and each one's scopes (the recipe and its
/// titled sections), tagged "file" or "file§title".
Iterable<(String, Recipe)> _scopes() sync* {
  final files =
      Directory(corpusRecipesDir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.yaml'))
          .toList()
        ..sort();
  for (final file in files) {
    final host = loadCorpusRecipe(file);
    yield (file, host);
    for (final sub in host.subsections) {
      yield ('$file§${sub.title ?? ''}', sectionRecipeOf(host, sub));
    }
  }
}

String _sha(Iterable<String> lines) =>
    sha256.convert(utf8.encode(lines.join('\n'))).toString();

/// R8 (A5): every corpus line (recipes and titled sections) of the three
/// keys and of 'assertive green', each computed ALONE in its scope's steps:
/// one record per key — the turkey pair the record its own skin words say
/// (`removesSkin`: 174518, else 171533).
void keyProperty() {
  test(
    'R8: every line of the four keys lands one record',
    () async {
      const records = {
        'turnip': 2747674,
        'portobello mushroom cap': 169255,
        'assertive green': 323505,
      };
      final (db, _) = a.pathDb();
      final got = <String>[];
      for (final (tag, r) in _scopes()) {
        for (final (i, line) in nutritionLines(r).indexed) {
          final key = lineKeyOf(line);
          if (!records.containsKey(key) && key != 'bone-in turkey thigh') {
            continue;
          }
          final one = r.copyWith(
            id: 'k${got.length}',
            slug: 'k${got.length}',
            ingredients: [
              IngredientGroup(items: [line]),
            ],
          );
          await d.editAndCompute(db, _fx, one);
          final fdcId = d.rowOf(db, one, 0).fdcId;
          expect(
            fdcId,
            records[key] ?? (removesSkin(line.raw) ? 174518 : 171533),
            reason: '$tag|$i',
          );
          got.add('$tag|$i $key $fdcId');
        }
      }
      expect(
        (got.length, _sha(got)),
        (
          10,
          'dee10c2a51f37e08107b894af3f786855bde657f2212e3468cd3b106969d25b8',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// A database holding [files] computed whole on the fixtures.
Future<(SaltDatabase, Map<String, Recipe>)> _whole(List<String> files) async {
  final (db, _) = a.pathDb();
  final out = <String, Recipe>{};
  for (final f in files) {
    final r = loadCorpusRecipe(f);
    await d.editAndCompute(db, _fx, r);
    out[f] = r;
  }
  return (db, out);
}

const _zero = 'discarded\t';

/// C8: the rows the rinsed cure moves, each in its whole recipe — every
/// stored column, the kcal and the basis (the v122 replay's rows): the
/// confit's |0 |2 |3 |4 (760.00, 45.10, 18.00, 3.45 g → 0; −366.76 kcal)
/// and the corned beef's |1–|5 (−52.49 kcal), and the confit's |1 "12 sprigs
/// fresh thyme" (0.00 g before and after: its gram source `unmeasured` →
/// `discarded`, the basis "12 sprig — a sprig is not measured, counted as 0
/// g" → the shipped "discarded in cooking — counted as 0 g").
const _cured = [
  '$_confit|0\t790646\tOnions, yellow, raw\tauto\t\t${_zero}0.936667\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_confit|1\t173470\tThyme, fresh\tauto\t\t${_zero}0.900000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_confit|2\t173468\tSalt, table\tauto\t\t${_zero}0.575000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_confit|3\t746784\tSugars, granulated\tauto\t\t${_zero}0.950000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_confit|4\t170931\tSpices, pepper, black\tauto\t\t${_zero}1.000000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_corned|1\t170931\tSpices, pepper, black\tauto\t\t${_zero}1.000000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_corned|2\t170938\tSpices, thyme, dried\tauto\t\t${_zero}0.933333\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_corned|3\t171315\tSpices, allspice, ground\tauto\t\t${_zero}0.933333\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_corned|4\t171329\tSpices, paprika\tauto\t\t${_zero}0.900000\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
  '$_corned|5\t170917\tSpices, bay leaf\tauto\t\t${_zero}0.866667\t0.00\t0.00\tdiscarded in cooking — counted as 0 g',
];

void partC() {
  test(
    'C8: the rinsed cure rows, every stored column, and both recipes per serving',
    () async {
      final (db, rs) = await _whole([_confit, _corned]);
      for (final want in _cured) {
        final [key, ...columns] = want.split('\t');
        final [file, position] = key.split('|');
        expect(
          await _columnsOf(db, rs[file]!, int.parse(position)),
          columns.join('\t'),
          reason: key,
        );
      }
      // The medium each answers: the sugar a brine's sugar, every other line
      // a brine's (C6); the corned beef's |0 salt the shipped body's brine.
      final media = [
        for (final (file, positions) in [
          (_confit, [0, 1, 2, 3, 4, 5]),
          (_corned, [0, 1, 5, 6]),
        ])
          for (final k in positions)
            '$k ${discardedMediumOf(rs[file]!, nutritionLines(rs[file]!)[k], normalizeItem(lineItemOf(nutritionLines(rs[file]!)[k])))?.name}',
      ];
      expect(media, [
        '0 brine', '1 brine', '2 brine', '3 brineSugar', '4 brine', '5 null', //
        '0 brine', '1 brine', '5 brine', '6 null',
      ]);
      final perServing = [
        for (final f in [_confit, _corned])
          db.nutritionFor(rs[f]!.id)!.caloriesPerServing?.toStringAsFixed(2),
      ];
      // The fresh compute (the replay: 500.72 → 439.59, 584.11 → 577.55).
      expect(perServing, ['439.59', '577.62']);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test('A2: the matches GET reads the confit|0 onion at 0 g', () async {
    final (db, rs) = await _whole([_confit]);
    final body = await matchesBody(db, _fx, rs[_confit]!);
    final m = ((body['items']! as List)[0] as Map)['match'] as Map;
    expect(
      (
        m['fdc_id'],
        (m['grams'] as num?)?.toStringAsFixed(2),
        m['hold'],
        m['gram_basis'],
      ),
      (790646, '0.00', null, 'discarded in cooking — counted as 0 g'),
    );
  });
  // A11 (closer round 1): the person's verbs that reach `discardedMediumOf`
  // through `derivedFor` (its `dropGrams` and `keepTyped` reads) on a line
  // the new reader now answers — the confit's |0 onion, in its whole
  // recipe: a Confirm, a pick of another record (SR 170000 "Onions, raw")
  // and a typed amount. Each reads as the SHIPPED body's brine line does
  // under the same verb (measured on
  // new-englandstyle-home-corned-beef-and-cabbage|0, the salt the body
  // answers `brine`: a Confirm or a pick keeps
  // 0 g with the decided row's basis "poured away — counted as 0 g", a typed
  // amount is counted as typed) — no new person-path wording.
  for (final (verb, body, want) in [
    (
      'Confirm',
      {'confirmed': true},
      '790646|0.00|confirmed|null|0.936667|poured away — counted as 0 g',
    ),
    (
      'pick 170000',
      {'fdc_id': 170000},
      '170000|0.00|overridden|null|1.000000|poured away — counted as 0 g',
    ),
    (
      'typed 100 g',
      {'grams': 100},
      '790646|100.00|overridden|null|0.936667|entered by hand',
    ),
  ]) {
    test('A11: $verb on the confit|0 onion', () async {
      final (db, rs) = await _whole([_confit]);
      final r = rs[_confit]!;
      await applyMatchOverride(db, _fx, r, 0, body);
      final row = d.rowOf(db, r, 0);
      expect(
        '${row.fdcId}|${row.grams?.toStringAsFixed(2)}|${row.status}|'
        '${row.hold}|${row.confidence.toStringAsFixed(6)}|'
        '${gramBasisFor(db, nutritionLines(r)[0], row, recipe: r)}',
        want,
      );
    });
  }
  // A11: `derivedFor`'s `keepTyped` reads the medium only once the line's
  // amount moves under typed grams — a typed amount, then the line edited
  // ("4 large onions, chopped coarse (6 cups)" for the corpus's "3 … (4¾
  // cups)"; a STATED synthesized edit of the corpus line): the grams typed
  // stay, as on any discarded-medium line.
  test('A11: typed 100 g, then the confit|0 amount edited', () async {
    final (db, rs) = await _whole([_confit]);
    final r = rs[_confit]!;
    await applyMatchOverride(db, _fx, r, 0, {'grams': 100});
    final lines = nutritionLines(r);
    final edited = r.copyWith(
      ingredients: [
        IngredientGroup(
          items: [
            lines[0].copyWith(
              raw: '4 large onions, chopped coarse (6 cups)',
              amounts: [
                for (final m in lines[0].amounts)
                  m.copyWith(
                    quantity: m.measure == Measure.volume ? '6' : '4',
                  ),
              ],
            ),
            ...lines.skip(1),
          ],
        ),
      ],
    );
    await d.editAndCompute(db, _fx, edited);
    final row = d.rowOf(db, edited, 0);
    expect(
      '${row.fdcId}|${row.grams?.toStringAsFixed(2)}|${row.status}|'
          '${row.gramSource}',
      '790646|100.00|overridden|override',
    );
  });
  // C5 / C2: the negatives the corpus decides (each recipe reads no rinsed
  // cure) and one held vegetable salt keeping its shipped answer.
  for (final (file, why) in [
    (
      '0168-roast-salted-turkey.yaml',
      'an "excess" rinse: "Rinse off any excess salt …"',
    ),
    (_miso, 'a negated rinse: "… (do not rinse)"'),
    (
      '0203-skillet-barbecued-pork-chops.yaml',
      'the step gate: "Combine the rub ingredients" reads the noun; the brine rinse names the food',
    ),
    (
      '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
      // The owner gate, 2026-11-20: no step gate holds this one — its step
      // begins "While the turkey brines," — the sentence is read as an
      // application and names no line (docs/API.md "Matcher v122", STATED).
      'an application that names no line: "Spread the bread … on two rimmed baking sheets"',
    ),
    (
      '0506-chinese-pork-dumplings.yaml',
      'the word-bound rub: "rubber spatula" … "Rinse skillet"',
    ),
    (
      '0091-home-corned-beef-with-vegetables.yaml',
      'a brine, no rub or spread: "Remove brisket from brine, rinse, and pat dry"',
    ),
    (_gravlax, 'a cure patted dry, never rinsed'),
  ]) {
    test('C5: $file reads no rinsed cure — $why', () {
      expect(rinsedCureLinesForTest(loadCorpusRecipe(file)), isEmpty);
    });
  }
  test(
    'C3 (synthesized from the corpus recipe, a STATED exception): steak-tacos with its scrape spelled as a rinse — the share set '
    'aside (|6, the lime juice) is not the paste',
    () {
      final corpus = loadCorpusRecipe(_tacos);
      final steps = [
        for (final s in corpus.steps)
          s.copyWith(
            text: s.text.replaceFirst(
              'Scrape the herb paste off the steak and sprinkle',
              'Rinse the steak and sprinkle',
            ),
          ),
      ];
      final r = corpus.copyWith(steps: steps);
      // The paste |0 |3 |4 |5 and the salt |8 rubbed on; never |6.
      expect(rinsedCureLinesForTest(r).toList()..sort(), [0, 3, 4, 5, 8]);
    },
  );
  test(
    'C2: a held vegetable salt keeps its shipped answer (creamy-coleslaw|2)',
    () {
      final r = loadCorpusRecipe('0057-creamy-coleslaw.yaml');
      final line = nutritionLines(r)[2];
      expect(
        discardedMediumOf(r, line, normalizeItem(lineItemOf(line))),
        DiscardedMedium.saltBath,
      );
    },
  );
}

/// C11: the flag on each scraped line (engine level, `m50FlagOf`), and the
/// stored basis of one row in its whole recipe.
const _scrapedFlag =
    'approximate (scraped off the food — how much clings is not written)';

void scraped() {
  for (final (file, flagged, unflagged) in [
    (_miso, [0, 1, 2, 3], [4, 5]),
    // |1 "3 medium scallions" (head 'onion') and |2 "1 medium jalapeño
    // chile" (head 'pepper') are named by no step sentence in the engine's
    // words; |6 the lime juice whisked into the share set aside; |8 the salt
    // rubbed on under the paste.
    (_tacos, [0, 3, 4, 5], [1, 2, 6, 7, 8, 9, 10]),
    (_gravlax, [4], [0, 1, 2, 3]),
  ]) {
    test('C11: $file — the scraped lines flagged, the rest not', () {
      final r = loadCorpusRecipe(file);
      final lines = nutritionLines(r);
      expect(
        [for (final k in flagged) m50FlagOf(r, lines[k])],
        List.filled(flagged.length, _scrapedFlag),
      );
      expect([
        for (final k in unflagged) m50FlagOf(r, lines[k]),
      ], everyElement(isNull));
    });
  }
  test('C11: the stored basis of miso-marinated-salmon|0', () async {
    final (db, rs) = await _whole([_miso]);
    expect(
      await _columnsOf(db, rs[_miso]!, 0),
      '172442\tMiso\tauto\t\tportion\t0.575000\t137.50\t272.25\t1/2 cup · USDA portion · $_scrapedFlag',
    );
  });
  for (final (file, why) in [
    (
      '0939-make-ahead-chocolate-souffles.yaml',
      'scrape … from the bottom of the bowl',
    ),
    (
      '1148-omelet-with-cheddar-and-chives.yaml',
      'scrape eggs from sides of skillet',
    ),
    (
      '1181-jellied-cranberry-sauce.yaml',
      'scrape mixture from bottom of strainer',
    ),
    (
      '1139-alu-parathas-punjabi-potato-stuffed-griddle-breads.yaml',
      'brush any remaining flour from both sides',
    ),
    ('0407-eggplant-parmesan.yaml', 'an "excess" wipe on a held row'),
    (
      '0580-grilled-marinated-flank-steak.yaml',
      'a sub-recipe paste wiped off, held `discarded_recipe`',
    ),
  ]) {
    test('C11: $file flags nothing — $why', () {
      expect(scrapedOffLinesForTest(loadCorpusRecipe(file)), isEmpty);
    });
  }
}

/// C5 / C11 (A5): one loop over every corpus recipe and titled section —
/// the lines the rinsed-cure reader names and the lines the scraped-off
/// flag names, each set exactly (count and SHA).
void cureProperty() {
  test(
    'the rinsed-cure and scraped-off sets over the whole corpus',
    () {
      final rinsed = <String>[];
      final scraped = <String>[];
      for (final (tag, r) in _scopes()) {
        rinsed.addAll([for (final k in rinsedCureLinesForTest(r)) '$tag|$k']);
        scraped.addAll([for (final k in scrapedOffLinesForTest(r)) '$tag|$k']);
      }
      rinsed.sort();
      scraped.sort();
      expect(rinsed, [
        for (final k in [0, 1, 2, 3, 4, 5]) '$_corned|$k',
        for (final k in [0, 1, 2, 3, 4]) '$_confit|$k',
      ]);
      expect(
        scraped,
        [
          for (final k in [0, 1, 2, 3]) '$_miso|$k',
          for (final k in [0, 3, 4, 5]) '$_tacos|$k',
          '$_gravlax|4',
        ]..sort(),
      );
      expect(
        (_sha(rinsed), _sha(scraped)),
        (
          'a8068d90f73e29a6ac028bfcfac6c15441358cc854d4e92da6f344eb58bd1f59',
          'c1f2e98a2f697df2748d48f8300b15edb42a688a699dab0881ffa50162784631',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _fill(String sentence) =>
    List.filled(capStep ~/ sentence.length, sentence).join().trim();

/// RULE C: the two readers at the caps — 400 lines (the confit's thighs and
/// 399 pepper lines), 120 steps of 10,000 characters. RINSE TRUE: every
/// sentence combines, spreads the mixture over the thighs or rinses them
/// (the last rinse read, every spread before it an application, the making
/// step's every combine sentence carried); SCRAPE TRUE: every third sentence
/// scrapes the mixture off. The counts EXACT (the families of the tip, each
/// once per index or per cut), the clock a backstop. The QUIET shapes are
/// every other cap pin of the suite (each gains `memo:rinsedCureLines` 1,
/// and on a GET `memo:scrapedOff` 1 — re-pinned there).
void caps() {
  group(
    'RULE C, the rinsed cure and the scraped-off flag at the caps',
    skip: skipIfNoCorpus,
    () {
      for (final (shape, sentence, zeroed, compute, get) in [
        (
          'RINSE TRUE',
          'Combine pepper in bowl. Spread pepper mixture over thighs. Rinse thighs. ',
          335,
          '{"allSentences":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:cutShare":1,"memo:defatsLiquid":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:makingStep":1,"memo:mayHoldCoat":1,"memo:measuresOut":1,"memo:mentionLines":1,"memo:mixtureLines":137,"memo:namedHeads":1,"memo:naming":2,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:rinsedCureLines":1,"memo:savesRemainder":1,"memo:setAsideLine":2,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":48960,"skinScans":2,"words":179520}',
          '{"allSentences":1,"carriedReads":2,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:cutShare":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:liftedFromMarinade":1,"memo:makingStep":1,"memo:measuresOut":1,"memo:mentionLines":1,"memo:mixtureLines":137,"memo:namedHeads":1,"memo:naming":2,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:rinsedCureLines":1,"memo:savesRemainder":1,"memo:scrapedOff":1,"memo:setAsideLine":2,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":48960,"skinScans":2,"words":179520}',
        ),
        (
          'SCRAPE TRUE',
          'Combine pepper in bowl. Rub thighs with pepper mixture. Scrape pepper mixture off thighs. ',
          0,
          '{"allSentences":1,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:defatsLiquid":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:measuresOut":1,"memo:naming":2,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:rinsedCureLines":1,"memo:savesRemainder":1,"memo:setAsideLine":2,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":39960,"skinScans":2,"words":186480}',
          '{"allSentences":1,"carriedReads":2,"cheese":1,"heads":1,"indexes":1,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brines":1,"memo:browningFat":1,"memo:bundles":1,"memo:cutShare":1,"memo:dips":1,"memo:discards":1,"memo:foodNaming":1,"memo:keptSolids":1,"memo:leftInBowl":1,"memo:liftedFromMarinade":1,"memo:makingStep":1,"memo:measuresOut":1,"memo:mentionLines":1,"memo:mixtureLines":112,"memo:namedHeads":1,"memo:naming":2,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:reservedWhole":1,"memo:rinsedCureLines":1,"memo:savesRemainder":1,"memo:scrapedOff":1,"memo:setAsideLine":2,"memo:skinSentences":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"sentences":39960,"skinScans":2,"words":186480}',
        ),
      ]) {
        test(
          '$shape: the counts exact, within the backstop',
          () async {
            final dir = Directory.systemTemp.createTempSync('salt-v122-cap-');
            final db = SaltDatabase.open(
              ServerConfig(
                dataDir: dir.path,
                logLevel: Level.WARNING,
                trustProxy: false,
              ).dbPath,
            )..upsertSource(slug: 'atk-tv-2023', name: 'ATK', type: 'epub');
            addTearDown(() {
              db.dispose();
              dir.deleteSync(recursive: true);
            });
            final fdc = FixtureProvider(pending: {...pendingSearches});
            final r =
                capped(loadCorpusRecipe(_confit), [
                  '4 pounds bone-in turkey thighs',
                  ...List.filled(capLines - 1, '1½ teaspoons pepper'),
                ], List.filled(capSteps, _fill(sentence))).copyWith(
                  id: 'cap-$shape',
                  slug: 'cap-$shape',
                );
            db.upsertRecipe(
              r,
              sourceSlug: 'atk-tv-2023',
              contentHash: contentHashOf(r),
            );
            final stored = db.recipeByIdOrSlug(r.id)!.recipe;
            stepIndexCounts.clear();
            final sw = Stopwatch()..start();
            expect(await matchAndCompute(db, fdc, stored), isNull);
            expect(sw.elapsedMilliseconds, lessThan(backstopMs));
            // 'names' (the head patterns compiled, a process-wide cache) depends on
            // the tests run before: not pinned, as v94's caps.
            final computed = Map.of(stepIndexCounts)..remove('names');
            expectBounded(stored, computed, '$shape compute');
            expect(computed, jsonDecode(compute), reason: '$shape compute');
            expect(
              db
                  .ingredientMatchesFor(r.id)
                  .where((m) => m.gramSource == 'discarded')
                  .length,
              zeroed,
            );
            stepIndexCounts.clear();
            sw.reset();
            await matchesBody(db, fdc, db.recipeByIdOrSlug(r.id)!.recipe);
            expect(sw.elapsedMilliseconds, lessThan(backstopMs));
            final got = Map.of(stepIndexCounts)..remove('names');
            expectBounded(stored, got, '$shape GET');
            expect(got, jsonDecode(get), reason: '$shape GET');
          },
          timeout: const Timeout(Duration(minutes: 3)),
        );
      }
    },
  );
}

/// A recipe of [lines] and [steps] (synthesized: a STATED exception — each
/// case below names the gate no corpus line alone decides and the corpus
/// sentence its wording follows).
Recipe _syn(List<String> lines, List<String> steps) => Recipe(
  id: 'syn',
  title: 'syn',
  slug: 'syn',
  source: const RecipeSource(name: 'Test', type: 'book'),
  ingredients: [
    IngredientGroup(
      items: [
        for (final raw in lines)
          () {
            final p = parseIngredientLine(raw);
            return IngredientLine(
              raw: raw,
              item: p.item,
              prep: p.prep,
              amounts: p.amounts,
            );
          }(),
      ],
    ),
  ],
  steps: [
    for (final (i, s) in steps.indexed) RecipeStep(number: i + 1, text: s),
  ],
);

/// The gates no corpus line alone decides, each pinned on a synthesized
/// recipe (STATED exceptions; the wording follows the named corpus
/// sentences).
void synthesized() {
  group('v122 synthesized gates (stated exceptions)', () {
    // The confit's own lines and making step (1077).
    const confitLines = [
      '3 large onions, chopped coarse (4¾ cups)',
      '2½ tablespoons table salt for curing',
      '4½ teaspoons sugar',
      '4 pounds bone-in turkey thighs',
    ];
    const making =
        'Process onions, salt, and sugar in food processor until finely chopped, about 20 seconds. '
        'Arrange turkey thighs in single layer in dish. '
        'Spread remaining onion mixture evenly over thighs.';
    for (final (gate, rinse, want) in [
      // C5 (ruling.md C5, critique c8): "rinse X from FOOD" — the food named
      // AFTER from; the thighs are never zeroed.
      (
        'rinse X from FOOD',
        'Rinse the onion mixture from the thighs.',
        [0, 1, 2],
      ),
      // The confit's own shape (the control): "Remove thighs from onion
      // mixture and rinse well".
      (
        'remove FOOD from X and rinse',
        'Remove thighs from onion mixture and rinse well.',
        [0, 1, 2],
      ),
      // The negation (the miso's "(do not rinse)").
      ('negated', 'Remove thighs from onion mixture (do not rinse).', <int>[]),
      // "excess" (roast-salted-turkey's "Rinse off any excess salt").
      (
        'excess',
        'Remove thighs from onion mixture and rinse off the excess.',
        <int>[],
      ),
      // The rinse anywhere in its sentence, not only at its start.
      ('rinse at the start', 'Rinse thighs well.', [0, 1, 2]),
    ]) {
      test('C1: $gate', () {
        final r = _syn(confitLines, [making, rinse]);
        expect(rinsedCureLinesForTest(r).toList()..sort(), want);
      });
    }
    // C1 (3): an application's own words — the spread's over / on (the
    // confit's "Spread one-third of mixture evenly in bottom of … dish" reads
    // neither; no corpus line alone decides it) and the word-bound rub
    // ("rubber spatula", chinese-pork-dumplings); C3: the carry's `pulse`
    // alone (the corpus's pulse sentences also say "food processor").
    for (final (gate, lines, steps, want) in [
      (
        'a spread with no over / on',
        confitLines,
        [
          'Process onions, salt, and sugar in food processor. Arrange turkey thighs in single layer in dish. Spread remaining onion mixture evenly.',
          'Remove thighs from onion mixture and rinse well.',
        ],
        <int>[],
      ),
      (
        'rubber is no rub',
        confitLines,
        [
          'Process onions, salt, and sugar in food processor. Arrange turkey thighs in single layer in dish. Using rubber spatula, press onion mixture against thighs.',
          'Remove thighs from onion mixture and rinse well.',
        ],
        <int>[],
      ),
      (
        'pulse alone makes the mixture',
        [
          '½ cup packed fresh cilantro leaves',
          '3 medium garlic cloves, roughly chopped',
          '1 (1½-pound) flank steak, trimmed',
        ],
        [
          'Pulse the cilantro and garlic until finely chopped.',
          'Rub the steak with the herb paste.',
          'Rinse the steak.',
        ],
        [0, 1],
      ),
      (
        // C3's set-aside exclusion, its `reserv` arm (closer round 1): the
        // corpus's one set-aside mix sentence (steak-tacos: "Transfer 2
        // tablespoons of the herb paste to a medium bowl; whisk in the lime
        // juice and set aside.") reads `set aside`; this one says "reserve"
        // — the lime juice whisked into the share kept is not the cure.
        'a mix sentence that reserves a share',
        [
          '½ cup packed fresh cilantro leaves',
          '3 medium garlic cloves, roughly chopped',
          '1 tablespoon lime juice',
          '1 (1½-pound) flank steak, trimmed',
        ],
        [
          'Pulse the cilantro and garlic until finely chopped. Whisk the lime juice into 2 tablespoons of the herb paste and reserve.',
          'Rub the steak with the herb paste.',
          'Rinse the steak.',
        ],
        [0, 1],
      ),
    ]) {
      test('C1 / C3: $gate', () {
        final r = _syn(lines, steps);
        expect(rinsedCureLinesForTest(r).toList()..sort(), want);
      });
    }
    // C2: the wrapper asks the new reader only where the shipped body gives
    // no medium — a cure line the body already reads keeps the body's
    // answer (no corpus cure line holds a frying oil: the corned beef's |0
    // salt reads `brine` either way). The wording follows the confit's.
    test('C2: the shipped answer first (a frying oil in a rinsed cure)', () {
      final r = _syn(
        ['6 cups vegetable oil for frying', ...confitLines],
        [
          [
            'Process oil, onions, salt, and sugar in food processor.',
            'Arrange turkey thighs in single layer in dish.',
            'Spread remaining onion mixture evenly over thighs.',
          ].join(' '),
          'Remove thighs from onion mixture and rinse well.',
        ],
      );
      final oil = nutritionLines(r)[0];
      expect(rinsedCureLinesForTest(r), contains(0));
      expect(
        discardedMediumOf(r, oil, normalizeItem(lineItemOf(oil))),
        DiscardedMedium.fryingOil,
      );
    });
    // C2: never on a coat-only read nor a read without the sentences
    // (`_coatingAt`, the `bySentence: false` sites): no corpus path reads a
    // rinsed-cure line so. The confit's lines.
    test('C2: no answer on a coatOnly or a bySentence: false read', () {
      final r = _syn(confitLines, [
        making,
        'Remove thighs from onion mixture and rinse well.',
      ]);
      final onion = nutritionLines(r)[0];
      final n = normalizeItem(lineItemOf(onion));
      expect(
        (
          discardedMediumOf(r, onion, n)?.name,
          discardedMediumOf(r, onion, n, coatOnly: true)?.name,
          discardedMediumOf(r, onion, n, bySentence: false)?.name,
        ),
        ('brine', null, null),
      );
    });
    // C11: each gate no corpus line alone decides — the wording follows
    // gravlax ("Cover with dill, pressing firmly to adhere." … "Scrape off
    // dill.") and grilled-marinated-flank-steak ("wipe paste off steak").
    for (final (gate, lines, steps, want) in [
      (
        'wipe',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        [
          'Cover salmon with dill, pressing firmly to adhere.',
          'Using paper towels, wipe dill off salmon.',
        ],
        [0],
      ),
      (
        'an object no earlier sentence put on the food',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        ['Place salmon in dish.', 'Scrape off dill.'],
        <int>[],
      ),
      (
        'the food named after off',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        [
          'Cover salmon with dill, pressing firmly to adhere.',
          'Scrape dill and salmon off the salmon.',
        ],
        [0],
      ),
      (
        'an excess wipe',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        [
          'Cover salmon with dill, pressing firmly to adhere.',
          'Wipe off the excess dill.',
        ],
        <int>[],
      ),
      (
        // A vessel in the object (the corpus's vessel scrapes name it after
        // from: "scrape eggs from sides of skillet").
        'a vessel in the object',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        [
          'Cover salmon with dill, pressing firmly to adhere.',
          'Scrape the dill and foil off the salmon.',
        ],
        <int>[],
      ),
      (
        // A scrape down (the tacos' "scraping down the sides of the
        // workbowl", which names no off or from).
        'a scrape down',
        ['1 cup chopped fresh dill', '1 (1-pound) skin-on salmon fillet'],
        [
          'Cover salmon with dill, pressing firmly to adhere.',
          'Scrape down dill from salmon.',
        ],
        <int>[],
      ),
      (
        'a marinade word',
        ['½ cup soy sauce', '1 (1-pound) skin-on salmon fillet'],
        [
          'Whisk soy sauce in bowl. Coat salmon with marinade.',
          'Scrape marinade off salmon.',
        ],
        [0],
      ),
    ]) {
      test('C11: $gate', () {
        expect(
          scrapedOffLinesForTest(_syn(lines, steps)).toList()..sort(),
          want,
        );
      });
    }
    // THE OWNER GATE (2026-11-20). One word dropped from each word list of
    // the two readers, and three structural mutants, passed this file as
    // the batch left it — the corpus property with it, so none decides a
    // corpus row. Each is pinned below on a synthesized recipe (STATED
    // exceptions; the wording follows the confit's, the tacos' and gravlax's
    // sentences), each case naming its gate in its `reason`.
    const prep =
        'Process onions, salt, and sugar in food processor. '
        'Arrange turkey thighs in single layer in dish.';
    const spread = 'Spread remaining onion mixture evenly over thighs.';
    const blend =
        'Blend onions, salt, and sugar until smooth. '
        'Arrange turkey thighs in single layer in dish.';
    const rinsed = 'Remove thighs from onion mixture and rinse well.';
    const canned =
        'Spread remaining onion mixture and 1 (14.5-ounce) can diced '
        'tomatoes evenly over thighs.';
    test('C1 (owner gate): each rinse form, negation, rub form, over / on '
        'and mixture word alone', () {
      for (final (gate, steps, want) in [
        // `_cureRinse`'s forms.
        (
          'rinses',
          [
            '$prep $spread',
            'The cook removes thighs from onion mixture and rinses them well.',
          ],
          [0, 1, 2],
        ),
        (
          'rinsed',
          [
            '$prep $spread',
            'Thighs are removed from onion mixture and rinsed well.',
          ],
          [0, 1, 2],
        ),
        (
          'rinsing',
          ['$prep $spread', 'Remove thighs from onion mixture, rinsing well.'],
          [0, 1, 2],
        ),
        // `_rinseNegated`'s spellings (the miso's is "do not").
        (
          "don't (straight)",
          ['$prep $spread', "Remove thighs from onion mixture (don't rinse)."],
          <int>[],
        ),
        (
          'don’t (curly)',
          ['$prep $spread', 'Remove thighs from onion mixture (don’t rinse).'],
          <int>[],
        ),
        (
          'without',
          [
            '$prep $spread',
            'Remove thighs from onion mixture without rinsing.',
          ],
          <int>[],
        ),
        // `_rubWord`'s forms (the corned beef's is the bare "Rub").
        (
          'rubs',
          ['$prep The cook rubs thighs with onion mixture.', rinsed],
          [0, 1, 2],
        ),
        (
          'rubbed',
          ['$prep Thighs are rubbed with onion mixture.', rinsed],
          [0, 1, 2],
        ),
        (
          'rubbing',
          ['$prep Finish by rubbing onion mixture into thighs.', rinsed],
          [0, 1, 2],
        ),
        // `_overOrOn`'s "on" (the confit's is "over").
        (
          'on',
          ['$prep Spread remaining onion mixture evenly on thighs.', rinsed],
          [0, 1, 2],
        ),
        // A period INSIDE the sentence does not end the spread's read
        // (the cookbook's own can-size print; the owner gate's correction:
        // the batch stopped at the sentence's next period).
        (
          'an inner period',
          ['$prep $canned', rinsed],
          [0, 1, 2],
        ),
        // `_mixtureWord`'s other words (both corpus cures say "mixture").
        (
          'paste',
          ['$prep Spread remaining onion paste evenly over thighs.', rinsed],
          [0, 1, 2],
        ),
        (
          'cure',
          ['$prep Spread remaining cure evenly over thighs.', rinsed],
          [0, 1, 2],
        ),
        (
          'rub (the noun)',
          ['$prep Spread remaining onion rub evenly over thighs.', rinsed],
          [0, 1, 2],
        ),
        // The making step's `blend` (the corpus cures process and combine).
        (
          'blend',
          ['$blend $spread', rinsed],
          [0, 1, 2],
        ),
        // The LAST qualifying rinse is the one read: an earlier rinse of
        // the food, before the cure goes on, is not it.
        (
          'the last rinse',
          ['Rinse thighs and pat dry.', '$prep $spread', rinsed],
          [0, 1, 2],
        ),
        // The making step is the FIRST step holding a mix sentence: a later
        // one (a sauce whisked after the rinse) is not it.
        (
          'the first mix step',
          ['$prep $spread', rinsed, 'Whisk pan juices until smooth.'],
          [0, 1, 2],
        ),
      ]) {
        expect(
          rinsedCureLinesForTest(_syn(confitLines, steps)).toList()..sort(),
          want,
          reason: gate,
        );
      }
    });
    // A mixture named BEFORE the recipe's first mix step is not that step's:
    // the sauce whisked later is not the rub.
    test('C3 (owner gate): a mixture named before the first mix step '
        'carries nothing', () {
      final r = _syn(
        [
          '¼ cup soy sauce',
          '2 tablespoons honey',
          '4 pounds bone-in turkey thighs',
        ],
        [
          'Arrange turkey thighs in dish. Rub thighs with spice mixture.',
          'Whisk soy sauce and honey in bowl.',
          'Rinse thighs well.',
        ],
      );
      expect(rinsedCureLinesForTest(r), isEmpty);
    });
    const dill = [
      '1 cup chopped fresh dill',
      '1 (1-pound) skin-on salmon fillet',
    ];
    List<int> scraped(List<String> lines, List<String> steps) =>
        scrapedOffLinesForTest(_syn(lines, steps)).toList()..sort();
    test('C11 (owner gate): each put-on verb, mixture noun and refused '
        'scrape alone', () {
      // `_putsOn`'s verbs (gravlax's sentence holds two: cover, press).
      for (final put in [
        'Rub salmon with dill.',
        'Cover salmon with dill.',
        'Press dill onto salmon.',
        'Coat salmon with dill.',
        'Spread dill over salmon.',
        'Pack dill around salmon.',
        'Sprinkle salmon with dill.',
      ]) {
        expect(scraped(dill, [put, 'Scrape off dill.']), [0], reason: put);
      }
      // `_scrapedMixture`'s other nouns (the corpus says mixture and paste;
      // the batch pins marinade).
      for (final noun in ['cure', 'rub', 'coating', 'glaze']) {
        expect(
          scraped(
            ['½ cup soy sauce', '1 (1-pound) skin-on salmon fillet'],
            [
              'Whisk soy sauce in bowl. Coat salmon with $noun.',
              'Scrape $noun off salmon.',
            ],
          ),
          [0],
          reason: noun,
        );
      }
      // `_scrapesOff`'s first shape with a wipe ("wipe off X").
      expect(
        scraped(dill, ['Cover salmon with dill.', 'Wipe off dill.']),
        [0],
        reason: 'wipe off',
      );
      // `_scrapeNot`'s other words (the batch pins "excess" and a scrape
      // down).
      for (final not in [
        'Scrape up dill from salmon.',
        'Wipe out dill from salmon.',
        'Wipe clean dill from salmon.',
        'Wipe down dill from salmon.',
      ]) {
        expect(
          scraped(dill, ['Cover salmon with dill.', not]),
          isEmpty,
          reason: not,
        );
      }
    });
    test('C11 (owner gate): each vessel word alone, in the object and '
        'after off', () {
      // `_scrapedVessel`: a vessel word in the object.
      for (final vessel in [
        'bowl',
        'pot',
        'pan',
        'skillet',
        'wok',
        'sheet',
        'grate',
        'grill',
        'board',
        'sides',
        'bottom',
        'rack',
        'foil',
        'parchment',
        'towel',
      ]) {
        expect(
          scraped(dill, [
            'Cover salmon with dill, pressing firmly to adhere.',
            'Scrape the dill and $vessel off the salmon.',
          ]),
          isEmpty,
          reason: 'object: $vessel',
        );
      }
      // `_vesselTail`'s second list, the words its first does not hold.
      for (final vessel in [
        'wok',
        'sheet',
        'grate',
        'grill',
        'board',
        'rack',
        'foil',
        'parchment',
        'towel',
      ]) {
        expect(
          scraped(dill, [
            'Cover salmon with dill.',
            'Scrape dill off $vessel.',
          ]),
          isEmpty,
          reason: 'after off: $vessel',
        );
      }
      // `_vesselTail`'s first list behind "the " and "both ".
      for (final vessel in [
        'the bottom',
        'the sides',
        'the bowl',
        'the strainer',
        'the skillet',
        'the pan',
        'the pot',
        'both sides',
      ]) {
        expect(
          scraped(dill, [
            'Cover salmon with dill.',
            'Scrape dill off $vessel.',
          ]),
          isEmpty,
          reason: 'after off: $vessel',
        );
      }
    });
    test("C11 (owner gate): the scrape's shapes — a determiner, a longer "
        'object, each way the object ends', () {
      for (final (gate, scrape, want) in [
        ('off the …', 'Scrape off the fresh chopped dill.', [0]),
        ('off any …', 'Scrape off any fresh chopped dill.', [0]),
        ('a two-word object after off', 'Scrape off chopped dill.', [0]),
        ('ends at a comma', 'Scrape off dill, then pat salmon dry.', [0]),
        ('ends at a semicolon', 'Scrape off dill; pat salmon dry.', [0]),
        ('ends at and', 'Scrape off dill and pat salmon dry.', [0]),
        // The food after from is not the object.
        ('ends at from', 'Scrape off dill from salmon.', [0]),
        ('ends with the step (no period)', 'Scrape off dill', [0]),
        ('the … off', 'Scrape the fresh chopped dill off salmon.', [0]),
        ('any … off', 'Scrape any fresh chopped dill off salmon.', [0]),
      ]) {
        expect(
          scraped(dill, ['Cover salmon with dill.', scrape]),
          want,
          reason: gate,
        );
      }
    });
  });
}
