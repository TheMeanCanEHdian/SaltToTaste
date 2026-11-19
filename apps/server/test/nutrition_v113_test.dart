// The v113 pins (batch M100, prep52 P2: record choice; matcherVersion 99).
// Rank-as entries read a CACHED answer under the record's own words
// ([rankAsFor]); flagged stand-ins are [approximationRecords] entries.
// W6 turkey leg quarters and drumsticks and thighs on the leg record 171493
// (+ its [ah102Records] entry); W2a the sweet, mixed and link spellings of
// Italian sausage on the mild raw pork record 171631; W2b bulk pork sausage
// on the unprepared link/patty 172934; W9a raw cube steaks on raw top round
// 2646173 (flagged); W9b the bare ground beef on its siblings' 80 % lean
// 2514744; W7a low-fat yogurt cheese on strained low-fat Greek yogurt
// 170903 (flagged); W7b strained whole-milk yogurt on whole-milk Greek
// 2259794; S14′ 'flavored' docked as an unasked modified form; L368 the
// curry leaves a zero flavouring; W3 freekeh on dry bulgur 170688 (flagged).
// Corpus-backed groups skip without SALT_CORPUS_DIR; every corpus read sits
// inside a test body (the loader never reads the corpus). The landed
// records' DETAILS are seeded into each test database from the fixtures
// (copied verbatim from snapshot 33's fdc_food_cache), as snapshot 33 holds
// them — so the energies are the details', never a search hit's rounded
// figure.
//
// Hand derivations (grams unchanged but W3's; grams × the record's kcal per
// 100 g in the engine's order, nutrient 208, else 958, else 957):
//   W6  171493 (208 = 144): crowd|12 2,254.35 g × 1.44 = 3,246.27 (the
//       unrounded 4 × 793.79 × 0.71); slow-roasted|7 and braised|3
//       1,360.78 g × 1.44 = 1,959.52.
//   W2a 171631 (208 = 290): 226.80 g × 2.90 = 657.71 (226.796); 340.19 g
//       → 986.56 (340.194); 453.59 g → 1,315.42 (453.592); 680.39 g →
//       1,973.13 (680.389).
//   W2b 172934 (208 = 288): 340.19 g × 2.88 = 979.76; 453.59 g → 1,306.34.
//   W9a 2646173 (no 208; 958 = 146.437): 850.49 g × 1.46437 = 1,245.42.
//   W9b 2514744 (no 208; 958 = 247.813): 340.19 g × 2.47813 = 843.04.
//   W7a 170903 (208 = 73): 226.80 g × 0.73 = 165.56.
//   W7b 2259794 (no 208; 958 = 94.5071): 243.69 g × 0.945071 = 230.30.
//   S14′ 2708202 (208 = 472): 28.35 g × 4.72 = 133.81; 226.80 g → 1,070.48.
//   L368 the zero flavouring: 0 g, 0 kcal, no record.
//   W3  170688 (208 = 342; its own "1 cup" portion 140 g): 1½ cups =
//       210.00 g × 3.42 = 718.20.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _crowd = '0163-turkey-and-gravy-for-a-crowd.yaml';
const _slowRoasted = '0162-slow-roasted-turkey-with-gravy.yaml';
const _braised = '0172-braised-turkey.yaml';
const _steaks = '0304-chicken-fried-steaks.yaml';
const _palak = '0109-palak-dal-spinach-dal-with-cumin-and-mustard-seeds.yaml';
const _freekeh =
    '1179-chicken-and-spiced-freekeh-with-cilantro-and-preserved-lemon.yaml';
const _frenchStyle = '0454-french-style-chicken-and-stuffing-in-a-pot.yaml';

const _leg = 'Turkey, all classes, leg, meat and skin, raw';
const _item2596 =
    'from 4 pound × 0.75 edible · approximate (USDA AH-102 item 2596: turkey leg, raw, fryer-roaster class → meat and skin 75 % (70–79))';

