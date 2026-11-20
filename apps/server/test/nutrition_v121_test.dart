// The v121 pins (batch M108, prep52 P9 E1: measured step salt behind the
// seasoning zero rule; matcherVersion 107). Sodium only: every moved row is
// SR 173468 "Salt, table" at 0.00 kcal. An amount-less seasoning line whose
// item names salt (`seasoningSaltOf`: the set's salt spelling before " and ";
// the corpus typo "table alt" mended) is read by R-H1 with the FORM `salt`
// (`_readHeadsOf`), guard (i) by NAMING (`_saltNamedElsewhere`: no other line
// of its scope names salt), guards (ii) and (iii) as shipped. The line is a
// food row (`measuredStepSalt`) when the reading is not empty, at least one
// print is not lost (`_lostSaltPrint`, arms (a)–(e), (c') and (e') the
// critic's narrowings), no coat station holds it (`_dipsOf`,
// `_batterInBowl`), and no medium takes the line or any print
// (`discardedMediumOf`, per print through `_printedSaltLine`); a lost print
// is dropped and named after R-H1's basis (" · not counted: … the steps
// drain off or discard", the owner's wording to rule on). Every other such
// line stays the 0 g `confirmed` rule row. Corpus-backed groups skip without
// SALT_CORPUS_DIR; every corpus read sits inside a test body or setUpAll.
//
// Hand derivations (the step's printed amount × grams.dart's densities, the
// engine's: 'salt' 1.22 g/mL = 6.0133 g a teaspoon, 18.04 g a tablespoon;
// 'kosher salt' 0.60865 g/mL = 3.00 g a teaspoon where the line names
// kosher — `packsLikeKosherSalt`): breakfast-strata-with-spinach-and-
// gruyere|4 "Table salt and ground black pepper", step 3 "1 teaspoon salt"
// = 6.01 g; simple-pot-au-feu|1 "Kosher salt", step 1 "1 tablespoon salt" =
// 3 × 3.00 = 9.00 g; brazilian-shrimp-and-fish-stew-moqueca|8 "Table alt
// and pepper", ½ + ½ + ½ teaspoon = 9.02 g; creamy-baked-four-cheese-pasta|2,
// ¼ + ¼ teaspoon = 3.01 g, step 3's "1 tablespoon salt" into the pasta water
// (drained) not counted. Sodium: SR 173468 nutrient 307 = 38,758 mg per 100
// g in the snapshot's cache.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

const _strata = '0743-breakfast-strata-with-spinach-and-gruyere.yaml';
const _risotto = '0713-almost-hands-free-risotto-with-parmesan-and-herbs.yaml';
const _pistou = '0029-soupe-au-pistou-provencal-vegetable-soup.yaml';
const _potAuFeu = '0092-simple-pot-au-feu.yaml';
const _porkTenderloin = '0236-broiled-pork-tenderloin.yaml';

/// R11: moved rows computed in their WHOLE recipe on the fixtures —
/// "file|position", record, description, status, hold, gram source,
/// confidence, grams, kcal, basis; each the v121 replay's row (snapshot 33).
/// grilled-mojo-marinated-skirt-steak|5 and spanish-chilled-almond-and-
/// garlic-soup|5 (the (c') and (e') rows) are pinned at the engine in
/// [_arms]: the fixtures hold no "skirt steak" / "blanched almonds" search.
const _moved = [
  '$_strata|4\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t6.01\t0.00\tfrom step 3: 1 teaspoon (no amount on the line)',
  '0284-brazilian-shrimp-and-fish-stew-moqueca.yaml|8\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t9.02\t0.00\tfrom steps 2, 4: ½ teaspoon + ½ teaspoon + ½ teaspoon (no amount on the line)',
  '$_potAuFeu|1\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t9.00\t0.00\tfrom step 1: 1 tablespoon (no amount on the line)',
  '0366-creamy-baked-four-cheese-pasta.yaml|2\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t3.01\t0.00\tfrom steps 1, 4: ¼ teaspoon + ¼ teaspoon (no amount on the line) · not counted: 1 tablespoon the steps drain off or discard',
  '0403-italian-chicken-soup-with-parmesan-dumplings.yaml|1\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t3.01\t0.00\tfrom step 2: ½ teaspoon (no amount on the line)',
  '0222-best-prime-rib.yaml|1\t173468\tSalt, table\tauto\t\tdensity\t1.000000\t18.00\t0.00\tfrom step 1: 2 tablespoons (no amount on the line)',
];

