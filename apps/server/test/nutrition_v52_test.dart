// Real corpus lines are kept verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v52 (batch M51, references with no amount; matcherVersion 51;
// prep47 design_v2 §1 Q8, Q8b, Q9, Q22 and Q15 (iii), §2 "M51", decided
// under the owner's 2026-10-07 standing authorization, re-ruling prep41
// A3 (a) and CP3 for these lines; zero requests). Rule SW: a reference
// line with NO amount that is optional, for serving, offers an "or" or
// sits in a CONDIMENTS group is served with the dish — the 0 g rule row,
// accounted (a water row), never partial; D7's title rule keeps its own
// `servedWith` answer. Rule WB: any other such line reaching a child with
// lines, not nested, counts one whole batch (share 1.0), flagged. Rule PV:
// a reference to a section with no ingredient lines counts the base whose
// title shares the most words (the host on a tie; none shared: the
// `no_ingredients` row stays), flagged — it applies to lines WITH an amount
// (both reached lines print "1 recipe"). The critic's F7 gate: a line WITH
// an amount reads no served-with marker and no whole batch — the ten marked
// references with amounts stay as they were; D7's served-with accounting
// reaches herb-sauce|0 with or without an amount. RA1 (Q15 iii) shipped in v49; the coulis's frozen
// raspberries are read now that WB makes the coulis a child.
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider; 4
// searches and 6 foods added --from-db from snapshot 21, JSON-equal),
// never the network. Every row value is the v52 replay's (rp43 on
// snapshot 21). STATED SYNTHESIZED INPUTS (negative paths no corpus line
// holds): pan-seared-salmon|3 with its " or lemon wedges" cut (the
// "for serving" marker alone); the herb sauce's line with its "1 recipe"
// cut (D7 on a line with no amount); basic-double-crust-pie-dough given
// two prose sections, "Crust Pie Dough Variation" (3 words shared with the
// host AND with its Basic Single-Crust Pie Dough: a tie → the host) and
// "Graham Topping" (no word shared: `no_ingredients`), each named by a
// lemon-meringue-pie line; lemon-meringue-pie|0 rewritten to name
// "Graham Topping", with its amount and without (the not-accounted arm);
// lemon-meringue-pie|0 rewritten to the amount-less "Latin Flan (this
// page)" (the real lineless latin-flan: never WB's whole batch); for the
// hash fold (verifier round 3, D1), lemon-meringue-pie|0 rewritten
// amount-less to name 0972's prose "Single-Crust Pie Dough for Custard
// Pies" (and once with ", optional"), latin-flan or panna-cotta, then the
// prose section and latin-flan given the sibling Basic Single-Crust Pie
// Dough's lines and panna-cotta its |6 coulis line taken away.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/nutrition_composite.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// A STATED synthesized line, parsed as the importer parses one.
IngredientLine _line(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: parsed.item,
    prep: parsed.prep,
    amounts: parsed.amounts,
  );
}

const _salmon = '0256-pan-seared-salmon.yaml';
const _crab = '0288-maryland-crab-cakes.yaml';
const _curry =
    '0568-indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas.yaml';
const _tortilla =
    '0738-spanish-tortilla-with-roasted-red-peppers-and-peas.yaml';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _steaks = '0184-pan-seared-steaks.yaml';
const _fajitas = '0070-skillet-chicken-fajitas.yaml';
const _beans = '0712-red-beans-and-rice.yaml';
const _friedRice = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
const _panna = '0925-panna-cotta.yaml';
const _plum =
    '0983-fresh-plum-ginger-pie-with-whole-wheat-lattice-top-crust.yaml';
const _allButter = '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml';
const _lemon = '0989-lemon-meringue-pie.yaml';
const _dough = '0972-basic-double-crust-pie-dough.yaml';

const _files = [
  _salmon,
  _crab,
  _curry,
  _tortilla,
  _herb,
  _steaks,
  _fajitas,
  _beans,
  _friedRice,
  _panna,
  _plum,
  _allButter,
  _lemon,
  _dough,
];

