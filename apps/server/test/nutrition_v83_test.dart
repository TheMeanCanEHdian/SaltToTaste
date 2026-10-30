// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v83 (batch M81; matcherVersion 78 — no corpus row moves): the
// person paths and pins of prep51 design_v2 §2 M81. Every value is the
// fresh compute of the WHOLE recipe over recorded real FDC answers
// (FixtureProvider) and equals the v82 replay of snapshot 29 on every
// pinned field. Never the network. Every corpus line is real.
// STATED constructions (no corpus state reaches these paths):
// F2 snapshot 29's cache state for the computed lines (the 'thin-sliced
// cooked deli ham', 'whole milk' and 'saltines' answers and 2514744's
// detail, each recorded from snapshot 29) cached first; then a fresh
// deployment's cache — the deli-ham answer (snapshot 29 holds Rule B1's
// part record 168322 ONLY as a hit of it) removed, so no cache holds
// 168322; FDC's answer for 168322 is that recorded hit (snapshot 29 holds
// no detail of it: `record_fdc_fixtures.dart --from-db … food=168322`
// reads "not in the snapshot cache"), or an outage on it;
// F3 a person's row removed after its Confirm (stands in for a text edit,
// which re-lays the row as carried); each table loop's real row read on a
// `portion` weigh (a negative path: no corpus row on those records is);
// 0150 stored a second time under another id (0150|6 is its key's one
// corpus row, so no corpus state gives the GET's offer on it a reach);
// the RULE C cap shapes' 400 typed rows under filler steps of a real
// sentence (the house's cap-shape exception);
// F5c and A5 are STATED SYNTHESIZED positive pins (each group says why).

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v80_test.dart' show friedOnionRings;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

(SaltDatabase, String) _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v83-');
  final path = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  ).dbPath;
  final db = SaltDatabase.open(path)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return (db, path);
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// The recorded fixtures, every request counted — and FDC's answer for
/// Rule B1's part record 168322 the recorded 'thin-sliced cooked deli ham'
/// hit (snapshot 29 holds no detail of it), or with [partFails] FDC failing
/// on it (STATED: an outage); any other unrecorded answer throws
/// ([UnrecordedAnswer]).
class _Counted implements NutritionProvider {
  _Counted(this.inner);

  final FixtureProvider inner;
  final asked = <String>[];
  bool partFails = false;

  @override
  Future<List<FdcCandidate>> search(String query) {
    asked.add('search $query');
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    asked.add('food $fdcId');
    if (fdcId != 168322) {
      return inner.food(fdcId);
    }
    if (partFails) {
      throw const NutritionProviderException(
        'FoodData Central is unavailable.',
        scope: FailureScope.food,
      );
    }
    return (await inner.search(
      _deliHam,
    )).singleWhere((c) => c.fdcId == 168322).toFood();
  }
}

const _deliHam = 'thin-sliced cooked deli ham';

/// F2's library: meatloaf-with-brown-sugarketchup-glaze, grilled-bacon-
/// wrapped-scallops and chili-con-carne computed on snapshot 29's cache
/// state for their lines (STATED: the 'thin-sliced cooked deli ham',
/// 'whole milk' and 'saltines' answers and 2514744's detail, each
/// recorded from snapshot 29, cached first), then the deli-ham answer
/// removed (STATED: a fresh deployment) — no cache holds 168322; then
/// chili-con-carne|7 picked 167869 and then 168277, each apply_to_all.
/// Returns the library, the provider, the second PUT's receipt and the three
/// recipe ids (meatloaf, scallops, chili).
Future<(SaltDatabase, _Counted, AppliedToOthers?, List<String>)> _applied({
  bool partFails = false,
}) async {
  final (db, path) = _db();
  final fdc = _Counted(FixtureProvider(pending: {...pendingSearches}));
  for (final q in const [_deliHam, 'whole milk', 'saltines']) {
    db.fdcSearchCachePut(
      q,
      jsonEncode([for (final c in await fdc.inner.search(q)) c.toJson()]),
    );
  }
  db.fdcFoodCachePut(
    2514744,
    jsonEncode((await fdc.inner.food(2514744))!.toJson()),
  );
  final ids = [
    for (final f in const [
      '0306-meatloaf-with-brown-sugarketchup-glaze.yaml',
      '0652-grilled-bacon-wrapped-scallops.yaml',
      '0495-chili-con-carne.yaml',
    ])
      (await _compute(db, fdc, loadCorpusRecipe(f))).id,
  ];
  // Settled at the v82 figures, each bacon row on 168277 with B1's parts.
  // RE-PIN (M82 batch, v84, C3a): the meatloaf's garlic |5 and the chili's
  // |9 at their printed teaspoons (the replay 575.11 → 575.01, 787.78 →
  // 787.54): was 575.11, 787.78.
  // RE-PIN (M90 batch, v89, brown sugar + cornstarch): the meatloaf's brown
  // sugar |1 and the chili's masa harina |13 at the prints (the replay
  // 575.01 → 571.59, 787.54 → 784.73): was 575.01, 787.54.
  expect(
    [for (final id in ids) db.nutritionFor(id)!.caloriesPerServing],
    [
      // RE-PIN (M86 batch, v90, 958: 2514744 ground beef 80/20): was 571.59.
      579.46,
      350.84,
      // RE-PIN (M86 batch, v90, 958: 2685581 crushed tomatoes, 2710835 masa
      // harina): was 784.73.
      781.87,
    ],
  );
  for (final (id, at, cooked) in [(ids[0], 17, 65.49), (ids[1], 0, 110.88)]) {
    expect(partsOf(_row(db, id, at).parts), [
      (fdcId: 168322, grams: cooked),
      (fdcId: 172345, grams: 0.0),
    ]);
  }
  sqlite3.open(path)
    ..execute('DELETE FROM fdc_search_cache WHERE query = ?', [_deliHam])
    ..dispose();
  expect(knownFood(db, 168322), isNull);
  fdc
    ..asked.clear()
    ..partFails = partFails;
  final line = nutritionLines(nutritionRecipeOf(db, ids[2])!.recipe)[7];
  expect(line.raw, '8 ounces bacon (about 8 slices), cut into ¼-inch pieces');
  AppliedToOthers? applied;
  for (final pick in const [167869, 168277]) {
    applied = await applyMatchOverride(
      db,
      fdc,
      nutritionRecipeOf(db, ids[2])!.recipe,
      7,
      {'raw': line.raw, 'fdc_id': pick, 'apply_to_all': true},
    );
    // The first pick's own detail (no cache of this library holds it).
    if (pick == 167869) {
      expect(fdc.asked, ['food 167869']);
      expect((applied?.recipes, applied?.lines), (2, 2));
    }
  }
  return (db, fdc, applied, ids);
}

