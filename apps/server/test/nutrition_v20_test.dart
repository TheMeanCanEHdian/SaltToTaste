// Real corpus lines are kept verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// Run 051's grams (E1, E2) and the pins Run 051 found vacuous (E4). Real
/// corpus lines (recipe named on each), FDC answers recorded from sweep
/// snapshot 13. A guard no corpus line exercises is pinned on a synthesized
/// line or a synthesized line-to-record pairing, said so where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v20');
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(() {
      db.dispose();
      dir.deleteSync(recursive: true);
    });
    return db;
  }

  Future<GramResolution?> gramsOn(String raw, int fdcId) async =>
      lineGrams(tempDb(), lineOf(raw), await FixtureProvider().food(fdcId));

  group('E1 (Run 051 O6/S11): a dried chile is small by its own words', () {
    test('on 168570 "Peppers, hot chile, sun-dried" (0.5 g a pepper), '
        '"2 dried New Mexican chiles, stemmed, seeded, and flesh torn into '
        '½-inch pieces" (Grilled Steak with New Mexican Chile Rub, 0587) has '
        'no grams, and so does the same line torn into SMALL pieces (a '
        'synthesized prep, a stated exception: no corpus chile line says '
        'it) — "small" in the prep sizes the pieces, not the pod; "4 large '
        'dried guajillo chiles, … torn into small pieces" (Goan Pork '
        'Vindaloo 1095\'s line with "small" for "1-inch", synthesized) too; '
        '"10 dried arbol chiles" (Guay Tiew Tom Yum Goong, 0011) stays '
        '10 × 0.5 g', () async {
      expect(
        await gramsOn(
          '2 dried New Mexican chiles, stemmed, seeded, and flesh torn into ½-inch pieces',
          168570,
        ),
        isNull,
      );
      expect(
        await gramsOn(
          '2 dried New Mexican chiles, stemmed, seeded, and flesh torn into small pieces',
          168570,
        ),
        isNull,
      );
      expect(
        await gramsOn(
          '4 large dried guajillo chiles, wiped clean, stemmed, seeded, and torn into small pieces',
          168570,
        ),
        isNull,
      );
      expect(
        (await gramsOn(
          '10 dried arbol chiles, stemmed, halved lengthwise, and seeds reserved',
          168570,
        ))?.grams,
        closeTo(5, 0.001),
      );
      // "large" excludes small: the item calls the pod large (synthesized
      // "small large", a stated exception — it pins the large term alone).
      expect(
        await gramsOn('4 small large dried guajillo chiles', 168570),
        isNull,
      );
      expect(
        (await gramsOn(
          '8 small whole dried red chiles (optional)',
          168570,
        ))?.grams,
        closeTo(4, 0.001),
      );
    });
  });

  group('E2 (Run 051 O7): a density key that only modifies the head', () {
    Future<double?> g(String raw, int id) async =>
        (await gramsOn(raw, id))?.grams;

    test("on a record of the key's own food, the record's volume portion "
        'weighs it: "1 teaspoon vanilla extract" (German Apple Pancake, 0748) '
        '4.2 g on 173471\'s tsp, "½ teaspoon cayenne pepper" (Chicken and '
        'Sausage Gumbo, 0028) 0.9 g on 170932\'s, "¾ cup Dutch-processed cocoa '
        'powder" (Chocolate Cookies, 0821) 64.5 g on 169594\'s cup — the '
        'corpus\'s own "1 cup (3 ounces) unsweetened cocoa powder" — and "2 '
        'tablespoons unsweetened cocoa powder" (0993) 10.8 g, never \'cocoa\' '
        "0.52's 92 g and 15 g", () async {
      expect(await g('1 teaspoon vanilla extract', 173471), closeTo(4.2, 1e-9));
      expect(await g('½ teaspoon cayenne pepper', 170932), closeTo(0.9, 1e-9));
      expect(
        await g('¾ cup Dutch-processed cocoa powder', 169594),
        closeTo(64.5, 1e-9),
      );
      expect(
        await g('2 tablespoons unsweetened cocoa powder', 169593),
        closeTo(10.8, 1e-9),
      );
    });

    test('a key the record does not name keeps its figure: "½ cup panko '
        'bread crumbs" (Deviled Pork Chops, 0207) on "Bread, crumbs, dry, '
        'grated, plain" (108 g a cup of plain crumbs) is \'panko\' 0.25, and '
        '"1 teaspoon whole black peppercorns plus ground black pepper" '
        "(Shrimp Salad, 0286) on ground pepper is 'peppercorn' 0.59; a "
        'record with no volume portion keeps the key\'s too: "¼ cup grated '
        'Parmesan cheese" (Philly Cheesesteaks, 0309) on 325036 reads the '
        "grated figure the corpus prints (0.24, v23 G4; 'parmesan' 0.42 "
        'before); and the key that IS the head keeps its figure: "¼ cup '
        'molasses" (Indoor Pulled Chicken, 0129) \'molasses\' 1.41, 83.4 g, '
        "on 168820, not its cup's 84.25 g", () async {
      expect(await g('½ cup panko bread crumbs', 174928), closeTo(29.57, 0.01));
      expect(
        await g(
          '1 teaspoon whole black peppercorns plus ground black pepper',
          170931,
        ),
        closeTo(2.91, 0.01),
      );
      expect(
        await g('¼ cup grated Parmesan cheese', 325036),
        closeTo(14.18, 0.01),
      );
      expect(await g('¼ cup molasses', 168820), closeTo(83.40, 0.01));
    });

    test(
      'a key that modifies ANOTHER food: "2 cups sugar snap peas, strings '
      'removed" on 170010 "Peas, edible-podded, raw" is its "cup, whole" '
      '126 g, not \'sugar\' 0.85\'s 402 g; "8 cups chopped mustard greens" '
      'on 169256 its "cup, chopped" 448 g, not \'mustard\' 1.05\'s 1,987 g '
      '(both volumes synthesized, a stated exception: every corpus line of '
      'these foods is by weight — "8 ounces sugar snap peas, strings '
      'removed, trimmed", "12 ounces mustard greens, stemmed and rinsed")',
      () async {
        expect(
          await g('2 cups sugar snap peas, strings removed', 170010),
          closeTo(126, 1e-9),
        );
        expect(
          await g('8 cups chopped mustard greens', 169256),
          closeTo(448, 1e-9),
        );
      },
    );
  });

  group('E4: the pins Run 051 found vacuous', () {
    Future<double?> g(String raw, int id) async =>
        (await gramsOn(raw, id))?.grams;

    test("G2 (O13/S23): 'nuts' names no record of its own — \"¾ cup nuts, "
        'chopped" (Pear Crisp, 0963) is \'nuts\' 0.55 (97.59 g) on the '
        'recorded "Nuts, …" records 170185 (pistachio), 170182 (pecans) and '
        '170567 (almonds), never their own cups (92.25, 81.75, 107.25 g); '
        'and a salt state names none either: "½ cup unsalted nuts" (O13\'s '
        'line, synthesized — a stated exception: the corpus writes "unsalted" '
        'only on a named nut) on 170185 "… without salt added" is 65.06 g, '
        "not its cup's 61.5 g", () async {
      for (final id in const [170185, 170182, 170567]) {
        expect(await g('¾ cup nuts, chopped', id), closeTo(97.59, 0.01));
      }
      expect(await g('½ cup unsalted nuts', 170185), closeTo(65.06, 0.01));
      // A word of two letters names nothing: "¾ cup chopped pecans or
      // walnuts, toasted (optional)" (Classic Chocolate Chip Cookies, 0817)
      // shares only "or" with 170932 "Spices, pepper, red or cayenne" (a
      // synthesized pairing, a stated exception: no recorded nut record
      // with a volume portion has a word of two letters).
      expect(
        await g('¾ cup chopped pecans or walnuts, toasted (optional)', 170932),
        closeTo(97.59, 0.01),
      );
      // Nor does the "with" of a salt state ("salted" normalizes to "with
      // salt"): "2 tablespoons chopped salted dry-roasted peanuts" (Lao Hu Cai, 1174) on
      // 170122 "Radishes, oriental, cooked, boiled, drained, with salt" (a
      // synthesized pairing, a stated exception: the recorded "with salt
      // added" nut record, 323294, has no volume portion) is 'nuts' 0.55.
      expect(
        await g('2 tablespoons chopped salted dry-roasted peanuts', 170122),
        closeTo(16.26, 0.01),
      );
    });

    test('G3 (S22): only a POWDER on a "prepared with" record reads its dry '
        'portions — "2 tablespoons malt syrup" (New York Bagels, 0810) on '
        '174867 "…, powder, prepared with whole milk" weighs by its "cup (8 '
        'fl oz)" 265 g (33.1 g; a synthesized pairing, a stated exception: '
        'no corpus line on a prepared-with record lacks "powder"), where '
        '"3 tablespoons malted milk powder" (Deluxe Blueberry Pancakes, 1150) '
        'has none', () async {
      expect(
        await g('2 tablespoons malt syrup', 174867),
        closeTo(33.125, 0.001),
      );
      expect(await g('3 tablespoons malted milk powder', 174867), isNull);
    });

    test("G4 (S24): each prep word ends the item's size words, the comma "
        "too, and the case is the item's own — on the recorded baguette "
        '(2707610: "1 baguette" 324 g, "1 mini baguette" 152 g) and pita '
        '(2707616: 114 g, small 56 g) records (synthesized lines, a stated '
        'exception: no corpus line puts "small" after a prep word before a '
        'comma; "warmed in a small skillet" follows the corpus\'s "pecans, '
        'toasted in a small, dry skillet", 0767)', () async {
      for (final (raw, id, grams) in const [
        ('1 baguette broken in small pieces', 2707610, 324.0),
        ('1 baguette sliced small', 2707610, 324.0),
        ('1 baguette chopped small', 2707610, 324.0),
        ('1 baguette diced small', 2707610, 324.0),
        ('2 pita breads, warmed in a small skillet', 2707616, 114.0),
        ('2 Small pita breads', 2707616, 56.0),
      ]) {
        expect(await g(raw, id), closeTo(grams, 0.005), reason: raw);
      }
    });

    test('G5 (S24): "heaped" and "level" are quantity words before a flake '
        'salt (synthesized lines, a stated exception: every corpus flake '
        "salt line is 'N teaspoons/tablespoons …')", () {
      expect(packsLikeKosherSalt('1 heaped teaspoon flaky sea salt'), isTrue);
      expect(packsLikeKosherSalt('1 level teaspoon flaky sea salt'), isTrue);
    });

    test('G6 (S25): a grated or very thin slice is a shred by its prep too — '
        '"2 cups grated green cabbage" is 169975\'s "cup, shredded" 70 g a '
        'cup, not its "cup, chopped" 89 g, and "3 cups green cabbage, sliced very thin" '
        '169975\'s "cup, shredded" 70 g a cup (synthesized lines, a stated '
        'exception: no corpus cabbage line is grated, and none by volume '
        '"sliced very thin")', () async {
      // Grated on a record whose shred portion says "shredded": the shred
      // (a portion that says "grated" is read first as the one the line
      // names).
      expect(
        await g('2 cups grated green cabbage', 169975),
        closeTo(140, 1e-9),
      );
      expect(
        await g('3 cups green cabbage, sliced very thin', 169975),
        closeTo(210, 1e-9),
      );
    });
  });
}
