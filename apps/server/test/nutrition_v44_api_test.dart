// Matcher v44, step 5 (design_v2 §2 v44.5, P3 §3–§4; S9, S12 (a-i), S13's
// API texts, S14 (a), N1, N4): sections as children on the API — a section
// child and candidate on the wire (`section`, `host_title`, `state`,
// `pickable`), `?section=` on the routes, the PUT's section pick and every
// 422 it answers, the line-local reach, the other-host list read from the
// stored child set, and the review queue's section rows with the parent
// credit the banner shares.
//
// Real corpus recipes over the recorded real FDC answers (FixtureProvider,
// copied --from-db from snapshot 19), never the network; every decision goes
// through the PUT's own function and every body through the routes'
// builders.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/nutrition_review.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _chraime = '1208-chraime.yaml';
const _dough = '0972-basic-double-crust-pie-dough.yaml';
const _pumpkin = '0987-pumpkin-pie.yaml';
const _quiche = '0742-quiche-lorraine.yaml';
const _pecan = '0988-pecan-pie.yaml';
const _lemon = '0989-lemon-meringue-pie.yaml';
const _ham = '0251-glazed-spiral-sliced-ham.yaml';
const _broccoli = '0022-broccoli-cheese-soup.yaml';
const _carrot = '0015-carrot-ginger-soup.yaml';
const _sweetPotato = '0020-sweet-potato-soup.yaml';
const _pizza = '0393-the-best-gluten-free-pizza.yaml';
const _cookies = '0819-gluten-free-chocolate-chip-cookies.yaml';