/// The details the batch lands, seeded as snapshot 33 caches them.
const _landed = [
  171493,
  171631,
  172934,
  2646173,
  2514744,
  170903,
  2259794,
  2708202,
  170688,
];

/// THE 21 ROWS (file, position, raw start, record, source, stored
/// confidence, grams, kcal, basis) — the replay's on snapshot 33 (v112 → v113), each derived by hand
/// above. A null record is the zero flavouring row.
const _moved = [
  // W6 (the leg quarters flagged: a quarter carries a back portion the leg
  // record does not describe; the drumsticks and thighs ARE the leg).
  (
    _crowd,
    12,
    '4 (1½- to 2-pound) turkey leg quarters, trimmed',
    171493,
    'weight',
    '1.000000',
    '2254.35',
    '3246.27',
    '4 × 794 g (printed 1½–2 lb, the midpoint) × 0.71 edible · approximate (USDA AH-102 item 2595: turkey leg quarter, raw, fryer-roaster class → meat and skin 71 % (69–73)) · approximation (counted as $_leg)',
  ),
  (
    _slowRoasted,
    7,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171493,
    'weight',
    '1.000000',
    '1360.78',
    '1959.52',
    _item2596,
  ),
  (
    _braised,
    3,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171493,
    'weight',
    '1.000000',
    '1360.78',
    '1959.52',
    _item2596,
  ),
  // W2a (unflagged: "sweet" and "mild" name the same fresh sausage).
  (
    '0066-pasta-frittata-with-sausage-and-hot-peppers.yaml',
    6,
    '8 ounces sweet Italian sausage, casings removed, crumbled',
    171631,
    'weight',
    '0.980000',
    '226.80',
    '657.71',
    'from 8 ounce',
  ),
  (
    '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    3,
    '1 pound hot Italian sausage links',
    171631,
    'weight',
    '0.980000',
    '453.59',
    '1315.42',
    'from 1 pound',
  ),
  (
    '0360-sausage-meatballs-and-spaghetti.yaml',
    13,
    '12 ounces sweet Italian sausage, casings removed',
    171631,
    'weight',
    '0.980000',
    '340.19',
    '986.56',
    'from 12 ounce',
  ),
  (
    '0424-italian-sausage-with-grapes-and-balsamic-vinegar.yaml',
    1,
    '1½ pounds sweet Italian sausage',
    171631,
    'weight',
    '0.980000',
    '680.39',
    '1973.13',
    'from 1 1/2 pound',
  ),
  (
    '1132-orecchiette-with-broccoli-rabe-and-sausage.yaml',
    1,
    '8 ounces hot or sweet Italian sausage, casings removed',
    171631,
    'weight',
    '0.980000',
    '226.80',
    '657.71',
    'from 8 ounce',
  ),
  (
    '1190-ricotta-calzones-with-sausage-and-broccoli-rabe.yaml',
    5,
    '8 ounces sweet or hot Italian sausage, casings removed',
    171631,
    'weight',
    '0.980000',
    '226.80',
    '657.71',
    'from 8 ounce',
  ),
  // W2b (unflagged).
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    8,
    '12 ounces bulk pork sausage, broken into 1-inch pieces',
    172934,
    'weight',
    '1.000000',
    '340.19',
    '979.76',
    'from 12 ounce',
  ),
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    3,
    '1 pound bulk pork sausage',
    172934,
    'weight',
    '1.000000',
    '453.59',
    '1306.34',
    'from 1 pound',
  ),
  (
    _frenchStyle,
    9,
    '1 pound bulk pork sausage',
    172934,
    'weight',
    '1.000000',
    '453.59',
    '1306.34',
    'from 1 pound',
  ),
  // W9a (flagged; the printed raw weight stays, so the fried-food readers'
  // coat and oil, sized per raw beef, do not move — [_unmoved]).
  (
    _steaks,
    7,
    '6 (5-ounce) cube steaks, pounded ⅓ inch thick',
    2646173,
    'weight',
    '1.000000',
    '850.49',
    '1245.42',
    '6 × 142 g (printed weight) · approximation (counted as Beef, round, top round, boneless, choice, raw)',
  ),
  // W9b (unflagged).
  (
    '0308-classic-stuffed-bell-peppers.yaml',
    5,
    '12 ounces ground beef, preferably 80 percent lean ground chuck',
    2514744,
    'weight',
    '0.970000',
    '340.19',
    '843.04',
    'from 12 ounce',
  ),
  // W7a (flagged).
  (
    '0914-light-new-york-cheesecake.yaml',
    5,
    '8 ounces (1 cup) low-fat yogurt cheese',
    170903,
    'weight',
    '1.000000',
    '226.80',
    '165.56',
    'from 8 ounce · approximation (counted as Yogurt, Greek, plain, lowfat)',
  ),
  // W7b (unflagged; the cup's density grams unchanged).
  (
    '1145-clbr-turkish-poached-eggs-with-yogurt-and-spiced-butter.yaml',
    0,
    '1 cup plain whole-milk strained yogurt',
    2259794,
    'density',
    '1.000000',
    '243.69',
    '230.30',
    '1 cup ≈ 237 mL',
  ),
  // S14′ (unflagged).
  (
    '0009-best-ground-beef-chili.yaml',
    5,
    '1 ounce tortilla chips, crushed (¼ cup)',
    2708202,
    'weight',
    '0.923333',
    '28.35',
    '133.81',
    'from 1 ounce',
  ),
  (
    '0314-black-bean-burgers.yaml',
    11,
    '1 ounce tortilla chips, crushed coarse (½ cup)',
    2708202,
    'weight',
    '0.923333',
    '28.35',
    '133.81',
    'from 1 ounce',
  ),
  (
    '0471-cheesy-nachos-with-guacamole-and-salsa.yaml',
    0,
    '8 ounces tortilla chips',
    2708202,
    'weight',
    '0.923333',
    '226.80',
    '1070.48',
    'from 8 ounce',
  ),
  // L368 (the zero flavouring row: no record, 0 g, confirmed).
  (
    _palak,
    9,
    '15 curry leaves, roughly torn (optional)',
    null,
    'unmeasured',
    '1.000000',
    '0.00',
    '0.00',
    'flavouring, no nutrients — counted as 0 g',
  ),
  // W3 (flagged twice, the 167781 crystallized-ginger precedent: the record
  // a stand-in, and the grams bulgur's cup — engine `trimStandInFlagOf`).
  (
    _freekeh,
    10,
    '1½ cups cracked freekeh, rinsed',
    170688,
    'portion',
    '1.000000',
    '210.00',
    '718.20',
    '1 1/2 cup · USDA portion · approximation (counted as Bulgur, dry) · '
        'approximate (FDC holds no freekeh — a stand-in by class: SR 170688 '
        "Bulgur, dry (342 kcal); weighed at bulgur's own cup, 140 g — "
        "freekeh's cup is unpublished)",
  ),
];

