// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v44, steps 2, 4 and 6 (prep43 design_v2 §2 v44.2 / v44.4 /
// v44.6; the owner's 2026-10-06 rulings S5–S11, N8): a reference to a
// SECTION routes to it as a child of its own (`<host id>#<exact title>`)
// at the share the line reads from the SECTION's yield; a section with no
// lines is the `no_ingredients` rule row; another host's section routes
// only when ONE host carries the title (N8); a "(recipes follow)" line held
// for a person lists its own sections no other line routes to (rule PO);
// an unmarked line naming its own section reads one too (A9), a bare 1 as
// one recipe (S11); a share-less pick on a marinade is refused (S10). The
// 16 defect queries are rules and the 23 section reads land on cached
// answers (S5, S6, S7): each pinned with NO fixture for its defect query,
// so FixtureProvider's UnrecordedAnswer bites the moment a rule stops.
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider;
// entries added --from-db from snapshot 19), never the network. Each
// unchanged row's values are the owner's v43 replay row
// (.claude/diag/2026-10-06/v43_rows.tsv). Synthesized inputs, each a
// stated negative path: a host with NO section of its own reading
// another's "Spice Rub" (the N8 guard: no corpus line names a title two
// other hosts carry).

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _chraime = '1208-chraime.yaml';
const _gfPizza = '0393-the-best-gluten-free-pizza.yaml';
const _gfCookies = '0819-gluten-free-chocolate-chip-cookies.yaml';
const _rainbow = '1201-rainbow-cake.yaml';
const _spiceCake = '0869-spice-cake.yaml';
const _carrotCake = '0866-carrot-cake.yaml';
const _eggplant = '0053-crispy-thai-eggplant-salad.yaml';
const _lemonMeringue = '0989-lemon-meringue-pie.yaml';
const _basicDouble = '0972-basic-double-crust-pie-dough.yaml';
const _plumPie =
    '0983-fresh-plum-ginger-pie-with-whole-wheat-lattice-top-crust.yaml';
const _foolproofAllButter =
    '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml';
const _peruvian = '0139-peruvian-roast-chicken-with-garlic-and-lime.yaml';
const _calamari = '1084-rhode-islandstyle-fried-calamari.yaml';
const _memphis = '0614-memphis-style-barbecued-spareribs.yaml';
const _beerCan = '0640-grill-roasted-beer-can-chicken.yaml';
const _ham = '0251-glazed-spiral-sliced-ham.yaml';
const _pulledPork = '0609-barbecued-pulled-pork.yaml';
const _freshHam = '0249-roast-fresh-ham.yaml';
const _tenderloin = '0214-roast-beef-tenderloin.yaml';
const _pumpkin = '0987-pumpkin-pie.yaml';
const _pecan = '0988-pecan-pie.yaml';
const _quiche = '0742-quiche-lorraine.yaml';
const _kibbeh = '1176-red-lentil-kibbeh.yaml';
const _tapenade = '0703-boiled-potatoes-with-black-olive-tapenade.yaml';
const _baja = '1093-vegan-baja-style-cauliflower-tacos.yaml';
const _tinga = '0482-tinga-de-pollo-shredded-chicken-tacos.yaml';
const _kebabs = '0620-grilled-lamb-kebabs.yaml';
const _turkey =
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml';
const _herbSauce =
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _pepperoni = '0394-pepperoni-pan-pizza.yaml';
const _thinCrust = '0383-crisp-thin-crust-pizza.yaml';
const _guayTiew =
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml';
const _mushroomSoup = '0017-creamy-mushroom-soup.yaml';

/// Every recipe a test here reads, stored as the importer stores them.
const _library = [
  _chraime, _gfPizza, _gfCookies, _rainbow, _spiceCake, _carrotCake, //
  _eggplant, _lemonMeringue, _basicDouble, _plumPie, _foolproofAllButter,
  _peruvian, _calamari, _memphis, _beerCan, _ham, _pulledPork, _freshHam,
  _tenderloin, _pumpkin, _pecan, _quiche, _kibbeh, _tapenade, _baja, _tinga,
  _kebabs, _turkey, _herbSauce, _pepperoni, _thinCrust, _guayTiew,
  _mushroomSoup,
];

