// Matcher v103 (batch fix103 at the base 63e4315; matcherVersion 95 → 96) —
// the fixes of dual-fleet review Run 075/076 over v30–v43, union U1–U24
// (.claude/diag/2026-11-05/review075/union_P.md; the rulings in
// fix103/brief.md). Every pin is a real corpus recipe through the real
// compute / PUT on the recorded fixtures or a snapshot-32 record; each
// STATED synthesized input names its exception and its corpus source.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart'
    show capLines, capStep, capSteps, capped, pork;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v27_cost_test.dart' show tok;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'nutrition_v29_rule_a_test.dart' as v29;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _nachos = '0471-cheesy-nachos-with-guacamole-and-salsa.yaml';
const _guac = '0472-chunky-guacamole.yaml';

final _fx = FixtureProvider(pending: pendingSearches);

({SaltDatabase db, ServerConfig config}) _open() {
  final dir = Directory.systemTemp.createTempSync('salt-v103-');
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return (db: db, config: config);
}

SaltDatabase _db() => _open().db;

Recipe _store(SaltDatabase db, Recipe r) {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [r] stored and computed (its section children first); the stored copy.
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  final stored = _store(db, r);
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

Recipe _rec(SaltDatabase db, String id) => nutritionRecipeOf(db, id)!.recipe;

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// [r] with its main line [position]'s raw text replaced (amounts kept).
Recipe _withRaw(Recipe r, int position, String raw) {
  var at = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              (at++ == position) ? l.copyWith(raw: raw) : l,
          ],
        ),
    ],
  );
}

Future<Map<String, Object?>> _child(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
  int at,
) async {
  final body = await matchesBody(db, fdc, _rec(db, id));
  jsonEncode(body);
  final item = (body['items']! as List)
      .cast<Map<String, Object?>>()
      .singleWhere(
        (i) => i['position'] == at,
      );
  return (item['match']! as Map<String, Object?>)['child']!
      as Map<String, Object?>;
}

void main() {
  group('v103 (fix103: Run 075/076 U1–U24)', skip: skipIfNoCorpus, () {
    u1();
    u2();
    u3();
    u4();
    u5();
    u6();
    u7();
    u8u10();
    u14();
    u15();
    u16();
    u17();
  });
}

/// U1 (MED; SC1/SC3/OC2): `shareReaderOf`'s written "(N recipe" and
/// `recipe`-amount arms returned the share unchecked — "(0 recipe" wrote
/// child_share 0.0 and the INSERT threw CHECK 275 (no row, the recipe never
/// computed, a sweep failed it every pass); "(500000 recipes" counted
/// 500000 × the child, fresh. v103: every arm reads `validShare` (the PUT's
/// (0, 100] bound, spelled once in salt_shared). STATED synthesized
/// (negative path: no corpus line writes 0 or more than 100 recipes): 0184
/// Herb Sauce line 3 "¼ cup Sauce Base (½ recipe; recipe follows)" with its
/// written share edited.
void u1() {
  for (final edit in [
    '(0 recipe; recipe follows)',
    '(500000 recipes; recipe follows)',
  ]) {
    test('U1: "$edit" — the compute does not throw, no row carries a share '
        '≤ 0 or > 100, the row is `not_routed` `no_share`, the GET serves, a '
        'bulk sweep counts 0 failed', () async {
      final db = _db();
      final real = loadCorpusRecipe(_herb);
      final line = nutritionLines(real)[3];
      expect(line.raw, '¼ cup Sauce Base (½ recipe; recipe follows)');
      final edited = _withRaw(real, 3, '¼ cup Sauce Base $edit');
      final stored = await _compute(db, _fx, edited);
      for (final m in db.ingredientMatchesFor(stored.id)) {
        final s = m.childShare;
        expect(s == null || (s > 0 && s <= 100), isTrue, reason: '$s');
      }
      expect(_row(db, stored.id, 3).childShare, isNull);
      final child = await _child(db, _fx, stored.id, 3);
      expect((child['state'], child['reason']), ('not_routed', 'no_share'));
      db.upsertRecipe(stored, sourceSlug: _source, contentHash: 'v103-u1');
      final job = startBulkJob(db, _fx, scope: BulkScope.all)!;
      while (bulkJobRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final row = db.nutritionJob(job)!;
      expect((row['status'], row['failed']), ('done', 0));
    });
  }

  // RE-PIN (an equality on the v102 figure): the unedited line keeps ½.
  test('U1: the real "(½ recipe" keeps 0.5', () async {
    final db = _db();
    final stored = await _compute(db, _fx, loadCorpusRecipe(_herb));
    expect(_row(db, stored.id, 3).childShare, 0.5);
  });
}

/// U2 (MED; S10/O8): a MAIN library child's yield was hashed by neither the
/// child nor its parent — a yield edit left both fresh while the parent's
/// routed share moved on recompute. v103: the `servings` term for every
/// recipe (`ingredientsHashOf`). STATED synthesized (every corpus main-child
/// route is "N recipe" at share 1.0): 0471 nachos line 6 "1 recipe Chunky
/// Guacamole (see this page)" edited to "1 cup …" (amount 1 cup) — the
/// fleets' probe; 0472's yield saved as "MAKES 6 CUPS" through the real
/// edit service.
void u2() {
  test('U2: a child yield edit stales the child, then the parent; the '
      'parent recompute writes 1/6', () async {
    final (:db, :config) = _open();
    final nachos = _store(db, loadCorpusRecipe(_nachos));
    final guac = _store(db, loadCorpusRecipe(_guac));
    final groups = [
      for (final g in nachos.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              l.raw == '1 recipe Chunky Guacamole (see this page)'
                  ? l.copyWith(
                      raw: '1 cup Chunky Guacamole (see this page)',
                      amounts: [
                        const Amount(
                          measure: Measure.volume,
                          quantity: '1',
                          unit: 'cup',
                          primary: true,
                        ),
                      ],
                    )
                  : l,
          ],
        ),
    ];
    updateRecipe(db, config, nachos.id, {
      'ingredients': [for (final g in groups) g.toMap()],
    });
    Recipe stored(Recipe r) => db.recipeByIdOrSlug(r.id)!.recipe;
    expect(
      await matchAndCompute(
        db,
        _fx,
        nutritionRecipeOf(
          db,
          sectionKeyOf(nachos.id, 'One-Minute Salsa'),
        )!.recipe,
      ),
      isNull,
    );
    expect(await matchAndCompute(db, _fx, stored(guac)), isNull);
    expect(await matchAndCompute(db, _fx, stored(nachos)), isNull);
    expect(_row(db, nachos.id, 6).childShare, closeTo(1 / 3, 1e-9));
    final hash = ingredientsHashOf(stored(guac), ResolverMemo(db));
    updateRecipe(db, config, guac.id, {'servings': 'MAKES 6 CUPS'});
    expect(ingredientsHashOf(stored(guac), ResolverMemo(db)), isNot(hash));
    expect(nutritionIsFresh(db, stored(guac)), isFalse);
    expect(bulkScopeIds(db, BulkScope.stale), contains(guac.id));
    expect(await matchAndCompute(db, _fx, stored(guac)), isNull);
    expect(nutritionIsFresh(db, stored(nachos)), isFalse);
    expect(bulkScopeIds(db, BulkScope.stale), contains(nachos.id));
    expect(await matchAndCompute(db, _fx, stored(nachos)), isNull);
    expect(_row(db, nachos.id, 6).childShare, closeTo(1 / 6, 1e-9));
    expect(
      db.nutritionFor(nachos.id)!.caloriesPerServing,
      closeTo(878.52, 0.01),
    );
  });
}