/// The class's look-alikes, unchanged (file, position, raw start, record,
/// grams, kcal) — the v112 rows, equal on the v113 replay.
const _unmoved = [
  // W9a: the coat and the oil the fried-food readers size from the RAW
  // beef grams (P4 re-pins the coat's flour record later in the chain).
  (
    _steaks,
    0,
    '3 cups unbleached all-purpose flour',
    // RE-PIN (M102 batch, v115): the line names `unbleached` — 789951
    // (358 kcal, carbohydrate 73.2), the coat's grams 96.71 × 77.3 / 73.2
    // = 102.13, × 3.58 = 365.63 (was 789890, 96.71 g, 353.96).
    789951,
    '102.13',
    '365.63',
  ),
  (_steaks, 8, '4–5 cups peanut oil', 2710187, '84.11', '756.99'),
  // W6: the thighs and the boneless thigh keep their records.
  (
    '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml',
    5,
    '4 pounds bone-in turkey thighs',
    171533,
    '1487.78',
    '2395.33',
  ),
  (
    '0309-juicy-grilled-turkey-burgers.yaml',
    0,
    '1 (2-pound) bone-in turkey thigh',
    174518,
    '698.53',
    '810.30',
  ),
  // W2a / W9a: the other sausages (smoked, andouille, kielbasa, chorizo).
  (
    '0345-orecchiette-with-broccoli-rabe-and-sausage.yaml',
    2,
    '8 ounces hot Italian sausage, casings removed',
    171631,
    '226.80',
    '657.71',
  ),
  (
    '0028-chicken-and-sausage-gumbo.yaml',
    13,
    '8 ounces andouille sausage',
    174584,
    '226.80',
    '700.80',
  ),
  (
    '0295-indoor-clambake.yaml',
    2,
    '1 pound kielbasa',
    173879,
    '453.59',
    '1474.17',
  ),
  (
    '1208-albondigas-en-chipotle.yaml',
    15,
    '12 ounces Mexican-style chorizo sausage',
    173859,
    '340.19',
    '1006.97',
  ),
  // W9a: the oxtails stay on their ruled FNDDS yield.
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    0,
    '4 pounds oxtails',
    2705843,
    '1024.00',
    '2631.68',
  ),
  // W9b: a sibling on its own answer.
  (
    '0303-cincinnati-chili.yaml',
    1,
    '1½ pounds 80 percent lean ground chuck',
    2514744,
    '680.39',
    '1686.09',
  ),
  // W7a / W7b: plain low-fat yogurt, plain Greek yogurt.
  (
    '0044-kale-caesar-salad.yaml',
    5,
    '3 tablespoons plain low-fat yogurt',
    170886,
    '45.69',
    '28.79',
  ),
  (
    '0570-falafel.yaml',
    13,
    '⅓ cup plain Greek yogurt',
    2259794,
    '81.23',
    '76.77',
  ),
  // S14′: the lines naming 'flavored' never END in it.
  (
    '0540-pork-lo-mein.yaml',
    1,
    '2 tablespoons oyster-flavored sauce',
    2707150,
    '32.00',
    '16.32',
  ),
  (
    '0943-frozen-yogurt.yaml',
    1,
    // RE-PIN (M105 batch, v118): frozen-yogurt|1 on 169599 2.33 → 3.54 g (7.82 → 11.87 kcal), the replay's row — was '2.33', '7.82' (a v113 negative; v118's S8c moves it: the corpus packet, 0.7190 g/mL).
    '1 teaspoon unflavored gelatin',
    169599,
    '3.54',
    '11.87',
  ),
  // W3: bulgur itself.
  (
    '1176-red-lentil-kibbeh.yaml',
    7,
    '1 cup medium-grind bulgur',
    170688,
    '140.00',
    '478.80',
  ),
];

