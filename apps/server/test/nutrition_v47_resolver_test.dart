// Real corpus titles are kept verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v47, engine and resolver (the SECTIONS-batch review fixes; Run 061
// Sonnet 5.5 / Run 062 Opus 5.5):
//
// F2 (O2) — whether the section a reference line names lists lines is a
// resolver input: the parent's hash folds the PROSE sections its lines
// resolve to (`proseSectionsReadBy`, only when there is one — every other
// recipe hashes as in v46), so a prose section that gains lines stales its
// parent at once and ONE stale sweep routes it; one that loses them sends
// the parent back to the `no_ingredients` rule row in one sweep.
// F6 (S3) — of several own sections the looser title forms reach, the one
// whose title IS the item wins (routed, never held).
// F7 (S4) — a SECTION's line naming its own host is the `self` rule row
// (not_routed, reason `self`; no child, no stamp): no nested cycle.
// F8 (S7) — on a SECTION's own line no candidate is pickable (the PUT reads
// one level) and no candidate names the section's own host.
// F11 (fleet-1 critic) — two subsections of one recipe sharing a title are
// refused on save, import and scan (422).
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider),
// never the network. STATED SYNTHESIZED EDITS (each a negative path the
// corpus cannot hold): (F2) basic-double-crust-pie-dough's prose "Single-
// Crust Pie Dough for Custard Pies" given its sibling "Basic Single-Crust
// Pie Dough"'s lines, then those lines taken away again; (F2, own host,
// closer round 3) chraime's Tabil emptied (made prose), then given its
// corpus lines back; (F6) red-lentil-kibbeh given a sibling "Harissa
// Yogurt" holding Harissa's lines; (F7)
// yeasted-doughnuts given the main line "1 recipe Boston Cream Doughnuts
// (recipe follows)" (a cycle); (F11) chraime given a second "Tabil" holding
// the first's lines reversed; (F11, closer round 4) chraime given a second
// "Tabil" with NO lines (a prose twin) placed BEFORE the first. F8 needs
// none: pecan-pie's real "Triple Chocolate Chunk Pecan Pie" and
// restaurant-style-herb-sauce's real "Port Wine" variation each hold a real
// reference line.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/library_scan.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _lemon = '0989-lemon-meringue-pie.yaml';
const _dough = '0972-basic-double-crust-pie-dough.yaml';
const _plum =
    '0983-fresh-plum-ginger-pie-with-whole-wheat-lattice-top-crust.yaml';
const _allButter = '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml';
const _chraime = '1208-chraime.yaml';
const _kibbeh = '1176-red-lentil-kibbeh.yaml';
const _doughnuts = '1105-yeasted-doughnuts.yaml';
const _pecan = '0988-pecan-pie.yaml';
const _herbSauce =
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _greenBeans = '0681-blanched-green-beans.yaml';
const _couscous = '0715-simple-israeli-couscous.yaml';
const _farro = '0717-simple-farro.yaml';