void main() {
  group('matcher v44 sections', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v44-sections-');
      config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath)
        ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
      provider = FixtureProvider();
      for (final file in _library) {
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
      }
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Recipe stored(String file) =>
        db.recipeByIdOrSlug(loadCorpusRecipe(file).id)!.recipe;

    String keyOf(String file, String title) =>
        sectionKeyOf(stored(file).id, title);

    IngredientLine lineOf(String file, int position) =>
        nutritionLines(stored(file))[position];

    ReferenceResolution resolved(String file, int position) => resolveReference(
      db,
      stored(file),
      lineOf(file, position),
      ResolverMemo(db),
    );

    IngredientMatchRow rowFor(String file, int position) => referenceRowFor(
      db,
      stored(file),
      position,
      lineOf(file, position),
      ResolverMemo(db),
    );

    Future<void> computeKey(String key) async => expect(
      await matchAndCompute(db, provider, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );

    var alones = 0;

    /// [file]'s line at [position] — of its section [section], else a main
    /// line — ALONE in its recipe (the host's steps, notes and sections
    /// kept; a section line under the section's own key), computed on the
    /// fixtures; its one row and the recipe it was computed in.
    Future<(IngredientMatchRow, Recipe)> alone(
      String file,
      int position, {
      String? section,
    }) async {
      final host = stored(file);
      final from = section == null
          ? host
          : sectionOf(host, sectionKeyOf(host.id, section))!;
      final line = nutritionLines(from)[position];
      final id = 'r${alones++}';
      final one = section == null
          ? host.copyWith(
              id: id,
              slug: id,
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            )
          : from.copyWith(
              ingredients: [
                IngredientGroup(items: [line]),
              ],
            );
      if (section == null) {
        db.upsertRecipe(one, sourceSlug: _source, contentHash: id);
      }
      expect(await matchAndCompute(db, provider, one), isNull);
      return (db.ingredientMatchesFor(one.id).single, one);
    }

    group('step 2: a reference routes to its section', () {
      test("the key and the share the line reads from the SECTION's yield "
          "(own, another host's, the reversed title, the first 'or' "
          'alternative, a double batch, a written half)', () {
        for (final (file, position, hostFile, title, share) in [
          (_chraime, 7, _chraime, 'Tabil', 0.125),
          (
            _gfPizza,
            0,
            _gfPizza,
            'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
            16 / 42,
          ),
          (
            _gfCookies,
            0,
            _gfPizza,
            'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
            8 / 42,
          ),
          (_rainbow, 9, _rainbow, 'Vanilla Frosting', 2.0),
          (_turkey, 4, _turkey, 'Golden Cornbread', 0.75),
          (_herbSauce, 3, _herbSauce, 'Sauce Base', 0.5),
          (_spiceCake, 16, _carrotCake, 'Cream Cheese Frosting', 1.0),
          (_carrotCake, 12, _carrotCake, 'Cream Cheese Frosting', 1.0),
          (_pepperoni, 7, _thinCrust, 'Quick Tomato Sauce for Pizza', 1.0),
          (_quiche, 0, _basicDouble, 'Basic Single-Crust Pie Dough', 1.0),
          (_pumpkin, 0, _basicDouble, 'Basic Single-Crust Pie Dough', 1.0),
          (_pecan, 0, _basicDouble, 'Basic Single-Crust Pie Dough', 1.0),
          (
            _eggplant,
            14,
            _eggplant,
            'Fried Shallots and Fried Shallot Oil',
            1 / 3,
          ),
          (_guayTiew, 15, _guayTiew, 'Nam Prik Pao (Thai Chili Jam)', 1.0),
          (_mushroomSoup, 12, _mushroomSoup, 'Sautéed Wild Mushrooms', 1.0),
          (_memphis, 0, _memphis, 'Spice Rub', 1.0),
          (_beerCan, 3, _beerCan, 'Spice Rub', 0.1875),
        ]) {
          final found = resolved(file, position);
          final reason = '$file|$position';
          expect(found.childId, keyOf(hostFile, title), reason: reason);
          expect(found.named, 0, reason: reason);
          expect(found.kind, ReferenceKind.routed, reason: reason);
          expect(found.share, closeTo(share, 1e-4), reason: reason);
        }
      });

      test("another host's section routes only when ONE host carries the "
          'title (N8); a host owning the title reads its OWN', () {
        // Peruvian's own "Spicy Mayonnaise" with Rhode Island-style fried
        // calamari's in the library: its own, as every "Spice Rub" line
        // (Memphis, beer-can chicken: each its own host, never the other's).
        expect(
          db.subsectionTitleIndex().where((s) => s.title == 'Spicy Mayonnaise'),
          hasLength(2),
        );
        expect(
          resolved(_peruvian, 12).childId,
          keyOf(_peruvian, 'Spicy Mayonnaise'),
        );
        // A stated negative path (no corpus line names a title two OTHER
        // hosts carry): beer-can chicken's real "3 tablespoons Spice Rub"
        // line in a host with no section of its own — two hosts carry
        // "Spice Rub", so the line is held for a person, never a guess.
        final beerCan = stored(_beerCan);
        final orphan = beerCan.copyWith(id: 'r', subsections: const []);
        final found = resolveReference(
          db,
          orphan,
          lineOf(_beerCan, 3),
          ResolverMemo(db),
        );
        expect(found.kind, ReferenceKind.held);
        expect(found.childId, isNull);
        // With ONE other host (Memphis gone) it routes there.
        deleteRecipe(db, config, stored(_memphis).id);
        final one = resolveReference(
          db,
          orphan,
          lineOf(_beerCan, 3),
          ResolverMemo(db),
        );
        expect(one.kind, ReferenceKind.routed);
        expect(one.childId, keyOf(_beerCan, 'Spice Rub'));
      });

      test('a target section with no ingredient lines is the no_ingredients '
          'rule row, its v43 row unchanged (S13)', () {
        for (final (file, position, key) in [
          (_lemonMeringue, 0, 'single-crust pie dough for custard py'),
          (_plumPie, 0, 'foolproof whole-wheat dough for double-crust pie'),
        ]) {
          final found = resolved(file, position);
          expect(found.kind, ReferenceKind.section, reason: file);
          expect(found.noIngredients, isTrue, reason: file);
          expect(found.childId, isNull, reason: file);
          final row = rowFor(file, position);
          expect(
            (row.fdcId, row.description, row.grams, row.gramSource),
            (null, subRecipeNote, 0, 'unmeasured'),
            reason: file,
          );
          expect(
            (row.status, row.hold, row.itemKey),
            (
              'confirmed',
              null,
              key,
            ),
          );
          expect(
            gramBasisFor(db, lineOf(file, position), row, recipe: stored(file)),
            'a sub-recipe — counted as 0 g',
          );
        }
        // Their hosts are no children: a prose variation is never computed.
        expect(
          sectionChildKeysOf(db, stored(_lemonMeringue), ResolverMemo(db)),
          isEmpty,
        );
      });

      test('the no-amount lines and the served-with line stay the rule row, '
          'their v43 rows unchanged', () {
        for (final (file, position, key) in [
          ('0070-skillet-chicken-fajitas.yaml', 22, 'spicy pickled radish'),
          (
            '0256-pan-seared-salmon.yaml',
            3,
            'sweet-and-sour chutney or lemon wedge',
          ),
          ('0288-maryland-crab-cakes.yaml', 10, 'sweet and tangy tartar sauce'),
          (
            '0568-indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas.yaml',
            16,
            'onion relish',
          ),
          (
            '0568-indian-style-curry-with-potatoes-cauliflower-peas-and-chickpeas.yaml',
            17,
            'cilantro-mint chutney or mango chutney',
          ),
          ('0712-red-beans-and-rice.yaml', 14, 'basic white rice'),
          (
            '0738-spanish-tortilla-with-roasted-red-peppers-and-peas.yaml',
            8,
            'garlic mayonnaise',
          ),
          ('0925-panna-cotta.yaml', 6, 'raspberry coulis'),
          (_herbSauce, 0, 'pan-seared steak'),
        ]) {
          // The library title the herb sauce is served WITH (D7).
          final steaks = loadCorpusRecipe('0184-pan-seared-steaks.yaml');
          db.upsertRecipe(steaks, sourceSlug: _source, contentHash: steaks.id);
          final recipe = loadCorpusRecipe(file);
          db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
          expect(
            resolved(file, position).kind,
            file == _herbSauce
                ? ReferenceKind.servedWith
                : ReferenceKind.noAmount,
            reason: file,
          );
          final row = rowFor(file, position);
          expect(
            (
              row.fdcId,
              row.description,
              row.grams,
              row.gramSource,
              row.status,
              row.hold,
              row.itemKey,
              row.childRecipeId,
            ),
            (
              null,
              subRecipeNote,
              0,
              'unmeasured',
              'confirmed',
              null,
              key,
              null,
            ),
            reason: file,
          );
          expect(
            gramBasisFor(db, lineOf(file, position), row, recipe: stored(file)),
            'a sub-recipe — counted as 0 g',
          );
        }
      });

      test('the four lines a shipped rule counts on a food stay food rows, '
          'cols 1–12 as v43 (S17)', () async {
        for (final (
              file,
              position,
              fdcId,
              description,
              confidence,
              grams,
              source,
              key,
              basis,
            )
            in [
              (
                '0731-curry-deviled-eggs-with-easy-peel-hard-cooked-eggs.yaml',
                0,
                173424,
                'Egg, whole, cooked, hard-boiled',
                '0.580000',
                '300.00',
                'piece',
                'easy-peel hard-cooked egg',
                '6 × 50 g each',
              ),
              (
                '1192-gado-gado.yaml',
                17,
                173424,
                'Egg, whole, cooked, hard-boiled',
                '0.580000',
                '200.00',
                'piece',
                'easy-peel hard-cooked egg',
                '4 × 50 g each',
              ),
              (
                '0478-ground-beef-tacos.yaml',
                15,
                172800,
                'Taco shells, baked',
                '0.508333',
                '103.20',
                'piece',
                'home-fried taco shell',
                '8 · USDA per-item weight',
              ),
              (
                '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
                7,
                2710180,
                'Vegetable oil, NFS',
                '0.923333',
                '42.00',
                'portion',
                'crispy onion plus reserved oil',
                '3 tablespoon · USDA portion',
              ),
            ]) {
          final recipe = loadCorpusRecipe(file);
          db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
          final line = lineOf(file, position);
          expect(subRecipeRowFor(stored(file), position, line), isNull);
          expect(
            sectionChildKeysOf(db, stored(file), ResolverMemo(db)),
            isEmpty,
            reason: file,
          );
          final (row, one) = await alone(file, position);
          expect(
            (
              row.raw,
              row.fdcId,
              row.description,
              row.confidence.toStringAsFixed(6),
              row.grams?.toStringAsFixed(2),
              row.gramSource,
              row.status,
              row.hold,
              row.itemKey,
              gramBasisFor(db, line, row, recipe: one),
            ),
            (
              line.raw,
              fdcId,
              description,
              confidence,
              grams,
              source,
              'auto',
              null,
              key,
              basis,
            ),
            reason: file,
          );
        }
      });

      test('a routed section row: the child, its share, the section total '
          'grams × the share, its stamp; the section rules read the '
          "SECTION's own steps (its frying oil 0 g)", () async {
        for (final (file, position, hostFile, title) in [
          (_chraime, 7, _chraime, 'Tabil'),
          (_eggplant, 14, _eggplant, 'Fried Shallots and Fried Shallot Oil'),
          (_spiceCake, 16, _carrotCake, 'Cream Cheese Frosting'),
        ]) {
          final key = keyOf(hostFile, title);
          await computeKey(key);
          final child = db.nutritionFor(key)!;
          expect(child.status, 'complete', reason: key);
          final row = rowFor(file, position);
          final share = resolved(file, position).share!;
          expect(row.childRecipeId, key);
          expect(row.childShare, share);
          expect(row.childStamp, child.computedAt);
          expect(row.grams, closeTo(child.totalGrams! * share, 1e-9));
          expect((row.status, row.hold, row.fdcId), ('auto', null, null));
          expect(row.gramSource, 'recipe');
        }
        // The shallots' "2 cups vegetable oil" is the frying medium of the
        // section's OWN step ("Fried Shallots and Fried Shallot Oil": 108 of
        // the 140 child sections store no steps; this one is of the 32).
        final shallots = keyOf(
          _eggplant,
          'Fried Shallots and Fried Shallot Oil',
        );
        final oil = db
            .ingredientMatchesFor(shallots)
            .singleWhere((r) => r.position == 1);
        expect(oil.raw, '2 cups vegetable oil');
        expect(oil.grams, 0);
        expect(nutritionRecipeOf(db, shallots)!.recipe.steps, isNotEmpty);
        expect(
          nutritionRecipeOf(db, shallots)!.recipe.steps.map((s) => s.text),
          isNot(stored(_eggplant).steps.map((s) => s.text)),
        );
      });

      test(
        'a partial section child is counted, flagged and never accounted: '
        'the gluten-free flour blend with its potato starch unanswered',
        () async {
          // Since v46 the potato starch reads the cached 'cornstarch' answer
          // (and the brown rice flour 'white rice flour'): the blend is
          // complete on real data, so a stated synthesized negative path
          // answers that recorded search as FDC's no hits.
          provider.noHits = {'cornstarch'};
          final key = keyOf(
            _gfPizza,
            'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
          );
          await computeKey(key);
          final blend = db.nutritionFor(key)!;
          expect(blend.status, 'partial');
          expect((blend.matchedCount, blend.totalCount), (4, 5));
          final (row, one) = await alone(_gfCookies, 0);
          expect(row.childRecipeId, key);
          final label = db.nutritionFor(one.id)!;
          // Counted (its kcal in the totals), never accounted: partial.
          expect(label.status, 'partial');
          expect((label.matchedCount, label.totalCount), (1, 1));
          expect(
            batchTotalsOf(label)['energy'],
            closeTo(batchTotalsOf(blend)['energy']! * 8 / 42, 1e-6),
          );
          expect(
            compositeFlagOf(
              db,
              one,
              nutritionLines(one).single,
              row,
              ResolverMemo(db),
            ),
            'approximation (The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend is partial: 4 of 5 lines)',
          );
        },
      );

      test("a section's stale hash carries its yield; a main recipe's does "
          'not', () {
        final host = stored(_chraime);
        final tabil = nutritionRecipeOf(db, keyOf(_chraime, 'Tabil'))!.recipe;
        expect(
          ingredientsHashOf(
            tabil.copyWith(servings: 'MAKES ABOUT 1 CUP'),
            ResolverMemo(db),
          ),
          isNot(ingredientsHashOf(tabil, ResolverMemo(db))),
        );
        expect(
          ingredientsHashOf(
            host.copyWith(servings: 'SERVES 8'),
            ResolverMemo(db),
          ),
          ingredientsHashOf(host, ResolverMemo(db)),
        );
      });
    });

    group('step 4: rule PO, A9, the marinade', () {
      List<String?> ownGroup(String file, int position) => [
        for (final c in referenceCandidates(
          stored(file),
          lineOf(file, position),
          ResolverMemo(db),
        ))
          if (c.group == 'own_section') c.section,
      ];

      test('a "(recipes follow)" line held for a person lists its own '
          'sections no other line routes to, in document order (S8)', () {
        expect(ownGroup(_ham, 2), ['Maple-Orange Glaze', 'Cherry-Port Glaze']);
        // Line 1 routes to the Dry Rub: only the two sauces are listed.
        expect(ownGroup(_pulledPork, 4), [
          'Eastern North Carolina Barbecue Sauce',
          'Mid–South Carolina Mustard Sauce',
        ]);
        expect(ownGroup(_freshHam, 12), [
          'Cider and Brown Sugar Glaze',
          'Spicy Pineapple-Ginger Glaze',
          'Coca-Cola Glaze with Lime and Jalapeño',
          'Orange, Cinnamon, and Star Anise Glaze',
        ]);
        expect(ownGroup(_tenderloin, 5), [
          'Shallot and Parsley Butter',
          'Chipotle and Garlic Butter with Lime and Cilantro',
        ]);
        expect(ownGroup(_kebabs, 0), hasLength(3)); // the three marinades
        expect(ownGroup(_pumpkin, 0), isEmpty);
        // Listed, never routed: the line stays held for a person.
        for (final (file, position) in [(_ham, 2), (_pulledPork, 4)]) {
          expect(resolved(file, position).kind, ReferenceKind.held);
          expect(rowFor(file, position).hold, chooseRecipeHold);
        }
        // Each candidate is a child (computed by the sweep, pickable).
        expect(
          sectionChildKeysOf(db, stored(_ham), ResolverMemo(db)),
          {keyOf(_ham, 'Maple-Orange Glaze'), keyOf(_ham, 'Cherry-Port Glaze')},
        );
      });

      test('A9: an unmarked line naming its own section routes there; a '
          'bare 1 reads one recipe (S11); a counted food stays its food', () {
        for (final (file, position, title, share) in [
          (_kibbeh, 4, 'Harissa', 0.25),
          (_tapenade, 2, 'Black Olive Tapenade', 2 / 9),
          (_baja, 14, 'Vegan Cilantro Sauce', 1.0),
        ]) {
          final recipe = stored(file);
          final line = lineOf(file, position);
          expect(isSubRecipeReference(line.raw), isFalse, reason: line.raw);
          expect(namesOwnSection(recipe, line), isTrue, reason: line.raw);
          expect(isReferenceIn(recipe, line), isTrue, reason: line.raw);
          expect(subRecipeRowFor(recipe, position, line), isNotNull);
          expect(readsSubRecipe(recipe), isTrue, reason: file);
          final found = resolved(file, position);
          expect(found.kind, ReferenceKind.routed, reason: line.raw);
          expect(found.childId, keyOf(file, title));
          expect(found.share, closeTo(share, 1e-6), reason: line.raw);
          // The hash reads the sections an A9 recipe's line names.
          expect(
            ingredientsHashOf(
              recipe.copyWith(
                subsections: [
                  for (final sub in recipe.subsections)
                    sub.title == title ? sub.copyWith(title: '$title II') : sub,
                ],
              ),
              ResolverMemo(db),
            ),
            isNot(ingredientsHashOf(recipe, ResolverMemo(db))),
          );
        }
        // "12 (6-inch) corn tortillas, warmed" names tinga's "Corn
        // Tortillas" — a bare count of 12, its food.
        final tortillas = lineOf(_tinga, 12);
        expect(namesOwnSection(stored(_tinga), tortillas), isFalse);
        expect(subRecipeRowFor(stored(_tinga), 12, tortillas), isNull);
      });

      test('a share-less pick on a marinade is refused (S10)', () async {
        final kebabs = stored(_kebabs);
        final line = lineOf(_kebabs, 0);
        // The wire (S3, P3 §4): the host's slug and the section's title.
        const marinade = 'Warm-Spiced Parsley Marinade with Ginger';
        expect(resolved(_kebabs, 0).kind, ReferenceKind.marinade);
        await expectLater(
          applyMatchOverride(db, provider, kebabs, 0, {
            'raw': line.raw,
            'child': kebabs.slug,
            'section': marinade,
          }),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              'Set the share that is eaten — the rest is poured away.',
            ),
          ),
        );
        // With a share typed, the marinade check passes (the next one asks
        // for the section's totals).
        await expectLater(
          applyMatchOverride(db, provider, kebabs, 0, {
            'raw': line.raw,
            'child': kebabs.slug,
            'section': marinade,
            'share': 0.25,
          }),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              sectionUncomputedMessage,
            ),
          ),
        );
      });
    });

    group('step 6: the defect queries as rules and the section reads '
        '(no request; no fixture holds a defect query)', () {
      Future<(IngredientMatchRow, Recipe, IngredientLine)> at(
        String file,
        int? section,
        int position,
      ) async {
        final recipe = loadCorpusRecipe(file);
        db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
        final title = section == null
            ? null
            : stored(file).subsections[section].title;
        final (row, one) = await alone(file, position, section: title);
        return (row, one, nutritionLines(one).single);
      }

      const spiceRub =
          'Reserved from the main recipe — counted in the main recipe’s spice rub';
      const noAmount =
          'Reserved from the main recipe — no amount on the line, counts as zero';
      const seasoning = 'Seasoning to taste — no measurable amount';
      const champagne = '1155-champagne-cocktail.yaml';
      const thai =
          '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml';
      const chicken =
          '0626-grilled-glazed-boneless-skinless-chicken-breasts.yaml';
      const rice = '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml';
      const breast = 'Chicken, breast, boneless, skinless, raw';

      test('each line: its record (or rule), grams, status, basis', () async {
        for (final (file, section, position, raw, fdcId, description, grams, status, basis) in [
          // S6 — the main recipe's own parts (two new rule notes).
          (
            '0591-grill-roasted-beef-short-ribs.yaml',
            0,
            3,
            '1 teaspoon reserved spice rub',
            null,
            spiceRub,
            '0.00',
            'confirmed',
            'counted in the main recipe’s spice rub — counted as 0 g',
          ),
          (
            '0591-grill-roasted-beef-short-ribs.yaml',
            1,
            5,
            '1 teaspoon reserved spice rub',
            null,
            spiceRub,
            '0.00',
            'confirmed',
            'counted in the main recipe’s spice rub — counted as 0 g',
          ),
          (
            '0591-grill-roasted-beef-short-ribs.yaml',
            2,
            4,
            '1 teaspoon reserved spice rub',
            null,
            spiceRub,
            '0.00',
            'confirmed',
            'counted in the main recipe’s spice rub — counted as 0 g',
          ),
          (
            '0154-classic-roast-turkey.yaml',
            0,
            1,
            'Reserved turkey giblets, neck, and tailpiece',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          (
            '0155-roast-turkey-for-a-crowd.yaml',
            0,
            1,
            'Reserved turkey giblets, neck, and tailpiece',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          (
            '0159-julia-childs-stuffed-turkey-updated.yaml',
            0,
            0,
            'Reserved turkey giblets, neck, backbone, and thighbones, hacked into 2-inch pieces',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          (
            _turkey,
            1,
            0,
            'Reserved giblets, neck, tailpiece, and backbone and rib bones from the turkey',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          (
            '0175-simple-grill-roasted-turkey.yaml',
            0,
            1,
            'Reserved turkey neck, cut into 1-inch pieces, and giblets',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          (
            '0170-herbed-roast-turkey.yaml',
            0,
            10,
            'Defatted pan drippings from Herbed Roast Turkey (optional)',
            null,
            noAmount,
            '0.00',
            'confirmed',
            'no amount on the line — counted as 0 g',
          ),
          // S6 — seasoning (a purpose tail; the "back pepper" typo), water.
          (
            '0434-salade-lyonnaise.yaml',
            0,
            2,
            'Table salt for poaching eggs',
            null,
            seasoning,
            null,
            'confirmed',
            null,
          ),
          (
            '0054-green-bean-salad-with-cherry-tomatoes-and-feta.yaml',
            1,
            3,
            'Table salt for blanching',
            null,
            seasoning,
            null,
            'confirmed',
            null,
          ),
          (
            '0044-mediterranean-chopped-salad.yaml',
            0,
            10,
            'Ground back pepper',
            null,
            seasoning,
            null,
            'confirmed',
            null,
          ),
          (
            '1136-rose-sangria.yaml',
            0,
            1,
            '5 ounces warm tap water',
            null,
            'Water/ice — counts as zero',
            null,
            'confirmed',
            null,
          ),
          // S6 — the leaked "fluid ounce(s)" unit; the lone cut word.
          (
            champagne,
            0,
            0,
            '2½ fluid ounces (¼ cup plus 1 tablespoon) orange juice, strained and chilled',
            169098,
            "Orange juice, raw (Includes foods for USDA's Food Distribution Program)",
            '77.57',
            'auto',
            '74 ml · USDA portion',
          ),
          (
            champagne,
            0,
            1,
            '¼ fluid ounce (1½ teaspoons) orange liqueur',
            2710623,
            'Liqueur',
            '7.50',
            'auto',
            '1 1/2 teaspoon · USDA portion',
          ),
          (
            champagne,
            0,
            2,
            '3 fluid ounces (¼ cup plus 2 tablespoons) sparkling wine, chilled',
            2710689,
            'Wine, white',
            '88.11',
            'auto',
            '89 ml ≈ 89 mL · approximation (counted as Wine, white)',
          ),
          (
            champagne,
            1,
            1,
            '¼ fluid ounce (1½ teaspoons) peach schnapps',
            2710623,
            'Liqueur',
            '7.50',
            'auto',
            '1 1/2 teaspoon · USDA portion · approximation (counted as Liqueur)',
          ),
          (
            champagne,
            1,
            2,
            '3 fluid ounces (¼ cup plus 2 tablespoons) sparkling wine, chilled',
            2710689,
            'Wine, white',
            '88.11',
            'auto',
            '89 ml ≈ 89 mL · approximation (counted as Wine, white)',
          ),
          (
            rice,
            0,
            0,
            '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
            2646170,
            breast,
            // RE-PIN (M48): 907.18 → 793.79 g, the printed 6–8 oz range at
            // its midpoint (was its top); the basis names the range. (A
            // variation section no main line routes to: not among the
            // replay's 140 child sections.)
            '793.79',
            'auto',
            '4 × 198 g (printed 6–8 oz, the midpoint)',
          ),
          (
            rice,
            1,
            0,
            '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
            2646170,
            breast,
            // RE-PIN (M48): 907.18 → 793.79 g, the printed 6–8 oz range at
            // its midpoint (was its top); the basis names the range. (A
            // variation section no main line routes to: not among the
            // replay's 140 child sections.)
            '793.79',
            'auto',
            '4 × 198 g (printed 6–8 oz, the midpoint)',
          ),
          // S5 — "green thai" on J6's 'thai'; S7 — the counted oranges.
          (
            thai,
            0,
            1,
            '12 fresh green Thai, serrano, or jalapeño chiles, seeds and ribs removed, chiles chopped coarse',
            2709798,
            'Peppers, hot, raw',
            '180.00',
            'auto',
            '12 · USDA per-item weight',
          ),
          (
            '0607-grill-roasted-bone-in-pork-rib-roast.yaml',
            0,
            0,
            '½ teaspoon grated orange zest plus 5 oranges peeled and segmented; each segment quartered crosswise',
            746771,
            'Oranges, raw, navels',
            '655.00',
            'auto',
            '5 × 131 g each · the fruit only (the zest is dropped)',
          ),
          // S5 — the section reads onto cached answers.
          (
            '0244-slow-roasted-bone-in-pork-rib-roast.yaml',
            0,
            0,
            '2 cups tawny port',
            2710692,
            'Wine, dessert, sweet',
            '480.00',
            'auto',
            '2 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
          ),
          (
            '0192-pepper-crusted-filet-mignon.yaml',
            0,
            0,
            '1½ cups port',
            2710692,
            'Wine, dessert, sweet',
            '360.00',
            'auto',
            '1 1/2 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
          ),
          (
            '0234-pan-seared-oven-roasted-pork-tenderloin.yaml',
            0,
            2,
            '¾ cup port',
            2710692,
            'Wine, dessert, sweet',
            '180.00',
            'auto',
            '3/4 cup · USDA portion · approximation (counted as Wine, dessert, sweet)',
          ),
          (
            '1189-bruschetta-with-artichoke-hearts-and-parmesan.yaml',
            0,
            0,
            '1 (10 by 5-inch) loaf country bread with thick crust, ends discarded, sliced crosswise into ¾-inch-thick pieces',
            174913,
            'Bread, Italian',
            '454.00',
            'auto',
            '1 loaf × 454 g each',
          ),
          (
            '0015-carrot-ginger-soup.yaml',
            0,
            2,
            '3 large slices high-quality sandwich bread, cut into ½-inch cubes (about 2 cups)',
            174924,
            'Bread, white, commercially prepared (includes soft bread crumbs)',
            '70.00',
            'auto',
            '2 cup · USDA portion',
          ),
          (
            _mushroomSoup,
            0,
            1,
            '8 ounces shiitake, chanterelle, oyster, or cremini mushrooms, stems trimmed and discarded, mushrooms wiped clean and sliced thin',
            1999628,
            'Mushrooms, shiitake',
            '226.80',
            'auto',
            'from 8 ounce',
          ),
          (
            _beerCan,
            0,
            4,
            '2 teaspoons ground celery seeds',
            170920,
            'Spices, celery seed',
            '4.00',
            'auto',
            '2 teaspoon · USDA portion',
          ),
          (
            '0523-nasi-goreng-indonesian-style-fried-rice.yaml',
            0,
            1,
            '2 cups jasmine or long-grain white rice, rinsed',
            2512381,
            'Rice, white, long grain, unenriched, raw',
            '402.20',
            'auto',
            '2 cup ≈ 473 mL',
          ),
          (
            thai,
            0,
            7,
            '2 tablespoons minced fresh cilantro stems',
            2709782,
            'Cilantro, raw',
            '2.00',
            'auto',
            '2 tablespoon · USDA portion',
          ),
          (
            thai,
            2,
            6,
            '2 tablespoons minced fresh cilantro stems',
            2709782,
            'Cilantro, raw',
            '2.00',
            'auto',
            '2 tablespoon · USDA portion',
          ),
          (
            thai,
            0,
            4,
            '2 stalks lemon grass, bottom 5 inches only, trimmed and sliced thin',
            168573,
            'Lemon grass (citronella), raw',
            '20.00',
            'auto',
            '2 stalk × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
          ),
          (
            thai,
            2,
            3,
            '2 stalks lemon grass, bottom 5 inches only, trimmed and sliced thin',
            168573,
            'Lemon grass (citronella), raw',
            '20.00',
            'auto',
            '2 stalk × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
          ),
          (
            _tapenade,
            0,
            2,
            '½ cup pitted salt-cured black olives',
            2710090,
            'Olives, black',
            '67.50',
            'auto',
            '1/2 cup · USDA portion · approximation (counted as Olives, black)',
          ),
          (
            '0899-bittersweet-chocolate-roulade.yaml',
            0,
            1,
            '2 teaspoons espresso powder or instant coffee',
            171893,
            'Beverages, coffee, instant, regular, powder',
            '4.24',
            'auto',
            '2 teaspoon ≈ 10 mL',
          ),
          (
            '0940-pavlova-with-fruit-and-whipped-cream.yaml',
            0,
            2,
            '5 navel oranges',
            746771,
            'Oranges, raw, navels',
            '655.00',
            'auto',
            '5 × 131 g each',
          ),
          (
            '0597-easy-grilled-boneless-pork-chops.yaml',
            2,
            2,
            '2 jalapeños, stemmed, seeded, and sliced into thin rings',
            2747661,
            'Peppers, jalapeno, seeded, raw',
            '28.00',
            'auto',
            '2 × 14 g each',
          ),
          (
            chicken,
            3,
            4,
            '1 tablespoon sesame oil',
            2710190,
            'Sesame oil',
            '14.00',
            'auto',
            '1 tablespoon · USDA portion',
          ),
          (
            chicken,
            1,
            6,
            '¼ teaspoon ground fennel seeds',
            171323,
            'Spices, fennel seed',
            '0.50',
            'auto',
            '1/4 teaspoon · USDA portion',
          ),
          (
            _freshHam,
            3,
            2,
            '4 pods star anise',
            171316,
            'Spices, anise seed',
            '2.00',
            'auto',
            '4 × 0.5 g each · approximate (reference figure: a whole star anise) · approximation (counted as Spices, anise seed)',
          ),
          (
            '1147-fresh-bulk-sausage.yaml',
            0,
            1,
            '2 teaspoons rubbed sage',
            170935,
            'Spices, sage, ground',
            '1.40',
            'auto',
            '2 teaspoon · USDA portion · approximation (counted as Spices, sage, ground)',
          ),
          (
            '0735-fluffy-omelets.yaml',
            1,
            2,
            '4 ounces white or cremini mushrooms, trimmed and chopped',
            1999629,
            'Mushrooms, white button',
            '113.40',
            'auto',
            'from 4 ounce',
          ),
          (
            '0601-grilled-glazed-pork-tenderloin-roast.yaml',
            2,
            6,
            '2 tablespoons peanut butter',
            2262072,
            'Peanut butter, creamy',
            '32.24',
            'auto',
            '2 tablespoon ≈ 30 mL',
          ),
        ]) {
          provider = FixtureProvider();
          final (row, one, line) = await at(file, section, position);
          final reason = '$file|$section|$position';
          expect(line.raw, raw, reason: reason);
          expect(
            (
              row.fdcId,
              row.description,
              row.grams?.toStringAsFixed(2),
              row.status,
              row.hold,
            ),
            (fdcId, description, grams, status, null),
            reason: reason,
          );
          expect(
            gramBasisFor(db, line, row, recipe: one),
            basis,
            reason: reason,
          );
        }
      });

      test('the reads whose record detail no snapshot holds read their named '
          'answer, its record first (option A fetches the detail)', () async {
        for (final (item, answer, words, fdcId) in [
          ('vegan mayonnaise', 'mayonnaise', 'vegan mayonnaise', 2710205),
          ('pepitas', 'roasted with salt pepitas', 'pepitas', 2515380),
          (
            'raw sunflower seeds',
            'without salt pumpkin seeds or sunflower seeds',
            'raw sunflower seeds',
            2515381,
          ),
          (
            'toasted sesame seeds',
            'sesame seeds',
            'toasted sesame seeds',
            170151,
          ),
        ]) {
          expect(
            lineSearchFor(db, item, item),
            (query: words, answer: answer),
            reason: item,
          );
          final top = rankCandidates(
            words,
            await provider.search(answer),
          ).first;
          expect(top.candidate.fdcId, fdcId, reason: item);
        }
      });

      test(
        'the salt "for <purpose>" rule moves three MAIN rows onto the '
        'seasoning row (0 g either way); the champagne row stays as v43',
        () async {
          for (final (file, position, raw) in [
            (
              '0369-hand-rolled-meat-ravioli.yaml',
              16,
              'Table salt for cooking pasta',
            ),
            (
              '1132-orecchiette-with-broccoli-rabe-and-sausage.yaml',
              5,
              'Table salt for cooking broccoli rabe and pasta',
            ),
            ('1192-gado-gado.yaml', 12, 'Table salt for cooking vegetables'),
          ]) {
            provider = FixtureProvider();
            final (row, _, line) = await at(file, null, position);
            expect(line.raw, raw);
            expect(
              (row.fdcId, row.description, row.status, row.grams),
              (null, seasoning, 'confirmed', null),
              reason: raw,
            );
            expect(provider.searchCalls, 0, reason: raw);
          }
          final (row, one, line) = await at(champagne, null, 2);
          expect(
            (
              row.fdcId,
              row.description,
              row.confidence.toStringAsFixed(6),
              row.grams?.toStringAsFixed(2),
              row.gramSource,
              row.status,
              row.itemKey,
            ),
            (
              2710689,
              'Wine, white',
              '0.990000',
              '165.35',
              'portion',
              'auto',
              'fluid ounce champagne',
            ),
          );
          expect(
            gramBasisFor(db, line, row, recipe: one),
            '163 ml · USDA portion · approximation (counted as Wine, white)',
          );
        },
      );

      test("the two new rule notes are the engine's own rows: in the list, "
          'the SQL list, the decided-row predicate', () {
        expect(engineRuleNotes, containsAll([spiceRub, noAmount]));
        expect(SaltDatabase.engineRuleNotesSql, contains(spiceRub));
        expect(SaltDatabase.engineRuleNotesSql, contains(noAmount));
      });
    });
  });
}