String? _staleReason(SaltDatabase db, String id) => staleReasonOf(
  db,
  nutritionRecipeOf(db, id)!.recipe,
  db.nutritionFor(id)!,
  ResolverMemo(db),
);

/// [file] computed, its line [at] decided through the real PUT ([body]: a
/// Confirm, or a pick), then its row removed (STATED: stands in for a text
/// edit, which re-lays the row as carried) and the recipe computed — the
/// decision carried back onto its own line. Returns the decision stored
/// for [key], the row before, the carried row, the kcal per serving and the
/// requests the decision and the compute made.
Future<(int?, IngredientMatchRow, IngredientMatchRow, double?, int)>
_carriedBack(
  String file,
  int at,
  String key, [
  Map<String, Object?> body = const {'confirmed': true},
]) async {
  final (db, path) = _db();
  final fdc = FixtureProvider(pending: {...pendingSearches});
  final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
  final before = _row(db, recipe.id, at);
  final asked = (fdc.searchCalls, fdc.foodCalls);
  await applyMatchOverride(db, fdc, recipe, at, {
    'raw': nutritionLines(recipe)[at].raw,
    ...body,
  });
  final decided = db.decisionFor(key)?.fdcId;
  sqlite3.open(path)
    ..execute(
      'DELETE FROM ingredient_matches WHERE recipe_id = ? AND position = ?',
      [recipe.id, at],
    )
    ..dispose();
  expect(
    await matchAndCompute(db, fdc, nutritionRecipeOf(db, recipe.id)!.recipe),
    isNull,
  );
  return (
    decided,
    before,
    _row(db, recipe.id, at),
    db.nutritionFor(recipe.id)!.caloriesPerServing,
    fdc.searchCalls + fdc.foodCalls - asked.$1 - asked.$2,
  );
}

