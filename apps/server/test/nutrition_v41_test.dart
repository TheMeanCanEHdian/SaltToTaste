// The resolution table keeps each real section title verbatim, one
// literal per entry (v44).
// ignore_for_file: lines_longer_than_80_chars

// Matcher v41, step 2 (design_v3 §2.2): the composite row in the ENGINE —
// sub-recipe routing phase 1 (R1), rule B1's two-part rendered-bacon row
// (R2), the partial label of every reference line not routed (R3), the
// `choose_recipe` / `nested_recipe` / `discarded_recipe` holds, the
// derivation's child arm, and A10 (a)'s food alternative — under the
// owner's 2026-10-05 rulings (A1-A10 as recommended; D2, D11, D12).
//
// Real corpus recipes over the recorded real FDC answers (FixtureProvider,
// copied --from-db from snapshot 17), never the network. A recipe pick
// (`child` on the match PUT) is step 3's API: until it ships, a pin stores
// the decided row in the shape that PUT stores (a person's status, the
// child, its share) and the REAL compute derives it — the path every
// later PUT, compute and GET takes ([derivedFor]).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/nutrition_composite.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// v51 (M49 Q4 b): rule B1's flag.
const String _ah102Flag =
    'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → '
    'cooked 33 % (18–43))';

// The corpus files the pins compute (every FDC answer they read is a
// fixture copied from snapshot 17).
const _deliHam = '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml';
const _allButter = '0973-all-butter-double-crust-pie-dough.yaml';
const _basic = '0972-basic-double-crust-pie-dough.yaml';
const _foolproofDouble = '0974-foolproof-double-crust-pie-dough.yaml';
const _graham = '0977-graham-cracker-crust.yaml';
const _tartDough = '0994-classic-tart-dough.yaml';
const _single = '0975-foolproof-all-butter-dough-for-single-crust-pie.yaml';
const _guacamole = '0472-chunky-guacamole.yaml';
const _blueberry = '0979-blueberry-pie.yaml';
const _deepDish = '0978-deep-dish-apple-pie.yaml';
const _summerBerry = '0980-summer-berry-pie.yaml';
const _keyLime = '0989-key-lime-pie.yaml';
const _coconut = '0991-coconut-cream-pie.yaml';
const _nachos = '0471-cheesy-nachos-with-guacamole-and-salsa.yaml';
const _freeForm = '1005-free-form-apple-tart.yaml';
const _steakTips = '0583-grilled-steak-tips.yaml';
const _thai = '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml';
const _porkChops = '0598-grilled-pork-chops.yaml';
const _wilted = '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml';
const _tenderloin = '0234-pan-seared-oven-roasted-pork-tenderloin.yaml';
const _herbSauce =
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _lemonTart = '0994-lemon-tart.yaml';
const _fruitTart = '0997-fresh-fruit-tart-with-pastry-cream.yaml';
// RE-PIN (M47 batch, v49 Q12): the held line the partial-child pins append
// (its kiwi counts now): Foundation 2747675, held no_nutrients.
const _watermelon = '1071-watermelon-salad-with-cotija-and-serrano-chiles.yaml';