/// The prose section lemon-meringue-pie|0 names (S13) and its sibling.
const _custard = 'Single-Crust Pie Dough for Custard Pies';
const _basic = 'Basic Single-Crust Pie Dough';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v47-resolver-');
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

  Recipe stored(String file) =>
      nutritionRecipeOf(db, loadCorpusRecipe(file).id)!.recipe;

  String keyOf(String file, String title) =>
      sectionKeyOf(loadCorpusRecipe(file).id, title);

  bool fresh(String file) => nutritionIsFresh(db, stored(file));

  Future<void> sweep(BulkScope scope) async {
    final job = startBulkJob(db, provider, scope: scope);
    expect(job, isNotNull);
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(db.nutritionJob(job!)!['status'], 'done');
    expect(db.nutritionJob(job)!['failed'], 0);
  }

  IngredientMatchRow rowAt(String file, int position) => db
      .ingredientMatchesFor(stored(file).id)
      .singleWhere((row) => row.position == position);

  /// [file]'s subsection [title] given [ingredients], saved through the
  /// recipe edit service (the recipe PUT's path).
  void setSectionLines(
    String file,
    String title,
    List<IngredientGroup>? ingredients,
  ) {
    final recipe = stored(file);
    final result = updateRecipe(db, config, recipe.id, {
      'subsections': [
        for (final sub in recipe.subsections)
          (sub.title == title ? sub.copyWith(ingredients: ingredients) : sub)
              .toMap(),
      ],
    });
    expect(result.changed, isTrue);
  }

  ReferenceResolution resolve(Recipe recipe, int position) => resolveReference(
    db,
    recipe,
    nutritionLines(recipe)[position],
    ResolverMemo(db),
  );

  group(
    'F2: a prose section that gains or loses lines [O2]',
    skip: skipIfNoCorpus,
    () {
      test(
        'gains lines (stated synthesized edit: its sibling’s lines) → the '
        'parent reads stale at once and ONE stale sweep routes it; the '
        'lines taken away again (the corpus’s own prose) → ONE stale sweep '
        'back to its PV base (v52; was the no_ingredients rule row)',
        () async {
          store([_lemon, _dough]);
          final key = keyOf(_dough, _custard);
          final base = keyOf(_dough, _basic);
          final lemonId = stored(_lemon).id;
          await sweep(BulkScope.all);
          var row = rowAt(_lemon, 0);
          // RE-PIN (M51 batch, v52, rule PV): the prose section's line counts
          // its BASE, the sibling Basic Single-Crust Pie Dough, 302.1 g (was
          // the no_ingredients rule row, 0 g); the fold still lists the prose
          // section.
          expect(row.grams, 302.1);
          expect(row.childRecipeId, base);
          expect(row.description, isNull);
          expect(proseSectionsReadBy(stored(_lemon), ResolverMemo(db)), [key]);
          expect(db.nutritionFor(key), isNull);
          expect(fresh(_lemon), isTrue);

          final corpusDough = loadCorpusRecipe(_dough);
          final basic = corpusDough.subsections.singleWhere(
            (s) => s.title == _basic,
          );
          setSectionLines(_dough, _custard, basic.ingredients);
          // The page reads stale with no sweep: the hash moved (the fold).
          expect(
            proseSectionsReadBy(stored(_lemon), ResolverMemo(db)),
            isEmpty,
          );
          expect(fresh(_lemon), isFalse);
          expect(bulkScopeIds(db, BulkScope.stale), [key, lemonId]);
          await sweep(BulkScope.stale);
          // v52: the base, no child of anything now, is collected.
          expect(db.nutritionFor(base), isNull);
          final section = db.nutritionFor(key)!;
          row = rowAt(_lemon, 0);
          expect(row.childRecipeId, key);
          expect(row.childShare, 1.0);
          expect(row.childStamp, section.computedAt);
          expect(row.hold, isNull);
          expect(row.status, 'auto');
          expect(section.totalGrams, 302.1);
          expect(row.grams, section.totalGrams! * 1.0);
          expect(db.nutritionFor(lemonId)!.status, 'complete');
          expect(fresh(_lemon), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);

          final prose = corpusDough.subsections.singleWhere(
            (s) => s.title == _custard,
          );
          setSectionLines(_dough, _custard, prose.ingredients);
          expect(proseSectionsReadBy(stored(_lemon), ResolverMemo(db)), [key]);
          expect(fresh(_lemon), isFalse);
          // The key is no child now (its sweep collects it); the parent is
          // stale by its own hash in the same scope. RE-PIN (M51 batch, v52,
          // rule PV): the base is a child again, unstamped since its
          // collection, so it leads the scope (was [lemonId] alone).
          expect(bulkScopeIds(db, BulkScope.stale), [base, lemonId]);
          await sweep(BulkScope.stale);
          row = rowAt(_lemon, 0);
          // RE-PIN (M51 batch, v52, rule PV): back to its base (was back to
          // the no_ingredients rule row: 0 g, no child, no stamp).
          expect(row.grams, 302.1);
          expect(row.childRecipeId, base);
          expect(row.childStamp, db.nutritionFor(base)!.computedAt);
          expect(row.description, isNull);
          expect(db.nutritionFor(key), isNull);
          expect(fresh(_lemon), isTrue);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );

      test('the per-recipe compute routes it too: the gained section first, '
          'then the parent (stated synthesized edit as above)', () async {
        store([_lemon, _dough]);
        final key = keyOf(_dough, _custard);
        await sweep(BulkScope.all);
        final basic = loadCorpusRecipe(
          _dough,
        ).subsections.singleWhere((s) => s.title == _basic);
        setSectionLines(_dough, _custard, basic.ingredients);
        expect(sectionChildKeysOf(db, stored(_lemon), ResolverMemo(db)), {key});
        final job = startRecipeComputeJob(db, provider, stored(_lemon));
        while (recipeComputeJobId(stored(_lemon).id) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(db.nutritionJob(job)!['status'], 'done');
        expect(rowAt(_lemon, 0).childRecipeId, key);
        expect(rowAt(_lemon, 0).childStamp, db.nutritionFor(key)!.computedAt);
        expect(fresh(_lemon), isTrue);
      });

      test("an OWN prose section (stated synthesized edit: chraime's Tabil "
          'emptied, then given its corpus lines back) folds too: chraime '
          'reads stale at once and ONE stale sweep routes |7', () async {
        store([_chraime]);
        final key = keyOf(_chraime, 'Tabil');
        final chraimeId = stored(_chraime).id;
        final tabil = loadCorpusRecipe(
          _chraime,
        ).subsections.singleWhere((s) => s.title == 'Tabil');
        setSectionLines(_chraime, 'Tabil', null);
        await sweep(BulkScope.all);
        var row = rowAt(_chraime, 7);
        expect(row.grams, 0);
        expect(row.childRecipeId, isNull);
        expect(row.description, subRecipeNote);
        expect(proseSectionsReadBy(stored(_chraime), ResolverMemo(db)), [key]);
        expect(fresh(_chraime), isTrue);

        setSectionLines(_chraime, 'Tabil', tabil.ingredients);
        expect(
          proseSectionsReadBy(stored(_chraime), ResolverMemo(db)),
          isEmpty,
        );
        expect(fresh(_chraime), isFalse);
        expect(bulkScopeIds(db, BulkScope.stale), [key, chraimeId]);
        await sweep(BulkScope.stale);
        row = rowAt(_chraime, 7);
        expect(row.childRecipeId, key);
        expect(row.childStamp, db.nutritionFor(key)!.computedAt);
        expect(row.hold, isNull);
        expect(fresh(_chraime), isTrue);
        expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      });

      test('the two real prose parents; a recipe reading no prose section '
          'hashes as v46 did (update the literal with a matcher bump)', () {
        store([_lemon, _dough, _plum, _allButter, _chraime]);
        expect(proseSectionsReadBy(stored(_lemon), ResolverMemo(db)), [
          keyOf(_dough, _custard),
        ]);
        expect(proseSectionsReadBy(stored(_plum), ResolverMemo(db)), [
          keyOf(_allButter, 'Foolproof Whole-Wheat Dough for Double-Crust Pie'),
        ]);
        // chraime reads its own Tabil (a section WITH lines): no fold. The
        // literal is its stamp in the v46 replay of snapshot 20.
        expect(
          proseSectionsReadBy(stored(_chraime), ResolverMemo(db)),
          isEmpty,
        );
        // RE-PIN (M59 batch, v58, matcherVersion 57): its stamp at
        // matcherVersion 57 (was c85f3025…, the M58 stamp at matcherVersion
        // 56; the version alone moves it — the base tree with only the bump
        // gives this literal).
        // RE-PIN (M60 batch, v59, matcherVersion 58): its stamp at
        // matcherVersion 58 (was 2b3bd4e6…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        // RE-PIN (M61 batch, v60, matcherVersion 59): its stamp at
        // matcherVersion 59 (was c99926ab…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        // RE-PIN (M62 batch, v61, matcherVersion 60): its stamp at
        // matcherVersion 60 (was ad0bf035…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        // RE-PIN (M63 batch, v62, matcherVersion 61): its stamp at
        // matcherVersion 61 (was 20642317…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        // RE-PIN (M64 batch, v63, matcherVersion 62): its stamp at
        // matcherVersion 62 (was e303a776…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        // RE-PIN (M65 batch, v64, matcherVersion 63): its stamp at
        // matcherVersion 63 (was c4b3f185…; the version alone moves it —
        // the base tree with only the bump gives this literal).
        expect(
          ingredientsHashOf(stored(_chraime), ResolverMemo(db)),
          '41969b8cc583a6d91d49f6d951b5223831a3a68e067ac2771b20671e7ab2d884',
        );
        // lemon's moved off its v46 stamp (the fold) — once, on deploy.
        expect(
          ingredientsHashOf(stored(_lemon), ResolverMemo(db)),
          isNot(
            'c3ab0b3beb8920345d2987ba05dd04d1ce9a768df0b15b95b697cd5856350952',
          ),
        );
      });
    },
  );

  test(
    'F2 cost: the fold reads the compute’s and the GET’s own resolver memo '
    '— lemon (another host’s section: both indexes) at most two index '
    'reads per compute and per label [F14]',
    () async {
      store([_lemon, _dough]);
      await sweep(BulkScope.all);
      resolverIndexReads = 0;
      await matchAndCompute(db, provider, stored(_lemon));
      expect(resolverIndexReads, 2);
      resolverIndexReads = 0;
      nutritionBody(db, stored(_lemon), forAdmin: true);
      expect(resolverIndexReads, 2);
    },
    skip: skipIfNoCorpus,
  );

  group(
    'F6: the exact own title wins over a looser sibling [S3]',
    skip: skipIfNoCorpus,
    () {
      test('red-lentil-kibbeh|4 "2 tablespoons harissa" (A9) routes to Harissa '
          'at 0.25 — real, and beside a stated synthesized "Harissa Yogurt" '
          '(whose title starts with the item: a looser form)', () async {
        final corpus = loadCorpusRecipe(_kibbeh);
        final harissa = corpus.subsections.singleWhere(
          (s) => s.title == 'Harissa',
        );
        final key = sectionKeyOf(corpus.id, 'Harissa');
        void check(Recipe host) {
          final line = nutritionLines(host)[4];
          expect(line.raw, startsWith('2 tablespoons harissa'));
          expect(namesOwnSection(host, line), isTrue);
          final found = resolve(host, 4);
          expect(found.kind, ReferenceKind.routed);
          expect(found.childId, key);
          expect(found.share, closeTo(0.25, 1e-6));
          expect(sectionChildKeysOf(db, host, ResolverMemo(db)), contains(key));
        }

        store([_kibbeh]);
        check(stored(_kibbeh));
        final edited = corpus.copyWith(
          subsections: [
            ...corpus.subsections,
            Subsection(
              title: 'Harissa Yogurt',
              servings: 'MAKES 1 CUP',
              ingredients: harissa.ingredients,
              steps: const [],
            ),
          ],
        );
        db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'f6');
        final host = stored(_kibbeh);
        check(host);
        // Both stay listed for a person.
        expect(
          [
            for (final c in referenceCandidates(
              host,
              nutritionLines(host)[4],
              ResolverMemo(db),
            ))
              if (c.group == 'own_section') c.section,
          ],
          ['Harissa', 'Harissa Yogurt'],
        );
        // The row the engine writes (no FDC: the reference row alone).
        final row = referenceRowFor(
          db,
          host,
          4,
          nutritionLines(host)[4],
          ResolverMemo(db),
        );
        expect(row.childRecipeId, key);
        expect(row.childShare, closeTo(0.25, 1e-6));
        expect(row.hold, isNull);
      });
    },
  );

  group(
    'F7: a section line naming its own host is `self` [S4]',
    skip: skipIfNoCorpus,
    () {
      test('the corpus’s seven such lines (every one in a non-child section) '
          'resolve self', () {
        store([_greenBeans, _couscous, _farro, _doughnuts]);
        final got = <String>[];
        for (final file in [_greenBeans, _couscous, _farro, _doughnuts]) {
          final host = stored(file);
          for (final sub in host.subsections) {
            final section = sectionRecipeOf(host, sub);
            for (final (i, line) in nutritionLines(section).indexed) {
              if (subRecipeRowFor(section, i, line) != null &&
                  resolve(section, i).kind == ReferenceKind.self) {
                got.add('${host.slug}#${sub.title}|$i');
              }
            }
          }
        }
        expect(got, [
          'blanched-green-beans#Green Beans with Sautéed Shallots and Vermouth|2',
          'blanched-green-beans#Green Beans with Toasted Hazelnuts and Browned Butter|3',
          'simple-israeli-couscous#Israeli Couscous with Lemon, Mint, Peas, Feta, and Pickled Shallots|8',
          'simple-israeli-couscous#Israeli Couscous with Tomatoes, Olives, and Ricotta Salata|4',
          'simple-farro#Farro Salad with Asparagus, Sugar Snap Peas, and Tomatoes|7',
          'simple-farro#Warm Farro with Lemon and Herbs|4',
          'yeasted-doughnuts#Boston Cream Doughnuts|0',
        ]);
      });

      test('its row is the 0 g rule row with no child; the wire reads '
          'not_routed `self`', () async {
        store([_doughnuts]);
        // The host computed: its library candidate has stored totals.
        await sweep(BulkScope.all);
        final section = routeRecipeOf(
          db,
          stored(_doughnuts),
          'Boston Cream Doughnuts',
        );
        await matchAndCompute(db, provider, section);
        final row = db
            .ingredientMatchesFor(section.id)
            .singleWhere((r) => r.position == 0);
        expect(row.raw, '1 recipe Yeasted Doughnuts (this page)');
        expect(row.grams, 0);
        expect(row.childRecipeId, isNull);
        expect(row.childStamp, isNull);
        expect(row.description, subRecipeNote);
        final item =
            ((await matchesBody(db, provider, section))['items']! as List).first
                as Map<String, Object?>;
        final child =
            (item['match']! as Map<String, Object?>)['child']!
                as Map<String, Object?>;
        expect(child['state'], 'not_routed');
        expect(child['reason'], 'self');
        // F8 too: the host offered as a library candidate on its own
        // section's line — stored totals, never pickable there.
        final host = (child['candidates']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((c) => c['title'] == 'Yeasted Doughnuts');
        expect(host['group'], 'library');
        expect(host['kcal'], isNotNull);
        expect(host['pickable'], isFalse);
        final partial =
            nutritionBody(db, section, forAdmin: true)['partial']! as List;
        expect(partial.first, containsPair('reason', 'self'));
      });

      test(
        'the stated synthesized cycle (the host given "1 recipe Boston Cream '
        'Doughnuts (recipe follows)") converges: the host line held nested, '
        'the section’s line self; a recompute of either settles in one '
        'sweep',
        () async {
          final corpus = loadCorpusRecipe(_doughnuts);
          const raw = '1 recipe Boston Cream Doughnuts (recipe follows)';
          final parsed = parseIngredientLine(raw);
          final edited = corpus.copyWith(
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
          );
          db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'f7');
          final host = stored(_doughnuts);
          final position = nutritionLines(host).length - 1;
          final key = sectionKeyOf(host.id, 'Boston Cream Doughnuts');
          expect(resolve(host, position).kind, ReferenceKind.nested);
          expect(resolve(host, position).childId, key);
          await sweep(BulkScope.all);
          expect(rowAt(_doughnuts, position).hold, nestedRecipeHold);
          expect(
            rowAt(_doughnuts, position).childStamp,
            db.nutritionFor(key)!.computedAt,
          );
          final sectionRow = db
              .ingredientMatchesFor(key)
              .singleWhere((r) => r.position == 0);
          expect(sectionRow.childRecipeId, isNull);
          expect(sectionRow.childStamp, isNull);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
          // The section recomputed: the host reads it again, then nothing does.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await matchAndCompute(
            db,
            provider,
            nutritionRecipeOf(db, key)!.recipe,
          );
          expect(bulkScopeIds(db, BulkScope.stale), [host.id]);
          await sweep(BulkScope.stale);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
          await sweep(BulkScope.stale);
          expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
        },
      );
    },
  );

  group(
    'F8: a section’s own line offers no pick [S7]',
    skip: skipIfNoCorpus,
    () {
      test('pecan-pie’s "Triple Chocolate Chunk Pecan Pie" line 0 (real) '
          'routes to the pie dough’s Basic Single-Crust section: every '
          'candidate unpickable, the PUT refuses; the host’s own line 0 keeps '
          'its pick', () async {
        store([_pecan, _dough]);
        await sweep(BulkScope.all);
        final pecan = stored(_pecan);
        final section = routeRecipeOf(
          db,
          pecan,
          'Triple Chocolate Chunk Pecan Pie',
        );
        await matchAndCompute(db, provider, section);
        Future<List<Map<String, Object?>>> candidates(Recipe recipe) async {
          final item =
              ((await matchesBody(db, provider, recipe))['items']! as List)
                      .first
                  as Map<String, Object?>;
          final child =
              (item['match']! as Map<String, Object?>)['child']!
                  as Map<String, Object?>;
          return (child['candidates']! as List).cast<Map<String, Object?>>();
        }

        final onSection = await candidates(section);
        expect(onSection, isNotEmpty);
        expect(onSection, everyElement(containsPair('pickable', false)));
        final basic = onSection.singleWhere((c) => c['section'] == _basic);
        expect(basic['current'], isTrue);
        // Another host's section keeps naming its host.
        expect(basic['host_title'], 'Basic Double-Crust Pie Dough');
        await expectLater(
          applyMatchOverride(db, provider, section, 0, {
            'raw': nutritionLines(section)[0].raw,
            'child': stored(_dough).slug,
            'section': _basic,
          }),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              sectionLineChildMessage,
            ),
          ),
        );
        final onHost = await candidates(pecan);
        expect(
          onHost.singleWhere((c) => c['section'] == _basic)['pickable'],
          isTrue,
        );
      });

      test(
        'restaurant-style-herb-sauce’s Port Wine variation line 3 (real) '
        'routes to its OWN host’s "Sauce Base": no host_title, no pick',
        () async {
          store([_herbSauce]);
          final host = stored(_herbSauce);
          final base = routeRecipeOf(db, host, 'Sauce Base');
          await matchAndCompute(db, provider, base);
          final section = routeRecipeOf(
            db,
            host,
            'Restaurant-Style Port Wine Sauce for Pan-Seared Steaks',
          );
          await matchAndCompute(db, provider, section);
          final item =
              ((await matchesBody(db, provider, section))['items']! as List)
                  .cast<Map<String, Object?>>()
                  .singleWhere((i) => i['position'] == 3);
          final child =
              (item['match']! as Map<String, Object?>)['child']!
                  as Map<String, Object?>;
          expect(child['state'], 'routed');
          expect(child['section'], 'Sauce Base');
          expect(child['host_title'], isNull);
          final candidate = (child['candidates']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((c) => c['section'] == 'Sauce Base');
          expect(candidate['group'], 'other_section');
          expect(candidate['host_title'], isNull);
          expect(candidate['pickable'], isFalse);
        },
      );
    },
  );

  group(
    'F11: two sections of one title are refused [fleet-1 critic]',
    skip: skipIfNoCorpus,
    () {
      const message =
          'Two sections share the title "Tabil" — give each its own title.';
      // chraime with a second "Tabil" (stated synthesized: the first's lines
      // reversed).
      Recipe twinned(Recipe recipe) {
        final tabil = recipe.subsections.singleWhere((s) => s.title == 'Tabil');
        return recipe.copyWith(
          subsections: [
            ...recipe.subsections,
            tabil.copyWith(
              ingredients: [
                IngredientGroup(
                  items: [
                    for (final g in tabil.ingredients!) ...g.items,
                  ].reversed.toList(),
                ),
              ],
            ),
          ],
        );
      }

      Matcher refused() => throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', message),
      );

      test('the recipe PUT and create refuse it; nothing is stored', () {
        store([_chraime]);
        final before = db.contentHashOf(stored(_chraime).id);
        expect(duplicateSectionTitleMessage('Tabil'), message);
        expect(
          () => updateRecipe(db, config, stored(_chraime).id, {
            'subsections': [
              for (final s in twinned(stored(_chraime)).subsections) s.toMap(),
            ],
          }),
          refused(),
        );
        expect(db.contentHashOf(stored(_chraime).id), before);
        final doc = twinned(loadCorpusRecipe(_chraime)).toMap();
        expect(
          () => createRecipe(db, config, {
            for (final key in editableRecipeKeys)
              if (doc.containsKey(key)) key: doc[key],
          }),
          refused(),
        );
        // The import's and the scan's gate.
        expect(
          () => validateRecipeDocument(twinned(loadCorpusRecipe(_chraime))),
          refused(),
        );
        expect(
          () => validateRecipeDocument(loadCorpusRecipe(_chraime)),
          returnsNormally,
        );
      });

      test('the library scan skips a hand-edited file holding one, the stored '
          'recipe kept', () {
        final doc = loadCorpusRecipe(_chraime).toMap();
        final created = createRecipe(db, config, {
          for (final key in editableRecipeKeys)
            if (doc.containsKey(key)) key: doc[key],
        }).recipe;
        File(
          exportPathFor(config, manualSourceSlug, created.id),
        ).writeAsStringSync(RecipeYamlCodec.encode(twinned(created)));
        final report = scanLibrary(db: db, config: config);
        expect(report.skipped.single.reason, 'fails validation: $message');
        expect(
          db
              .recipeByIdOrSlug(created.id)!
              .recipe
              .subsections
              .where((s) => s.title == 'Tabil'),
          hasLength(1),
        );
      });

      // Closer round 4 (verify4 D4): the rule holds for any two titled
      // subsections — a twin with no lines too, the harmful shape when it
      // comes first (`sectionOf` takes the first: 0 g while the doc lists
      // lines).
      test('a twin with NO lines (a prose section, placed first) is refused '
          'too; nothing is stored', () {
        store([_chraime]);
        Recipe proseFirst(Recipe recipe) {
          final tabil = recipe.subsections.singleWhere(
            (s) => s.title == 'Tabil',
          );
          return recipe.copyWith(
            subsections: [
              tabil.copyWith(ingredients: const <IngredientGroup>[]),
              ...recipe.subsections,
            ],
          );
        }

        expect(
          () => validateRecipeDocument(proseFirst(loadCorpusRecipe(_chraime))),
          refused(),
        );
        final before = db.contentHashOf(stored(_chraime).id);
        expect(
          () => updateRecipe(db, config, stored(_chraime).id, {
            'subsections': [
              for (final s in proseFirst(stored(_chraime)).subsections)
                s.toMap(),
            ],
          }),
          refused(),
        );
        expect(db.contentHashOf(stored(_chraime).id), before);
      });
    },
  );
}