/// The ten marked references WITH an amount (critic F7): (file, position,
/// the child's section title, share) — each unchanged in the v52 replay.
const _ten = [
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    15,
    'Nam Prik Pao (Thai Chili Jam)',
    1.0,
  ),
  ('0158-classic-roast-stuffed-turkey.yaml', 10, 'Giblet Pan Gravy', 1.0),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    4,
    'Golden Cornbread',
    0.75,
  ),
  (
    '0241-garlic-studded-roast-pork-loin.yaml',
    6,
    'Mustard–Shallot Sauce with Thyme',
    1.0,
  ),
  ('0282-spanish-style-toasted-pasta-with-shrimp.yaml', 16, 'Aioli', 1.0),
  ('0312-juicy-pub-style-burgers.yaml', 5, 'Pub-Style Burger Sauce', 1.0),
  (
    '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml',
    1,
    'Green Curry Paste',
    1.0,
  ),
  ('0598-grilled-pork-chops.yaml', 3, 'Basic Spice Rub for Pork Chops', 1.0),
  (
    '0607-grill-roasted-bone-in-pork-rib-roast.yaml',
    4,
    'Orange Salsa with Cuban Flavors',
    1.0,
  ),
  (
    '0892-dark-chocolate-cupcakes.yaml',
    11,
    'Easy Vanilla Bean Buttercream',
    1.0,
  ),
];