/// Every corpus line that resolves as a sub-recipe reference (the 119 the
/// shipped detector zeroes; engine_lines.tsv with A7 a, A8 a and D11
/// applied): what it resolves to.
const Map<String, String> _resolved = {
  'guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp|15':
      'routed section Nam Prik Pao (Thai Chili Jam)',
  'creamy-mushroom-soup|12': 'routed section Sautéed Wild Mushrooms',
  'broccoli-cheese-soup|13':
      'routed section Buttery Croutons of carrot-ginger-soup',
  'crispy-thai-eggplant-salad|14':
      'routed section Fried Shallots and Fried Shallot Oil',
  // RE-PIN (M51 batch, v52 — WB, SW, PV, design_v2 Q22 / Q8 / Q9): ten
  // entries moved — fajitas|22, red-beans-and-rice|14, panna-cotta|6
  // (were noAmount) route one whole batch; pan-seared-salmon|3,
  // maryland-crab-cakes|10, the curry's |16 |17 and spanish-tortilla|8 (were
  // noAmount) are servedWith; fresh-plum-ginger-pie|0 and
  // lemon-meringue-pie|0 (were "section no_ingredients") count their base.
  'skillet-chicken-fajitas|22': 'routed section Spicy Pickled Radishes',
  'indoor-pulled-chicken|7': 'held generic',
  'peruvian-roast-chicken-with-garlic-and-lime|12':
      'routed section Spicy Mayonnaise',
  'high-roast-butterflied-chicken-with-potatoes|3':
      'routed section Mustard-Garlic Butter with Thyme',
  'stuffed-roast-butterflied-chicken|5':
      'routed section Mushroom-Leek Bread Stuffing with Herbs',
  'buffalo-wings|13': 'held missing',
  'classic-roast-turkey|8': 'routed section Giblet Pan Gravy',
  'classic-roast-stuffed-turkey|7':
      'routed section Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions',
  'classic-roast-stuffed-turkey|10':
      'routed section Giblet Pan Gravy of classic-roast-turkey',
  'crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing|4':
      'routed section Golden Cornbread',
  'crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing|17':
      'routed section Turkey Gravy',
  'restaurant-style-herb-sauce-for-pan-seared-steaks|0': 'servedWith',
  'restaurant-style-herb-sauce-for-pan-seared-steaks|3':
      'routed section Sauce Base',
  'flank-steak-and-arugula-sandwiches-with-red-onion|4':
      'routed section Garlic-Soy Mayonnaise',
  'roast-beef-tenderloin|5': 'held generic',
  'pan-seared-oven-roasted-pork-tenderloin|4': 'held generic',
  'garlic-studded-roast-pork-loin|6':
      'routed section Mustard–Shallot Sauce with Thyme',
  'slow-roasted-bone-in-pork-rib-roast|4':
      'routed section Port Wine–Cherry Sauce',
  'roast-fresh-ham|12': 'held generic',
  'glazed-spiral-sliced-ham|2': 'held generic',
  'pan-seared-salmon|3': 'servedWith',
  'glazed-salmon|6': 'held generic',
  'oven-roasted-salmon|3': 'held generic',
  'pan-seared-sesame-crusted-tuna-steaks|4': 'held generic',
  'pan-roasted-halibut-steaks|3': 'held generic',
  'spanish-style-toasted-pasta-with-shrimp|16': 'routed section Aioli',
  'maryland-crab-cakes|10': 'servedWith',
  'best-old-fashioned-burgers|8': 'routed section Classic Burger Sauce',
  'juicy-pub-style-burgers|5': 'routed section Pub-Style Burger Sauce',
  'fresh-pasta-without-a-machine|4': 'held generic',
  'crisp-thin-crust-pizza|6': 'routed section Quick Tomato Sauce for Pizza',
  'the-best-gluten-free-pizza|0':
      'routed section The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
  'pepperoni-pan-pizza|7':
      'routed section Quick Tomato Sauce for Pizza of crisp-thin-crust-pizza',
  'grilled-tomato-and-cheese-pizza|11': 'routed section Spicy Garlic Oil',
  'lighter-chicken-parmesan|9': 'routed section Simple Tomato Sauce',
  'salade-lyonnaise|7': 'routed section Perfect Poached Eggs',
  'steak-diane|6': 'routed section Sauce Base for Steak Diane',
  'cheesy-nachos-with-guacamole-and-salsa|5': 'routed section One-Minute Salsa',
  'cheesy-nachos-with-guacamole-and-salsa|6': 'routed chunky-guacamole',
  'tamales|10': 'routed section Red Chile Chicken Filling',
  'shrimp-tempura|8': 'held missing',
  'beef-satay|8': 'routed section Spicy Peanut Dipping Sauce',
  'nasi-goreng-indonesian-style-fried-rice|10':
      'routed section Faux Leftover Rice',
  'thai-green-curry-with-chicken-broccoli-and-mushrooms|1':
      'routed section Green Curry Paste',
  'indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas|16':
      'servedWith',
  'indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas|17':
      'servedWith',
  'grilled-marinated-flank-steak|2': 'marinade',
  'grilled-steak-tips|0': 'marinade',
  'grill-roasted-beef-short-ribs|10': 'held generic',
  'easy-grilled-boneless-pork-chops|6': 'held generic',
  'grilled-pork-chops|3': 'routed section Basic Spice Rub for Pork Chops',
  'grilled-glazed-pork-tenderloin-roast|3': 'held generic',
  'grilled-stuffed-pork-tenderloin|3': 'held generic',
  'grill-roasted-bone-in-pork-rib-roast|4':
      'routed section Orange Salsa with Cuban Flavors',
  'barbecued-pulled-pork|1': 'routed section Dry Rub for Barbecue',
  'barbecued-pulled-pork|4': 'held generic',
  'memphis-style-barbecued-spareribs|0': 'routed section Spice Rub',
  'grilled-glazed-baby-back-ribs|2': 'held generic',
  'grilled-lamb-kebabs|0': 'marinade',
  'grilled-glazed-boneless-skinless-chicken-breasts|6': 'held generic',
  'grilled-glazed-bone-in-chicken-breasts|3': 'held generic',
  'best-grilled-chicken-thighs|2': 'held generic',
  'grilled-spice-rubbed-chicken-drumsticks|2': 'held generic',
  'grill-roasted-beer-can-chicken|3': 'routed section Spice Rub',
  'grill-roasted-cornish-game-hens|11': 'held generic',
  'grilled-shrimp-skewers|4': 'held generic',
  'grilled-corn-with-flavored-butter|0': 'held generic',
  'buffalo-cauliflower-bites|11': 'routed section Ranch Dressing',
  'red-beans-and-rice|14':
      'routed section Basic White Rice of fried-rice-with-shrimp-pork-and-shiitakes',
  'fluffy-omelets|4': 'held generic',
  'denver-omelets|6': 'routed section Filling for Denver Omelets',
  'spanish-tortilla-with-roasted-red-peppers-and-peas|8': 'servedWith',
  'quiche-lorraine|0':
      'routed section Basic Single-Crust Pie Dough of basic-double-crust-pie-dough',
  'gluten-free-chocolate-chip-cookies|0':
      'routed section The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend of the-best-gluten-free-pizza',
  'carrot-cake|12': 'routed section Cream Cheese Frosting',
  'spice-cake|16': 'routed section Cream Cheese Frosting of carrot-cake',
  'dark-chocolate-cupcakes|11': 'routed section Easy Vanilla Bean Buttercream',
  'bittersweet-chocolate-roulade|10':
      'routed section Espresso-Mascarpone Cream',
  'bittersweet-chocolate-roulade|11': 'routed section Dark Chocolate Ganache',
  'panna-cotta|6': 'routed section Raspberry Coulis',
  'pavlova-with-fruit-and-whipped-cream|7': 'held generic',
  'classic-apple-pie|0': 'routed all-butter-double-crust-pie-dough default',
  'deep-dish-apple-pie|0': 'routed all-butter-double-crust-pie-dough default',
  'blueberry-pie|0': 'routed all-butter-double-crust-pie-dough default',
  'summer-berry-pie|7': 'routed graham-cracker-crust',
  'sweet-cherry-pie|0': 'routed all-butter-double-crust-pie-dough default',
  'fresh-peach-pie|7': 'routed section Pie Dough for Lattice-Top Pie',
  'fresh-plum-ginger-pie-with-whole-wheat-lattice-top-crust|0':
      'routed foolproof-all-butter-dough-for-double-crust-pie for variation '
      'Foolproof Whole-Wheat Dough for Double-Crust Pie',
  'fresh-strawberry-pie|0':
      'routed section Foolproof Single-Crust Pie Dough of foolproof-double-crust-pie-dough',
  'pumpkin-pie|0':
      'routed section Basic Single-Crust Pie Dough of basic-double-crust-pie-dough',
  'pecan-pie|0':
      'routed section Basic Single-Crust Pie Dough of basic-double-crust-pie-dough',
  'key-lime-pie|3': 'routed graham-cracker-crust',
  'lemon-meringue-pie|0':
      'routed section Basic Single-Crust Pie Dough of basic-double-crust-pie-dough '
      'for variation Single-Crust Pie Dough for Custard Pies',
  'coconut-cream-pie|9': 'routed graham-cracker-crust',
  'chocolate-cream-pie-with-all-butter-crust|0':
      'routed foolproof-all-butter-dough-for-single-crust-pie',
  'lemon-tart|0': 'routed classic-tart-dough',
  'fresh-fruit-tart-with-pastry-cream|7': 'routed classic-tart-dough',
  'free-form-apple-tart|5': 'held missing',
  'peach-tarte-tatin|0':
      'routed foolproof-all-butter-dough-for-single-crust-pie',
  'skillet-roasted-broccoli|0': 'held generic',
  'pupusas-with-quick-salsa-and-curtido|6': 'routed section Quick Salsa',
  'pupusas-with-quick-salsa-and-curtido|7': 'routed section Curtido',
  'fresh-peach-pie-with-all-butter-lattice-top|7':
      'routed section Pie Dough for Lattice-Top Pie',
  'rose-sangria|4': 'routed section Simple Syrup',
  'roasted-fennel|5': 'held generic',
  'fresh-bulk-sausage|2': 'held generic',
  'fruit-hand-pies|6': 'held generic',
  'bruschetta-with-artichoke-hearts-and-parmesan|8':
      'routed section Toasted Bread for Bruschetta',
  'simple-cheese-quiche|0': 'held generic',
  'rainbow-cake|9': 'routed section Vanilla Frosting',
  'salted-caramel-apple-pie|0': 'held generic',
  'triple-berry-slab-pie-with-ginger-lemon-streusel|0':
      'routed section Slab Pie Dough',
  'chocolate-cherry-pie-pops|1': 'held generic',
  'nutella-tart|0': 'routed classic-tart-dough',
  'chraime|7': 'routed section Tabil',
  'boiled-potatoes-with-black-olive-tapenade|2':
      'routed section Black Olive Tapenade',
  'vegan-baja-style-cauliflower-tacos|14':
      'routed section Vegan Cilantro Sauce',
  'red-lentil-kibbeh|4': 'routed section Harissa',
};

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  void openDb() {
    tempDir = Directory.systemTemp.createTempSync('salt-v41-');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
    provider = FixtureProvider();
  }

  void closeDb() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  }

  /// Stores the corpus recipe [fileName] as the importer does.
  Recipe store(String fileName) {
    final recipe = loadCorpusRecipe(fileName);
    db.upsertRecipe(
      recipe,
      sourceSlug: _source,
      contentHash: contentHashOf(recipe),
    );
    return recipe;
  }

  Recipe stored(Recipe recipe) => db.recipeByIdOrSlug(recipe.id)!.recipe;

  Future<void> compute(Recipe recipe) async {
    expect(await matchAndCompute(db, provider, stored(recipe)), isNull);
  }

  /// v44: the section [key] computed as the sweep computes a child.
  Future<void> computeKey(String key) async {
    expect(
      await matchAndCompute(db, provider, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }

  IngredientMatchRow rowAt(Recipe recipe, int position) => db
      .ingredientMatchesFor(recipe.id)
      .singleWhere((row) => row.position == position);

  IngredientLine lineAt(Recipe recipe, int position) =>
      nutritionLines(stored(recipe))[position];

  RecipeNutritionRow label(Recipe recipe) => db.nutritionFor(recipe.id)!;

  bool fresh(Recipe recipe) => nutritionIsFresh(db, stored(recipe));

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  /// The bucket parity (one rule, Dart and SQL): every row's
  /// [matchBucketFor] counted, against the queue's SQL counts — v44: a
  /// section's rows too (the counts read every row, keys included).
  void parity() {
    final dart = <String, int>{};
    for (final id in db.recipesWithMatches()) {
      for (final row in db.ingredientMatchesFor(id)) {
        dart.update(bucketOf(row).wire, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    expect(db.nutritionReviewCounts(), dart);
  }

  int calls() => provider.searchCalls + provider.foodCalls;

  /// ONE bulk sweep of [scope], run to its end.
  Future<void> sweep(BulkScope scope) async {
    final job = startBulkJob(db, provider, scope: scope);
    expect(job, isNotNull);
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(db.nutritionJob(job!)!['status'], 'done');
  }

  /// A recipe pick as step 3's PUT stores it (A1 b: the row only, never
  /// `ingredient_decisions`): [parent]'s line at [position] decided
  /// `overridden` on [child] at [share] (the line's own when null).
  void pick(Recipe parent, int position, Recipe child, {double? share}) {
    final at = rowAt(parent, position);
    db.upsertIngredientMatch(
      at.copyWith(
        status: 'overridden',
        childRecipeId: child.id,
        childShare:
            share ??
            parseShare(
              lineAt(parent, position).raw,
              lineAt(parent, position).amounts,
              stored(child).servings,
            ),
        gramSource: SaltDatabase.recipeGramSource,
        clearHold: true,
        clearChildStamp: true,
        clearDerivedSeq: true,
      ),
    );
  }

  /// The kcal a routed row adds to its recipe's batch: its child's batch
  /// energy x its share.
  double childKcal(IngredientMatchRow row) =>
      batchTotalsOf(db.nutritionFor(row.childRecipeId!)!)['energy']! *
      row.childShare!;

  /// The recipe's whole-batch energy as its label stores it.
  double batchKcal(Recipe recipe) => batchTotalsOf(label(recipe))['energy']!;

  group('the share parser (real lines, real yields)', skip: skipIfNoCorpus, () {
    double? shareOf(String fileName, int position, {String? servings}) {
      final recipe = loadCorpusRecipe(fileName);
      final line = nutritionLines(recipe)[position];
      final sub = recipe.subsections.firstWhere(
        (s) => (line.item ?? '').toLowerCase().contains(
          (s.title ?? '\u0000').toLowerCase().split(' ').first,
        ),
      );
      return parseShare(line.raw, line.amounts, servings ?? sub.servings);
    }

    test('"1 recipe" is 1; a written "(½ recipe" wins', () {
      final pie = loadCorpusRecipe(_blueberry);
      final dough = nutritionLines(pie)[0];
      expect(dough.raw, '1 recipe double-crust pie dough');
      expect(parseShare(dough.raw, dough.amounts, null), 1);
      final herb = nutritionLines(loadCorpusRecipe(_herbSauce))[3];
      expect(herb.raw, '¼ cup Sauce Base (½ recipe; recipe follows)');
      // M11 is equivalent on this line (¼ cup of MAKES ½ CUP is ½ too):
      // the written share is pinned against a yield it does not fit.
      expect(parseShare(herb.raw, herb.amounts, 'MAKES 2 CUPS'), 0.5);
      expect(parseShare(herb.raw, herb.amounts, 'MAKES ½ CUP'), 0.5);
    });

    test('an amount over the child yield, in one unit family', () {
      expect(
        shareOf('0383-crisp-thin-crust-pizza.yaml', 6),
        closeTo(2 / 3, 1e-9),
      );
      expect(shareOf('1136-rose-sangria.yaml', 4), closeTo(0.5, 1e-9));
      expect(shareOf('1208-chraime.yaml', 7), closeTo(1 / 8, 1e-6));
      expect(shareOf('1201-rainbow-cake.yaml', 9), closeTo(2, 1e-9));
      expect(
        shareOf('0393-the-best-gluten-free-pizza.yaml', 0),
        closeTo(16 / 42, 1e-6),
      );
      // "1 recipe" over a yield that is a count of pizzas: the recipe unit.
      expect(shareOf('0396-grilled-tomato-and-cheese-pizza.yaml', 11), 1);
      // "1 cup" over that same yield: no share reads.
      final sauce = nutritionLines(
        loadCorpusRecipe('0383-crisp-thin-crust-pizza.yaml'),
      )[6];
      expect(
        parseShare(sauce.raw, sauce.amounts, 'MAKES ENOUGH FOR 4 PIZZAS'),
        isNull,
      );
      // A weight never divides a volume yield: Rosé Sangria's "4 ounces
      // Simple Syrup" over the pizza sauce's "MAKES ABOUT 1½ CUPS".
      final syrup = nutritionLines(
        loadCorpusRecipe('1136-rose-sangria.yaml'),
      )[4];
      expect(
        parseShare(syrup.raw, syrup.amounts, 'MAKES ABOUT 1½ CUPS'),
        isNull,
      );
      // A yield range reads its upper bound (the standing range ruling):
      // chunky guacamole "MAKES 2½ TO 3 CUPS", 1 cup of it is ⅓.
      expect(
        parseShare(sauce.raw, sauce.amounts, 'MAKES 2½ TO 3 CUPS'),
        closeTo(1 / 3, 1e-9),
      );
    });
  });

  group('the resolver over the whole library', skip: skipIfNoCorpus, () {
    setUpAll(() {
      openDb();
      for (final file in Directory(corpusRecipesDir).listSync()) {
        if (file is File && file.path.endsWith('.yaml')) {
          final recipe = RecipeYamlCodec.decode(
            file.readAsStringSync(),
          ).recipe;
          db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
        }
      }
    });
    tearDownAll(closeDb);

    test('every reference line the detector zeroes resolves as ruled', () {
      final memo = ResolverMemo(db);
      resolverIndexReads = 0;
      final got = <String, String>{};
      for (final id in db.allRecipeIds()) {
        final recipe = db.recipeByIdOrSlug(id)!.recipe;
        for (final (position, line) in nutritionLines(recipe).indexed) {
          if (subRecipeRowFor(recipe, position, line) == null) {
            continue;
          }
          final found = resolveReference(db, recipe, line, memo);
          final variation = switch (found.variation) {
            (:final title, host: _) => ' for variation $title',
            null => '',
          };
          got['${recipe.slug}|$position'] =
              '${switch (found.kind) {
                // v44: a section routes as a child of its own (the key).
                ReferenceKind.routed when found.section != null => 'routed section ${found.section!.title}'
                    '${found.section!.host == recipe.id ? '' : ' of '
                              '${db.recipeByIdOrSlug(found.section!.host)!.recipe.slug}'}',
                ReferenceKind.routed => 'routed ${db.recipeByIdOrSlug(found.childId!)!.recipe.slug}'
                    '${found.named >= 2 ? ' default' : ''}',
                ReferenceKind.section when found.noIngredients => 'section no_ingredients',
                ReferenceKind.held => 'held ${found.missing ? 'missing' : 'generic'}',
                final kind => kind.name,
              }}$variation';
        }
      }
      expect(got, _resolved);
      // The library's titles and sections: two statements for 122 lines
      // (v44: the three A9 lines join).
      expect(resolverIndexReads, 2);
    });

    test('similar titles: whole words, fewest extra, at most 5 [F12]', () {
      final memo = ResolverMemo(db);
      List<String> similar(String slug, int position) {
        final recipe = db.recipeByIdOrSlug(slug)!.recipe;
        final item = referenceItemOf(nutritionLines(recipe)[position]);
        return [for (final t in similarTitles(recipe, item, memo)) t.title];
      }

      expect(similar('blueberry-pie', 0), [
        'Foolproof All-Butter Dough for Double-Crust Pie',
      ]);
      expect(similar('roast-fresh-ham', 12), [
        'Spiced Pecans with Rum Glaze',
        'Grilled Pork Kebabs with Hoisin Glaze',
        'Meatloaf with Brown Sugar–Ketchup Glaze',
        'Campanelle with Asparagus, Basil, and Balsamic Glaze',
        'Turkey Meatloaf with Ketchup–Brown Sugar Glaze',
      ]);
      // 55 library titles hold "sauce" (snapshot 17): the cap keeps the five
      // with the fewest extra words (1, 2, 2, 2, 3).
      expect(similar('grilled-shrimp-skewers', 4), [
        'Marinara Sauce',
        'Classic Cranberry Sauce',
        'Jellied Cranberry Sauce',
        'Quick Tomato Sauce',
        'Dark Chocolate Fudge Sauce',
      ]);
    });

    test('the three unmarked own-section references are no trip [A9]', () {
      for (final (slug, position) in [
        ('vegan-baja-style-cauliflower-tacos', 14),
        ('boiled-potatoes-with-black-olive-tapenade', 2),
        ('red-lentil-kibbeh', 4),
      ]) {
        final line = nutritionLines(
          db.recipeByIdOrSlug(slug)!.recipe,
        )[position];
        expect(isSubRecipeReference(line.raw), isFalse, reason: line.raw);
      }
    });

    test('A10 a: the food alternative carries an amount, or is none', () {
      String? alternative(String slug, int position) => foodAlternativeOf(
        nutritionLines(db.recipeByIdOrSlug(slug)!.recipe)[position],
      )?.raw;
      expect(
        alternative('thai-green-curry-with-chicken-broccoli-and-mushrooms', 1),
        '2 tablespoons store-bought green curry paste',
      );
      expect(alternative('grilled-pork-chops', 3), '2 teaspoons pepper');
      expect(
        alternative(
          'crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing',
          4,
        ),
        startsWith('18 cups 1-inch challah'),
      );
      expect(alternative('pan-seared-salmon', 3), isNull);
      expect(alternative('maryland-crab-cakes', 10), isNull);
      // A food offered FIRST is no reference: its row is that food.
      expect(alternative('blueberry-pie', 0), isNull);
    });
  });

  group('the composite rows a compute writes', skip: skipIfNoCorpus, () {
    final recipes = <String, Recipe>{};
    Recipe r(String fileName) => recipes[fileName]!;

    setUpAll(() async {
      openDb();
      for (final file in Directory(corpusRecipesDir).listSync()) {
        if (file is File && file.path.endsWith('.yaml')) {
          final recipe = RecipeYamlCodec.decode(
            file.readAsStringSync(),
          ).recipe;
          db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
          recipes[file.uri.pathSegments.last] = recipe;
        }
      }
      // Children first (the bulk order, parents last); the deli-ham line
      // caches the one answer that holds 168322, the cooked bacon (B1).
      for (final file in [
        _deliHam,
        _allButter,
        _basic,
        _graham,
        _tartDough,
        _single,
        _guacamole,
        _blueberry,
        _deepDish,
        _summerBerry,
        _keyLime,
        _coconut,
        _nachos,
        _freeForm,
        _steakTips,
        _thai,
        _porkChops,
        _wilted,
        _tenderloin,
        _herbSauce,
        _lemonTart,
        _fruitTart,
      ]) {
        // v44: a recipe's child sections first, as the bulk order runs
        // them (nachos' One-Minute Salsa, the Green Curry Paste).
        for (final key in sectionChildKeysOf(
          db,
          stored(r(file)),
          ResolverMemo(db),
        )) {
          expect(
            await matchAndCompute(
              db,
              provider,
              nutritionRecipeOf(db, key)!.recipe,
            ),
            isNull,
          );
        }
        await compute(r(file));
      }
    });
    tearDownAll(closeDb);

    test('R1: each routed line counts its child × 1 [7.1]', () {
      for (final (file, position, child, grams, kcal, perServing, status) in [
        (_blueberry, 0, _allButter, 642.9, 3056.69, 571.51, 'complete'),
        // v43 (Y8): its two apple lines × 0.78 (AH-102 item 17).
        (_deepDish, 0, _allButter, 642.9, 3056.69, 597.13, 'complete'),
        (_summerBerry, 7, _graham, 220.6, 1135.14, 273.62, 'complete'),
        // RE-PIN (M47 batch, v49 Q6): its 4 tsp lime zest plus ½ cup juice
        // counts, two parts (was 445.87, partial).
        (_keyLime, 3, _graham, 220.6, 1135.14, 450.14, 'complete'),
        (_coconut, 9, _graham, 220.6, 1135.14, 598.27, 'complete'),
        // v44: its |5 now routes to its own One-Minute Salsa (+23.00).
        (_nachos, 6, _guacamole, 522.5, 1032.78, 1098.56, 'complete'),
        // RE-PIN (M47 batch, v49): the lemon tart's strained zest line counts
        // its juice (Q6; was 399.33), the fruit tart's kiwis 150 g (Q12; was
        // 547.59, partial).
        (_lemonTart, 0, _tartDough, 401.8, 1870.07, 403.79, 'partial'),
        (_fruitTart, 7, _tartDough, 401.8, 1870.07, 559.79, 'complete'),
      ]) {
        final parent = r(file);
        final row = rowAt(parent, position);
        final reason = '${parent.slug}|$position';
        expect(row.childRecipeId, r(child).id, reason: reason);
        expect(row.childShare, 1, reason: reason);
        expect(row.grams, closeTo(grams, 0.05), reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.fdcId, isNull, reason: reason);
        expect(row.description, isNull, reason: reason);
        expect(row.gramSource, 'recipe', reason: reason);
        expect(row.hold, isNull, reason: reason);
        expect(row.childStamp, label(r(child)).computedAt, reason: reason);
        expect(bucketOf(row), MatchBucket.counted, reason: reason);
        expect(childKcal(row), closeTo(kcal, 0.05), reason: reason);
        expect(
          label(parent).caloriesPerServing,
          closeTo(perServing, 0.005),
          reason: reason,
        );
        expect(label(parent).status, status, reason: reason);
        expect(fresh(parent), isTrue, reason: reason);
      }
      final blueberry = r(_blueberry);
      final line = lineAt(blueberry, 0);
      final row = rowAt(blueberry, 0);
      expect(
        gramBasisFor(db, line, row, recipe: stored(blueberry)),
        'from the recipe All-Butter Double-Crust Pie Dough: 643 g, 3,057 kcal',
      );
      expect(
        compositeFlagOf(db, stored(blueberry), line, row, ResolverMemo(db)),
        'approximation (the first dough the note names: All-Butter '
        'Double-Crust Pie Dough)',
      );
      // An exact title is no default: no flag.
      expect(
        compositeFlagOf(
          db,
          stored(r(_summerBerry)),
          lineAt(r(_summerBerry), 7),
          rowAt(r(_summerBerry), 7),
          ResolverMemo(db),
        ),
        isNull,
      );
    });

    test('R1: the other routes, as the compute would write them [7.1]', () {
      final memo = ResolverMemo(db);
      // parent_kind (A4, F12): the title's last word when pie, tart or
      // quiche, else recipe — never "crust" (verify3 D3).
      for (final (slug, position, child, grams, flagged, parentKind) in [
        ('classic-apple-pie', 0, _allButter, 642.9, true, 'pie'),
        ('sweet-cherry-pie', 0, _allButter, 642.9, true, 'pie'),
        (
          'chocolate-cream-pie-with-all-butter-crust',
          0,
          _single,
          334.6,
          false,
          'recipe',
        ),
        // D2: its note names ONE dough — routed, unflagged.
        ('peach-tarte-tatin', 0, _single, 334.6, false, 'recipe'),
        ('nutella-tart', 0, _tartDough, 401.8, false, 'tart'),
      ]) {
        final parent = db.recipeByIdOrSlug(slug)!.recipe;
        final line = nutritionLines(parent)[position];
        final row = referenceRowFor(db, parent, position, line, memo);
        expect(row.childRecipeId, r(child).id, reason: slug);
        expect(row.grams, closeTo(grams, 0.05), reason: slug);
        expect(row.status, 'auto', reason: slug);
        expect(
          compositeFlagOf(db, parent, line, row, memo) != null,
          flagged,
          reason: slug,
        );
        expect(
          referenceChildJson(
            db,
            parent,
            position,
            line,
            row,
            memo,
          )!['parent_kind'],
          parentKind,
          reason: slug,
        );
      }
    });

    test('held: no library title (missing), a marinade [7.2, A5]', () {
      final tart = r(_freeForm);
      final held = rowAt(tart, 5);
      expect(held.raw, startsWith('1 recipe Rustic Tart Dough (this page)'));
      expect(held.hold, 'choose_recipe');
      expect(held.status, 'auto');
      expect(held.grams, 0);
      expect(held.gramSource, 'recipe');
      expect(held.childRecipeId, isNull);
      expect(held.childStamp, isNull);
      expect(bucketOf(held), MatchBucket.chooseRecipe);
      expect(label(tart).status, 'partial');
      expect(label(tart).matchedCount, 5);
      // v43 (Y8): its two peeled, cored apple pounds × 0.78 (AH-102 item 17).
      expect(label(tart).caloriesPerServing, closeTo(143.11, 0.005));
      expect(fresh(tart), isTrue);

      final tips = r(_steakTips);
      final marinade = rowAt(tips, 0);
      expect(marinade.raw, '1 recipe marinade (recipes follow)');
      expect(marinade.hold, 'discarded_recipe');
      expect(marinade.status, 'auto');
      expect(marinade.description, isNull);
      expect(bucketOf(marinade), MatchBucket.check);
      expect(label(tips).status, 'partial');
      expect(label(tips).matchedCount, 2);
      expect(fresh(tips), isTrue);
    });

    // RE-PIN (M51 batch, v52, design_v2 Q8b — re-rules prep41 A3 (a) for a
    // dish served with): the herb sauce's D7 row is ACCOUNTED, its label
    // complete 10/10 (was "R3: a reference rule row makes its label
    // partial", 9 of 10). No corpus line keeps a not-routed row that is not
    // served with (nutrition_v52_test; the mockup's "none in the library").
    test('R3 (v52): a served-with rule row is accounted — its label '
        'complete [7.6, A3, Q8b]', () {
      for (final (file, position, matched, total, perServing) in [
        // v44: a section of its own routes (thai|1, nachos|5 — pinned in
        // nutrition_v44_sections_test.dart); served with, not made from
        // (D7) stays the rule row although exact.
        // v44: its |3 "¼ cup Sauce Base (½ recipe; recipe follows)" routes
        // to its own section at ½ (8 → 9 matched; 51.71 → 207.91).
        // RE-PIN (M50 batch, v50, Q16): the Sauce Base strains out its
        // onion, carrot, mushrooms, garlic, ground beef, bay and peppercorns
        // (2,042.50 → 1,456.70 g; the parent row 1,021.25 → 728.35 g,
        // −306.27 kcal a batch): 207.91 → 131.34 a serving (P1 R12's 131.3).
        // RE-PIN (Q25 batch, v54, design_q25_v2 R12): the Sauce Base's 2
        // cups red wine simmer 20 + 5 = 25 min → USDA 5004 40 % of its
        // ethanol kept (347.96 kcal; −208.78 for the section), the parent
        // reading ½ of it: −104.39 a batch, 131.34 → 105.24 a serving.
        (_herbSauce, 0, 10, 10, 105.24),
      ]) {
        final recipe = r(file);
        final row = rowAt(recipe, position);
        expect(isEngineRuleRow(row), isTrue, reason: row.raw);
        expect(row.description, subRecipeNote);
        expect(row.grams, 0);
        expect(bucketOf(row), MatchBucket.counted, reason: row.raw);
        expect(label(recipe).status, 'complete', reason: recipe.slug);
        expect(label(recipe).matchedCount, matched, reason: recipe.slug);
        expect(label(recipe).totalCount, total, reason: recipe.slug);
        expect(
          label(recipe).caloriesPerServing,
          closeTo(perServing, 0.005),
          reason: recipe.slug,
        );
        expect(fresh(recipe), isTrue, reason: recipe.slug);
      }
    });

    test('R2: rendered bacon, one row with two parts [7.7]', () {
      final salad = r(_wilted);
      final bacon = rowAt(salad, 5);
      expect(
        bacon.raw,
        '10 ounces (about 8 slices) thick-cut bacon, cut into ½-inch pieces',
      );
      expect(bacon.fdcId, 168277);
      expect(bacon.status, 'auto');
      // RE-PIN (M49 batch, v51): 283.495 × 0.33 (AH-102 item 1981) = 93.55
      // + the stated 3 tablespoons 38.70 (was 114.25 + 38.70 = 152.95).
      expect(bacon.grams, closeTo(132.25, 1e-9));
      expect(partsOf(bacon.parts), [
        (fdcId: 168322, grams: 93.55),
        (fdcId: 172345, grams: 38.7),
      ]);
      expect(bucketOf(bacon), MatchBucket.counted);
      final line = lineAt(salad, 5);
      expect(
        gramBasisFor(db, line, bacon, recipe: stored(salad)),
        '284 g raw → 94 g cooked bacon + 39 g bacon grease kept in the pan',
      );
      expect(
        compositeFlagOf(db, stored(salad), line, bacon, ResolverMemo(db)),
        baconYieldFlag,
      );
      expect(baconYieldFlag, _ah102Flag);
      expect(label(salad).status, 'complete');
      // RE-PIN (M49 batch, v51): the v51 replay's 277.44 (was 301.66).
      expect(label(salad).caloriesPerServing, closeTo(277.44, 0.005));
      // Its "3 hard-cooked eggs (recipe follows)": counted on its food, as
      // in v40 (a count of the food itself — no route).
      final eggs = rowAt(salad, 8);
      expect(eggs.fdcId, isNotNull);
      expect(eggs.grams, closeTo(150, 1e-9));
      expect(eggs.childRecipeId, isNull);
    });

    test('only a rendered bacon row carries parts: the record gate [B1]', () {
      final withParts = [
        for (final id in db.allRecipeIds())
          for (final row in db.ingredientMatchesFor(id))
            if (row.parts != null) '${row.recipeId}|${row.position}',
      ];
      // RE-PIN (M47 batch, v49 Q6): a zest-plus-juice row carries its two
      // parts too ([withParts]); only the bacon row is rendered.
      expect(withParts, ['${r(_wilted).id}|5', '${r(_keyLime).id}|1']);
    });

    test('every computed recipe is fresh; the buckets agree [§3, parity]', () {
      for (final recipe in recipes.values) {
        if (db.nutritionFor(recipe.id) != null) {
          expect(fresh(recipe), isTrue, reason: recipe.slug);
        }
      }
      parity();
    });

    test(
      'cost: the library index at most twice per compute, no FDC [F14]',
      () async {
        final before = calls();
        resolverIndexReads = 0;
        await compute(r(_blueberry));
        expect(resolverIndexReads, lessThanOrEqualTo(2));
        resolverIndexReads = 0;
        await compute(r(_allButter)); // holds no reference: no index read
        expect(resolverIndexReads, 0);
        // One matches GET of the routed recipe reads no FDC either.
        await matchesBody(db, provider, stored(r(_blueberry)));
        expect(calls(), before);
      },
    );

    test(
      'rule B1: the 13 trips and the non-trips, on their v40 rows [7.7]',
      () {
        IngredientMatchRow v40(
          String slug,
          int position,
          double grams,
          String source, {
          int fdcId = 168277,
          String status = 'auto',
        }) {
          final line = nutritionLines(
            db.recipeByIdOrSlug(slug)!.recipe,
          )[position];
          return IngredientMatchRow(
            recipeId: db.recipeByIdOrSlug(slug)!.recipe.id,
            position: position,
            raw: line.raw,
            fdcId: fdcId,
            description: null,
            dataType: 'SR Legacy',
            confidence: 1,
            grams: grams,
            gramSource: source,
            status: status,
          );
        }

        IngredientMatchRow rendered(IngredientMatchRow row) {
          final recipe = db.recipeByIdOrSlug(row.recipeId)!.recipe;
          return withRenderedBacon(
            recipe,
            nutritionLines(recipe)[row.position],
            row,
          );
        }

        // Snapshot 17's rows (v40_rows.tsv): raw grams → cooked + kept.
        // RE-PIN (M49 batch, v51): the same v40 raw grams at AH-102 item
        // 1981's 0.33 and 0.2555 g rendered a raw gram; the three pans an
        // oil shares (P4 §4) keep R / (R + O) of the stated amount —
        // pasta-with-tomato 15.87 (was 25.80), lyonnaise 14.73 (25.80),
        // gricia 55.72 (52.14, the ⅓ cup now below R + O); the tart's
        // stated ¼ cup above its rendered 49.06.
        for (final (slug, position, raw, source, cooked, kept) in [
          (
            'wilted-spinach-salad-with-warm-bacon-dressing',
            5,
            283.50,
            'weight',
            93.56,
            38.70,
          ),
          (
            'pasta-with-tomato-bacon-and-onion',
            1,
            170.10,
            'weight',
            56.13,
            15.87,
          ),
          // kept ≥ rendered: the rendered fat (B7's min).
          (
            'pasta-alla-gricia-rigatoni-with-pancetta-and-pecorino-romano',
            0,
            226.80,
            'weight',
            74.84,
            55.72,
          ),
          ('beef-braised-in-barolo', 2, 113.40, 'weight', 37.42, 25.80),
          // "leaving pancetta in skillet"; 5 ounces as weighed (141.7475 g).
          ('salade-lyonnaise', 0, 5 * 28.3495, 'weight', 46.78, 14.73),
          ('french-onion-and-bacon-tart', 5, 113.40, 'weight', 37.42, 25.80),
          (
            'potato-casserole-with-bacon-and-caramelized-onion',
            0,
            72.00,
            'piece',
            23.76,
            12.90,
          ),
          (
            'simplified-cassoulet-with-pork-and-kielbasa',
            8,
            170.10,
            'weight',
            56.13,
            25.80,
          ),
          (
            'braised-greens-with-bacon-and-onion',
            0,
            144.00,
            'piece',
            47.52,
            25.80,
          ),
          // "discard all but 2 teaspoons": teaspoons, not tablespoons.
          (
            'scrambled-eggs-with-bacon-onion-and-pepper-jack-cheese',
            4,
            113.40,
            'weight',
            37.42,
            8.60,
          ),
          (
            'tartiflette-french-potato-and-cheese-gratin',
            2,
            144.00,
            'piece',
            47.52,
            25.80,
          ),
          // "Measure out and reserve ¼ cup fat; discard remaining fat" trips.
          (
            'caramelized-onion-pear-and-bacon-tart',
            0,
            192.00,
            'piece',
            63.36,
            49.06,
          ),
          (
            'rigatoni-with-tomatoes-bacon-and-fennel',
            0,
            144.00,
            'piece',
            47.52,
            25.80,
          ),
        ]) {
          final row = rendered(v40(slug, position, raw, source));
          expect(partsOf(row.parts), [
            (fdcId: 168322, grams: cooked),
            (fdcId: 172345, grams: kept),
          ], reason: slug);
          expect(
            row.grams,
            closeTo(cooked + kept, 1e-9),
            reason: '$slug: the row counts the sum',
          );
        }
        // Non-trips, each for the reason its text shows.
        for (final (slug, position, raw, source) in [
          ('smothered-pork-chops', 0, 85.05, 'weight'), // fat kept in the pan
          ('chili-con-carne', 7, 226.80, 'weight'), // "into a small bowl"
          ('erbazzone-swiss-chard-pie', 5, 85.05, 'weight'), // "divided"
          ('coq-au-vin', 0, 170.10, 'weight'), // pour-off in another step
          ('quiche-lorraine', 1, 226.80, 'weight'), // moved out, fat kept
          ('oven-fried-bacon', 0, 288.00, 'piece'), // no steps
          ('foolproof-spaghetti-carbonara', 0, 192.00, 'piece'),
        ]) {
          final row = rendered(v40(slug, position, raw, source));
          expect(row.parts, isNull, reason: slug);
          expect(row.grams, raw, reason: slug);
        }
        // RE-PIN (M60 batch, v59): the scallops' bacon, wrapped round them
        // and grilled, drips (P7b): B1's cooked part, no fat kept.
        expect(
          partsOf(
            rendered(
              v40('grilled-bacon-wrapped-scallops', 0, 288, 'piece'),
            ).parts,
          ),
          [(fdcId: 168322, grams: 95.04), (fdcId: 172345, grams: 0.0)],
        );
        // The record gate: salt pork (168287) never renders.
        expect(
          rendered(
            v40('pasta-allamatriciana', 0, 226.80, 'weight', fdcId: 168287),
          ).parts,
          isNull,
        );
        // D12: a Confirm keeps the parts; a pick (`overridden`) and typed
        // grams (`override`) are one record.
        const salad = 'wilted-spinach-salad-with-warm-bacon-dressing';
        expect(
          rendered(v40(salad, 5, 283.5, 'weight', status: 'confirmed')).parts,
          isNotNull,
        );
        expect(
          rendered(v40(salad, 5, 283.5, 'weight', status: 'overridden')).parts,
          isNull,
        );
        expect(
          rendered(v40(salad, 5, 200, 'override', status: 'confirmed')).parts,
          isNull,
        );
      },
    );
  });

  group('decisions on a composite row', skip: skipIfNoCorpus, () {
    setUp(openDb);
    tearDown(closeDb);

    Map<String, Object?> matchOf(Map<String, Object?> body, int position) =>
        ((body['items']! as List<Object?>)[position]!
                as Map<String, Object?>)['match']!
            as Map<String, Object?>;

    test('[F1] a Confirm keeps the child; a pick counts another', () async {
      final allButter = store(_allButter);
      final basic = store(_basic);
      store(_foolproofDouble); // the note's third dough (named, not computed)
      final blueberry = store(_blueberry);
      final deepDish = store(_deepDish);
      for (final recipe in [allButter, basic, blueberry, deepDish]) {
        await compute(recipe);
      }
      final kcal = label(blueberry).caloriesPerServing;
      final line = lineAt(blueberry, 0);
      await applyMatchOverride(db, provider, stored(blueberry), 0, {
        'raw': line.raw,
        'confirmed': true,
      });
      void confirmed() {
        final row = rowAt(blueberry, 0);
        expect(row.status, 'confirmed');
        expect(row.childRecipeId, allButter.id);
        expect(row.grams, closeTo(642.9, 0.05));
        expect(row.gramSource, 'recipe');
        expect(bucketOf(row), MatchBucket.counted);
        // D6: a person's decision clears the default flag.
        expect(
          compositeFlagOf(db, stored(blueberry), line, row, ResolverMemo(db)),
          isNull,
        );
        expect(label(blueberry).caloriesPerServing, closeTo(kcal!, 0.005));
        expect(fresh(blueberry), isTrue);
      }

      confirmed();
      final match = matchOf(
        await matchesBody(db, provider, stored(blueberry)),
        0,
      );
      expect(match['grams'], closeTo(642.9, 0.05));
      expect(match['gram_source'], 'recipe');
      expect(match['status'], 'confirmed');
      await compute(blueberry); // the next compute keeps it
      confirmed();
      // A1 (b): a recipe decision is never recorded library-wide.
      expect(db.decisionFor(lineKeyOf(line)), isNull);

      // A pick of Basic Double-Crust on deep-dish-apple-pie|0.
      pick(deepDish, 0, basic);
      await compute(deepDish);
      final picked = rowAt(deepDish, 0);
      expect(picked.status, 'overridden');
      expect(picked.childRecipeId, basic.id);
      expect(picked.grams, closeTo(label(basic).totalGrams!, 1e-9));
      expect(childKcal(picked), closeTo(3519.96, 0.05));
      expect(label(deepDish).status, 'complete');
      expect(fresh(deepDish), isTrue);
      parity();
    });

    test('[F2] typed grams on a rendered row: one record, no parts', () async {
      store(_deliHam);
      final salad = store(_wilted);
      await compute(loadCorpusRecipe(_deliHam));
      await compute(salad);
      expect(rowAt(salad, 5).parts, isNotNull);
      await applyMatchOverride(db, provider, stored(salad), 5, {
        'raw': lineAt(salad, 5).raw,
        'grams': 200,
      });
      final row = rowAt(salad, 5);
      expect(row.fdcId, 168277);
      expect(row.grams, 200);
      expect(row.gramSource, 'override');
      expect(row.parts, isNull);
      expect(
        compositeFlagOf(
          db,
          stored(salad),
          lineAt(salad, 5),
          row,
          ResolverMemo(db),
        ),
        isNull,
      );
      expect(bucketOf(row), MatchBucket.counted);
      await compute(salad);
      expect(rowAt(salad, 5).parts, isNull);
      expect(fresh(salad), isTrue);
    });

    test("[A6] a Confirm keeps a rendered row's parts and flag", () async {
      store(_deliHam);
      final salad = store(_wilted);
      await compute(loadCorpusRecipe(_deliHam));
      await compute(salad);
      String? flag() => compositeFlagOf(
        db,
        stored(salad),
        lineAt(salad, 5),
        rowAt(salad, 5),
        ResolverMemo(db),
      );
      // RE-PIN (M49 batch, v51): the AH-102 item 1981 flag.
      const rendered = _ah102Flag;
      expect(rowAt(salad, 5).status, 'auto');
      expect(flag(), rendered);
      await applyMatchOverride(db, provider, stored(salad), 5, {
        'raw': lineAt(salad, 5).raw,
        'confirmed': true,
      });
      for (final pass in ['the Confirm', 'the next compute']) {
        final row = rowAt(salad, 5);
        expect(row.status, 'confirmed', reason: pass);
        expect(row.parts, isNotNull, reason: pass);
        // A6: the flag names a fact about the row, not the engine's guess.
        expect(flag(), rendered, reason: pass);
        await compute(salad);
      }
      expect(fresh(salad), isTrue);
    });

    test('[F5] a nested pick is held, out of the totals', () async {
      final herb = store(_herbSauce);
      final tenderloin = store(_tenderloin);
      await compute(herb);
      await compute(tenderloin);
      final before = label(tenderloin);
      pick(tenderloin, 4, herb, share: 1);
      await compute(tenderloin);
      final row = rowAt(tenderloin, 4);
      expect(row.raw, startsWith('1 recipe pan sauce'));
      expect(row.status, 'overridden');
      expect(row.hold, 'nested_recipe');
      expect(row.grams, 0);
      expect(row.childRecipeId, herb.id);
      expect(row.childStamp, label(herb).computedAt);
      expect(bucketOf(row), MatchBucket.chooseRecipe);
      expect(label(tenderloin).status, 'partial');
      expect(
        label(tenderloin).caloriesPerServing,
        closeTo(before.caloriesPerServing!, 0.005),
      );
      expect(label(tenderloin).matchedCount, before.matchedCount);
      expect(fresh(tenderloin), isTrue);
      parity();
    });

    test('[F6, N6] a child deleted: held missing, fresh after ONE sweep; '
        're-imported, routed again', () async {
      final crust = store(_graham);
      final parents = [store(_summerBerry), store(_keyLime), store(_coconut)];
      const at = {_summerBerry: 7, _keyLime: 3, _coconut: 9};
      final files = [_summerBerry, _keyLime, _coconut];
      await compute(crust);
      for (final parent in parents) {
        await compute(parent);
      }
      // A person's Confirm on summer-berry-pie|7 first.
      final summer = parents.first;
      await applyMatchOverride(db, provider, stored(summer), 7, {
        'raw': lineAt(summer, 7).raw,
        'confirmed': true,
      });
      expect(fresh(summer), isTrue);
      final before = calls();
      deleteRecipe(db, config, crust.id);
      for (final parent in parents) {
        expect(fresh(parent), isFalse, reason: parent.slug); // the arm
      }
      await sweep(BulkScope.stale);
      for (final (i, parent) in parents.indexed) {
        final row = rowAt(parent, at[files[i]]!);
        expect(row.hold, 'choose_recipe', reason: parent.slug);
        expect(row.grams, 0, reason: parent.slug);
        expect(bucketOf(row), MatchBucket.chooseRecipe, reason: parent.slug);
        expect(label(parent).status, 'partial', reason: parent.slug);
        expect(fresh(parent), isTrue, reason: parent.slug);
      }
      final decided = rowAt(summer, 7);
      expect(decided.status, 'confirmed');
      expect(decided.childStamp, isNull); // N6
      expect(decided.childRecipeId, crust.id); // kept: ids survive
      expect(calls(), before);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      parity();

      // The crust re-imported from the corpus (same id), one `all` sweep.
      store(_graham);
      await sweep(BulkScope.all);
      final again = rowAt(summer, 7);
      expect(again.status, 'confirmed');
      expect(again.hold, isNull);
      expect(again.grams, closeTo(220.6, 0.05));
      expect(again.childStamp, label(crust).computedAt);
      for (final (i, parent) in parents.indexed.skip(1)) {
        final row = rowAt(parent, at[files[i]]!);
        expect(row.status, 'auto', reason: parent.slug);
        expect(row.childRecipeId, crust.id, reason: parent.slug);
        expect(row.hold, isNull, reason: parent.slug);
      }
      for (final parent in parents) {
        expect(fresh(parent), isTrue, reason: parent.slug);
      }
    });

    test('[N1] a saved share re-derives and re-stamps', () async {
      final allButter = store(_allButter);
      store(_basic);
      store(_foolproofDouble);
      final blueberry = store(_blueberry);
      await compute(allButter);
      await compute(blueberry);
      final whole = batchKcal(blueberry);
      final dough = batchKcal(allButter);
      pick(blueberry, 0, allButter, share: 0.5);
      await compute(blueberry);
      void half() {
        final row = rowAt(blueberry, 0);
        expect(row.status, 'overridden');
        expect(row.gramSource, 'recipe');
        expect(row.childShare, 0.5);
        expect(row.grams, closeTo(321.45, 1e-9));
        expect(batchKcal(blueberry), closeTo(whole - dough / 2, 0.01));
      }

      half();
      rebaseNutrition(db, allButter.id, 2); // the child's serving basis
      expect(fresh(blueberry), isFalse);
      await sweep(BulkScope.stale);
      half();
      expect(fresh(blueberry), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test('[N3] a confirmed marinade is poured away, complete', () async {
      final tips = store(_steakTips);
      await compute(tips);
      expect(label(tips).status, 'partial');
      await applyMatchOverride(db, provider, stored(tips), 0, {
        'raw': lineAt(tips, 0).raw,
        'confirmed': true,
      });
      void poured() {
        final row = rowAt(tips, 0);
        expect(row.status, 'confirmed');
        expect(row.hold, 'discarded_recipe');
        expect(row.description, isNull);
        expect(bucketOf(row), MatchBucket.counted);
        expect(label(tips).status, 'complete');
        expect(label(tips).matchedCount, 3);
        expect(label(tips).caloriesPerServing, closeTo(394.63, 0.005));
        expect(fresh(tips), isTrue);
      }

      poured();
      await compute(tips);
      poured();
      await sweep(BulkScope.all);
      poured();
      parity();
    });

    test('[N5] A10 a: a food pick on a reference line weighs its '
        'alternative, keyed on the row', () async {
      final thai = store(_thai);
      final chops = store(_porkChops);
      await compute(thai);
      await compute(chops);
      final curry = lineAt(thai, 1);
      // v44 (sections as children): both lines now ROUTE to their own
      // sections (Green Curry Paste, Basic Spice Rub for Pork Chops), and a
      // routed row's action table refuses a food pick (v41 F3) — OPEN for
      // the owner (fix_s2.md): A10 a's PUT path is unreachable on them.
      for (final (recipe, position, line) in [
        (thai, 1, curry),
        (chops, 3, lineAt(chops, 3)),
      ]) {
        expect(rowAt(recipe, position).childRecipeId, contains('#'));
        await expectLater(
          applyMatchOverride(db, provider, stored(recipe), position, {
            'raw': line.raw,
            'fdc_id': 170924,
          }),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              routedMessage,
            ),
          ),
        );
      }
      void weighed() {
        final row = rowAt(thai, 1);
        expect(row.fdcId, 170924);
        expect(row.grams, closeTo(12.6, 1e-9)); // "2 tablespoons"
        expect(bucketOf(row), MatchBucket.counted);
      }

      // Gate 2 stands: a person's decision on the line's key CARRIED to
      // it (as a pick before v44 left it) is weighed on the alternative,
      // never routed.
      db.putDecision(
        itemKey: 'green curry paste',
        item: 'green curry paste',
        fdcId: 170924,
        description: 'Spices, curry powder',
        dataType: 'SR Legacy',
        decidedBy: null,
      );
      await compute(thai);
      weighed();
      expect(rowAt(thai, 1).status, 'auto');
    });

    test('[F10] the totals read the child LIVE, never stored grams', () async {
      final crust = store(_graham);
      final keyLime = store(_keyLime);
      await compute(crust);
      await compute(keyLime);
      final kcal0 = batchKcal(keyLime);
      final grams0 = label(keyLime).totalGrams!;
      final crustKcal0 = batchKcal(crust);
      final crustGrams0 = label(crust).totalGrams!;
      // A person's Skip of the crust's butter moves its totals and stamp.
      await applyMatchOverride(db, provider, stored(crust), 1, {
        'skipped': true,
      });
      expect(lineAt(crust, 1).raw, contains('unsalted butter'));
      expect(label(crust).totalGrams, lessThan(crustGrams0));
      // A PUT on ANOTHER line of key-lime-pie before any sweep.
      await applyMatchOverride(db, provider, stored(keyLime), 0, {
        'raw': lineAt(keyLime, 0).raw,
        'confirmed': true,
      });
      expect(
        batchKcal(keyLime),
        closeTo(kcal0 - crustKcal0 + batchKcal(crust), 0.01),
      );
      expect(
        label(keyLime).totalGrams,
        closeTo(grams0 - crustGrams0 + label(crust).totalGrams!, 0.1),
      );
    });

    test('a routed child that is partial flags its parent row [M16]', () async {
      // A stated composed-from-real-lines exception (tests.md 7.6): the
      // watermelon salad's real held watermelon line appended to Classic
      // Tart Dough (RE-PIN (M47 batch, v49 Q12): was the fruit tart's kiwi
      // line, counted now).
      final dough = store(_tartDough);
      final lemon = store(_lemonTart);
      final kiwi = nutritionLines(loadCorpusRecipe(_watermelon))[5];
      expect(kiwi.raw, '6 cups 1½-inch seedless watermelon pieces');
      final group = stored(dough).ingredients.last;
      final edited = stored(dough).copyWith(
        ingredients: [
          ...stored(dough).ingredients.take(
            stored(dough).ingredients.length - 1,
          ),
          group.copyWith(items: [...group.items, kiwi]),
        ],
      );
      expect(
        updateRecipe(db, config, dough.id, {
          'ingredients': edited.toMap()['ingredients'],
        }).changed,
        isTrue,
      );
      await compute(dough);
      expect(label(dough).status, 'partial');
      await compute(lemon);
      final row = rowAt(lemon, 0);
      expect(row.childRecipeId, dough.id);
      expect(
        compositeFlagOf(
          db,
          stored(lemon),
          lineAt(lemon, 0),
          row,
          ResolverMemo(db),
        ),
        'approximation (Classic Tart Dough is partial: '
        '${label(dough).matchedCount} of ${label(dough).totalCount} lines)',
      );
      expect(label(lemon).status, 'partial');
    });

    /// The All-Butter dough with the watermelon salad's real held line
    /// appended (the M16 composed-lines exception, tests.md 7.6): a child
    /// that computes partial, 7 of 8. RE-PIN (M47 batch, v49 Q12): was the
    /// fruit tart's kiwi line, counted now.
    Future<void> kiwiDough(Recipe dough) async {
      final kiwi = nutritionLines(loadCorpusRecipe(_watermelon))[5];
      expect(kiwi.raw, '6 cups 1½-inch seedless watermelon pieces');
      final group = stored(dough).ingredients.last;
      final edited = stored(dough).copyWith(
        ingredients: [
          ...stored(dough).ingredients.take(
            stored(dough).ingredients.length - 1,
          ),
          group.copyWith(items: [...group.items, kiwi]),
        ],
      );
      expect(
        updateRecipe(db, config, dough.id, {
          'ingredients': edited.toMap()['ingredients'],
        }).changed,
        isTrue,
      );
      await compute(dough);
      expect(label(dough).status, 'partial');
    }

    test('a partial child is counted, never accounted [6(i)]', () async {
      final allButter = store(_allButter);
      store(_basic);
      store(_foolproofDouble);
      final blueberry = store(_blueberry);
      await compute(allButter);
      await compute(blueberry);
      final total = label(blueberry).totalCount;
      expect(label(blueberry).status, 'complete');
      expect(label(blueberry).matchedCount, total);
      final withoutDough = batchKcal(blueberry) - batchKcal(allButter);
      await kiwiDough(allButter);
      await compute(blueberry);
      expect(rowAt(blueberry, 0).childRecipeId, allButter.id);
      // Contributing: the partial dough's batch is in the pie's...
      expect(
        batchKcal(blueberry),
        closeTo(withoutDough + batchKcal(allButter), 0.01),
      );
      // ...and every line contributes (the label's matched count), but the
      // dough is not accounted: the otherwise-complete pie reads partial.
      expect(label(blueberry).matchedCount, total);
      expect(label(blueberry).status, 'partial');
      // A6: the partial-child flag names a fact and stays on a Confirm; the
      // default flag is the engine's guess and the Confirm clears it (D6).
      String? flag() => compositeFlagOf(
        db,
        stored(blueberry),
        lineAt(blueberry, 0),
        rowAt(blueberry, 0),
        ResolverMemo(db),
      );
      final partial =
          'approximation (All-Butter Double-Crust Pie Dough is partial: '
          '${label(allButter).matchedCount} of '
          '${label(allButter).totalCount} lines)';
      expect(
        flag(),
        'approximation (the first dough the note names: '
        'All-Butter Double-Crust Pie Dough) · $partial',
      );
      await applyMatchOverride(db, provider, stored(blueberry), 0, {
        'raw': lineAt(blueberry, 0).raw,
        'confirmed': true,
      });
      expect(rowAt(blueberry, 0).status, 'confirmed');
      expect(rowAt(blueberry, 0).childRecipeId, allButter.id);
      expect(flag(), partial);
    });

    test('a skip reads no child: its next write leaves the parent fresh '
        '[F2, D-a]', () async {
      final allButter = store(_allButter);
      store(_basic);
      store(_foolproofDouble);
      final blueberry = store(_blueberry);
      await compute(allButter);
      await compute(blueberry);
      expect(rowAt(blueberry, 0).childStamp, label(allButter).computedAt);
      await applyMatchOverride(db, provider, stored(blueberry), 0, {
        'raw': lineAt(blueberry, 0).raw,
        'skipped': true,
      });
      expect(rowAt(blueberry, 0).status, 'skipped');
      expect(rowAt(blueberry, 0).childStamp, isNull);
      rebaseNutrition(db, allButter.id, 4); // the child's next write
      await compute(blueberry);
      expect(rowAt(blueberry, 0).childStamp, isNull);
      expect(fresh(blueberry), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test('a prep-note edit makes the parent stale; the next compute routes '
        'the dough the note names first [S12, item 9]', () async {
      final allButter = store(_allButter);
      final basic = store(_basic);
      store(_foolproofDouble);
      final blueberry = store(_blueberry);
      await compute(allButter);
      await compute(basic);
      await compute(blueberry);
      expect(rowAt(blueberry, 0).childRecipeId, allButter.id);
      // The note's own words, its first two doughs in the other order.
      final note = stored(blueberry).prepNotes!;
      const first = 'All-Butter Double-Crust Pie Dough (this page)';
      const second = 'Basic Double-Crust Pie Dough (this page)';
      expect(note, contains('$first, $second'));
      expect(
        updateRecipe(db, config, blueberry.id, {
          'prep_notes': note.replaceFirst('$first, $second', '$second, $first'),
        }).changed,
        isTrue,
      );
      expect(fresh(blueberry), isFalse); // the hash reads the note
      await compute(blueberry);
      expect(rowAt(blueberry, 0).childRecipeId, basic.id);
      expect(fresh(blueberry), isTrue);
    });

    test('a section rename makes the parent stale; the next compute '
        're-resolves on the sections it has now [S12, item 9]', () async {
      final nachos = store(_nachos);
      final guacamole = store(_guacamole);
      final salsa = sectionKeyOf(nachos.id, 'One-Minute Salsa');
      await compute(guacamole);
      await computeKey(salsa);
      await compute(nachos);
      // v44: routed to its own section (a child of its own).
      expect(rowAt(nachos, 5).childRecipeId, salsa);
      expect(rowAt(nachos, 6).childRecipeId, guacamole.id); // the library's
      expect(fresh(nachos), isTrue);
      // Its own section given the title of the line beside it: the salsa
      // line loses its section, the guacamole line gains one, which wins
      // over the library recipe (design §2.2 item 2's order).
      final sub = stored(nachos).subsections.single;
      expect(sub.title, 'One-Minute Salsa');
      final renamed = stored(
        nachos,
      ).copyWith(subsections: [sub.copyWith(title: 'Chunky Guacamole')]);
      expect(
        updateRecipe(db, config, nachos.id, {
          'subsections': renamed.toMap()['subsections'],
        }).changed,
        isTrue,
      );
      expect(fresh(nachos), isFalse); // the hash reads the section titles
      // v44: the renamed section is a new key (S15), computed first as the
      // per-recipe job computes a recipe's child sections.
      final renamed0 = sectionKeyOf(nachos.id, 'Chunky Guacamole');
      await computeKey(renamed0);
      await compute(nachos);
      expect(rowAt(nachos, 6).childRecipeId, renamed0);
      expect(rowAt(nachos, 5).hold, 'choose_recipe');
      expect(fresh(nachos), isTrue);
    });

    test('one child totals read per composite row per compute [F14]', () async {
      final allButter = store(_allButter);
      store(_basic);
      store(_foolproofDouble);
      final blueberry = store(_blueberry);
      await compute(allButter);
      await compute(blueberry); // its own foods' answers, cached once
      final before = calls();
      int readsOf(Recipe recipe) => db
          .ingredientMatchesFor(recipe.id)
          .where((row) => row.childRecipeId != null)
          .length;
      // An engine row (auto), then a person's Confirm (a decided row).
      for (final decide in [false, true]) {
        if (decide) {
          await applyMatchOverride(db, provider, stored(blueberry), 0, {
            'raw': lineAt(blueberry, 0).raw,
            'confirmed': true,
          });
          expect(rowAt(blueberry, 0).status, 'confirmed');
        }
        childNutritionReads = 0;
        await compute(blueberry);
        expect(readsOf(blueberry), 1);
        expect(childNutritionReads, readsOf(blueberry), reason: '$decide');
      }
      expect(calls(), before); // 0 FDC calls
      // The row the compute writes reads its child through the memo, so the
      // totals' read of it is the same one.
      final memo = ResolverMemo(db);
      childNutritionReads = 0;
      final row = referenceRowFor(
        db,
        stored(blueberry),
        0,
        lineAt(blueberry, 0),
        memo,
      );
      expect(row.childRecipeId, allButter.id);
      expect(childNutritionReads, 1);
      expect(memo.childNutrition(allButter.id)?.computedAt, row.childStamp);
      expect(childNutritionReads, 1); // the memo's, not a second read
    });
  });

  group(
    'the bulk order puts a parent after its child',
    skip: skipIfNoCorpus,
    () {
      setUp(openDb);
      tearDown(closeDb);

      test('nachos routed and fresh in ONE `missing` job [7.5, F7b]', () async {
        final nachos = store(_nachos);
        final guacamole = store(_guacamole);
        await sweep(BulkScope.missing);
        final row = rowAt(nachos, 6);
        expect(row.childRecipeId, guacamole.id);
        expect(row.childStamp, label(guacamole).computedAt);
        expect(fresh(nachos), isTrue);
        expect(fresh(guacamole), isTrue);
        // v44: |5 routes to its own One-Minute Salsa, computed first in the
        // same job ([child section keys, non-parents, parents]).
        final salsa = rowAt(nachos, 5);
        expect(
          salsa.childRecipeId,
          sectionKeyOf(nachos.id, 'One-Minute Salsa'),
        );
        expect(
          salsa.childStamp,
          db.nutritionFor(salsa.childRecipeId!)!.computedAt,
        );
        expect(label(nachos).status, 'complete');
      });
    },
  );
}
