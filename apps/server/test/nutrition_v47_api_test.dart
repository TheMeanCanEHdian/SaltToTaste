// Matcher v47, handlers and queue (the SECTIONS-batch review fixes; Run 061
// Sonnet 5.5 / Run 062 Opus 5.5):
//
// F3 (O3, S5) — a decision that recomputes a SECTION (a person's PUT on
// one of its lines, `?section=`, or an apply-to-all reaching one) re-reads
// the parents routed to it in the SAME request (`recomputeParentsOf`): the
// queue's `finishes` credits them, so the parents' stored status moves and
// they read fresh (their `child_stamp` re-derived). The apply's receipt
// counts RECIPES — `completed_recipes` the parents completed, never a key;
// `recipes` the reached hosts — and the decided section line's own parents
// other than its host join the receipt (the app's promise drops only the
// decided line's own recipe). O3 itself on real lines: gado-gado's 'red
// curry paste' confirmed with apply_to_all reaches the pork's Satay Glaze
// and the chicken's Coconut-Curry Glaze (both picked) and completes both
// parents in one receipt — its answers recorded from snapshot 20 (closer
// round 1: 7 searches, 2 details, each JSON-equal to its cache row), the
// curry paste record's detail (2706388) cached first as a swept library
// holds it.
// F4 (S6, O4) — the lines view's `finishes` applies the grouped `credit`'s
// `pend`: a main line whose recipe waits on an incomplete routed child
// finishes nothing, in both views.
// F5 (Run 062 critic) — a routed section edited since its parent's compute
// reads the parent STALE (`stale_reason` `inputs`) on the recipe page;
// the per-recipe compute computes the section first, then the parent.
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider),
// never the network; every decision goes through the PUT's own function
// (`applyMatchOverride`, `routeRecipeOf` for `?section=`). STATED
// SYNTHESIZED STATES (the corpus over its recorded answers leaves none of
// them): (F3 c) the recorded "caraway seeds" answer served as FDC's no hits
// (`FixtureProvider.noHits`), so chraime's Tabil is partial — the person's
// pick is then that answer's own top record, 170918 "Spices, caraway
// seed"; (F4) the recorded "white rice flour" and "cornstarch" answers
// served as no hits (the v44 suite's state: the GF flour blend partial);
// (F5) Tabil's coriander line removed from chraime's document (a section
// edit), and (F5 b) a Tabil decision's `derived_seq` cleared — the state
// RULE A leaves when its derivation could not run; (F5 c) S2's stated
// cycle — yeasted-doughnuts given "1 recipe Boston Cream Doughnuts (recipe
// follows)", a host line held `nested_recipe` on its own section — then
// that section's lines reversed (a section edit); (F3 d) a person's pick of
// SR 173410 "Butter, salted" on the Basil and Lemon Butter's butter line;
// (O23, closer round 2) an FDC outage during a person's apply-to-all (the
// v27 critic-1 shape, `Outage`): mechouia's "1½ teaspoons caraway seeds"
// picked to 2710502 — the other hit of the recorded "caraway seeds" answer,
// whose detail no fixture records (the outage throws before one is read) —
// with 4 g typed; and a Tabil writer's mark held, then released stale (a
// writer that threw, as `releaseComputing` leaves it). mechouia's one
// search no fixture held ('bell peppers') is recorded from snapshot 20,
// JSON-equal to its cache row.
// Closer round 3 (the stated `stale_reason` precedence and the receipt's
// "turns complete"): chraime's own "Lemon wedges" line removed (a main-line
// edit); chraime's own line-0 decision confirmed, then its `derived_seq`
// cleared (RULE A's state, as F5 b); bittersweet-chocolate-roulade's
// Espresso-Mascarpone Cream writer's mark held (a live compute) while its
// Dark Chocolate Ganache's lines are reversed (a section edit) — the
// roulade's two searches no fixture held ('dark or dark chocolate', 'cold
// without salt butter') recorded from snapshot 20, each JSON-equal to its
// cache row (its chocolate lines are weighed, so the search hit stands in
// for 170271's unrecorded detail, as in the Bundt cake's golden); F3 c's
// second decision is the same PUT body again (no synthesized state).
// Closer round 4 (verify4 D1, D5): (F3 e) a person's typed share 0.5 on
// roast|5's pick of chraime's Tabil (the PUT body's own `share`; the
// line's words parse 1.0); (F5 d) a Tabil decision's `derived_seq` cleared,
// as F5 b.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _corn = '0657-grilled-corn-with-flavored-butter.yaml';
const _crab = '0288-maryland-crab-cakes.yaml';
const _chraime = '1208-chraime.yaml';
const _roast = '0214-roast-beef-tenderloin.yaml';
const _pizza = '0393-the-best-gluten-free-pizza.yaml';
const _cookies = '0819-gluten-free-chocolate-chip-cookies.yaml';
const _oldBayButter = 'Spicy Old Bay Butter';
const _doughnuts = '1105-yeasted-doughnuts.yaml';
const _gadoGado = '1192-gado-gado.yaml';
const _pork = '0601-grilled-glazed-pork-tenderloin-roast.yaml';
const _chicken = '0626-grilled-glazed-boneless-skinless-chicken-breasts.yaml';
const _mechouia = '0661-mechouia-tunisian-style-grilled-vegetables.yaml';
const _roulade = '0899-bittersweet-chocolate-roulade.yaml';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v47-api-');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
    provider = FixtureProvider();
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// [files] stored, then every `all`-scope id computed in the sweep's
  /// order (sections first, parents last).
  Future<void> storeAndCompute(List<String> files) async {
    for (final file in files) {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(
        recipe,
        sourceSlug: _source,
        contentHash: contentHashOf(recipe),
      );
    }
    for (final id in bulkScopeIds(db, BulkScope.all)) {
      await computeUntilFresh(db, provider, nutritionRecipeOf(db, id)!.recipe);
    }
  }

  Recipe stored(String file) =>
      nutritionRecipeOf(db, loadCorpusRecipe(file).id)!.recipe;

  String idOf(String file) => loadCorpusRecipe(file).id;

  String keyOf(String file, String title) => sectionKeyOf(idOf(file), title);

  String? statusOf(String id) => db.nutritionFor(id)?.status;

  bool fresh(String id) =>
      nutritionIsFresh(db, nutritionRecipeOf(db, id)!.recipe);

  IngredientMatchRow rowAt(String id, int position) =>
      db.ingredientMatchesFor(id).singleWhere((r) => r.position == position);

  /// [parent]'s line [position] picked onto [host]'s section [title]
  /// through the PUT's own function (body `{raw, child, section}`).
  Future<void> pick(String parent, int position, String host, String title) =>
      applyMatchOverride(db, provider, stored(parent), position, {
        'raw': nutritionLines(stored(parent))[position].raw,
        'child': stored(host).slug,
        'section': title,
      });

  /// The banner and the groups agree (v44 N1): Σ finishes = finishable.
  void bannerHolds() {
    final groups = db.nutritionReviewGroups(limit: 100000, offset: 0);
    expect(
      groups.fold<int>(0, (sum, g) => sum + g.finishes),
      db.nutritionReviewFinishable().finishable,
    );
  }

  group(
    'F3: a section decision completes the parents it promises',
    skip: skipIfNoCorpus,
    () {
      test("S5: the corn's line 0 picked onto its own Spicy Old Bay Butter; "
          "crab cakes' Old Bay confirmed with apply_to_all → the receipt names "
          'the corn (never the key), the corn complete and fresh', () async {
        await cachedFood(db, provider, 171331);
        await storeAndCompute([_corn, _crab]);
        final corn = idOf(_corn);
        final key = keyOf(_corn, _oldBayButter);
        expect(statusOf(key), 'partial');
        await pick(_corn, 0, _corn, _oldBayButter);
        expect(rowAt(corn, 0).childRecipeId, key);
        expect(statusOf(corn), 'partial');
        final group = db
            .nutritionReviewGroups(limit: 100, offset: 0)
            .singleWhere((g) => g.itemKey == 'old bay seasoning');
        expect(group.finishes, 1);
        expect([for (final r in group.finishesRecipes) r.id], [corn]);
        bannerHolds();
        final before = db.nutritionReviewFinishable();
        final crab = stored(_crab);
        final line = db
            .ingredientMatchesFor(crab.id)
            .singleWhere((m) => m.raw.contains('Old Bay'));
        final applied = await applyMatchOverride(
          db,
          provider,
          crab,
          line.position,
          {
            'raw': line.raw,
            'confirmed': true,
            'apply_to_all': true,
          },
        );
        final receipt = appliedJson(applied!);
        expect(receipt['completed_recipes'], [corn]);
        expect(receipt['completed'], 1);
        expect(receipt['recipes'], 1, reason: "the section's host, once");
        expect(receipt['lines'], 1);
        expect('$receipt', isNot(contains('#')));
        expect(statusOf(key), 'complete');
        expect(statusOf(corn), 'complete');
        expect(fresh(corn), isTrue, reason: 'its child_stamp re-derived');
        expect(rowAt(corn, 0).childStamp, db.nutritionFor(key)!.computedAt);
        expect(
          rowAt(corn, 0).grams,
          closeTo(
            db.nutritionFor(key)!.totalGrams! * rowAt(corn, 0).childShare!,
            1e-9,
          ),
        );
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        final after = db.nutritionReviewFinishable();
        expect(after.finishable, before.finishable - 1);
        expect(after.open, before.open - 1);
        bannerHolds();
      });

      test("the single PUT: the corn's section line confirmed (?section=) "
          'completes the corn in the same request', () async {
        await cachedFood(db, provider, 171331);
        await storeAndCompute([_corn, _crab]);
        final corn = idOf(_corn);
        final key = keyOf(_corn, _oldBayButter);
        await pick(_corn, 0, _corn, _oldBayButter);
        final stampBefore = db.nutritionFor(key)!.computedAt;
        final section = routeRecipeOf(db, stored(_corn), _oldBayButter);
        final line = db
            .ingredientMatchesFor(key)
            .singleWhere((m) => m.raw.contains('Old Bay'));
        final applied = await applyMatchOverride(
          db,
          provider,
          section,
          line.position,
          {
            'raw': line.raw,
            'confirmed': true,
          },
        );
        expect(applied, isNull, reason: 'no apply_to_all: no receipt');
        expect(db.nutritionFor(key)!.computedAt, isNot(stampBefore));
        expect(statusOf(key), 'complete');
        expect(statusOf(corn), 'complete');
        expect(fresh(corn), isTrue);
        expect(rowAt(corn, 0).childStamp, db.nutritionFor(key)!.computedAt);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        bannerHolds();
      });

      test(
        "another host's parent: roast|5 picked onto chraime's Tabil; Tabil's "
        'caraway line picked with apply_to_all → the receipt names the roast, '
        "never chraime (the decided line's own recipe) nor the key",
        () async {
          provider.noHits = {'caraway seeds'};
          await storeAndCompute([_chraime, _roast]);
          final chraime = idOf(_chraime);
          final roast = idOf(_roast);
          final key = keyOf(_chraime, 'Tabil');
          await pick(_roast, 5, _chraime, 'Tabil');
          expect(rowAt(roast, 5).childRecipeId, key);
          expect(statusOf(key), 'partial');
          expect(statusOf(roast), 'partial');
          expect(statusOf(chraime), 'partial');
          final tabil = routeRecipeOf(db, stored(_chraime), 'Tabil');
          final line = db
              .ingredientMatchesFor(key)
              .singleWhere((m) => m.raw.contains('caraway'));
          final applied = await applyMatchOverride(
            db,
            provider,
            tabil,
            line.position,
            {
              'raw': line.raw,
              'fdc_id': 170918,
              'apply_to_all': true,
            },
          );
          final receipt = appliedJson(applied!);
          expect(receipt['completed_recipes'], [roast]);
          expect(receipt['completed'], 1);
          expect(receipt['recipes'], 0, reason: 'no other caraway line');
          expect(statusOf(key), 'complete');
          expect(statusOf(roast), 'complete');
          expect(statusOf(chraime), 'complete');
          expect(fresh(roast), isTrue);
          expect(fresh(chraime), isTrue);
          expect(rowAt(roast, 5).childStamp, db.nutritionFor(key)!.computedAt);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);

          // The same PUT body again on the now COMPLETE section: the roast
          // was complete before this request, so nothing TURNS complete.
          final again = appliedJson(
            (await applyMatchOverride(
              db,
              provider,
              routeRecipeOf(db, stored(_chraime), 'Tabil'),
              line.position,
              {
                'raw': line.raw,
                'fdc_id': 170918,
                'apply_to_all': true,
              },
            ))!,
          );
          expect(again['completed'], 0);
          expect(again['completed_recipes'], isEmpty);
          expect(statusOf(roast), 'complete');
        },
      );

      test("one host's four sections reached by one apply count ONE recipe; "
          'the parent routed to one of them is re-derived fresh', () async {
        await cachedFood(db, provider, 171331);
        await storeAndCompute([_corn, _crab]);
        final corn = idOf(_corn);
        await pick(_corn, 0, _corn, _oldBayButter);
        // STATED SYNTHESIZED decision: a person picks SR 173410 "Butter,
        // salted" (a recorded answer of "butter salted") on the Basil and
        // Lemon Butter's butter line — every other butter section's line is
        // on 173430 "Butter, without salt", so the apply reaches all four.
        final basil = routeRecipeOf(
          db,
          stored(_corn),
          'Basil and Lemon Butter',
        );
        final line = rowAt(basil.id, 0);
        expect(line.fdcId, 173430);
        final applied = await applyMatchOverride(db, provider, basil, 0, {
          'raw': line.raw,
          'fdc_id': 173410,
          'apply_to_all': true,
        });
        final receipt = appliedJson(applied!);
        expect(receipt['lines'], 4);
        expect(receipt['recipes'], 1, reason: 'the four sections share a host');
        expect(receipt['completed_recipes'], isEmpty);
        expect('$receipt', isNot(contains('#')));
        final key = keyOf(_corn, _oldBayButter);
        expect(rowAt(key, 0).fdcId, 173410);
        expect(rowAt(corn, 0).childStamp, db.nutritionFor(key)!.computedAt);
        expect(fresh(corn), isTrue, reason: 'its routed section re-read');
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test("O3: pork|3 picked onto its Satay Glaze and the chicken's |6 onto "
          "its Coconut-Curry Glaze; the 'red curry paste' group finishes "
          'gado-gado, the chicken and the pork; gado-gado|0 confirmed with '
          "apply_to_all → ONE main-line apply reaches two hosts' sections "
          'and the receipt names both parents (never a key), each stored '
          'complete and fresh', () async {
        // The 'red curry paste' answer's top record, cached as a swept
        // library holds it (snapshot 20 does): a check line reads its
        // portion from the cached detail (15 g a tablespoon).
        await cachedFood(db, provider, 2706388);
        await storeAndCompute([_gadoGado, _pork, _chicken]);
        final gado = idOf(_gadoGado);
        final pork = idOf(_pork);
        final chicken = idOf(_chicken);
        final satay = keyOf(_pork, 'Satay Glaze');
        final curry = keyOf(_chicken, 'Coconut-Curry Glaze');
        await pick(_pork, 3, _pork, 'Satay Glaze');
        await pick(_chicken, 6, _chicken, 'Coconut-Curry Glaze');
        expect(rowAt(pork, 3).childRecipeId, satay);
        expect(rowAt(chicken, 6).childRecipeId, curry);
        for (final id in [satay, curry, pork, chicken, gado]) {
          expect(statusOf(id), 'partial', reason: id);
        }
        final group = db
            .nutritionReviewGroups(limit: 100, offset: 0)
            .singleWhere((g) => g.itemKey == 'red curry paste');
        expect((group.match.recipeId, group.match.position), (gado, 0));
        expect(group.lines, 3);
        expect(group.finishes, 3);
        expect(
          [for (final r in group.finishesRecipes) r.id],
          unorderedEquals([gado, chicken, pork]),
        );
        expect(db.nutritionReviewFinishable(), (finishable: 3, open: 3));
        bannerHolds();

        final applied = await applyMatchOverride(
          db,
          provider,
          stored(_gadoGado),
          0,
          {
            'raw': rowAt(gado, 0).raw,
            'confirmed': true,
            'apply_to_all': true,
          },
        );
        final receipt = appliedJson(applied!);
        expect(
          receipt['completed_recipes'],
          unorderedEquals([pork, chicken]),
          reason: "the promise less the decided line's own recipe",
        );
        expect(receipt['completed'], 2);
        expect(receipt['recipes'], 2, reason: "two hosts' sections");
        expect(receipt['lines'], 2);
        expect('$receipt', isNot(contains('#')));
        for (final id in [satay, curry, pork, chicken, gado]) {
          expect(statusOf(id), 'complete', reason: id);
        }
        expect(fresh(pork), isTrue);
        expect(fresh(chicken), isTrue);
        expect(rowAt(pork, 3).childStamp, db.nutritionFor(satay)!.computedAt);
        expect(
          rowAt(chicken, 6).childStamp,
          db.nutritionFor(curry)!.computedAt,
        );
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        expect(db.nutritionReviewFinishable(), (finishable: 0, open: 0));
        bannerHolds();
      });

      test("a parent's SKIPPED row on the section is left as it is (a skip "
          'reads no child: no stamp, its grams untouched)', () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        final key = keyOf(_chraime, 'Tabil');
        await applyMatchOverride(db, provider, stored(_chraime), 7, {
          'raw': rowAt(chraime, 7).raw,
          'skipped': true,
        });
        final skipped = rowAt(chraime, 7);
        expect(skipped.status, 'skipped');
        expect(skipped.childRecipeId, key, reason: 'the child id is kept');
        expect(skipped.childStamp, isNull);
        final tabil = routeRecipeOf(db, stored(_chraime), 'Tabil');
        final line = db
            .ingredientMatchesFor(key)
            .singleWhere((m) => m.raw.contains('caraway'));
        await applyMatchOverride(db, provider, tabil, line.position, {
          'raw': line.raw,
          'confirmed': true,
        });
        expect(sameMatchRow(rowAt(chraime, 7), skipped), isTrue);
        expect(rowAt(chraime, 7).childStamp, isNull);
        expect(fresh(chraime), isTrue);
      });

      // Closer round 4 (verify4 D1): the re-read derives a parent's rows as
      // its own compute derives them (`sameAmount`) — a person's typed share
      // stands, never re-parsed from the line's words.
      test("F3 e: a person's typed share kept — roast|5 picked onto chraime's "
          "Tabil with share 0.5 (stated); Tabil's caraway line confirmed "
          '(?section=) → the roast re-read at 0.5 of the total, not the '
          "line's parsed 1.0", () async {
        await storeAndCompute([_chraime, _roast]);
        final roast = idOf(_roast);
        final key = keyOf(_chraime, 'Tabil');
        final line5 = nutritionLines(stored(_roast))[5];
        expect(line5.raw, '1 recipe flavored butter (recipes follow)');
        expect(
          parseShare(
            line5.raw,
            line5.amounts,
            routeRecipeOf(db, stored(_chraime), 'Tabil').servings,
          ),
          1.0,
          reason: "the line's own words",
        );
        await applyMatchOverride(db, provider, stored(_roast), 5, {
          'raw': line5.raw,
          'child': stored(_chraime).slug,
          'section': 'Tabil',
          'share': 0.5,
        });
        expect(rowAt(roast, 5).childRecipeId, key);
        expect(rowAt(roast, 5).childShare, 0.5);
        expect(rowAt(roast, 5).grams, closeTo(22.65, 1e-9));
        final stampBefore = db.nutritionFor(key)!.computedAt;
        final tabil = routeRecipeOf(db, stored(_chraime), 'Tabil');
        final line = db
            .ingredientMatchesFor(key)
            .singleWhere((m) => m.raw.contains('caraway'));
        await applyMatchOverride(db, provider, tabil, line.position, {
          'raw': line.raw,
          'confirmed': true,
        });
        expect(db.nutritionFor(key)!.computedAt, isNot(stampBefore));
        final after = rowAt(roast, 5);
        expect(after.childShare, 0.5, reason: "the person's share");
        expect(after.grams, closeTo(22.65, 1e-9));
        expect(
          after.grams,
          closeTo(db.nutritionFor(key)!.totalGrams! * 0.5, 1e-9),
        );
        expect(after.childStamp, db.nutritionFor(key)!.computedAt);
        expect(fresh(roast), isTrue);
      });
    },
  );

  group('F4: the lines view applies pend', skip: skipIfNoCorpus, () {
    test("the GF pizza's psyllium line finishes nothing while its flour blend "
        'is partial — in BOTH views; sort=finishes follows', () async {
      provider.noHits = {'white rice flour', 'cornstarch'};
      await cachedFood(db, provider, 169656);
      await storeAndCompute([_pizza, _cookies]);
      final pizza = idOf(_pizza);
      final blend = keyOf(
        _pizza,
        'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
      );
      expect(statusOf(blend), 'partial');
      final line = db
          .nutritionReviewLines(limit: 1000, offset: 0)
          .singleWhere((l) => l.match.recipeId == pizza);
      expect(line.match.raw, '1½ tablespoons powdered psyllium husk');
      expect(line.bucket, 'check');
      expect(line.match.grams, 12.0);
      expect(line.finishes, 0, reason: 'its recipe waits on the blend');
      final group = db
          .nutritionReviewGroups(limit: 1000, offset: 0)
          .singleWhere((g) => g.match.recipeId == pizza);
      expect(group.finishes, 0);
      final byFinishes = db.nutritionReviewLines(
        limit: 1000,
        offset: 0,
        sort: 'finishes',
      );
      expect(
        byFinishes.singleWhere((l) => l.match.recipeId == pizza).finishes,
        0,
      );
      // Ordered by finishes first: no line badged 0 sits above one badged 1.
      final badges = [for (final l in byFinishes) l.finishes];
      expect(badges, [...badges]..sort((a, b) => b.compareTo(a)));
      bannerHolds();
      // The confirm keeps the pizza partial: the badge was right.
      await applyMatchOverride(
        db,
        provider,
        stored(_pizza),
        line.match.position,
        {
          'raw': line.match.raw,
          'confirmed': true,
        },
      );
      expect(statusOf(pizza), 'partial');
    });

    test('the blend complete (the recorded answers, real data): the same '
        'line finishes the pizza in both views — the arm is pend, not every '
        'parent', () async {
      await cachedFood(db, provider, 169656);
      await storeAndCompute([_pizza, _cookies]);
      final pizza = idOf(_pizza);
      expect(
        statusOf(
          keyOf(
            _pizza,
            'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
          ),
        ),
        'complete',
      );
      final line = db
          .nutritionReviewLines(limit: 1000, offset: 0)
          .singleWhere((l) => l.match.recipeId == pizza);
      expect(line.match.raw, '1½ tablespoons powdered psyllium husk');
      expect(line.finishes, 1);
      expect(
        db
            .nutritionReviewGroups(limit: 1000, offset: 0)
            .singleWhere((g) => g.match.recipeId == pizza)
            .finishes,
        1,
      );
      bannerHolds();
    });
  });

  group(
    "F5: a routed section's edit reads its parent's page stale",
    skip: skipIfNoCorpus,
    () {
      /// chraime's document with Tabil's coriander line removed (STATED
      /// SYNTHESIZED: a section edit), saved through the recipe PUT's path.
      void editTabil() {
        final host = stored(_chraime);
        final result = updateRecipe(db, config, host.id, {
          'subsections': [
            for (final sub in host.subsections)
              (sub.title == 'Tabil'
                      ? sub.copyWith(
                          ingredients: [
                            sub.ingredients!.first.copyWith(
                              items: sub.ingredients!.first.items.sublist(1),
                            ),
                          ],
                        )
                      : sub)
                  .toMap(),
          ],
        });
        expect(result.changed, isTrue);
      }

      Map<String, Object?> page() =>
          nutritionBody(db, stored(_chraime), forAdmin: true);

      test('chraime fresh; Tabil edited → the GET reads stale `inputs`; '
          'the per-recipe compute recomputes Tabil, then chraime, and the GET '
          'reads fresh with the new totals', () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        final key = keyOf(_chraime, 'Tabil');
        expect(rowAt(chraime, 7).childRecipeId, key);
        final kcal = page()['calories_per_serving'];
        expect(page()['status'], 'complete');
        expect(page().containsKey('stale_reason'), isFalse);
        final tabilAt = db.nutritionFor(key)!.computedAt!;

        editTabil();
        expect(
          nutritionStampCurrent(db, stored(_chraime)),
          isTrue,
          reason: "chraime's own inputs did not move",
        );
        expect(db.hasUnderivedRows(chraime), isFalse);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'inputs',
        );
        expect(fresh(chraime), isFalse);
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'inputs');
        expect(page()['calories_per_serving'], kcal, reason: 'not recomputed');
        expect(bulkScopeIds(db, BulkScope.stale), [key, chraime]);

        startRecipeComputeJob(db, provider, stored(_chraime));
        while (recipeComputeJobId(chraime) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final tabil = db.nutritionFor(key)!.computedAt!;
        expect(tabil, isNot(tabilAt), reason: 'Tabil recomputed');
        expect(
          tabil.compareTo(db.nutritionFor(chraime)!.computedAt!),
          lessThanOrEqualTo(0),
          reason: 'Tabil first, then chraime',
        );
        expect(rowAt(chraime, 7).childStamp, tabil);
        expect(page()['status'], 'complete');
        expect(page()['calories_per_serving'], isNot(kcal));
        expect(fresh(chraime), isTrue);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test("ANOTHER recipe's section: roast|5 picked onto chraime's Tabil; "
          "Tabil edited → the roast's GET reads stale `inputs`; the roast's "
          'own compute recomputes Tabil, then the roast', () async {
        await storeAndCompute([_chraime, _roast]);
        final chraime = idOf(_chraime);
        final roast = idOf(_roast);
        final key = keyOf(_chraime, 'Tabil');
        await pick(_roast, 5, _chraime, 'Tabil');
        expect(rowAt(roast, 5).childRecipeId, key);
        Map<String, Object?> roastPage() =>
            nutritionBody(db, stored(_roast), forAdmin: true);
        final kcal = roastPage()['calories_per_serving'];
        expect(roastPage()['status'], 'complete');
        expect(fresh(roast), isTrue);
        final tabilAt = db.nutritionFor(key)!.computedAt!;

        editTabil();
        expect(
          nutritionStampCurrent(db, stored(_roast)),
          isTrue,
          reason: "the roast's own inputs did not move",
        );
        expect(db.hasUnderivedRows(roast), isFalse);
        expect(
          staleSectionsReadBy(db, stored(_roast), ResolverMemo(db)),
          'inputs',
        );
        expect(fresh(roast), isFalse);
        expect(roastPage()['status'], 'stale');
        expect(roastPage()['stale_reason'], 'inputs');
        expect(roastPage()['calories_per_serving'], kcal);

        startRecipeComputeJob(db, provider, stored(_roast));
        while (recipeComputeJobId(roast) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final tabil = db.nutritionFor(key)!.computedAt!;
        expect(tabil, isNot(tabilAt), reason: 'Tabil recomputed');
        expect(
          tabil.compareTo(db.nutritionFor(roast)!.computedAt!),
          lessThanOrEqualTo(0),
          reason: 'Tabil first, then the roast',
        );
        expect(rowAt(roast, 5).childStamp, tabil);
        expect(roastPage()['status'], 'complete');
        expect(roastPage()['calories_per_serving'], isNot(kcal));
        expect(fresh(roast), isTrue);
        expect(
          bulkScopeIds(db, BulkScope.stale),
          [chraime],
          reason: "the roast's job is not chraime's: chraime still waits",
        );
      });

      test('a Tabil decision left underived reads chraime stale `underived` '
          "(waiting on USDA, not an ingredients change); chraime's own line "
          'then removed → `inputs` (its own inputs win)', () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        final key = keyOf(_chraime, 'Tabil');
        final tabil = routeRecipeOf(db, stored(_chraime), 'Tabil');
        final line = db
            .ingredientMatchesFor(key)
            .singleWhere((m) => m.raw.contains('caraway'));
        await applyMatchOverride(db, provider, tabil, line.position, {
          'raw': line.raw,
          'confirmed': true,
        });
        expect(fresh(chraime), isTrue, reason: 'F3: re-derived in the PUT');
        // STATED SYNTHESIZED: the decision's derivation could not run (RULE
        // A's one unhappy outcome) — its `derived_seq` cleared.
        db.clearDerivedSeq(key, [line.position]);
        expect(db.hasUnderivedRows(key), isTrue);
        expect(nutritionStampCurrent(db, stored(_chraime)), isTrue);
        expect(db.hasUnderivedRows(chraime), isFalse);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'underived',
        );
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'underived');

        // STATED SYNTHESIZED EDIT: chraime's own "Lemon wedges" line
        // removed. The recipe's OWN `inputs` wins over its Tabil's
        // `underived` (which still stands).
        final host = stored(_chraime);
        updateRecipe(db, config, host.id, {
          'ingredients': [
            for (final group in host.ingredients)
              group
                  .copyWith(
                    items: [
                      for (final item in group.items)
                        if (item.raw != 'Lemon wedges') item,
                    ],
                  )
                  .toMap(),
          ],
        });
        expect(nutritionStampCurrent(db, stored(_chraime)), isFalse);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'underived',
        );
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'inputs');
      });

      // Closer round 4 (verify4 D5): the page's Recompute (the per-recipe
      // job) computes first a section that is not FRESH — an underived
      // decision as well as an edit — not only one whose stamp moved.
      test(
        'F5 d: a Tabil decision left underived (stated, as F5 b): its '
        "stamp current, chraime stale `underived`; chraime's per-recipe "
        'job re-derives Tabil first → chraime fresh, the GET complete',
        () async {
          await storeAndCompute([_chraime]);
          final chraime = idOf(_chraime);
          final key = keyOf(_chraime, 'Tabil');
          final tabil = routeRecipeOf(db, stored(_chraime), 'Tabil');
          final line = db
              .ingredientMatchesFor(key)
              .singleWhere((m) => m.raw.contains('caraway'));
          await applyMatchOverride(db, provider, tabil, line.position, {
            'raw': line.raw,
            'confirmed': true,
          });
          expect(fresh(chraime), isTrue);
          db.clearDerivedSeq(key, [line.position]);
          expect(db.hasUnderivedRows(key), isTrue);
          expect(
            nutritionStampCurrent(
              db,
              routeRecipeOf(db, stored(_chraime), 'Tabil'),
            ),
            isTrue,
            reason: "Tabil's stamp is current: only its decision waits",
          );
          expect(page()['status'], 'stale');
          expect(page()['stale_reason'], 'underived');

          startRecipeComputeJob(db, provider, stored(_chraime));
          while (recipeComputeJobId(chraime) != null) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            db.hasUnderivedRows(key),
            isFalse,
            reason: 'Tabil computed first',
          );
          expect(
            rowAt(chraime, 7).childStamp,
            db.nutritionFor(key)!.computedAt,
          );
          expect(fresh(chraime), isTrue);
          expect(page()['status'], 'complete');
          expect(page().containsKey('stale_reason'), isFalse);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );

      test("the recipe's OWN decision underived (stated synthesized: its "
          "derived_seq cleared) and its Tabil edited → `inputs` (a section's "
          "`inputs` over the recipe's own `underived`)", () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        await applyMatchOverride(db, provider, stored(_chraime), 0, {
          'raw': rowAt(chraime, 0).raw,
          'confirmed': true,
        });
        db.clearDerivedSeq(chraime, [0]);
        editTabil();
        expect(nutritionStampCurrent(db, stored(_chraime)), isTrue);
        expect(db.hasUnderivedRows(chraime), isTrue);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'inputs',
        );
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'inputs');
      });

      test(
        "two of the roulade's real routed sections: the "
        'Espresso-Mascarpone Cream mid-write (`interrupted`) and the Dark '
        'Chocolate Ganache edited (`inputs`) → the roulade reads `inputs`',
        () async {
          await storeAndCompute([_roulade]);
          final roulade = idOf(_roulade);
          final cream = keyOf(_roulade, 'Espresso-Mascarpone Cream');
          final ganache = keyOf(_roulade, 'Dark Chocolate Ganache');
          expect(rowAt(roulade, 10).childRecipeId, cream);
          expect(rowAt(roulade, 11).childRecipeId, ganache);
          expect(statusOf(roulade), 'complete');
          expect(fresh(roulade), isTrue);
          Map<String, Object?> pageOf(Recipe recipe) =>
              nutritionBody(db, recipe, forAdmin: true);

          final live = db.markComputing(cream);
          // STATED SYNTHESIZED EDIT: the Ganache's lines reversed.
          final host = stored(_roulade);
          final result = updateRecipe(db, config, host.id, {
            'subsections': [
              for (final sub in host.subsections)
                (sub.title == 'Dark Chocolate Ganache'
                        ? sub.copyWith(
                            ingredients: [
                              for (final group in sub.ingredients!)
                                group.copyWith(
                                  items: group.items.reversed.toList(),
                                ),
                            ],
                          )
                        : sub)
                    .toMap(),
            ],
          });
          expect(result.changed, isTrue);
          expect(
            pageOf(
              routeRecipeOf(db, stored(_roulade), 'Espresso-Mascarpone Cream'),
            )['stale_reason'],
            'interrupted',
          );
          expect(
            pageOf(
              routeRecipeOf(db, stored(_roulade), 'Dark Chocolate Ganache'),
            )['stale_reason'],
            'inputs',
          );
          expect(nutritionStampCurrent(db, stored(_roulade)), isTrue);
          expect(
            staleSectionsReadBy(db, stored(_roulade), ResolverMemo(db)),
            'inputs',
          );
          expect(pageOf(stored(_roulade))['stale_reason'], 'inputs');
          db.releaseComputing(cream, owned: live, stale: false);
        },
      );

      test('only what the totals read: a SKIPPED row on the section does not '
          'tie the parent to it', () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        await applyMatchOverride(db, provider, stored(_chraime), 7, {
          'raw': rowAt(chraime, 7).raw,
          'skipped': true,
        });
        editTabil();
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          isNull,
        );
        expect(page()['status'], isNot('stale'));
      });

      test('only what the totals read: a host line held nested_recipe on an '
          'edited section leaves the page fresh (the held line counts '
          'nothing)', () async {
        final corpus = loadCorpusRecipe(_doughnuts);
        const raw = '1 recipe Boston Cream Doughnuts (recipe follows)';
        final parsed = parseIngredientLine(raw);
        db.upsertRecipe(
          corpus.copyWith(
            ingredients: [
              ...corpus.ingredients,
              IngredientGroup(
                items: [
                  IngredientLine(
                    raw: raw,
                    item: parsed.item,
                    prep: parsed.prep,
                    amounts: parsed.amounts,
                  ),
                ],
              ),
            ],
          ),
          sourceSlug: _source,
          contentHash: 'f7',
        );
        for (final id in bulkScopeIds(db, BulkScope.all)) {
          await computeUntilFresh(
            db,
            provider,
            nutritionRecipeOf(db, id)!.recipe,
          );
        }
        final host = stored(_doughnuts);
        final key = sectionKeyOf(host.id, 'Boston Cream Doughnuts');
        final position = nutritionLines(host).length - 1;
        expect(rowAt(host.id, position).hold, nestedRecipeHold);
        expect(rowAt(host.id, position).childRecipeId, key);
        expect(fresh(host.id), isTrue);
        final result = updateRecipe(db, config, host.id, {
          'subsections': [
            for (final sub in host.subsections)
              (sub.title == 'Boston Cream Doughnuts'
                      ? sub.copyWith(
                          ingredients: [
                            sub.ingredients!.first.copyWith(
                              items: sub.ingredients!.first.items.reversed
                                  .toList(),
                            ),
                          ],
                        )
                      : sub)
                  .toMap(),
          ],
        });
        expect(result.changed, isTrue);
        expect(fresh(key), isFalse, reason: 'the section itself is stale');
        expect(
          staleSectionsReadBy(db, stored(_doughnuts), ResolverMemo(db)),
          isNull,
        );
        expect(fresh(host.id), isTrue);
      });

      // Closer round 2 (the verifier's D1 — Run 059 O23): a section not
      // fresh for a reason that is no ingredient change names that reason
      // on its parent's page, read as the section's own page reads it
      // ([staleReasonOf]) — never `inputs`.
      test("O23: mechouia's caraway picked with apply_to_all during an "
          "outage leaves chraime's Tabil stamped waiting on USDA → chraime "
          'reads stale `underived`, as Tabil does', () async {
        await storeAndCompute([_chraime, _mechouia]);
        final chraime = idOf(_chraime);
        final key = keyOf(_chraime, 'Tabil');
        expect(rowAt(chraime, 7).childRecipeId, key);
        final line = rowAt(idOf(_mechouia), 1);
        expect(line.raw, '1½ teaspoons caraway seeds');
        expect(fresh(chraime), isTrue);
        final outage = a.Outage(provider)..down = true;
        final applied = await applyMatchOverride(
          db,
          outage,
          stored(_mechouia),
          1,
          {
            'raw': line.raw,
            'fdc_id': 2710502,
            'grams': 4,
            'apply_to_all': true,
          },
        );
        expect(appliedJson(applied!)['unavailable'], 1);
        expect(
          db.nutritionFor(key)!.ingredientsHash,
          startsWith('unavailable:'),
        );
        expect(
          nutritionBody(
            db,
            routeRecipeOf(db, stored(_chraime), 'Tabil'),
            forAdmin: true,
          )['stale_reason'],
          'underived',
          reason: "Tabil's own page",
        );
        expect(nutritionStampCurrent(db, stored(_chraime)), isTrue);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'underived',
        );
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'underived');
      });

      test('O23: a Tabil writer holding its mark, then one that threw (its '
          'mark released stale) → chraime reads stale `interrupted`, as Tabil '
          'does; the mark released clean → fresh again', () async {
        await storeAndCompute([_chraime]);
        final chraime = idOf(_chraime);
        final key = keyOf(_chraime, 'Tabil');
        Map<String, Object?> tabilPage() => nutritionBody(
          db,
          routeRecipeOf(db, stored(_chraime), 'Tabil'),
          forAdmin: true,
        );
        expect(fresh(chraime), isTrue);
        final live = db.markComputing(key);
        expect(tabilPage()['stale_reason'], 'interrupted');
        expect(page()['stale_reason'], 'interrupted');
        db.releaseComputing(key, owned: live, stale: false);
        expect(fresh(chraime), isTrue);
        expect(page().containsKey('stale_reason'), isFalse);
        final threw = db.markComputing(key);
        db.releaseComputing(key, owned: threw, stale: true);
        expect(
          db.nutritionFor(key)!.ingredientsHash,
          startsWith(SaltDatabase.interruptedStamp),
        );
        expect(tabilPage()['stale_reason'], 'interrupted');
        expect(nutritionStampCurrent(db, stored(_chraime)), isTrue);
        expect(db.hasUnderivedRows(chraime), isFalse);
        expect(
          staleSectionsReadBy(db, stored(_chraime), ResolverMemo(db)),
          'interrupted',
        );
        expect(page()['status'], 'stale');
        expect(page()['stale_reason'], 'interrupted');
      });
    },
  );
}