void main() {
  group('F2 — the apply path resolves the parts', skip: skipIfNoCorpus, () {
    test('chili-con-carne|7 "8 ounces bacon …" picked 167869, then 168277, '
        "apply_to_all, with no cache holding Rule B1's part record 168322 "
        '(STATED: a fresh deployment) — both B1 targets reached, 168322 '
        'fetched ONCE for the two (RULE A, the onePass memo), each fresh at '
        'its v82 figure (meatloaf 575.11, scallops 350.84 /serving) and '
        'equal to a full compute (base: both `underived`, 524.02 and 221.11 '
        '— the bacon rows out of the label)', () async {
      final (db, fdc, applied, ids) = await _applied();
      expect(
        (applied?.recipes, applied?.lines, applied?.unavailable),
        (
          2,
          2,
          0,
        ),
      );
      expect(
        [for (final id in ids.take(2)) db.nutritionFor(id)!.caloriesPerServing],
        // RE-PIN (M82 batch, v84, C3a): the meatloaf's garlic — was 575.11.
        // RE-PIN (M90 batch, v89, brown sugar): its brown sugar — was 575.01.
        // RE-PIN (M86 batch, v90, 958: 2514744 ground beef 80/20): was 571.59.
        [579.46, 350.84],
      );
      expect(
        [for (final id in ids.take(2)) _staleReason(db, id)],
        [
          null,
          null,
        ],
      );
      // The cost: one request per part record per apply.
      expect(fdc.asked, ['food 167869', 'food 168322']);
      // Stored == a full compute (no request: everything is cached now).
      fdc.asked.clear();
      for (final id in ids.take(2)) {
        final before = db.nutritionFor(id)!.totalsJson;
        await matchAndCompute(db, fdc, nutritionRecipeOf(db, id)!.recipe);
        expect(db.nutritionFor(id)!.totalsJson, before);
      }
      expect(fdc.asked, isEmpty);
    });

    test('the part record FDC cannot serve (STATED: an outage on 168322) '
        "takes the weigh failure's arm: each target counted `unavailable`, "
        'never `failed` or written — its row stays the first pick, 167869, '
        'and its totals read `underived`', () async {
      final (db, fdc, applied, ids) = await _applied(partFails: true);
      expect(
        (
          applied?.recipes,
          applied?.lines,
          applied?.unavailable,
          applied?.failed,
        ),
        (0, 0, 2, 0),
      );
      expect(fdc.asked, ['food 167869', 'food 168322']);
      expect(
        [_row(db, ids[0], 17).fdcId, _row(db, ids[1], 0).fdcId],
        [
          167869,
          167869,
        ],
      );
      expect(
        [for (final id in ids.take(2)) _staleReason(db, id)],
        [
          'underived',
          'underived',
        ],
      );
    });
  });

  group(
    "F3 — the skin / shell / can inverses gate on the forward move's "
    'term',
    skip: skipIfNoCorpus,
    () {
      test('oven-fried-chicken|6 "4 whole chicken legs, … skin removed" '
          '(173619, `piece` 1,060.00 g — the forward move never fires on a '
          'piece weight): its Confirm decides 173619, and carried back it '
          'lands on 173619 at 1,060.00 g, 527.93 /serving (base: 172378, the '
          'meat AND skin, 1,376.00 g, 958.56)', () async {
        final (decided, before, carried, kcal, requests) = await _carriedBack(
          '0150-oven-fried-chicken.yaml',
          6,
          'whole chicken leg',
        );
        expect(
          before.raw,
          '4 whole chicken legs, separated into drumsticks and thighs and skin removed',
        );
        expect(
          (before.fdcId, before.grams, before.gramSource),
          (
            173619,
            1060.0,
            'piece',
          ),
        );
        expect(kcal, 527.93);
        expect(
          (carried.fdcId, carried.grams, carried.gramSource),
          (
            173619,
            1060.0,
            'piece',
          ),
        );
        expect(decided, 173619);
        expect(requests, 0);
      });

      test(
        'the converse: grilled-lemon-chicken-with-rosemary|0 (171052, '
        '`weight` — moved there by the skin trip) still decides the skin-on '
        '171447 and round-trips on 171052 at 738.75 g, 312.17 /serving',
        () async {
          final (decided, before, carried, kcal, requests) = await _carriedBack(
            '0637-grilled-lemon-chicken-with-rosemary.yaml',
            0,
            'whole chicken',
          );
          expect(
            (before.fdcId, before.grams, before.gramSource),
            (
              171052,
              738.75,
              'weight',
            ),
          );
          expect(decided, 171447);
          expect(
            (carried.fdcId, carried.grams, carried.gramSource),
            (
              171052,
              738.75,
              'weight',
            ),
          );
          expect(kcal, 312.17);
          expect(requests, 0);
        },
      );

      test('a pick of the moved record on the same line (171052 on '
          'grilled-lemon-chicken-with-rosemary|0) decides 171447 too — the '
          "PUT reads the derived row's gram source (the pick clears the "
          "edited row's)", () async {
        final (decided, _, carried, kcal, _) = await _carriedBack(
          '0637-grilled-lemon-chicken-with-rosemary.yaml',
          0,
          'whole chicken',
          const {'fdc_id': 171052},
        );
        expect(decided, 171447);
        expect((carried.fdcId, carried.grams), (171052, 738.75));
        expect(kcal, 312.17);
      });

      // v83 closer 1 (verify1 D1): typed grams (`override`) are no weigh of
      // their own — the gate reads the line's engine weigh on the row's food.
      // STATED: the grams a person types are the row's own (no new figure).
      test(
        'typed grams on the moved record: '
        'grilled-lemon-chicken-with-rosemary|0 Confirmed, or picked on '
        '171052, with its own 738.75 g '
        'typed decides 171447 as the bare Confirm does, so '
        'perfect-roast-chicken|2 (skin eaten) keeps 171447 at 1,035.00 g, '
        '1,277.30 /serving (pre-closer: 171052 decided and carried there at '
        '738.75 g, 604.23); oven-fried-chicken|6 Confirmed with its own '
        '1,060.00 g typed still decides 173619 (its weigh is `piece`)',
        () async {
          for (final body in const [
            {'confirmed': true, 'grams': 738.75},
            {'fdc_id': 171052, 'grams': 738.75},
          ]) {
            final (db, _) = _db();
            final fdc = FixtureProvider(pending: {...pendingSearches});
            final lemon = await _compute(
              db,
              fdc,
              loadCorpusRecipe('0637-grilled-lemon-chicken-with-rosemary.yaml'),
            );
            final roast = await _compute(
              db,
              fdc,
              loadCorpusRecipe('0134-perfect-roast-chicken.yaml'),
            );
            await applyMatchOverride(db, fdc, lemon, 0, {
              'raw': nutritionLines(lemon)[0].raw,
              ...body,
            });
            final typed = _row(db, lemon.id, 0);
            expect(
              (typed.fdcId, typed.grams, typed.gramSource),
              (171052, 738.75, 'override'),
              reason: '$body',
            );
            expect(
              db.decisionFor('whole chicken')?.fdcId,
              171447,
              reason: '$body',
            );
            expect(
              await matchAndCompute(
                db,
                fdc,
                nutritionRecipeOf(db, roast.id)!.recipe,
              ),
              isNull,
            );
            final bird = _row(db, roast.id, 2);
            expect(
              bird.raw,
              '1 (3½- to 4-pound) whole chicken, giblets discarded',
            );
            expect(
              (bird.fdcId, bird.grams, bird.gramSource),
              (171447, 1035.0, 'weight'),
              reason: '$body',
            );
            expect(
              db.nutritionFor(roast.id)!.caloriesPerServing,
              1277.30,
              reason: '$body',
            );
          }
          final (decided, before, _, _, _) = await _carriedBack(
            '0150-oven-fried-chicken.yaml',
            6,
            'whole chicken leg',
            const {'confirmed': true, 'grams': 1060.0},
          );
          expect((before.fdcId, before.gramSource), (173619, 'piece'));
          expect(decided, 173619);
        },
      );

      test(
        'the GET offers what the PUT writes on a typed row: '
        "grilled-lemon-chicken-with-rosemary|0's own 738.75 g typed (an "
        'edit), then '
        'Confirmed apply_to_all — the offer names 171447, so '
        'perfect-roast-chicken|2 (on 171447) is not reached: offered (0, 0), '
        'written (0, 0) (pre-closer: 171052 offered and written, (1, 1))',
        () async {
          final (db, _) = _db();
          final fdc = FixtureProvider(pending: {...pendingSearches});
          final lemon = await _compute(
            db,
            fdc,
            loadCorpusRecipe('0637-grilled-lemon-chicken-with-rosemary.yaml'),
          );
          final roast = await _compute(
            db,
            fdc,
            loadCorpusRecipe('0134-perfect-roast-chicken.yaml'),
          );
          final raw = nutritionLines(lemon)[0].raw;
          await applyMatchOverride(db, fdc, lemon, 0, {
            'raw': raw,
            'grams': 738.75,
          });
          expect(_row(db, lemon.id, 0).gramSource, 'override');
          final item =
              ((await matchesBody(db, fdc, lemon))['items']! as List)[0] as Map;
          final applied = await applyMatchOverride(db, fdc, lemon, 0, {
            'raw': raw,
            'confirmed': true,
            'apply_to_all': true,
          });
          expect((item['others'], item['others_lines']), (0, 0));
          expect((applied?.recipes ?? 0, applied?.lines ?? 0), (0, 0));
          expect(db.decisionFor('whole chicken')?.fdcId, 171447);
          expect(_row(db, roast.id, 2).fdcId, 171447);
        },
      );

      // v83 closer 5 (verify5 D1): the GET's call site reads the row's own
      // gram source on a row that is not `weight` too. STATED SYNTHESIZED
      // (the standing exception recorded in docs/IMPLEMENTATION.md
      // :1518–1519, :1653, :1804): 0150|6 is the one row of the key 'whole
      // chicken leg' on snapshot 29 (v82_rows), so no corpus state gives it a
      // reach — the real 0150 is stored a second time under another id (a
      // library holding its real line twice); the copy's |6 is the reach.
      test(
        'the GET offers what the PUT writes on a `piece` row: '
        'oven-fried-chicken|6 (173619, `piece`) with 0150 stored a second '
        'time (STATED) — Confirmed apply_to_all, the offer names 173619, so '
        "the copy's |6 (on 173619) is not reached: offered (0, 0), written "
        '(0, 0), decision 173619, the copy kept at 1,060.00 g `piece` (base: '
        'the skin-on 172378 offered and written, (1, 1); the GET reading the '
        'row as `weight`: offered (1, 1), written (0, 0))',
        () async {
          final (db, _) = _db();
          final fdc = FixtureProvider(pending: {...pendingSearches});
          final legs = loadCorpusRecipe('0150-oven-fried-chicken.yaml');
          final recipe = await _compute(db, fdc, legs);
          final copy = await _compute(
            db,
            fdc,
            legs.copyWith(id: '${legs.id}-v83', slug: '${legs.slug}-v83'),
          );
          for (final id in [recipe.id, copy.id]) {
            final row = _row(db, id, 6);
            expect(
              row.raw,
              '4 whole chicken legs, separated into drumsticks and thighs and skin removed',
            );
            expect(
              (row.fdcId, row.grams, row.gramSource),
              (173619, 1060.0, 'piece'),
            );
          }
          final item =
              ((await matchesBody(db, fdc, recipe))['items']! as List)[6]
                  as Map;
          expect(item['position'], 6);
          final applied = await applyMatchOverride(db, fdc, recipe, 6, {
            'raw': nutritionLines(recipe)[6].raw,
            'confirmed': true,
            'apply_to_all': true,
          });
          expect((item['others'], item['others_lines']), (0, 0));
          expect((applied?.recipes ?? 0, applied?.lines ?? 0), (0, 0));
          expect(db.decisionFor('whole chicken leg')?.fdcId, 173619);
          final kept = _row(db, copy.id, 6);
          expect(
            (kept.fdcId, kept.grams, kept.gramSource),
            (173619, 1060.0, 'piece'),
          );
        },
      );

      test("each table loop's gate (skin, shell, can): on the real line and "
          'record a `weight` row decides the record bought; the same row read '
          'on a `portion` weigh decides itself (STATED: no corpus row on these '
          'records is weighed otherwise — a negative path; base: the record '
          'bought for both)', () async {
        final (db, _) = _db();
        final fdc = FixtureProvider(pending: {...pendingSearches});
        for (final (file, at, raw, bought) in const [
          ('0637-grilled-lemon-chicken-with-rosemary.yaml', 0, 171052, 171447),
          ('0294-oven-steamed-mussels.yaml', 6, 174216, 2706350),
          ('0340-pasta-e-ceci-pasta-with-chickpeas.yaml', 10, 175206, 2644288),
        ]) {
          final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
          final row = _row(db, recipe.id, at);
          expect((row.fdcId, row.gramSource), (raw, 'weight'), reason: file);
          final line = weighedLine(recipe, nutritionLines(recipe)[at]);
          int? decides(String source) => decisionRecordOf(
            recipe,
            line,
            row.fdcId,
            db: db,
            description: row.description,
            gramSource: source,
          );
          expect(
            [decides('weight'), decides('portion')],
            [bought, raw],
            reason: file,
          );
        }
      });

      // RULE C at the editor caps (closer 4, verify4 D1): a typed row's term
      // is the line's own weigh WITHOUT the recipe's step readers — with them
      // each typed row paid `skinDiscarded`'s scans of the memoized skin
      // sentences again (uncounted, so the clock is this pin's kill: the TRUE
      // shape's GET 12.5 s, over the backstop). STATED synthesized cost inputs
      // (the house's cap-shape exception, nutrition_v82_test `costShapes`):
      // 0637|0's real line × 400 under 120 steps × 10,000 characters of a real
      // 0637 sentence — TRUE "Using fingers and shears, peel skin off chicken,
      // leaving skin on wings." (the skin trip fires), QUIET "Flip chicken
      // over and press on breastbone to flatten."; every row 0637|0's own
      // (171052, `weight` 738.75 g) with its 738.75 g typed (`override` /
      // `overridden`), written directly: the GET reads them as it reads the
      // compute's rows so retyped (items, offers and clock measured equal; the
      // 29 s compute only warms 0637's carried read), beside the real 0637 the
      // TRUE offer reaches (0637|0 on 171052, the decision 171447). Measured
      // (quiet machine, two GETs each, this shape): TRUE 4,423 / 4,427 ms at
      // 4325a3d, 4,474 / 4,340 here, 12,513 / 12,563 with `recipe:`; QUIET
      // 344 / 336 at 4325a3d, 370 / 361 here (the arm's 400 weighs, no step
      // reader). The counts are base's exactly (count-pinned: the clock is
      // the backstop, never the kill — except for the uncounted scans above).
      Map<String, int> capCounts(int indexes, int sentences, int words) => {
        // Each memo family once per index: the cap recipe's, and on the TRUE
        // shape's first GET 0637's (its reached row's carried read decodes
        // it; the library's carried memo holds it for the second GET).
        for (final family in const [
          'cheese',
          'heads',
          'indexes',
          'lower',
          'memo:braise',
          'memo:brineWords',
          'memo:brines',
          'memo:discards',
          'memo:measuresOut',
          'memo:naming',
          'memo:parting',
          'memo:pourAway',
          'memo:reservedWhole',
          'memo:savesRemainder',
          'memo:setAsideLine',
          'memo:setsAsidePieces',
          'memo:starter',
          'memo:strain',
          'memo:strainAt',
          'memo:wordHeads',
        ])
          family: indexes,
        if (indexes > 1) 'ends': 1,
        // The cap recipe's sentences and skin sentences, once.
        'allSentences': 1,
        'memo:skinSentences': 1,
        'sentences': sentences,
        'words': words,
      };
      for (final (shape, sentence, decides, offered, gets) in [
        (
          'TRUE',
          'Using fingers and shears, peel skin off chicken, leaving skin on wings.',
          171447,
          (1, 1),
          [capCounts(2, 16717, 199208), capCounts(1, 16680, 198720)],
        ),
        (
          'QUIET',
          'Flip chicken over and press on breastbone to flatten.',
          171052,
          (0, 0),
          [capCounts(1, 22320, 199800), capCounts(1, 22320, 199800)],
        ),
      ]) {
        test(
          'RULE C at the editor caps, the $shape shape: 400 typed rows on '
          "171052 under 120 × 10,000 characters of 0637's real sentence — the "
          "GET's counts base's exactly, within the backstop; the typed rows "
          'decide $decides, offered $offered',
          () async {
            final (db, _) = _db();
            final fdc = FixtureProvider(pending: {...pendingSearches});
            final lemon = await _compute(
              db,
              fdc,
              loadCorpusRecipe('0637-grilled-lemon-chicken-with-rosemary.yaml'),
            );
            expect(
              lemon.steps.where((s) => s.text.contains(sentence)),
              hasLength(1),
            );
            final own = _row(db, lemon.id, 0);
            expect(
              (own.raw, own.fdcId, own.grams, own.gramSource),
              (
                '1 (3½- to 4-pound) whole chicken, giblets discarded',
                171052,
                738.75,
                'weight',
              ),
            );
            final r = capped(
              lemon,
              List.filled(capLines, own.raw),
              List.filled(
                capSteps,
                '$sentence ' * (capStep ~/ (sentence.length + 1)),
              ),
            ).copyWith(id: 'cap-$shape', slug: 'cap-$shape');
            db.upsertRecipe(
              r,
              sourceSlug: _source,
              contentHash: contentHashOf(r),
            );
            for (var at = 0; at < capLines; at++) {
              db.upsertIngredientMatch(
                IngredientMatchRow(
                  recipeId: r.id,
                  position: at,
                  raw: own.raw,
                  fdcId: own.fdcId,
                  description: own.description,
                  dataType: own.dataType,
                  confidence: own.confidence,
                  grams: own.grams,
                  gramSource: 'override',
                  status: 'overridden',
                  itemKey: own.itemKey,
                ),
              );
            }
            for (final expected in gets) {
              // Each GET decodes the recipe, as a request does.
              final stored = db.recipeByIdOrSlug(r.id)!.recipe;
              stepIndexCounts.clear();
              final sw = Stopwatch()..start();
              final body = await matchesBody(db, fdc, stored);
              final ms = sw.elapsedMilliseconds;
              final counts = Map.of(stepIndexCounts);
              expectBounded(
                stored,
                counts,
                '$shape GET',
                copies: counts['indexes'] ?? 1,
              );
              expect(counts, expected, reason: '$shape GET');
              expect(ms, lessThan(backstopMs), reason: '$shape GET: $counts');
              final items = body['items']! as List;
              expect(items, hasLength(capLines));
              final item = items[0] as Map;
              final match = item['match']! as Map;
              expect(
                (match['fdc_id'], match['gram_source']),
                (171052, 'override'),
              );
              // The offer reads the decision the arm names.
              expect((item['others'], item['others_lines']), offered);
            }
            // The arm's own path on row 0: 171447 where the skin trip fires
            // (the line weighs `weight` on its food), else the record itself.
            final stored = db.recipeByIdOrSlug(r.id)!.recipe;
            final line = weighedLine(stored, nutritionLines(stored)[0]);
            expect(
              decisionRecordOf(
                stored,
                line,
                own.fdcId,
                db: db,
                description: own.description,
                gramSource: 'override',
                food: knownFood(db, 171052, line: line),
              ),
              decides,
            );
          },
          timeout: const Timeout(Duration(minutes: 3)),
        );
      }
    },
  );

  group('F5c — a main recipe hashes its yield oil', skip: skipIfNoCorpus, () {
    // STATED SYNTHESIZED (a positive pin of a guard no corpus recipe
    // reaches — the standing exception recorded in docs/IMPLEMENTATION.md
    // :1518–1519, :1653, :1804 and contract_golden_test.dart:138): 0053's
    // real section "Fried Shallots and Fried Shallot Oil" saved as a MAIN
    // recipe (no corpus main recipe prints a yield oil; the section's own
    // yield is hashed already), its real yield edited as v63's pins edit it.
    // The host gate's converse is the real section itself (no synthesis).
    test('0053\'s "Fried Shallots and Fried Shallot Oil" as a main recipe: '
        'its yield edited "ABOUT 1¾ CUPS FRIED SHALLOT OIL" → "ABOUT 1½ '
        'CUPS …" stales its stamp (base: fresh) — and the recompute counts '
        'the oil the edit keeps, 56.00 → 112.00 g', () async {
      final (db, _) = _db();
      final fdc = FixtureProvider(pending: {...pendingSearches});
      final host = loadCorpusRecipe('0053-crispy-thai-eggplant-salad.yaml');
      final section = sectionOf(
        host,
        sectionKeyOf(host.id, 'Fried Shallots and Fried Shallot Oil'),
      )!;
      final main = section.copyWith(
        id: 'fried-shallots',
        slug: 'fried-shallots',
      );
      expect(hostOf(main.id), main.id);
      expect(
        main.servings,
        'MAKES ABOUT 1½ CUPS FRIED SHALLOTS AND ABOUT 1¾ CUPS FRIED SHALLOT OIL',
      );
      final stored = await _compute(db, fdc, main);
      final oil = nutritionLines(stored).indexWhere(
        (l) => l.raw == '2 cups vegetable oil',
      );
      expect(_row(db, stored.id, oil).grams!.toStringAsFixed(2), '56.00');
      expect(nutritionStampCurrent(db, stored), isTrue);
      final edited = stored.copyWith(
        servings: stored.servings!.replaceFirst(
          'ABOUT 1¾ CUPS FRIED SHALLOT OIL',
          'ABOUT 1½ CUPS FRIED SHALLOT OIL',
        ),
      );
      expect(edited.servings, isNot(stored.servings));
      expect(nutritionStampCurrent(db, edited), isFalse);
      final recomputed = await _compute(db, fdc, edited);
      expect(_row(db, recomputed.id, oil).grams!.toStringAsFixed(2), '112.00');
      expect(nutritionStampCurrent(db, recomputed), isTrue);
    });

    test('the host gate (`hostOf(recipe.id) == recipe.id`): the REAL '
        'section 0053 "Fried Shallots and Fried Shallot Oil" prints a yield '
        'oil and hashes no `yield_oil` — its hash is the one every '
        'matcherVersion-78 library stores (gate dropped: bf6e9662…, the '
        'section stale on every deployment)', () {
      final (db, _) = _db();
      final host = loadCorpusRecipe('0053-crispy-thai-eggplant-salad.yaml');
      db.upsertRecipe(
        host,
        sourceSlug: _source,
        contentHash: contentHashOf(host),
      );
      final section = nutritionRecipeOf(
        db,
        sectionKeyOf(host.id, 'Fried Shallots and Fried Shallot Oil'),
      )!.recipe;
      expect(hostOf(section.id), isNot(section.id));
      expect(
        section.servings,
        'MAKES ABOUT 1½ CUPS FRIED SHALLOTS AND ABOUT 1¾ CUPS FRIED SHALLOT OIL',
      );
      expect(
        ingredientsHashOf(section, ResolverMemo(db)),
        // Snapshot 29's: an ingredientsHashOf dump of all 1,342
        // bulkScopeIds(all) ids on a snapshot-29 copy reads this for the
        // section on base 4325a3d and on v83 alike (verify3). Re-pin it with
        // each matcherVersion bump (the version alone moves it).
        // RE-PIN (M82 batch, v84): the hash at matcherVersion 79 (was
        // 3b204f37…; the base tree with only the bump gives this literal).
        // RE-PIN (M83 batch, v85): the hash at matcherVersion 80 (was
        // 8aab695d…; the base tree with only the bump gives this literal).
        // RE-PIN (M84 batch, v86): the hash at matcherVersion 81 (was
        // ec64db32…; the base tree with only the bump gives this literal).
        // RE-PIN (M85 batch, v87): the hash at matcherVersion 82 (was
        // a5e2895d…; the base tree with only the bump gives this literal).
        // RE-PIN (M88 batch, v88): the hash at matcherVersion 83 (was
        // 261b14d5…; the base tree with only the bump gives this literal).
        // RE-PIN (M90 batch, v89): the hash at matcherVersion 84 (was
        // 037e93f7…; the base tree with only the bump gives this literal).
        // RE-PIN (M86 batch, v90): the hash at matcherVersion 85 (was
        // f33ea134…; the base tree with only the bump gives this literal).
        // RE-PIN (M87 batch, v91): the hash at matcherVersion 86 (was
        // 3d506465…; the version alone — the arm kept at 85 gives 3d506465).
        // RE-PIN (M89 batch, v92): the hash at matcherVersion 87 (was
        // 7d5dc015…; the version alone — the arm with 86 put back gives 7d5dc015).
        // RE-PIN (M91 batch, v93): the hash at matcherVersion 88 (was
        // 23ff4609…; the version alone — the keys with 87 put back give 23ff4609).
        // RE-PIN (M92 batch, v94): the hash at matcherVersion 89 (was
        // 62e9afcd…; the version alone — the rule with 88 put back gives 62e9afcd).
        // RE-PIN (M93 batch, v95): the hash at matcherVersion 90 (was
        // aa243fa7…; the version alone — the base engine with 90 gives this literal).
        'f656c45d79573048a096ab1c181e557770e2fd73440f9dc13f87a37dd36b2495',
      );
    });
  });

  group(
    "A5 — `_dipsOf`'s two `_before` sites (the U1 gap)",
    skip: skipIfNoCorpus,
    () {
      // STATED SYNTHESIZED (positive pins of two sites no corpus recipe
      // reaches — 19 dip recipes, one dip sentence each; the standing
      // exception recorded in docs/IMPLEMENTATION.md:1518–1519, :1653, :1804
      // and contract_golden_test.dart:138): every sentence is copied verbatim
      // from a named corpus step, only its placement is synthesized — on
      // nutrition_v80_test's STATED fried copy of 0315 ([friedOnionRings]),
      // where M62 H holds every dip line `coating` with its dip sentence as
      // the hold note (the NOTES pinned, never |0's grams).
      const whisk =
          'Whisk the remaining ¼ cup flour, the salt, black pepper, and cayenne '
          'into the buttermilk mixture.';
      const plate = 'Transfer to a large plate.';
      const beat = 'Beat the egg and buttermilk in a medium bowl.';
      // 0198 S2 and 0420 S4, verbatim.
      const s0198 =
          'Using tongs, coat with the buttermilk mixture; let excess drip off.';
      const s0420 =
          'Working with 1 chicken cutlet at a time, dredge in the flour, shaking '
          'off the excess, then coat with the egg mixture, allowing the excess '
          'to drip off.';
      // 0315 S2's dip sentence, whole.
      const dip0315 =
          'Dip in the buttermilk mixture, allowing the excess to drip back into '
          'the bowl, then drop into the crumb coating, turning the ring over to '
          'coat evenly.';

      /// The fried copy with [step]'s text edited, under its own id.
      Recipe synth(String tag, int step, String Function(String) edit) {
        final fried = friedOnionRings();
        return fried.copyWith(
          id: '${fried.id}-$tag',
          slug: '${fried.slug}-$tag',
          steps: [
            for (final (i, s) in fried.steps.indexed)
              i == step ? s.copyWith(text: edit(s.text)) : s,
          ],
        );
      }

      /// The hold note of each dip line of [r] — |1 egg, |2 buttermilk, |3
      /// salt, |4 black pepper, |5 cayenne — computed, each held `coating`.
      Future<List<String?>> notes(Recipe r) async {
        final (db, _) = _db();
        final stored = await _compute(
          db,
          FixtureProvider(pending: {...pendingSearches}),
          r,
        );
        final lines = nutritionLines(stored);
        expect(
          [for (var at = 1; at <= 5; at++) lines[at].raw],
          [
            '1 large egg, at room temperature',
            '½ cup buttermilk, at room temperature',
            '½ teaspoon table salt',
            '¼ teaspoon ground black pepper',
            '¼ teaspoon cayenne pepper',
          ],
        );
        expect(
          [for (var at = 1; at <= 5; at++) _row(db, stored.id, at).hold],
          [
            for (var at = 1; at <= 5; at++) 'coating',
          ],
        );
        return [
          for (var at = 1; at <= 5; at++)
            holdNoteOf(stored, lines[at], _row(db, stored.id, at).hold),
        ];
      }

      setUpAll(() {
        final rings = loadCorpusRecipe('0315-oven-fried-onion-rings.yaml');
        expect(rings.steps[0].text, contains(whisk));
        expect(rings.steps[1].text, contains(dip0315));
        expect(rings.steps[1].text, contains(plate));
        expect(rings.steps[0].text, contains(beat));
        expect(
          loadCorpusRecipe(
            '0198-crispy-pan-fried-pork-chops.yaml',
          ).steps[1].text,
          contains(s0198),
        );
        expect(
          loadCorpusRecipe('0420-chicken-francese.yaml').steps[3].text,
          contains(s0420),
        );
      });

      test("synthA (`dipped.firstWhere((d) => _before(p, d))`): 0198 S2's "
          'buttermilk dip inserted in 0315 S1 before the whisk of the salt, '
          "pepper and cayenne — those three read the LATER dip (0315 S2's), "
          'the egg and buttermilk beaten before both the earlier', () async {
        final got = await notes(
          synth('synthA', 0, (t) => t.replaceFirst(whisk, '$s0198 $whisk')),
        );
        // Base mutant `dipped.first`: |3–|5 read 0198's sentence.
        expect(got, [s0198, s0198, dip0315, dip0315, dip0315]);
      });

      test("synthB (`at[k] == null || _before(dip, at[k]!)`): 0420 S4's egg "
          'dip inserted in 0315 S2 after its buttermilk dip — every dip line '
          '(the egg and buttermilk named by both bases) reads the EARLIER dip, '
          "0315's", () async {
        final got = await notes(
          synth('synthB', 1, (t) => t.replaceFirst(plate, '$s0420 $plate')),
        );
        // Mutant `_before(at[k]!, dip)`: |1, |2 read 0420's sentence. (The
        // buttermilk base, whose dip comes first, is also processed first
        // here, so `at[k] == null` alone reads the same: synthC.)
        expect(got, [for (var at = 1; at <= 5; at++) dip0315]);
      });

      test('synthC (the comparison `_before(dip, at[k]!)` itself): 0198 '
          "S2's buttermilk dip inserted in 0315 S1 before its beat of the egg "
          "and buttermilk, 0420 S4's egg dip right after it — the egg and "
          'buttermilk, mixed there for both bases, read the EARLIER of the '
          "two bases' dips (0420's, though the buttermilk base is processed "
          "first and offers 0315 S2's); the salt, pepper and cayenne 0315 "
          "S2's", () async {
        final got = await notes(
          synth(
            'synthC',
            0,
            (t) => t.replaceFirst(beat, '$s0198 $beat $s0420'),
          ),
        );
        // Mutants `at[k] == null` (the first base processed wins) and
        // `_before(at[k]!, dip)`: |1, |2 read 0315 S2's sentence.
        expect(got, [s0420, s0420, dip0315, dip0315, dip0315]);
      });
    },
  );
}