final _fx = FixtureProvider(pending: {...pendingSearches});

void main() {
  group('v113 (M100: record choice)', skip: skipIfNoCorpus, () {
    moved();
    unmoved();
    statuses();
  });
  keys();
  ranking();
}

/// Recipes whose other lines search answers the fixtures do not hold ("bone-in
/// turkey breasts", "red seedless grapes", "1 percent cottage cheese",
/// "oregano or dried"): computed with their real steps and only the pinned
/// line (no reader the batch touches sizes it from another line).
const Map<String, List<int>> _onlyLines = {
  _crowd: [12],
  '0424-italian-sausage-with-grapes-and-balsamic-vinegar.yaml': [1],
  '0914-light-new-york-cheesecake.yaml': [5],
  '1208-albondigas-en-chipotle.yaml': [15],
};

/// [r] stored and computed (its section children first), on a database
/// holding the landed details ([_landed]).
Future<Recipe> _compute(SaltDatabase db, Recipe r) async {
  final foods =
      jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final id in _landed) {
    db.fdcFoodCachePut(id, jsonEncode(foods['$id']));
  }
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, _fx, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [file] computed (whole, or its [_onlyLines]) and [position]'s index in it.
Future<(Recipe, int)> _computeAt(
  SaltDatabase db,
  String file,
  int position,
) async {
  final corpus = loadCorpusRecipe(file);
  final only = _onlyLines[file];
  if (only == null) return (await _compute(db, corpus), position);
  final lines = nutritionLines(corpus);
  return (
    await _compute(
      db,
      corpus.copyWith(
        ingredients: [
          IngredientGroup(items: [for (final k in only) lines[k]]),
        ],
      ),
    ),
    only.indexOf(position),
  );
}

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v113-');
  final db = SaltDatabase.open(
    ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath,
  )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

