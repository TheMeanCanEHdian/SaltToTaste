// Matcher v41, step 3 (design_v3 §2.3): the composite row on the API —
// the matches GET's `child` / `parts` / `flag`, the PUT's `child` / `share`
// and every 422 it answers, the RECIPE apply-to-all twin and its reach, the
// nutrition GET's `includes` / `partial`, and the review queue's
// `choose_recipe` chip (the ONE flagged list, its rank, the SLIM child).
//
// Real corpus recipes over the recorded real FDC answers (FixtureProvider,
// copied --from-db from snapshot 17), never the network; every decision goes
// through the PUT's own function ([applyMatchOverride]) and every body
// through the routes' builders.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/nutrition_review.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

const _allButter = '0973-all-butter-double-crust-pie-dough.yaml';
const _basic = '0972-basic-double-crust-pie-dough.yaml';
const _foolproofDouble = '0974-foolproof-double-crust-pie-dough.yaml';
const _foolproofAllButter =
    '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml';
const _blueberry = '0979-blueberry-pie.yaml';
const _classicApple = '0977-classic-apple-pie.yaml';
const _deepDish = '0978-deep-dish-apple-pie.yaml';
const _sweetCherry = '0981-sweet-cherry-pie.yaml';
const _freeForm = '1005-free-form-apple-tart.yaml';
const _steakTips = '0583-grilled-steak-tips.yaml';
const _herbSauce =
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _steaks = '0184-pan-seared-steaks.yaml';
const _tenderloin = '0234-pan-seared-oven-roasted-pork-tenderloin.yaml';
const _graham = '0977-graham-cracker-crust.yaml';
const _summerBerry = '0980-summer-berry-pie.yaml';
const _brisket = '0595-barbecued-whole-beef-brisket-with-spicy-chili-rub.yaml';
const _indoorChicken = '0129-indoor-pulled-chicken.yaml';
const _pulledPork = '0609-barbecued-pulled-pork.yaml';
const _tartDough = '0994-classic-tart-dough.yaml';
const _indoorPork =
    '0246-indoor-pulled-pork-with-sweet-and-tangy-barbecue-sauce.yaml';