/// U3 (MED/LOW; O1/S1): the Granny Smith cup divided the print's GROSS
/// purchase weight by the peeled, cored flesh's 3 cups (226.8 g/cup); v43
/// Y8 reads the SAME print as edible (× 0.78, AH-102 item 17) on the bundt
/// line. v103: the cup at the edible yield, 1.5 × 453.592 × 0.78 / (3 ×
/// 236.588) = 0.7477 g/mL (176.9 g/cup) — the only corpus movement: two
/// rows. Real corpus lines on the fixtures' 1750342.
void u3() {
  for (final (file, at, raw, grams, basis) in [
    (
      '0777-classic-strawberry-jam.yaml',
      2,
      '1¼ cups peeled and shredded Granny Smith apple (1 large apple)',
      221.13,
      '1 1/4 cup ≈ 296 mL · approximate (ATK: 1½ pounds Granny Smith apples, peeled, cored, shredded = 3 cups, × 0.78 edible (AH-102 item 17))',
    ),
    (
      '0158-classic-roast-stuffed-turkey.yaml',
      3,
      '2 Granny Smith apples, peeled, cored, and cut into ½-inch cubes (about 2 cups)',
      // RE-PIN (fix104 batch, v104, U2: the cubed cup — the brown-betty
      // print 1½ lb × 0.78 / 4 cups): was 353.80 and the shredded label.
      265.35,
      '2 cup ≈ 473 mL · approximate (ATK: 1½ pounds Granny Smith apples, peeled, cored, cut into ½-inch cubes = 4 cups, × 0.78 edible (AH-102 item 17))',
    ),
    // RE-PIN (an equality on the v102 figure): the weight path, unchanged.
    (
      '0858-cider-glazed-apple-bundt-cake.yaml',
      12,
      '1½ pounds Granny Smith apples, peeled, cored, and shredded (3 cups)',
      530.70,
      'from 1 1/2 pound × 0.78 edible · approximate (USDA AH-102 item 17: apples, all cultivars, raw whole → flesh, pared and cored 78 % (60–87))',
    ),
  ]) {
    test('U3: $file|$at → ${grams.toStringAsFixed(2)} g', () async {
      // The real corpus line (the v37 form: one line, its own recipe — the
      // row reads only the line); its corpus position stated.
      final real = loadCorpusRecipe(file);
      final lines = [
        for (final g in real.ingredients) ...g.items,
        for (final sub in real.subsections)
          for (final g in sub.ingredients ?? const <IngredientGroup>[])
            ...g.items,
      ];
      final line = lines.singleWhere((l) => l.raw == raw);
      final db = _db();
      final r = Recipe(
        id: 'u3',
        title: 'u3',
        slug: 'u3',
        source: const RecipeSource(name: 'ATK', type: 'epub'),
        ingredients: [
          IngredientGroup(items: [line]),
        ],
      );
      db.upsertRecipe(r, sourceSlug: _source, contentHash: 'u3');
      expect(await matchAndCompute(db, _fx, r), isNull);
      final row = db.ingredientMatchesFor('u3').single;
      expect(row.fdcId, 1750342);
      expect(row.grams, closeTo(grams, 0.01));
      expect(gramBasisFor(db, line, row), basis);
    });
  }
}

