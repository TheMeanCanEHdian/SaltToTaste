// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v76 (batch M76 — eaten foods below the gate; matcherVersion 73;
// prep50 design_v2 §2 M76, the owner's Q3 (a) and Q4 (a); zero requests):
// Q3 (a) — A9's yield-named TAIL form (engine `yieldNamesOwnSection`, read
// by `namesOwnSection` and the resolver's own-section list): the tart's
// UNMARKED "1 pound pizza dough" (below the gate on FNDDS 2708008 "Dessert
// pizza") names the tail of its own "Classic Pizza Dough" and its amount IS
// the section's printed "MAKES 1 POUND" (parseShare == 1.0) → routed at
// share 1.0, the section computed as a child (sections 143 → 144). Q4 (a) —
// kasseri on SR 170850 "Cheese, provolone" by rank-as, flagged
// (`approximationRecords`, `trimStandInFlagOf`). Every row value is the
// fresh compute of the WHOLE recipe over recorded real FDC answers
// (FixtureProvider; fixtures recorded from snapshot 27 only) and equals the
// v76 replay of snapshot 27 (rp43) on every pinned field. Never the
// network. Synthesized, STATED: one census pin (verify1 D1, verify2 D1)
// rewrites the tart's YAML text — its section retitled "Classic Sourdough"
// (and, as the positive control, "Classic Dough") with line 6 "1 pound
// dough", and retitled "Classic Pizza Dough for Grilling" with line 6 as
// printed — because no corpus title ends in a line's item without a word
// boundary, and the census reads only titles that END in the item; one
// more (verify4 D1) removes the tart section's five ingredient lines
// (MAKES 1 POUND and its steps kept; also retitled "Pizza Dough", the
// equality form) — no corpus section with a yield lists no lines under a
// tail or equality title; and the memo exactness oracle (verify4 D2;
// verify5 D1) adds to the real tart a "Whole-Wheat Pizza Dough" section
// (the real section's own lines, at MAKES 2 POUNDS) and three lines after
// the recipe's own — "1 pound pizza dough" at 2-pound amounts, "1 pound
// pizza dough (½ recipe)" and "1 pound pizza dough (recipe follows)" —
// because no corpus recipe holds two tail sections or line twins. Every
// other line is a corpus line. Fixtures added
// (snapshot 27, --from-db, JSON-equal): the searches 'provolone cheese'
// (kasseri's rank-as answer), 'kasseri cheese' (the line's own answer, read
// by the "FDC holds no kasseri" pin) and '93 percent lean ground beef'
// (pastitsio|0).

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _tart = '1177-caramelized-onion-pear-and-bacon-tart.yaml';
const _pastitsio = '0375-pastitsio.yaml';
const _kibbeh = '1176-red-lentil-kibbeh.yaml';
const _pulledPork = '0609-barbecued-pulled-pork.yaml';
const _turkey = '0175-simple-grill-roasted-turkey.yaml';
const _friedRice = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
const _dough = 'Classic Pizza Dough';

/// §2 M76's kasseri flag, verbatim.
const _kasseriFlag =
    "approximate (FDC holds no kasseri — counted as provolone, the larger part of the recipe's own substitute: 3 oz provolone with 1½ oz Pecorino Romano for 4 oz kasseri)";

/// The section's five rows as the v76 replay holds them: (position, raw,
/// fdc id, grams, kcal, basis). The flour's item parses as "plus 2
/// tablespoons bread flour" and keys `bread flour` (matcher.dart's left-over
/// amount strip): the printed 11½ oz on SR 168913.
const _sectionRows = [
  (
    0,
    '2 cups plus 2 tablespoons bread flour (11½ ounces)',
    168913,
    '326.02',
    '1176.93',
    'from 11 1/2 ounce',
  ),
  (
    1,
    '1⅛ teaspoons instant or rapid-rise yeast',
    2710005,
    '3.55',
    '11.53',
    '1 1/8 teaspoon ≈ 6 mL',
  ),
  (2, '¾ teaspoon table salt', 173468, '4.51', '0.00', '3/4 teaspoon ≈ 4 mL'),
  (
    3,
    '1 tablespoon olive oil',
    2710186,
    '14.00',
    '126.00',
    '1 tablespoon · USDA portion',
  ),
];

