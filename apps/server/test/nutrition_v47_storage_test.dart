// Matcher v47, storage and bulk (the SECTIONS-batch review fixes; Run 061
// Sonnet 5.5 / Run 062 Opus 5.5):
//
// F1 (S1, S2, O1, O5) — a PERSON's pick of a section (a decided row whose
// child is a section key) keeps that section a CHILD whether or not a main
// line routes there: the library-wide child set the bulk GC, order and
// stale scope read, and the per-recipe job's children-first set, are the
// engine's routes ∪ every decided pick whose host still carries the title
// (`pickedSectionKeysOf`). Before, the GC deleted the picked section's
// stamp once its last engine route went, the parent read a gone stamp
// (underived, stale for good) and the re-pick was refused (422).
// F12 (Run 062 critic) — a job's `total` / `done` count RECIPES (a section
// key is computed first and moves neither) and its log names a section by
// "{host slug} · {title}", never its key.
// F10 (S9, O6) — `bulkScopes` reads the library once for the three scopes,
// each scope's selection equal to its own `bulkScopeIds`.
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider),
// never the network; each pick goes through the PUT's own function
// (`applyMatchOverride`, `routeRecipeOf` for `?section=`). STATED
// SYNTHESIZED EDITS (each the negative path that removes an engine route;
// the corpus holds none of them): (a) creamless-creamy-tomato-soup's
// "Classic Croutons" retitled "Buttery Croutons" (a second host carries the
// title — N8 holds broccoli-cheese-soup|13); (b) pumpkin-pie's reference
// line removed; (c) chraime's own tabil line removed; (e) carrot-ginger-
// soup's "Buttery Croutons" retitled "Toasted Croutons" (S15); (job)
// chraime's Tabil lines reversed (a section edit); (F12) the provider
// failing every search (`failWith`, the outage class); (F12 job, closer
// round 3) Tabil's caraway record dropped from the caches and its detail
// failing at food scope (the v28 `FoodFault`), Tabil's lines reversed.
// Closer round 4 (verify4 D2, D3): (F12 skip) no synthesized data — the
// per-recipe job is held mid-search on Tabil by `FixtureProvider.gate` (a
// timing hold) while an `all` sweep runs; (F12 gone) Tabil's lines reversed
// (the (job) edit), then Tabil retitled "Tabil Blend" after the stale sweep
// starts, before its turn (S15's shape, as (e)).

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v28_rule_a_test.dart' as v28;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _broccoli = '0022-broccoli-cheese-soup.yaml';
const _carrot = '0015-carrot-ginger-soup.yaml';
const _tomato = '0014-creamless-creamy-tomato-soup.yaml';
const _sweetPotato = '0020-sweet-potato-soup.yaml';
const _dough = '0972-basic-double-crust-pie-dough.yaml';
const _pumpkin = '0987-pumpkin-pie.yaml';
const _quiche = '1196-simple-cheese-quiche.yaml';
const _chraime = '1208-chraime.yaml';
const _roast = '0214-roast-beef-tenderloin.yaml';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v47-storage-');
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

  /// The corpus recipe [file] as stored now.
  Recipe stored(String file) =>
      nutritionRecipeOf(db, loadCorpusRecipe(file).id)!.recipe;

  String keyOf(String file, String title) =>
      sectionKeyOf(loadCorpusRecipe(file).id, title);

  bool fresh(String file) => nutritionIsFresh(db, stored(file));

  Future<int> sweep(BulkScope scope) async {
    final job = startBulkJob(db, provider, scope: scope);
    expect(job, isNotNull);
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(db.nutritionJob(job!)!['status'], 'done');
    expect(db.nutritionJob(job)!['failed'], 0);
    return job;
  }

  /// [parent]'s line [position] picked onto [host]'s section [title]
  /// through the PUT's own function (body `{raw, child, section}`).
  Future<void> pick(String parent, int position, String host, String title) =>
      applyMatchOverride(db, provider, stored(parent), position, {
        'raw': nutritionLines(stored(parent))[position].raw,
        'child': stored(host).slug,
        'section': title,
      });

  IngredientMatchRow rowAt(String file, int position) => db
      .ingredientMatchesFor(stored(file).id)
      .singleWhere((row) => row.position == position);

  /// [file]'s main ingredient lines without its sub-recipe references,
  /// saved through the recipe edit service (the recipe PUT's path).
  void dropReferences(String file) {
    final recipe = stored(file);
    final result = updateRecipe(db, config, recipe.id, {
      'ingredients': [
        for (final group in recipe.ingredients)
          group
              .copyWith(
                items: [
                  for (final line in group.items)
                    if (!isSubRecipeReference(line.raw)) line,
                ],
              )
              .toMap(),
      ],
    });
    expect(result.changed, isTrue);
  }

  /// [file]'s section [from] retitled [to] through the edit service.
  void retitle(String file, String from, String to) {
    final recipe = stored(file);
    final result = updateRecipe(db, config, recipe.id, {
      'subsections': [
        for (final sub in recipe.subsections)
          (sub.title == from ? sub.copyWith(title: to) : sub).toMap(),
      ],
    });
    expect(result.changed, isTrue);
  }

  group(
    'F1: a decided pick keeps its section a child',
    skip: skipIfNoCorpus,
    () {
      test('(a) O1: broccoli|13 picked onto carrot#Buttery Croutons, then a '
          'second host carries the title (N8) — the stamp survives three '
          'stale sweeps and an all sweep, broccoli reads fresh, the re-pick '
          'is accepted', () async {
        store([_broccoli, _carrot, _tomato]);
        await sweep(BulkScope.all);
        final key = keyOf(_carrot, 'Buttery Croutons');
        expect(rowAt(_broccoli, 13).childRecipeId, key); // The engine's route.
        await pick(_broccoli, 13, _carrot, 'Buttery Croutons');
        expect(rowAt(_broccoli, 13).status, 'overridden');
        expect(fresh(_broccoli), isTrue);
        // STATED SYNTHESIZED EDIT (a).
        retitle(_tomato, 'Classic Croutons', 'Buttery Croutons');
        final line = nutritionLines(stored(_broccoli))[13];
        expect(
          resolveReference(
            db,
            stored(_broccoli),
            line,
            ResolverMemo(db),
          ).section,
          isNull,
          reason: 'N8: two hosts carry the title — the engine routes no more',
        );
        expect(pickedSectionKeysOf(db), {key});
        expect(sectionChildKeysOf(db, stored(_broccoli), ResolverMemo(db)), {
          key,
        });
        for (final scope in [
          BulkScope.stale,
          BulkScope.stale,
          BulkScope.stale,
          BulkScope.all,
        ]) {
          expect(bulkScope(db, scope).children, contains(key));
          await sweep(scope);
          expect(db.nutritionFor(key), isNotNull, reason: '${scope.name} GC');
          expect(fresh(_broccoli), isTrue);
        }
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        await pick(_broccoli, 13, _carrot, 'Buttery Croutons');
        final row = rowAt(_broccoli, 13);
        expect(row.childRecipeId, key);
        expect(row.childStamp, db.nutritionFor(key)!.computedAt);
        expect(fresh(_broccoli), isTrue);
      });

      test("(a') a CONFIRM of the engine's section route is a person's pick "
          'too: it survives N8; a SKIP reads no child — the key is collected '
          'and the skipped parent stays fresh', () async {
        store([_broccoli, _carrot, _tomato]);
        await sweep(BulkScope.all);
        final key = keyOf(_carrot, 'Buttery Croutons');
        final raw = nutritionLines(stored(_broccoli))[13].raw;
        await applyMatchOverride(db, provider, stored(_broccoli), 13, {
          'raw': raw,
          'confirmed': true,
        });
        expect(
          (rowAt(_broccoli, 13).status, rowAt(_broccoli, 13).childRecipeId),
          ('confirmed', key),
        );
        // STATED SYNTHESIZED EDIT (a).
        retitle(_tomato, 'Classic Croutons', 'Buttery Croutons');
        await sweep(BulkScope.stale);
        expect(db.nutritionFor(key), isNotNull);
        expect(fresh(_broccoli), isTrue);
        await applyMatchOverride(db, provider, stored(_broccoli), 13, {
          'raw': raw,
          'skipped': true,
        });
        expect(pickedSectionKeysOf(db), isEmpty);
        await sweep(BulkScope.stale);
        expect(db.nutritionFor(key), isNull);
        // The skipped row reads no stamp: the parent is fresh, nothing waits.
        expect(
          (rowAt(_broccoli, 13).status, rowAt(_broccoli, 13).childStamp),
          ('skipped', null),
        );
        expect(fresh(_broccoli), isTrue);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test(
        '(b) S2: quiche|0 picked onto the pie dough#Basic Single-Crust Pie '
        'Dough, then pumpkin-pie|0 (its only engine route) removed — the '
        'stamp survives, the quiche stays fresh, the re-pick is accepted',
        () async {
          store([_dough, _pumpkin, _quiche]);
          await sweep(BulkScope.all);
          final key = keyOf(_dough, 'Basic Single-Crust Pie Dough');
          expect(rowAt(_pumpkin, 0).childRecipeId, key);
          expect(rowAt(_quiche, 0).childRecipeId, isNull); // Held: generic.
          await pick(_quiche, 0, _dough, 'Basic Single-Crust Pie Dough');
          // STATED SYNTHESIZED EDIT (b).
          dropReferences(_pumpkin);
          final scope = bulkScope(db, BulkScope.stale);
          expect(scope.children, {key});
          // The quiche's pick is the quiche's child, never the pie's.
          expect(
            sectionChildKeysOf(db, stored(_pumpkin), ResolverMemo(db)),
            isEmpty,
          );
          expect(sectionChildKeysOf(db, stored(_quiche), ResolverMemo(db)), {
            key,
          });
          await sweep(BulkScope.stale);
          expect(db.nutritionFor(key), isNotNull);
          expect(fresh(_quiche), isTrue);
          expect(
            rowAt(_quiche, 0).childStamp,
            db.nutritionFor(key)!.computedAt,
          );
          await pick(_quiche, 0, _dough, 'Basic Single-Crust Pie Dough');
          expect(rowAt(_quiche, 0).status, 'overridden');
        },
      );

      test("(c) S1: roast-beef-tenderloin|5 picked onto chraime's Tabil, then "
          "chraime's own tabil line removed — the stamp survives two stale "
          'sweeps, the roast stays fresh and derived', () async {
        store([_chraime, _roast]);
        await sweep(BulkScope.all);
        final key = keyOf(_chraime, 'Tabil');
        await pick(_roast, 5, _chraime, 'Tabil');
        expect(rowAt(_roast, 5).childRecipeId, key);
        // STATED SYNTHESIZED EDIT (c).
        dropReferences(_chraime);
        expect(
          sectionChildKeysOf(db, stored(_chraime), ResolverMemo(db)),
          isEmpty,
        );
        await sweep(BulkScope.stale);
        await sweep(BulkScope.stale);
        expect(db.nutritionFor(key), isNotNull);
        expect(db.hasUnderivedRows(stored(_roast).id), isFalse);
        expect(fresh(_roast), isTrue);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test("the per-recipe job computes a picked section first: Tabil's "
          "lines reversed (stated synthesized edit (job)), the roast's own "
          'compute recomputes Tabil, then the roast', () async {
        store([_chraime, _roast]);
        await sweep(BulkScope.all);
        final key = keyOf(_chraime, 'Tabil');
        await pick(_roast, 5, _chraime, 'Tabil');
        final before = db.nutritionFor(key)!.computedAt;
        final chraime = stored(_chraime);
        // STATED SYNTHESIZED EDIT (job).
        final result = updateRecipe(db, config, chraime.id, {
          'subsections': [
            for (final sub in chraime.subsections)
              (sub.title == 'Tabil'
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
          nutritionIsFresh(db, nutritionRecipeOf(db, key)!.recipe),
          isFalse,
        );
        // The roast's own child set (its rule-PO butters) holds Tabil only
        // through the pick.
        expect(
          sectionChildKeysOf(db, stored(_roast), ResolverMemo(db)),
          contains(key),
        );
        expect(pickedSectionKeysOf(db, recipeId: stored(_roast).id), {key});
        final job = startRecipeComputeJob(db, provider, stored(_roast));
        while (recipeComputeJobId(stored(_roast).id) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(db.nutritionJob(job)!['status'], 'done');
        expect(db.nutritionFor(key)!.computedAt, isNot(before));
        expect(
          nutritionIsFresh(db, nutritionRecipeOf(db, key)!.recipe),
          isTrue,
        );
        expect(rowAt(_roast, 5).childStamp, db.nutritionFor(key)!.computedAt);
        expect(fresh(_roast), isTrue);
      });

      test('(d) O5: an admin ?section= skip stamps a NON-child section, '
          'broccoli|13 picks it — the stamp survives the GC and recompute-all; '
          'unpicked, such a stamp is collected', () async {
        store([_broccoli, _carrot, _sweetPotato]);
        // "light rye bread": a search no snapshot holds (the v44 api pin).
        provider.pending = {'light rye bread'};
        await sweep(BulkScope.all);
        final key = keyOf(_sweetPotato, 'Buttery Rye Croutons');
        expect(bulkScope(db, BulkScope.stale).children, isNot(contains(key)));
        expect(db.nutritionFor(key), isNull);
        final target = routeRecipeOf(
          db,
          stored(_sweetPotato),
          'Buttery Rye Croutons',
        );
        await applyMatchOverride(db, provider, target, 0, {
          'raw': nutritionLines(target)[0].raw,
          'skipped': true,
        });
        expect(db.nutritionFor(key), isNotNull);
        // Unpicked: not a child — a sweep collects the stamp (v44, kept).
        expect(
          db.collectSectionGarbage(bulkScope(db, BulkScope.stale).children),
          [
            key,
          ],
        );
        expect(db.nutritionFor(key), isNull);
        // The admin's skip again (its PUT restamps); then a person picks.
        await applyMatchOverride(db, provider, target, 0, {
          'raw': nutritionLines(target)[0].raw,
          'skipped': true,
        });
        expect(db.nutritionFor(key), isNotNull);
        await pick(_broccoli, 13, _sweetPotato, 'Buttery Rye Croutons');
        expect(bulkScope(db, BulkScope.stale).children, contains(key));
        await sweep(BulkScope.stale);
        expect(db.nutritionFor(key), isNotNull);
        await sweep(BulkScope.all);
        expect(db.nutritionFor(key), isNotNull);
        final label = nutritionBody(db, stored(_broccoli), forAdmin: true);
        expect(label['status'], isNot('stale'));
        expect(
          [
            for (final c in label['includes']! as List<Object?>)
              (c! as Map)['section'],
          ],
          contains('Buttery Rye Croutons'),
        );
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test('(e) S15 stands: a picked section retitled away is dropped and '
          'never resurrected by the pick', () async {
        store([_broccoli, _carrot]);
        await sweep(BulkScope.all);
        final key = keyOf(_carrot, 'Buttery Croutons');
        await pick(_broccoli, 13, _carrot, 'Buttery Croutons');
        expect(pickedSectionKeysOf(db), {key});
        // STATED SYNTHESIZED EDIT (e).
        retitle(_carrot, 'Buttery Croutons', 'Toasted Croutons');
        expect(db.nutritionFor(key), isNull); // S15's drop.
        expect(db.decidedSectionPicks(), [key]); // The person's row stands.
        expect(pickedSectionKeysOf(db), isEmpty);
        expect(bulkScope(db, BulkScope.stale).children, isNot(contains(key)));
        await sweep(BulkScope.stale);
        await sweep(BulkScope.all);
        expect(db.nutritionFor(key), isNull);
        expect(bulkScopeIds(db, BulkScope.all), isNot(contains(key)));
      });
    },
  );

  group(
    'F12: a job counts recipes and never prints a key',
    skip: skipIfNoCorpus,
    () {
      test('a sweep stopped at a section names it "{host slug} · {title}"; '
          'total and done count the recipe, not its section', () async {
        store([_chraime]);
        final key = keyOf(_chraime, 'Tabil');
        expect(bulkScopeIds(db, BulkScope.missing), [key, stored(_chraime).id]);
        expect(bulkCountsBody(db), {
          'missing': 1,
          'stale': 0,
          'all': 1,
          'sections': {'missing': 1, 'stale': 1, 'all': 1},
        });
        // STATED SYNTHESIZED (F12): every search fails (the outage class).
        provider.failWith = 'FoodData Central is unavailable';
        final stopped = startBulkJob(db, provider)!;
        while (bulkJobRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final row = db.nutritionJob(stopped)!;
        expect(row['status'], 'failed');
        expect(row['total'], 1);
        expect(row['done'], 0);
        expect(row['log'], [
          startsWith('stopped at chraime · Tabil: '),
        ]);
        expect('${row['log']}', isNot(contains('#')));
        provider.failWith = null;
        final job = await sweep(BulkScope.missing);
        expect(db.nutritionJob(job)!['total'], 1);
        expect(db.nutritionJob(job)!['done'], 1);
        expect(db.nutritionFor(key), isNotNull);
        expect(jobLogName(db, key), 'chraime · Tabil');
        // The counts body: the recipe, and its section apart.
        expect(bulkCountsBody(db), {
          'missing': 0,
          'stale': 0,
          'all': 1,
          'sections': {'missing': 0, 'stale': 0, 'all': 1},
        });
        expect(jobLogName(db, stored(_chraime).id), stored(_chraime).id);
        expect(recipeCountOf([key, stored(_chraime).id]), 1);
      });

      test("the per-recipe job names a section's FOOD failure "
          '"{host slug} · {title}", never its key: Tabil\'s lines reversed '
          '(stated synthesized edit (job)) and its caraway detail failing at '
          'food scope (the v28 FoodFault)', () async {
        store([_chraime]);
        await sweep(BulkScope.all);
        final key = keyOf(_chraime, 'Tabil');
        final caraway = db
            .ingredientMatchesFor(key)
            .singleWhere((m) => m.raw.contains('caraway'))
            .fdcId!;
        v28.dropFood(config.dbPath, caraway);
        final chraime = stored(_chraime);
        final result = updateRecipe(db, config, chraime.id, {
          'subsections': [
            for (final sub in chraime.subsections)
              (sub.title == 'Tabil'
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
        final fault = v28.FoodFault(
          provider,
          {caraway},
          scope: FailureScope.food,
        );
        final job = startRecipeComputeJob(db, fault, stored(_chraime));
        while (recipeComputeJobId(chraime.id) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final row = db.nutritionJob(job)!;
        expect(fault.asked, 1);
        expect(row['status'], 'done');
        expect(row['log'], ['chraime · Tabil: FoodData Central error 500.']);
      });

      // Closer round 4 (verify4 D2): the sweep's single-flight skip names a
      // section by its host and title too, never its key.
      test('a sweep meeting a section the per-recipe job is computing logs '
          '"chraime · Tabil: skipped, …", never the key; total and done '
          'count the recipe', () async {
        store([_chraime]);
        final chraime = stored(_chraime).id;
        provider.gate = Completer<void>();
        final perRecipe = startRecipeComputeJob(db, provider, stored(_chraime));
        while (provider.searchCalls == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final job = startBulkJob(db, provider, scope: BulkScope.all)!;
        while (bulkJobRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final row = db.nutritionJob(job)!;
        provider.gate!.complete();
        while (recipeComputeJobId(chraime) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(row['log'], [
          'chraime · Tabil: skipped, a compute is already running',
          '$chraime: skipped, a compute is already running',
        ]);
        expect('${row['log']}', isNot(contains('#')));
        expect(row['total'], 1);
        expect(row['done'], 1);
        expect(db.nutritionJob(perRecipe)!['status'], 'done');
      });

      // Closer round 4 (verify4 D3): a section key gone before its turn
      // (deleted mid-job) moves `done` by its step — 0 — as it never moved
      // `total`.
      test('a section key gone mid-sweep (Tabil retitled after the stale '
          'sweep starts, S15) moves neither total nor done', () async {
        store([_chraime]);
        await sweep(BulkScope.all);
        final chraime = stored(_chraime).id;
        final key = keyOf(_chraime, 'Tabil');
        final host = stored(_chraime);
        final result = updateRecipe(db, config, host.id, {
          'subsections': [
            for (final sub in host.subsections)
              (sub.title == 'Tabil'
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
        expect(bulkScopeIds(db, BulkScope.stale), [key, chraime]);
        final job = startBulkJob(db, provider, scope: BulkScope.stale)!;
        retitle(_chraime, 'Tabil', 'Tabil Blend');
        expect(nutritionRecipeOf(db, key), isNull);
        while (bulkJobRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final row = db.nutritionJob(job)!;
        expect(row['total'], 1);
        expect(row['done'], 1);
        expect('${row['log']}', isNot(contains('#')));
      });
    },
  );

  group('F10: bulkScopes', skip: skipIfNoCorpus, () {
    test('one library read: every scope equals its own bulkScopeIds', () async {
      store([_broccoli, _carrot, _chraime, _dough, _pumpkin, _quiche]);
      Future<void> same() async {
        final scopes = bulkScopes(db);
        expect(scopes.keys, BulkScope.values);
        for (final scope in BulkScope.values) {
          expect(scopes[scope], bulkScopeIds(db, scope), reason: scope.name);
        }
      }

      await same(); // Nothing computed.
      await sweep(BulkScope.missing);
      await same(); // Every stamp current.
      dropReferences(_pumpkin);
      expect(bulkScopeIds(db, BulkScope.stale), isNotEmpty);
      await same(); // A stale recipe and its collected child.
    });
  });
}