/// U4 (MED; S3): the un-skip of a kept engine row (`auto` with a food, v36)
/// whose food no cache holds stored `auto`, no grams, no hold, under a FRESH
/// stamp (12/13, 362.43 kcal/serving vs the compute's 13/13, 464.1). v103:
/// the row the compute writes for it — held `food_unavailable`, grams null,
/// its food kept — and v102 R2's hook reads the totals underived. The S3
/// probe as a test: 0857 line 0 (butter 173430) dropped from the caches,
/// FOOD fault ×3 → held; the PUT's skip, then its un-skip. STATED
/// synthesized (negative path): the cache deletion and the provider fault.
void u4() {
  test('U4: an un-skip of a held kept row whose food no cache holds → held '
      '`food_unavailable` (food kept, grams null), not fresh, partial; the '
      '`all` compute with FDC up restores 13/13, 464.1', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, 173430);
    final fault = v28.FoodFault(_fx, {173430}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 0);
    expect((held.fdcId, held.hold), (173430, 'food_unavailable'));
    await applyMatchOverride(db, fault, r, 0, {
      'raw': held.raw,
      'skipped': true,
    });
    await applyMatchOverride(db, fault, r, 0, {
      'raw': held.raw,
      'skipped': false,
    });
    final row = d.rowOf(db, r, 0);
    expect(
      (row.status, row.fdcId, row.hold, row.grams),
      ('auto', 173430, 'food_unavailable', null),
    );
    expect(nutritionIsFresh(db, r), isFalse);
    final n = db.nutritionFor(r.id)!;
    expect(n.status, 'partial');
    expect(n.matchedCount, 12);
    fault.up = true;
    await matchAndCompute(db, fault, r, retryUnavailable: true);
    final m = db.nutritionFor(r.id)!;
    expect((m.matchedCount, m.totalCount), (13, 13));
    // RE-PIN (fix104 batch, v104 U13): within the stored figure's 0.01
    // (the test's own run stores 464.1; was closeTo(464.1, 0.05)).
    expect(m.caloriesPerServing, closeTo(464.1, 0.01));
    expect(d.rowOf(db, r, 0).grams, closeTo(170.166, 0.001));
  });
}

/// A provider that answers nothing and counts every ask (NoNet).
class _NoNet implements NutritionProvider {
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }
}

/// U5 (MED; O2): a kept row held `food_unavailable` on a failing PART
/// record was never re-opened by a cache gain — `unholdOn` matched the
/// row's own `fdc_id` only. v103: migration 022's `held_on` (the part
/// `_resolveParts` could not fetch) and `unholdOn` matches `fdc_id` OR
/// `held_on`. O2's probe as a test: 0040 line 5 (v41's rendered bacon, row
/// food 168277, parts 168322 + 172345) computed after 0118; 168322 dropped
/// from the caches + a FOOD fault ×3 → held; then 0118's compute caches
/// 168322 again. STATED synthesized (negative path): the cache deletion
/// and the provider fault.
void u5() {
  test(
    'U5: a hold on a part is held_on it; the part regained re-opens the '
    'row; a cache-only compute restores 9/9 at 274.36 with 0 requests',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(
        '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
      );
      final ham = loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      );
      await d.editAndCompute(db, _fx, ham);
      await d.editAndCompute(db, _fx, r);
      final before = db.nutritionFor(r.id)!;
      expect((before.matchedCount, before.totalCount), (9, 9));
      expect(before.caloriesPerServing, closeTo(274.36, 0.005));
      expect(d.rowOf(db, r, 5).fdcId, 168277);
      v28.dropFood(path, 168322);
      final fault = v28.FoodFault(_fx, {168322}, scope: FailureScope.food);
      for (var p = 1; p <= 3; p++) {
        await matchAndCompute(db, fault, r);
      }
      final held = d.rowOf(db, r, 5);
      expect(
        (held.fdcId, held.hold, held.heldOn, held.grams),
        (168277, 'food_unavailable', 168322, null),
      );
      final n = db.nutritionFor(r.id)!;
      expect(n.matchedCount, 8);
      expect(n.caloriesPerServing, closeTo(78.12, 0.005));
      expect(held.derivedSeq, isNotNull);
      // The gain: 0118's compute caches 168322 (its search answer).
      await matchAndCompute(db, v29.Asks(_fx), ham);
      expect(knownFood(db, 168322), isNotNull);
      expect(d.rowOf(db, r, 5).derivedSeq, isNull);
      expect(nutritionIsFresh(db, r), isFalse);
      final none = _NoNet();
      await matchAndCompute(db, none, r);
      expect(none.calls, 0);
      final m = db.nutritionFor(r.id)!;
      expect((m.matchedCount, m.totalCount), (9, 9));
      expect(m.caloriesPerServing, closeTo(274.36, 0.005));
      expect(d.rowOf(db, r, 5).hold, isNull);
      expect(d.rowOf(db, r, 5).heldOn, isNull);
    },
  );

  // closer1 D3: the hold's `held_on` clears with the hold
  // (IngredientMatchRow.copyWith's clearHold arm, salt_database.dart) — the
  // same held 0040|5 skipped through the PUT: no hold, held_on NULL. STATED
  // synthesized (negative path) as above: the cache deletion and the fault.
  test('U5: the held 0040|5 skipped through the PUT — hold and held_on '
      'both clear', () async {
    final (db, path) = a.pathDb();
    final r = loadCorpusRecipe(
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    );
    await d.editAndCompute(
      db,
      _fx,
      loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      ),
    );
    await d.editAndCompute(db, _fx, r);
    v28.dropFood(path, 168322);
    final fault = v28.FoodFault(_fx, {168322}, scope: FailureScope.food);
    for (var p = 1; p <= 3; p++) {
      await matchAndCompute(db, fault, r);
    }
    final held = d.rowOf(db, r, 5);
    expect((held.hold, held.heldOn), ('food_unavailable', 168322));
    await applyMatchOverride(db, fault, r, 5, {
      'raw': held.raw,
      'skipped': true,
    });
    final row = d.rowOf(db, r, 5);
    expect((row.status, row.hold, row.heldOn), ('skipped', null, null));
  });

  test('U5: migration 022 — user_version 22, ingredient_matches.held_on '
      'present and NULL by default', () async {
    final (:db, :config) = _open();
    final r = await _compute(db, _fx, loadCorpusRecipe(_herb));
    final raw = sqlite3.open(config.dbPath);
    addTearDown(raw.dispose);
    expect(raw.select('PRAGMA user_version').first.columnAt(0), 22);
    expect(migrations.length, 22);
    expect(
      raw
          .select('PRAGMA table_info(ingredient_matches)')
          .map((c) => c['name'])
          .contains('held_on'),
      isTrue,
    );
    expect(
      raw.select(
        'SELECT COUNT(*) AS n FROM ingredient_matches WHERE recipe_id = ? '
        'AND held_on IS NOT NULL',
        [r.id],
      ).first['n'],
      0,
    );
  });
}