/// (file, status, per serving, stored batch energy) after the compute.
const _totals = [
  // RE-PIN (M90 batch, v89, brown sugar): its brown sugar |3 at the print
  // (6.88 → 6.20 g; the replay 381.96 → 381.64): was 381.96, 3055.71.
  (_tart, 'complete', '381.64', '3053.15'),
  // RE-PIN (M82 batch, v84, C5a): its 2 tablespoons flour |16 15.08 → 17.72
  // g (the replay 469.49 → 471.10): was 469.49, 2816.96.
  // RE-PIN (M86 batch, v90, 958: 2685580 tomato): was 471.10, 2826.61.
  (_pastitsio, 'complete', '468.82', '2812.95'),
];

/// The v74 rows on 170850 (3; generated from v74_rows.tsv): (slug|position, raw, normalized item).
const _provolone = [
  (
    'antipasto-pasta-salad|11',
    '4 ounces aged provolone cheese, grated (about 1 cup)',
    'aged provolone cheese',
  ),
  (
    'grilled-stuffed-flank-steak|7',
    '4 ounces thinly sliced provolone cheese',
    'provolone cheese',
  ),
  (
    'ultracreamy-spaghetti-with-zucchini|7',
    '2½ ounces mild provolone cheese, shredded (⅔ cup)',
    'mild provolone cheese',
  ),
];

/// The v74 rows on 171249 (29; generated from v74_rows.tsv): (slug|position, raw, normalized item).
const _romano = [
  (
    'spanakopita-greek-spinach-and-feta-pie|16',
    '1½ ounces Pecorino Romano cheese, grated (¾ cup)',
    'pecorino romano cheese',
  ),
  (
    'herb-crusted-pork-roast|4',
    '1 ounce Parmesan or Pecorino Romano cheese, grated (½ cup), divided',
    'parmesan or pecorino romano cheese',
  ),
  (
    'spaghetti-with-pecorino-romano-and-black-pepper|0',
    '4 ounces Pecorino Romano, grated fine (about 2 cups), plus 2 ounces grated coarse (about 1 cup), for serving',
    'pecorino romano',
  ),
  (
    'pasta-allamatriciana|6',
    '2 ounces Pecorino Romano, grated fine (1 cup)',
    'pecorino romano',
  ),
  (
    'pasta-with-tomato-bacon-and-onion|7',
    '⅓ cup grated Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'pasta-alla-gricia-rigatoni-with-pancetta-and-pecorino-romano|4',
    '2 ounces Pecorino Romano cheese, grated fine (1 cup), plus extra for serving',
    'pecorino romano cheese',
  ),
  (
    'penne-arrabbiata|9',
    '¼ cup grated Pecorino Romano, plus extra for serving',
    'pecorino romano',
  ),
  (
    'campanelle-with-asparagus-basil-and-balsamic-glaze|9',
    '2 ounces Pecorino Romano cheese, shaved (about 1 cup)',
    'pecorino romano cheese',
  ),
  (
    'spaghetti-with-quick-mushroom-ragu|11',
    'Grated Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'pasta-alla-norcina|12',
    '1½ ounces Pecorino Romano, grated (¾ cup)',
    'pecorino romano',
  ),
  (
    'rigatoni-with-beef-and-onion-ragu|11',
    '1 ounce Pecorino Romano cheese, grated (½ cup), plus extra for serving',
    'pecorino romano cheese',
  ),
  (
    'pasta-with-hearty-italian-meat-sauce-sunday-gravy|19',
    '1 ounce Pecorino Romano cheese, grated (about ½ cup)',
    'pecorino romano cheese',
  ),
  (
    'pork-fennel-and-lemon-ragu-with-pappardelle|11',
    '2 ounces Pecorino Romano cheese, grated (1 cup), plus extra for serving',
    'pecorino romano cheese',
  ),
  (
    'foolproof-spaghetti-carbonara|3',
    '2½ ounces Pecorino Romano, grated (1¼ cups)',
    'pecorino romano',
  ),
  (
    'classic-spaghetti-alla-carbonara|5',
    '¼ cup grated Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'creamy-baked-four-cheese-pasta|5',
    '1 ounce Pecorino Romano cheese, grated (about ½ cup)',
    'pecorino romano cheese',
  ),
  (
    'simple-cheese-lasagna|0',
    '4 ounces Pecorino Romano cheese, grated (2 cups)',
    'pecorino romano cheese',
  ),
  (
    'simple-cheese-lasagna|18',
    '1 ounce Pecorino Romano cheese, grated (½ cup)',
    'pecorino romano cheese',
  ),
  (
    'simple-cheese-lasagna|22',
    '¼ cup grated Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'thin-crust-whole-wheat-pizza-with-garlic-oil-three-cheeses-and-basil|15',
    '1 ounce Pecorino Romano cheese, grated (½ cup)',
    'pecorino romano cheese',
  ),
  (
    'acquacotta-tuscan-white-bean-and-escarole-soup|14',
    'Grated Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'eggplant-involtini|9',
    '1½ ounces grated Pecorino Romano (¾ cup)',
    'pecorino romano',
  ),
  (
    'mexican-style-grilled-corn|0',
    '1½ ounces Pecorino Romano cheese, grated (¾ cup)',
    'pecorino romano cheese',
  ),
  (
    'skillet-roasted-brussels-sprouts-with-lemon-and-pecorino-romano|4',
    '¼ cup shredded Pecorino Romano cheese',
    'pecorino romano cheese',
  ),
  (
    'pao-de-queijo-brazilian-cheese-bread|8',
    '3½ ounces Pecorino Romano, finely grated (1¾ cups)',
    'pecorino romano',
  ),
  (
    'braciole|6',
    '⅓ cup grated Pecorino Romano cheese, plus extra for serving',
    'pecorino romano cheese',
  ),
  (
    'pasta-cacio-e-uova-pasta-with-cheese-and-eggs|4',
    '1 ounce Pecorino Romano cheese, grated (½ cup)',
    'pecorino romano cheese',
  ),
  (
    'orecchiette-with-broccoli-rabe-and-sausage-2|7',
    '2 ounces Pecorino Romano, grated (1 cup)',
    'pecorino romano',
  ),
  (
    'rigatoni-with-tomatoes-bacon-and-fennel|11',
    '¼ cup grated Pecorino Romano cheese, plus extra for serving',
    'pecorino romano cheese',
  ),
];