void main() {
  test(
    'the matcher version carries the batch (update the literal with a '
    'bump)',
    // RE-PIN (M52 batch, v53): matcherVersion 52 (was 51).
    // RE-PIN (Q25 batch, v54): matcherVersion 53 (was 52).
    // RE-PIN (M57 batch, v56): matcherVersion 55 (was 54).
    // RE-PIN (M58 batch, v57): matcherVersion 56 (was 55).
    // RE-PIN (M59 batch, v58): matcherVersion 57 (was 56).
    // RE-PIN (M60 batch, v59): matcherVersion 58 (was 57).
    // RE-PIN (M61 batch, v60): matcherVersion 59 (was 58).
    // RE-PIN (M62 batch, v61): matcherVersion 60 (was 59).
    // RE-PIN (M63 batch, v62): matcherVersion 61 (was 60).
    // RE-PIN (M64 batch, v63): matcherVersion 62 (was 61).
    // RE-PIN (M65 batch, v64): matcherVersion 63 (was 62).
    // RE-PIN (M66 batch, v65): matcherVersion 64 (was 63).
    // RE-PIN (M67 batch, v66): matcherVersion 65 (was 64).
    // RE-PIN (M68 batch, v67): matcherVersion 66 (was 65).
    // RE-PIN (M69 batch, v68): matcherVersion 67 (was 66).
    // RE-PIN (M70 batch, v69): matcherVersion 68 (was 67).
    () => expect(matcherVersion, 68),
  );

  group('matcher v52 (batch M51)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v52-');
      db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider();
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    void store(List<String> files) {
      for (final file in files) {
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(
          recipe,
          sourceSlug: _source,
          contentHash: contentHashOf(recipe),
        );
      }
    }

    Recipe stored(String file) =>
        nutritionRecipeOf(db, loadCorpusRecipe(file).id)!.recipe;

    String keyOf(String file, String title) =>
        sectionKeyOf(loadCorpusRecipe(file).id, title);

    Future<void> sweep([BulkScope scope = BulkScope.all]) async {
      final job = startBulkJob(db, provider, scope: scope);
      expect(job, isNotNull);
      while (bulkJobRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(db.nutritionJob(job!)!['status'], 'done');
      expect(db.nutritionJob(job)!['failed'], 0);
    }

    IngredientMatchRow rowAt(String file, int position, {String? section}) => db
        .ingredientMatchesFor(
          section == null ? stored(file).id : keyOf(file, section),
        )
        .singleWhere((row) => row.position == position);

    ReferenceResolution resolve(Recipe recipe, IngredientLine line) =>
        resolveReference(db, recipe, line, ResolverMemo(db));

    ReferenceResolution resolveAt(String file, int position) {
      final recipe = stored(file);
      return resolve(recipe, nutritionLines(recipe)[position]);
    }

    String? flagAt(String file, int position) {
      final recipe = stored(file);
      return compositeFlagOf(
        db,
        recipe,
        nutritionLines(recipe)[position],
        rowAt(file, position),
        ResolverMemo(db),
      );
    }

    ({
      List<Map<String, Object?>> includes,
      List<Map<String, Object?>> partial,
      List<Map<String, Object?>> servedWith,
    })
    summaryOf(String file) => referenceSummary(
      db,
      stored(file),
      db.ingredientMatchesFor(stored(file).id),
      ResolverMemo(db),
    );

    test('SW: the six served-with lines stay the 0 g rule row, reason '
        'served_with, and count ACCOUNTED — salmon, the curry, the tortilla '
        'and the herb sauce complete; crab cakes stays partial on |3 |8 |9; '
        'the label lists them served with, never partial', () async {
      store(_files);
      await sweep();
      const sw = [
        (
          _salmon,
          3,
          'Sweet-and-Sour Chutney (recipe follows) or lemon wedges, for serving',
          'Sweet-and-Sour Chutney or lemon wedges',
        ),
        (
          _crab,
          10,
          'Sweet and Tangy Tartar Sauce (this page), Creamy Chipotle Chile Sauce (recipe follows), or lemon wedges',
          'Sweet and Tangy Tartar Sauce',
        ),
        (_curry, 16, 'Onion Relish (recipe follows)', 'Onion Relish'),
        (
          _curry,
          17,
          'Cilantro-Mint Chutney (recipe follows) or mango chutney',
          'Cilantro-Mint Chutney or mango chutney',
        ),
        (
          _tortilla,
          8,
          'Garlic Mayonnaise (optional) (recipe follows)',
          'Garlic Mayonnaise',
        ),
        (
          _herb,
          0,
          '1 recipe Pan-Seared Steaks (this page)',
          'Pan-Seared Steaks',
        ),
      ];
      for (final (file, position, raw, name) in sw) {
        final row = rowAt(file, position);
        expect(row.raw, raw);
        expect(
          (
            row.fdcId,
            row.grams,
            row.description,
            row.status,
            row.childRecipeId,
          ),
          (null, 0.0, subRecipeNote, 'confirmed', null),
          reason: raw,
        );
        expect(resolveAt(file, position).kind, ReferenceKind.servedWith);
        final recipe = stored(file);
        expect(
          referenceChildJson(
            db,
            recipe,
            position,
            nutritionLines(recipe)[position],
            row,
            ResolverMemo(db),
            slim: true,
          ),
          allOf(
            containsPair('state', 'not_routed'),
            containsPair('reason', 'served_with'),
            containsPair('name', name),
          ),
        );
      }
      for (final (file, count, sw) in [
        (_salmon, 4, [(3, 'Sweet-and-Sour Chutney')]),
        (_curry, 18, [(16, 'Onion Relish'), (17, 'Cilantro-Mint Chutney')]),
        (_tortilla, 9, [(8, 'Garlic Mayonnaise')]),
        (_herb, 10, [(0, 'Pan-Seared Steaks')]),
      ]) {
        final n = db.nutritionFor(stored(file).id)!;
        expect(
          (n.status, n.matchedCount, n.totalCount),
          (
            'complete',
            count,
            count,
          ),
          reason: file,
        );
        final summary = summaryOf(file);
        expect(summary.partial, isEmpty, reason: file);
        expect(summary.servedWith, [
          for (final (position, name) in sw)
            {'position': position, 'name': name},
        ]);
      }
      // Crab cakes: served with its sauces, partial on its own |3 Old Bay
      // (vetoed, Q23). RE-PIN (M52 batch, v53): was partial on three — |8
      // the coating (now the coat budget) and |9 the frying oil (now Q24 b's
      // frying oil, its crab's uptake) count (was 8 of 11).
      final crab = db.nutritionFor(stored(_crab).id)!;
      expect(
        (crab.status, crab.matchedCount, crab.totalCount),
        (
          'partial',
          10,
          11,
        ),
      );
      expect(rowAt(_crab, 3).status, 'unmatched');
      // RE-PIN (M52 batch, v53): |8 counted by the coat budget (C1, f = 1:
      // the whole ¼ cup) and |9 the crab's frying oil (Q24 b), both unheld.
      expect(
        (rowAt(_crab, 8).hold, rowAt(_crab, 8).grams?.toStringAsFixed(2)),
        (null, '30.16'),
      );
      // RE-PIN (M63 batch, v62, Q11): |9 at the crab cake's own read oil,
      // FNDDS 2706549's 7.69 % (was 30.30 on the breast's 6.68 % stand-in).
      expect(
        (rowAt(_crab, 9).hold, rowAt(_crab, 9).grams?.toStringAsFixed(2)),
        (null, '34.88'),
      );
      expect(summaryOf(_crab).servedWith, [
        {'position': 10, 'name': 'Sweet and Tangy Tartar Sauce'},
      ]);
    });

    test('SW markers, one line each: optional (tortilla|8), " or " (crab '
        'cakes|10), a CONDIMENTS group (curry|16); not SW: fajitas|22, its '
        'group "RAJAS CON CREMA"; STATED synthesized: "for serving" alone '
        '(salmon|3 with " or lemon wedges" cut) and D7 on a line with no '
        'amount (the herb sauce line with "1 recipe" cut)', () {
      store(_files);
      for (final (file, position, marked) in [
        (_tortilla, 8, true),
        (_crab, 10, true),
        (_curry, 16, true),
        (_curry, 17, true),
        (_salmon, 3, true),
        (_fajitas, 22, false),
        (_beans, 14, false),
        (_panna, 6, false),
      ]) {
        final recipe = stored(file);
        final line = nutritionLines(recipe)[position];
        expect(line.amounts, isEmpty, reason: line.raw);
        expect(servedWithMarked(recipe, line), marked, reason: line.raw);
      }
      final fajitas = stored(_fajitas);
      expect(
        fajitas.ingredients
            .singleWhere(
              (g) => g.items.any(
                (l) => l.raw == 'Spicy Pickled Radishes (recipe follows)',
              ),
            )
            .group,
        'RAJAS CON CREMA',
      );
      // The only CONDIMENTS heading of the library holds curry|16 and |17.
      expect(
        stored(_curry).ingredients.last.group,
        'CONDIMENTS',
      );
      final forServing = _line(
        'Sweet-and-Sour Chutney (recipe follows), for serving',
      );
      expect(forServing.amounts, isEmpty);
      expect(servedWithMarked(stored(_salmon), forServing), isTrue);
      expect(
        resolve(stored(_salmon), forServing).kind,
        ReferenceKind.servedWith,
      );
      final d7 = _line('Pan-Seared Steaks (this page)');
      expect(d7.amounts, isEmpty);
      expect(servedWithMarked(stored(_herb), d7), isFalse);
      expect(resolve(stored(_herb), d7).kind, ReferenceKind.servedWith);
    });

    test('WB: the three amount-less plated references count ONE whole batch '
        '(share 1.000000), flagged; their three new child sections computed '
        'alone (radishes 5/5; rice 2/2, 402.2 g of 2512381; coulis 4/4, RA1 '
        '2709282 at 680.39 g); the three recipes complete', () async {
      store(_files);
      await sweep();
      for (final (file, position, raw, host, title, grams, kcal, lines, count)
          in [
            (
              _fajitas,
              22,
              'Spicy Pickled Radishes (recipe follows)',
              _fajitas,
              'Spicy Pickled Radishes',
              184.3,
              55.55,
              5,
              24,
            ),
            (
              _beans,
              14,
              'Basic White Rice (this page)',
              _friedRice,
              'Basic White Rice',
              402.2,
              1442.71,
              2,
              18,
            ),
            (
              _panna,
              6,
              'Raspberry Coulis (recipe follows)',
              _panna,
              'Raspberry Coulis',
              748.2,
              642.77,
              4,
              7,
            ),
          ]) {
        final key = keyOf(host, title);
        final row = rowAt(file, position);
        expect(row.raw, raw);
        expect(
          (row.childRecipeId, row.childShare, row.grams, row.hold, row.status),
          (key, 1.0, grams, null, 'auto'),
          reason: raw,
        );
        expect(flagAt(file, position), wbFlag);
        final section = db.nutritionFor(key)!;
        expect(
          (section.status, section.matchedCount, section.totalCount),
          ('complete', lines, lines),
        );
        expect(section.totalGrams, grams);
        expect(batchTotalsOf(section)['energy'], closeTo(kcal, 0.005));
        expect(row.childStamp, section.computedAt);
        final n = db.nutritionFor(stored(file).id)!;
        expect(
          (n.status, n.matchedCount, n.totalCount),
          (
            'complete',
            count,
            count,
          ),
        );
        expect(
          summaryOf(file).includes.single,
          containsPair('flag', 'approximation'),
        );
      }
      expect(
        db.nutritionFor(stored(_beans).id)!.caloriesPerServing,
        closeTo(711.48, 0.005),
      );
      final rice = rowAt(_friedRice, 1, section: 'Basic White Rice');
      expect(
        (rice.raw, rice.fdcId),
        ('2 cups long-grain white rice, rinsed', 2512381),
      );
      expect(rice.grams, closeTo(402.2, 0.005));
      // RA1 (shipped v49): the coulis's frozen raspberries on FNDDS 2709282.
      final berries = rowAt(_panna, 0, section: 'Raspberry Coulis');
      expect(
        (berries.raw, berries.fdcId),
        ('24 ounces (about 5 cups) frozen raspberries', 2709282),
      );
      expect(berries.grams, closeTo(680.39, 0.005));
    });

    test('PV: the two prose-variation references count their base, flagged '
        "— plum|0 the host 0976 (6 shared words), lemon|0 0972's Basic "
        'Single-Crust Pie Dough (4) and NEVER the double-crust host (3; '
        '3,519.96 kcal); the F2 fold still lists the prose section', () async {
      store(_files);
      await sweep();
      final allButter = loadCorpusRecipe(_allButter).id;
      final single = keyOf(_dough, 'Basic Single-Crust Pie Dough');
      for (final (file, raw, child, title, grams, perServing, count) in [
        (
          _plum,
          '1 recipe Foolproof Whole-Wheat Dough for Double-Crust Pie (this page)',
          allButter,
          'Foolproof All-Butter Dough for Double-Crust Pie',
          669.1,
          586.77,
          9,
        ),
        (
          _lemon,
          '1 recipe Single-Crust Pie Dough for Custard Pies (this page), fitted into a 9-inch pie plate and chilled',
          single,
          'Basic Single-Crust Pie Dough',
          302.1,
          435.07,
          14,
        ),
      ]) {
        final row = rowAt(file, 0);
        expect(row.raw, raw);
        expect(
          (row.childRecipeId, row.childShare, row.grams, row.hold, row.status),
          (child, 1.0, grams, null, 'auto'),
        );
        expect(flagAt(file, 0), pvFlagOf(title));
        final n = db.nutritionFor(stored(file).id)!;
        expect(
          (n.status, n.matchedCount, n.totalCount),
          (
            'complete',
            count,
            count,
          ),
        );
        expect(n.caloriesPerServing, closeTo(perServing, 0.005));
      }
      expect(rowAt(_lemon, 0).childRecipeId, isNot(stored(_dough).id));
      expect(
        batchTotalsOf(db.nutritionFor(stored(_dough).id)!)['energy'],
        closeTo(3519.96, 0.005),
      );
      expect(proseSectionsReadBy(stored(_lemon), ResolverMemo(db)), [
        keyOf(_dough, 'Single-Crust Pie Dough for Custard Pies'),
      ]);
      expect(proseSectionsReadBy(stored(_plum), ResolverMemo(db)), [
        keyOf(_allButter, 'Foolproof Whole-Wheat Dough for Double-Crust Pie'),
      ]);
      expect(summaryOf(_lemon).includes.single, {
        'slug': 'basic-double-crust-pie-dough',
        'title': 'Basic Single-Crust Pie Dough',
        'section': 'Basic Single-Crust Pie Dough',
        'host_title': 'Basic Double-Crust Pie Dough',
        'flag': 'approximation',
      });
    });

    test('the F7 gate: the ten marked references WITH an amount carry a '
        'served-with marker and still route as ruled (child, share; their '
        'grams are byte-equal in the v52 replay)', () {
      store([for (final (file, _, _, _) in _ten) file]);
      store(['0154-classic-roast-turkey.yaml']);
      for (final (file, position, title, share) in _ten) {
        final recipe = stored(file);
        final line = nutritionLines(recipe)[position];
        expect(line.amounts, isNotEmpty, reason: line.raw);
        expect(servedWithMarked(recipe, line), isTrue, reason: line.raw);
        final found = resolve(recipe, line);
        expect(
          (found.kind, found.section?.title, found.share, found.variation),
          (ReferenceKind.routed, title, share, null),
          reason: line.raw,
        );
      }
    });

    test("the drippings line (old-fashioned-stuffed-turkey's Make-Ahead "
        'Turkey Gravy, a variation no line routes to) makes no row: its '
        'section is no child, so nothing computes it', () {
      const file = '0156-old-fashioned-stuffed-turkey.yaml';
      store([file]);
      final key = keyOf(file, 'Make-Ahead Turkey Gravy');
      final section = nutritionRecipeOf(db, key)!.recipe;
      expect(
        nutritionLines(section).map((l) => l.raw),
        contains(
          'Defatted drippings from Old-Fashioned Stuffed Turkey (this page) (optional)',
        ),
      );
      expect(
        sectionChildKeysOf(db, stored(file), ResolverMemo(db)),
        isNot(contains(key)),
      );
      expect(bulkScopeIds(db, BulkScope.all), isNot(contains(key)));
    });

    test('PV, STATED synthesized (no corpus line reaches either): 0972 given '
        'two prose sections — "Crust Pie Dough Variation" ties the host and '
        'its Basic Single-Crust Pie Dough at 3 words → the HOST; "Graham '
        'Topping" shares none → the no_ingredients row stays', () {
      final dough = loadCorpusRecipe(_dough);
      final edited = dough.copyWith(
        subsections: [
          ...dough.subsections,
          const Subsection(
            title: 'Crust Pie Dough Variation',
            kind: 'variation',
            body: 'A stated synthesized prose variation.',
          ),
          const Subsection(
            title: 'Graham Topping',
            kind: 'variation',
            body: 'A stated synthesized prose variation.',
          ),
        ],
      );
      db.upsertRecipe(
        edited,
        sourceSlug: _source,
        contentHash: contentHashOf(edited),
      );
      store([_lemon]);
      final lemon = stored(_lemon);
      final tie = resolve(
        lemon,
        _line('1 recipe Crust Pie Dough Variation (this page)'),
      );
      expect(
        (tie.kind, tie.childId, tie.section, tie.share, tie.variation?.title),
        (
          ReferenceKind.routed,
          dough.id,
          null,
          1.0,
          'Crust Pie Dough Variation',
        ),
      );
      final none = resolve(
        lemon,
        _line('1 recipe Graham Topping (this page)'),
      );
      expect(
        (none.kind, none.noIngredients, none.section?.title, none.variation),
        (ReferenceKind.section, true, 'Graham Topping', null),
      );
    });

    // Verifier round 1, D1: v41's R3 pinned recomputeTotals' not-accounted
    // arm on the herb sauce, which v52 makes served with; no corpus line
    // reaches the arm since v52, so it is pinned here.
    for (final (raw, kind, title, reason) in [
      (
        '1 recipe Graham Topping (this page)',
        ReferenceKind.section,
        'Graham Topping',
        'no_ingredients',
      ),
      ('Graham Topping (this page)', ReferenceKind.noAmount, null, 'no_amount'),
    ]) {
      test('the not-accounted arm, STATED synthesized: lemon-meringue-pie|0 '
          'rewritten to "$raw" (0972 given the prose "Graham Topping", no '
          'word shared) — a reference neither routed nor served with stays '
          'the 0 g rule row, NOT accounted: lemon partial 13/14, the line '
          'listed partial ($reason), never served with', () async {
        final dough = loadCorpusRecipe(_dough);
        final lemon = loadCorpusRecipe(_lemon);
        for (final recipe in [
          dough.copyWith(
            subsections: [
              ...dough.subsections,
              const Subsection(
                title: 'Graham Topping',
                kind: 'variation',
                body: 'A stated synthesized prose variation.',
              ),
            ],
          ),
          lemon.copyWith(
            ingredients: [
              lemon.ingredients.first.copyWith(items: [_line(raw)]),
              ...lemon.ingredients.skip(1),
            ],
          ),
        ]) {
          db.upsertRecipe(
            recipe,
            sourceSlug: _source,
            contentHash: contentHashOf(recipe),
          );
        }
        await sweep();
        final row = rowAt(_lemon, 0);
        expect(row.raw, raw);
        expect(
          (
            row.fdcId,
            row.grams,
            row.description,
            row.status,
            row.childRecipeId,
          ),
          (null, 0.0, subRecipeNote, 'confirmed', null),
        );
        expect(resolveAt(_lemon, 0).kind, kind);
        final n = db.nutritionFor(stored(_lemon).id)!;
        expect(
          (n.status, n.matchedCount, n.totalCount),
          (
            'partial',
            13,
            14,
          ),
        );
        final summary = summaryOf(_lemon);
        expect(summary.servedWith, isEmpty);
        expect(summary.includes, isEmpty);
        expect(summary.partial, [
          {
            'position': 0,
            'kind': 'not_routed',
            'name': 'Graham Topping',
            'title': title,
            'matched': null,
            'total': null,
            'reason': reason,
          },
        ]);
      });
    }

    // Verifier round 2, D1: rule WB's whole batch is for "a child with
    // lines" (P5 §3); latin-flan is a REAL library recipe with no
    // ingredient lines (its lines sit in a "CHECK BACK FOR FINAL"
    // subsection), and no corpus line names it with no amount.
    test('WB never reaches a lineless LIBRARY recipe, STATED synthesized: '
        'lemon-meringue-pie|0 rewritten to "Latin Flan (this page)" (no '
        'amount, unmarked) → noAmount, the 0 g rule row, lemon partial '
        '13/14 with the line listed partial (no_amount), never routed at '
        'share 1.0', () async {
      const raw = 'Latin Flan (this page)';
      final flan = loadCorpusRecipe('0929-latin-flan.yaml');
      expect(nutritionLines(flan), isEmpty);
      final lemon = loadCorpusRecipe(_lemon);
      for (final recipe in [
        flan,
        lemon.copyWith(
          ingredients: [
            lemon.ingredients.first.copyWith(items: [_line(raw)]),
            ...lemon.ingredients.skip(1),
          ],
        ),
      ]) {
        db.upsertRecipe(
          recipe,
          sourceSlug: _source,
          contentHash: contentHashOf(recipe),
        );
      }
      await sweep();
      expect(resolveAt(_lemon, 0).kind, ReferenceKind.noAmount);
      final row = rowAt(_lemon, 0);
      expect(row.raw, raw);
      expect(
        (
          row.fdcId,
          row.grams,
          row.description,
          row.status,
          row.childRecipeId,
          row.childShare,
        ),
        (null, 0.0, subRecipeNote, 'confirmed', null, null),
      );
      final n = db.nutritionFor(stored(_lemon).id)!;
      expect((n.status, n.matchedCount, n.totalCount), ('partial', 13, 14));
      final summary = summaryOf(_lemon);
      expect(summary.servedWith, isEmpty);
      expect(summary.includes, isEmpty);
      expect(summary.partial, [
        {
          'position': 0,
          'kind': 'not_routed',
          'name': 'Latin Flan',
          'title': null,
          'matched': null,
          'total': null,
          'reason': 'no_amount',
        },
      ]);
    });

    // Verifier round 3, D1: a line with NO amount resolves by its child's
    // LINES (WB's whole batch, or `noAmount` when the child lists none or
    // is made from a recipe), and its 0 g rule row ties no stamp — so the
    // parent's hash folds that child ([proseSectionsReadBy]): gaining or
    // losing those lines stales the parent at once and ONE stale sweep
    // settles it. STATED synthesized (no corpus line reaches it).
    const custard = 'Single-Crust Pie Dough for Custard Pies';
    const custardRaw =
        '$custard (this page), fitted into a 9-inch pie plate and chilled';
    const flanFile = '0929-latin-flan.yaml';
    List<IngredientGroup> basicLines() =>
        loadCorpusRecipe(
              _dough,
            ).subsections
            .singleWhere((s) => s.title == 'Basic Single-Crust Pie Dough')
            .ingredients!;
    Recipe lemonNaming(String raw) {
      final lemon = loadCorpusRecipe(_lemon);
      return lemon.copyWith(
        ingredients: [
          lemon.ingredients.first.copyWith(items: [_line(raw)]),
          ...lemon.ingredients.skip(1),
        ],
      );
    }

    Recipe doughGained() {
      final dough = loadCorpusRecipe(_dough);
      return dough.copyWith(
        subsections: [
          for (final sub in dough.subsections)
            sub.title == custard
                ? sub.copyWith(ingredients: basicLines())
                : sub,
        ],
      );
    }

    Recipe pannaUnnested() {
      final panna = loadCorpusRecipe(_panna);
      return panna.copyWith(
        ingredients: [
          for (final group in panna.ingredients)
            group.copyWith(
              items: [
                for (final line in group.items)
                  if (!isReferenceIn(panna, line)) line,
              ],
            ),
        ],
      );
    }

    // The batch a gain routes: Basic Single-Crust's 302.1 g (the PV pin's);
    // panna-cotta's six lines 244.00 + 6.42 + 716.86 + 0 + 75.41 + 0.40 (the
    // v51 replay's rows) = 1,043.1 g.
    for (final (what, raw, first, then, folded, gains, grams) in [
      (
        'the prose section GAINS lines',
        custardRaw,
        () => [loadCorpusRecipe(_dough)],
        doughGained,
        () => keyOf(_dough, custard),
        true,
        302.1,
      ),
      (
        'the section LOSES its lines',
        custardRaw,
        () => [doughGained()],
        () => loadCorpusRecipe(_dough),
        () => keyOf(_dough, custard),
        false,
        0.0,
      ),
      (
        'the lineless library latin-flan GAINS lines',
        'Latin Flan (this page)',
        () => [loadCorpusRecipe(flanFile)],
        () => loadCorpusRecipe(flanFile).copyWith(ingredients: basicLines()),
        () => loadCorpusRecipe(flanFile).id,
        true,
        302.1,
      ),
      (
        'panna-cotta (nested: its |6 coulis line) loses its reference line',
        'Panna Cotta (this page)',
        () => [loadCorpusRecipe(_panna)],
        pannaUnnested,
        () => loadCorpusRecipe(_panna).id,
        true,
        1043.1,
      ),
    ]) {
      test(
        'the fold, STATED synthesized: lemon-meringue-pie|0 rewritten to '
        'the amount-less "$raw"; $what → lemon reads stale at once and '
        'ONE stale sweep ${gains ? 'routes WB' : 'returns no_amount'}',
        () async {
          for (final recipe in [...first(), lemonNaming(raw)]) {
            db.upsertRecipe(
              recipe,
              sourceSlug: _source,
              contentHash: contentHashOf(recipe),
            );
          }
          await sweep();
          final lemonId = stored(_lemon).id;
          final fold = proseSectionsReadBy(stored(_lemon), ResolverMemo(db));
          expect(fold, gains ? [folded()] : isEmpty);
          expect(nutritionIsFresh(db, stored(_lemon)), isTrue);
          final edited = then();
          db.upsertRecipe(
            edited,
            sourceSlug: _source,
            contentHash: contentHashOf(edited),
          );
          expect(
            proseSectionsReadBy(stored(_lemon), ResolverMemo(db)),
            gains ? isEmpty : [folded()],
          );
          expect(nutritionIsFresh(db, stored(_lemon)), isFalse);
          expect(bulkScopeIds(db, BulkScope.stale), contains(lemonId));
          await sweep(BulkScope.stale);
          expect(nutritionIsFresh(db, stored(_lemon)), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
          final row = rowAt(_lemon, 0);
          expect(row.grams, grams);
          final n = db.nutritionFor(lemonId)!;
          if (gains) {
            final child = edited.id == loadCorpusRecipe(_dough).id
                ? keyOf(_dough, custard)
                : edited.id;
            expect(resolveAt(_lemon, 0).kind, ReferenceKind.routed);
            expect(
              (row.childRecipeId, row.childShare, row.description),
              (child, 1.0, null),
            );
            expect(row.grams, db.nutritionFor(child)!.totalGrams);
            expect(
              (n.status, n.matchedCount, n.totalCount),
              (
                'complete',
                14,
                14,
              ),
            );
          } else {
            expect(resolveAt(_lemon, 0).kind, ReferenceKind.noAmount);
            expect(
              (row.grams, row.childRecipeId, row.description),
              (0.0, null, subRecipeNote),
            );
            expect(
              (n.status, n.matchedCount, n.totalCount),
              (
                'partial',
                13,
                14,
              ),
            );
          }
        },
      );
    }

    test('the fold skips a served-with line, STATED synthesized: '
        'lemon-meringue-pie|0 rewritten to "$custard (this page), '
        'optional" reads no child, so the prose section gaining lines '
        'leaves lemon fresh (served with, 0 g, accounted)', () async {
      for (final recipe in [
        loadCorpusRecipe(_dough),
        lemonNaming('$custard (this page), optional'),
      ]) {
        db.upsertRecipe(
          recipe,
          sourceSlug: _source,
          contentHash: contentHashOf(recipe),
        );
      }
      await sweep();
      expect(proseSectionsReadBy(stored(_lemon), ResolverMemo(db)), isEmpty);
      final edited = doughGained();
      db.upsertRecipe(
        edited,
        sourceSlug: _source,
        contentHash: contentHashOf(edited),
      );
      expect(resolveAt(_lemon, 0).kind, ReferenceKind.servedWith);
      expect(nutritionIsFresh(db, stored(_lemon)), isTrue);
      expect(rowAt(_lemon, 0).grams, 0.0);
      expect(db.nutritionFor(stored(_lemon).id)!.status, 'complete');
    });
  });
}