/// U6 (MED; S4): `_baconN`'s unbounded digit run made `_baconExtra`'s
/// `(N)\s+to\s+(N)` quadratic on a digit run in the UNWINDOWED step text —
/// 2.3 s per 10,000-character step, 281 s for the 120-step cap in one
/// engineOutcome pass over a recipe's oil line (extrapolated from 1 and 4
/// steps at base 63e4315). v103: `{1,12}` (no corpus text holds a run of
/// more than 4). The cap shape (STATED synthesized: the fleet's filler step
/// "Lift with a slotted spoon. " + 9,960 digits, ×120, over the real corpus
/// line "1 cup vegetable oil" on 0241's recipe and the fixtures' 2710180).
void u6() {
  test('U6 CAPS: one oil line, 120 × 9,987-character digit-run steps — one '
      'engineOutcome pass bounded, memo:baconKept once per index', () async {
    expect(capSteps, 120);
    final step = 'Lift with a slotted spoon. ${'1' * 9960}';
    expect(step.length, lessThanOrEqualTo(capStep));
    final r = capped(loadCorpusRecipe(pork), [
      '1 cup vegetable oil',
    ], List.filled(capSteps, step));
    final food = (await _fx.food(2710180))!;
    stepIndexCounts.clear();
    final sw = Stopwatch()..start();
    for (final line in nutritionLines(r)) {
      engineOutcome(
        r,
        line,
        food,
        resolveGrams(
          amounts: line.amounts,
          food: food,
          normalizedItem: normalizeItem(lineItemOf(line)),
          raw: line.raw,
        ),
        picked: true,
      );
    }
    final ms = sw.elapsedMilliseconds;
    final counts = Map.of(stepIndexCounts)..remove('names');
    expectBounded(r, counts, 'U6 caps');
    expect(counts['memo:baconKept'], 1);
    expect(ms, lessThan(backstopMs), reason: 'U6 caps: ${ms}ms');
    // ignore: avoid_print
    print('U6 caps engineOutcome ${ms}ms');
  });
}