/// Every corpus main line that names the TAIL of one of its recipe's own
/// section titles, UNMARKED, whose amount reads no share of that section's
/// yield — the lines the yield guard alone keeps off (`slug|position →
/// title`); the design names turkey|0 and fried-rice|10.
const _tailNoYield = [
  'roasted-cornish-game-hens|0 → Herb-Roasted Cornish Game Hens',
  'roasted-cornish-game-hens|0 → Cumin-Coriander Roasted Cornish Game Hens',
  'roasted-cornish-game-hens|0 → Oregano-Anise Roasted Cornish Game Hens',
  'simple-grill-roasted-turkey|0 → Gravy for Simple Grill-Roasted Turkey',
  'fried-rice-with-shrimp-pork-and-shiitakes|10 → Fried Rice with Peas and Bean Sprouts',
  'indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas|12 → Indian-Style Curry with Sweet Potatoes, Eggplant, Green Beans, and Chickpeas',
  'baklava|1 → Pistachio Baklava with Cardamom and Rose Water',
];

String _norm(String text) => foldAccents(
  text.toLowerCase(),
).replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

List<String> _corpusFiles() =>
    Directory(corpusRecipesDir)
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((f) => f.endsWith('.yaml'))
        .toList()
      ..sort();

void main() {
  test('kasseri reads the cached provolone answer, flagged: the rank-as, the '
      "approximation record and the arm keyed on the line's own word", () {
    expect(normalizeItem('kasseri cheese'), 'kasseri cheese');
    expect(rankAsFor('kasseri cheese'), (
      query: 'cheese provolone',
      answer: 'provolone cheese',
    ));
    expect(approximationRecords['kasseri cheese'], 170850);
    const raw = '4 ounces kasseri cheese, shredded (1 cup), divided';
    expect(trimStandInFlagOf(raw, 170850), _kasseriFlag);
    // The arm is the record's AND the word's: kasseri on another record
    // says nothing.
    expect(trimStandInFlagOf(raw, 2705720), isNull);
    expect(
      isApproximation(
        item: 'kasseri cheese',
        raw: raw,
        fdcId: 170850,
        description: 'Cheese, provolone',
      ),
      isTrue,
    );
  });

  test(
    "FDC holds no kasseri: the line's own cached answer (25 cheese "
    'foods) names none, its best rank the Monterey 2705720 below the gate '
    "(v74's row) — the rank-as reads the provolone answer instead",
    () async {
      final provider = FixtureProvider();
      final own = await provider.search('kasseri cheese');
      expect(own, hasLength(25));
      expect(
        own.where((c) => c.description.toLowerCase().contains('kasseri')),
        isEmpty,
      );
      final ranked = rankCandidates('kasseri cheese', own);
      expect(ranked.first.candidate.fdcId, 2705720);
      expect(belowConfidenceGate(ranked.first.confidence), isTrue);
      final provolone = await provider.search('provolone cheese');
      expect(provolone.first.fdcId, 170850);
      expect(
        rankCandidates('cheese provolone', provolone).first.candidate.fdcId,
        170850,
      );
    },
  );

  test('the negatives: the 3 provolone rows on 170850 and the 29 Romano rows '
      'on 171249 are no approximation and carry no flag', () {
    expect(_provolone, hasLength(3));
    expect(_romano, hasLength(29));
    for (final (fdcId, rows) in [(170850, _provolone), (171249, _romano)]) {
      for (final (key, raw, item) in rows) {
        expect(trimStandInFlagOf(raw, fdcId), isNull, reason: key);
        expect(
          isApproximation(
            item: item,
            raw: raw,
            fdcId: fdcId,
            description: null,
          ),
          isFalse,
          reason: key,
        );
      }
    }
  });

  group('the census over the corpus (no compute)', skip: skipIfNoCorpus, () {
    test('exactly ONE corpus line names its own section by the yield-named '
        'tail: the tart|6 "1 pound pizza dough" → "Classic Pizza Dough" '
        '(MAKES 1 POUND, share 1.0); the unmarked tails the yield guard '
        'alone refuses; no marked line ever takes the tail', () {
      final hits = <String>[];
      final noYield = <String>[];
      final marked = <String>[];
      var kasseri = <String>[];
      for (final file in _corpusFiles()) {
        final recipe = loadCorpusRecipe(file);
        for (final (i, line) in nutritionLines(recipe).indexed) {
          if (line.raw.toLowerCase().contains('kasseri')) {
            kasseri = [...kasseri, '${recipe.slug}|$i'];
          }
          final item = referenceItemOf(line);
          for (final sub in recipe.subsections) {
            if (item.isEmpty || !_norm(sub.title ?? '').endsWith(' $item')) {
              continue;
            }
            final key = '${recipe.slug}|$i → ${sub.title}';
            final share = parseShare(line.raw, line.amounts, sub.servings);
            if (yieldNamesOwnSection(line, item, sub)) {
              hits.add(key);
              expect(share, 1.0, reason: key);
            } else if (isSubRecipeReference(line.raw)) {
              marked.add(key);
            } else {
              expect(share, isNot(1.0), reason: key);
              noYield.add(key);
            }
          }
        }
      }
      expect(hits, [
        'caramelized-onion-pear-and-bacon-tart|6 → Classic Pizza Dough',
      ]);
      expect(noYield, _tailNoYield);
      expect(
        marked,
        contains(
          'barbecued-pulled-pork|4 → Eastern North Carolina Barbecue Sauce',
        ),
      );
      expect(marked, hasLength(60));
      expect(kasseri, ['pastitsio|23']);
    });

    test(
      'the dough lines: 23 corpus lines name a dough — the 22 marked '
      'references keep their forms, the tart|6 is the one the tail reads',
      () {
        final unmarked = <String>[];
        var marked = 0;
        for (final file in _corpusFiles()) {
          final recipe = loadCorpusRecipe(file);
          for (final (i, line) in nutritionLines(recipe).indexed) {
            final item = referenceItemOf(line);
            if (!item.split(' ').contains('dough')) {
              continue;
            }
            if (isSubRecipeReference(line.raw)) {
              marked++;
              for (final sub in recipe.subsections) {
                expect(
                  yieldNamesOwnSection(line, item, sub),
                  isFalse,
                  reason: '${recipe.slug}|$i',
                );
              }
            } else {
              unmarked.add('${recipe.slug}|$i');
              expect(isReferenceIn(recipe, line), isTrue);
            }
          }
        }
        expect(marked, 22);
        expect(unmarked, ['caramelized-onion-pear-and-bacon-tart|6']);
      },
    );

    test('the guards on the real lines: the tart reads its section; turkey|0 '
        'and fried-rice|10 name a section tail but read no share of its '
        'yield (6 cups of gravy; serves 4 to 6) — no reference; the pulled '
        "pork's marked sauce line reads its yield but is marked", () {
      (IngredientLine, Subsection) at(String file, int i, String title) {
        final recipe = loadCorpusRecipe(file);
        return (
          nutritionLines(recipe)[i],
          recipe.subsections.singleWhere((s) => s.title == title),
        );
      }

      final tart = loadCorpusRecipe(_tart);
      final (dough, doughSection) = at(_tart, 6, _dough);
      expect(dough.raw, '1 pound pizza dough');
      expect(doughSection.servings, 'MAKES 1 POUND');
      expect(referenceItemOf(dough), 'pizza dough');
      expect(parseShare(dough.raw, dough.amounts, doughSection.servings), 1.0);
      expect(yieldNamesOwnSection(dough, 'pizza dough', doughSection), isTrue);
      expect(namesOwnSection(tart, dough), isTrue);
      expect(isReferenceIn(tart, dough), isTrue);
      for (final (file, i, title, raw) in const [
        (
          _turkey,
          0,
          'Gravy for Simple Grill-Roasted Turkey',
          '1 (12- to 14-pound) turkey, neck and giblets removed and reserved for gravy',
        ),
        (
          _friedRice,
          10,
          'Fried Rice with Peas and Bean Sprouts',
          '1 cup bean sprouts',
        ),
      ]) {
        final recipe = loadCorpusRecipe(file);
        final (line, sub) = at(file, i, title);
        expect(line.raw, raw);
        expect(_norm(title), endsWith(' ${referenceItemOf(line)}'));
        expect(parseShare(line.raw, line.amounts, sub.servings), isNull);
        expect(
          yieldNamesOwnSection(line, referenceItemOf(line), sub),
          isFalse,
        );
        expect(namesOwnSection(recipe, line), isFalse, reason: file);
        expect(isReferenceIn(recipe, line), isFalse, reason: file);
      }
      final (sauce, carolina) = at(
        _pulledPork,
        4,
        'Eastern North Carolina Barbecue Sauce',
      );
      expect(sauce.raw, '2 cups barbecue sauce (recipes follow)');
      expect(parseShare(sauce.raw, sauce.amounts, carolina.servings), 1.0);
      expect(
        yieldNamesOwnSection(sauce, referenceItemOf(sauce), carolina),
        isFalse,
      );
    });

    test("the tail is whole words and the title's LAST words (verify1 D1, "
        'verify2 D1): a STATED synthesized rewrite of the tart — its section '
        'retitled "Classic Sourdough", line 6 "1 pound dough", MAKES 1 POUND '
        'kept — reads the full yield yet names no section ("sourdough" does '
        'not end in the word "dough"); the same rewrite titled "Classic Dough" '
        'does; retitled "Classic Pizza Dough for Grilling" with line 6 as '
        'printed it names none (the item is inside the title, not its tail) — '
        "no corpus title ends in a line's item without a space before it, and "
        'the census reads only titles that end in the item, so neither '
        'refusal can come from the corpus', () {
      Recipe rewrite(String title, String item) {
        var text = File('$corpusRecipesDir/$_tart').readAsStringSync();
        for (final (from, to) in [
          ('- title: $_dough\n', '- title: $title\n'),
          ('  - raw: 1 pound pizza dough\n', '  - raw: 1 pound $item\n'),
          ('    item: pizza dough\n', '    item: $item\n'),
        ]) {
          expect(from.allMatches(text), hasLength(1), reason: from);
          text = text.replaceFirst(from, to);
        }
        return RecipeYamlCodec.decode(text).recipe;
      }

      for (final (title, item, names) in const [
        ('Classic Sourdough', 'dough', false),
        ('Classic Dough', 'dough', true),
        // verify2 D1: the item is the title's last words, not any words.
        ('Classic Pizza Dough for Grilling', 'pizza dough', false),
      ]) {
        final recipe = rewrite(title, item);
        final line = nutritionLines(recipe)[6];
        final sub = recipe.subsections.single;
        expect(line.raw, '1 pound $item');
        expect(referenceItemOf(line), item);
        expect(sub.title, title);
        expect(sub.servings, 'MAKES 1 POUND');
        expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
        expect(yieldNamesOwnSection(line, item, sub), names, reason: title);
        expect(namesOwnSection(recipe, line), names, reason: title);
        expect(isReferenceIn(recipe, line), names, reason: title);
      }
    });

    test('a section with NO ingredient lines is never one, by the tail or '
        "by A9's equality (verify4 D1: the has-lines gate): a STATED "
        "synthesized rewrite of the tart — its section's five ingredient "
        'lines removed (the key omitted, as the corpus writes a prose '
        'section), MAKES 1 POUND and its two steps kept — reads the full '
        'yield on the tail yet is no reference; retitled "Pizza Dough" (the '
        'equality form) likewise; the same title WITH the lines names it — '
        'no corpus tail or equality title reaches a lineless section with a '
        'yield, so neither refusal can come from the corpus', () {
      Recipe rewrite({required String title, required bool lines}) {
        var text = File('$corpusRecipesDir/$_tart').readAsStringSync();
        const head = '- title: $_dough\n';
        expect(head.allMatches(text), hasLength(1));
        text = text.replaceFirst(head, '- title: $title\n');
        if (!lines) {
          const from = '  servings: MAKES 1 POUND\n  ingredients:\n';
          expect(from.allMatches(text), hasLength(1));
          final start = text.indexOf(from) + from.indexOf('  ingredients:');
          final end = text.indexOf('  steps:\n', start);
          expect(
            '- raw: '.allMatches(text.substring(start, end)),
            hasLength(5),
          );
          text = text.replaceRange(start, end, '');
        }
        return RecipeYamlCodec.decode(text).recipe;
      }

      for (final (title, lines, tail, names) in const [
        (_dough, false, true, false),
        ('Pizza Dough', false, false, false),
        ('Pizza Dough', true, false, true),
      ]) {
        final recipe = rewrite(title: title, lines: lines);
        final line = nutritionLines(recipe)[6];
        final sub = recipe.subsections.single;
        final reason = '$title, lines: $lines';
        expect(line.raw, '1 pound pizza dough');
        expect(sub.title, title);
        expect(sub.servings, 'MAKES 1 POUND');
        expect(sub.steps, hasLength(2));
        expect(sub.ingredients ?? const [], hasLength(lines ? 1 : 0));
        expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
        expect(
          yieldNamesOwnSection(line, 'pizza dough', sub),
          tail,
          reason: reason,
        );
        expect(namesOwnSection(recipe, line), names, reason: reason);
        expect(isReferenceIn(recipe, line), names, reason: reason);
      }
    });
  });

  group('matcher v76 (batch M76)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;
    final recipes = <String, Recipe>{};

    Future<Recipe> compute(SaltDatabase db, Recipe recipe) async {
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      final stored = db.recipeByIdOrSlug(recipe.id)!.recipe;
      for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
        expect(
          await matchAndCompute(
            db,
            provider,
            nutritionRecipeOf(db, key)!.recipe,
          ),
          isNull,
        );
      }
      expect(await matchAndCompute(db, provider, stored), isNull);
      return db.recipeByIdOrSlug(recipe.id)!.recipe;
    }

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-v76-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider(pending: {...pendingSearches});
      // The tart's bacon (rule B1) counts its cooked part on SR 168322, a
      // search hit only (snapshot 27 holds no detail): the deli-ham answer
      // cached first, as a library does (v51's practice).
      db.fdcSearchCachePut(
        'thin-sliced cooked deli ham',
        jsonEncode([
          for (final c in await provider.search('thin-sliced cooked deli ham'))
            c.toJson(),
        ]),
      );
      for (final file in [_tart, _pastitsio]) {
        recipes[file] = await compute(db, loadCorpusRecipe(file));
      }
      // Stored, not computed: their reference lines resolve off the
      // recipe alone.
      for (final file in [_kibbeh, _pulledPork]) {
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
        recipes[file] = db.recipeByIdOrSlug(recipe.id)!.recipe;
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    IngredientMatchRow rowIn(String id, int position) =>
        db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

    String kcalOf(IngredientMatchRow row, IngredientLine line) =>
        (kcalPer100g(knownFood(db, row.fdcId!, line: line)!) * row.grams! / 100)
            .toStringAsFixed(2);

    test('the tart|6 routes to its own "Classic Pizza Dough" at share 1.0 — '
        'the section a child (computed first), the row its batch', () {
      final tart = recipes[_tart]!;
      final line = nutritionLines(tart)[6];
      final key = sectionKeyOf(tart.id, _dough);
      final memo = ResolverMemo(db);
      expect(sectionChildKeysOf(db, tart, memo), {key});
      expect(routedSectionKeysOf(db, tart, memo), {key});
      final found = resolveReference(db, tart, line, memo);
      expect(found.kind, ReferenceKind.routed);
      expect(found.section, (host: tart.id, title: _dough));
      expect(found.share, 1.0);
      final row = rowIn(tart.id, 6);
      expect(row.fdcId, isNull);
      expect(row.status, 'auto');
      expect(row.hold, isNull);
      expect(row.gramSource, 'recipe');
      expect(row.childRecipeId, key);
      expect(row.childShare, 1.0);
      expect(row.grams?.toStringAsFixed(2), '348.10');
      expect(
        gramBasisFor(db, line, row, recipe: tart),
        'from the recipe $_dough: 348 g, 1,314 kcal',
      );
    });

    test("the section's rows on their own records — the flour on SR 168913 "
        'at the printed 11½ oz; the water the shipped rule row — and its '
        'totals', () {
      final key = sectionKeyOf(recipes[_tart]!.id, _dough);
      final section = nutritionRecipeOf(db, key)!.recipe;
      final lines = nutritionLines(section);
      expect(lines, hasLength(5));
      for (final (position, raw, fdcId, grams, kcal, basis) in _sectionRows) {
        final row = rowIn(key, position);
        final reason = '$key|$position';
        expect(lines[position].raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(kcalOf(row, lines[position]), kcal, reason: reason);
        expect(
          gramBasisFor(db, lines[position], row, recipe: section),
          basis,
          reason: reason,
        );
      }
      final water = rowIn(key, 4);
      expect(lines[4].raw, '¾ cup warm water (110 degrees)');
      expect(water.fdcId, isNull);
      expect(water.status, 'confirmed');
      expect(water.grams, isNull);
      final n = db.nutritionFor(key)!;
      expect(n.status, 'complete');
      expect((batchTotalsOf(n)['energy'] ?? 0).toStringAsFixed(2), '1314.46');
    });

    test('pastitsio|23: kasseri on SR 170850 provolone at the printed 4 oz, '
        '398.03 kcal, flagged after the approximation clause', () {
      final pastitsio = recipes[_pastitsio]!;
      final line = nutritionLines(pastitsio)[23];
      expect(line.raw, '4 ounces kasseri cheese, shredded (1 cup), divided');
      final row = rowIn(pastitsio.id, 23);
      expect(row.fdcId, 170850);
      expect(row.confidence, 1.0);
      expect(row.status, 'auto');
      expect(row.hold, isNull);
      expect(row.grams?.toStringAsFixed(2), '113.40');
      expect(kcalOf(row, line), '398.03');
      expect(
        gramBasisFor(db, line, row, recipe: pastitsio),
        'from 4 ounce · approximation (counted as Cheese, provolone) · '
        '$_kasseriFlag',
      );
    });

    test('the totals: both recipes complete — the tart 381.96 and pastitsio '
        '469.49 per serving', () {
      for (final (file, status, perServing, energy) in _totals) {
        final n = db.nutritionFor(recipes[file]!.id)!;
        expect(
          (
            n.status,
            n.caloriesPerServing?.toStringAsFixed(2),
            (batchTotalsOf(n)['energy'] ?? 0).toStringAsFixed(2),
          ),
          (status, perServing, energy),
          reason: file,
        );
      }
    });

    test('the GET: the tart|6 routed to its section with the basis, its fix '
        "sheet's own_section group listing the section the resolver routes "
        'to; pastitsio|23 on 170850 with the kasseri flag', () async {
      Future<Map<String, Object?>> itemOf(String file, int position) async =>
          ((await matchesBody(db, provider, recipes[file]!))['items']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((i) => i['position'] == position);
      final dough = (await itemOf(_tart, 6))['match']! as Map<String, Object?>;
      expect(dough['gram_basis'], 'from the recipe $_dough: 348 g, 1,314 kcal');
      final child = dough['child']! as Map<String, Object?>;
      expect(child['state'], 'routed');
      expect(child['section'], _dough);
      final own = (child['candidates']! as List)
          .cast<Map<String, Object?>>()
          .where((c) => c['group'] == 'own_section')
          .map((c) => c['section'])
          .toList();
      expect(own, [_dough]);
      final kasseri =
          (await itemOf(_pastitsio, 23))['match']! as Map<String, Object?>;
      expect(kasseri['fdc_id'], 170850);
      expect(
        kasseri['gram_basis'],
        'from 4 ounce · approximation (counted as Cheese, provolone) · '
        '$_kasseriFlag',
      );
    });

    test("the marked and A9-equal negatives keep v74's resolution: the "
        "pulled pork's \"2 cups barbecue sauce (recipes follow)\" stays rule "
        "PO's (held, its two sauces listed for a person); red-lentil-kibbeh|4 "
        '"2 tablespoons harissa" routes to Harissa at 0.25 (equality)', () {
      final memo = ResolverMemo(db);
      final pork = recipes[_pulledPork]!;
      final sauce = nutritionLines(pork)[4];
      expect(resolveReference(db, pork, sauce, memo).kind, ReferenceKind.held);
      expect(pickOwnSections(db, pork, sauce, memo), [
        'Eastern North Carolina Barbecue Sauce',
        'Mid–South Carolina Mustard Sauce',
      ]);
      final kibbeh = recipes[_kibbeh]!;
      final harissa = nutritionLines(kibbeh)[4];
      expect(harissa.raw, startsWith('2 tablespoons harissa'));
      final found = resolveReference(db, kibbeh, harissa, memo);
      expect(found.kind, ReferenceKind.routed);
      expect(found.section, (host: kibbeh.id, title: 'Harissa'));
      // 2 tbsp of "MAKES ½ CUP" through the mL table.
      expect(found.share?.toStringAsFixed(6), '0.250001');
    });

    test('a second recompute writes nothing — rows and totals', () {
      for (final file in [_tart, _pastitsio]) {
        final recipe = recipes[file]!;
        for (final id in [
          recipe.id,
          ...sectionChildKeysOf(db, recipe, ResolverMemo(db)),
        ]) {
          final stored = nutritionRecipeOf(db, id)!.recipe;
          List<(int, double?, String?, String?, int?)> rows() => [
            for (final r in db.ingredientMatchesFor(id))
              (r.position, r.grams, r.hold, r.updatedAt, r.fdcId),
          ];
          expect(recomputeTotals(db, stored), isTrue, reason: id);
          final before = rows();
          final totals = batchTotalsOf(db.nutritionFor(id)!);
          expect(recomputeTotals(db, stored), isTrue, reason: id);
          expect(rows(), before, reason: id);
          expect(batchTotalsOf(db.nutritionFor(id)!), totals, reason: id);
        }
      }
    });

    test('the per-recipe memo of the tail (verify4 D2, verify5 D2) answers '
        'exactly as derived afresh — in line order, in reverse on a fresh '
        'instance, and '
        'with every memo off: a STATED synthesized tart (no corpus recipe '
        'holds two tail sections or line twins) — a "Whole-Wheat Pizza '
        'Dough" (its lines, MAKES 2 POUNDS) before the real section, and '
        'three lines after its own: line 6 at 2 pounds (the raw kept, other '
        'amounts — the share key reads the amounts), at "(½ recipe)" (line '
        "6's amounts, another raw — it reads the raw), and marked \"(recipe "
        'follows)" (the mark key reads the raw)', () {
      Recipe make() {
        final tart = loadCorpusRecipe(_tart);
        final dough = nutritionLines(tart)[6];
        final real = tart.subsections.single;
        final pound = dough.amounts.single;
        return tart.copyWith(
          subsections: [
            real.copyWith(
              title: 'Whole-Wheat Pizza Dough',
              servings: 'MAKES 2 POUNDS',
            ),
            real,
          ],
          ingredients: [
            ...tart.ingredients,
            IngredientGroup(
              items: [
                dough.copyWith(amounts: [pound.copyWith(quantity: '2')]),
                dough.copyWith(raw: '1 pound pizza dough (½ recipe)'),
                dough.copyWith(raw: '1 pound pizza dough (recipe follows)'),
              ],
            ),
          ],
        );
      }

      final memo = ResolverMemo(db);
      String answer(Recipe recipe, int i) {
        final line = nutritionLines(recipe)[i];
        final found = resolveReference(db, recipe, line, memo);
        return '${line.raw} ${line.amounts.single.quantity}: '
            '${namesOwnSection(recipe, line)} ${isReferenceIn(recipe, line)} '
            '${found.kind.name} ${found.section?.title} ${found.share}';
      }

      final n = nutritionLines(loadCorpusRecipe(_tart)).length;
      final positions = [6, n, n + 1, n + 2];
      final first = make();
      expect(
        [for (final i in positions) nutritionLines(first)[i].raw],
        [
          '1 pound pizza dough',
          '1 pound pizza dough',
          '1 pound pizza dough (½ recipe)',
          '1 pound pizza dough (recipe follows)',
        ],
      );
      final inOrder = [for (final i in positions) answer(first, i)];
      final reversed = make();
      final backwards = [
        for (final i in positions.reversed) answer(reversed, i),
      ].reversed.toList();
      memoOffForTest = true;
      try {
        final afresh = make();
        expect(inOrder, [for (final i in positions) answer(afresh, i)]);
      } finally {
        memoOffForTest = false;
      }
      expect(backwards, inOrder);
      expect(inOrder, [
        '1 pound pizza dough 1: true true routed $_dough 1.0',
        // At 2 pounds the twin is the whole-wheat section's yield.
        '1 pound pizza dough 2: true true routed Whole-Wheat Pizza Dough 1.0',
        // "(½ recipe)" reads half of either yield: no reference.
        '1 pound pizza dough (½ recipe) 1: false false held null null',
        // Marked: a reference, never by the tail (rule PO's forms only).
        '1 pound pizza dough (recipe follows) 1: false true held null null',
      ]);
    });
  });
}