void main() {
  late Directory tempDir;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v44-api-');
    final config = ServerConfig(
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

  Recipe stored(String file) =>
      db.recipeByIdOrSlug(loadCorpusRecipe(file).id)!.recipe;

  String keyOf(String file, String title) =>
      sectionKeyOf(stored(file).id, title);

  Recipe section(String file, String title) =>
      nutritionRecipeOf(db, keyOf(file, title))!.recipe;

  /// Stores [files] as the importer does and computes every stored id in
  /// the engine's own order (bulkScopeIds: child sections first).
  Future<void> library(List<String> files, {bool compute = true}) async {
    for (final file in files) {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
    }
    if (!compute) {
      return;
    }
    for (final id in bulkScopeIds(db, BulkScope.all)) {
      expect(
        await matchAndCompute(db, provider, nutritionRecipeOf(db, id)!.recipe),
        isNull,
        reason: id,
      );
    }
  }

  String rawAt(Recipe recipe, int position) =>
      nutritionLines(recipe)[position].raw;

  /// A PUT `…/matches/{position}` as the route runs it ([target] is the
  /// recipe or, with `?section=`, its section).
  Future<AppliedToOthers?> put(
    Recipe target,
    int position,
    Map<String, Object?> body,
  ) => applyMatchOverride(db, provider, target, position, {
    'raw': rawAt(target, position),
    ...body,
  });

  Future<Map<String, Object?>> itemOf(Recipe recipe, int position) async =>
      ((await matchesBody(db, provider, recipe))['items']!
              as List<Object?>)[position]!
          as Map<String, Object?>;

  Map<String, Object?> childOf(Map<String, Object?> item) =>
      (item['match']! as Map<String, Object?>)['child']!
          as Map<String, Object?>;

  Matcher refusedWith(String message) => throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  );

  group(
    'the wire: a section child and its candidates [P3 §3]',
    skip: skipIfNoCorpus,
    () {
      test(
        'an own section: slug and title, `section`, no host title',
        () async {
          await library([_chraime]);
          final chraime = stored(_chraime);
          final key = keyOf(_chraime, 'Tabil');
          final item = await itemOf(chraime, 7);
          expect(item['raw'], '1 tablespoon tabil (recipe follows)');
          expect(item['others'], 0);
          final child = childOf(item);
          expect(child, containsPair('state', 'routed'));
          expect(child, containsPair('slug', 'chraime'));
          expect(child, containsPair('title', 'Tabil'));
          expect(child, containsPair('section', 'Tabil'));
          expect(child, containsPair('host_title', null));
          expect(child, containsPair('yield_text', 'MAKES ABOUT ½ CUP'));
          final batch = batchTotalsOf(db.nutritionFor(key)!)['energy']!;
          expect(child['candidates'], [
            {
              'group': 'own_section',
              'slug': 'chraime',
              'title': 'Tabil',
              'section': 'Tabil',
              'note': null,
              'yield_text': 'MAKES ABOUT ½ CUP',
              'kcal': double.parse(batch.toStringAsFixed(2)),
              'kcal_per_serving': double.parse(
                (batch * 0.125 / db.nutritionFor(chraime.id)!.servingBasis!)
                    .toStringAsFixed(2),
              ),
              'current': true,
              'default': false,
              'state': 'ready',
              'pickable': true,
              'host_title': null,
            },
          ]);
          // A member's label names it too (the bare title; no host).
          expect(nutritionBody(db, chraime, forAdmin: false)['includes'], [
            {
              'slug': 'chraime',
              'title': 'Tabil',
              'section': 'Tabil',
              'host_title': null,
              'flag': null,
            },
          ]);
        },
      );

      test(
        "another host's section names its host; a prose one no_ingredients",
        () async {
          await library([_dough, _pumpkin, _lemon]);
          final child = childOf(await itemOf(stored(_pumpkin), 0));
          expect(child, containsPair('state', 'routed'));
          expect(child, containsPair('slug', 'basic-double-crust-pie-dough'));
          expect(
            child,
            containsPair('section', 'Basic Single-Crust Pie Dough'),
          );
          expect(
            child,
            containsPair('host_title', 'Basic Double-Crust Pie Dough'),
          );
          // S14 (a): the host's prose sections are no children — never listed.
          expect(
            [
              for (final c
                  in (child['candidates']! as List<Object?>)
                      .cast<Map<String, Object?>>())
                if (c['group'] == 'other_section')
                  (c['section'], c['state'], c['pickable']),
            ],
            [('Basic Single-Crust Pie Dough', 'ready', true)],
          );
          // RE-PIN (M51 batch, v52, rule PV): the prose reference counts
          // its base, the sibling Basic Single-Crust Pie Dough, flagged (was
          // not_routed, reason no_ingredients, section "Single-Crust Pie
          // Dough for Custard Pies", one partial line).
          final prose = childOf(await itemOf(stored(_lemon), 0));
          expect(prose, containsPair('state', 'routed'));
          expect(prose, containsPair('reason', null));
          expect(
            prose,
            containsPair('section', 'Basic Single-Crust Pie Dough'),
          );
          expect(
            prose,
            containsPair('host_title', 'Basic Double-Crust Pie Dough'),
          );
          final body = nutritionBody(db, stored(_lemon), forAdmin: false);
          expect(body['partial'], isEmpty);
          expect(body['includes'], [
            containsPair('flag', 'approximation'),
          ]);
        },
      );

      test(
        "a pick-own line's own sections: no totals, then ready and picked",
        () async {
          await library([_ham], compute: false);
          final ham = stored(_ham);
          // The recipe alone: its sections are not computed yet.
          expect(await matchAndCompute(db, provider, ham), isNull);
          Future<List<(Object?, Object?, Object?)>> states() async => [
            for (final c
                in (childOf(await itemOf(stored(_ham), 2))['candidates']!
                        as List<Object?>)
                    .cast<Map<String, Object?>>())
              if (c['group'] == 'own_section')
                (c['section'], c['state'], c['pickable']),
          ];
          expect(await states(), [
            ('Maple-Orange Glaze', 'no_totals', false),
            ('Cherry-Port Glaze', 'no_totals', false),
          ]);
          await expectLater(
            put(ham, 2, {'child': ham.slug, 'section': 'Cherry-Port Glaze'}),
            refusedWith(sectionUncomputedMessage),
          );
          for (final title in ['Maple-Orange Glaze', 'Cherry-Port Glaze']) {
            expect(
              await matchAndCompute(db, provider, section(_ham, title)),
              isNull,
            );
          }
          expect(await states(), [
            ('Maple-Orange Glaze', 'ready', true),
            ('Cherry-Port Glaze', 'ready', true),
          ]);
          await put(ham, 2, {
            'child': ham.slug,
            'section': 'Cherry-Port Glaze',
          });
          final item = await itemOf(stored(_ham), 2);
          final child = childOf(item);
          expect(child, containsPair('state', 'routed'));
          expect(child, containsPair('section', 'Cherry-Port Glaze'));
          expect(child, containsPair('host_title', null));
          // Exactly ONE candidate is current: the key, never the host's slug.
          expect(
            [
              for (final c
                  in (child['candidates']! as List<Object?>)
                      .cast<Map<String, Object?>>())
                if (c['current'] == true) c['section'],
            ],
            ['Cherry-Port Glaze'],
          );
          // S9 (a): a section pick is line-local.
          expect(item['others'], 0);
          final row = db
              .ingredientMatchesFor(ham.id)
              .singleWhere((r) => r.position == 2);
          expect(row.childRecipeId, keyOf(_ham, 'Cherry-Port Glaze'));
          expect(row.status, 'overridden');
          expect(row.childShare, 1);
        },
      );

      test('S14 (a), N4: another host is listed only once its section is a '
          'stored child', () async {
        await library([_broccoli, _carrot, _sweetPotato]);
        Future<List<String>> others() async => [
          for (final c
              in (childOf(await itemOf(stored(_broccoli), 13))['candidates']!
                      as List<Object?>)
                  .cast<Map<String, Object?>>())
            if (c['group'] == 'other_section') c['section']! as String,
        ];
        expect(
          rawAt(stored(_broccoli), 13),
          '1 recipe Buttery Croutons (this page)',
        );
        // Carrot-Ginger Soup's routed child is listed; Sweet Potato Soup's
        // "Buttery Rye Croutons" — every word of the item, no child — is not.
        expect(await others(), ['Buttery Croutons']);
        // The source is the stored stamp: once that section is computed it is
        // a child as stored, and listed. (Its "light rye bread" is a search
        // no snapshot holds — not a child, never swept: answered as no hits.)
        provider.pending = {'light rye bread'};
        expect(
          await matchAndCompute(
            db,
            provider,
            section(_sweetPotato, 'Buttery Rye Croutons'),
          ),
          isNull,
        );
        expect(await others(), ['Buttery Croutons', 'Buttery Rye Croutons']);
      });
    },
  );

  group(
    'the PUT: a section pick and its 422s [P3 §4, the copy delta §6]',
    skip: skipIfNoCorpus,
    () {
      test('an own section is picked where `child` is this recipe', () async {
        await library([_chraime]);
        final chraime = stored(_chraime);
        expect(
          await put(chraime, 7, {'child': chraime.slug, 'section': 'Tabil'}),
          isNull,
        );
        final row = db
            .ingredientMatchesFor(chraime.id)
            .singleWhere((r) => r.position == 7);
        expect(row.childRecipeId, keyOf(_chraime, 'Tabil'));
        expect(row.status, 'overridden');
        expect(row.childShare, closeTo(0.125, 1e-6));
        // The same `child` with no section is the recipe itself.
        await expectLater(
          put(chraime, 7, {'child': chraime.slug}),
          refusedWith(selfRecipeMessage),
        );
      });

      test(
        'S15: a pick whose section was retitled names the OLD title',
        () async {
          await library([_chraime]);
          final chraime = stored(_chraime);
          await put(chraime, 7, {'child': chraime.slug, 'section': 'Tabil'});
          // A disclosed synthesized edit (a negative path no corpus document
          // holds): the host saved with its section retitled.
          db.upsertRecipe(
            chraime.copyWith(
              subsections: [
                for (final sub in chraime.subsections)
                  sub.title == 'Tabil' ? sub.copyWith(title: 'Tabil II') : sub,
              ],
            ),
            sourceSlug: _source,
            contentHash: 'retitled',
          );
          final child = childOf(await itemOf(stored(_chraime), 7));
          expect(child, containsPair('state', 'held'));
          expect(child, containsPair('reason', 'missing'));
          // The old title from the stored key: the app's "{old title} is no
          // longer a section of {host title} — choose again".
          expect(child, containsPair('section', 'Tabil'));
          expect(child, containsPair('title', 'Tabil'));
          expect(child, containsPair('slug', 'chraime'));
          expect(child, containsPair('host_title', null));
        },
      );

      test('every refusal, in its words', () async {
        await library([_chraime, _dough, _lemon]);
        final chraime = stored(_chraime);
        await expectLater(
          put(chraime, 7, {'section': 'Tabil'}),
          refusedWith('Pick a recipe first, then its section.'),
        );
        for (final section in <Object>['Tabil II', 'tabil', 3]) {
          await expectLater(
            put(chraime, 7, {'child': chraime.slug, 'section': section}),
            refusedWith('No section with that title in that recipe.'),
            reason: '$section',
          );
        }
        // A section KEY never travels on the wire.
        await expectLater(
          put(chraime, 7, {'child': keyOf(_chraime, 'Tabil')}),
          refusedWith(noSuchRecipeMessage),
        );
        await expectLater(
          put(stored(_lemon), 0, {
            'child': 'basic-double-crust-pie-dough',
            'section': 'Single-Crust Pie Dough for Custard Pies',
          }),
          refusedWith(
            'That section lists no ingredients — it cannot be counted.',
          ),
        );
        // `?section=` on the PUT: a section's line is never made from
        // another recipe (one level is read) — but takes a food decision.
        final tabil = section(_chraime, 'Tabil');
        await expectLater(
          put(tabil, 0, {'child': chraime.slug, 'section': 'Tabil'}),
          refusedWith(
            "Only one level is read — a section's line is not made from "
            'another recipe.',
          ),
        );
        expect(await put(tabil, 0, {'skipped': true}), isNull);
        expect(
          db
              .ingredientMatchesFor(tabil.id)
              .singleWhere((r) => r.position == 0)
              .status,
          'skipped',
        );
        expect(
          sectionUncomputedMessage,
          'That section has no totals yet — compute its recipe first.',
        );
      });

      test(
        '`?section=`: the section, else 404 "No section with that title."',
        () async {
          await library([_chraime]);
          final chraime = stored(_chraime);
          expect(routeRecipeOf(db, chraime, null), same(chraime));
          expect(
            routeRecipeOf(db, chraime, 'Tabil').id,
            keyOf(_chraime, 'Tabil'),
          );
          for (final title in ['Nope', '', 'tabil']) {
            expect(
              () => routeRecipeOf(db, chraime, title),
              throwsA(
                isA<NotFoundException>().having(
                  (e) => e.message,
                  'message',
                  'No section with that title.',
                ),
              ),
            );
          }
          final label = nutritionBody(
            db,
            routeRecipeOf(db, chraime, 'Tabil'),
            forAdmin: false,
          );
          expect(label['status'], 'complete');
          // A section is labelled per batch, basis 1 (P3 §3.4; verify2
          // V1): never its host's SERVES 4 TO 6 (it read 4, 37.25 kcal); the
          // batch is 4 × 37.25.
          expect(
            (
              label['serving_basis'],
              label['basis_kind'],
              label['calories_per_serving'],
            ),
            (1, 'per_batch', 149.01),
          );
          expect(
            db.nutritionFor(keyOf(_chraime, 'Tabil'))!.servingBasis,
            1,
          );
          expect((label['matched_count'], label['total_count']), (3, 3));
          final lines =
              (await matchesBody(
                    db,
                    provider,
                    routeRecipeOf(db, chraime, 'Tabil'),
                  ))['items']!
                  as List<Object?>;
          expect(lines, hasLength(3));
        },
      );
    },
  );

  group('S9 (a): a section pick is line-local', skip: skipIfNoCorpus, () {
    test('a section child reaches nothing; a row on a section is never '
        'reached', () async {
      await library([_dough, _pumpkin, _quiche, _pecan]);
      final pumpkin = stored(_pumpkin);
      final key = keyOf(_dough, 'Basic Single-Crust Pie Dough');
      const itemKey = 'basic single-crust pie dough';
      final excluding = (recipeId: pumpkin.id, position: 0);
      // The rows the exclusion acts on: quiche's and pecan's, on the key.
      expect(
        [
          for (final r in db.undecidedRoutedMatchesForItemKey(
            itemKey,
            excluding: excluding,
          ))
            (r.recipeId, r.childRecipeId),
        ],
        [
          (stored(_quiche).id, key),
          (stored(_pecan).id, key),
        ],
      );
      final memo = ResolverMemo(db);
      expect(
        recipeReach(
          db,
          itemKey,
          childId: key,
          excluding: excluding,
          memo: memo,
        ),
        isEmpty,
      );
      // Not by a LIBRARY recipe's decision either (another child).
      expect(
        recipeReach(
          db,
          itemKey,
          childId: stored(_dough).id,
          excluding: excluding,
          memo: memo,
        ),
        isEmpty,
      );
      expect((await itemOf(pumpkin, 0))['others'], 0);
    });
  });

  group(
    'the queue: section rows, the parent credit, the banner [S12 a-i, '
    'N1]',
    skip: skipIfNoCorpus,
    () {
      // RE-PIN (M47 batch, v49 Q23 (a)): the vehicle was Grilled Corn's
      // Spicy Old Bay Butter, whose Old Bay line now lands no_match with no
      // record — a No match line finishes nothing. Now Roast Beef
      // Tenderloin's (0214) "1 recipe flavored butter (recipes follow)"
      // picked onto its own "Chipotle and Garlic Butter with Lime and
      // Cilantro", whose chipotle line (on 171186, no grams: the No grams
      // bucket, which the amount-first confirm finishes) is the section's
      // one open line: one open line, in a section, finishing a recipe that
      // has none of its own.
      const chipotle = 'Chipotle and Garlic Butter with Lime and Cilantro';
      const tenderloin = '0214-roast-beef-tenderloin.yaml';
      const chipotleKey = 'chipotle chile in adobo sauce';

      int sumOfFinishes() => db
          .nutritionReviewGroups(limit: 100000, offset: 0)
          .fold(0, (sum, g) => sum + g.finishes);

      test('a section row names its host and section; its group credits the '
          'parent; the banner is the sum', () async {
        await library([tenderloin]);
        final host = stored(tenderloin);
        final key = keyOf(tenderloin, chipotle);
        final flagged = db
            .ingredientMatchesFor(key)
            .singleWhere((r) => r.position == 1);
        expect(
          flagged.raw,
          '1 medium chipotle chile in adobo sauce, seeded and minced, with 1 '
          'teaspoon adobo sauce',
        );
        expect((flagged.fdcId, flagged.grams), (171186, null));
        // Before the pick the host's own held line keeps it open: the
        // section's group credits nobody, and the banner still sums.
        var payoff = db.nutritionReviewFinishable();
        expect(payoff.finishable, sumOfFinishes());
        expect(payoff.open, 1, reason: 'the host; a section key is no recipe');
        expect(
          db
              .nutritionReviewGroups(limit: 100, offset: 0)
              .singleWhere((g) => g.itemKey == chipotleKey)
              .finishes,
          0,
        );

        await put(host, 5, {'child': host.slug, 'section': chipotle});
        payoff = db.nutritionReviewFinishable();
        final group = db
            .nutritionReviewGroups(limit: 100, offset: 0)
            .singleWhere((g) => g.itemKey == chipotleKey);
        expect(group.finishes, 1);
        expect(group.lastOpen, 1);
        expect(group.finishesRecipes, [
          (id: host.id, title: 'Roast Beef Tenderloin'),
        ]);
        expect(payoff.finishable, sumOfFinishes());
        expect(payoff.finishable, 1);
        expect(payoff.open, 1);

        // The wire: the HOST as `recipe` (never the key), the section beside
        // it; the item read from the section's own line.
        final body = buildNutritionReview(
          db,
          page: 1,
          limit: 100,
          grouped: true,
        );
        final item = (body['items']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .singleWhere((i) => i['item_key'] == chipotleKey);
        expect(item['recipe'], {
          'id': host.id,
          'slug': host.slug,
          'title': 'Roast Beef Tenderloin',
        });
        expect(item['section'], chipotle);
        expect(item['item'], 'medium chipotle chile in adobo sauce');
        expect(item['finishes'], 1);
        expect(body['finishable'], 1);
        expect(body['open_recipes'], 1);
        // At line grain a section row promises nothing (its last open line
        // finishes a section).
        final line =
            (buildNutritionReview(db, page: 1, limit: 100)['items']!
                    as List<Object?>)
                .cast<Map<String, Object?>>()
                .singleWhere((i) => i['section'] == chipotle);
        expect(line['recipe'], containsPair('id', host.id));
        expect(line['finishes'], 0);
      });

      test('a section with TWO parents: each credited once, and only while '
          'it has no open line of its own', () async {
        // The GF flour blend (the-best-gluten-free-pizza's own section) is
        // the child of the pizza (0.381) and of the cookies (0.190). Since
        // v46 its brown rice flour and potato starch read the cached 'white
        // rice flour' and 'cornstarch' answers and the blend is complete on
        // real data (no two-parent section stays partial): a stated
        // synthesized negative path answers those two recorded searches as
        // FDC's no hits, leaving three of its lines open (white rice flour,
        // brown rice flour, potato starch).
        provider.noHits = {'white rice flour', 'cornstarch'};
        await library([_pizza, _cookies]);
        final pizza = stored(_pizza);
        final cookies = stored(_cookies);
        final blend = section(
          _pizza,
          'The America’s Test Kitchen All-Purpose Gluten-Free Flour Blend',
        );
        expect(
          [
            for (final r in [
              ...db.ingredientMatchesFor(pizza.id),
              ...db.ingredientMatchesFor(cookies.id),
            ])
              if (r.childRecipeId != null) (r.recipeId, r.childRecipeId),
          ],
          [(pizza.id, blend.id), (cookies.id, blend.id)],
        );
        NutritionReviewGroupRow flour() => db
            .nutritionReviewGroups(limit: 100, offset: 0)
            .singleWhere((g) => g.itemKey == 'brown rice flour');
        // A person skips the blend's potato starch and white rice flour: one
        // open line left in the section, but each parent still has its own
        // open line (the pizza's psyllium husk, the cookies' xanthan gum) —
        // credited to nobody.
        // verify44 D2: while the blend is partial, each parent's OWN line's
        // group finishes nothing — its incomplete child keeps it partial
        // whatever that group decides (the pizza's psyllium husk was
        // credited before the fix).
        NutritionReviewGroupRow ownLine(Recipe parent) => db
            .nutritionReviewGroups(limit: 100, offset: 0)
            .singleWhere(
              (g) => g.match.recipeId == parent.id && g.match.position == 2,
            );
        for (final parent in [pizza, cookies]) {
          expect(ownLine(parent).finishes, 0, reason: parent.slug);
          expect(ownLine(parent).lastOpen, 0, reason: parent.slug);
        }
        expect(db.nutritionReviewFinishable().finishable, sumOfFinishes());
        expect(rawAt(blend, 2), '7 ounces (1⅓ cups) potato starch');
        await put(blend, 2, {'skipped': true});
        expect(
          rawAt(blend, 0),
          '24 ounces (4½ cups plus ⅓ cup) white rice flour',
        );
        await put(blend, 0, {'skipped': true});
        expect(flour().lastOpen, 0);
        expect(db.nutritionReviewFinishable().finishable, sumOfFinishes());
        // Their own lines skipped too, both parents wait on the blend's
        // one line alone: ONE group credits TWO recipes, each once.
        expect(rawAt(pizza, 2), '1½ tablespoons powdered psyllium husk');
        expect(rawAt(cookies, 2), '¾ teaspoon xanthan gum');
        await put(pizza, 2, {'skipped': true});
        await put(cookies, 2, {'skipped': true});
        expect(flour().lastOpen, 2);
        // No grams on a no-match line: a decision promises no grams, so it
        // finishes nothing yet (the accepted under-promise).
        expect(flour().finishes, 0);
        final payoff = db.nutritionReviewFinishable();
        expect(payoff.finishable, sumOfFinishes());
        expect(payoff.open, 2, reason: 'the two parents, never the key');
      });
    },
  );
}
