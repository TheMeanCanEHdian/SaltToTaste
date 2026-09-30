// Real corpus lines are kept verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v19: Run 050's grams. Real corpus lines (recipe named on each;
/// G0 proves each exists), FDC answers recorded from sweep snapshot 13. A
/// guard no corpus line exercises is pinned on a synthesized line or a
/// synthesized line-to-record pairing, said so where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v19');
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(() {
      db.dispose();
      dir.deleteSync(recursive: true);
    });
    return db;
  }

  Future<GramResolution?> gramsOn(String raw, int fdcId) async =>
      lineGrams(tempDb(), lineOf(raw), await FixtureProvider().food(fdcId));

  // (corpus file, line, its record in snapshot 13, grams, source): the
  // rows v19 re-massed in the cache-only replay of snapshot 13, at their
  // record's own portion.
  const moved = <(String, String, int, double?, String?)>[
    // G1: a density key that only modifies a compound.
    (
      '0815-snickerdoodles.yaml',
      '2 teaspoons cream of tartar',
      175041,
      6.0,
      'portion',
    ),
    (
      '0227-sous-vide-rosemarymustard-seed-crusted-roast-beef.yaml',
      '¼ cup mustard seeds',
      170929,
      24.6,
      'portion',
    ),
    (
      '0664-bread-and-butter-pickles.yaml',
      '1 tablespoon yellow mustard seeds',
      170929,
      6.3,
      'portion',
    ),
    (
      '0712-chelow-persian-style-rice-with-golden-crust.yaml',
      '1½ teaspoons cumin seeds',
      170923,
      3.15,
      'portion',
    ),
    (
      '0141-pollo-en-mole-poblano-chicken-in-puebla-style-mole.yaml',
      '¼ cup almond butter',
      2707533,
      64.0,
      'portion',
    ),
    (
      '1079-mustardy-apple-butterglazed-pork-chops.yaml',
      '3 tablespoons apple butter',
      168816,
      51.0,
      'portion',
    ),
    (
      '0831-triple-coconut-macaroons.yaml',
      '1 cup cream of coconut',
      2707571,
      240.0,
      'portion',
    ),
    // G2: a named nut on its record's own cup.
    (
      '0545-kung-pao-shrimp.yaml',
      '½ cup unsalted roasted peanuts',
      173806,
      73.0,
      'portion',
    ),
    (
      '1083-pan-seared-shrimp-with-peanuts-black-pepper-and-lime.yaml',
      '3 tablespoons dry-roasted peanuts, chopped coarse',
      2707517,
      27.375,
      'portion',
    ),
    (
      '0908-paris-brest.yaml',
      '2 tablespoons toasted, skinned, and chopped hazelnuts',
      2707502,
      16.875,
      'portion',
    ),
    // G3: a powder on its drink's record: no grams.
    (
      '1150-deluxe-blueberry-pancakes.yaml',
      '3 tablespoons malted milk powder',
      174867,
      null,
      null,
    ),
    // G6: a shred on the record's shredded or grated cup.
    (
      '0542-mu-shu-pork.yaml',
      '3 cups thinly sliced green cabbage',
      169975,
      210.0,
      'portion',
    ),
    (
      '0481-carne-deshebrada-shredded-beef-tacos.yaml',
      '½ head green cabbage, cored and sliced thin (6 cups)',
      169975,
      420.0,
      'portion',
    ),
  ];

  // Lines v19 must NOT move (their snapshot-13 grams and source).
  const kept = <(String, String, int, double, String)>[
    // 'nuts' on a record with no volume portion of its own.
    (
      '0040-arugula-salad-with-figs-prosciutto-walnuts-and-parmesan.yaml',
      '½ cup walnuts, toasted and chopped',
      2346394,
      65.06,
      'density',
    ),
    // "unsalted" is "without salt", and 'butter' is still butter.
    (
      '0015-carrot-ginger-soup.yaml',
      '2 tablespoons unsalted butter',
      173430,
      28.36,
      'density',
    ),
    // A powder reads its drink record's DRY portion (v8's 'cup dry mix').
    (
      '0793-authentic-baguettes-at-home.yaml',
      '1 teaspoon diastatic malt powder (optional)',
      171874,
      98 / 48,
      'portion',
    ),
    // 'small' is the item's own size.
    (
      '0432-classic-french-onion-soup.yaml',
      '1 small baguette, cut on the bias into ½-inch slices',
      2707610,
      152.0,
      'piece',
    ),
  ];

  group('G: grams (Run 050)', () {
    test('G0: every pinned line is its corpus line — the same raw, item and '
        'amounts the corpus file stores', () {
      for (final (file, raw) in [
        for (final (file, raw, _, _, _) in moved) (file, raw),
        for (final (file, raw, _, _, _) in kept) (file, raw),
      ]) {
        final stored = [
          for (final g in loadCorpusRecipe(file).ingredients) ...g.items,
        ].firstWhere((l) => l.raw == raw, orElse: () => fail('$file: $raw'));
        final line = lineOf(raw);
        expect(stored.item, line.item, reason: raw);
        expect(stored.amounts, line.amounts, reason: raw);
      }
    }, skip: skipIfNoCorpus);

    test("G1-G3, G6: each re-massed line weighs on its record's own portion "
        '(or none)', () async {
      for (final (_, raw, fdcId, grams, source) in moved) {
        final g = await gramsOn(raw, fdcId);
        expect(
          g?.grams,
          grams == null ? isNull : closeTo(grams, 0.005),
          reason: raw,
        );
        expect(g?.source.name, source, reason: raw);
      }
    });

    test('the lines v19 must not move keep their grams', () async {
      for (final (_, raw, fdcId, grams, source) in kept) {
        final g = await gramsOn(raw, fdcId);
        expect(g?.grams, closeTo(grams, 0.005), reason: raw);
        expect(g?.source.name, source, reason: raw);
      }
    });

    test("G2: 'nuts' gives way only to a record of the nut the item names — "
        '"¾ cup nuts, chopped" (Pear Crisp, 0963) on the peanut record '
        "173806 stays on 'nuts' 0.55, never its 'cup' 146 g (synthesized "
        'pairing, a stated exception: its own record, cashews 2515374, has no '
        'volume portion)', () async {
      final g = await gramsOn('¾ cup nuts, chopped', 173806);
      expect(g?.grams, closeTo(0.75 * 236.588 * 0.55, 0.005));
      expect(g?.source, GramSource.density);
    });

    test('G4: "small" is read from the item\'s own words, never its prep '
        '(synthesized lines on the recorded 2707610 and 2707616, a stated '
        'exception: no corpus line puts "small" in the prep of a bare count '
        'on a record with a small portion)', () async {
      for (final (raw, fdcId, grams) in const [
        ('1 baguette', 2707610, 324.0),
        ('1 baguette, cut into small cubes', 2707610, 324.0),
        ('1 baguette torn into small pieces', 2707610, 324.0),
        ('2 pita breads, cut into wedges', 2707616, 114.0),
        // A large line is sized as the regular one (no large preference),
        // never as the small one its prep names.
        ('2 large pita breads, cut into small wedges', 2707616, 114.0),
        // D2: a small line takes the small portion over the medium one
        // (rank 3 over 2) — on the baguette record the mini portion wins
        // on a tie, so only a record whose medium portion outranks a
        // plain one pins the rank.
        ('2 small pita breads', 2707616, 56.0),
      ]) {
        expect(
          (await gramsOn(raw, fdcId))?.grams,
          closeTo(grams, 0.005),
          reason: raw,
        );
      }
    });

    test("G5: quantity words before a flake salt are its amount's — it still "
        'packs like kosher (synthesized lines, a stated exception: every '
        "corpus flake salt line is 'N teaspoons/tablespoons …')", () async {
      for (final raw in const [
        '1 heaping tablespoon flaky sea salt',
        'scant ½ teaspoon flaky sea salt',
        'about 1 teaspoon flaky sea salt',
        '1 rounded teaspoon flake sea salt',
        '1 generous tablespoon coarse sea salt',
      ]) {
        expect(packsLikeKosherSalt(raw), isTrue, reason: raw);
      }
      expect(packsLikeKosherSalt('1 teaspoon table salt'), isFalse);
      // The corpus parse reads no amount past a quantity word, so the
      // grams are pinned on another library's structured amount.
      final g = lineGrams(
        tempDb(),
        const IngredientLine(
          raw: '1 heaping tablespoon flaky sea salt',
          item: 'flaky sea salt',
          amounts: [
            Amount(
              measure: Measure.volume,
              quantity: '1',
              unit: 'tablespoon',
              primary: true,
            ),
          ],
        ),
        await FixtureProvider().food(173468),
      );
      expect(g?.grams, closeTo(14.7868 * 0.72, 0.005));
    });
  });

  test('G6: a plain slice is no shred — "1 cup sliced carrots" is 170393 '
      "'cup strips or slices' 122 g, a shred its 'cup grated' 110 g "
      '(synthesized lines, a stated exception)', () async {
    expect((await gramsOn('1 cup sliced carrots', 170393))?.grams, 122.0);
    expect((await gramsOn('1 cup shredded carrots', 170393))?.grams, 110.0);
    expect((await gramsOn('1 cup grated carrots', 170393))?.grams, 110.0);
  });

  test(
    'D2: the "liquid" dock skips a query that asks for liquid (the clam '
    'juice target keeps 171977 at 0.933, not the docked 0.873) and docks '
    "an unasked one by 0.06 (167567 at 0.84 under the squares' 0.90)",
    () async {
      final provider = FixtureProvider(pending: pendingSearches);
      const clam = 'mollusks clam canned liquid';
      final juice = rankCandidates(clam, await provider.search(clam)).first;
      expect(juice.candidate.fdcId, 171977);
      expect(juice.confidence, closeTo(14 / 15, 1e-9));
      final chocolate = rankCandidates(
        'unsweetened chocolate',
        await provider.search('unsweetened chocolate'),
      );
      double of(int id) =>
          chocolate.firstWhere((r) => r.candidate.fdcId == id).confidence;
      expect(of(167568), closeTo(0.90, 1e-9));
      expect(of(167567), closeTo(0.84, 1e-9));
    },
  );
}