/// Q7: each arm of `_lostSaltPrint` and each condition of the count on a
/// real corpus row it ALONE decides (re-measured on this tree: the class
/// probe with that one arm removed moves exactly these rows), plus the
/// negatives. `rule` = the line stays the 0 g seasoning rule row; else the
/// grams and basis `stepAmountGrams` writes on SR 173468.
const _arms = [
  // (a) S names water, wine or a brine and a later sentence drains.
  (
    '0366-creamy-baked-four-cheese-pasta.yaml',
    2,
    '3.01 from steps 1, 4: ¼ teaspoon + ¼ teaspoon (no amount on the line) · not counted: 1 tablespoon the steps drain off or discard',
  ),
  ('0728-poached-eggs.yaml', 0, 'rule'),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    2,
    '1.50 from step 6: ½ teaspoon (no amount on the line) · not counted: 1 teaspoon the steps drain off or discard',
  ),
  // (b) the rest of the print's step drains, squeezes, wrings or soaks.
  ('0017-mushroom-bisque.yaml', 3, 'rule'),
  (
    '0700-duck-fatroasted-potatoes.yaml',
    1,
    '3.00 from step 2: 1 teaspoon (no amount on the line) · not counted: ⅓ cup the steps drain off or discard',
  ),
  ('0689-crispy-potato-latkes.yaml', 2, 'rule'),
  // (c') a crumb station that dredges / lets the excess off / coats.
  ('0122-chicken-kiev.yaml', 8, 'rule'),
  ('0416-lighter-chicken-parmesan.yaml', 5, 'rule'),
  (
    '0117-nut-crusted-chicken-breasts-with-lemon-and-thyme.yaml',
    1,
    '1.50 from step 1: ½ teaspoon (no amount on the line) · not counted: ½ teaspoon the steps drain off or discard',
  ),
  // (c') negative: a coat word with no crumb — "Flip steaks to coat both
  // sides with marinade" — the marinade is eaten.
  (
    '0590-grilled-mojo-marinated-skirt-steak.yaml',
    5,
    '4.51 from step 1: ¾ teaspoon (no amount on the line)',
  ),
  // (d) S names chicken and the skin is discarded.
  ('0095-lighter-chicken-and-dumplings.yaml', 1, 'rule'),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    17,
    '1.50 from step 4: ¼ teaspoon (no amount on the line) · not counted: ½ teaspoon the steps drain off or discard',
  ),
  // (e') a remainder kept for another use / discarded that names a liquid.
  ('0490-spicy-pork-tacos-al-pastor.yaml', 5, 'rule'),
  ('0046-cherry-tomato-salad-with-feta-and-olives.yaml', 2, 'rule'),
  (
    '0494-braised-new-mexicostyle-pork-in-red-chile-sauce-carne-adovada.yaml',
    1,
    '3.00 from step 3: 1 teaspoon (no amount on the line) · not counted: 1 tablespoon the steps drain off or discard',
  ),
  // (e') negatives: the remainder names no liquid (the crumbs; the garnish).
  (
    '0403-italian-chicken-soup-with-parmesan-dumplings.yaml',
    1,
    '3.01 from step 2: ½ teaspoon (no amount on the line)',
  ),
  (
    '0032-spanish-chilled-almond-and-garlic-soup.yaml',
    5,
    '4.50 from steps 3, 5: 1¼ teaspoons + ¼ teaspoon (no amount on the line)',
  ),
  // A negative of (a) and (b): "Transfer drained tomatoes" — `drained`
  // is no drain verb.
  (
    '0347-shrimp-fra-diavolo.yaml',
    1,
    '3.01 from step 1: ½ teaspoon (no amount on the line)',
  ),
  // The count: every print lost (the bean soak, (a) and (b) together).
  ('0406-hearty-tuscan-bean-stew.yaml', 0, 'rule'),
  // The per-print medium ask (closer 1): pot water, a purpose line, a brine.
  ('0058-cool-and-creamy-macaroni-salad.yaml', 0, 'rule'),
  ('0369-hand-rolled-meat-ravioli.yaml', 16, 'rule'),
  ('0198-sauteed-pork-cutlets-with-mustard-cider-sauce.yaml', 0, 'rule'),
  // The coat-station exclusion (a dip M52 plans).
  ('0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml', 2, 'rule'),
  // Guard (i) by naming (another line names salt: "… or celery salt").
  ('0302-light-macaroni-and-cheese.yaml', 0, 'rule'),
  // The weigh under the salt part: "… and ground black pepper" at salt's
  // 1.22 g/mL, never pepper's.
  (_strata, 4, '6.01 from step 3: 1 teaspoon (no amount on the line)'),
  // Kosher: 3.00 g a teaspoon.
  (_potAuFeu, 1, '9.00 from step 1: 1 tablespoon (no amount on the line)'),
];