/// U7 (MED; S5): `skinDiscarded` memoised per ITEM but rescanned every
/// skin sentence per distinct item, running `_skinPart`'s lazy gap on each
/// — 170.7 s for 400 distinct lines × 1,200 "skin skin … skin." sentences
/// (base 63e4315). v103: the sentence facts once per skin sentence
/// (`skinSentenceFacts`, `_skinFactsOf`); an item's scan reads the facts.
/// The cap shape (STATED synthesized: the fleet's filler sentence "skin ×
/// 198 skin." (995 characters), 10 a step, 120 steps; 400 distinct lines
/// "1 cup <token> vegetable oil" on 0241's recipe — the v27 cost files'
/// token form — every search answered with the recorded "vegetable oil"
/// answer ([_OneAnswer]) so each line reaches lineGrams' skin read).
void u7() {
  test('U7 CAPS: 400 distinct lines × 1,200 skin sentences — compute, GET '
      'and recompute bounded; skinSentenceFacts once per skin sentence per '
      'index', () async {
    final sentence = '${'skin ' * 198}skin.';
    expect(sentence.length, 995);
    final step = List.filled(10, sentence).join(' ');
    final r = capped(loadCorpusRecipe(pork), [
      for (var i = 0; i < capLines; i++) '1 cup ${tok(i)} vegetable oil',
    ], List.filled(capSteps, step));
    final oil = _OneAnswer('vegetable oil');
    final db = _db();
    _store(db, r);
    Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
    for (final (path, run) in <(String, Future<Object?> Function())>[
      ('compute', () => matchAndCompute(db, oil, stored())),
      ('GET', () => matchesBody(db, oil, stored())),
      ('recompute', () async => recomputeTotals(db, stored())),
    ]) {
      stepIndexCounts.clear();
      final sw = Stopwatch()..start();
      await run();
      final ms = sw.elapsedMilliseconds;
      final counts = Map.of(stepIndexCounts)..remove('names');
      expectBounded(
        stored(),
        counts,
        'U7 $path',
        copies: counts['indexes'] ?? 1,
      );
      // The exact counts (measured): the facts once per skin sentence (the
      // 1,200), the item scans once per distinct item (400) — on the paths
      // that weigh the lines; the recompute reads stored grams, no skin.
      if (path != 'recompute') {
        expect(counts['skinSentenceFacts'], 1200, reason: path);
        expect(counts['skinScans'], capLines, reason: path);
      } else {
        expect(counts['skinSentenceFacts'], isNull);
      }
      // ignore: avoid_print
      print('U7 $path ${ms}ms');
      expect(ms, lessThan(backstopMs), reason: 'U7 $path: ${ms}ms');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Every search answered with the fixtures' recorded answer for [query]
/// (STATED synthesized: the cap shapes' token lines have no recorded
/// answer of their own); details from the fixtures.
class _OneAnswer implements NutritionProvider {
  _OneAnswer(this.query);
  final String query;
  @override
  Future<List<FdcCandidate>> search(String q) => _fx.search(query);
  @override
  Future<FdcFood?> food(int fdcId) => _fx.food(fdcId);
}

/// The matches GET's `others` / `others_lines` per routed line the base
/// way — a fresh memo per line, the walk run per call, the handler's own
/// filter (another recipe, or an own row at another position: a GET over
/// an unchanged layout pairs each row to its own position) — U8's control.
Map<int, (int, int)> _othersFresh(SaltDatabase db, Recipe r) => {
  for (final row in db.ingredientMatchesFor(r.id))
    if (row.childRecipeId != null && row.hold == null)
      row.position: () {
        final reached = [
          for (final other in recipeReach(
            db,
            row.itemKey ?? '',
            childId: row.childRecipeId!,
            excluding: (recipeId: r.id, position: -1),
            memo: ResolverMemo(db),
          ))
            if (other.recipeId != r.id || other.position != row.position) other,
        ];
        return ({for (final o in reached) o.recipeId}.length, reached.length);
      }(),
};

/// U8 (MED; O3) and U10 (LOW; O4): the matches GET walked [recipeReach] per
/// routed line (an exclusion of position −1 that excludes nothing, the
/// walk's isDefaultRoute → resolveReference decoding the child per row)
/// and referenceChildJson decoded every library candidate per line. v103:
/// the walk memoised per (item key, child) in the request memo, the child
/// and the candidates read through [childRecipeOf]; `hostDecodes` counts
/// every whole-document decode. The cap shapes (STATED synthesized: the
/// repetition of a real corpus line; the 134-title note): 0977 Classic
/// Apple Pie re-lined with 400 × its real line 0 "1 recipe double-crust pie
/// dough" over the fixtures' four computed doughs (0972, 0973, 0974, 0976);
/// 0151 Buffalo Wings re-lined with 400 × "1 recipe chicken (see this
/// page)" and its prep note "See this page: " + every corpus title holding
/// "chicken".
void u8u10() {
  Future<SaltDatabase> doughs() async {
    final db = _db();
    for (final f in [
      '0972-basic-double-crust-pie-dough.yaml',
      '0973-all-butter-double-crust-pie-dough.yaml',
      '0974-foolproof-double-crust-pie-dough.yaml',
      '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml',
    ]) {
      await _compute(db, _fx, loadCorpusRecipe(f));
    }
    return db;
  }

  test('U8 CAPS: 400 × 0977|0 — the GET decodes each document once, its '
      "`others` equal the per-line walk's, within the backstop", () async {
    final db = await doughs();
    final real = loadCorpusRecipe('0977-classic-apple-pie.yaml');
    final line = nutritionLines(real)[0];
    expect(line.raw, '1 recipe double-crust pie dough');
    final r = real.copyWith(
      id: '${real.id}-u8',
      slug: '${real.slug}-u8',
      ingredients: [
        IngredientGroup(items: List.filled(capLines, line)),
      ],
    );
    final stored = await _compute(db, _NoNet(), r);
    final routed = db
        .ingredientMatchesFor(stored.id)
        .where((m) => m.childRecipeId != null)
        .length;
    expect(routed, capLines);
    final fresh = _othersFresh(db, stored);
    hostDecodes = 0;
    final sw = Stopwatch()..start();
    final body = await matchesBody(db, _NoNet(), stored);
    final ms = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('U8 GET ${ms}ms hostDecodes=$hostDecodes');
    final items = (body['items']! as List).cast<Map<String, Object?>>();
    expect({
      for (final i in items) i['position']: (i['others'], i['others_lines']),
    }, fresh);
    expect(hostDecodes, _u8Decodes);
    // A caller's exclusion filters the memoised walk (the apply's: its own
    // deciding line) — the same memo, so the walk is the memoised one.
    final memo = ResolverMemo(db);
    final row0 = _row(db, stored.id, 0);
    List<IngredientMatchRow> reach(int position) => recipeReach(
      db,
      row0.itemKey!,
      childId: row0.childRecipeId!,
      excluding: (recipeId: stored.id, position: position),
      memo: memo,
    );
    expect(reach(-1).map((m) => m.position), contains(0));
    expect(reach(0).map((m) => m.position), isNot(contains(0)));
    expect(reach(0), hasLength(reach(-1).length - 1));
    expect(ms, lessThan(backstopMs));
  }, timeout: const Timeout(Duration(minutes: 5)));

  // closer1 D2: the memo is keyed per (item key, CHILD) — one memo, two
  // children, two walks. 1006 Peach Tarte Tatin line 0 "1 recipe
  // single-crust pie dough, chilled" routes to 0975 (its note names that
  // one dough: not a flagged default), so a decision on 0975 reaches
  // nothing and one on 0973 reaches 1006|0 — either order on ONE memo.
  test('U8: the reach memo is keyed per child — 1006|0 on 0975 vs 0973, one '
      'memo, either order', () async {
    final db = await doughs();
    await _compute(
      db,
      _fx,
      loadCorpusRecipe(
        '0975-foolproof-all-butter-dough-for-single-crust-pie.yaml',
      ),
    );
    final tatin = await _compute(
      db,
      _fx,
      loadCorpusRecipe('1006-peach-tarte-tatin.yaml'),
    );
    final row = _row(db, tatin.id, 0);
    expect(row.raw, '1 recipe single-crust pie dough, chilled');
    const own =
        'atk-tv-2023-0975-foolproof-all-butter-dough-for-single-crust-pie';
    const other = 'atk-tv-2023-0973-all-butter-double-crust-pie-dough';
    expect((row.status, row.childRecipeId), ('auto', own));
    for (final order in [
      [own, other],
      [other, own],
    ]) {
      final memo = ResolverMemo(db);
      final reached = {
        for (final c in order)
          c: [
            for (final m in recipeReach(
              db,
              row.itemKey!,
              childId: c,
              excluding: (recipeId: '', position: -1),
              memo: memo,
            ))
              (m.recipeId, m.position),
          ],
      };
      expect(reached, {
        own: <(String, int)>[],
        other: [(tatin.id, 0)],
      }, reason: '$order');
    }
  });

  test('U10 CAPS: 0151 × 400 "1 recipe chicken (see this page)" naming every '
      'corpus chicken title — one decode per distinct candidate', () async {
    final db = _db();
    final titles = <String>[];
    final files = [
      for (final e in Directory(corpusRecipesDir).listSync())
        e.uri.pathSegments.last,
    ]..sort();
    for (final f in files) {
      final c = loadCorpusRecipe(f);
      if (c.title.toLowerCase().contains('chicken')) {
        _store(db, c);
        titles.add(c.title);
      }
    }
    final real = loadCorpusRecipe('0151-buffalo-wings.yaml');
    const raw = '1 recipe chicken (see this page)';
    final p = parseIngredientLine(raw);
    final ln = IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
    final r = real.copyWith(
      id: '${real.id}-u10',
      slug: '${real.slug}-u10',
      prepNotes: 'See this page: ${titles.join(', ')}.',
      ingredients: [
        IngredientGroup(items: List.filled(capLines, ln)),
      ],
    );
    final stored = await _compute(db, _NoNet(), r);
    hostDecodes = 0;
    final sw = Stopwatch()..start();
    await matchesBody(db, _NoNet(), stored);
    final ms = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('U10 GET ${ms}ms hostDecodes=$hostDecodes titles=${titles.length}');
    // Measured 135 (≤ the 136 named titles + the host): one per distinct
    // candidate document (base: ~53,600 — lines × named titles).
    expect(hostDecodes, lessThanOrEqualTo(titles.length + 1));
    expect(ms, lessThan(backstopMs));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// U8's measured decodes on the cap shape: the four doughs and the cap
/// recipe itself — each distinct document once (base: per line × row,
/// 164,406 counted by the fleet on snapshot 32's library).
const _u8Decodes = 5;

/// U14 (LOW; S2): a part-less skin-off sentence about another food ("Remove
/// the skin from the roasted peppers.") tripped every bird line of the
/// recipe. v103: its object after "from (the)" must name a bird or its part
/// (`_birdWords`); no "from" object trips as before. STATED synthesized
/// (user-entered recipe only, 0 corpus rows): 0148 Crispy Fried Chicken
/// with one step sentence appended. The corpus census (fix103/fix.md): of
/// the 40 corpus recipes where skinDiscarded fires, exactly 0272 (halibut
/// "steaks"), 0488 (poblanos) and 0706 (squash) stop — no poultry line
/// among them; 0002, 0637, Chicken Provençal, Barbecued Pulled Chicken and
/// 1098 unchanged.
void u14() {
  Future<IngredientMatchRow> line6(String sentence) async {
    final db = _db();
    final real = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
    final r = real.copyWith(
      steps: [
        ...real.steps,
        RecipeStep(number: real.steps.length + 1, text: sentence),
      ],
    );
    final stored = await _compute(db, _fx, r);
    final line = nutritionLines(stored)[6];
    expect(line.raw, contains('skin-on'));
    expect(
      skinDiscarded(stored, line),
      sentence.contains('chicken'),
      reason: sentence,
    );
    return _row(db, stored.id, 6);
  }

  test('U14: "…from the roasted peppers." trips nothing — line 6 stays on '
      '171447 at 1266.89 g; "…from the chicken." trips it', () async {
    final peppers = await line6('Remove the skin from the roasted peppers.');
    expect(peppers.fdcId, 171447);
    expect(peppers.grams, closeTo(1266.89, 0.01));
    final chicken = await line6('Remove the skin from the chicken.');
    expect(chicken.fdcId, isNot(171447));
  });

  // RE-PIN (an equality on the v40/v101 figure): 0637's real "peel skin off
  // chicken, leaving skin on wings" keeps its part.
  test('U14: 0637 keeps "wings"', () async {
    final db = _db();
    final r = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0637-grilled-lemon-chicken-with-rosemary.yaml'),
    );
    final bird = nutritionLines(r)[0];
    expect(skinDiscarded(r, bird), isTrue);
    expect(skinKeptPart(r, bird), 'wings');
  });
}

/// U15 (LOW; S7/O5): seven `ah102Parts` figures no pin held — read (Y13,
/// the record decides) when a person picks a meat-only (or a meat-and-skin)
/// record. Each through the REAL PUT ([applyMatchOverride]) on the real
/// corpus line, alone in its recipe (the v37 form: the row reads the line
/// and the record), the fixtures' records; the expected grams from
/// .claude/diag/2026-10-06/ah102_poultry.md (items 585, 590, 2592,
/// 2595–2597) × the line's printed pounds. STATED synthesized: the turkey
/// drumstick — no corpus line names turkey drumsticks alone; 0162's real
/// "4 pounds turkey drumsticks and thighs, trimmed" reads the leg (pinned
/// too), so its "and thighs, trimmed" is dropped.
void u15() {
  const lb = 453.592;
  for (final (file, raw, fdcId, grams) in [
    // Item 585 drumstick → meat 55 %.
    (
      '0630-grilled-spice-rubbed-chicken-drumsticks.yaml',
      '5 pounds chicken drumsticks',
      2646171,
      5 * lb * 0.55,
    ),
    // Item 590 wing → meat 31 %.
    (
      '0526-dakgangjeong-korean-fried-chicken-wings.yaml',
      '3 pounds chicken wings, cut at joints, wing tips discarded',
      2646171,
      3 * lb * 0.31,
    ),
    // Item 2592 carcass → meat 63 %, neck and giblets off 78 of 85; the
    // printed 12–14 lb at its midpoint.
    (
      '0154-classic-roast-turkey.yaml',
      '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
      174518,
      13 * lb * 78 / 85 * 0.63,
    ),
    // Item 2597 drumstick → meat and skin 69 % (171533, meat and skin),
    // meat 65 % (174518) — STATED synthesized line.
    (null, '4 pounds turkey drumsticks', 171533, 4 * lb * 0.69),
    (null, '4 pounds turkey drumsticks', 174518, 4 * lb * 0.65),
    // Item 2596 leg → meat 71 % ("drumsticks and thighs" is the leg).
    (
      '0162-slow-roasted-turkey-with-gravy.yaml',
      '4 pounds turkey drumsticks and thighs, trimmed',
      174518,
      4 * lb * 0.71,
    ),
    // Item 2595 leg quarter → meat 64 %; 4 × the printed 1½–2 lb midpoint.
    (
      '0163-turkey-and-gravy-for-a-crowd.yaml',
      '4 (1½- to 2-pound) turkey leg quarters, trimmed',
      174518,
      4 * 1.75 * lb * 0.64,
    ),
  ]) {
    test(
      'U15: "$raw" picked onto $fdcId → ${grams.toStringAsFixed(2)} g',
      () async {
        final IngredientLine line;
        if (file == null) {
          final p = parseIngredientLine(raw);
          line = IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
        } else {
          final real = loadCorpusRecipe(file);
          line = [
            for (final g in real.ingredients) ...g.items,
            for (final sub in real.subsections)
              for (final g in sub.ingredients ?? const <IngredientGroup>[])
                ...g.items,
          ].firstWhere((l) => l.raw == raw);
        }
        final db = _db();
        final r = Recipe(
          id: 'u15',
          title: 'u15',
          slug: 'u15',
          source: const RecipeSource(name: 'ATK', type: 'epub'),
          ingredients: [
            IngredientGroup(items: [line]),
          ],
        );
        db.upsertRecipe(r, sourceSlug: _source, contentHash: 'u15');
        await matchAndCompute(db, _NoNet(), r);
        await applyMatchOverride(db, _fx, r, 0, {'raw': raw, 'fdc_id': fdcId});
        final row = db.ingredientMatchesFor('u15').single;
        expect(row.fdcId, fdcId);
        expect(row.grams, closeTo(grams, 0.01));
      },
    );
  }
}

/// U16 (LOW; S6): v36 E4's kept-set guard's PARTS-arm copy
/// (`!kept.contains(row.position)` in `recomputeTotals`'s two-part branch)
/// was pinned by nothing. S6's probe as a test: 0040 computed after 0118
/// (168322 cached), 172345 (the bacon row's fat part) dropped + a FOOD
/// fault → the kept rendered-bacon row; the stamp a real hash (never
/// `unavailable:`), and a `computeUntilFresh` pass counts no failure.
/// STATED synthesized (negative path): the cache deletion and the fault.
void u16() {
  test(
    'U16: a kept two-part row whose part no cache holds — the stamp a '
    'real hash; a job pass runs once, its failure counted once (mutant: '
    "the parts arm's `!kept.contains` → `true` stamps `unavailable:`)",
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(
        '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
      );
      await d.editAndCompute(
        db,
        _fx,
        loadCorpusRecipe(
          '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
        ),
      );
      await d.editAndCompute(db, _fx, r);
      v28.dropFood(path, 172345);
      final fault = v28.FoodFault(_fx, {172345}, scope: FailureScope.food);
      await matchAndCompute(db, fault, r);
      final row = d.rowOf(db, r, 5);
      expect((row.status, row.fdcId), ('auto', 168277));
      expect(row.parts, contains('172345'));
      final stamp = db.nutritionFor(r.id)!.ingredientsHash;
      expect(stamp.startsWith('unavailable:'), isFalse, reason: stamp);
      final failures = <NutritionProviderException>[];
      final passes = await computeUntilFresh(
        db,
        fault,
        r,
        onFoodFailure: failures.add,
      );
      // The job's pass runs ONCE and counts its failure once: the stamp is
      // current, so no second pass asks (and counts) the same food again.
      expect((passes, failures.length), (1, 1));
    },
  );
}

/// [line] alone in its recipe (the v37 form), computed NoNet, then the REAL
/// PUT picks [fdcId] (the fixtures' detail); the stored row.
Future<IngredientMatchRow> _pick(IngredientLine line, int fdcId) async {
  final db = _db();
  final r = Recipe(
    id: 'pick',
    title: 'pick',
    slug: 'pick',
    source: const RecipeSource(name: 'ATK', type: 'epub'),
    ingredients: [
      IngredientGroup(items: [line]),
    ],
  );
  db.upsertRecipe(r, sourceSlug: _source, contentHash: 'pick');
  await matchAndCompute(db, _NoNet(), r);
  await applyMatchOverride(db, _fx, r, 0, {'raw': line.raw, 'fdc_id': fdcId});
  return db.ingredientMatchesFor('pick').single;
}

IngredientLine _typed(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

/// U17 (LOW; O6): eight span arms no pin held, each reaching no corpus row
/// (the fleet: all eight deleted together, the suite green, the replay
/// unmoved). One value pin per arm, each a STATED synthesized line or
/// sentence over a real recipe or record (corpus census: 0 lines reach the
/// arm — "with their liquid" in 0 files, every cardamom line plural, the
/// two "into a small bowl" bacon steps (0495, 0458) also "set aside").
void u17() {
  // _baconVeto's two arms: 0040's real bacon step with the pour-off's fat
  // kept "into a bowl" / "reserve remaining fat" (no "aside") — no rendering
  // lost: no parts; the real step splits the row.
  group('U17 _baconVeto', () {
    // `late`: a skipped group's body still runs at declaration time (the
    // loader), so a corpus read here must wait for the first test (CI has
    // no corpus; bdd0c5e).
    late final real = loadCorpusRecipe(
      '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
    );
    late final line = nutritionLines(real)[5];
    const pour =
        'Pour off all but 3 tablespoons of the bacon fat left in the pan.';
    late final row = IngredientMatchRow(
      recipeId: real.id,
      position: 5,
      raw: line.raw,
      fdcId: rawBaconFdcId,
      description: null,
      dataType: null,
      confidence: 0.9,
      grams: 283.5,
      gramSource: GramSource.weight.name,
      status: 'auto',
    );
    Recipe withPour(String text) => real.copyWith(
      steps: [
        for (final s in real.steps)
          s.text.contains(pour)
              ? s.copyWith(text: s.text.replaceFirst(pour, text))
              : s,
      ],
    );
    test('the real step splits the bacon (control)', () {
      expect(real.steps.any((s) => s.text.contains(pour)), isTrue);
      expect(withRenderedBacon(real, line, row).parts, isNotNull);
    });
    for (final text in [
      'Pour off all but 3 tablespoons of the bacon fat into a bowl.',
      'Pour off all but 3 tablespoons of the bacon fat and reserve remaining fat.',
    ]) {
      test('"$text" — the fat kept: no parts', () {
        expect(withRenderedBacon(withPour(text), line, row).parts, isNull);
      });
    }
  });

  // _setsOutTheCoat's "shallow dish": 0206's real "Place ¼ cup of the flour
  // in a pie plate." with "a shallow dish" for "a pie plate" — the same set
  // out coat (v33's pin: 53.16 g `discarded` `coating` on 789890).
  test(
    'U17 _setsOutTheCoat: "…flour in a shallow dish." sets the coat out',
    () async {
      final real = loadCorpusRecipe('0206-crunchy-baked-pork-chops.yaml');
      final recipe = real.copyWith(
        steps: [
          for (final s in real.steps)
            s.copyWith(
              text: s.text.replaceFirst(
                'Place ¼ cup of the flour in a pie plate.',
                'Place ¼ cup of the flour in a shallow dish.',
              ),
            ),
        ],
      );
      expect(
        recipe.steps.any((s) => s.text.contains('flour in a shallow dish')),
        isTrue,
      );
      final line = nutritionLines(recipe)[10];
      final flour = (await _fx.food(789890))!;
      final out = engineOutcome(
        recipe,
        line,
        flour,
        resolveGrams(
          amounts: line.amounts,
          food: flour,
          normalizedItem: normalizeItem(lineItemOf(line)),
        ),
      );
      expect(out.grams, closeTo(53.16, 0.01));
      expect((out.source, out.hold), ('discarded', 'coating'));
    },
  );

  // _skinKept's "lay … back": 0148 + "Remove the skin, then lay it back
  // over the meat." — the skin eaten, no trip (U14 pins the same sentence
  // without "lay … back" tripping).
  test('U17 _skinKept: "…lay it back over the meat." vetoes the trip', () {
    final real = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
    final r = real.copyWith(
      steps: [
        ...real.steps,
        RecipeStep(
          number: real.steps.length + 1,
          text: 'Remove the skin, then lay it back over the meat.',
        ),
      ],
    );
    expect(skinDiscarded(r, nutritionLines(r)[6]), isFalse);
  });

  // _keepsBeanLiquid's "with their liquid": the whole can on the drained
  // chickpea record; the real "1 (15-ounce) can chickpeas, rinsed" form
  // drained.
  test(
    'U17 _keepsBeanLiquid: "…, with their liquid" keeps the whole can',
    () async {
      expect(
        keepsWholeCan('1 (15-ounce) can chickpeas, with their liquid'),
        isTrue,
      );
      expect(keepsWholeCan('1 (15-ounce) can chickpeas, rinsed'), isFalse);
      final row = await _pick(
        _typed('1 (15-ounce) can chickpeas, with their liquid'),
        173801,
      );
      expect(row.grams, closeTo(15 * 28.3495, 0.01));
    },
  );

  // _scallionPartOf's _otherPartUsed veto: "white parts only" with the
  // green parts used too — the whole scallion (4 × 15 g), never × 0.37.
  test('U17 _otherPartUsed: "4 scallions, white parts only, minced; green '
      'parts sliced thin" counts the whole scallions', () async {
    final row = await _pick(
      _typed('4 scallions, white parts only, minced; green parts sliced thin'),
      2709794,
    );
    expect(row.grams, closeTo(60.0, 0.01));
  });

  // _srSizePieces' tomato "small" (SR 170457 small whole 91 g) and v31's
  // singular ('cardamom pod', 0.2).
  test('U17 "1 small tomato" → 91 g; "1 cardamom pod" → 0.2 g', () async {
    expect((await _pick(_typed('1 small tomato'), 170457)).grams, 91);
    expect(
      (await _pick(_typed('1 cardamom pod'), 170919)).grams,
      closeTo(0.2, 1e-9),
    );
  });
}