String _kcal(SaltDatabase db, IngredientMatchRow row) => row.fdcId == null
    ? (row.grams ?? 0).toStringAsFixed(2)
    : (kcalPer100g(knownFood(db, nutrientSiblings[row.fdcId] ?? row.fdcId!)!) *
              row.grams! /
              100)
          .toStringAsFixed(2);

/// Each moved row's record, status, source, confidence, grams, energy and
/// basis (the flag text, or its absence) in its real recipe.
void moved() {
  for (final (
        file,
        position,
        raw,
        fdcId,
        source,
        confidence,
        grams,
        kcal,
        basis,
      )
      in _moved) {
    test('$file|$position: $fdcId at $confidence, $grams g `$source`, $kcal '
        'kcal', () async {
      final db = _db();
      final (recipe, at) = await _computeAt(db, file, position);
      final line = nutritionLines(recipe)[at];
      expect(line.raw, startsWith(raw));
      final row = _row(db, recipe.id, at);
      expect(
        (row.fdcId, row.status, row.hold, row.gramSource),
        (fdcId, fdcId == null ? 'confirmed' : 'auto', null, source),
      );
      // The stored confidence (the replay's rows column 6): a rank word or
      // answer narrowed can keep the record and still move it — to below
      // the gate for W9b's words on the chuck answer (0.3825, the recipe
      // partial; verifier round 1 D3).
      expect(row.confidence.toStringAsFixed(6), confidence);
      expect(row.grams?.toStringAsFixed(2), grams);
      expect(_kcal(db, row), kcal);
      expect(gramBasisFor(db, line, row, recipe: recipe), basis);
    });
  }
}

/// R6's negatives: the look-alikes keep their v112 rows.
void unmoved() {
  for (final (file, position, raw, fdcId, grams, kcal) in _unmoved) {
    test('$file|$position unchanged: $fdcId $grams g, $kcal kcal', () async {
      final db = _db();
      final (recipe, at) = await _computeAt(db, file, position);
      expect(nutritionLines(recipe)[at].raw, startsWith(raw));
      final row = _row(db, recipe.id, at);
      expect(
        (row.fdcId, row.grams?.toStringAsFixed(2), _kcal(db, row)),
        (fdcId, grams, kcal),
      );
    });
  }
  test('the bulgur line on 170688 carries no freekeh flag (the W3 case is '
      "keyed on the line's own word)", () async {
    final db = _db();
    final (recipe, at) = await _computeAt(db, '1176-red-lentil-kibbeh.yaml', 7);
    final line = nutritionLines(recipe)[at];
    expect(
      gramBasisFor(db, line, _row(db, recipe.id, at), recipe: recipe),
      '1 cup · USDA portion',
    );
  });
  test('W6: the braised drumsticks and thighs on 171493 deduct nothing '
      '(no [braisedKept] key); on the thigh record 171533 the same line in '
      'the same recipe still would (v94)', () {
    final recipe = loadCorpusRecipe(_braised);
    const raw = '4 pounds turkey drumsticks and thighs, trimmed';
    expect(nutritionLines(recipe)[3].raw, startsWith(raw));
    expect(braisedKeptOf(raw, 171493, recipe, position: 3), isNull);
    expect(
      braisedKeptOf(
        raw,
        171533,
        recipe,
        position: 3,
      )?['energy']?.toStringAsFixed(6),
      '0.925419',
    );
  });
  test('the whole farro stays on 2710828 with no grams (the STATED label '
      'gap) and the red curry paste stays `no_match` with no record (a '
      '[noFdcRecordItems] veto)', () async {
    final db = _db();
    final (farro, f) = await _computeAt(db, '0717-simple-farro.yaml', 0);
    final row = _row(db, farro.id, f);
    expect((row.fdcId, row.grams), (2710828, null));
    final (gado, g) = await _computeAt(db, '1192-gado-gado.yaml', 0);
    final curry = _row(db, gado.id, g);
    expect(nutritionLines(gado)[g].raw, '2 tablespoons red curry paste');
    expect(
      (curry.fdcId, curry.grams, curry.status),
      (null, null, 'unmatched'),
    );
  });
}