void main() {
  test('matcherVersion 107', () => expect(matcherVersion, 107));
  group('v121 (M108: measured step salt)', skip: skipIfNoCorpus, () {
    arms();
    section();
    moved();
    travel();
    ownVerbs();
    ruleRowSibling();
    label();
    coatStation();
    property();
  });
  caps();
  synthesized();
}

String _reading(Recipe r, int position, FdcFood salt) {
  final line = nutritionLines(r)[position];
  final n = normalizeItem(lineItemOf(line));
  if (!measuredStepSalt(r, line, n)) {
    return 'rule';
  }
  final g = stepAmountGrams(r, line, salt, n)!;
  return '${g.grams.toStringAsFixed(2)} ${g.basis}';
}

/// Q7 / R11: the per-arm rows and the negatives (engine level, each whole
/// corpus recipe on its own steps).
void arms() {
  test('Q7: each arm and condition on the row it alone decides', () async {
    final salt = (await _fx.food(173468))!;
    for (final (file, position, want) in _arms) {
      expect(
        _reading(loadCorpusRecipe(file), position, salt),
        want,
        reason: '$file|$position',
      );
    }
  });
}

/// R11: a section's line on the section's own steps — tamales "Red Chile
/// Chicken Filling" |7 "Salt and pepper", step 2's ½ teaspoon.
void section() {
  test('tamales §0 "Red Chile Chicken Filling" |7: 3.01 g', () async {
    final host = loadCorpusRecipe('0475-tamales.yaml');
    final sub = host.subsections.first;
    expect(sub.title, 'Red Chile Chicken Filling');
    final r = sectionRecipeOf(host, sub);
    expect(nutritionLines(r)[7].raw, 'Salt and pepper');
    expect(
      _reading(r, 7, (await _fx.food(173468))!),
      '3.01 from step 2: ½ teaspoon (no amount on the line)',
    );
  });
}

/// A database holding [files] computed whole on the fixtures (the recipe
/// ids are the corpus ids; each once).
Future<(SaltDatabase, Map<String, Recipe>)> _computed(
  List<String> files,
) async {
  final (db, _) = a.pathDb();
  final out = <String, Recipe>{};
  for (final f in files) {
    final r = loadCorpusRecipe(f);
    await d.editAndCompute(db, _fx, r);
    out[f] = r;
  }
  return (db, out);
}

String _columnsOf(SaltDatabase db, Recipe r, int position) {
  final row = d.rowOf(db, r, position);
  final line = nutritionLines(r)[position];
  return [
    row.fdcId,
    row.description,
    row.status,
    row.hold ?? '',
    row.gramSource,
    row.confidence.toStringAsFixed(6),
    row.grams?.toStringAsFixed(2),
    // Salt has no energy: SR 173468's 208 is 0.0.
    (row.grams! * 0).toStringAsFixed(2),
    gramBasisFor(db, line, row, recipe: r),
  ].join('\t');
}