const _keyLime = '0989-key-lime-pie.yaml';
const _coconut = '0991-coconut-cream-pie.yaml';
const _lemonTart = '0994-lemon-tart.yaml';
const _fruitTart = '0997-fresh-fruit-tart-with-pastry-cream.yaml';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v41-api-');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
    // Sweet Cherry Pie's cherry line asks a search no snapshot holds (its
    // pie still routes its dough): answered as FDC's no hits.
    provider = FixtureProvider(pending: {'sweet cherries or frozen cherries'});
  });
  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  Recipe stored(String fileName) =>
      db.recipeByIdOrSlug(loadCorpusRecipe(fileName).id)!.recipe;

  /// Stores [files] as the importer does and computes the [computed] ones
  /// (children first, as the bulk order runs them).
  Future<void> library(List<String> files, {Set<String>? computed}) async {
    for (final file in files) {
      final recipe = loadCorpusRecipe(file);
      db.upsertRecipe(recipe, sourceSlug: _source, contentHash: recipe.id);
    }
    for (final file in files) {
      if (computed == null || computed.contains(file)) {
        expect(await matchAndCompute(db, provider, stored(file)), isNull);
      }
    }
  }

  IngredientMatchRow rowAt(String file, int position) => db
      .ingredientMatchesFor(stored(file).id)
      .singleWhere((row) => row.position == position);

  String rawAt(String file, int position) =>
      nutritionLines(stored(file))[position].raw;

  /// A PUT `…/matches/{position}` as the route runs it.
  Future<AppliedToOthers?> put(
    String file,
    int position,
    Map<String, Object?> body,
  ) => applyMatchOverride(db, provider, stored(file), position, {
    'raw': rawAt(file, position),
    ...body,
  });

  Future<Map<String, Object?>> itemOf(String file, int position) async =>
      ((await matchesBody(db, provider, stored(file)))['items']!
              as List<Object?>)[position]!
          as Map<String, Object?>;

  Matcher refusedWith(String message) => throwsA(
    isA<ValidationException>().having((e) => e.message, 'message', message),
  );

  MatchBucket dartBucket(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  /// The bucket the queue's SQL gives [row] ([SaltDatabase.
  /// nutritionReviewLines] filtered on each bucket): exactly one.
  String sqlBucket(IngredientMatchRow row) {
    final hits = [
      for (final bucket in MatchBucket.values)
        if (db
            .nutritionReviewLines(limit: 100000, offset: 0, bucket: bucket.wire)
            .any(
              (line) =>
                  line.match.recipeId == row.recipeId &&
                  line.match.position == row.position,
            ))
          bucket.wire,
    ];
    expect(hits, hasLength(1));
    return hits.single;
  }

  void bothWays(IngredientMatchRow row, MatchBucket bucket) {
    expect(dartBucket(row), bucket);
    expect(sqlBucket(row), bucket.wire);
  }

  group('the bucket, Dart and SQL alike [§2.3]', skip: skipIfNoCorpus, () {
    test('routed counted; held, a nested pick and a gone child choose '
        'recipe; the marinade check', () async {
      await library([
        _allButter,
        _blueberry,
        _freeForm,
        _steakTips,
        _herbSauce,
        _tenderloin,
        _graham,
        _summerBerry,
      ]);
      bothWays(rowAt(_blueberry, 0), MatchBucket.counted);
      expect(rowAt(_blueberry, 0).gramSource, 'recipe');
      bothWays(rowAt(_freeForm, 5), MatchBucket.chooseRecipe);
      bothWays(rowAt(_steakTips, 0), MatchBucket.check);
      expect(rowAt(_steakTips, 0).hold, discardedRecipeHold);
      // A person's pick of a child itself made from a recipe: accepted,
      // stored held `nested_recipe` (F5).
      await put(_tenderloin, 4, {'child': stored(_herbSauce).slug});
      expect(rowAt(_tenderloin, 4).status, 'overridden');
      expect(rowAt(_tenderloin, 4).hold, nestedRecipeHold);
      bothWays(rowAt(_tenderloin, 4), MatchBucket.chooseRecipe);
      // A Confirm whose child is then deleted: held `choose_recipe`, the
      // person's status kept (N6).
      await put(_summerBerry, 7, {'confirmed': true});
      deleteRecipe(db, config, stored(_graham).id);
      expect(
        await matchAndCompute(db, provider, stored(_summerBerry)),
        isNull,
      );
      expect(rowAt(_summerBerry, 7).status, 'confirmed');
      expect(rowAt(_summerBerry, 7).hold, chooseRecipeHold);
      bothWays(rowAt(_summerBerry, 7), MatchBucket.chooseRecipe);
      // A person's Confirm of the marinade: poured away, counted (N3).
      await put(_steakTips, 0, {'confirmed': true});
      expect(rowAt(_steakTips, 0).hold, discardedRecipeHold);
      bothWays(rowAt(_steakTips, 0), MatchBucket.counted);
    });

    test('ONE flagged list: no literal copy is left in the SQL', () {
      final source = File(
        'lib/src/db/salt_database.dart',
      ).readAsStringSync();
      expect(RegExp(r"'no_match',\s*'no_grams'").allMatches(source), isEmpty);
      expect(
        SaltDatabase.flaggedBucketsSql,
        "'no_match', 'no_grams', 'check', 'choose_recipe'",
      );
      expect(nutritionReviewFlaggedBuckets, same(flaggedBuckets));
      expect(nutritionReviewBucketLabels['choose_recipe'], 'Choose recipe');
    });
  });

  group("the review queue's chip [§2.3, F14]", skip: skipIfNoCorpus, () {
    test('the held tart: Choose recipe, finishes 0, a SLIM child, one '
        'index read a page', () async {
      await library([_freeForm]);
      for (final grouped in [false, true]) {
        resolverIndexReads = 0;
        final body = buildNutritionReview(
          db,
          page: 1,
          limit: 50,
          bucket: 'choose_recipe',
          grouped: grouped,
        );
        final buckets = body['buckets']! as List<Object?>;
        expect(buckets.cast<Map<String, Object?>>().map((b) => b['id']), [
          'no_match',
          'no_grams',
          'check',
          'choose_recipe',
          'skipped',
        ]);
        expect(
          buckets.cast<Map<String, Object?>>().singleWhere(
            (b) => b['id'] == 'choose_recipe',
          ),
          {
            'id': 'choose_recipe',
            'label': 'Choose recipe',
            'count': 1,
            'groups': 1,
          },
        );
        final item =
            (body['items']! as List<Object?>).single! as Map<String, Object?>;
        // The rank slot: a choose_recipe group never decodes as skipped.
        expect(item['bucket'], 'choose_recipe');
        expect(item['position'], 5);
        // A held reference is never promised to a confirm.
        expect(item['finishes'], 0);
        final match = item['match']! as Map<String, Object?>;
        expect(match['hold'], chooseRecipeHold);
        expect(match['child'], {
          'state': 'held',
          'reason': 'missing',
          'name': 'Rustic Tart Dough',
          'slug': null,
          'title': null,
          // v44: a library child names no section and no host.
          'section': null,
          'host_title': null,
          'share_text': '1',
          'default': false,
          'why': 'none',
        });
        expect(
          (match['child']! as Map<String, Object?>).containsKey('candidates'),
          isFalse,
        );
        expect(resolverIndexReads, lessThanOrEqualTo(2));
      }
      final payoff = buildNutritionReview(
        db,
        page: 1,
        limit: 50,
        grouped: true,
      );
      expect(payoff['total'], greaterThanOrEqualTo(1));
      expect(payoff['open_recipes'], 1);
      expect(payoff['finishable'], 0);
    });
  });

  group(
    'the PUT on a reference line [§2.3, A4, N2, F3]',
    skip: skipIfNoCorpus,
    () {
      setUp(
        () => library(
          [
            _allButter,
            _foolproofAllButter,
            _blueberry,
            _freeForm,
            _steakTips,
            _steaks,
            _herbSauce,
          ],
          computed: {_allButter, _blueberry, _freeForm, _steakTips, _herbSauce},
        ),
      );

      test('every 422, its text, and nothing written', () async {
        final routed = rowAt(_blueberry, 0);
        final dough = stored(_allButter).slug;
        final cases = <(String, int, Map<String, Object?>, String)>[
          (
            _blueberry,
            0,
            {'child': dough, 'skipped': true},
            oneDecisionMessage,
          ),
          (
            _blueberry,
            0,
            {'child': dough, 'fdc_id': 170931},
            oneRecipeDecisionMessage,
          ),
          (
            _blueberry,
            0,
            {'child': dough, 'grams': 200},
            oneRecipeDecisionMessage,
          ),
          (
            _blueberry,
            0,
            {'child': dough, 'confirmed': true},
            oneRecipeDecisionMessage,
          ),
          (_blueberry, 0, {'child': 'no-such-recipe'}, noSuchRecipeMessage),
          (_blueberry, 0, {'child': 42}, noSuchRecipeMessage),
          (
            _blueberry,
            0,
            {'child': stored(_blueberry).slug},
            selfRecipeMessage,
          ),
          (_blueberry, 2, {'child': dough}, notAReferenceMessage),
          (
            _blueberry,
            0,
            {'child': stored(_foolproofAllButter).slug},
            childUncomputedMessage,
          ),
          (_blueberry, 0, {'child': dough, 'share': 0}, badShareMessage),
          (_blueberry, 0, {'child': dough, 'share': -1}, badShareMessage),
          (_blueberry, 0, {'child': dough, 'share': 101}, badShareMessage),
          (_blueberry, 0, {'child': dough, 'share': 'half'}, badShareMessage),
          (_blueberry, 0, {'share': 0.5}, shareWithoutChildMessage),
          // A routed row takes no food and no typed grams (F3, N2).
          (_blueberry, 0, {'fdc_id': 170931}, routedMessage),
          (_blueberry, 0, {'grams': 200}, routedMessage),
          (
            _blueberry,
            0,
            {'skipped': true, 'apply_to_all': true},
            needsRecipeDecisionMessage,
          ),
          // A held reference: a recipe or a skip, never a confirm or a food.
          (_freeForm, 5, {'confirmed': true}, chooseRecipeMessage),
          (_freeForm, 5, {'fdc_id': 170931}, chooseRecipeMessage),
          (
            _freeForm,
            5,
            {'child': dough, 'apply_to_all': true},
            lineHoldApplyMessage,
          ),
          // The marinade (A5 a): never noRecordMessage.
          (_steakTips, 0, {'fdc_id': 170931}, marinadeMessage),
          (_steakTips, 0, {'grams': 100}, marinadeMessage),
          (
            _steakTips,
            0,
            {'confirmed': true, 'apply_to_all': true},
            lineHoldApplyMessage,
          ),
          // A reference the engine does not route (served with, A3 a / S14).
          (_herbSauce, 0, {'fdc_id': 170931}, notRoutedMessage),
          (_herbSauce, 0, {'child': dough}, notRoutedMessage),
        ];
        for (final (file, position, body, message) in cases) {
          final before = rowAt(file, position);
          await expectLater(
            put(file, position, body),
            refusedWith(message),
            reason: '$file|$position $body',
          );
          expect(sameMatchRow(rowAt(file, position), before), isTrue);
        }
        expect(sameMatchRow(rowAt(_blueberry, 0), routed), isTrue);
      });

      test('the marinade offers and accepts exactly Skip, Confirm, Choose a '
          'recipe; an unheld food row offers no recipe [F3]', () async {
        const three = {
          HoldDecision.skip,
          HoldDecision.confirm,
          HoldDecision.recipe,
        };
        final marinade = rowAt(_steakTips, 0);
        final actions = holdActionsOf(
          marinade.hold,
          routed: marinade.childRecipeId != null,
        );
        expect(actions.offers, three);
        expect(actions.accepts, three);
        expect(actions.finishes, three);
        expect(actions.decidesLibraryWide, isFalse);
        final food = rowAt(_blueberry, 2);
        expect(food.raw, '6 cups (30 ounces) fresh blueberries');
        expect(food.fdcId, 2346411);
        final unheld = holdActionsOf(
          food.hold,
          routed: food.childRecipeId != null,
        );
        expect(unheld.offers, isNot(contains(HoldDecision.recipe)));
        expect(unheld.accepts, isNot(contains(HoldDecision.recipe)));
        expect(
          ((await itemOf(_blueberry, 2))['match']! as Map)['child'],
          isNull,
        );
        // The routed row reads routedActions: confirm, choose, skip — and it
        // may be applied to others (N2).
        final routed = rowAt(_blueberry, 0);
        expect(
          holdActionsOf(routed.hold, routed: routed.childRecipeId != null),
          same(routedActions),
        );
        expect(routedActions.offers, three);
        expect(routedActions.decidesLibraryWide, isTrue);
        // The marinade's Confirm: poured away, no library-wide decision.
        await put(_steakTips, 0, {'confirmed': true});
        expect(rowAt(_steakTips, 0).status, 'confirmed');
        expect(
          db.decisionFor(lineKeyOf(nutritionLines(stored(_steakTips))[0])),
          isNull,
        );
      });
    },
  );

  group(
    'apply-to-all on a composite row [F4, A1 b, N2]',
    skip: skipIfNoCorpus,
    () {
      const pies = [_blueberry, _classicApple, _deepDish, _sweetCherry];
      setUp(
        () => library([
          _allButter,
          _basic,
          _foolproofDouble,
          ...pies,
        ]),
      );

      test('a Confirm + apply on blueberry-pie|0 reaches the three sister '
          "pies, written as a person's, flags cleared", () async {
        final allButter = stored(_allButter);
        for (final pie in pies) {
          expect(rowAt(pie, 0).childRecipeId, allButter.id);
        }
        expect((await itemOf(_blueberry, 0))['others'], 3);
        expect((await itemOf(_blueberry, 0))['others_lines'], 3);
        // The Confirm alone: the offer the cubit raises reads the routed
        // row's table (`decidesLibraryWide` true) and the count, still 3.
        expect(await put(_blueberry, 0, {'confirmed': true}), isNull);
        final item = await itemOf(_blueberry, 0);
        final match = item['match']! as Map<String, Object?>;
        expect(match['status'], 'confirmed');
        expect(match['flag'], isNull);
        expect(
          holdActionsOf(
            match['hold'] as String?,
            routed: match['child'] != null,
          ).decidesLibraryWide,
          isTrue,
        );
        expect(item['others'], 3);
        // The apply (chosen by the ROW, a Confirm carries no `child`).
        final applied = await put(_blueberry, 0, {
          'confirmed': true,
          'apply_to_all': true,
        });
        expect(applied!.lines, 3);
        expect(applied.recipes, 3);
        expect(applied.failed, 0);
        for (final pie in pies.skip(1)) {
          final row = rowAt(pie, 0);
          expect(row.status, 'overridden', reason: pie);
          expect(row.childRecipeId, allButter.id);
          expect(row.childShare, 1);
          expect(
            row.grams,
            closeTo(db.nutritionFor(allButter.id)!.totalGrams!, 1e-6),
          );
          expect(
            ((await itemOf(pie, 0))['match']! as Map<String, Object?>)['flag'],
            isNull,
          );
          expect(nutritionIsFresh(db, stored(pie)), isTrue, reason: pie);
        }
        // A recipe decision is never an ingredient decision (A1 b).
        expect(db.decisionFor('double crust pie dough'), isNull);
        expect(db.decisionFor(rowAt(_blueberry, 0).itemKey!), isNull);
        expect((await itemOf(_blueberry, 0))['others'], 0);
      });

      test('a sister a person decided first is left out', () async {
        await put(_deepDish, 0, {'child': stored(_basic).slug});
        expect(rowAt(_deepDish, 0).status, 'overridden');
        expect(rowAt(_deepDish, 0).childRecipeId, stored(_basic).id);
        // A recipe pick is never an ingredient decision (A1 b).
        expect(db.decisionFor(rowAt(_deepDish, 0).itemKey!), isNull);
        expect((await itemOf(_blueberry, 0))['others_lines'], 2);
        final applied = await put(_blueberry, 0, {
          'confirmed': true,
          'apply_to_all': true,
        });
        expect(applied!.lines, 2);
        expect(rowAt(_deepDish, 0).childRecipeId, stored(_basic).id);
        expect(
          db.nutritionFor(stored(_deepDish).id)!.caloriesPerServing,
          isNotNull,
        );
      });
    },
  );

  group(
    'the food and recipe reaches never meet [S18]',
    skip: skipIfNoCorpus,
    () {
      test('the real "barbecue sauce" collision', () async {
        await library([_brisket, _indoorChicken, _pulledPork]);
        final chicken = rowAt(_indoorChicken, 7);
        final pork = rowAt(_pulledPork, 4);
        expect(chicken.hold, chooseRecipeHold);
        expect(pork.hold, chooseRecipeHold);
        expect(rowAt(_brisket, 12).fdcId, 174523);
        expect((await itemOf(_brisket, 12))['others'], 0);
        final applied = await put(_brisket, 12, {
          'confirmed': true,
          'apply_to_all': true,
        });
        expect(applied!.lines, 0);
        expect(sameMatchRow(rowAt(_indoorChicken, 7), chicken), isTrue);
        expect(sameMatchRow(rowAt(_pulledPork, 4), pork), isTrue);
        // A recipe apply from a held line: refused (a LINE hold), and the
        // recipe reach holds no food row.
        final brisket = rowAt(_brisket, 12);
        await expectLater(
          put(_indoorChicken, 7, {
            'child': stored(_brisket).slug,
            'apply_to_all': true,
          }),
          refusedWith(lineHoldApplyMessage),
        );
        expect(
          recipeReach(
            db,
            'barbecue sauce',
            childId: stored(_brisket).id,
            excluding: (recipeId: stored(_indoorChicken).id, position: 7),
            memo: ResolverMemo(db),
          ),
          isEmpty,
        );
        expect(sameMatchRow(rowAt(_brisket, 12), brisket), isTrue);
      });
    },
  );

  group(
    'a recipe pick with no share to read [verify3 D1]',
    skip: skipIfNoCorpus,
    () {
      test('refused until the share is sent; then counted at it', () async {
        await library([_indoorPork, _pulledPork]);
        final held = rowAt(_pulledPork, 4);
        expect(held.raw, '2 cups barbecue sauce (recipes follow)');
        expect(held.hold, chooseRecipeHold);
        final pork = stored(_indoorPork);
        // SERVES 6 TO 8: no cup measure, so no share of it the line can read.
        expect(
          parseShare(
            held.raw,
            nutritionLines(stored(_pulledPork))[4].amounts,
            pork.servings,
          ),
          isNull,
        );
        await expectLater(
          put(_pulledPork, 4, {'child': pork.slug}),
          refusedWith(noShareMessage),
        );
        expect(sameMatchRow(rowAt(_pulledPork, 4), held), isTrue);
        expect(rowAt(_pulledPork, 4).hold, chooseRecipeHold);
        bothWays(rowAt(_pulledPork, 4), MatchBucket.chooseRecipe);
        // The share sent: accepted as before.
        expect(
          await put(_pulledPork, 4, {'child': pork.slug, 'share': 0.5}),
          isNull,
        );
        final row = rowAt(_pulledPork, 4);
        expect(row.status, 'overridden');
        expect(row.gramSource, 'recipe');
        expect(row.hold, isNull);
        expect(row.childRecipeId, pork.id);
        expect(row.childShare, 0.5);
        expect(
          row.grams,
          closeTo(db.nutritionFor(pork.id)!.totalGrams! * 0.5, 1e-6),
        );
        bothWays(row, MatchBucket.counted);
      });
    },
  );

  group(
    'an unflagged row on the same child stays out of the reach [§2.3 b]',
    skip: skipIfNoCorpus,
    () {
      for (final (child, parents) in [
        (_graham, [(_summerBerry, 7), (_keyLime, 3), (_coconut, 9)]),
        (_tartDough, [(_lemonTart, 0), (_fruitTart, 7)]),
      ]) {
        test('${parents.first.$1}: others 0, a Confirm + apply lands on '
            'none', () async {
          await library([child, for (final (file, _) in parents) file]);
          final (file, position) = parents.first;
          for (final (parent, at) in parents) {
            final row = rowAt(parent, at);
            expect(row.childRecipeId, stored(child).id, reason: parent);
            expect(row.status, 'auto', reason: parent);
            expect(
              ((await itemOf(parent, at))['match']!
                  as Map<String, Object?>)['flag'],
              isNull,
              reason: parent,
            );
          }
          final item = await itemOf(file, position);
          expect(item['others'], 0);
          expect(item['others_lines'], 0);
          final sisters = [
            for (final (parent, at) in parents.skip(1)) rowAt(parent, at),
          ];
          final applied = await put(file, position, {
            'confirmed': true,
            'apply_to_all': true,
          });
          expect(applied!.lines, 0);
          expect(rowAt(file, position).status, 'confirmed');
          for (final (i, (parent, at)) in parents.skip(1).indexed) {
            expect(rowAt(parent, at).status, 'auto', reason: parent);
            expect(
              sameMatchRow(rowAt(parent, at), sisters[i]),
              isTrue,
              reason: parent,
            );
          }
        });
      }
    },
  );

  group('the GETs [§2.3, F14]', skip: skipIfNoCorpus, () {
    test('matches: child, flag, parts; nutrition: includes, partial', () async {
      await library(
        [
          _allButter,
          _basic,
          _foolproofDouble,
          _foolproofAllButter,
          _blueberry,
          _freeForm,
          _steakTips,
          _steaks,
          _herbSauce,
        ],
        computed: {
          _allButter,
          _basic,
          _foolproofDouble,
          _blueberry,
          _freeForm,
          _steakTips,
          _herbSauce,
        },
      );
      resolverIndexReads = 0;
      final item = await itemOf(_blueberry, 0);
      expect(resolverIndexReads, lessThanOrEqualTo(2));
      final match = item['match']! as Map<String, Object?>;
      expect(
        match['flag'],
        'approximation (the first dough the note names: All-Butter '
        'Double-Crust Pie Dough)',
      );
      expect(match['parts'], isEmpty);
      final child = match['child']! as Map<String, Object?>;
      expect(child['state'], 'routed');
      expect(child['slug'], 'all-butter-double-crust-pie-dough');
      expect(child['default'], isTrue);
      expect(child['why'], 'default');
      expect(child['parent_kind'], 'pie');
      expect(child['kind'], 'dough');
      expect(child['kcal'], 3056.69);
      final candidates = (child['candidates']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        [for (final c in candidates) (c['group'], c['title'])].take(4),
        [
          ('note_named', 'All-Butter Double-Crust Pie Dough'),
          ('note_named', 'Basic Double-Crust Pie Dough'),
          ('note_named', 'Foolproof Double-Crust Pie Dough'),
          ('similar', 'Foolproof All-Butter Dough for Double-Crust Pie'),
        ],
      );
      expect(
        candidates.where((c) => c['group'] == 'other_section'),
        everyElement(containsPair('pickable', false)),
      );

      Map<String, Object?> label(String file) =>
          nutritionBody(db, stored(file), forAdmin: false);
      expect(label(_blueberry)['includes'], [
        {
          'slug': 'all-butter-double-crust-pie-dough',
          'title': 'All-Butter Double-Crust Pie Dough',
          'section': null,
          'host_title': null,
          'flag': 'approximation',
        },
      ]);
      expect(label(_blueberry)['partial'], isEmpty);
      resolverIndexReads = 0;
      final tart = label(_freeForm);
      expect(resolverIndexReads, lessThanOrEqualTo(2));
      expect(tart['includes'], isEmpty);
      expect(tart['partial'], [
        {
          'position': 5,
          'kind': 'held',
          'name': 'Rustic Tart Dough',
          'title': null,
          'matched': null,
          'total': null,
          'reason': 'missing',
        },
      ]);
      expect(label(_steakTips)['partial'], [
        containsPair('reason', 'marinade'),
      ]);
      final herb = (label(_herbSauce)['partial']! as List<Object?>)
          .cast<Map<String, Object?>>();
      // v44: |3 "¼ cup Sauce Base (½ recipe …)" routes to its own section
      // (nutrition_v44_sections_test.dart); only the served-with line stays.
      expect(herb.map((p) => (p['position'], p['kind'], p['reason'])), [
        (0, 'not_routed', 'served_with'),
      ]);
      // A person's Confirm clears the default flag, never the include.
      await put(_blueberry, 0, {'confirmed': true});
      expect(label(_blueberry)['includes'], [
        containsPair('flag', null),
      ]);
      await put(_steakTips, 0, {'confirmed': true});
      expect(label(_steakTips)['partial'], isEmpty);
    });

    test("a partial child: its parent's partial line", () async {
      // A stated composed-from-real-lines exception (tests.md 7.6, as the
      // engine's M16 pin): the fresh fruit tart's real kiwi line appended to
      // Classic Tart Dough makes the child partial.
      await library([_tartDough, _lemonTart], computed: {});
      final dough = stored(_tartDough);
      final kiwi = nutritionLines(loadCorpusRecipe(_fruitTart))[9];
      expect(kiwi.raw, startsWith('2 large kiwis'));
      final group = dough.ingredients.last;
      expect(
        updateRecipe(db, config, dough.id, {
          'ingredients': dough
              .copyWith(
                ingredients: [
                  ...dough.ingredients.take(dough.ingredients.length - 1),
                  group.copyWith(items: [...group.items, kiwi]),
                ],
              )
              .toMap()['ingredients'],
        }).changed,
        isTrue,
      );
      expect(await matchAndCompute(db, provider, stored(_tartDough)), isNull);
      expect(await matchAndCompute(db, provider, stored(_lemonTart)), isNull);
      final child = db.nutritionFor(dough.id)!;
      expect(child.status, 'partial');
      final body = nutritionBody(db, stored(_lemonTart), forAdmin: false);
      expect(body['includes'], [
        {
          'slug': 'classic-tart-dough',
          'title': 'Classic Tart Dough',
          'section': null,
          'host_title': null,
          'flag': 'approximation',
        },
      ]);
      expect(body['partial'], [
        {
          'position': 0,
          'kind': 'child_partial',
          'name': 'Classic Tart Dough',
          'title': 'Classic Tart Dough',
          'matched': child.matchedCount,
          'total': child.totalCount,
          'reason': null,
        },
      ]);
    });
  });
}