/// The two recipe status changes (`partial` → `complete`), the one that
/// stays partial and W9b's recipe that stays complete.
void statuses() {
  for (final (file, status) in [
    (_palak, 'complete'),
    (_freekeh, 'complete'),
    (_frenchStyle, 'partial'),
    // W9b's row stays above the gate (verifier round 1 D3: a narrowed
    // rank word put it at 0.3825 and the recipe partial).
    ('0308-classic-stuffed-bell-peppers.yaml', 'complete'),
  ]) {
    test('$file is $status', () async {
      final db = _db();
      final recipe = await _compute(db, loadCorpusRecipe(file));
      expect(db.nutritionFor(recipe.id)!.status, status);
    });
  }
}

/// The tables (no corpus): every new key, its flag or the flag's absence,
/// and the keys no corpus line prints pinned EQUAL to a sibling whose
/// landing a corpus row pins.
void keys() {
  test('matcherVersion 105 (v113 set it, batch M100: 21 rows move)', () {
    // RE-PIN (M101 batch, v114): matcherVersion 100 (was 99).
    // RE-PIN (M102 batch, v115): matcherVersion 101 (was 100).
    // RE-PIN (M103 batch, v116): matcherVersion 102 (was 101).
    // RE-PIN (M104 batch, v117): matcherVersion 103 (was 102).
    // RE-PIN (M105 batch, v118): matcherVersion 104 (was 103).
    // RE-PIN (M106 batch, v119): matcherVersion 105 (was 104).
    expect(matcherVersion, 105);
  });

  test('every new key is a rank-as item; the unprinted numbers read their '
      "printed sibling's answer under its words", () {
    expect(
      rankAsKeys,
      containsAll([
        'turkey leg quarters',
        'turkey drumsticks and thighs',
        'sweet italian sausage',
        'sweet italian sausage link',
        'sweet italian sausage links',
        'hot italian sausage link',
        'hot italian sausage links',
        'hot or sweet italian sausage',
        'sweet or hot italian sausage',
        'bulk pork sausage',
        'cube steaks',
        'cube steak',
        'ground beef',
        'low-fat yogurt cheese',
        'plain whole-milk strained yogurt',
        'cracked freekeh',
        'freekeh',
      ]),
    );
    // No corpus line prints these (`grep -h -i -E "^\s*- raw: .*<p>"` over
    // the 1,198 recipes: 'sweet italian sausage link' 0, 'hot italian
    // sausage link[^s]' 0, 'cube steak[^s]' 0; 'freekeh' 1 — the cracked
    // freekeh line itself).
    for (final (key, printed) in [
      ('sweet italian sausage link', 'sweet italian sausage'),
      ('sweet italian sausage links', 'sweet italian sausage'),
      ('hot italian sausage link', 'hot italian sausage links'),
      ('cube steak', 'cube steaks'),
      ('freekeh', 'cracked freekeh'),
    ]) {
      expect(rankAsFor(key), isNotNull, reason: key);
      expect(rankAsFor(key), rankAsFor(printed), reason: key);
    }
    // The entries whose landing a narrowed answer leaves unchanged (their
    // own answers rank the same record first; verifier round 1 R9's probe —
    // only the offered runners-up differ): pinned by value (answer, words).
    for (final (key, answer, query) in [
      (
        'sweet or hot italian sausage',
        'hot italian sausage',
        'sausage italian pork raw',
      ),
      (
        'ground beef',
        '80 percent lean ground beef',
        '80 percent lean ground beef',
      ),
      (
        'plain whole-milk strained yogurt',
        'whole-milk greek yogurt',
        'whole-milk greek yogurt',
      ),
    ]) {
      expect(rankAsFor(key), (query: query, answer: answer), reason: key);
    }
    // The drumsticks and thighs read the leg quarters' answer (no cached
    // answer of their own holds 171493).
    expect(
      rankAsFor('turkey drumsticks and thighs'),
      rankAsFor('turkey leg quarters'),
    );
  });

  test('the flags: W6 leg quarters, W9a, W7a and W3 are flagged stand-ins; '
      'the drumsticks and thighs (the leg itself), W2a, W2b, W9b and W7b are '
      'not', () {
    for (final (key, fdcId) in [
      ('turkey leg quarters', 171493),
      ('cube steaks', 2646173),
      ('cube steak', 2646173),
      ('low-fat yogurt cheese', 170903),
      ('cracked freekeh', 170688),
      ('freekeh', 170688),
    ]) {
      expect(approximationRecords[key], fdcId, reason: key);
    }
    for (final key in [
      'turkey drumsticks and thighs',
      'sweet italian sausage',
      'hot italian sausage links',
      'hot or sweet italian sausage',
      'sweet or hot italian sausage',
      'bulk pork sausage',
      'ground beef',
      'plain whole-milk strained yogurt',
    ]) {
      expect(approximationRecords.containsKey(key), isFalse, reason: key);
    }
  });

  test("W6: the leg record's own roasted pair keeps every calorie, so "
      '171493 is no [braisedKept] key (the v94 tracer: cooked × P raw ÷ (P '
      'cooked × raw))', () async {
    // The pair (snapshot 33's caches, copied into the fixtures): 171493's
    // DETAIL (E 144, P 19.54, F 6.72; the search hit rounds P to 19.5) →
    // SR 171494 "Turkey, all classes, leg, meat and skin, cooked, roasted",
    // a hit in the recorded `turkey leg quarters` answer (E 208, P 27.9, F
    // 9.82) — no braised leg record is cached, as v94's thigh pair.
    final foods =
        jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
            as Map<String, dynamic>;
    final raw = {
      for (final e
          in ((foods['171493'] as Map<String, dynamic>)['nutrients']
                  as Map<String, dynamic>)
              .entries)
        e.key: (e.value as num).toDouble(),
    };
    final roast = (await _fx.search(
      'turkey leg quarters',
    )).singleWhere((h) => h.fdcId == 171494).nutrientsPer100g!;
    String share(String k) =>
        (roast[k]! * raw['203']! / (roast['203']! * raw[k]!)).toStringAsFixed(
          6,
        );
    expect((share('208'), share('204')), ('1.011629', '1.023440'));
    expect(braisedKept.containsKey(171493), isFalse);
    expect(braisedKept.containsKey(171533), isTrue);
  });

  test("W3's grams flag reads the line's own word `freekeh` on 170688 "
      '(engine `trimStandInFlagOf`), never a bulgur line', () {
    // SYNTHESIZED (the brief's exception: a key no corpus line prints) —
    // "1 cup freekeh" is the corpus line 1179|10 ("1½ cups cracked
    // freekeh, rinsed") with its `cracked` and prep dropped: the unprinted
    // `'freekeh'` rank-as key's line; the bulgur line is red-lentil-kibbeh|7.
    const flag =
        'approximate (FDC holds no freekeh — a stand-in by class: SR 170688 '
        "Bulgur, dry (342 kcal); weighed at bulgur's own cup, 140 g — "
        "freekeh's cup is unpublished)";
    expect(trimStandInFlagOf('1 cup freekeh', 170688), flag);
    expect(trimStandInFlagOf('1½ cups cracked freekeh, rinsed', 170688), flag);
    // SYNTHESIZED (the brief's exception: no corpus line capitalises the
    // word — the one freekeh line, 1179|10, is lowercase): the same line
    // as above with `Freekeh` capitalised pins the arm's case-fold.
    expect(trimStandInFlagOf('1 cup Freekeh', 170688), flag);
    expect(trimStandInFlagOf('1 cup medium-grind bulgur', 170688), isNull);
    expect(trimStandInFlagOf('1 cup freekeh', 172672), isNull);
  });

  test('W6: the leg record is an AH-102 turkey record, meat and skin', () {
    expect(ah102Records[171493], (species: 'turkey', meatOnly: false));
  });

  test('L368: both numbers are zero flavourings, neither a no-record veto '
      '(the veto would leave palak-dal partial)', () {
    for (final item in ['curry leaves', 'curry leaf']) {
      expect(isZeroNutrientFlavouring(item), isTrue, reason: item);
      expect(noFdcRecordItems, isNot(contains(item)), reason: item);
    }
    expect(isZeroNutrientFlavouring('red curry paste'), isFalse);
    expect(noFdcRecordItems, contains('red curry paste'));
  });
}