/// R11 / A2: every stored column the rule writes on the moved rows, the GET
/// and the label's sodium a serving.
void moved() {
  test(
    'the moved rows: every stored column and the basis, in the whole recipe',
    () async {
      final files = {for (final w in _moved) w.split('|').first}.toList();
      final (db, recipes) = await _computed(files);
      for (final want in _moved) {
        final [key, ...columns] = want.split('\t');
        final [file, position] = key.split('|');
        expect(
          _columnsOf(db, recipes[file]!, int.parse(position)),
          columns.join('\t'),
          reason: key,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'A2: the matches GET reads breakfast-strata-with-spinach-and-gruyere|4',
    () async {
      final (db, recipes) = await _computed([_strata]);
      final body = await matchesBody(db, _fx, recipes[_strata]!);
      final m = ((body['items']! as List)[4] as Map)['match'] as Map;
      expect(
        (
          m['fdc_id'],
          (m['grams'] as num?)?.toStringAsFixed(2),
          m['hold'],
          m['status'],
          m['gram_basis'],
        ),
        (
          173468,
          '6.01',
          null,
          'auto',
          'from step 3: 1 teaspoon (no amount on the line)',
        ),
      );
    },
  );
}

/// The row at [position] of [r] as the probe read it: record, description,
/// status, hold, gram source, confidence, grams, the basis.
String _rowOf(SaltDatabase db, Recipe r, int position) {
  final m = d.rowOf(db, r, position);
  return '${m.fdcId}|${m.description}|${m.status}|${m.hold}|${m.gramSource}|'
      '${m.confidence.toStringAsFixed(6)}|${m.grams?.toStringAsFixed(2)}|'
      '${gramBasisFor(db, nutritionLines(r)[position], m, recipe: r)}';
}

/// The matches GET's view of [position]: grams, hold, status, basis.
Future<String> _getOf(SaltDatabase db, Recipe r, int position) async {
  final body = await matchesBody(db, _fx, r);
  final m = ((body['items']! as List)[position] as Map)['match'] as Map;
  return '${(m['grams'] as num?)?.toStringAsFixed(2)}|${m['hold']}|'
      '${m['status']}|${m['gram_basis']}';
}

/// R7 (A13): a decision on the key made on ANOTHER recipe's line reaches a
/// moved row as the shipped "Decisions travel" rules give — the stored row,
/// the GET and the next compute (measured first by a printing probe on both
/// trees: at the base 412d9d5 every A row below was the 0 g rule row before
/// and after each verb, and a pick + apply_to_all applied 0 lines).
void travel() {
  for (final (aFile, aPos, bFile, bPos, verb, body, applied, row) in [
    (
      _risotto, 4, _pistou, 8, 'Confirm + apply_to_all', //
      {'confirmed': true, 'apply_to_all': true}, '0/0',
      '173468|Salt, table|auto|null|density|1.000000|4.51|from step 2: ¾ teaspoon (no amount on the line)',
    ),
    (
      _risotto,
      4,
      _pistou,
      8,
      'pick 746775 + apply_to_all',
      {'fdc_id': 746775, 'apply_to_all': true},
      '1/1',
      '746775|Salt, table, iodized|auto|null|portion|1.000000|4.57|from step 2: ¾ teaspoon (no amount on the line)',
    ),
    (
      _potAuFeu,
      1,
      _porkTenderloin,
      1,
      'Confirm + apply_to_all',
      {'confirmed': true, 'apply_to_all': true},
      '0/0',
      '173468|Salt, table|auto|null|density|1.000000|9.00|from step 1: 1 tablespoon (no amount on the line)',
    ),
    (
      _potAuFeu,
      1,
      _porkTenderloin,
      1,
      'pick 746775 + apply_to_all',
      {'fdc_id': 746775, 'apply_to_all': true},
      '1/1',
      '746775|Salt, table, iodized|auto|null|density|1.000000|9.00|from step 1: 1 tablespoon (no amount on the line)',
    ),
  ]) {
    test(
      'R7: $bFile|$bPos $verb → $aFile|$aPos keeps its step grams',
      () async {
        final (db, recipes) = await _computed([aFile, bFile]);
        final ra = recipes[aFile]!;
        final out = await applyMatchOverride(
          db,
          _fx,
          recipes[bFile]!,
          bPos,
          body,
        );
        expect('${out?.lines ?? 0}/${out?.recipes ?? 0}', applied);
        expect(_rowOf(db, ra, aPos), row);
        final [_, _, status, hold, _, _, grams, basis] = row.split('|');
        expect(await _getOf(db, ra, aPos), '$grams|$hold|$status|$basis');
        await matchAndCompute(db, _fx, ra);
        expect(_rowOf(db, ra, aPos), row);
      },
    );
  }
  test(
    'R7: a skip + apply_to_all elsewhere is refused (no food decision)',
    () async {
      final (db, recipes) = await _computed([_risotto, _pistou]);
      await expectLater(
        applyMatchOverride(db, _fx, recipes[_pistou]!, 8, {
          'skipped': true,
          'apply_to_all': true,
        }),
        throwsA(isA<ValidationException>()),
      );
      expect(
        _rowOf(db, recipes[_risotto]!, 4),
        '173468|Salt, table|auto|null|density|1.000000|4.51|from step 2: ¾ teaspoon (no amount on the line)',
      );
    },
  );
}

/// R8 (A13): a person's own verbs on a moved line, and the same verbs on the
/// line with no steps (it stays the rule row): the stored row, the GET and
/// the next compute. A pick on an amount-less line stores no grams — as on
/// every shipped R-H1 line (ultimate-grilled-pizza|4 picked: 748608,
/// `overridden`, no grams; measured) and as on the base's rule row.
void ownVerbs() {
  const rule =
      'null|Seasoning to taste — no measurable amount|confirmed|null|null|1.000000|null|null';
  for (final (verb, body, moved, ruled) in [
    (
      'Confirm',
      {'confirmed': true},
      '173468|Salt, table|confirmed|null|density|1.000000|4.51|from step 2: ¾ teaspoon (no amount on the line)',
      rule,
    ),
    (
      'pick 746775',
      {'fdc_id': 746775},
      '746775|Salt, table, iodized|overridden|null|null|1.000000|null|null',
      '746775|Salt, table, iodized|overridden|null|null|1.000000|null|null',
    ),
    (
      'typed 5 g', {'grams': 5},
      '173468|Salt, table|overridden|null|override|1.000000|5.00|entered by hand',
      // Refused on the rule row: "Pick a matching food first, then set the
      // grams."
      rule,
    ),
    (
      'skip',
      {'skipped': true},
      '173468|Salt, table|skipped|null|density|1.000000|4.51|from step 2: ¾ teaspoon (no amount on the line)',
      'null|Seasoning to taste — no measurable amount|skipped|null|null|1.000000|null|null',
    ),
  ]) {
    for (final (label, steps, want) in [
      ('the moved line', true, moved),
      ('the same line with no steps (the rule row)', false, ruled),
    ]) {
      test(
        'R8: $verb on almost-hands-free-risotto-with-parmesan-and-herbs|4, $label',
        () async {
          final (db, _) = a.pathDb();
          final r = steps
              ? loadCorpusRecipe(_risotto)
              : loadCorpusRecipe(_risotto).copyWith(steps: const []);
          await d.editAndCompute(db, _fx, r);
          try {
            await applyMatchOverride(db, _fx, r, 4, body);
          } on ValidationException {
            expect((verb, steps), ('typed 5 g', false));
          }
          expect(_rowOf(db, r, 4), want);
          final [_, _, status, hold, _, _, grams, basis] = want.split('|');
          expect(await _getOf(db, r, 4), '$grams|$hold|$status|$basis');
          await matchAndCompute(db, _fx, r);
          expect(_rowOf(db, r, 4), want);
        },
      );
    }
  }
}

/// v102's P7 (the rule order inside the own-recipe settle, its mutants m7
/// and m8) on a line that STAYS a rule row: falafel|16 "Table salt" (step 2
/// prints salt, but |7 "1 teaspoon table salt" names salt in the same scope
/// — guard (i)); a pick of 746775 on |7 (the same key) leaves |16 the rule
/// row.
void ruleRowSibling() {
  test("falafel|7 pick 746775 → |16 'Table salt' stays the rule row", () async {
    const file = '0570-falafel.yaml';
    final (db, recipes) = await _computed([file]);
    final r = recipes[file]!;
    expect(nutritionLines(r)[16].raw, 'Table salt');
    expect(nutritionLines(r)[7].raw, '1 teaspoon table salt');
    const rule =
        'null|Seasoning to taste — no measurable amount|confirmed|null|null|1.000000|null|null';
    expect(_rowOf(db, r, 16), rule);
    await applyMatchOverride(db, _fx, r, 7, {'fdc_id': 746775});
    expect(d.rowOf(db, r, 7).fdcId, 746775);
    expect(_rowOf(db, r, 16), rule);
  });
}

/// R11: the label a person reads — breakfast-strata-with-spinach-and-
/// gruyere's sodium a serving (6 servings): 1,005.72 mg with |4 counted (the
/// v121 replay's), 617.29 mg with |4 skipped — the v120 replay's figure, the
/// rule row's 0 g (6.01 g × 387.58 mg/g ÷ 6 = +388.43 mg).
void label() {
  test('R11: the sodium a serving on the label, counted and skipped', () async {
    final (db, recipes) = await _computed([_strata]);
    final r = recipes[_strata]!;
    String sodium() => jsonEncode(
      (nutritionBody(db, r, forAdmin: false)['per_serving']! as Map)['sodium'],
    );
    expect(
      sodium(),
      '{"label":"Sodium","amount":1005.72,"unit":"mg","dv_percent":43.7}',
    );
    await applyMatchOverride(db, _fx, r, 4, {'skipped': true});
    expect(
      sodium(),
      '{"label":"Sodium","amount":617.29,"unit":"mg","dv_percent":26.8}',
    );
  });
}

/// R3 / Q7: the coat-station exclusion keeps ENERGY — chicken-katsu-crispy-
/// pan-fried-chicken-cutlets|2 "Salt" (step 1's dip) stays the rule row and
/// the dip's eggs keep M52's share (|1 53.35 g, the v120 row; counted, the
/// salt diluted the coat's carbohydrate share: 50.33 g, run 1's replay).
void coatStation() {
  test('chicken-katsu|2 stays the rule row; |1 eggs 53.35 g', () async {
    const file = '0115-chicken-katsu-crispy-pan-fried-chicken-cutlets.yaml';
    final (db, recipes) = await _computed([file]);
    final r = recipes[file]!;
    expect(
      _rowOf(db, r, 2),
      'null|Seasoning to taste — no measurable amount|confirmed|null|null|1.000000|null|null',
    );
    final eggs = d.rowOf(db, r, 1);
    expect(
      (eggs.fdcId, eggs.gramSource, eggs.grams?.toStringAsFixed(2)),
      (748967, 'discarded', '53.35'),
    );
  });
}

/// R12 (A5): ONE loop over every corpus recipe's own lines — the selector.
/// The amount-less seasoning lines `measuredStepSalt` turns into food rows
/// are exactly the v121 replay's 149 main rows (count, and the SHA-256 of
/// the sorted "file|position grams basis" list, each `stepAmountGrams` on SR
/// 173468 — the replay's grams and basis, compared row by row with
/// kit/moved_g2.tsv: 0 differences); every other one (413: pepper, no
/// reading, a medium, every print lost, a coat station) is not. The titled
/// sections are not looped: the one stamped section row is tamales §0|7
/// ([section]); 13 more section lines read a step in sections no host
/// routes to (none stored).
void property() {
  test(
    'R12: the selector over every corpus recipe',
    () async {
      final salt = (await _fx.food(173468))!;
      final files =
          Directory(corpusRecipesDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.yaml'))
              .map((f) => f.uri.pathSegments.last)
              .toList()
            ..sort();
      final food = <String>[];
      var other = 0;
      for (final file in files) {
        final r = loadCorpusRecipe(file);
        for (final (i, line) in nutritionLines(r).indexed) {
          final n = normalizeItem(lineItemOf(line));
          if (line.amounts.isNotEmpty || !isSeasoningToTaste(n)) {
            continue;
          }
          final read = _reading(r, i, salt);
          if (read == 'rule') {
            other++;
          } else {
            food.add('$file|$i $read');
          }
        }
      }
      food.sort();
      expect((food.length, other), (149, 413));
      expect(
        sha256.convert(utf8.encode(food.join('\n'))).toString(),
        '9b74984b01bb5d865b00bd0ead6fcb5e8473d5f3246e2208c772669f56744ba2',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _fill(String sentence) => List.filled(
  capStep ~/ sentence.length,
  sentence,
).join().trim();

/// R14 / Q8 (RULE C): the new arm at the caps — 400 lines ("Table salt" and
/// 399 "Ground black pepper"), 120 steps of 10,000 characters. TRUE: every
/// sentence prints "½ teaspoon salt" (48,000 prints, each asked of
/// `_lostSaltPrint` — its tables built once, `memo:lostSalt` — and of the
/// per-print medium); QUIET: no print (the rule row). The counts EXACT, the
/// clock a backstop. Measured on both trees (scratch probe): the base reads
/// nothing on either shape (TRUE compute 288 ms, its counts the index's
/// alone); v2's per-print scan form (no tables) took 848,811 ms on the TRUE
/// compute.
void caps() {
  group('RULE C, measured step salt at the caps', skip: skipIfNoCorpus, () {
    for (final (shape, sentence, row, compute, get) in [
      (
        'TRUE',
        'Stir in ½ teaspoon salt. ',
        '173468 auto 144318.78',
        '{"allSentences":1,"cheese":1,"ends":120,"heads":1,"hits":360,"indexes":1,"lineMentions":4,"lower":1,"memo:braise":1,"memo:brinedByVolume":1,"memo:browningFat":1,"memo:dips":1,"memo:dissolving":1,"memo:firstOwn":4,"memo:firstShare":1,"memo:kept":1,"memo:keptSolids":1,"memo:labelScope":1,"memo:lastRinse":1,"memo:leftInBowl":1,"memo:lostSalt":1,"memo:mentions":1,"memo:naming":2,"memo:parted":48000,"memo:parting":1,"memo:pourAway":1,"memo:saltLines":1,"memo:shares":1,"memo:starter":1,"memo:stepAmountGrams":2,"memo:stepAmounts":1,"memo:stepAmountsAt":1,"memo:strain":1,"mentionVisits":192000,"mentions":48000,"sentences":48000,"stepPrints":48000,"stepPrintsWalked":48000,"words":192000}',
        '{"allSentences":1,"carriedReads":1,"cheese":1,"heads":1,"indexes":1,"lineMentions":2,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brinedByVolume":1,"memo:brines":1,"memo:browningFat":1,"memo:cutShare":1,"memo:dips":1,"memo:dissolving":1,"memo:kept":1,"memo:keptSolids":1,"memo:labelScope":1,"memo:lastRinse":1,"memo:leftInBowl":1,"memo:liftedFromMarinade":1,"memo:lostSalt":1,"memo:mentions":1,"memo:naming":2,"memo:panFatLines":1,"memo:parting":1,"memo:pourAway":1,"memo:saltLines":1,"memo:starter":1,"memo:stepAmountGrams":1,"memo:stepAmounts":1,"memo:stepAmountsAt":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"mentions":48000,"sentences":48000,"stepPrints":48000,"stepPrintsWalked":48000,"words":192000}',
      ),
      (
        'QUIET',
        'Stir in the pepper. ',
        'null confirmed null',
        '{"heads":1,"indexes":1,"lower":1,"memo:browningFat":1,"memo:dips":1,"memo:keptSolids":1,"memo:labelScope":1,"memo:leftInBowl":1,"memo:naming":2,"memo:saltLines":1,"memo:stepAmounts":1,"memo:stepAmountsAt":1,"sentences":60000,"stepPrints":0,"words":240000}',
        '{"allSentences":1,"cheese":1,"heads":1,"indexes":1,"lineMentions":2,"lower":1,"memo:braise":1,"memo:brineWords":1,"memo:brinedByVolume":1,"memo:brines":1,"memo:dissolving":1,"memo:kept":1,"memo:lastRinse":1,"memo:mentions":1,"memo:naming":1,"memo:parting":1,"memo:pourAway":1,"memo:starter":1,"memo:strain":1,"memo:strainAt":1,"memo:wordHeads":1,"mentions":0,"sentences":60000,"words":240000}',
      ),
    ]) {
      test(
        '$shape: the counts exact, within the backstop',
        () async {
          final dir = Directory.systemTemp.createTempSync('salt-v121-cap-');
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
              capped(loadCorpusRecipe(_risotto), [
                'Table salt',
                ...List.filled(capLines - 1, 'Ground black pepper'),
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
          final computed = Map.of(stepIndexCounts);
          expectBounded(stored, computed, '$shape compute');
          expect(computed, jsonDecode(compute), reason: '$shape compute');
          final m = db.ingredientMatchesFor(r.id).first;
          expect('${m.fdcId} ${m.status} ${m.grams?.toStringAsFixed(2)}', row);
          stepIndexCounts.clear();
          sw.reset();
          final body = await matchesBody(
            db,
            fdc,
            db.recipeByIdOrSlug(r.id)!.recipe,
          );
          expect(sw.elapsedMilliseconds, lessThan(backstopMs));
          final got = Map.of(stepIndexCounts);
          expectBounded(stored, got, '$shape GET');
          expect(got, jsonDecode(get), reason: '$shape GET');
          expect(body['items']! as List, hasLength(capLines));
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  });
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

/// R13 / A1: the gates whose narrowed neighbour survived every corpus pin
/// (the whole-library replay under each byte-identical to the tip's), each
/// shown to change behaviour on one synthesized input and pinned there.
void synthesized() {
  group('v121 synthesized gates (stated exceptions)', () {
    for (final (gate, steps, want) in [
      (
        // (c') `\bdredg` alone (the corpus's dredge stations also shake or
        // pat the excess: chicken-kiev, lighter-chicken-parmesan).
        'dredge',
        [
          'Combine flour and ½ teaspoon salt in shallow dish.',
          'Dredge cutlets in flour mixture.',
        ],
        'rule',
      ),
      (
        // (c') "coat both sides" with a crumb (the mojo steak's coat
        // sentence, with panko in the print's step).
        'coat both sides',
        [
          'Combine panko and ½ teaspoon salt in bowl.',
          'Press cutlets into panko to coat both sides.',
        ],
        'rule',
      ),
      (
        // (c') the crumb word `bread` alone.
        'bread',
        [
          'Pulse bread and ½ teaspoon salt in food processor.',
          'Dredge cutlets in bread mixture.',
        ],
        'rule',
      ),
      (
        // (b) "let … soak" alone (the bean soaks also drain).
        'let soak',
        [
          'Combine beans and 1 tablespoon salt in large bowl and let beans soak overnight.',
        ],
        'rule',
      ),
      (
        // (a) a later "draining" (`_saltDrain`'s inflections; the corpus's
        // rice-wine toss, crispy-salt-and-pepper-shrimp|2, meets "drain").
        'draining',
        [
          'Toss shrimp with 1 tablespoon rice wine and 1 teaspoon salt in bowl.',
          'Refrigerate for 15 minutes before draining shrimp and patting dry.',
        ],
        'rule',
      ),
      (
        // (d) S names `chicken` alone (the corpus prints name breasts or
        // thighs too).
        'chicken',
        ['Season chicken with ½ teaspoon salt.', 'Remove and discard skin.'],
        'rule',
      ),
      (
        // The coat-station exclusion's batter arm (`_batterInBowl`): the
        // corpus's batter lines are refused by `_dipsOf` or (c') as well
        // (fish-and-chips|7).
        'batter left in the bowl',
        [
          'Whisk cornstarch, beer, and ½ teaspoon salt in bowl to make batter.',
          'Dip fish in batter, allowing excess batter to drip back into bowl.',
        ],
        'rule',
      ),
    ]) {
      test('$gate: a print it alone decides stays off', () async {
        final r = _syn(['Table salt'], steps);
        expect(_reading(r, 0, (await _fx.food(173468))!), want);
      });
    }
    test('the line-level medium ask: "Table salt, for brining" stays the '
        'rule row', () async {
      // `measuredStepSalt`'s `discardedMediumOf(recipe, line, salt)` (the
      // amount-less line's own text; verify1 D1): the line's "for brining"
      // is a brine, while the per-print ask's "½ teaspoon table salt" reads
      // none — the line ask alone decides. No amount-less corpus line names
      // a purpose (corpus reach 0); the spelling follows the corpus's "½ cup
      // table salt, for brining" (0125, 0240) without its amount. Measured.
      final r = _syn(
        ['Table salt, for brining', '4 pork chops'],
        ['Season chops with ½ teaspoon salt.'],
      );
      expect(_reading(r, 0, (await _fx.food(173468))!), 'rule');
      // The same line without the purpose is counted (the control).
      final c = _syn(
        ['Table salt', '4 pork chops'],
        ['Season chops with ½ teaspoon salt.'],
      );
      expect(
        _reading(c, 0, (await _fx.food(173468))!),
        '3.01 from step 1: ½ teaspoon (no amount on the line)',
      );
    });
    test("(e') each liquid word that decides no corpus row: a discarded "
        'remainder of it keeps the print off', () async {
      // The owner gate's mutant: `_saltLeftLiquid` narrowed to the two words
      // on which a corpus sentence decides a seasoning-salt print (sauce —
      // spicy-pork-tacos-al-pastor|5; liquid —
      // cherry-tomato-salad-with-feta-and-olives|2 and the carne adovada)
      // passed this whole file, and the whole-library replay under it was
      // byte-identical to the tip's. The corpus names two of the other four
      // words in such a sentence — broth (braised-turkey, step 5) and water
      // (foolproof-spaghetti-carbonara, step 2) — and neither follows a
      // seasoning-salt print. Each of the four is pinned here on a
      // synthesized step (a STATED exception; the wording follows the carne
      // adovada's "discard remaining soaking liquid"). No other arm reads
      // these steps: no drain, no crumb, no chicken.
      final salt = (await _fx.food(173468))!;
      for (final word in ['broth', 'marinade', 'brine', 'water']) {
        final r = _syn(
          ['Table salt'],
          [
            'Whisk ½ teaspoon salt into mixture in bowl.',
            'Reserve ½ cup of mixture; discard remaining $word.',
          ],
        );
        expect(_reading(r, 0, salt), 'rule', reason: word);
      }
      // The control: a discarded remainder that names no liquid.
      final c = _syn(
        ['Table salt'],
        [
          'Whisk ½ teaspoon salt into mixture in bowl.',
          'Reserve ½ cup of mixture; discard remaining herbs.',
        ],
      );
      expect(
        _reading(c, 0, salt),
        '3.01 from step 1: ½ teaspoon (no amount on the line)',
      );
    });
    test('flake sea salt: its step teaspoon weighs 3.55 g', () async {
      // The design's mutant (e), the kosher flag of the weighing: no moved
      // corpus row is a flake spelling (corpus lines "Flake sea salt" read
      // no print), so the pin is this one; measured value.
      final r = _syn(['Flake sea salt'], ['Stir in 1 teaspoon salt.']);
      expect(
        _reading(r, 0, (await _fx.food(173468))!),
        '3.55 from step 1: 1 teaspoon (no amount on the line)',
      );
    });
    test(
      'the compute asks no search for a measured salt line (one detail)',
      () async {
        final (db, _) = a.pathDb();
        final fx = FixtureProvider(pending: pendingSearches);
        final r = _syn(['Table salt'], ['Stir in ½ teaspoon salt.']);
        await d.editAndCompute(db, fx, r);
        expect((fx.searchCalls, fx.foodCalls), (0, 1));
        expect(
          _rowOf(db, r, 0),
          '173468|Salt, table|auto|null|density|1.000000|3.01|from step 1: ½ teaspoon (no amount on the line)',
        );
      },
    );
  });
}