/// S14′ on the recorded 'tortilla chips' answer (snapshot 13's, the
/// fixtures'): the plain record ranks first once 'flavored' is an unasked
/// modified form; the head noun of a line naming 'flavored' is unchanged.
void ranking() {
  test("S14′: 'tortilla chips' ranks 2708202 \"Tortilla chips, plain\" "
      'over 2708204 "…, flavored" (the tie at 0.923 broken by the dock, no '
      "longer by FDC's order)", () async {
    final hits = await _fx.search('tortilla chips');
    final ranked = rankCandidates('tortilla chips', hits);
    expect(ranked.first.candidate.fdcId, 2708202);
    expect(ranked.first.confidence.toStringAsFixed(6), '0.923333');
    final flavored = ranked.firstWhere((c) => c.candidate.fdcId == 2708204);
    expect(flavored.confidence.toStringAsFixed(6), '0.863333');
    // The owner gate: the dock is QUERY-GATED — a query holding the token
    // exempts the record. SYNTHESIZED queries (no corpus line prints a
    // flavored tortilla chip; the 42 replay rows whose line names the word
    // move 0): a mutant docking 'flavored' whatever the query asks passed
    // the whole file and left the replay byte-identical. Each query's
    // CONFIDENCE is pinned, not only its first record: docked, the flavored
    // record still ranks first (the hand-edit verifier's mutant, the gate
    // skipped for a hyphenated '-flavored' query alone, passed the first
    // record's pin).
    for (final (query, confidence) in [
      ('flavored tortilla chips', '0.990000'),
      ('lime-flavored tortilla chips', '0.727500'),
    ]) {
      final asked = rankCandidates(query, hits).first;
      expect(asked.candidate.fdcId, 2708204, reason: query);
      expect(asked.confidence.toStringAsFixed(6), confidence, reason: query);
    }
    // 'unflavored' is another token: the flavored record stays docked.
    expect(
      rankCandidates('unflavored tortilla chips', hits).first.candidate.fdcId,
      2708202,
    );
  });

  test("S14′: a line naming 'flavored' never ends in it — the head noun "
      "is never 'flavored'", () {
    // MEASURED (every corpus row's normalized item, base eed6f10 vs v113):
    // exactly one head moves — 'oyster-flavored sauce' read 'flavored'
    // (the identity tail 'sauce' stepped back onto it) and reads 'oyster'
    // now that 'flavored' is a modified form; its 7 rows stay 2707150 on
    // the replay (its search query, the rewrite's, read 'oyster' on both).
    expect(headNounOf('oyster-flavored sauce'), 'oyster');
    expect(headNounOf('unflavored gelatin'), 'gelatin');
    expect(headNounOf('orange-flavored liqueur'), 'liqueur');
    expect(headNounOf('mild-flavored lager'), 'lager');
  });
}
